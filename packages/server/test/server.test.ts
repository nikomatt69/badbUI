import { beforeEach, describe, expect, test } from "bun:test"
import { Lua, type Schema } from "@badb/core"
import { context, create, type App } from "../src/server"
import type { Ctx } from "../src/ctx"

// Mercoledi' 11 novembre 2026, 13:00 a Roma.
const START = Date.parse("2026-11-11T12:00:00Z")
const WEEK = "2026-11-09"

type State = { app: App; ctx: Ctx; clock: { now: number }; said: string[] }
const state = {} as State

beforeEach(() => {
  const clock = { now: START }
  const said: string[] = []
  const ctx = context(
    { db: ":memory:", tz: "Europe/Rome", origins: [], bot: "bot-secret", webhook: "", web: "" },
    { now: () => clock.now, announce: (text) => said.push(text) },
  )
  Object.assign(state, { app: create(ctx), ctx, clock, said })
})

async function call<T = any>(method: string, path: string, token?: string | null, body?: unknown, headers: Record<string, string> = {}) {
  const response = await state.app.request(path, {
    method,
    headers: {
      ...(token ? { authorization: token.includes(" ") ? token : `Bearer ${token}` } : {}),
      ...(body === undefined ? {} : { "content-type": "application/json" }),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  return { status: response.status, data: (await response.json()) as T }
}

async function account(name: string) {
  const result = await call("POST", "/auth/register", null, { name, password: "password123" })
  expect(result.status).toBe(200)
  return result.data as { token: string; user: Schema.User }
}

/** Capogilda + un membro con personaggio. */
async function guild() {
  const gm = await account("Capo")
  const member = await account("Niko")
  await call("PATCH", `/member/${member.user.id}`, gm.token, { rank: "member" })
  const character = await call<Schema.Character>("POST", "/character", member.token, { name: "Nikomago", cls: "mage", spec: "frost" })
  return { gm, member, character: character.data }
}

describe("account", () => {
  test("il primo account e' capogilda, gli altri ospiti", async () => {
    const gm = await account("Capo")
    const guest = await account("Ospite")
    expect(gm.user.rank).toBe("gm")
    expect(guest.user.rank).toBe("guest")
    expect((await call("POST", "/auth/register", null, { name: "capo", password: "password123" })).status).toBe(409)
    expect((await call("POST", "/auth/register", null, { name: "x", password: "short" })).status).toBe(400)
  })

  test("login, me, logout", async () => {
    await account("Capo")
    expect((await call("POST", "/auth/login", null, { name: "CAPO", password: "sbagliata1" })).status).toBe(401)
    expect((await call("POST", "/auth/login", null, { name: "nessuno", password: "password123" })).status).toBe(401)
    const login = await call("POST", "/auth/login", null, { name: "CAPO", password: "password123" })
    expect(login.status).toBe(200)
    expect((await call("GET", "/auth/me", login.data.token)).data.user.name).toBe("Capo")
    expect(JSON.stringify(login.data)).not.toContain("argon")
    await call("POST", "/auth/logout", login.data.token)
    expect((await call("GET", "/auth/me", login.data.token)).status).toBe(401)
    expect((await call("GET", "/auth/me", null)).status).toBe(401)
  })

  test("le sessioni scadono", async () => {
    const gm = await account("Capo")
    state.clock.now += 31 * 86_400_000
    expect((await call("GET", "/auth/me", gm.token)).status).toBe(401)
  })

  test("limite di tentativi sul login", async () => {
    await account("Capo")
    const tries = await Promise.all(Array.from({ length: 14 }, () => call("POST", "/auth/login", null, { name: "Capo", password: "sbagliata1" })))
    expect(tries.filter((t) => t.status === 429).length).toBeGreaterThan(0)
  })

  test("gradi: gli ufficiali non toccano ufficiali, resta sempre un capogilda", async () => {
    const gm = await account("Capo")
    const officer = await account("Uff")
    const guest = await account("Ospite")
    expect((await call("PATCH", `/member/${guest.user.id}`, guest.token, { rank: "gm" })).status).toBe(403)
    expect((await call("PATCH", `/member/${officer.user.id}`, gm.token, { rank: "officer" })).data.rank).toBe("officer")
    expect((await call("PATCH", `/member/${guest.user.id}`, officer.token, { rank: "member" })).data.rank).toBe("member")
    expect((await call("PATCH", `/member/${guest.user.id}`, officer.token, { rank: "officer" })).status).toBe(403)
    expect((await call("PATCH", `/member/${gm.user.id}`, officer.token, { rank: "guest" })).status).toBe(403)
    expect((await call("PATCH", `/member/${gm.user.id}`, gm.token, { rank: "member" })).status).toBe(409)
    expect((await call("GET", "/member", guest.token)).status).toBe(403)
  })
})

describe("collegamenti", () => {
  test("codice addon: monouso, a scadenza, token funzionante", async () => {
    const gm = await account("Capo")
    const link = await call("POST", "/auth/link", gm.token, { kind: "addon" })
    expect(link.data.code).toMatch(/^[A-Z2-9]{8}$/)
    const redeemed = await call("POST", "/auth/link/redeem", null, { code: link.data.code.toLowerCase(), label: "PC" })
    expect(redeemed.status).toBe(200)
    expect((await call("GET", "/auth/me", redeemed.data.token)).data.user.name).toBe("Capo")
    expect((await call("POST", "/auth/link/redeem", null, { code: link.data.code })).status).toBe(400)
    const late = await call("POST", "/auth/link", gm.token, { kind: "mobile" })
    state.clock.now += 11 * 60_000
    expect((await call("POST", "/auth/link/redeem", null, { code: late.data.code })).status).toBe(400)
  })

  test("un codice Discord non si riscatta come token", async () => {
    const gm = await account("Capo")
    const link = await call("POST", "/auth/link", gm.token, { kind: "discord" })
    expect((await call("POST", "/auth/link/redeem", null, { code: link.data.code })).status).toBe(400)
  })

  test("bot Discord: collega e agisce per l'utente", async () => {
    const { member } = await guild()
    const link = await call("POST", "/auth/link", member.token, { kind: "discord" })
    expect((await call("POST", "/auth/discord", "Bot wrong", { code: link.data.code, discordId: "123456789" })).status).toBe(401)
    expect((await call("POST", "/auth/discord", member.token, { code: link.data.code, discordId: "123456789" })).status).toBe(401)
    const linked = await call("POST", "/auth/discord", "Bot bot-secret", { code: link.data.code, discordId: "123456789", discordName: "niko" })
    expect(linked.data.discordId).toBe("123456789")
    const said = await call("POST", "/availability/text", "Bot bot-secret", { text: "ci sono giovedì dalle 21 alle 23" }, { "x-discord-id": "123456789" })
    expect(said.status).toBe(200)
    expect(said.data.entry.source).toBe("discord")
    expect(said.data.entry.ranges).toEqual([{ day: 3, start: 1260, end: 1380 }])
    expect((await call("GET", "/auth/me", "Bot bot-secret", undefined, { "x-discord-id": "999999999" })).status).toBe(403)
    expect((await call("GET", "/auth/me", "Bot wrong", undefined, { "x-discord-id": "123456789" })).status).toBe(401)
  })
})

describe("armory", () => {
  test("personaggi: ruolo coerente, main, proprieta'", async () => {
    const { gm, member, character } = await guild()
    expect(character).toMatchObject({ name: "Nikomago", role: "dps", main: true, owner: "Niko" })
    const alt = await call<Schema.Character>("POST", "/character", member.token, { name: "Nikoprete", cls: "priest", spec: "holy", role: "tank", main: true })
    expect(alt.data).toMatchObject({ role: "healer", main: true })
    expect((await call("GET", "/auth/me", member.token)).data.characters.map((c: Schema.Character) => [c.name, c.main])).toEqual([
      ["Nikoprete", true],
      ["Nikomago", false],
    ])
    expect((await call("POST", "/character", gm.token, { name: "nikomago", cls: "mage" })).status).toBe(409)
    const other = await account("Altro")
    expect((await call("PATCH", `/character/${character.id}`, other.token, { spec: "fire" })).status).toBe(403)
    expect((await call("PATCH", `/character/${character.id}`, member.token, { level: 42 })).data).toMatchObject({ spec: "frost", level: 42 })
    expect((await call("PATCH", `/character/${character.id}`, member.token, { spec: "bogus" })).data).toMatchObject({ spec: null, level: 42 })
    expect((await call("GET", "/character/NIKOMAGO")).data.name).toBe("Nikomago")
    expect((await call("GET", "/character")).data.length).toBe(2)
    expect((await call("DELETE", `/character/${alt.data.id}`, member.token)).status).toBe(200)
  })
})

describe("candidature", () => {
  test("invio, revisione e accettazione", async () => {
    const gm = await account("Capo")
    const guest = await account("Nuovo")
    const input = { name: "Tankone", cls: "warrior", spec: "protection", role: "tank", discord: "nuovo#1", slots: ["sera"], ranges: [{ day: 0, start: 1200, end: 1380 }] }
    expect((await call("POST", "/application", null, input)).status).toBe(401)
    const sent = await call<Schema.Application>("POST", "/application", guest.token, input)
    expect(sent.data.status).toBe("pending")
    expect(state.said.some((s) => s.includes("Tankone"))).toBe(true)
    // Reinvio: aggiorna la stessa candidatura.
    await call("POST", "/application", guest.token, { ...input, about: "ciao" })
    expect((await call("GET", "/application", guest.token)).status).toBe(403)
    const list = await call<Schema.Application[]>("GET", "/application", gm.token)
    expect(list.data.length).toBe(1)
    expect(list.data[0]!.about).toBe("ciao")
    await call("PATCH", `/application/${sent.data.id}`, gm.token, { feePaid: true, note: "segreto" })
    const me = await call<Schema.Me>("GET", "/auth/me", guest.token)
    expect(me.data.application).toMatchObject({ feePaid: true, note: "", status: "pending" })
    expect((await call("GET", "/availability", guest.token)).status).toBe(403)
    const done = await call<Schema.Application>("PATCH", `/application/${sent.data.id}`, gm.token, { status: "accepted" })
    expect(done.data.status).toBe("accepted")
    const after = await call<Schema.Me>("GET", "/auth/me", guest.token)
    expect(after.data.user.rank).toBe("member")
    expect(after.data.characters[0]).toMatchObject({ name: "Tankone", role: "tank", main: true })
    const week = await call<Schema.Week>("GET", "/availability", guest.token)
    expect(week.data.people[0]).toMatchObject({ name: "Nuovo", cls: "warrior", mask: "001000000000000000000" })
    expect((await call("POST", "/application", guest.token, input)).status).toBe(409)
  })
})

describe("disponibilita'", () => {
  test("replace, add, remove e griglia della settimana", async () => {
    const { member } = await guild()
    const set = await call<Schema.Availability>("PUT", "/availability", member.token, {
      week: "2026-11-12",
      ranges: [{ day: 0, start: 1140, end: 1440 }, { day: 2, start: 600, end: 720 }],
    })
    expect(set.data.mask).toBe("001000100000000000000")
    await call("PUT", "/availability", member.token, { week: WEEK, mode: "add", ranges: [{ day: 0, start: 780, end: 1140 }] })
    const cut = await call<Schema.Availability>("PUT", "/availability", member.token, { week: WEEK, mode: "remove", ranges: [{ day: 0, start: 1140, end: 1440 }] })
    expect(cut.data.ranges).toEqual([{ day: 0, start: 780, end: 1140 }, { day: 2, start: 600, end: 720 }])
    const week = await call<Schema.Week>("GET", `/availability?week=${WEEK}`, member.token)
    expect(week.data).toMatchObject({ week: WEEK, people: [{ name: "Niko", cls: "mage" }] })
    expect((await call("GET", "/availability?week=2026-11-16", member.token)).data.people).toEqual([])
    expect((await call("PUT", "/availability", member.token, { week: WEEK, ranges: [{ day: 9, start: 0, end: 10 }] })).status).toBe(400)
    expect((await call("GET", "/availability?week=boh", member.token)).status).toBe(400)
    expect((await call("POST", "/availability/text", member.token, { text: "boh" })).status).toBe(400)
    const no = await call("POST", "/availability/text", member.token, { text: "non ci sono lunedì" })
    expect(no.data.entry.ranges).toEqual([{ day: 2, start: 600, end: 720 }])
  })
})

describe("raid", () => {
  async function setup() {
    const base = await guild()
    const group = await call<Schema.Group>("POST", "/group", base.gm.token, {
      name: "Sera", slot: "sera", raid: "barrow-deeps", days: [3, 1, 3], start: 21 * 60, leaderId: base.member.user.id,
    })
    return { ...base, group: group.data }
  }

  test("gruppi: permessi, membri e composizione di default", async () => {
    const { gm, member, character, group } = await setup()
    expect(group).toMatchObject({ days: [1, 3], comp: { tank: 2, healer: 3, dps: 5 }, leader: "Niko" })
    expect((await call("POST", "/group", member.token, { name: "X", slot: "sera", raid: "barrow-deeps", start: 0 })).status).toBe(403)
    expect((await call("POST", "/group", gm.token, { name: "X", slot: "sera", raid: "molten-core", start: 0 })).status).toBe(400)
    // Il capo gruppo (membro semplice) gestisce il proprio roster.
    const added = await call<Schema.Group>("PUT", `/group/${group.id}/member`, member.token, { characterId: character.id })
    expect(added.data.members).toMatchObject([{ name: "Nikomago", bench: false }])
    const other = await account("Altro")
    await call("PATCH", `/member/${other.user.id}`, gm.token, { rank: "member" })
    expect((await call("PUT", `/group/${group.id}/member`, other.token, { characterId: character.id })).status).toBe(403)
    expect((await call("DELETE", `/group/${group.id}/member/${character.id}`, member.token)).data.members).toEqual([])
  })

  test("pianifica la settimana senza duplicati, orario nel fuso della gilda", async () => {
    const { member, group } = await setup()
    const made = await call<Schema.RaidEvent[]>("POST", `/group/${group.id}/schedule`, member.token, { week: WEEK })
    expect(made.data.map((e) => e.date)).toEqual(["2026-11-10", "2026-11-12"])
    expect(new Date(made.data[1]!.startsAt).toISOString()).toBe("2026-11-12T20:00:00.000Z")
    expect(made.data[1]!.title).toBe("Barrow Deeps")
    expect((await call("POST", `/group/${group.id}/schedule`, member.token, { week: WEEK })).data).toEqual([])
    expect(state.said.filter((s) => s.includes("Nuovo raid")).length).toBe(2)
    // In home solo quelli non ancora finiti.
    expect((await call<Schema.Home>("GET", "/home")).data.events.map((e) => e.date)).toEqual(["2026-11-12"])
  })

  test("prenotazione: una per giocatore, titolari scelti subito, chiusura", async () => {
    const { gm, member, character, group } = await setup()
    await call("PUT", `/group/${group.id}/member`, gm.token, { characterId: character.id })
    const event = (await call<Schema.RaidEvent>("POST", "/raid/event", gm.token, { groupId: group.id, raid: "barrow-deeps", date: "2026-11-12", start: 1260 })).data
    const guest = await account("Ospite")
    expect((await call("PUT", `/raid/event/${event.id}/signup`, guest.token, { status: "yes" })).status).toBe(403)
    expect((await call("PUT", `/raid/event/${event.id}/signup`, gm.token, { status: "yes" })).status).toBe(400)
    const yes = await call<Schema.RaidEvent>("PUT", `/raid/event/${event.id}/signup`, member.token, { status: "yes", note: "ci sono" })
    expect(yes.data.signups).toMatchObject([{ name: "Nikomago", status: "yes", picked: true, role: "dps", source: "site" }])
    const alt = (await call<Schema.Character>("POST", "/character", member.token, { name: "Nikoprete", cls: "priest", spec: "holy" })).data
    const swapped = await call<Schema.RaidEvent>("PUT", `/raid/event/${event.id}/signup`, member.token, { characterId: alt.id, status: "maybe" })
    expect(swapped.data.signups).toMatchObject([{ name: "Nikoprete", status: "maybe", picked: false, role: "healer" }])
    expect((await call("PUT", `/raid/event/${event.id}/signup`, gm.token, { characterId: alt.id, status: "yes" })).status).toBe(403)
    const picked = await call<Schema.RaidEvent>("PUT", `/raid/event/${event.id}/pick`, member.token, { characterId: alt.id, picked: true })
    expect(picked.data.signups[0]!.picked).toBe(true)
    await call("PATCH", `/raid/event/${event.id}`, gm.token, { status: "locked" })
    expect((await call("PUT", `/raid/event/${event.id}/signup`, member.token, { status: "no" })).status).toBe(409)
    const moved = await call<Schema.RaidEvent>("PATCH", `/raid/event/${event.id}`, gm.token, { date: "2026-11-13", status: "open" })
    expect(new Date(moved.data.startsAt).toISOString()).toBe("2026-11-13T20:00:00.000Z")
    expect(moved.data).toMatchObject({ groupId: group.id, duration: 180, status: "open" })
    expect((await call("DELETE", `/raid/event/${event.id}`, guest.token)).status).toBe(403)
    expect((await call("DELETE", `/raid/event/${event.id}`, member.token)).status).toBe(200)
    expect((await call("GET", `/raid/event/${event.id}`)).status).toBe(404)
  })

  test("un capo gruppo non crea eventi fuori dal suo gruppo", async () => {
    const { gm, member, group } = await setup()
    const other = (await call<Schema.Group>("POST", "/group", gm.token, { name: "Mattina", slot: "mattina", raid: "onyxia", start: 600 })).data
    expect((await call("POST", "/raid/event", member.token, { groupId: other.id, raid: "onyxia", date: "2026-11-12", start: 600 })).status).toBe(403)
    expect((await call("POST", "/raid/event", member.token, { raid: "onyxia", date: "2026-11-12", start: 600 })).status).toBe(403)
    const own = await call<Schema.RaidEvent>("POST", "/raid/event", member.token, { groupId: group.id, raid: "barrow-deeps", date: "2026-11-12", start: 600 })
    expect(own.status).toBe(200)
    expect((await call("PATCH", `/raid/event/${own.data.id}`, member.token, { groupId: other.id })).status).toBe(403)
  })
})

describe("boss e tattiche", () => {
  test("classifica per boss, correzioni alla matrice, analisi dell'evento", async () => {
    const { gm, member, character } = await guild()
    expect((await call("POST", "/boss", member.token, { raid: "onyxia", name: "Onyxia" })).status).toBe(403)
    const boss = await call<Schema.BossDetail>("POST", "/boss", gm.token, { raid: "barrow-deeps", name: "Guardiano", weights: { decurse: 3, ranged: 2, cc: 3, "tank-swap": 1 } })
    expect(boss.data.best.dps[0]).toMatchObject({ cls: "mage", score: 100 })
    expect(boss.data.best.tank.length).toBe(3)
    expect(boss.data.rank.dps.length).toBe(20)
    expect((await call<Schema.Boss[]>("GET", "/boss?raid=barrow-deeps")).data.length).toBe(1)
    expect((await call<Schema.Boss[]>("GET", "/boss?raid=onyxia")).data).toEqual([])

    expect((await call("PUT", "/tactics", member.token, { "rogue/combat": { decurse: 3 } })).status).toBe(403)
    const caps = await call<Schema.Capabilities>("PUT", "/tactics", gm.token, { "rogue/combat": { decurse: 3, st: 3 }, "nope/x": { st: 1 } })
    expect(caps.data.overrides).toEqual({ "rogue/combat": { decurse: 3 } })
    expect(caps.data.matrix["rogue/combat"]!.decurse).toBe(3)
    const reset = await call<Schema.Capabilities>("PUT", "/tactics", gm.token, { "rogue/combat": { decurse: 0 } })
    expect(reset.data.overrides).toEqual({})

    const event = (await call<Schema.RaidEvent>("POST", "/raid/event", gm.token, { raid: "barrow-deeps", date: "2026-11-12", start: 1260 })).data
    await call("PUT", `/raid/event/${event.id}/signup`, member.token, { characterId: character.id, status: "yes" })
    const analysis = await call<Schema.EventAnalysis>("GET", `/raid/event/${event.id}/analysis`)
    expect(analysis.data[0]!.boss.name).toBe("Guardiano")
    expect(analysis.data[0]!.analysis.roles.dps).toEqual({ have: 1, need: 5 })
    expect(analysis.data[0]!.analysis.coverage.find((c) => c.tag === "decurse")).toMatchObject({ have: 1, need: 2, ok: false })
    expect(analysis.data[0]!.analysis.score).toBe(100)
    const ranked = await call("POST", "/tactics/rank", null, { weights: { "raid-heal": 3 } })
    expect(ranked.data.healer[0].score).toBe(100)
  })
})

describe("blog e guide", () => {
  test("bozze visibili solo agli ufficiali, slug unici, annuncio alla pubblicazione", async () => {
    const { gm, member } = await guild()
    expect((await call("POST", "/post", member.token, { kind: "blog", title: "No" })).status).toBe(403)
    const a = await call<Schema.Post>("POST", "/post", gm.token, { kind: "blog", title: "Benvenuti in gilda!", body: "# Ciao" })
    const b = await call<Schema.Post>("POST", "/post", gm.token, { kind: "blog", title: "Benvenuti in gilda", published: false })
    expect([a.data.slug, b.data.slug]).toEqual(["benvenuti-in-gilda", "benvenuti-in-gilda-2"])
    expect(state.said.filter((s) => s.includes("Nuovo articolo")).length).toBe(1)
    expect((await call("GET", "/post?kind=blog")).data.length).toBe(1)
    expect((await call("GET", "/post?kind=blog", gm.token)).data.length).toBe(2)
    expect((await call("GET", "/post?kind=guide")).data).toEqual([])
    expect((await call("GET", `/post/blog/${b.data.slug}`)).status).toBe(404)
    expect((await call("GET", `/post/blog/${a.data.slug}`)).data.body).toBe("# Ciao")
    await call("PUT", `/post/${b.data.id}`, gm.token, { kind: "guide", title: "Guida", published: true })
    expect((await call("GET", "/post?kind=guide")).data.length).toBe(1)
    expect((await call("DELETE", `/post/${a.data.id}`, gm.token)).status).toBe(200)
  })
})

describe("gilda", () => {
  test("impostazioni solo dal capogilda", async () => {
    const { gm, member } = await guild()
    const current = (await call<Schema.Guild>("GET", "/guild")).data
    expect(current.feeSilver).toBe(3)
    expect((await call("PUT", "/guild", member.token, current)).status).toBe(403)
    expect((await call("PUT", "/guild", gm.token, { ...current, discordInvite: "javascript:alert(1)" })).status).toBe(400)
    const saved = await call<Schema.Guild>("PUT", "/guild", gm.token, { ...current, name: "Darkness Beyond", feeSilver: 0 })
    expect(saved.data.name).toBe("Darkness Beyond")
    expect((await call<Schema.Home>("GET", "/home")).data).toMatchObject({ members: 2, characters: 1, guild: { name: "Darkness Beyond" } })
  })
})

describe("addon", () => {
  test("sync: scheda personaggio, azioni idempotenti, file Lua rileggibile", async () => {
    const { gm, member, character } = await guild()
    const event = (await call<Schema.RaidEvent>("POST", "/raid/event", gm.token, { raid: "barrow-deeps", date: "2026-11-12", start: 1260 })).data
    await call("POST", "/boss", gm.token, { raid: "barrow-deeps", name: "Guardiano", weights: { decurse: 3, cc: 3 }, notes: 'Occhio al "muro" |cffff0000rosso' })
    const link = await call("POST", "/auth/link", member.token, { kind: "addon" })
    const token = (await call("POST", "/auth/link/redeem", null, { code: link.data.code })).data.token as string
    const payload = {
      version: "0.3.0",
      characters: [{ name: "Nikomago", cls: "mage", spec: "frost", level: 60, itemLevel: 62, gear: [{ slot: 16, id: 19019, name: "Thunderfury", quality: 5 }], professions: [{ name: "Sartoria", rank: 300 }] }],
      roster: [{ name: "Fantasma", cls: "rogue", level: 60, guildRank: "Membro" }],
      actions: [
        { type: "signup", id: "a1", at: 2, eventId: event.id, character: "Nikomago", status: "yes" },
        { type: "availability", id: "a0", at: 1, week: WEEK, mask: "001000000000000000000" },
        { type: "signup", id: "a2", at: 3, eventId: event.id, character: "Capone", status: "yes" },
        { type: "signup", id: "a3", at: 4, eventId: "missing", character: "Nikomago", status: "yes" },
      ],
    }
    const first = await call<Schema.SyncResult>("POST", "/addon/sync", token, payload)
    expect(first.status).toBe(200)
    expect(first.data.bundle.applied).toEqual(["a0", "a1"])
    expect(first.data.bundle.rejected.map((r) => r.id)).toEqual(["a2", "a3"])
    expect(first.data.bundle.events[0]!.signups).toEqual([{ name: "Nikomago", cls: "mage", role: "dps", status: "yes", picked: false }])
    expect(first.data.bundle.availability[0]).toEqual({ week: WEEK, people: [{ name: "Niko", cls: "mage", mask: "001000000000000000000" }] })
    expect(first.data.bundle.bosses[0]!.best.dps[0]).toMatchObject({ cls: "mage", score: 100 })
    // Il roster inviato da un membro semplice viene ignorato.
    expect((await call("GET", "/character/Fantasma")).status).toBe(404)
    const sheet = (await call<Schema.Character>("GET", "/character/Nikomago")).data
    expect(sheet).toMatchObject({ id: character.id, itemLevel: 62, source: "addon", gear: [{ id: 19019 }] })
    expect((await call<Schema.RaidEvent>("GET", `/raid/event/${event.id}`)).data.signups[0]!.source).toBe("addon")

    const parsed = Lua.parse(first.data.lua).BadbUI_GuildSync as Record<string, any>
    expect(parsed.rev).toBe(first.data.bundle.rev)
    expect(parsed.events[0].signups[0].name).toBe("Nikomago")
    expect(parsed.bosses[0].notes).toBe('Occhio al "muro" ||cffff0000rosso')

    // Stessa coda reinviata dopo che il giocatore ha cambiato idea dal sito: non sovrascrive.
    await call("PUT", `/raid/event/${event.id}/signup`, member.token, { status: "no" })
    const again = await call<Schema.SyncResult>("POST", "/addon/sync", token, payload)
    expect(again.data.bundle.applied).toEqual(["a0", "a1", "a2", "a3"])
    expect((await call<Schema.RaidEvent>("GET", `/raid/event/${event.id}`)).data.signups[0]!.status).toBe("no")
    expect((await call("POST", "/addon/sync", null, payload)).status).toBe(401)
    expect((await call("POST", "/addon/sync", token, { actions: [{ type: "drop", id: "x", at: 1 }] })).status).toBe(400)
  })

  test("roster da un ufficiale: crea, aggiorna, segna gli usciti; i personaggi altrui non si rubano", async () => {
    const { gm, member } = await guild()
    await call("POST", "/addon/sync", gm.token, { roster: [{ name: "Fantasma", cls: "rogue", level: 58, guildRank: "Recluta" }, { name: "Nikomago", cls: "mage", level: 60, guildRank: "Membro" }] })
    expect((await call<Schema.Character>("GET", "/character/Fantasma")).data).toMatchObject({ level: 58, guildRank: "Recluta", owner: null })
    expect((await call<Schema.Character>("GET", "/character/Nikomago")).data).toMatchObject({ guildRank: "Membro", owner: "Niko" })
    await call("POST", "/addon/sync", gm.token, { roster: [{ name: "Nikomago", cls: "mage", level: 60, guildRank: "Membro" }] })
    expect((await call<Schema.Character[]>("GET", "/character")).data.map((c) => c.name)).toEqual(["Nikomago"])
    const stolen = await call<Schema.SyncResult>("POST", "/addon/sync", gm.token, { characters: [{ name: "Nikomago", cls: "mage", level: 60 }] })
    expect(stolen.data.bundle.rejected[0]!.id).toBe("character:Nikomago")
    expect((await call<Schema.Character>("GET", "/character/Nikomago")).data.owner).toBe("Niko")
    // Un ospite sincronizza la propria scheda ma non vede la disponibilita' e non prenota.
    const guest = await account("Ospite")
    const sync = await call<Schema.SyncResult>("POST", "/addon/sync", guest.token, {
      characters: [{ name: "Ospitino", cls: "druid", level: 20 }],
      actions: [{ type: "availability", id: "g1", at: 1, week: WEEK, mask: "1".repeat(21) }],
    })
    expect(sync.data.bundle.availability).toEqual([])
    expect(sync.data.bundle.rejected.map((r) => r.id)).toEqual(["g1"])
    void member
  })
})

describe("http", () => {
  test("errori JSON, 404 e flusso eventi", async () => {
    const gm = await account("Capo")
    const bad = await state.app.request("/auth/login", { method: "POST", body: "{", headers: { "content-type": "application/json" } })
    expect(bad.status).toBe(400)
    expect((await call("GET", "/nope")).status).toBe(404)
    expect((await call("GET", "/health")).data.ok).toBe(true)

    const stream = await state.app.request("/event")
    expect(stream.headers.get("content-type")).toContain("text/event-stream")
    const reader = stream.body!.getReader()
    const decoder = new TextDecoder()
    expect(decoder.decode((await reader.read()).value)).toContain('"connected"')
    await call("PUT", "/guild", gm.token, { ...(await call("GET", "/guild")).data, name: "Nuova" })
    expect(decoder.decode((await reader.read()).value)).toContain('"guild"')
    await reader.cancel()
  })
})
