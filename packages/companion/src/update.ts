import { Lua } from "@badb/core"
import { DEFAULT_SERVER_URL } from "@badb/sdk"
import { unzipSync } from "fflate"
import { copyFile, lstat, mkdir, mkdtemp, open, readFile, rename, rm, writeFile } from "node:fs/promises"
import { basename, dirname, join } from "node:path"
import { atomic, declaresGuildExport, readSavedVariables, type Paths } from "./sync"

const CHECK_INTERVAL = 120
const MAX_ARCHIVE_BYTES = 12 * 1024 * 1024
const MAX_EXPANDED_BYTES = 40 * 1024 * 1024
const VERSION = /^(?:0|[1-9]\d{0,5})\.(?:0|[1-9]\d{0,5})\.(?:0|[1-9]\d{0,5})$/
const STATUS_FILE = "Data/UpdateStatus.lua"
const SYNC_FILES = ["Data/GuildSync.lua", "Data/ChatbotSync.lua"]
const GAME_PROCESS = /^(?:World of Warcraft|Wow(?:Forever|ClassicT?|T)?\.exe)$/i

type Release = { version: string; url: string; bytes: number; sha256: string }
type Request = { id: string; from: string; version: string; at: number }
type Receipt = { id: string; result: "installed" | "failed" | "release_changed" }
type Status = { installed: string; checkedAt: number; latest?: string; receipt?: Receipt }

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function isVersion(value: unknown): value is string {
  return typeof value === "string" && VERSION.test(value)
}

function newer(version: string, installed: string) {
  const a = version.split(".").map(Number)
  const b = installed.split(".").map(Number)
  return a[0]! !== b[0] ? a[0]! > b[0]! : a[1]! !== b[1] ? a[1]! > b[1]! : a[2]! > b[2]!
}

function tocVersion(toc: string) {
  const version = /^## Version:[ \t]*(\S+)[ \t]*\r?$/m.exec(toc)?.[1]
  if (!isVersion(version) || !/^## Interface:[ \t]*16001[ \t]*\r?$/m.test(toc)) {
    throw new Error("TOC di BadbUI non valido per WoW Forever")
  }
  return version
}

function releaseFrom(value: unknown): Release {
  const manifest = object(value)
  if (!Array.isArray(manifest.artifacts)) throw new Error("Catalogo aggiornamenti non valido")
  const candidates = manifest.artifacts.map(object).filter((artifact) => artifact.kind === "addon")
  const artifact = candidates[0]
  if (candidates.length !== 1 || !artifact || !isVersion(artifact.version) || manifest.version !== artifact.version
    || artifact.url !== `/downloads/BadbUI-${artifact.version}.zip`
    || typeof artifact.bytes !== "number" || !Number.isSafeInteger(artifact.bytes)
    || artifact.bytes <= 0 || artifact.bytes > MAX_ARCHIVE_BYTES
    || typeof artifact.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(artifact.sha256)) {
    throw new Error("Versione o archivio di BadbUI non valido nel catalogo")
  }
  return { version: artifact.version, url: artifact.url, bytes: artifact.bytes, sha256: artifact.sha256 }
}

async function fetchBytes(send: typeof fetch, path: string, maxBytes: number) {
  const response = await send(new URL(path, DEFAULT_SERVER_URL), {
    redirect: "error",
    cache: "no-cache",
    signal: AbortSignal.timeout(15_000),
  })
  if (!response.ok || !response.body) throw new Error(`Download BadbUI non riuscito (HTTP ${response.status})`)
  const reader = response.body.getReader()
  const chunks: Uint8Array[] = []
  let size = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      size += value.byteLength
      if (size > maxBytes) throw new Error("Download BadbUI oltre il limite previsto")
      chunks.push(value)
    }
  } finally {
    await reader.cancel().catch(() => {})
    reader.releaseLock()
  }
  return Buffer.concat(chunks, size)
}

function missing(error: unknown) {
  return object(error).code === "ENOENT"
}

async function optionalStat(path: string) {
  return lstat(path).catch((error: unknown) => {
    if (!missing(error)) throw error
    return undefined
  })
}

export function gameIsRunning() {
  const windows = process.platform === "win32"
  const result = Bun.spawnSync(windows
    ? ["tasklist.exe", "/fo", "csv", "/nh"]
    : ["/bin/ps", "-ax", "-o", "comm="], { timeout: 5000 })
  if (result.exitCode !== 0) throw new Error("Impossibile verificare che WoW sia chiuso")
  return result.stdout.toString().split(/\r?\n/).some((line) => {
    const command = windows ? /^"([^"]+)"/.exec(line.trim())?.[1] : basename(line.trim())
    return command !== undefined && GAME_PROCESS.test(command)
  })
}

async function readRequest(file: string, now: number): Promise<Request | undefined> {
  const text = await readSavedVariables(file).catch((error: unknown) => {
    if (!missing(error)) throw error
  })
  if (!text) return
  const data = object(object(Lua.parse(text).BadbUIDB).data)
  const request = object(object(data.updates).request)
  const { id, from, version, at } = request
  if (typeof id !== "string" || !/^\d{1,12}-\d{1,10}$/.test(id) || !isVersion(from) || !isVersion(version)
    || !newer(version, from) || typeof at !== "number" || !Number.isSafeInteger(at)
    || at > now + 300 || now - at > 24 * 3600) return
  return { id, from, version, at }
}

function archiveFiles(data: Uint8Array) {
  let count = 0
  let total = 0
  const names = new Set<string>()
  return unzipSync(data, {
    filter: (entry) => {
      const path = entry.name
      // Estrazione solo come file regolari in una directory privata. Niente
      // path assoluti, traversal, alias di Windows o collisioni di maiuscole.
      const valid = /^BadbUI\/(?:[a-zA-Z0-9_-]+\/)*(?:[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*)?$/
      const reserved = /(?:^|\/)(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:[./]|$)/i
      const key = path.toLowerCase().replace(/\/$/, "")
      if (++count > 2000 || path.length > 200 || !valid.test(path) || reserved.test(path) || names.has(key)
        || !Number.isSafeInteger(entry.originalSize) || entry.originalSize < 0
        || (entry.compression === 0 && entry.size !== entry.originalSize)) {
        throw new Error("Archivio BadbUI con percorsi o voci non validi")
      }
      names.add(key)
      total += entry.originalSize
      if (total > MAX_EXPANDED_BYTES) throw new Error("Archivio BadbUI estratto troppo grande")
      return !path.endsWith("/")
    },
  })
}

async function lockInstall(path: string) {
  const acquire = () => open(path, "wx", 0o600)
  let file = await acquire().catch((error: unknown) => {
    if (object(error).code !== "EEXIST") throw error
  })
  if (!file) {
    const stats = await optionalStat(path)
    if (!stats?.isFile() || Date.now() - stats.mtimeMs < 120_000) return
    const owner = Number(await readFile(path, "utf8"))
    if (Number.isSafeInteger(owner) && owner > 0) {
      try {
        process.kill(owner, 0)
        return
      } catch (error) {
        if (object(error).code !== "ESRCH") return
      }
    }
    await rm(path, { force: true })
    file = await acquire().catch((error: unknown) => {
      if (object(error).code !== "EEXIST") throw error
    })
    if (!file) return
  }
  try {
    await file.writeFile(String(process.pid))
  } catch (error) {
    await rm(path, { force: true })
    throw error
  } finally {
    await file.close()
  }
  return () => rm(path, { force: true })
}

async function writeStatus(root: string, status: Status) {
  const lua = Lua.stringify("status", status)
  await atomic(join(root, STATUS_FILE), `-- Generato dal companion BadbUI.\nlocal _, ns = ...\nlocal ${lua}ns.Badb.UpdateStatus = status\n`, 0o644)
}

async function readReceipt(root: string): Promise<Receipt | undefined> {
  const file = join(root, STATUS_FILE)
  const stats = await optionalStat(file)
  if (!stats?.isFile() || stats.size > 4096) return
  const text = await readFile(file, "utf8")
  const data = /^-- Generato dal companion BadbUI\.\nlocal _, ns = \.\.\.\nlocal (status = [\s\S]+)ns\.Badb\.UpdateStatus = status\n$/.exec(text)
  if (!data) return
  try {
    const { id, result } = object(object(Lua.parse(data[1]!).status).receipt)
    if (typeof id === "string" && (result === "installed" || result === "failed" || result === "release_changed")) {
      return { id, result }
    }
  } catch {
    // Uno stato locale alterato verrà rigenerato al prossimo controllo.
  }
}

async function install(
  target: Paths, backup: string, release: Release, status: Status, request: Request,
  send: typeof fetch, isGameRunning: () => boolean,
) {
  const data = await fetchBytes(send, release.url, release.bytes)
  if (data.byteLength !== release.bytes || new Bun.CryptoHasher("sha256").update(data).digest("hex") !== release.sha256) {
    throw new Error("Il pacchetto BadbUI non corrisponde alla dimensione o allo SHA-256 del catalogo")
  }
  const files = archiveFiles(data)
  const tocFile = files["BadbUI/BadbUI.toc"]
  const toc = tocFile && new TextDecoder().decode(tocFile)
  if (!toc || tocVersion(toc) !== release.version) {
    throw new Error("Il pacchetto BadbUI non contiene il TOC atteso")
  }
  const stage = await mkdtemp(join(dirname(backup), ".badbui-stage-"))
  const next = join(stage, "BadbUI")
  try {
    for (const [name, content] of Object.entries(files)) {
      const file = join(stage, name)
      await mkdir(dirname(file), { recursive: true })
      await writeFile(file, content, { flag: "wx" })
    }
    // Conserva un bridge locale solo se la release include ancora quello stesso file.
    for (const path of SYNC_FILES) {
      if (!Object.hasOwn(files, `BadbUI/${path}`)) continue
      if (path === "Data/GuildSync.lua" && !declaresGuildExport(toc)) continue
      const file = join(target.addon, path)
      if ((await optionalStat(file))?.isFile()) await copyFile(file, join(next, path))
    }
    const receipt = { id: request.id, result: "installed" } as const
    await writeStatus(next, { ...status, installed: release.version, receipt })
    if (isGameRunning()) return
    if (tocVersion(await readFile(join(target.addon, "BadbUI.toc"), "utf8")) !== request.from) {
      throw new Error("L'installazione di BadbUI è cambiata durante il download")
    }
    await rm(backup, { recursive: true, force: true })
    await rename(target.addon, backup)
    try {
      await rename(next, target.addon)
    } catch (error) {
      await rename(backup, target.addon)
      throw error
    }
    return receipt
  } finally {
    await rm(stage, { recursive: true, force: true }).catch(() => {})
  }
}

export function createUpdater(
  target: Paths,
  { send = fetch, isGameRunning = gameIsRunning, now = () => Math.floor(Date.now() / 1000) } = {},
) {
  const clientInterface = dirname(dirname(target.addon))
  const backup = join(clientInterface, ".badbui-update-backup")
  const lock = join(clientInterface, ".badbui-update-lock")
  let checkedAt = -Infinity
  let release: Release | undefined
  let lastStatus: string | undefined
  let savedFingerprint: string | undefined
  let savedRequest: Request | undefined

  return async function update(): Promise<Receipt | undefined> {
    const releaseLock = await lockInstall(lock)
    if (!releaseLock) return
    try {
      if (!(await optionalStat(target.addon)) && (await optionalStat(backup))?.isDirectory()) {
        if (isGameRunning()) throw new Error("Chiudi WoW per ripristinare la cartella di BadbUI")
        // Riprende un'installazione interrotta tra i due rename.
        await rename(backup, target.addon)
      }
      return await updateLocked()
    } finally {
      await releaseLock()
    }
  }

  async function updateLocked(): Promise<Receipt | undefined> {
    if (!(await optionalStat(target.addon))?.isDirectory()) throw new Error("Cartella BadbUI non trovata")
    const installed = tocVersion(await readFile(join(target.addon, "BadbUI.toc"), "utf8"))
    const timestamp = now()
    let checkError: unknown
    if (timestamp - checkedAt >= CHECK_INTERVAL) {
      checkedAt = timestamp
      try {
        const catalog = await fetchBytes(send, "/downloads/release.json", 64 * 1024)
        release = releaseFrom(JSON.parse(catalog.toString("utf8")))
      } catch (error) {
        release = undefined
        checkError = error
      }
    }
    const receipt = await readReceipt(target.addon)
    const status: Status = { installed, latest: release?.version, checkedAt, receipt }
    if (release) {
      const saved = await optionalStat(target.saved)
      const fingerprint = saved ? `${saved.ino}:${saved.mtimeMs}:${saved.size}` : undefined
      if (savedFingerprint !== fingerprint) {
        savedRequest = await readRequest(target.saved, timestamp)
        savedFingerprint = fingerprint
      }
      const request = savedRequest
      if (request && timestamp - request.at <= 24 * 3600 && request.id !== receipt?.id && request.from === installed && !isGameRunning()) {
        if (request.version !== release.version) {
          status.receipt = { id: request.id, result: "release_changed" }
        } else {
          try {
            const result = await install(target, backup, release, status, request, send, isGameRunning)
            if (result) {
              lastStatus = undefined
              return result
            }
          } catch (error) {
            status.receipt = { id: request.id, result: "failed" }
            checkError = error
          }
        }
      }
    }
    const fingerprint = JSON.stringify(status)
    if (lastStatus !== fingerprint) {
      await writeStatus(target.addon, status)
      lastStatus = fingerprint
    }
    if (checkError) throw checkError
    return status.receipt?.id !== receipt?.id ? status.receipt : undefined
  }

}
