import { mkdtemp, cp, rm, mkdir } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
const root = resolve(import.meta.dir, "..")
const guild = Bun.argv[2] === "guild"
const folder = guild ? "BadbUI_Guild" : "BadbUI"
const archiveName = guild ? "BadbUI-Guild" : "BadbUI"
const source = join(root, guild ? "packages/guild-addon" : "packages/addon")
const toc = await Bun.file(join(source, `${folder}.toc`)).text()
const version = toc.match(/^## Version:\s*([\d.]+)\s*$/m)?.[1]
if (!version) throw new Error(`Missing version in ${folder}.toc`)
const stage = await mkdtemp(join(tmpdir(), "badb-package-"))
try {
  const target = join(stage, folder)
  await cp(source, target, {
    recursive: true,
    filter: (path) => !["tests", "scripts", "docs", ".DS_Store"].includes(path.split("/").at(-1)!),
  })
  // Replace generated state with empty files in distributable builds.
  if (guild) {
    await Bun.write(join(target, "Data/GuildSync.lua"), "-- Written by the guild companion.\nBadbUI_GuildSync = nil\n")
  } else {
    await Bun.write(join(target, "Data/ChatbotSync.lua"), "-- Written by the optional local chatbot runtime.\nBadbUI_ChatbotSync = nil\n")
    await Bun.write(join(target, "Data/UpdateStatus.lua"), "-- Written by the BadbUI updater.\n")
  }
  await mkdir(join(root, "dist"), { recursive: true })
  const destination = join(root, `dist/${archiveName}-${version}.zip`)
  await rm(destination, { force: true })
  const result = Bun.spawnSync(["zip", "-qr", destination, folder], { cwd: stage })
  if (result.exitCode !== 0) throw new Error(result.stderr.toString())
  console.log(destination)
} finally {
  await rm(stage, { recursive: true, force: true })
}
