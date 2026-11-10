// sdk-next 1.428.0 publishes JS without declarations. This subset follows its
// embedded README and generated HTTP API contract; all results are decoded.
declare module "@nikcli-ai/sdk-next" {
  import type { Effect } from "effect"
  export namespace NikCli {
    interface Client {
      provider: {
        list(): Promise<unknown>
        auth(): Promise<unknown>
        api(input: { providerID: string; key: string }): Promise<unknown>
        removeAuth(input: { providerID: string }): Promise<unknown>
        oauthAuthorize(input: { providerID: string; method: number }): Promise<unknown>
        oauthCallback(input: { providerID: string; method: number; code?: string }): Promise<unknown>
      }
      session: {
        create(input: {
          title: string
          permission: Array<{ permission: string; pattern: string; action: "allow" | "deny" }>
        }): Promise<unknown>
        messages(input: { sessionID: string; limit?: number }): Promise<unknown>
        abort(input: { sessionID: string }): Promise<unknown>
      }
      "session-prompt": {
        prompt(input: {
          sessionID: string
          agent: string
          system: string
          model: { providerID: string; modelID: string }
          variant?: string
          parts: Array<{ type: "text"; text: string }>
        }): Promise<unknown>
      }
      config: { get(): Promise<unknown>; update(input: { payload: Record<string, unknown> }): Promise<unknown> }
      experimental: { toolIDs(): Promise<unknown> }
    }
    function create(options: { directory: string }): Effect.Effect<Client, Error>
  }
}
