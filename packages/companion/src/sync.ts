import { Lua, Addon } from "@badb/core"
export const decode = Addon.decode
import { mkdir, readFile, rename, writeFile, stat } from "node:fs/promises"
import { dirname, join } from "node:path"
import type { Client } from "@badb/sdk"

export async function atomic(path: string, content: string, mode = 0o600) {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.${crypto.randomUUID()}.tmp`
  await writeFile(temporary, content, { mode })
  await rename(temporary, path)
}
export type Paths = { saved: string; addon: string }
export function paths(wow: string, account: string): Paths {
  if (!account || /[\\/]|^\.{1,2}$/.test(account)) throw new Error("Account WTF non valido")
  return {
    saved: join(wow, "WTF", "Account", account, "SavedVariables", "BadbUI.lua"),
    addon: join(wow, "Interface", "AddOns", "BadbUI"),
  }
}
export async function readSavedVariables(file: string) {
  const before = await stat(file)
  if (before.size > 8_000_000) throw new Error("SavedVariables troppo grandi (limite 8 MB)")
  const text = await readFile(file, "utf8")
  const after = await stat(file)
  if (before.ino !== after.ino || before.mtimeMs !== after.mtimeMs || before.size !== after.size)
    throw new Error("Il gioco sta ancora scrivendo il file: riprova")
  return text
}
export async function synchronize(client: Client, paths: Paths) {
  // Non si creano cartelle di gioco se il percorso è sbagliato.
  await stat(join(paths.addon, "BadbUI.toc"))
  const input = decode(await readSavedVariables(paths.saved))
  const result = await client.addon.sync(input)
  // Rigenera dai dati tipizzati ricevuti; non scrive codice Lua restituito da un server remoto.
  const lua = `-- Dati del server Badb; caricati al prossimo /reload.\n${Lua.stringify("BadbUI_GuildSync", result.bundle)}`
  await atomic(join(paths.addon, "Data", "GuildSync.lua"), lua, 0o644)
  return result.bundle
}
