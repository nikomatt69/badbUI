// Server centrale Badb: un'unica API per sito, app mobile, bot Discord e companion dell'addon.
import { Availability, Game, Schema, Tactics } from "@badb/core"
import { Hono } from "hono"
import { cors } from "hono/cors"
import { serveStatic } from "hono/bun"
import { streamSSE } from "hono/streaming"
import { z } from "zod"
import * as Addon from "./addon"
import * as Application from "./application"
import * as Auth from "./auth"
import * as Avail from "./availability"
import * as Boss from "./boss"
import * as Character from "./character"
import { Bus, Fail, check, type Config, type Ctx } from "./ctx"
import { open } from "./db"
import * as Guild from "./guild"
import * as Post from "./post"
import * as Raid from "./raid"

type Env = { Variables: { identity: Auth.Identity | undefined } }

/** Annuncio su Discord tramite webhook: senza menzioni, mai bloccante per la richiesta. */
function webhook(url: string) {
  return (text: string) => {
    if (!url) return
    fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ content: text.slice(0, 1800), allowed_mentions: { parse: [] } }),
      signal: AbortSignal.timeout(5000),
    }).catch(() => undefined)
  }
}

export function context(config: Config, overrides: Partial<Ctx> = {}): Ctx {
  return { db: open(config.db), config, bus: new Bus(), now: () => Date.now(), announce: webhook(config.webhook), ...overrides }
}

export function create(ctx: Ctx) {
  const app = new Hono<Env>()
  const attempts = Auth.limiter(12, 60_000)

  app.onError((error, c) => {
    if (error instanceof Fail) {
      const issues = (error as Fail & { issues?: Schema.ApiError["issues"] }).issues
      return c.json<Schema.ApiError>({ error: error.message, issues }, error.status)
    }
    if (error instanceof SyntaxError) return c.json<Schema.ApiError>({ error: "JSON non valido" }, 400)
    console.error(error)
    return c.json<Schema.ApiError>({ error: "Errore interno" }, 500)
  })

  // Niente cookie: l'accesso e' sempre un token nell'intestazione, quindi CORS aperto non espone sessioni.
  app.use(
    "*",
    cors({
      origin: (origin) => (ctx.config.origins.length === 0 || ctx.config.origins.includes(origin) ? origin : null),
      allowHeaders: ["authorization", "content-type", "x-discord-id"],
      allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE"],
      maxAge: 600,
    }),
  )

  app.use("*", async (c, next) => {
    c.header("x-content-type-options", "nosniff")
    c.header("referrer-policy", "same-origin")
    c.set("identity", Auth.identify(ctx, c.req.header("authorization"), c.req.header("x-discord-id")))
    await next()
  })

  const body = async <T extends z.ZodType>(c: { req: { json: () => Promise<unknown> } }, schema: T) =>
    check(schema, await c.req.json().catch(() => {
      throw new Fail(400, "JSON non valido")
    }))
  const who = (c: { get: (key: "identity") => Auth.Identity | undefined }, min?: Game.Rank) => Auth.must(c.get("identity"), min)
  const officer = (c: { get: (key: "identity") => Auth.Identity | undefined }) => !!c.get("identity") && Game.rankAtLeast(c.get("identity")!.user.rank, "officer")
  const throttle = (c: { req: { header: (name: string) => string | undefined } }, scope: string) =>
    attempts(`${scope}:${c.req.header("x-forwarded-for")?.split(",")[0]?.trim() ?? "local"}`, ctx.now())

  app.get("/health", (c) => c.json({ ok: true, name: "badb", version: "0.3.0" }))

  // Flusso eventi (SSE): i client ricaricano solo cio' che e' cambiato.
  app.get("/event", (c) =>
    streamSSE(c, async (stream) => {
      const queue: Schema.BusEvent[] = [{ type: "connected" }]
      const wake = { fn: () => {} }
      const off = ctx.bus.on((event) => {
        if (queue.length < 500) queue.push(event)
        wake.fn()
      })
      stream.onAbort(() => {
        off()
        wake.fn()
      })
      while (!stream.aborted) {
        const next = queue.shift()
        if (next) {
          await stream.writeSSE({ data: JSON.stringify(next) })
          continue
        }
        const timeout = new Promise<"ping">((resolve) => setTimeout(() => resolve("ping"), 25_000))
        const signal = new Promise<"event">((resolve) => (wake.fn = () => resolve("event")))
        if ((await Promise.race([timeout, signal])) === "ping") await stream.writeSSE({ event: "ping", data: "" })
      }
    }),
  )

  // ── Gilda ─────────────────────────────────────────────────────────────────────────────────────
  app.get("/home", (c) => c.json(Guild.home(ctx)))
  app.get("/guild", (c) => c.json(Guild.get(ctx)))
  app.put("/guild", async (c) => {
    who(c, "gm")
    return c.json(Guild.set(ctx, await body(c, Schema.GuildInput)))
  })

  // ── Account ───────────────────────────────────────────────────────────────────────────────────
  app.post("/auth/register", async (c) => {
    throttle(c, "register")
    return c.json(await Auth.register(ctx, await body(c, Schema.Credentials)))
  })
  app.post("/auth/login", async (c) => {
    throttle(c, "login")
    const input = await body(c, z.object({ name: z.string().max(60), password: z.string().max(200) }))
    return c.json(await Auth.login(ctx, input))
  })
  app.post("/auth/logout", (c) => {
    Auth.logout(ctx, who(c))
    return c.json({ ok: true })
  })
  app.get("/auth/me", (c) => {
    const user = who(c).user
    const mine = Application.mine(ctx, user.id)
    return c.json<Schema.Me>({ user, characters: Character.ofUser(ctx, user.id), application: mine ? Application.redact(mine) : null })
  })
  app.post("/auth/link", async (c) => {
    const input = await body(c, z.object({ kind: Schema.LinkKind }))
    return c.json(Auth.link(ctx, who(c).user.id, input.kind))
  })
  app.post("/auth/link/redeem", async (c) => {
    throttle(c, "redeem")
    return c.json(Auth.redeem(ctx, await body(c, Schema.LinkRedeem)))
  })
  app.post("/auth/discord", async (c) => {
    if (!Auth.isBot(ctx, c.req.header("authorization"))) throw new Fail(401, "Bot non autorizzato")
    throttle(c, "discord")
    return c.json(Auth.discord(ctx, await body(c, Schema.DiscordLink)))
  })
  app.delete("/auth/discord", (c) => {
    Auth.unlink(ctx, who(c).user.id)
    return c.json({ ok: true })
  })

  app.get("/member", (c) => {
    who(c, "officer")
    return c.json(Auth.list(ctx).map((user) => ({ ...user, characters: Character.ofUser(ctx, user.id) })))
  })
  app.patch("/member/:id", async (c) => {
    const actor = who(c, "officer").user
    const input = await body(c, Schema.RankPatch)
    return c.json(Auth.setRank(ctx, actor, c.req.param("id"), input.rank))
  })

  // ── Armory ────────────────────────────────────────────────────────────────────────────────────
  app.get("/character", (c) => c.json(Character.list(ctx)))
  app.get("/character/:name", (c) => {
    const found = Character.byName(ctx, c.req.param("name"))
    if (!found) throw new Fail(404, "Personaggio non trovato")
    return c.json(found)
  })
  app.post("/character", async (c) => c.json(Character.save(ctx, who(c).user, await body(c, Schema.CharacterInput))))
  app.patch("/character/:id", async (c) =>
    c.json(Character.patch(ctx, who(c).user, c.req.param("id"), await body(c, Schema.CharacterPatch))),
  )
  app.delete("/character/:id", (c) => {
    Character.remove(ctx, who(c).user, c.req.param("id"))
    return c.json({ ok: true })
  })

  // ── Candidature ───────────────────────────────────────────────────────────────────────────────
  app.get("/application", (c) => {
    who(c, "officer")
    return c.json(Application.list(ctx))
  })
  app.post("/application", async (c) => c.json(Application.submit(ctx, who(c).user, await body(c, Schema.ApplicationInput))))
  app.patch("/application/:id", async (c) => {
    who(c, "officer")
    return c.json(Application.review(ctx, await body(c, Schema.ApplicationReview), c.req.param("id")))
  })

  // ── Disponibilita' ────────────────────────────────────────────────────────────────────────────
  const thisWeek = () => Availability.currentWeek(new Date(ctx.now()), ctx.config.tz)
  app.get("/availability", (c) => {
    who(c, "member")
    return c.json(Avail.week(ctx, c.req.query("week") ?? thisWeek()))
  })
  app.put("/availability", async (c) => {
    const identity = who(c, "member")
    return c.json(Avail.set(ctx, identity.user, identity.source, await body(c, Schema.AvailabilityInput)))
  })
  app.post("/availability/text", async (c) => {
    const identity = who(c, "member")
    const input = await body(c, Schema.AvailabilityText)
    return c.json(Avail.text(ctx, identity.user, identity.source, input.text))
  })

  // ── Gruppi raid ───────────────────────────────────────────────────────────────────────────────
  app.get("/group", (c) => c.json(Raid.groups(ctx)))
  app.post("/group", async (c) => {
    who(c, "officer")
    return c.json(Raid.createGroup(ctx, await body(c, Schema.GroupInput)))
  })
  app.put("/group/:id", async (c) => {
    who(c, "officer")
    return c.json(Raid.updateGroup(ctx, c.req.param("id"), await body(c, Schema.GroupInput)))
  })
  app.delete("/group/:id", (c) => {
    who(c, "officer")
    Raid.removeGroup(ctx, c.req.param("id"))
    return c.json({ ok: true })
  })
  const leader = (c: Parameters<typeof who>[0], group: string | null) => {
    const identity = who(c, "member")
    if (!Raid.leads(ctx, identity.user, group)) throw new Fail(403, "Solo ufficiali e capo gruppo")
    return identity
  }
  app.put("/group/:id/member", async (c) => {
    leader(c, c.req.param("id"))
    return c.json(Raid.setMember(ctx, c.req.param("id"), await body(c, Schema.MemberInput)))
  })
  app.delete("/group/:id/member/:character", (c) => {
    leader(c, c.req.param("id"))
    return c.json(Raid.removeMember(ctx, c.req.param("id"), c.req.param("character")))
  })
  app.post("/group/:id/schedule", async (c) => {
    leader(c, c.req.param("id"))
    const input = await body(c, z.object({ week: Schema.DateSchema }))
    return c.json(Raid.schedule(ctx, c.req.param("id"), input.week))
  })

  // ── Eventi e prenotazioni ─────────────────────────────────────────────────────────────────────
  app.get("/raid/event", (c) => {
    const from = Number(c.req.query("from") ?? ctx.now() - 86_400_000)
    const to = Number(c.req.query("to") ?? from + 45 * 86_400_000)
    if (!Number.isFinite(from) || !Number.isFinite(to)) throw new Fail(400, "Intervallo non valido")
    return c.json(Raid.events(ctx, from, Math.min(to, from + 400 * 86_400_000)))
  })
  app.get("/raid/event/:id", (c) => c.json(Raid.event(ctx, c.req.param("id"))))
  app.get("/raid/event/:id/analysis", (c) => c.json(Raid.analysis(ctx, c.req.param("id"))))
  app.post("/raid/event", async (c) => {
    const input = await body(c, Schema.EventInput)
    leader(c, input.groupId)
    return c.json(Raid.createEvent(ctx, input))
  })
  app.patch("/raid/event/:id", async (c) => {
    const input = await body(c, Schema.EventPatch)
    const identity = leader(c, Raid.event(ctx, c.req.param("id")).groupId)
    // Spostare l'evento su un altro gruppo richiede di poter gestire anche quello.
    if (input.groupId !== undefined && !Raid.leads(ctx, identity.user, input.groupId)) throw new Fail(403, "Solo ufficiali e capo gruppo")
    return c.json(Raid.updateEvent(ctx, c.req.param("id"), input))
  })
  app.delete("/raid/event/:id", (c) => {
    leader(c, Raid.event(ctx, c.req.param("id")).groupId)
    Raid.removeEvent(ctx, c.req.param("id"))
    return c.json({ ok: true })
  })
  app.put("/raid/event/:id/signup", async (c) => {
    const identity = who(c, "member")
    return c.json(Raid.signup(ctx, identity.user, identity.source, c.req.param("id"), await body(c, Schema.SignupInput)))
  })
  app.put("/raid/event/:id/pick", async (c) => {
    leader(c, Raid.event(ctx, c.req.param("id")).groupId)
    return c.json(Raid.pick(ctx, c.req.param("id"), await body(c, Schema.PickInput)))
  })

  // ── Boss e tattiche ───────────────────────────────────────────────────────────────────────────
  app.get("/boss", (c) => c.json(Boss.list(ctx, c.req.query("raid"))))
  app.get("/boss/:id", (c) => c.json(Boss.get(ctx, c.req.param("id"))))
  app.post("/boss", async (c) => {
    who(c, "officer")
    return c.json(Boss.create(ctx, await body(c, Schema.BossInput)))
  })
  app.put("/boss/:id", async (c) => {
    who(c, "officer")
    return c.json(Boss.update(ctx, c.req.param("id"), await body(c, Schema.BossInput)))
  })
  app.delete("/boss/:id", (c) => {
    who(c, "officer")
    Boss.remove(ctx, c.req.param("id"))
    return c.json({ ok: true })
  })
  app.get("/tactics", (c) => c.json(Boss.capabilities(ctx)))
  app.put("/tactics", async (c) => {
    who(c, "officer")
    return c.json(Boss.setCapabilities(ctx, await body(c, Schema.MatrixPatch)))
  })
  app.post("/tactics/rank", async (c) => {
    const input = await body(c, z.object({ weights: Schema.WeightsSchema }))
    return c.json(Tactics.rank(Boss.matrix(ctx), Tactics.sanitize(input.weights)))
  })

  // ── Blog e guide ──────────────────────────────────────────────────────────────────────────────
  const kind = z.enum(["blog", "guide"])
  app.get("/post", (c) => c.json(Post.list(ctx, kind.optional().catch(undefined).parse(c.req.query("kind")), officer(c))))
  app.get("/post/:kind/:slug", (c) => c.json(Post.get(ctx, c.req.param("kind"), c.req.param("slug"), officer(c))))
  app.post("/post", async (c) => c.json(Post.create(ctx, who(c, "officer").user, await body(c, Schema.PostInput))))
  app.put("/post/:id", async (c) => {
    who(c, "officer")
    return c.json(Post.update(ctx, c.req.param("id"), await body(c, Schema.PostInput)))
  })
  app.delete("/post/:id", (c) => {
    who(c, "officer")
    Post.remove(ctx, c.req.param("id"))
    return c.json({ ok: true })
  })

  // ── Addon ─────────────────────────────────────────────────────────────────────────────────────
  app.post("/addon/sync", async (c) => c.json(Addon.sync(ctx, who(c).user, await body(c, Schema.AddonSync))))
  app.get("/addon/bundle", (c) => {
    const value = Addon.bundle(ctx, who(c).user)
    return c.json<Schema.SyncResult>({ bundle: value, lua: Addon.lua(value) })
  })

  // ── Sito compilato (facoltativo): stesso processo, stesso host ────────────────────────────────
  if (ctx.config.web) {
    app.use("*", serveStatic({ root: ctx.config.web }))
    app.get("*", serveStatic({ root: ctx.config.web, path: "index.html" }))
  }

  app.notFound((c) => c.json<Schema.ApiError>({ error: "Non trovato" }, 404))
  return app
}

export type App = ReturnType<typeof create>
