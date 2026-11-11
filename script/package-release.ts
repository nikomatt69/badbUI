import { mkdir, cp } from "node:fs/promises"
import { resolve, join } from "node:path"
const root = resolve(import.meta.dir, "..")
const destination = join(root, "packages/web/public/downloads")
await mkdir(destination, { recursive: true })
async function addonVersion(path: string) {
  const toc = await Bun.file(join(root, path)).text()
  const version = toc.match(/^## Version:\s*([\d.]+)\s*$/m)?.[1]
  if (!version) throw new Error(`Missing version in ${path}`)
  return version
}
const version = await addonVersion("packages/addon/BadbUI.toc")
const guildVersion = await addonVersion("packages/guild-addon/BadbUI_Guild.toc")
const companionVersion = (await Bun.file(join(root, "packages/companion/package.json")).json()).version as string
const chatVersion = (await Bun.file(join(root, "packages/wow-chat/package.json")).json()).version as string
const files = [
  { kind: "addon", version, file: `BadbUI-${version}.zip`, latest: "BadbUI-latest.zip" },
  { kind: "guild-addon", version: guildVersion, file: `BadbUI-Guild-${guildVersion}.zip`, latest: "BadbUI-Guild-latest.zip" },
  { kind: "companion", version: companionVersion, file: `Fratelli-Companion-${companionVersion}.zip`, latest: "Fratelli-Companion-latest.zip" },
  { kind: "chatbot", version: chatVersion, file: `BadbUI-Chatbot-${chatVersion}.zip`, latest: "BadbUI-Chatbot-latest.zip" },
]
const artifacts = []
for (const { kind, version: artifactVersion, file, latest } of files) {
  const source = Bun.file(join(root, "dist", file))
  const data = await source.arrayBuffer()
  await cp(source.name!, join(destination, file))
  await cp(source.name!, join(destination, latest))
  artifacts.push({
    kind,
    version: artifactVersion,
    name: file,
    url: `/downloads/${file}`,
    latestUrl: `/downloads/${latest}`,
    bytes: data.byteLength,
    sha256: new Bun.CryptoHasher("sha256").update(data).digest("hex"),
  })
}
const scan = Bun.spawnSync(["luajit", "-", join(root, "packages/addon")], {
  stdin: new TextEncoder().encode(`local root = arg[1]\nlocal Mock = dofile(root .. "/tests/wow_mock.lua")\nMock.LoadAddon(root, "BadbUI.toc")\nfor _, line in ipairs(Mock.chat) do assert(not line:find("Macros", 1, true), line) end\nprint(#BadbUI.Macros.order)\n`),
})
const macroCount = Number(scan.stdout.toString().trim())
if (scan.exitCode !== 0 || !Number.isSafeInteger(macroCount) || macroCount < 6000)
  throw new Error("Macro catalog verification failed: " + scan.stderr.toString())
await Bun.write(join(destination, "release.json"), JSON.stringify({ version, macroCount, classes: 9, specializations: 27, artifacts }, null, 2) + "\n")
console.log(`Prepared ${artifacts.length} public downloads without private data or credentials.`)
