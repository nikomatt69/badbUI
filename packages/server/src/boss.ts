// Boss e tattiche: pesi per boss, matrice delle capacita' per spec, classifiche calcolate.
import { Game, Tactics, type Schema } from "@badb/core"
import type { z } from "zod"
import { Fail, id, json, touch, type Ctx } from "./ctx"

type Row = {
  id: string
  raid: string
  name: string
  position: number
  weights: string
  notes: string
  confidence: "A" | "B" | "C"
}

export function overrides(ctx: Ctx): Tactics.Matrix {
  const row = ctx.db.query<{ value: string }, []>("SELECT value FROM setting WHERE key = 'capabilities'").get()
  return json<Tactics.Matrix>(row?.value, {})
}

export function matrix(ctx: Ctx) {
  return Tactics.matrix(overrides(ctx))
}

export function capabilities(ctx: Ctx): Schema.Capabilities {
  return { matrix: matrix(ctx), overrides: overrides(ctx) }
}

/** Salva solo le differenze rispetto ai default, cosi' i default futuri restano efficaci dove nessuno ha toccato. */
export function setCapabilities(ctx: Ctx, patch: Record<string, Tactics.Caps>) {
  const merged = { ...overrides(ctx) }
  for (const [key, caps] of Object.entries(patch)) {
    const base = Tactics.defaults[key]
    if (!base) continue
    const next: Tactics.Caps = { ...merged[key] }
    for (const tag of Tactics.tagIds) {
      const value = caps[tag]
      if (value === undefined || tag === "ranged" || tag === "melee") continue
      if (value === (base[tag] ?? 0)) delete next[tag]
      if (value !== (base[tag] ?? 0)) next[tag] = value
    }
    merged[key] = next
    if (Object.keys(next).length === 0) delete merged[key]
  }
  ctx.db.run("INSERT INTO setting (key, value) VALUES ('capabilities', ?1) ON CONFLICT(key) DO UPDATE SET value = ?1", [
    JSON.stringify(merged),
  ])
  touch(ctx, { type: "boss" })
  return capabilities(ctx)
}

function toBoss(row: Row, m: Tactics.Matrix): Schema.BossDetail {
  const weights = Tactics.sanitize(json(row.weights, {}))
  const rank = Tactics.rank(m, weights)
  return {
    id: row.id,
    raid: row.raid,
    name: row.name,
    order: row.position,
    weights,
    notes: row.notes,
    confidence: row.confidence,
    best: { tank: Tactics.best(m, weights, "tank", 3), healer: Tactics.best(m, weights, "healer", 3), dps: Tactics.best(m, weights, "dps", 5) },
    rank,
  }
}

function strip(boss: Schema.BossDetail): Schema.Boss {
  return { id: boss.id, raid: boss.raid, name: boss.name, order: boss.order, weights: boss.weights, notes: boss.notes, confidence: boss.confidence, best: boss.best }
}

export function list(ctx: Ctx, raid?: string): Schema.Boss[] {
  const m = matrix(ctx)
  return ctx.db
    .query<Row, []>("SELECT * FROM boss ORDER BY raid, position, name")
    .all()
    .filter((row) => !raid || row.raid === raid)
    .map((row) => strip(toBoss(row, m)))
}

export function get(ctx: Ctx, boss: string) {
  const row = ctx.db.query<Row, [string]>("SELECT * FROM boss WHERE id = ?").get(boss)
  if (!row) throw new Fail(404, "Boss non trovato")
  return toBoss(row, matrix(ctx))
}

type Input = z.infer<typeof Schema.BossInput>

function checkRaid(raid: string) {
  if (!Game.findRaid(raid)) throw new Fail(400, "Raid sconosciuto")
}

export function create(ctx: Ctx, input: Input) {
  checkRaid(input.raid)
  const boss = id()
  ctx.db.run("INSERT INTO boss (id, raid, name, position, weights, notes, confidence) VALUES (?, ?, ?, ?, ?, ?, ?)", [
    boss,
    input.raid,
    input.name,
    input.order,
    JSON.stringify(Tactics.sanitize(input.weights)),
    input.notes,
    input.confidence,
  ])
  touch(ctx, { type: "boss", id: boss })
  return get(ctx, boss)
}

export function update(ctx: Ctx, boss: string, input: Input) {
  checkRaid(input.raid)
  get(ctx, boss)
  ctx.db.run("UPDATE boss SET raid = ?, name = ?, position = ?, weights = ?, notes = ?, confidence = ? WHERE id = ?", [
    input.raid,
    input.name,
    input.order,
    JSON.stringify(Tactics.sanitize(input.weights)),
    input.notes,
    input.confidence,
    boss,
  ])
  touch(ctx, { type: "boss", id: boss })
  return get(ctx, boss)
}

export function remove(ctx: Ctx, boss: string) {
  get(ctx, boss)
  ctx.db.run("DELETE FROM boss WHERE id = ?", [boss])
  touch(ctx, { type: "boss", id: boss })
}
