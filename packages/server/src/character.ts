// Personaggi e armory. I dati di equipaggiamento arrivano dall'addon (via companion).
import { Game, type Schema } from "@badb/core"
import { Fail, id, json, touch, type Ctx } from "./ctx"

export type Row = {
  id: string
  user_id: string | null
  owner: string | null
  name: string
  realm: string
  cls: Game.ClassId
  spec: string | null
  role: Game.Role
  level: number
  race: string | null
  guild_rank: string | null
  main: number
  item_level: number | null
  gear: string
  professions: string
  updated: number
  source: "site" | "addon"
}

const SELECT = `SELECT character.*, user.name AS owner FROM character LEFT JOIN user ON user.id = character.user_id`

export function toCharacter(row: Row): Schema.Character {
  return {
    id: row.id,
    userId: row.user_id,
    owner: row.owner,
    name: row.name,
    realm: row.realm,
    cls: row.cls,
    spec: row.spec,
    role: row.role,
    level: row.level,
    race: row.race,
    guildRank: row.guild_rank,
    main: row.main === 1,
    itemLevel: row.item_level,
    gear: json<Schema.GearItem[]>(row.gear, []),
    professions: json<Schema.Profession[]>(row.professions, []),
    updated: row.updated,
    source: row.source,
  }
}

export function list(ctx: Ctx) {
  return ctx.db
    .query<Row, []>(`${SELECT} WHERE character.in_guild = 1 ORDER BY character.name_key`)
    .all()
    .map(toCharacter)
}

export function ofUser(ctx: Ctx, user: string) {
  return ctx.db
    .query<Row, [string]>(`${SELECT} WHERE character.user_id = ? ORDER BY character.main DESC, character.name_key`)
    .all(user)
    .map(toCharacter)
}

export function get(ctx: Ctx, character: string) {
  const row = ctx.db.query<Row, [string]>(`${SELECT} WHERE character.id = ?`).get(character)
  return row ? toCharacter(row) : undefined
}

export function byName(ctx: Ctx, name: string) {
  const row = ctx.db.query<Row, [string]>(`${SELECT} WHERE character.name_key = ?`).get(name.toLowerCase())
  return row ? toCharacter(row) : undefined
}

/** Il personaggio con cui un utente si prenota se non ne indica uno: il main, altrimenti il primo. */
export function main(ctx: Ctx, user: string) {
  return ofUser(ctx, user)[0]
}

function spec(cls: Game.ClassId, value: string | null | undefined) {
  return Game.findSpec(cls, value)?.id ?? null
}

function setMain(ctx: Ctx, user: string, character: string) {
  ctx.db.run("UPDATE character SET main = CASE WHEN id = ? THEN 1 ELSE 0 END WHERE user_id = ?", [character, user])
}

type Input = {
  name: string
  realm: string
  cls: Game.ClassId
  spec: string | null
  role?: Game.Role
  level: number
  race: string | null
  main: boolean
}

/** Crea un personaggio o reclama quello importato dal roster di gioco (ancora senza proprietario). */
export function save(ctx: Ctx, user: Schema.User, input: Input) {
  const existing = byName(ctx, input.name)
  if (existing?.userId && existing.userId !== user.id) throw new Fail(409, "Personaggio già collegato a un altro account")
  const fixed = spec(input.cls, input.spec)
  const role = Game.resolveRole(input.cls, fixed, input.role)
  const target = existing?.id ?? id()
  if (existing) {
    ctx.db.run(
      "UPDATE character SET user_id = ?, realm = ?, cls = ?, spec = ?, role = ?, level = ?, race = ?, in_guild = 1, updated = ? WHERE id = ?",
      [user.id, input.realm, input.cls, fixed, role, input.level, input.race, ctx.now(), target],
    )
  }
  if (!existing) {
    ctx.db.run(
      `INSERT INTO character (id, user_id, name, name_key, realm, cls, spec, role, level, race, updated, source)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'site')`,
      [target, user.id, input.name, input.name.toLowerCase(), input.realm, input.cls, fixed, role, input.level, input.race, ctx.now()],
    )
  }
  const first = ofUser(ctx, user.id).length === 1
  if (input.main || first) setMain(ctx, user.id, target)
  touch(ctx, { type: "character", id: target })
  return get(ctx, target)!
}

export function owned(ctx: Ctx, user: Schema.User, character: string) {
  const found = get(ctx, character)
  if (!found) throw new Fail(404, "Personaggio non trovato")
  if (found.userId !== user.id && !Game.rankAtLeast(user.rank, "officer")) throw new Fail(403, "Non è un tuo personaggio")
  return found
}

export function patch(ctx: Ctx, user: Schema.User, character: string, input: Partial<Input>) {
  const found = owned(ctx, user, character)
  const cls = input.cls ?? found.cls
  const fixed = spec(cls, input.spec === undefined ? found.spec : input.spec)
  const role = Game.resolveRole(cls, fixed, input.role ?? found.role)
  ctx.db.run("UPDATE character SET realm = ?, cls = ?, spec = ?, role = ?, level = ?, race = ?, updated = ? WHERE id = ?", [
    input.realm ?? found.realm,
    cls,
    fixed,
    role,
    input.level ?? found.level,
    input.race === undefined ? found.race : input.race,
    ctx.now(),
    character,
  ])
  if (input.main && found.userId) setMain(ctx, found.userId, character)
  touch(ctx, { type: "character", id: character })
  return get(ctx, character)!
}

/** Toglie il personaggio dall'account. Se arriva dal roster di gioco resta nell'armory, senza proprietario. */
export function remove(ctx: Ctx, user: Schema.User, character: string) {
  const found = owned(ctx, user, character)
  if (found.source === "addon" && found.guildRank) {
    ctx.db.run("UPDATE character SET user_id = NULL, main = 0 WHERE id = ?", [character])
  }
  if (!(found.source === "addon" && found.guildRank)) ctx.db.run("DELETE FROM character WHERE id = ?", [character])
  touch(ctx, { type: "character", id: character })
}

/** Scheda completa letta dall'addon sul personaggio del giocatore: lo collega al suo account. */
export function scan(ctx: Ctx, user: Schema.User, input: Schema.AddonCharacter) {
  const existing = byName(ctx, input.name)
  if (existing?.userId && existing.userId !== user.id) return { ok: false as const, error: `${input.name}: collegato a un altro account` }
  const fixed = spec(input.cls, input.spec)
  const role = Game.resolveRole(input.cls, fixed, input.role ?? existing?.role)
  const target = existing?.id ?? id()
  const values = [
    user.id,
    input.realm,
    input.cls,
    fixed,
    role,
    input.level,
    input.race,
    input.guildRank,
    input.itemLevel,
    JSON.stringify(input.gear),
    JSON.stringify(input.professions),
    ctx.now(),
  ]
  if (existing) {
    ctx.db.run(
      `UPDATE character SET user_id = ?, realm = ?, cls = ?, spec = ?, role = ?, level = ?, race = ?, guild_rank = COALESCE(?, guild_rank),
       item_level = ?, gear = ?, professions = ?, updated = ?, source = 'addon', in_guild = 1 WHERE id = ?`,
      [...values, target],
    )
  }
  if (!existing) {
    ctx.db.run(
      `INSERT INTO character (user_id, realm, cls, spec, role, level, race, guild_rank, item_level, gear, professions, updated, source, id, name, name_key)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'addon', ?, ?, ?)`,
      [...values, target, input.name, input.name.toLowerCase()],
    )
  }
  if (ofUser(ctx, user.id).every((c) => !c.main)) setMain(ctx, user.id, target)
  return { ok: true as const, id: target }
}

/** Roster di gilda visto in gioco da un ufficiale: crea chi manca, aggiorna grado e livello, segna chi e' uscito. */
export function roster(ctx: Ctx, entries: Schema.AddonSync["roster"]) {
  const seen = new Set(entries.map((e) => e.name.toLowerCase()))
  ctx.db.transaction(() => {
    for (const entry of entries) {
      const key = entry.name.toLowerCase()
      const found = ctx.db.query<{ id: string; cls: string }, [string]>("SELECT id, cls FROM character WHERE name_key = ?").get(key)
      if (found) {
        ctx.db.run("UPDATE character SET level = ?, guild_rank = ?, in_guild = 1 WHERE id = ?", [entry.level, entry.guildRank, found.id])
        continue
      }
      ctx.db.run(
        `INSERT INTO character (id, name, name_key, cls, role, level, guild_rank, updated, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'addon')`,
        [id(), entry.name, key, entry.cls, Game.resolveRole(entry.cls, null), entry.level, entry.guildRank, ctx.now()],
      )
    }
    const all = ctx.db.query<{ id: string; name_key: string }, []>("SELECT id, name_key FROM character WHERE in_guild = 1 AND guild_rank IS NOT NULL").all()
    for (const row of all) if (!seen.has(row.name_key)) ctx.db.run("UPDATE character SET in_guild = 0 WHERE id = ?", [row.id])
  })()
}
