import { expect, test } from "bun:test"
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { Lua } from "@badb/core"
import { context, create } from "@badb/server"
import { createClient } from "@badb/sdk"
import { decode, paths, synchronize } from "../src/sync"

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
    await writeFile(join(target.addon, "BadbUI.toc"), "## Interface: 16001")
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
