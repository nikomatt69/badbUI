// Account, sessioni e codici di collegamento (Discord, addon, app).
import { Game, type Schema } from "@badb/core"
import { createHash, timingSafeEqual } from "node:crypto"
import { Fail, id, touch, type Ctx } from "./ctx"
import { passwords } from "./password"

const DAY = 86_400_000
/** Durata delle sessioni per tipo di client. */
const ttl = { web: 30 * DAY, mobile: 180 * DAY, addon: 365 * DAY }
const LINK_TTL = 10 * 60_000

type Row = {
  id: string
  name: string
  password: string
  rank: Game.Rank
  discord_id: string | null
  discord_name: string | null
  created: number
}

export type Identity = { user: Schema.User; source: Schema.Source; session: string | null }

export function toUser(row: Row): Schema.User {
  return {
    id: row.id,
    name: row.name,
    rank: row.rank,
    discordId: row.discord_id,
    discordName: row.discord_name,
    created: row.created,
  }
}

function hash(token: string) {
  return createHash("sha256").update(token).digest("hex")
}

function secret(bytes: number) {
  return Buffer.from(crypto.getRandomValues(new Uint8Array(bytes))).toString("hex")
}

function equal(a: string, b: string) {
  const left = Buffer.from(hash(a))
  const right = Buffer.from(hash(b))
  return timingSafeEqual(left, right)
}

function issue(ctx: Ctx, user: string, kind: keyof typeof ttl, label = "") {
  const token = secret(32)
  ctx.db.run("INSERT INTO session (hash, user_id, kind, label, created, expires) VALUES (?, ?, ?, ?, ?, ?)", [
    hash(token),
    user,
    kind,
    label,
    ctx.now(),
    ctx.now() + ttl[kind],
  ])
  return token
}

export function byId(ctx: Ctx, user: string) {
  const row = ctx.db.query<Row, [string]>("SELECT * FROM user WHERE id = ?").get(user)
  return row ? toUser(row) : undefined
}

export async function register(ctx: Ctx, input: { name: string; password: string; setupKey?: string }) {
  if (!ctx.db.query("SELECT 1 FROM user").get() && (ctx.config.requireSetup || ctx.config.setupKey)) {
    if (!ctx.config.setupKey) throw new Fail(503, "Configurazione iniziale del server in corso")
    if (!equal(input.setupKey ?? "", ctx.config.setupKey))
      throw new Fail(403, "Per creare il primo capogilda serve il codice installazione")
  }
  const key = input.name.toLowerCase()
  if (ctx.db.query("SELECT 1 FROM user WHERE name_key = ?").get(key)) throw new Fail(409, "Nome già in uso")
  const password = await (ctx.passwords ?? passwords).hash(input.password)
  const user = id()
  // Il primo account diventa capogilda: e' chi installa il server. La scelta e' atomica nella INSERT.
  ctx.db.run(
    `INSERT INTO user (id, name, name_key, password, rank, created)
     VALUES (?, ?, ?, ?, CASE WHEN EXISTS (SELECT 1 FROM user) THEN 'guest' ELSE 'gm' END, ?)`,
    [user, input.name, key, password, ctx.now()],
  )
  touch(ctx, { type: "user", id: user })
  return { token: issue(ctx, user, "web"), user: byId(ctx, user)! }
}

// Hash usato quando l'account non esiste: il tempo di risposta resta lo stesso.
const decoys = new WeakMap<Ctx, Promise<string>>()
function decoy(ctx: Ctx) {
  if (!decoys.has(ctx)) decoys.set(ctx, (ctx.passwords ?? passwords).hash("badb-decoy-password"))
  return decoys.get(ctx)!
}

export async function login(ctx: Ctx, input: { name: string; password: string }) {
  const row = ctx.db.query<Row, [string]>("SELECT * FROM user WHERE name_key = ?").get(input.name.toLowerCase())
  const ok = await (ctx.passwords ?? passwords)
    .verify(input.password, row?.password ?? (await decoy(ctx)))
    .catch(() => false)
  if (!row || !ok) throw new Fail(401, "Nome o password errati")
  return { token: issue(ctx, row.id, "web"), user: toUser(row) }
}

export function logout(ctx: Ctx, identity: Identity) {
  if (identity.session) ctx.db.run("DELETE FROM session WHERE hash = ?", [identity.session])
}

/** Risolve l'intestazione Authorization: sessione utente oppure bot Discord che agisce per un utente. */
export function identify(ctx: Ctx, header: string | undefined, discord: string | undefined): Identity | undefined {
  if (!header) return undefined
  const [scheme, value] = header.split(" ")
  if (!value) return undefined
  if (scheme === "Bot") {
    if (!ctx.config.bot || !equal(value, ctx.config.bot)) throw new Fail(401, "Bot non autorizzato")
    if (!discord) return undefined
    const row = ctx.db.query<Row, [string]>("SELECT * FROM user WHERE discord_id = ?").get(discord)
    if (!row) throw new Fail(403, "Account Discord non collegato: usa /collega")
    return { user: toUser(row), source: "discord", session: null }
  }
  if (scheme !== "Bearer") return undefined
  const key = hash(value)
  const row = ctx.db
    .query<
      Row & { kind: string; expires: number },
      [string]
    >("SELECT user.*, session.kind, session.expires FROM session JOIN user ON user.id = session.user_id WHERE session.hash = ?")
    .get(key)
  if (!row) return undefined
  if (row.expires < ctx.now()) {
    ctx.db.run("DELETE FROM session WHERE hash = ?", [key])
    return undefined
  }
  const source = row.kind === "mobile" || row.kind === "addon" ? row.kind : "site"
  return { user: toUser(row), source, session: key }
}

export function isBot(ctx: Ctx, header: string | undefined) {
  const [scheme, value] = (header ?? "").split(" ")
  return scheme === "Bot" && !!value && !!ctx.config.bot && equal(value, ctx.config.bot)
}

/** Codice breve e leggibile (niente 0/O, 1/I) da digitare su Discord, nel companion o nell'app. */
export function link(ctx: Ctx, user: string, kind: "discord" | "addon" | "mobile") {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  const code = [...crypto.getRandomValues(new Uint8Array(8))].map((b) => alphabet[b % alphabet.length]).join("")
  ctx.db.run("DELETE FROM link WHERE user_id = ? AND kind = ?", [user, kind])
  ctx.db.run("DELETE FROM link WHERE expires < ?", [ctx.now()])
  ctx.db.run("INSERT INTO link (code, user_id, kind, expires) VALUES (?, ?, ?, ?)", [
    code,
    user,
    kind,
    ctx.now() + LINK_TTL,
  ])
  return { code, expires: ctx.now() + LINK_TTL }
}

function take(ctx: Ctx, code: string, kinds: string[]) {
  // DELETE ... RETURNING consuma il codice in un solo passo: non puo' essere riscattato due volte.
  const row = ctx.db
    .query<
      { user_id: string; kind: string; expires: number },
      [string]
    >("DELETE FROM link WHERE code = ? RETURNING user_id, kind, expires")
    .get(code.trim().toUpperCase())
  if (!row || row.expires < ctx.now() || !kinds.includes(row.kind)) throw new Fail(400, "Codice non valido o scaduto")
  return row
}

/** Il companion o l'app scambiano il codice con un token a lunga durata. */
export function redeem(ctx: Ctx, input: { code: string; label?: string }) {
  const row = take(ctx, input.code, ["addon", "mobile"])
  const kind = row.kind === "mobile" ? "mobile" : "addon"
  return { token: issue(ctx, row.user_id, kind, input.label ?? ""), user: byId(ctx, row.user_id)! }
}

export function discord(ctx: Ctx, input: { code: string; discordId: string; discordName?: string }) {
  const row = take(ctx, input.code, ["discord"])
  ctx.db.run("UPDATE user SET discord_id = NULL, discord_name = NULL WHERE discord_id = ?", [input.discordId])
  ctx.db.run("UPDATE user SET discord_id = ?, discord_name = ? WHERE id = ?", [
    input.discordId,
    input.discordName ?? null,
    row.user_id,
  ])
  touch(ctx, { type: "user", id: row.user_id })
  return byId(ctx, row.user_id)!
}

export function unlink(ctx: Ctx, user: string) {
  ctx.db.run("UPDATE user SET discord_id = NULL, discord_name = NULL WHERE id = ?", [user])
  touch(ctx, { type: "user", id: user })
}

export function list(ctx: Ctx) {
  return ctx.db.query<Row, []>("SELECT * FROM user ORDER BY name_key").all().map(toUser)
}

/** Cambio di grado: gli ufficiali gestiscono ospiti e membri, solo il capogilda nomina ufficiali. */
export function setRank(ctx: Ctx, actor: Schema.User, target: string, rank: Game.Rank) {
  const user = byId(ctx, target)
  if (!user) throw new Fail(404, "Utente non trovato")
  const high = (r: Game.Rank) => Game.rankAtLeast(r, "officer")
  if (actor.rank !== "gm" && (high(user.rank) || high(rank)))
    throw new Fail(403, "Solo il capogilda gestisce gli ufficiali")
  if (user.rank === "gm" && rank !== "gm") {
    const gms = ctx.db.query<{ n: number }, []>("SELECT COUNT(*) AS n FROM user WHERE rank = 'gm'").get()?.n ?? 0
    if (gms <= 1) throw new Fail(409, "Serve almeno un capogilda")
  }
  ctx.db.run("UPDATE user SET rank = ? WHERE id = ?", [rank, target])
  touch(ctx, { type: "user", id: target })
  return byId(ctx, target)!
}

export function must(identity: Identity | undefined, min: Game.Rank = "guest"): Identity {
  if (!identity) throw new Fail(401, "Accesso richiesto")
  if (!Game.rankAtLeast(identity.user.rank, min)) throw new Fail(403, "Permessi insufficienti")
  return identity
}

/** Limite di tentativi in memoria per IP: protegge login, registrazione e riscatto dei codici. */
export function limiter(max: number, window: number) {
  const hits = new Map<string, { count: number; reset: number }>()
  return (key: string, now: number) => {
    if (hits.size > 10_000) for (const [k, v] of hits) if (v.reset < now) hits.delete(k)
    const entry = hits.get(key)
    if (!entry || entry.reset < now) {
      hits.set(key, { count: 1, reset: now + window })
      return
    }
    entry.count++
    if (entry.count > max) throw new Fail(429, "Troppi tentativi, riprova tra poco")
  }
}
