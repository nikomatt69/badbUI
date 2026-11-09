// Ponte con l'addon. Il client di gioco non ha rete: il companion legge le SavedVariables, chiama
// /addon/sync e scrive il file Lua che l'addon carica al prossimo /reload (e ritrasmette in gilda).
import { Availability, Game, Lua, Tactics, type Schema } from "@badb/core"
import * as Avail from "./availability"
import * as Boss from "./boss"
import * as Character from "./character"
import { Fail, rev, touch, type Ctx } from "./ctx"
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
  if (!character || character.userId !== user.id) throw new Fail(403, `${action.character} non è collegato al tuo account`)
  Raid.signup(ctx, user, "addon", action.eventId, { characterId: character.id, status: action.status, note: action.note })
}

export function bundle(ctx: Ctx, user: Schema.User | null, applied: string[] = [], rejected: Schema.Bundle["rejected"] = []): Schema.Bundle {
  const guild = Guild.get(ctx)
  const now = new Date(ctx.now())
  const week = Availability.currentWeek(now, ctx.config.tz)
  const member = !!user && Game.rankAtLeast(user.rank, "member")
  const label = (cls: Game.ClassId, spec: string) => `${Game.classes[cls].label} ${Game.findSpec(cls, spec)?.label ?? ""}`.trim()
  const top = (fits: Tactics.Fit[]) => fits.map((f) => ({ cls: f.cls, spec: f.spec, label: label(f.cls, f.spec), score: f.score ?? 0 }))
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
    news: Post.list(ctx, "blog", false, 5).map((p) => ({ title: p.title, excerpt: p.excerpt, published: Math.floor((p.published ?? 0) / 1000) })),
  }
}

export function lua(value: Schema.Bundle) {
  return `-- Generato dal companion Badb. Non modificare: viene riscritto a ogni sincronizzazione.\n${Lua.stringify(GLOBAL, value)}`
}

export function sync(ctx: Ctx, user: Schema.User, input: Schema.AddonSync): Schema.SyncResult {
  const rejected: Schema.Bundle["rejected"] = []
  const applied: string[] = []
  for (const character of input.characters) {
    const result = Character.scan(ctx, user, character)
    if (!result.ok) rejected.push({ id: `character:${character.name}`, error: result.error })
  }
  if (input.characters.length > 0) touch(ctx, { type: "character" })
  // Solo gli ufficiali aggiornano il roster: decide chi compare nell'armory e chi risulta uscito.
  if (input.roster.length > 0 && Game.rankAtLeast(user.rank, "officer")) {
    Character.roster(ctx, input.roster)
    touch(ctx, { type: "character" })
  }
  const member = Game.rankAtLeast(user.rank, "member")
  for (const action of input.actions.toSorted((a, b) => a.at - b.at)) {
    // Idempotenza: il companion puo' reinviare la stessa coda se il file dati non e' stato ancora ricaricato.
    const fresh = ctx.db.run("INSERT OR IGNORE INTO addon_action (user_id, id, at) VALUES (?, ?, ?)", [user.id, action.id, ctx.now()]).changes > 0
    if (!fresh) {
      applied.push(action.id)
      continue
    }
    if (!member) {
      rejected.push({ id: action.id, error: "Solo i membri della gilda possono prenotarsi" })
      continue
    }
    try {
      apply(ctx, user, action)
      applied.push(action.id)
    } catch (error) {
      if (!(error instanceof Fail)) throw error
      rejected.push({ id: action.id, error: error.message })
    }
  }
  ctx.db.run("DELETE FROM addon_action WHERE at < ?", [ctx.now() - 60 * 86_400_000])
  const value = bundle(ctx, user, applied, rejected)
  return { bundle: value, lua: lua(value) }
}
