// Real embedded SDK + local synthetic provider/search service. No real account,
// paid model, or live character data is used by this integration check.
import { mkdtemp, rm } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { z } from "zod"
import { request } from "./fixtures"
import { createEngine } from "../src/engine"

const directory = await mkdtemp(join(tmpdir(), "badb-sdk-live-"))
const testHome = await mkdtemp(join(tmpdir(), "badb-sdk-home-"))
process.env.NIKCLI_TEST_HOME = testHome
process.env.NIKCLI_DISABLE_DEFAULT_PLUGINS = "1"
process.env.NIKCLI_DISABLE_EXTERNAL_SKILLS = "1"
process.env.NIKCLI_DISABLE_MODELS_FETCH = "1"
process.env.BUN_TMPDIR = tmpdir()
const deadline = setTimeout(() => {
  console.error("Embedded integration test timed out")
  process.exit(1)
}, 60000)
let searches = 0,
  sawContext = false
const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 0,
  async fetch(req) {
    const url = new URL(req.url)
    if (url.pathname === "/search") {
      searches++
      return Response.json({
        jsonrpc: "2.0",
        id: 1,
        result: {
          content: [
            {
              type: "text",
              text: "Title: The People's Militia\nURL: https://www.wowhead.com/classic/quest=12\nText: Fixture quest reference.",
            },
          ],
          structuredContent: {
            results: [
              {
                url: "https://www.wowhead.com/classic/quest=12",
                title: "The People's Militia",
                content: "Fixture quest reference.",
              },
            ],
          },
        },
      })
    }
    const body = z
      .object({
        messages: z.array(z.object({ role: z.string() }).passthrough()),
        tools: z.array(z.object({ function: z.object({ name: z.string() }) })).optional(),
      })
      .parse(await req.json())
    if (body.tools?.some((t) => ["bash", "read", "write", "task", "edit"].includes(t.function.name)))
      throw new Error("Non-research tools exposed to the WoW agent")
    sawContext ||=
      JSON.stringify(body.messages).includes("Westfall") && JSON.stringify(body.messages).includes("Defias: 2/10")
    const toolResult = body.messages.some((m) => m.role === "tool")
    const search = body.tools?.some((t) => t.function.name === "websearch") && !toolResult
    const delta = search
      ? {
          tool_calls: [
            {
              index: 0,
              id: "call_fixture_search",
              type: "function",
              function: {
                name: "websearch",
                arguments: JSON.stringify({
                  query: "site:wowhead.com/classic quest 12 People's Militia",
                  numResults: 1,
                }),
              },
            },
          ],
        }
      : {
          content:
            "At level 23 in Westfall, focus on your selected quest. [Quest reference](https://www.wowhead.com/classic/quest=12).",
        }
    const chunks = [
      {
        id: "fixture",
        object: "chat.completion.chunk",
        created: 1,
        model: "quest-model",
        choices: [{ index: 0, delta: { role: "assistant" }, finish_reason: null }],
      },
      {
        id: "fixture",
        object: "chat.completion.chunk",
        created: 1,
        model: "quest-model",
        choices: [{ index: 0, delta, finish_reason: null }],
      },
      {
        id: "fixture",
        object: "chat.completion.chunk",
        created: 1,
        model: "quest-model",
        choices: [{ index: 0, delta: {}, finish_reason: search ? "tool_calls" : "stop" }],
        usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 },
      },
    ]
    return new Response(chunks.map((c) => `data: ${JSON.stringify(c)}\n\n`).join("") + "data: [DONE]\n\n", {
      headers: { "Content-Type": "text/event-stream" },
    })
  },
})
try {
  const engine = await createEngine(directory)
  await engine.client.config.update({
    payload: {
      provider: {
        fixture: {
          name: "Fixture",
          npm: "@ai-sdk/openai-compatible",
          options: { baseURL: `${server.url}v1`, apiKey: "fixture-not-a-secret" },
          models: {
            "quest-model": { name: "Quest fixture", tool_call: true, limit: { context: 32000, output: 4000 } },
          },
        },
      },
      model: "fixture/quest-model",
      small_model: "fixture/quest-model",
      websearch: { provider: "mcp", url: `${server.url}search` },
    },
  })
  const catalog = await engine.catalog()
  if (!catalog.providers.some((p) => p.id === "fixture" && p.models.some((m) => m.id === "quest-model")))
    throw new Error("Fixture provider/model missing")
  const r = request()
  r.payload.provider = "fixture"
  r.payload.model = "quest-model"
  const answer = await engine.execute(r, [])
  if (
    !answer.text.includes("Westfall") ||
    answer.text.includes("unverified") ||
    searches !== 1 ||
    !sawContext ||
    !answer.sources.some((u) => u.includes("wowhead.com/classic/quest=12"))
  )
    throw new Error(`Embedded workflow failed: ${JSON.stringify({ answer, searches, sawContext })}`)
  console.log("EMBEDDED_WOW_CHAT_OK")
} finally {
  server.stop(true)
  await rm(directory, { recursive: true, force: true })
  await rm(testHome, { recursive: true, force: true })
  clearTimeout(deadline)
}
process.exit(0)
