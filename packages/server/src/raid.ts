// Gruppi raid (mattina, pomeriggio, sera), eventi a calendario e prenotazioni.
import { Availability, Game, Tactics, type Schema } from "@badb/core"
import type { z } from "zod"
import * as Boss from "./boss"
import * as Character from "./character"
import { Fail, id, json, touch, type Ctx } from "./ctx"

type Comp = Record<Game.Role, number>

function comp(raid: string, value?: Comp | null): Comp {
  return value ?? Game.findRaid(raid)?.comp ?? { tank: 2, healer: 3, dps: 5 }
}

function checkRaid(raid: string) {
  if (!Game.findRaid(raid)) throw new Fail(400, "Raid sconosciuto")
}

// ── Gruppi ──────────────────────────────────────────────────────────────────────────────────────
type GroupRow = {
  id: string
  name: string
  slot: Game.SlotId
  raid: string
  days: string
  start: number
  duration: number
  leader_id: string | null
  leader: string | null
  description: string
  comp: string
}

type MemberRow = {
  group_id: string
  character_id: string
  user_id: string | null
  name: string
  cls: Game.ClassId
  spec: string | null
  role: Game.Role
  bench: number
}

function members(ctx: Ctx) {
  const rows = ctx.db
    .query<MemberRow, []>(
      `SELECT group_member.group_id, group_member.character_id, group_member.bench, character.user_id, character.name, character.cls, character.spec, character.role
       FROM group_member JOIN character ON character.id = group_member.character_id
       ORDER BY group_member.bench, CASE character.role WHEN 'tank' THEN 0 WHEN 'healer' THEN 1 ELSE 2 END, character.name_key`,
    )
    .all()
  return Map.groupBy(rows, (row) => row.group_id)
}

function toGroup(row: GroupRow, list: MemberRow[] | undefined): Schema.Group {
  return {
    id: row.id,
    name: row.name,
    slot: row.slot,
    raid: row.raid,
    days: json<number[]>(row.days, []),
    start: row.start,
    duration: row.duration,
    leaderId: row.leader_id,
    leader: row.leader,
    description: row.description,
    comp: comp(row.raid, json<Comp | null>(row.comp, null)),
    members: (list ?? []).map((m) => ({
      characterId: m.character_id,
      userId: m.user_id,
      name: m.name,
      cls: m.cls,
      spec: m.spec,
      role: m.role,
      bench: m.bench === 1,
    })),
  }
}

const GROUPS = `SELECT raid_group.*, user.name AS leader FROM raid_group LEFT JOIN user ON user.id = raid_group.leader_id`

export function groups(ctx: Ctx) {
  const all = members(ctx)
  return ctx.db
    .query<GroupRow, []>(`${GROUPS} ORDER BY raid_group.position, raid_group.start, raid_group.name`)
    .all()
    .map((row) => toGroup(row, all.get(row.id)))
}

export function group(ctx: Ctx, target: string) {
  const found = groups(ctx).find((g) => g.id === target)
  if (!found) throw new Fail(404, "Gruppo non trovato")
  return found
}

type GroupInput = z.infer<typeof Schema.GroupInput>

function groupValues(ctx: Ctx, input: GroupInput) {
  checkRaid(input.raid)
  if (input.leaderId && !ctx.db.query("SELECT 1 FROM user WHERE id = ?").get(input.leaderId)) throw new Fail(400, "Capo gruppo non trovato")
  const days = [...new Set(input.days)].toSorted((a, b) => a - b)
  return [input.name, input.slot, input.raid, JSON.stringify(days), input.start, input.duration, input.leaderId, input.description, JSON.stringify(comp(input.raid, input.comp))]
}

export function createGroup(ctx: Ctx, input: GroupInput) {
  const target = id()
  ctx.db.run(
    `INSERT INTO raid_group (name, slot, raid, days, start, duration, leader_id, description, comp, id, position)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, (SELECT COUNT(*) FROM raid_group))`,
    [...groupValues(ctx, input), target],
  )
  touch(ctx, { type: "group", id: target })
  return group(ctx, target)
}

export function updateGroup(ctx: Ctx, target: string, input: GroupInput) {
  group(ctx, target)
  ctx.db.run("UPDATE raid_group SET name = ?, slot = ?, raid = ?, days = ?, start = ?, duration = ?, leader_id = ?, description = ?, comp = ? WHERE id = ?", [
    ...groupValues(ctx, input),
    target,
  ])
  touch(ctx, { type: "group", id: target })
  return group(ctx, target)
}

export function removeGroup(ctx: Ctx, target: string) {
  group(ctx, target)
  ctx.db.run("DELETE FROM raid_group WHERE id = ?", [target])
  touch(ctx, { type: "group", id: target })
}

export function setMember(ctx: Ctx, target: string, input: { characterId: string; bench: boolean }) {
  group(ctx, target)
  if (!Character.get(ctx, input.characterId)) throw new Fail(404, "Personaggio non trovato")
  ctx.db.run(
    "INSERT INTO group_member (group_id, character_id, bench) VALUES (?, ?, ?) ON CONFLICT(group_id, character_id) DO UPDATE SET bench = excluded.bench",
    [target, input.characterId, input.bench ? 1 : 0],
  )
  touch(ctx, { type: "group", id: target })
  return group(ctx, target)
}

export function removeMember(ctx: Ctx, target: string, character: string) {
  ctx.db.run("DELETE FROM group_member WHERE group_id = ? AND character_id = ?", [target, character])
  touch(ctx, { type: "group", id: target })
  return group(ctx, target)
}

/** Il capo del gruppo gestisce i propri eventi anche senza essere ufficiale. */
export function leads(ctx: Ctx, user: Schema.User, target: string | null) {
  if (Game.rankAtLeast(user.rank, "officer")) return true
  if (!target || !Game.rankAtLeast(user.rank, "member")) return false
  return !!ctx.db.query("SELECT 1 FROM raid_group WHERE id = ? AND leader_id = ?").get(target, user.id)
}

// ── Eventi ──────────────────────────────────────────────────────────────────────────────────────
type EventRow = {
  id: string
  group_id: string | null
  group_name: string | null
  group_comp: string | null
  raid: string
  title: string
  date: string
  start: number
  starts_at: number
  duration: number
  note: string
  status: Schema.RaidEvent["status"]
}

type SignupRow = {
  event_id: string
  character_id: string
  user_id: string | null
  name: string
  cls: Game.ClassId
  spec: string | null
  role: Game.Role
  status: Schema.Signup["status"]
  note: string
  picked: number
  source: Schema.Source
  updated: number
}

const EVENTS = `SELECT event.*, raid_group.name AS group_name, raid_group.comp AS group_comp FROM event LEFT JOIN raid_group ON raid_group.id = event.group_id`

function signups(ctx: Ctx, from: number, to: number) {
  const rows = ctx.db
    .query<SignupRow, [number, number]>(
      `SELECT signup.*, character.name, character.cls, character.spec
       FROM signup JOIN character ON character.id = signup.character_id JOIN event ON event.id = signup.event_id
       WHERE event.starts_at >= ? AND event.starts_at < ?
       ORDER BY CASE signup.status WHEN 'yes' THEN 0 WHEN 'maybe' THEN 1 ELSE 2 END,
         CASE signup.role WHEN 'tank' THEN 0 WHEN 'healer' THEN 1 ELSE 2 END, character.name_key`,
    )
    .all(from, to)
  return Map.groupBy(rows, (row) => row.event_id)
}

function toEvent(row: EventRow, list: SignupRow[] | undefined): Schema.RaidEvent {
  return {
    id: row.id,
    groupId: row.group_id,
    group: row.group_name,
    raid: row.raid,
    title: row.title || Game.findRaid(row.raid)?.label || row.raid,
    date: row.date,
    start: row.start,
    startsAt: row.starts_at,
    duration: row.duration,
    note: row.note,
    status: row.status,
    comp: comp(row.raid, json<Comp | null>(row.group_comp, null)),
    signups: (list ?? []).map((s) => ({
      characterId: s.character_id,
      userId: s.user_id,
      name: s.name,
      cls: s.cls,
      spec: s.spec,
      role: s.role,
      status: s.status,
      note: s.note,
      picked: s.picked === 1,
      source: s.source,
      updated: s.updated,
    })),
  }
}

export function events(ctx: Ctx, from: number, to: number) {
  const all = signups(ctx, from, to)
  return ctx.db
    .query<EventRow, [number, number]>(`${EVENTS} WHERE event.starts_at >= ? AND event.starts_at < ? ORDER BY event.starts_at`)
    .all(from, to)
    .map((row) => toEvent(row, all.get(row.id)))
}

/** Prossimi eventi non annullati: per la home, l'addon e il bot. */
export function upcoming(ctx: Ctx, limit: number) {
  // Un raid in corso resta visibile finche' non finisce.
  return events(ctx, ctx.now() - 6 * 3_600_000, ctx.now() + 60 * 86_400_000)
    .filter((e) => e.status !== "cancelled" && e.startsAt + e.duration * 60_000 > ctx.now())
    .slice(0, limit)
}

export function event(ctx: Ctx, target: string) {
  const row = ctx.db.query<EventRow, [string]>(`${EVENTS} WHERE event.id = ?`).get(target)
  if (!row) throw new Fail(404, "Evento non trovato")
  return toEvent(row, signups(ctx, row.starts_at, row.starts_at + 1).get(row.id))
}

type EventInput = z.infer<typeof Schema.EventInput>

function when(ctx: Ctx, date: string, start: number) {
  if (!Availability.isDate(date)) throw new Fail(400, "Data non valida")
  return Availability.instant(date, start, ctx.config.tz)
}

export function createEvent(ctx: Ctx, input: EventInput) {
  checkRaid(input.raid)
  if (input.groupId) group(ctx, input.groupId)
  const target = id()
  ctx.db.run("INSERT INTO event (id, group_id, raid, title, date, start, starts_at, duration, note, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
    target,
    input.groupId,
    input.raid,
    input.title,
    input.date,
    input.start,
    when(ctx, input.date, input.start),
    input.duration,
    input.note,
    ctx.now(),
  ])
  touch(ctx, { type: "event", id: target })
  const created = event(ctx, target)
  ctx.announce(`⚔️ Nuovo raid: **${created.title}** — ${created.date} alle ${Availability.formatMinutes(created.start)}. Prenotati dal sito, dall'app o con /prenota.`)
  return created
}

export function updateEvent(ctx: Ctx, target: string, input: z.infer<typeof Schema.EventPatch>) {
  const current = event(ctx, target)
  const raid = input.raid ?? current.raid
  checkRaid(raid)
  const groupId = input.groupId === undefined ? current.groupId : input.groupId
  if (groupId) group(ctx, groupId)
  const date = input.date ?? current.date
  const start = input.start ?? current.start
  ctx.db.run("UPDATE event SET group_id = ?, raid = ?, title = ?, date = ?, start = ?, starts_at = ?, duration = ?, note = ?, status = ? WHERE id = ?", [
    groupId,
    raid,
    input.title ?? (current.title === Game.findRaid(current.raid)?.label ? "" : current.title),
    date,
    start,
    when(ctx, date, start),
    input.duration ?? current.duration,
    input.note ?? current.note,
    input.status ?? current.status,
    target,
  ])
  touch(ctx, { type: "event", id: target })
  return event(ctx, target)
}

export function removeEvent(ctx: Ctx, target: string) {
  event(ctx, target)
  ctx.db.run("DELETE FROM event WHERE id = ?", [target])
  touch(ctx, { type: "event", id: target })
}

/** Crea gli eventi di una settimana per ogni giorno previsto dal gruppo, saltando quelli gia' a calendario. */
export function schedule(ctx: Ctx, target: string, week: string) {
  const g = group(ctx, target)
  if (!Availability.isDate(week)) throw new Fail(400, "Settimana non valida")
  const monday = Availability.weekOf(week)
  return g.days.flatMap((day) => {
    const date = Availability.addDays(monday, day)
    const taken = ctx.db.query("SELECT 1 FROM event WHERE group_id = ? AND date = ?").get(target, date)
    if (taken) return []
    return [createEvent(ctx, { groupId: target, raid: g.raid, title: "", date, start: g.start, duration: g.duration, note: "" })]
  })
}

// ── Prenotazioni ────────────────────────────────────────────────────────────────────────────────
type SignupInput = { characterId?: string; status: Schema.Signup["status"]; role?: Game.Role; note: string }

/** Una prenotazione per giocatore per evento: cambiare personaggio sostituisce la precedente. */
export function signup(ctx: Ctx, user: Schema.User, source: Schema.Source, target: string, input: SignupInput) {
  const current = event(ctx, target)
  if (current.status !== "open") throw new Fail(409, "Le prenotazioni per questo raid sono chiuse")
  const character = input.characterId ? Character.get(ctx, input.characterId) : Character.main(ctx, user.id)
  if (!character) throw new Fail(400, "Aggiungi prima un personaggio al tuo profilo")
  if (character.userId !== user.id) throw new Fail(403, "Non è un tuo personaggio")
  const role = Game.resolveRole(character.cls, character.spec, input.role ?? character.role)
  const member = ctx.db
    .query<{ bench: number }, [string | null, string]>("SELECT bench FROM group_member WHERE group_id = ? AND character_id = ?")
    .get(current.groupId, character.id)
  const previous = current.signups.find((s) => s.characterId === character.id)
  // Chi e' titolare nel gruppo preformato entra subito nel roster; gli altri li sceglie il capo gruppo.
  const picked = input.status === "yes" && (previous ? previous.picked : member?.bench === 0)
  ctx.db.transaction(() => {
    ctx.db.run("DELETE FROM signup WHERE event_id = ? AND user_id = ? AND character_id != ?", [target, user.id, character.id])
    ctx.db.run(
      `INSERT INTO signup (event_id, character_id, user_id, status, role, note, picked, source, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(event_id, character_id) DO UPDATE SET user_id = excluded.user_id, status = excluded.status, role = excluded.role,
         note = excluded.note, picked = excluded.picked, source = excluded.source, updated = excluded.updated`,
      [target, character.id, user.id, input.status, role, input.note, picked ? 1 : 0, source, ctx.now()],
    )
  })()
  touch(ctx, { type: "event", id: target })
  return event(ctx, target)
}

export function pick(ctx: Ctx, target: string, input: { characterId: string; picked: boolean }) {
  const result = ctx.db.run("UPDATE signup SET picked = ? WHERE event_id = ? AND character_id = ? AND status != 'no'", [
    input.picked ? 1 : 0,
    target,
    input.characterId,
  ])
  if (result.changes === 0) throw new Fail(404, "Prenotazione non trovata")
  touch(ctx, { type: "event", id: target })
  return event(ctx, target)
}

/** Per ogni boss del raid: il roster scelto (o, se vuoto, chi ha detto si') contro la tattica. */
export function analysis(ctx: Ctx, target: string): Schema.EventAnalysis {
  const current = event(ctx, target)
  const raid = Game.findRaid(current.raid)
  if (!raid) return []
  const yes = current.signups.filter((s) => s.status === "yes")
  const chosen = yes.some((s) => s.picked) ? yes.filter((s) => s.picked) : yes
  const roster = chosen.map((s) => ({ name: s.name, cls: s.cls, spec: s.spec, role: s.role }))
  const m = Boss.matrix(ctx)
  return Boss.list(ctx, current.raid).map((boss) => ({
    boss: { id: boss.id, name: boss.name, weights: boss.weights },
    analysis: Tactics.analyze(m, boss.weights, roster, { size: raid.size, comp: current.comp }),
  }))
}
