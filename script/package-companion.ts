import { mkdtemp, mkdir, rm, cp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
const root = resolve(import.meta.dir, "..")
const stage = await mkdtemp(join(tmpdir(), "fratelli-companion-"))
try {
  const directory = join(stage, "Fratelli-Companion")
  await mkdir(directory)
  const build = await Bun.build({
    entrypoints: [join(root, "packages/companion/src/index.ts")],
    target: "bun",
    minify: false,
    sourcemap: "none",
  })
  if (!build.success) throw new AggregateError(build.logs, "Compilazione companion fallita")
  await Bun.write(join(directory, "companion.mjs"), build.outputs[0]!)
  await Bun.write(
    join(directory, "LEGGIMI.txt"),
    `FRATELLI DI AZEROTH — COMPANION WOW FOREVER\n\nRichiede Bun: https://bun.sh\n\n1. Dal sito https://badb-guild.nikoemme-work.workers.dev crea/accedi al tuo account.\n2. Profilo → Collega addon: copia il codice monouso.\n3. In questa cartella esegui:\n\nbun companion.mjs login CODICE --wow "<cartella client Forever>" --account "<account in WTF/Account>"\nbun companion.mjs watch\n\nIn gioco: /badb gilda. /reload per esportare; attendi Dati pronti nel companion, poi /reload per importare.\nIl companion non modifica mai SavedVariables. Non contiene credenziali.\n`,
  )
  const output = join(root, "dist/Fratelli-Companion-0.3.0.zip")
  await mkdir(join(root, "dist"), { recursive: true })
  await rm(output, { force: true })
  const result = Bun.spawnSync(["zip", "-qr", output, "Fratelli-Companion"], { cwd: stage })
  if (result.exitCode) throw new Error(result.stderr.toString())
  console.log(output)
} finally {
  await rm(stage, { recursive: true, force: true })
}
