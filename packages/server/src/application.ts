// Candidature: il form "fatti gildare", con fasce raid preferite e orari.
import { Availability, Game, type Schema } from "@badb/core"
import type { z } from "zod"
import * as Avail from "./availability"
import * as Character from "./character"
import { Fail, id, json, touch, type Ctx } from "./ctx"

type Row = {
  id: string
  user_id: string | null
  account: string | null
  name: string
  cls: Game.ClassId
  spec: string | null
  role: Game.Role
  discord: string
  experience: string
  about: string
  slots: string
  ranges: string
  fee_paid: number
  status: Schema.Application["status"]
  note: string
  created: number
  reviewed: number | null
}

const SELECT = `SELECT application.*, user.name AS account FROM application LEFT JOIN user ON user.id = application.user_id`

function toApplication(row: Row): Schema.Application {
  return {
    id: row.id,
    userId: row.user_id,
    account: row.account,
    name: row.name,
    cls: row.cls,
    spec: row.spec,
    role: row.role,
    discord: row.discord,
    experience: row.experience,
    about: row.about,
    slots: json<Game.SlotId[]>(row.slots, []),
    ranges: json<Availability.Range[]>(row.ranges, []),
    feePaid: row.fee_paid === 1,
    status: row.status,
    note: row.note,
    created: row.created,
    reviewed: row.reviewed,
  }
}

export function list(ctx: Ctx) {
  return ctx.db
    .query<Row, []>(`${SELECT} ORDER BY application.status = 'pending' DESC, application.created DESC`)
    .all()
    .map(toApplication)
}

export function mine(ctx: Ctx, user: string) {
  const row = ctx.db.query<Row, [string]>(`${SELECT} WHERE application.user_id = ? ORDER BY application.created DESC`).get(user)
  return row ? toApplication(row) : null
}

/** Una candidatura aperta per account: reinviarla la aggiorna. La nota degli ufficiali non torna al candidato. */
export function submit(ctx: Ctx, user: Schema.User, input: z.infer<typeof Schema.ApplicationInput>) {
  if (Game.rankAtLeast(user.rank, "member")) throw new Fail(409, "Fai già parte della gilda")
  const spec = Game.findSpec(input.cls, input.spec)?.id ?? null
  const role = Game.resolveRole(input.cls, spec, input.role)
  const ranges = Availability.merge(input.ranges)
  const open = ctx.db.query<{ id: string }, [string]>("SELECT id FROM application WHERE user_id = ? AND status = 'pending'").get(user.id)
  const target = open?.id ?? id()
  const values = [input.name, input.cls, spec, role, input.discord, input.experience, input.about, JSON.stringify(input.slots), JSON.stringify(ranges)]
  if (open) {
    ctx.db.run(
      "UPDATE application SET name = ?, cls = ?, spec = ?, role = ?, discord = ?, experience = ?, about = ?, slots = ?, ranges = ? WHERE id = ?",
      [...values, target],
    )
  }
  if (!open) {
    ctx.db.run(
      `INSERT INTO application (name, cls, spec, role, discord, experience, about, slots, ranges, id, user_id, created)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [...values, target, user.id, ctx.now()],
    )
    ctx.announce(`📜 Nuova candidatura: **${input.name}** (${Game.classes[input.cls].label}, ${Game.roleLabel[role]})`)
  }
  touch(ctx, { type: "application", id: target })
  return redact(mine(ctx, user.id)!)
}

export function redact(application: Schema.Application): Schema.Application {
  return { ...application, note: "" }
}

/** Accettare una candidatura promuove l'account a membro, crea il personaggio e precompila la disponibilita'. */
export function review(ctx: Ctx, input: z.infer<typeof Schema.ApplicationReview>, application: string) {
  const row = ctx.db.query<Row, [string]>(`${SELECT} WHERE application.id = ?`).get(application)
  if (!row) throw new Fail(404, "Candidatura non trovata")
  const current = toApplication(row)
  ctx.db.transaction(() => {
    ctx.db.run("UPDATE application SET status = ?, fee_paid = ?, note = ?, reviewed = ? WHERE id = ?", [
      input.status ?? current.status,
      (input.feePaid ?? current.feePaid) ? 1 : 0,
      input.note ?? current.note,
      input.status && input.status !== current.status ? ctx.now() : current.reviewed,
      application,
    ])
    if (input.status !== "accepted" || current.status === "accepted" || !current.userId) return
    ctx.db.run("UPDATE user SET rank = 'member' WHERE id = ? AND rank = 'guest'", [current.userId])
    const taken = Character.byName(ctx, current.name)
    if (!taken || !taken.userId || taken.userId === current.userId) {
      const key = current.name.toLowerCase()
      const role = Game.resolveRole(current.cls, current.spec, current.role)
      ctx.db.run(
        `INSERT INTO character (id, user_id, name, name_key, cls, spec, role, main, updated, source)
         VALUES (?, ?, ?, ?, ?, ?, ?, NOT EXISTS (SELECT 1 FROM character WHERE user_id = ? AND main = 1), ?, 'site')
         ON CONFLICT(name_key) DO UPDATE SET user_id = excluded.user_id, spec = COALESCE(character.spec, excluded.spec), in_guild = 1`,
        [id(), current.userId, current.name, key, current.cls, current.spec, role, current.userId, ctx.now()],
      )
    }
    if (current.ranges.length > 0) {
      const week = Availability.currentWeek(new Date(ctx.now()), ctx.config.tz)
      Avail.write(ctx, current.userId, week, current.ranges, "site", "")
    }
  })()
  touch(ctx, { type: "application", id: application })
  if (input.status === "accepted" && current.status !== "accepted") touch(ctx, { type: "user", id: current.userId ?? undefined })
  return toApplication(ctx.db.query<Row, [string]>(`${SELECT} WHERE application.id = ?`).get(application)!)
}
