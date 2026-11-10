// Genera il codice del primo capogilda senza inserirlo nel repository o negli argomenti della shell.
import { randomBytes } from "node:crypto"
import { mkdir, readFile, writeFile, chmod } from "node:fs/promises"
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"
import { resolve } from "node:path"
const root = fileURLToPath(new URL("../", import.meta.url))
const directory = resolve(root, ".cloudflare")
const file = resolve(directory, "setup-key.txt")
await mkdir(directory, { recursive: true, mode: 0o700 })
let key
try {
  key = (await readFile(file, "utf8")).trim()
} catch (error) {
  if (error.code !== "ENOENT") throw error
}
if (!key) {
  key = randomBytes(24).toString("hex")
  await writeFile(file, key + "\n", { mode: 0o600, flag: "wx" })
}
await chmod(file, 0o600)
const child = spawn(
  process.execPath,
  [resolve(root, "node_modules/wrangler/bin/wrangler.js"), "secret", "put", "BADB_SETUP_KEY"],
  { cwd: root, stdio: ["pipe", "inherit", "inherit"] },
)
child.stdin.end(key + "\n")
const code = await new Promise((resolve, reject) => {
  child.once("error", reject)
  child.once("close", resolve)
})
if (code !== 0) throw new Error(`Impossibile configurare il codice installazione: uscita ${code}`)
console.log(`Codice installazione salvato privatamente in ${file}`)
