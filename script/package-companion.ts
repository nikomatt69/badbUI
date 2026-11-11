import { mkdtemp, mkdir, rm, cp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
const root = resolve(import.meta.dir, "..")
const { version } = await Bun.file(join(root, "packages/companion/package.json")).json()
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
    `FRATELLI DI AZEROTH — COMPANION WOW FOREVER\n\nRichiede Bun: https://bun.sh\n\nAGGIORNARE BADBUI\nbun companion.mjs updates --wow "<cartella client Forever>" --account "<account in WTF/Account>"\n\nIn gioco: /reload, poi /badb update. Conferma la versione proposta ed esci da WoW.\nQuando il companion conferma l'installazione, puoi riaprire il gioco.\n\nSINCRONIZZARE LA GILDA\n1. Dal sito https://badb-guild.nikoemme-work.workers.dev crea/accedi al tuo account.\n2. Profilo → Collega addon: copia il codice monouso.\n3. In questa cartella esegui:\n\nbun companion.mjs login CODICE --wow "<cartella client Forever>" --account "<account in WTF/Account>"\nbun companion.mjs watch\n\nIn gioco: /badb gilda. /reload per esportare; attendi Dati pronti nel companion, poi /reload per importare.\nwatch gestisce anche gli aggiornamenti. Il companion non modifica mai SavedVariables.\n`,
  )
  const output = join(root, `dist/Fratelli-Companion-${version}.zip`)
  await mkdir(join(root, "dist"), { recursive: true })
  await rm(output, { force: true })
  const result = Bun.spawnSync(["zip", "-qr", output, "Fratelli-Companion"], { cwd: stage })
  if (result.exitCode) throw new Error(result.stderr.toString())
  console.log(output)
} finally {
  await rm(stage, { recursive: true, force: true })
}
