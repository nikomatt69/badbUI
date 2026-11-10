import { mkdtemp, cp, rm, mkdir } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
const root = resolve(import.meta.dir, "..")
const toc = await Bun.file(join(root, "packages/addon/BadbUI.toc")).text()
const version = toc.match(/^## Version:\s*([\d.]+)\s*$/m)?.[1]
if (!version) throw new Error("Versione addon mancante nel TOC")
const stage = await mkdtemp(join(tmpdir(), "badb-package-"))
try {
  const target = join(stage, "BadbUI")
  await cp(join(root, "packages/addon"), target, {
    recursive: true,
    filter: (path) => !["tests", "scripts", "docs"].includes(path.split("/").at(-1)!),
  })
  // Il pacchetto distribuito non deve mai includere lo snapshot privato di un giocatore.
  await Bun.write(join(target, "Data/GuildSync.lua"), "-- Popolato dal companion Badb.\nBadbUI_GuildSync = nil\n")
  await Bun.write(join(target, "Data/ChatbotSync.lua"), "-- Filled by the local nikcli embedded runtime.\nBadbUI_ChatbotSync = nil\n")
  await mkdir(join(root, "dist"), { recursive: true })
  const destination = join(root, `dist/BadbUI-${version}.zip`)
  await rm(destination, { force: true })
  const result = Bun.spawnSync(["zip", "-qr", destination, "BadbUI"], { cwd: stage })
  if (result.exitCode !== 0) throw new Error(result.stderr.toString())
  console.log(destination)
} finally {
  await rm(stage, { recursive: true, force: true })
}
