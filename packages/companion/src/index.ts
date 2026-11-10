#!/usr/bin/env bun
import { parseArgs } from "node:util"
import { resolve, join } from "node:path"
import { homedir } from "node:os"
import { chmod } from "node:fs/promises"
import { createClient, DEFAULT_SERVER_URL } from "@badb/sdk"
import { atomic, paths, synchronize, type Paths } from "./sync"

type Settings = { server: string; token: string; paths: Paths }
const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  allowPositionals: true,
  options: {
    wow: { type: "string" },
    account: { type: "string" },
    server: { type: "string" },
    config: { type: "string" },
    help: { type: "boolean", short: "h" },
  },
})
const file = resolve(values.config ?? join(homedir(), ".config", "badb", "companion.json"))
const command = positionals[0]
async function main() {
  if (!command || values.help) {
    console.log(`Fratelli di Azeroth — companion — WoW Forever → server → sito/app/Discord

login <codice> --wow "<cartella client>" --account "<account WTF>" [--server ${DEFAULT_SERVER_URL}]
sync         Sincronizza una volta; i dati rientrano in gioco al prossimo /reload
watch        Sincronizza ogni 5 secondi, una richiesta alla volta
logout       Revoca il token e cancella la configurazione

--config <file>  Configurazione privata (default ~/.config/badb/companion.json)
L'addon deve essere installato in Interface/AddOns/BadbUI. Non si modifica mai il file SavedVariables.`)
    return
  }
  if (command === "login") {
    if (!positionals[1] || !values.wow || !values.account)
      throw new Error("Servono codice, --wow e --account. Usa --help")
    const server = values.server ?? process.env.BADB_SERVER ?? DEFAULT_SERVER_URL
    const url = new URL(server)
    if (
      url.protocol !== "https:" &&
      !(url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname))
    )
      throw new Error("Usa HTTPS per il server remoto")
    const target = paths(resolve(values.wow), values.account)
    if (!(await Bun.file(join(target.addon, "BadbUI.toc")).exists()))
      throw new Error("Addon non trovato. Installa BadbUI nella cartella client indicata")
    const client = createClient({ url: server })
    const session = await client.auth.redeem({ code: positionals[1], label: "Companion WoW Forever" })
    const settings: Settings = { server, token: session.token, paths: target }
    await atomic(file, JSON.stringify(settings, null, 2))
    await chmod(file, 0o600)
    console.log(`Collegato come ${session.user.name}. Ora: bun run --cwd packages/companion start watch`)
    return
  }
  if (!["sync", "watch", "logout"].includes(command!)) throw new Error("Comando sconosciuto. Usa --help")
  if (!(await Bun.file(file).exists())) throw new Error("Companion non collegato. Esegui login")
  const settings = (await Bun.file(file).json()) as Settings
  const client = createClient({ url: settings.server, token: settings.token })
  if (command === "logout") {
    await client.auth.logout()
    await Bun.file(file).delete()
    console.log("Token revocato e configurazione rimossa")
    return
  }
  const once = async () => {
    const bundle = await synchronize(client, settings.paths)
    console.log(
      `${new Date().toISOString()} · revisione ${bundle.rev} · ${bundle.applied.length} azioni ricevute. Dati pronti per /reload.`,
    )
    for (const rejection of bundle.rejected) console.error(`${rejection.id}: ${rejection.error}`)
  }
  if (command === "sync") return once()
  let running = true
  process.on("SIGINT", () => {
    running = false
  })
  process.on("SIGTERM", () => {
    running = false
  })
  console.log("In ascolto. Esporta con /reload o logout, attendi “Dati pronti”, poi /reload per caricare la risposta.")
  while (running) {
    await once().catch((e: Error) => console.error(e.message))
    if (running) await Bun.sleep(5000)
  }
}
main().catch((error: Error) => {
  console.error(error.message)
  process.exitCode = 1
})
