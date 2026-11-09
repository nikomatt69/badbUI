// Disponibilita' settimanale: una riga per utente e settimana, intervalli in JSON.
import { Availability, type Game, type Schema } from "@badb/core"
import { Fail, json, touch, type Ctx } from "./ctx"

type Row = {
  user_id: string
  name: string
  cls: Game.ClassId | null
  ranges: string
  note: string
  source: Schema.Source
  updated: number
}

function toEntry(row: Row): Schema.Availability {
  const ranges = Availability.merge(json<Availability.Range[]>(row.ranges, []))
  return {
    userId: row.user_id,
    name: row.name,
    cls: row.cls,
    ranges,
    mask: Availability.mask(ranges),
    note: row.note,
    source: row.source,
    updated: row.updated,
  }
}

const SELECT = `
  SELECT availability.*, user.name AS name,
    (SELECT cls FROM character WHERE character.user_id = user.id ORDER BY main DESC, name_key LIMIT 1) AS cls
  FROM availability JOIN user ON user.id = availability.user_id`

export function week(ctx: Ctx, value: string): Schema.Week {
  if (!Availability.isDate(value)) throw new Fail(400, "Settimana non valida")
  const monday = Availability.weekOf(value)
  const people = ctx.db
    .query<Row, [string]>(`${SELECT} WHERE availability.week = ? AND user.rank != 'guest' ORDER BY user.name_key`)
    .all(monday)
    .map(toEntry)
    .filter((entry) => entry.ranges.length > 0)
  return { week: monday, people }
}

export function mine(ctx: Ctx, user: string, value: string) {
  const row = ctx.db
    .query<Row, [string, string]>(`${SELECT} WHERE availability.user_id = ? AND availability.week = ?`)
    .get(user, Availability.weekOf(value))
  return row ? toEntry(row) : undefined
}

export function write(ctx: Ctx, user: string, monday: string, ranges: Availability.Range[], source: Schema.Source, note: string | undefined) {
  ctx.db.run(
    `INSERT INTO availability (user_id, week, ranges, note, source, updated) VALUES (?1, ?2, ?3, COALESCE(?4, ''), ?5, ?6)
     ON CONFLICT(user_id, week) DO UPDATE SET ranges = excluded.ranges, source = excluded.source, updated = excluded.updated,
       note = CASE WHEN ?4 IS NULL THEN availability.note ELSE ?4 END`,
    [user, monday, JSON.stringify(Availability.merge(ranges)), note ?? null, source, ctx.now()],
  )
}

type Input = { week: string; ranges: Availability.Range[]; mode: "replace" | "add" | "remove"; note?: string }

export function set(ctx: Ctx, user: Schema.User, source: Schema.Source, input: Input) {
  if (!Availability.isDate(input.week)) throw new Fail(400, "Settimana non valida")
  const monday = Availability.weekOf(input.week)
  const current = mine(ctx, user.id, monday)?.ranges ?? []
  const next = (() => {
    if (input.mode === "add") return Availability.merge([...current, ...input.ranges])
    if (input.mode === "remove") return input.ranges.reduce(Availability.subtract, current)
    return Availability.merge(input.ranges)
  })()
  write(ctx, user.id, monday, next, source, input.note)
  touch(ctx, { type: "availability", id: user.id })
  return mine(ctx, user.id, monday)!
}

/** "ci sono giovedi' dalle 21 alle 23": usato dal bot Discord e dal campo rapido del sito. */
export function text(ctx: Ctx, user: Schema.User, source: Schema.Source, value: string) {
  const parsed = Availability.parse(value, new Date(ctx.now()), ctx.config.tz)
  if (!parsed.ok) throw new Fail(400, parsed.error)
  const entry = set(ctx, user, source, { week: parsed.week, ranges: parsed.ranges, mode: parsed.remove ? "remove" : "add" })
  return { entry, week: parsed.week, changed: parsed.ranges, removed: parsed.remove }
}
