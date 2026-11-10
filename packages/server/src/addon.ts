// Ponte con l'addon. Il client di gioco non ha rete: il companion legge le SavedVariables, chiama
// /addon/sync e scrive il file Lua che l'addon carica al prossimo /reload.
import { Availability, Game, Lua, Tactics, type Schema } from "@badb/core"
import * as Avail from "./availability"
import * as Boss from "./boss"
import * as Character from "./character"
import { Fail, rev, touch, json, type Ctx } from "./ctx"
import * as Guild from "./guild"
import * as Post from "./post"
import * as Raid from "./raid"

/** Nome della variabile globale letta da packages/addon/Modules/Guild.lua. */
export const GLOBAL = "BadbUI_GuildSync"

function apply(ctx: Ctx, user: Schema.User, action: Schema.AddonAction) {
  if (action.type === "availability") {
    Avail.set(ctx, user, "addon", { week: action.week, ranges: Availability.fromMask(action.mask), mode: "replace" })
    return
  }
  const character = Character.byName(ctx, action.character)
  if (!character || character.userId !== user.id)
    throw new Fail(403, `${action.character} non è collegato al tuo account`)
  Raid.signup(ctx, user, "addon", action.eventId, {
    characterId: character.id,
    status: action.status,
    note: action.note,
  })
}

export function bundle(
  ctx: Ctx,
  user: Schema.User | null,
  applied: string[] = [],
  rejected: Schema.Bundle["rejected"] = [],
): Schema.Bundle {
  const guild = Guild.get(ctx)
  const now = new Date(ctx.now())
  const week = Availability.currentWeek(now, ctx.config.tz)
  const member = !!user && Game.rankAtLeast(user.rank, "member")
  const label = (cls: Game.ClassId, spec: string) =>
    `${Game.classes[cls].label} ${Game.findSpec(cls, spec)?.label ?? ""}`.trim()
  const top = (fits: Tactics.Fit[]) =>
    fits.map((f) => ({ cls: f.cls, spec: f.spec, label: label(f.cls, f.spec), score: f.score }))
  return {
    rev: rev(ctx),
    generated: Math.floor(ctx.now() / 1000),
    week,
    guild: { name: guild.name, realm: guild.realm, motto: guild.motto },
    user: user ? { name: user.name, rank: user.rank } : null,
    applied,
    rejected,
    events: Raid.upcoming(ctx, 12).map((e) => ({
      id: e.id,
      title: e.title,
      raid: e.raid,
      group: e.group,
      date: e.date,
      start: e.start,
      startsAt: Math.floor(e.startsAt / 1000),
      duration: e.duration,
      status: e.status,
      note: e.note,
      comp: e.comp,
      signups: e.signups.map((s) => ({ name: s.name, cls: s.cls, role: s.role, status: s.status, picked: s.picked })),
    })),
    groups: Raid.groups(ctx).map((g) => ({
      id: g.id,
      name: g.name,
      slot: g.slot,
      raid: g.raid,
      days: g.days,
      start: g.start,
      members: g.members.filter((m) => !m.bench).map((m) => m.name),
    })),
    // La disponibilita' e' riservata ai membri, come sul sito.
    availability: member
      ? [week, Availability.addDays(week, 7)].map((w) => ({
          week: w,
          people: Avail.week(ctx, w).people.map((p) => ({ name: p.name, cls: p.cls, mask: p.mask })),
        }))
      : [],
    bosses: Boss.list(ctx).map((b) => ({
      id: b.id,
      raid: b.raid,
      name: b.name,
      notes: b.notes.slice(0, 600),
      tags: Tactics.tagIds.filter((t) => (b.weights[t] ?? 0) >= 2).map((t) => Tactics.tags[t].label),
      best: { tank: top(b.best.tank), healer: top(b.best.healer), dps: top(b.best.dps) },
    })),
    news: Post.list(ctx, "blog", false, 5).map((p) => ({
      title: p.title,
      excerpt: p.excerpt,
      published: Math.floor((p.published ?? 0) / 1000),
    })),
    guides: Post.list(ctx, "guide", false, 10).map((p) => ({
      title: p.title,
      body: Post.get(ctx, "guide", p.slug, false).body.slice(0, 6000),
    })),
    armory: Character.list(ctx)
      .slice(0, 200)
      .map((c) => ({
        name: c.name,
        cls: c.cls,
        level: c.level,
        spec: c.spec,
        role: c.role,
        gear: c.gear,
        scannedAt: c.scannedAt,
      })),
  }
}

export function lua(value: Schema.Bundle) {
  return `-- Generato dal companion Badb. Non modificare: viene riscritto a ogni sincronizzazione.\n${Lua.stringify(GLOBAL, value)}`
}

export function sync(ctx: Ctx, user: Schema.User, input: Schema.AddonSync): Schema.SyncResult {
  if (input.client && input.client.interface !== 16001)
    throw new Fail(409, "La scansione non proviene dal client WoW Forever supportato (16001)")
  const rejected: Schema.Bundle["rejected"] = []
  const applied: string[] = []
  let changed = false
  for (const character of input.characters) {
    const result = Character.scan(ctx, user, character, input.client)
    if (!result.ok) rejected.push({ id: `character:${character.name}`, error: result.error })
    else if (result.changed) changed = true
  }
  if (changed) touch(ctx, { type: "character" })
  // Solo gli ufficiali aggiornano il roster: decide chi compare nell'armory e chi risulta uscito.
  if (input.roster.length > 0 && Game.rankAtLeast(user.rank, "officer")) {
    const previous = ctx.db.query<{ value: string }, []>("SELECT value FROM setting WHERE key = 'roster-scan'").get()
    const snapshot = JSON.stringify({ at: input.rosterAt, roster: input.roster })
    const previousAt = previous ? Number((JSON.parse(previous.value) as { at: number }).at) : 0
    if (snapshot !== previous?.value && (input.rosterAt === 0 || input.rosterAt >= previousAt)) {
      Character.roster(ctx, input.roster)
      ctx.db.run(
        "INSERT INTO setting (key, value) VALUES ('roster-scan', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [snapshot],
      )
      touch(ctx, { type: "character" })
    }
  }
  const member = Game.rankAtLeast(user.rank, "member")
  for (const action of input.actions.toSorted((a, b) => a.at - b.at)) {
    // Idempotenza: il companion puo' reinviare la stessa coda se il file dati non e' stato ancora ricaricato.
    const fresh =
      ctx.db.run("INSERT OR IGNORE INTO addon_action (user_id, id, at) VALUES (?, ?, ?)", [
        user.id,
        action.id,
        ctx.now(),
      ]).changes > 0
    if (!fresh) {
      const previous = ctx.db
        .query<
          { error: string | null },
          [string, string]
        >("SELECT error FROM addon_action WHERE user_id = ? AND id = ?")
        .get(user.id, action.id)
      if (previous?.error) rejected.push({ id: action.id, error: previous.error })
      else applied.push(action.id)
      continue
    }
    if (!member) {
      const error = "Solo i membri della gilda possono prenotarsi"
      rejected.push({ id: action.id, error })
      ctx.db.run("UPDATE addon_action SET error = ? WHERE user_id = ? AND id = ?", [error, user.id, action.id])
      continue
    }
    try {
      apply(ctx, user, action)
      applied.push(action.id)
    } catch (error) {
      if (!(error instanceof Fail)) throw error
      rejected.push({ id: action.id, error: error.message })
      ctx.db.run("UPDATE addon_action SET error = ? WHERE user_id = ? AND id = ?", [error.message, user.id, action.id])
    }
  }
  ctx.db.run("DELETE FROM addon_action WHERE at < ?", [ctx.now() - 60 * 86_400_000])
  const detail = {
    client: input.client ?? null,
    characters: input.characters.length,
    roster: input.roster.length,
    actions: input.actions.length,
    rejected,
  }
  ctx.db.run(
    "INSERT INTO addon_connection (user_id, received, detail) VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET received = excluded.received, detail = excluded.detail",
    [user.id, ctx.now(), JSON.stringify(detail)],
  )
  const value = bundle(ctx, user, applied, rejected)
  return { bundle: value, lua: lua(value) }
}

export function connections(ctx: Ctx, userId?: string): Schema.AddonConnection[] {
  return ctx.db
    .query<{ user_id: string; name: string; received: number; detail: string }, string[]>(
      `SELECT addon_connection.*, user.name FROM addon_connection JOIN user ON user.id = user_id ${userId ? "WHERE user_id = ?" : ""} ORDER BY received DESC`,
    )
    .all(...(userId ? [userId] : []))
    .map((row) => ({
      userId: row.user_id,
      name: row.name,
      received: row.received,
      ...json<Omit<Schema.AddonConnection, "userId" | "name" | "received">>(row.detail, {
        client: null,
        characters: 0,
        roster: 0,
        actions: 0,
        rejected: [],
      }),
    }))
}
