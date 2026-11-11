import { expect, test } from "bun:test"
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { tmpdir } from "node:os"
import { Lua, type Schema } from "@badb/core"
import { context, create } from "@badb/server"
import { createClient } from "@badb/sdk"
import { decode, guildPaths, paths, synchronize } from "../src/sync"

test("parse SavedVariables vuote e rifiuta codice Lua senza eseguirlo", () => {
  const sync = decode(
    'BadbUI_GuildExport = { characters = { ["Niko Emme"] = { name="Niko Emme", cls="mage", level=16, gear={}, professions={} } }, actions={}, roster={} }',
  )
  expect(sync.characters[0]).toMatchObject({ name: "Niko Emme", gear: [], professions: [] })
  expect(() => decode('BadbUI_GuildExport = os.execute("touch /tmp/pwned")')).toThrow()
  expect(() => paths("/wow", "../account")).toThrow()
})

test("SavedVariables → API reale in memoria → bundle sicuro, provenienza e ricevute persistenti", async () => {
  const root = await mkdtemp(join(tmpdir(), "badb-companion-"))
  const ctx = context({ db: ":memory:", tz: "Europe/Rome", origins: [], bot: "", webhook: "", web: "" })
  try {
    const app = create(ctx)
    const send: typeof fetch = Object.assign(
      async (input: RequestInfo | URL, init?: RequestInit) => app.request(String(input), init),
      { preconnect: fetch.preconnect },
    )
    const session = { token: "" }
    const client = createClient({ url: "http://badb.test", token: () => session.token, fetch: send })
    session.token = (await client.auth.register({ name: "Capo", password: "password123" })).token
    const target = paths(root, "ACCOUNT")
    await mkdir(join(target.addon, "Data"), { recursive: true })
    await mkdir(join(root, "WTF/Account/ACCOUNT/SavedVariables"), { recursive: true })
    await writeFile(join(target.addon, "BadbUI.toc"), "## Interface: 16001\n## SavedVariables: BadbUIDB, BadbUI_GuildExport\n")
    const snapshot = Lua.stringify("BadbUI_GuildExport", {
      client: { version: "1.60.1", build: "70790", interface: 16001 },
      characters: [
        {
          name: "Niko Emme",
          cls: "mage",
          level: 23,
          scanned: 1794260000,
          gear: [{ slot: 16, id: 35, name: "Letto dal client", quality: 1 }],
          professions: [],
        },
      ],
      actions: [
        { type: "signup", id: "missing-event", at: 1, eventId: "missing", character: "Niko Emme", status: "yes" },
      ],
    })
    await writeFile(target.saved, snapshot)
    const bundle = await synchronize(client, target)
    const character = await client.character.get("Niko Emme")
    expect(character).toMatchObject({
      level: 23,
      source: "addon",
      scannedAt: 1794260000000,
      client: { interface: 16001, build: "70790" },
    })
    expect(bundle.rejected[0]?.id).toBe("missing-event")
    const again = await synchronize(client, target)
    expect(again.rejected).toEqual(bundle.rejected)
    await client.character.save({ name: "Niko Emme", cls: "rogue", level: 60 })
    expect(await client.character.get("Niko Emme")).toMatchObject({ cls: "mage", level: 23 })
    await expect(client.character.patch(character.id, { level: 60 })).rejects.toThrow("Forever")
    const older = decode(snapshot)
    older.characters[0]!.scanned -= 1000
    older.characters[0]!.level = 2
    await client.addon.sync(older)
    expect((await client.character.get("Niko Emme")).level).toBe(23)
    expect(await readFile(target.saved, "utf8")).toBe(snapshot)
    expect(Lua.parse(await readFile(join(target.addon, "Data/GuildSync.lua"), "utf8")).BadbUI_GuildSync).toBeTruthy()
    await writeFile(
      target.saved,
      Lua.stringify("BadbUI_GuildExport", {
        client: { version: "retail", build: "1", interface: 120000 },
        characters: [{ name: "Retail", cls: "mage", level: 60 }],
      }),
    )
    await expect(synchronize(client, target)).rejects.toThrow("Forever")
    expect((await client.character.list()).map((c) => c.name)).toEqual(["Niko Emme"])
  } finally {
    ctx.db.close()
    await rm(root, { recursive: true, force: true })
  }
})

test("companion con configurazione storica usa il modulo gilda e legge la vecchia coda finché manca il nuovo export", async () => {
  const root = await mkdtemp(join(tmpdir(), "badb-guild-split-"))
  try {
    const target = paths(root, "ACCOUNT")
    const addon = join(dirname(target.addon), "BadbUI_Guild")
    const guildSaved = join(dirname(target.saved), "BadbUI_Guild.lua")
    const coreToc = join(target.addon, "BadbUI.toc")
    await mkdir(target.addon, { recursive: true })
    await mkdir(dirname(target.saved), { recursive: true })
    const action = { type: "signup", id: "legacy-action", at: 1, eventId: "raid", character: "Main", status: "yes" }
    const old = Lua.stringify("BadbUI_GuildExport", {
      client: { version: "1.60.1", build: "70790", interface: 16001 },
      characters: [{ name: "Main", cls: "mage", level: 60 }, { name: "Alt", cls: "rogue", level: 11 }],
      roster: [{ name: "Unrelated", cls: "mage", level: 60 }],
      actions: [action],
    })
    await writeFile(coreToc, "## SavedVariables: BadbUIDB, BadbUI_GuildExport\n")
    await writeFile(target.saved, old)
    const requests: Partial<Schema.AddonSync>[] = []
    const send: typeof fetch = Object.assign(
      async (input: RequestInfo | URL, init?: RequestInit) => {
        expect(new URL(String(input)).pathname).toBe("/addon/sync")
        requests.push(JSON.parse(String(init?.body)))
        return Response.json({ bundle: { rev: requests.length, applied: [], rejected: [] } })
      },
      { preconnect: fetch.preconnect },
    )
    const client = createClient({ url: "http://badb.test", fetch: send })
    await mkdir(addon)
    await writeFile(join(addon, "BadbUI_Guild.toc"), "## SavedVariables: BadbUI_GuildExport\n")
    expect(await guildPaths(target)).toEqual({ addon, saved: guildSaved, legacySaved: target.saved })
    expect((await synchronize(client, target)).rev).toBe(1)
    expect(requests[0]?.actions).toMatchObject([action])
    expect(requests[0]?.characters?.map(({ name }) => name)).toEqual(["Main"])
    expect(requests[0]?.roster).toBeUndefined()
    await expect(readFile(join(target.addon, "Data/GuildSync.lua"))).rejects.toThrow("ENOENT")

    const fresh = Lua.stringify("BadbUI_GuildExport", { characters: [{ name: "Current", cls: "mage", level: 60 }] })
    await writeFile(guildSaved, fresh)
    await writeFile(coreToc, "## SavedVariables: BadbUIDB\n")
    expect((await synchronize(client, target)).rev).toBe(2)
    expect(requests[1]?.characters?.map(({ name }) => name)).toEqual(["Current"])
    expect(requests[1]?.actions).toEqual([])
    expect(Lua.parse(await readFile(join(addon, "Data/GuildSync.lua"), "utf8")).BadbUI_GuildSync)
      .toMatchObject({ rev: 2 })
    expect(await readFile(target.saved, "utf8")).toBe(old)
    expect(await readFile(guildSaved, "utf8")).toBe(fresh)

    await writeFile(guildSaved, "-- Nessun export ancora scritto\n")
    await expect(synchronize(client, target)).rejects.toThrow("BadbUI_GuildExport")
    expect(requests).toHaveLength(2)

    await rm(addon, { recursive: true })
    await expect(synchronize(client, target)).rejects.toThrow("Installa BadbUI_Guild")
    expect(requests).toHaveLength(2)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test("la sincronizzazione legacy verifica la destinazione dopo la richiesta", async () => {
  const root = await mkdtemp(join(tmpdir(), "badb-guild-change-"))
  try {
    const target = paths(root, "ACCOUNT")
    const toc = join(target.addon, "BadbUI.toc")
    await mkdir(target.addon, { recursive: true })
    await mkdir(dirname(target.saved), { recursive: true })
    await writeFile(toc, "## SavedVariables: BadbUIDB, BadbUI_GuildExport\n")
    await writeFile(target.saved, Lua.stringify("BadbUI_GuildExport", { actions: [] }))
    const send: typeof fetch = Object.assign(async () => {
      await writeFile(toc, "## SavedVariables: BadbUIDB\n")
      return Response.json({ bundle: { rev: 1, applied: [], rejected: [] } })
    }, { preconnect: fetch.preconnect })
    const client = createClient({ url: "http://badb.test", fetch: send })
    await expect(synchronize(client, target)).rejects.toThrow("Installa BadbUI_Guild")
    await expect(readFile(join(target.addon, "Data/GuildSync.lua"))).rejects.toThrow("ENOENT")
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
