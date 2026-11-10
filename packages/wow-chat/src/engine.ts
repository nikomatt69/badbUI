import { Effect } from "effect"
import { z } from "zod"
import { mkdir, chmod } from "node:fs/promises"
import { join } from "node:path"
import { SYSTEM, prompt, publicConfig, type Bundle, type ChatRequest, type Receipt } from "./protocol"

// One host, no CLI subprocess and no listening HTTP server. Lazy loading keeps
// provider credentials and the SDK's initialization out of protocol-only tests.
export async function createEngine(directory: string) {
  await mkdir(directory, { recursive: true, mode: 0o700 })
  // nikcli 1.428 gates websearch for third-party models behind this flag,
  // including when websearch.provider is Parallel or a custom MCP endpoint.
  process.env.NIKCLI_ENABLE_EXA = "1"
  const { NikCli } = await import("@nikcli-ai/sdk-next")
  const client = await Effect.runPromise(NikCli.create({ directory }))
  const permissions = { "*": "deny", websearch: "allow", webfetch: "allow" }
  const guard = {
    share: "disabled",
    snapshot: false,
    agent: {
      "wow-assistant": {
        description: "In-game WoW quest assistant",
        mode: "primary",
        prompt: SYSTEM,
        steps: 8,
        permission: permissions,
      },
    },
  }
  await client.config.update({ payload: guard })
  const ids = z.array(z.string()).parse(await client.experimental.toolIDs())
  if (!ids.includes("websearch"))
    throw new Error("nikcli's websearch tool is unavailable. Enable a web search backend in nikcli.")
  const timeout = <T>(operation: Promise<T>, ms = 120000) => {
    let timer: ReturnType<typeof setTimeout>
    return Promise.race([
      operation,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("AI request timed out. Retry from chat.")), ms)
      }),
    ]).finally(() => clearTimeout(timer))
  }
  async function catalog(): Promise<Pick<Bundle, "providers" | "auth" | "configJSON">> {
    const [raw, auth, config] = await Promise.all([client.provider.list(), client.provider.auth(), client.config.get()])
    const data = z
      .object({
        all: z.array(
          z.object({
            id: z.string(),
            name: z.string(),
            models: z.record(
              z.string(),
              z.object({ id: z.string(), name: z.string(), variants: z.record(z.string(), z.unknown()).optional() }),
            ),
          }),
        ),
        connected: z.array(z.string()),
      })
      .parse(raw)
    return {
      providers: data.all.map((p) => ({
        id: p.id,
        name: p.name,
        connected: data.connected.includes(p.id),
        models: Object.values(p.models).map((m) => ({
          id: m.id,
          name: m.name,
          variants: Object.keys(m.variants ?? {}),
        })),
      })),
      auth: z.record(z.string(), z.array(z.object({ type: z.enum(["oauth", "api"]), label: z.string() }))).parse(auth),
      configJSON: JSON.stringify(publicConfig(config), null, 2),
    }
  }
  async function execute(
    request: ChatRequest,
    previous: Receipt[],
  ): Promise<Pick<Receipt, "text" | "sources" | "session">> {
    switch (request.kind) {
      case "catalog":
        return { text: "Provider and model catalog refreshed.", sources: [] }
      case "configure": {
        const config = z.record(z.string(), z.unknown()).parse(JSON.parse(request.payload.json))
        // The player can configure nikcli; the game assistant still has research-only tools.
        await client.config.update({ payload: config })
        await client.config.update({ payload: guard })
        await chmod(join(directory, "nikcli.json"), 0o600).catch(() => undefined)
        return { text: "nikcli settings saved. Provider/model selections are in the top bar.", sources: [] }
      }
      case "api-key":
        await client.provider.api({ providerID: request.payload.provider, key: request.payload.key })
        return {
          text: `Provider connected: ${request.payload.provider}. Reload once more to clear the credential from the addon's pending queue. Local .bak files may retain it.`,
          sources: [],
        }
      case "disconnect":
        await client.provider.removeAuth({ providerID: request.payload.provider })
        return { text: `Provider disconnected: ${request.payload.provider}.`, sources: [] }
      case "oauth-start": {
        const login = z
          .object({ url: z.string().url(), instructions: z.string(), method: z.string() })
          .nullable()
          .parse(
            await client.provider.oauthAuthorize({
              providerID: request.payload.provider,
              method: request.payload.method,
            }),
          )
        if (!login) throw new Error("This provider does not offer that OAuth method.")
        return {
          text: `Open this provider login URL in your browser:\n${login.url}\n${login.instructions}\nThen use Complete login in Chatbot settings. Keep the local runtime running during sign-in.`,
          sources: [],
        }
      }
      case "oauth-finish":
        await timeout(
          client.provider.oauthCallback({
            providerID: request.payload.provider,
            method: request.payload.method,
            code: request.payload.code || undefined,
          }),
        )
        return { text: "Provider login completed.", sources: [] }
      case "ask": {
        const input = prompt(request)
        // A separate SDK session for each character and conversation generation.
        let session = previous.findLast(
          (r) => r.character === request.character && r.generation === request.generation && r.session,
        )?.session
        if (!session)
          session = z.object({ id: z.string() }).parse(
            await client.session.create({
              title: `WoW · ${request.character}`,
              permission: Object.entries(permissions).map(([permission, action]) => ({
                permission,
                pattern: "*",
                action: action === "allow" ? "allow" : "deny",
              })),
            }),
          ).id
        const sessionID = session
        const response = await timeout(
          client["session-prompt"].prompt({
            sessionID,
            agent: "wow-assistant",
            system: SYSTEM,
            model: { providerID: request.payload.provider, modelID: request.payload.model },
            variant: request.payload.variant || undefined,
            parts: [{ type: "text", text: input }],
          }),
        ).catch(async (error: unknown) => {
          await client.session.abort({ sessionID }).catch(() => undefined)
          throw error
        })
        const parsed = z
          .object({
            info: z.object({ error: z.unknown().optional() }),
            parts: z.array(z.object({ type: z.string(), text: z.string().optional() }).passthrough()),
          })
          .parse(response)
        if (parsed.info.error)
          throw new Error(
            "The model provider could not finish this request. Check provider credentials, quota and model availability.",
          )
        let text = parsed.parts
          .filter((p) => p.type === "text")
          .map((p) => p.text ?? "")
          .join("\n")
          .trim()
        if (!text) throw new Error("The model returned no answer. Choose another model or retry.")
        // Only tool calls in this turn count as evidence; never reuse old citations.
        const withRoles = z
          .array(
            z.object({
              info: z.object({ role: z.string() }),
              parts: z.array(
                z.object({
                  type: z.string(),
                  tool: z.string().optional(),
                  state: z.object({ status: z.string(), output: z.string().optional() }).optional(),
                }),
              ),
            }),
          )
          .parse(await client.session.messages({ sessionID, limit: 30 }))
        const start = withRoles.findLastIndex((m) => m.info.role === "user")
        const tools = withRoles
          .slice(start + 1)
          .flatMap((m) => m.parts)
          .filter(
            (p) =>
              p.type === "tool" && p.state?.status === "completed" && ["websearch", "webfetch"].includes(p.tool ?? ""),
          )
        const sources = [
          ...new Set(tools.flatMap((p) => p.state?.output?.match(/https?:\/\/[^\s<>"\])]+/g) ?? [])),
        ].slice(0, 30)
        if (!tools.some((p) => p.tool === "websearch"))
          text = "Web research was not completed for this reply. Treat quest facts as unverified.\n\n" + text
        return { text: text.slice(0, 24000), sources, session }
      }
    }
  }
  return { catalog, execute, client }
}
