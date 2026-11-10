import { DurableObject } from "cloudflare:workers"
import { create } from "@badb/server/app"
import { Bus, config, type Ctx } from "@badb/server/ctx"
import { ensure } from "@badb/server/seed"
import { announce } from "@badb/server/notify"
import { storage } from "./storage"

export type Env = {
  GUILD: DurableObjectNamespace<GuildServer>
  ASSETS: Fetcher
  BADB_TZ?: string
  BADB_ORIGINS?: string
  BADB_BOT_SECRET?: string
  BADB_DISCORD_WEBHOOK?: string
  BADB_SETUP_KEY?: string
}

/** Una sola istanza nominata: sito, mobile, bot e companion vedono lo stesso database e bus. */
export class GuildServer extends DurableObject<Env> {
  private app!: ReturnType<typeof create>
  constructor(state: DurableObjectState, env: Env) {
    super(state, env)
    state.blockConcurrencyWhile(async () => {
      const settings = config({
        BADB_REQUIRE_SETUP: "1",
        BADB_DB: "durable-object",
        BADB_WEB: "",
        BADB_TZ: env.BADB_TZ,
        BADB_ORIGINS: env.BADB_ORIGINS,
        BADB_SETUP_KEY: env.BADB_SETUP_KEY,
        BADB_BOT_SECRET: env.BADB_BOT_SECRET,
        BADB_DISCORD_WEBHOOK: env.BADB_DISCORD_WEBHOOK,
      })
      const ctx: Ctx = {
        db: storage(state),
        config: settings,
        bus: new Bus(),
        now: () => Date.now(),
        announce: (text) => state.waitUntil(announce(settings.webhook, text)),
      }
      ensure(ctx)
      this.app = create(ctx)
    })
  }
  fetch(request: Request) {
    return this.app.fetch(request)
  }
}

const apiRoots = new Set([
  "health",
  "home",
  "guild",
  "auth",
  "member",
  "character",
  "application",
  "availability",
  "group",
  "raid",
  "boss",
  "tactics",
  "post",
  "addon",
  "event",
])
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    if (apiRoots.has(url.pathname.split("/")[1] ?? "")) {
      // Riscrive gli header controllabili dal client prima di inoltrare al server centrale.
      const headers = new Headers(request.headers)
      headers.delete("x-forwarded-for")
      const ip = request.headers.get("cf-connecting-ip")
      if (ip) headers.set("cf-connecting-ip", ip)
      return env.GUILD.getByName("badb-primary", { locationHint: "weur" }).fetch(new Request(request, { headers }))
    }
    if (request.method !== "GET" && request.method !== "HEAD")
      return Response.json({ error: "Non trovato" }, { status: 404 })
    const asset = await env.ASSETS.fetch(request)
    const headers = new Headers(asset.headers)
    if (asset.ok && url.pathname.startsWith("/downloads/")) {
      headers.set("cache-control", "public, max-age=0, must-revalidate")
      if (url.pathname.endsWith(".zip")) {
        headers.set("content-type", "application/zip")
        headers.set("content-disposition", `attachment; filename="${url.pathname.split("/").pop()}"`)
      }
    }
    headers.set("x-content-type-options", "nosniff")
    headers.set("referrer-policy", "same-origin")
    headers.set(
      "content-security-policy",
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
    )
    return new Response(asset.body, { status: asset.status, statusText: asset.statusText, headers })
  },
} satisfies ExportedHandler<Env>
