import { mkdtemp, mkdir, rm, cp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
const root = resolve(import.meta.dir, "..")
const stage = await mkdtemp(join(tmpdir(), "badb-chat-package-"))
try {
  const directory = join(stage, "BadbUI-Chatbot")
  await mkdir(directory)
  const build = await Bun.build({
    entrypoints: [join(root, "packages/wow-chat/src/index.ts")],
    target: "bun",
    external: ["@nikcli-ai/sdk-next", "effect"],
  })
  if (!build.success) throw new AggregateError(build.logs, "Chatbot build failed")
  await Bun.write(join(directory, "chat.mjs"), build.outputs[0]!)
  await Bun.write(
    join(directory, "package.json"),
    JSON.stringify(
      { private: true, type: "module", dependencies: { "@nikcli-ai/sdk-next": "1.428.0", effect: "4.0.0-rc.112" } },
      null,
      2,
    ),
  )
  await cp(join(root, "packages/wow-chat/README.md"), join(directory, "README.md"))
  const output = join(root, "dist/BadbUI-Chatbot-0.3.0.zip")
  await mkdir(join(root, "dist"), { recursive: true })
  await rm(output, { force: true })
  const zip = Bun.spawnSync(["zip", "-qr", output, "BadbUI-Chatbot"], { cwd: stage })
  if (zip.exitCode) throw new Error(zip.stderr.toString())
  console.log(output)
} finally {
  await rm(stage, { recursive: true, force: true })
}
