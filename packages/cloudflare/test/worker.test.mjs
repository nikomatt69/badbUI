import { test } from "node:test"
import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { Miniflare, Log, LogLevel, convertV4MiniflareOptions } from "miniflare"
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..")
const setupKey = "integration-test-installation-key"
const options = (persist) => ({
  ...convertV4MiniflareOptions({
    rootPath: root,
    name: "badb-guild",
    scriptPath: join(root, "dist/cloudflare/index.js"),
    modules: true,
    compatibilityDate: "2026-11-09",
    compatibilityFlags: ["nodejs_compat"],
    durableObjects: { GUILD: { className: "GuildServer", useSQLite: true } },
    durableObjectsPersist: persist,
    bindings: { BADB_TZ: "Europe/Rome", BADB_SETUP_KEY: setupKey, BADB_BOT_SECRET: "integration-bot" },
    log: new Log(LogLevel.ERROR),
    serviceBindings: {
      ASSETS: async (request) => {
        const pathname = new URL(request.url).pathname
        if (/^\/downloads\/[\w.-]+$/.test(pathname)) {
          try {
            const data = await readFile(join(root, "packages/web/dist", pathname.slice(1)))
            return new Response(request.method === "HEAD" ? null : data, {
              headers: { "content-type": pathname.endsWith(".json") ? "application/json" : "application/octet-stream" },
            })
          } catch { return new Response("missing", { status: 404 }) }
        }
        if (pathname !== "/") return new Response("missing", { status: 404 })
        return new Response(await readFile(join(root, "packages/web/dist/index.html")), {
          headers: { "content-type": "text/html" },
        })
      },
    },
  }),
  resourcePersistencePath: persist,
})

test(
  "Cloudflare: sito, auth, disponibilità, raid, addon, permessi e dati persistenti dopo riavvio",
  { timeout: 120000 },
  async () => {
    const persist = await mkdtemp(join(tmpdir(), "badb-cloudflare-"))
    let mf = new Miniflare(options(persist))
    const call = async (method, path, token, body, status = 200, headers = {}) => {
      const response = await mf.dispatchFetch(`https://badb.test${path}`, {
        method,
        headers: {
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(body ? { "content-type": "application/json" } : {}),
          ...headers,
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      })
      const data = await response.json()
      assert.equal(response.status, status, `${method} ${path}: ${JSON.stringify(data)}`)
      return data
    }
    try {
      const page = await mf.dispatchFetch("https://badb.test/")
      assert.equal(page.status, 200)
      assert.match(await page.text(), /Fratelli di Azeroth — La gilda/)
      assert.match(page.headers.get("content-security-policy"), /frame-ancestors 'none'/)
      const releaseResponse = await mf.dispatchFetch("https://badb.test/downloads/release.json")
      assert.equal(releaseResponse.status, 200, "release metadata is public")
      const release = await releaseResponse.json()
      assert.ok(release.macroCount >= 6000)
      assert.ok(release.artifacts.some((artifact) => artifact.kind === "addon"))
      for (const artifact of release.artifacts) {
        for (const path of [artifact.url, artifact.latestUrl]) {
          const download = await mf.dispatchFetch(`https://badb.test${path}`)
          assert.equal(download.status, 200, `public download: ${path}`)
          assert.match(download.headers.get("content-type"), /application\/zip/)
          assert.match(download.headers.get("content-disposition"), /^attachment;/)
          assert.match(download.headers.get("cache-control"), /must-revalidate/)
          const bytes = Buffer.from(await download.arrayBuffer())
          assert.equal(bytes.length, artifact.bytes)
          assert.equal(bytes.subarray(0, 2).toString(), "PK")
          assert.equal(createHash("sha256").update(bytes).digest("hex"), artifact.sha256)
        }
      }
      const head = await mf.dispatchFetch("https://badb.test/downloads/BadbUI-latest.zip", { method: "HEAD" })
      assert.equal(head.status, 200)
      assert.match(head.headers.get("content-disposition"), /BadbUI-latest\.zip/)
      assert.equal((await mf.dispatchFetch("https://badb.test/downloads/not-a-release.zip")).status, 404)
      assert.equal((await call("GET", "/health")).ok, true)
      assert.equal((await call("GET", "/auth/setup")).required, true)
      await call("POST", "/auth/register", null, { name: "Intruso", password: "password123" }, 403)
      const gm = await call("POST", "/auth/register", null, { name: "Capo", password: "password123", setupKey })
      assert.equal(gm.user.rank, "gm")
      const signedIn = await call("POST", "/auth/login", null, { name: "Capo", password: "password123" })
      assert.equal(signedIn.user.id, gm.user.id)
      await call("POST", "/auth/login", null, { name: "Capo", password: "wrongpass" }, 401)
      assert.equal((await call("GET", "/auth/setup")).required, false)
      const guest = await call("POST", "/auth/register", null, { name: "Membro", password: "password123" })
      await call("PUT", "/availability", guest.token, { week: "2026-11-09", ranges: [] }, 403)
      await call("PATCH", `/member/${guest.user.id}`, gm.token, { rank: "member" })
      const me = await call("GET", "/auth/me", guest.token)
      assert.equal(me.user.rank, "member")
      const character = await call("POST", "/character", guest.token, {
        name: "Niko Emme",
        cls: "mage",
        spec: "frost",
        level: 23,
      })
      await call("PUT", `/character/${character.id}/owner`, guest.token, { userId: gm.user.id }, 403)
      assert.equal(
        (await call("PUT", `/character/${character.id}/owner`, gm.token, { userId: gm.user.id })).userId,
        gm.user.id,
      )
      await call("PUT", `/character/${character.id}/owner`, gm.token, { userId: guest.user.id })
      const availability = await call("PUT", "/availability", guest.token, {
        week: "2026-11-09",
        ranges: [{ day: 2, start: 1200, end: 1380 }],
      })
      assert.equal(availability.mask[8], "1")
      const group = (await call("GET", "/group"))[2]
      await call("PUT", `/group/${group.id}`, gm.token, { ...group, name: "Gruppo Sera Reale" })
      const event = await call("POST", "/raid/event", gm.token, {
        groupId: group.id,
        raid: "barrow-deeps",
        date: "2026-12-12",
        start: 1260,
      })
      const joined = await call("PUT", `/raid/event/${event.id}/signup`, guest.token, {
        characterId: character.id,
        status: "yes",
      })
      assert.equal(joined.signups[0].name, "Niko Emme")
      await call("PUT", `/raid/event/${event.id}/pick`, gm.token, { characterId: character.id, picked: true })
      const patch = await call("PUT", "/guild", gm.token, { ...(await call("GET", "/guild")), name: "Badb Forever" })
      assert.equal(patch.name, "Badb Forever")
      assert.equal(await call("GET", "/addon/status", guest.token), null)
      await call("GET", "/addon/connections", guest.token, undefined, 403)
      const link = await call("POST", "/auth/link", guest.token, { kind: "addon" })
      const addon = await call("POST", "/auth/link/redeem", null, { code: link.code, label: "test" })
      const imported = await call("POST", "/addon/sync", addon.token, {
        client: { version: "1.60.1", build: "70790", interface: 16001 },
        characters: [
          {
            name: "Niko Emme",
            cls: "mage",
            level: 24,
            scanned: 1794260000,
            gear: [{ slot: 16, id: 35, name: "Dal client Forever", quality: 2 }],
          },
        ],
      })
      assert.match(imported.lua, /BadbUI_GuildSync/)
      const connection = await call("GET", "/addon/status", guest.token)
      assert.equal(connection.characters, 1)
      assert.equal(connection.client.build, "70790")
      assert.equal((await call("GET", "/addon/connections", gm.token))[0].userId, guest.user.id)
      await call("POST", "/addon/sync", addon.token, {
        actions: [{ type: "signup", id: "action-1", at: 1, eventId: event.id, character: "Niko Emme", status: "no" }],
      })
      const repeat = await call("POST", "/addon/sync", addon.token, {
        actions: [{ type: "signup", id: "action-1", at: 1, eventId: event.id, character: "Niko Emme", status: "yes" }],
      })
      assert.deepEqual(repeat.bundle.applied, ["action-1"])
      assert.equal((await call("GET", `/raid/event/${event.id}`)).signups[0].status, "no")
      await call("POST", "/post", gm.token, { kind: "blog", title: "Il primo raid", body: "Testo di prova" })
      assert.equal((await call("GET", "/post")).length, 3)
      const stream = await mf.dispatchFetch("https://badb.test/event")
      const reader = stream.body.getReader()
      assert.match(new TextDecoder().decode((await reader.read()).value), /connected/)
      await reader.cancel()
      // Simula il riavvio completo dell'isolate: account, token e armory non possono sparire.
      await mf.dispose()
      mf = new Miniflare(options(persist))
      assert.equal((await call("GET", "/auth/me", guest.token)).user.name, "Membro")
      const persisted = await call("GET", "/character/Niko%20Emme")
      assert.equal(persisted.level, 24)
      assert.equal(persisted.gear[0].name, "Dal client Forever")
      assert.equal((await call("GET", "/guild")).name, "Badb Forever")
      await call("POST", "/auth/logout", guest.token)
      await call("GET", "/auth/me", guest.token, undefined, 401)
    } finally {
      await mf.dispose()
      await rm(persist, { recursive: true, force: true })
    }
  },
)
