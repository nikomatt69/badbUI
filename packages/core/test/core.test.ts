import { describe, expect, test } from "bun:test"
import { Availability, Game, Lua, Schema, Tactics } from "../src"

const tz = "Europe/Rome"
// Mercoledi' 11 novembre 2026, 12:00 UTC (13:00 a Roma).
const now = new Date("2026-11-11T12:00:00Z")

describe("availability", () => {
  test("settimana e giorni", () => {
    expect(Availability.weekOf("2026-11-11")).toBe("2026-11-09")
    expect(Availability.weekOf("2026-11-15")).toBe("2026-11-09")
    expect(Availability.weekOf("2026-11-09")).toBe("2026-11-09")
    expect(Availability.dayIndex("2026-11-15")).toBe(6)
    expect(Availability.currentWeek(now, tz)).toBe("2026-11-09")
    expect(Availability.isDate("2026-02-30")).toBe(false)
  })

  test("la data locale segue il fuso, non UTC", () => {
    // Domenica 23:30 UTC e' gia' lunedi' a Roma.
    expect(Availability.currentWeek(new Date("2026-11-15T23:30:00Z"), tz)).toBe("2026-11-16")
  })

  test("istante con ora legale e solare", () => {
    expect(new Date(Availability.instant("2026-11-11", 21 * 60, tz)).toISOString()).toBe("2026-11-11T20:00:00.000Z")
    expect(new Date(Availability.instant("2026-07-01", 21 * 60, tz)).toISOString()).toBe("2026-07-01T19:00:00.000Z")
  })

  test("fasce coperte da un intervallo", () => {
    expect(Availability.slotsOf({ start: 21 * 60, end: 23 * 60 })).toEqual(["sera"])
    expect(Availability.slotsOf({ start: 12 * 60, end: 20 * 60 })).toEqual(["mattina", "pomeriggio", "sera"])
    expect(Availability.slotsOf({ start: 18 * 60 + 30, end: 20 * 60 })).toEqual(["sera"])
    expect(Availability.slotsOf({ start: 2 * 60, end: 4 * 60 })).toEqual([])
  })

  test("merge e subtract", () => {
    const merged = Availability.merge([
      { day: 0, start: 600, end: 700 },
      { day: 0, start: 650, end: 800 },
      { day: 1, start: 0, end: 60 },
      { day: 0, start: 900, end: 800 },
    ])
    expect(merged).toEqual([
      { day: 0, start: 600, end: 800 },
      { day: 1, start: 0, end: 60 },
    ])
    expect(Availability.subtract(merged, { day: 0, start: 650, end: 700 })).toEqual([
      { day: 0, start: 600, end: 650 },
      { day: 0, start: 700, end: 800 },
      { day: 1, start: 0, end: 60 },
    ])
  })

  test("maschera andata e ritorno", () => {
    const ranges = [Availability.slotRange(0, "sera"), Availability.slotRange(3, "mattina")]
    const mask = Availability.mask(ranges)
    expect(mask).toBe("001000000100000000000")
    expect(Availability.mask(Availability.fromMask(mask))).toBe(mask)
    expect(Availability.fromMask("nope")).toEqual([])
  })

  test("frasi in italiano", () => {
    const a = Availability.parse("ci sono dalle 21 alle 23 giovedì", now, tz)
    expect(a).toEqual({ ok: true, ranges: [{ day: 3, start: 1260, end: 1380 }], week: "2026-11-09", remove: false })
    const b = Availability.parse("lun mer ven sera", now, tz)
    expect(b.ok && b.ranges.map((r) => r.day)).toEqual([0, 2, 4])
    const c = Availability.parse("domani pomeriggio", now, tz)
    expect(c.ok && c.ranges).toEqual([{ day: 3, start: 780, end: 1140 }])
    const d = Availability.parse("stasera 20:30-01", now, tz)
    expect(d.ok && d.ranges).toEqual([{ day: 2, start: 1140, end: 1440 }])
    const e = Availability.parse("tutta la settimana sera prossima settimana", now, tz)
    expect(e.ok && e.week).toBe("2026-11-16")
    expect(e.ok && e.ranges.length).toBe(7)
    const f = Availability.parse("non ci sono sabato", now, tz)
    expect(f).toEqual({ ok: true, ranges: [{ day: 5, start: 0, end: 1440 }], week: "2026-11-09", remove: true })
    expect(Availability.parse("boh", now, tz).ok).toBe(false)
    expect(Availability.parse("lun 25-27", now, tz).ok).toBe(false)
  })

  test("griglia", () => {
    const g = Availability.grid([
      { name: "a", ranges: [Availability.slotRange(0, "sera")] },
      { name: "b", ranges: [{ day: 0, start: 1200, end: 1300 }] },
    ])
    expect(g[0]!.sera.map((p) => p.name)).toEqual(["a", "b"])
    expect(g[0]!.mattina).toEqual([])
  })
})

describe("game", () => {
  test("27 spec, ogni spec ha una riga nella matrice", () => {
    const keys = Game.classList.flatMap((c) => c.specs.map((s) => Game.specKey(c.id, s.id)))
    expect(keys.length).toBe(27)
    expect(Object.keys(Tactics.defaults).toSorted()).toEqual(keys.toSorted())
  })

  test("ruolo coerente con la spec", () => {
    expect(Game.resolveRole("mage", "frost", "tank")).toBe("dps")
    expect(Game.resolveRole("druid", "feral", "dps")).toBe("dps")
    expect(Game.resolveRole("druid", "feral")).toBe("tank")
    expect(Game.resolveRole("priest", null, "healer")).toBe("healer")
    expect(Game.resolveRole("rogue", null, "healer")).toBe("dps")
  })
})

describe("tactics", () => {
  const m = Tactics.matrix()

  test("punteggio per ruolo e tag derivati dalla distanza", () => {
    const w = { ranged: 3, decurse: 2 }
    expect(Tactics.fit(m, w, "mage", "frost", "dps").score).toBe(100)
    expect(Tactics.fit(m, w, "rogue", "combat", "dps").score).toBe(0)
    expect(Tactics.fit(m, w, "warrior", "protection", "tank").score).toBeNull()
    expect(Tactics.fit(m, w, "rogue", "combat", "dps").gaps).toEqual(["ranged", "decurse"])
  })

  test("classifica: le migliori classi sono distinte", () => {
    const top = Tactics.best(m, { decurse: 3, aoe: 2 }, "dps", 3)
    expect(top.map((f) => f.cls)).toEqual(["druid", "mage", "warlock"])
    expect(new Set(top.map((f) => f.cls)).size).toBe(3)
    expect(Tactics.best(m, {}, "dps")).toEqual([])
  })

  test("le correzioni degli ufficiali si sommano ai default e vengono limitate", () => {
    const fixed = Tactics.matrix({ "rogue/combat": { decurse: 9, bogus: 3 }, "nope/x": { st: 3 } })
    expect(Tactics.cap(fixed, "rogue", "combat", "decurse")).toBe(3)
    expect(Tactics.cap(fixed, "rogue", "combat", "st")).toBe(3)
    expect(fixed["nope/x"]).toBeUndefined()
    expect(Tactics.sanitize({ st: 2, bogus: 3, aoe: -1, cc: "x" })).toEqual({ st: 2 })
  })

  test("analisi del roster: ruoli e coperture", () => {
    const raid = Game.findRaid("barrow-deeps")!
    const roster: Tactics.Player[] = [
      { name: "Tank", cls: "warrior", spec: "protection", role: "tank" },
      { name: "Heal", cls: "priest", spec: "holy", role: "healer" },
      { name: "Mago", cls: "mage", spec: "frost", role: "dps" },
      { name: "Senza", cls: "rogue", spec: null, role: "dps" },
    ]
    const a = Tactics.analyze(m, { decurse: 3, interrupt: 1 }, roster, raid)
    expect(a.roles.tank).toEqual({ have: 1, need: 2 })
    const decurse = a.coverage.find((c) => c.tag === "decurse")!
    expect(decurse).toMatchObject({ have: 1, need: 2, ok: false, who: ["Mago"] })
    expect(a.coverage.find((c) => c.tag === "interrupt")!.ok).toBe(true)
    expect(a.warnings).toContain("Mancano 1 tank")
    expect(a.warnings).toContain("Maledizioni: 1/2")
    expect(Tactics.need(3, 40)).toBe(6)
    expect(Tactics.need(0, 40)).toBe(0)
  })
})

describe("lua", () => {
  test("legge un file SavedVariables", () => {
    const src = `
-- commento
BadbUIGuildDB = {
	["outbox"] = {
		{
			["type"] = "signup",
			["at"] = 1762800000,
			["note"] = "arrivo \\"tardi\\"\\n",
		}, -- [1]
	},
	["rev"] = 12,
	short = true,
	[1] = "uno",
	["vuota"] = {},
	["neg"] = -1.5e2,
	["link"] = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r",
	["utf"] = "Perché",
	["bytes"] = "\\195\\168",
}
Altro = nil
`
    const out = Lua.parse(src)
    const db = out.BadbUIGuildDB as Record<string, Lua.LuaValue>
    expect(db.rev).toBe(12)
    expect(db.short).toBe(true)
    expect(db["1"]).toBe("uno")
    expect(db.neg).toBe(-150)
    expect(db.vuota).toEqual({})
    expect(db.utf).toBe("Perché")
    expect(db.bytes).toBe("è")
    expect(db.outbox).toEqual([{ type: "signup", at: 1762800000, note: 'arrivo "tardi"\n' }])
    expect(String(db.link)).toContain("Hitem:19019")
    expect(out.Altro).toBeNull()
  })

  test("rifiuta codice e chiavi pericolose", () => {
    expect(() => Lua.parse("X = function() end")).toThrow()
    expect(() => Lua.parse("X = os.exit()")).toThrow()
    expect(() => Lua.parse("X = { 1, 2")).toThrow()
    const out = Lua.parse('X = { ["__proto__"] = { ["polluted"] = true } }')
    expect(({} as Record<string, unknown>).polluted).toBeUndefined()
    expect(Object.keys(out.X as object)).toEqual(["__proto__"])
  })

  test("scrive e rilegge", () => {
    const value = { rev: 3, list: ["a", "b"], nested: { ok: true, none: null, text: 'q"\\\n' }, empty: [] }
    const src = Lua.stringify("BadbUI_GuildSync", value)
    expect(src.startsWith("BadbUI_GuildSync = {")).toBe(true)
    expect(Lua.parse(src).BadbUI_GuildSync).toEqual({ rev: 3, list: ["a", "b"], nested: { ok: true, text: 'q"\\\n' }, empty: {} })
    expect(Lua.stringify("X", "a|cffff0000rosso")).toBe('X = "a||cffff0000rosso"\n')
    expect(() => Lua.stringify("os.exit()", 1)).toThrow()
  })
})

describe("schema", () => {
  test("azioni dell'addon", () => {
    expect(Schema.AddonAction.safeParse({ type: "availability", id: "a1", at: 1, week: "2026-11-09", mask: "0".repeat(21) }).success).toBe(true)
    expect(Schema.AddonAction.safeParse({ type: "availability", id: "a1", at: 1, week: "2026-11-09", mask: "2".repeat(21) }).success).toBe(false)
    expect(Schema.AddonAction.safeParse({ type: "delete-everything", id: "x", at: 1 }).success).toBe(false)
  })

  test("intervalli e credenziali", () => {
    expect(Schema.RangeSchema.safeParse({ day: 0, start: 100, end: 50 }).success).toBe(false)
    expect(Schema.Credentials.safeParse({ name: "Niko_emme", password: "password1" }).success).toBe(true)
    expect(Schema.Credentials.safeParse({ name: "a b", password: "password1" }).success).toBe(false)
    expect(Schema.GuildInput.shape.discordInvite.safeParse("javascript:alert(1)").success).toBe(false)
    expect(Schema.GuildInput.shape.discordInvite.safeParse("https://discord.gg/abc").success).toBe(true)
  })
})
