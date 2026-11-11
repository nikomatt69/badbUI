import { expect, test } from "bun:test"
import { Lua } from "@badb/core"
import { zipSync } from "fflate"
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { paths } from "../src/sync"
import { createUpdater } from "../src/update"

const at = 1_800_000_000
const oldVersion = "1.0.9"
const nextVersion = "1.0.10"
const request = { id: `${at}-1`, from: oldVersion, version: nextVersion, at }
const toc = (version: string) => `## Interface: 16001\n## Version: ${version}\n`
const oldSync = "BadbUI_GuildSync = { rev = 7 }\n"
const saved = Lua.stringify("BadbUIDB", { data: { updates: { request } } })
const encoder = new TextEncoder()
const encode = (text: string) => encoder.encode(text)

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "badb-update-"))
  const target = paths(root, "TEST")
  await mkdir(join(target.addon, "Data"), { recursive: true })
  await mkdir(dirname(target.saved), { recursive: true })
  await writeFile(join(target.addon, "BadbUI.toc"), toc(oldVersion))
  await writeFile(join(target.addon, "Data/GuildSync.lua"), oldSync)
  await writeFile(target.saved, saved)
  return { root, target, cleanup: () => rm(root, { recursive: true, force: true }) }
}

function release({ extra = {}, hash, version = nextVersion }: {
  extra?: Record<string, Uint8Array>; hash?: string; version?: string
} = {}) {
  const archive = zipSync({
    "BadbUI/BadbUI.toc": encode(toc(version)),
    "BadbUI/Data/GuildSync.lua": encode("BadbUI_GuildSync = nil\n"),
    "BadbUI/Data/UpdateStatus.lua": encode("-- stub\n"),
    ...extra,
  })
  const url = `/downloads/BadbUI-${version}.zip`
  const artifact = {
    kind: "addon", version, url, bytes: archive.length,
    sha256: hash ?? new Bun.CryptoHasher("sha256").update(archive).digest("hex"),
  }
  const manifest = { version, artifacts: [artifact] }
  const downloads: string[] = []
  const send: typeof fetch = Object.assign(async (input: RequestInfo | URL) => {
    const path = new URL(String(input)).pathname
    downloads.push(path)
    if (path === url) return new Response(archive)
    if (path === "/downloads/release.json") return Response.json(manifest)
    return new Response(null, { status: 404 })
  }, { preconnect: fetch.preconnect })
  return { send, downloads, artifact }
}

test("annuncia la nuova versione, attende l'uscita, installa e conserva i dati locali", async () => {
  const { root, target, cleanup } = await fixture()
  const { send, downloads, artifact } = release()
  let running = true
  const options = { send, now: () => at, isGameRunning: () => running }
  const update = createUpdater(target, options)
  try {
    expect(await update()).toBeUndefined()
    const status = () => readFile(join(target.addon, "Data/UpdateStatus.lua"), "utf8")
    expect(await status()).toContain(`["latest"] = "${nextVersion}"`)
    expect(downloads).toEqual(["/downloads/release.json"])
    running = false
    expect(await update()).toEqual({ id: request.id, result: "installed" })
    expect(downloads).toEqual(["/downloads/release.json", artifact.url])
    expect(await readFile(join(target.addon, "BadbUI.toc"), "utf8")).toBe(toc(nextVersion))
    expect(await readFile(join(target.addon, "Data/GuildSync.lua"), "utf8")).toBe(oldSync)
    expect(await readFile(target.saved, "utf8")).toBe(saved)
    expect(await readFile(join(root, "Interface/.badbui-update-backup/BadbUI.toc"), "utf8")).toBe(toc(oldVersion))
    expect(await status()).toContain('["result"] = "installed"')
    expect(await createUpdater(target, options)()).toBeUndefined()
    expect(downloads.filter((path) => path === artifact.url)).toHaveLength(1)
  } finally {
    await cleanup()
  }
})

test("rifiuta checksum errato o percorsi ZIP estranei e lascia intatta l'installazione", async () => {
  for (const badRelease of [
    release({ hash: "0".repeat(64) }),
    release({ extra: { "BadbUI/../../bad.lua": encode("unexpected") } }),
  ]) {
    const { target, cleanup } = await fixture()
    try {
      const update = createUpdater(target, { send: badRelease.send, now: () => at, isGameRunning: () => false })
      await expect(update()).rejects.toThrow(/SHA-256|percorsi/)
      expect(await readFile(join(target.addon, "BadbUI.toc"), "utf8")).toBe(toc(oldVersion))
      expect(await readFile(join(target.addon, "Data/UpdateStatus.lua"), "utf8")).toContain('["result"] = "failed"')
      expect(await update()).toBeUndefined()
    } finally {
      await cleanup()
    }
  }
})

test("ripristina un rename interrotto e richiede conferma per un'altra versione", async () => {
  const { root, target, cleanup } = await fixture()
  const { send, downloads } = release({ version: "1.1.0" })
  try {
    await rename(target.addon, join(root, "Interface/.badbui-update-backup"))
    const update = createUpdater(target, { send, now: () => at, isGameRunning: () => false })
    expect(await update()).toEqual({ id: request.id, result: "release_changed" })
    expect(downloads).toEqual(["/downloads/release.json"])
    expect(await readFile(join(target.addon, "BadbUI.toc"), "utf8")).toBe(toc(oldVersion))
  } finally {
    await cleanup()
  }
})
