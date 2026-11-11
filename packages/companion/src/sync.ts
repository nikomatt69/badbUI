import { Lua, Addon } from "@badb/core"
import { mkdir, readFile, rename, rm, writeFile, stat } from "node:fs/promises"
import { dirname, join } from "node:path"
import type { Client } from "@badb/sdk"

export const decode = Addon.decode

export async function atomic(path: string, content: string, mode = 0o600, beforeRename?: () => Promise<void>) {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.${crypto.randomUUID()}.tmp`
  try {
    await writeFile(temporary, content, { mode, flag: "wx" })
    await beforeRename?.()
    await rename(temporary, path)
  } catch (error) {
    await rm(temporary, { force: true }).catch(() => {})
    throw error
  }
}
export type Paths = { saved: string; addon: string }
export function paths(wow: string, account: string): Paths {
  if (!account || /[\\/]|^\.{1,2}$/.test(account)) throw new Error("Account WTF non valido")
  return {
    saved: join(wow, "WTF", "Account", account, "SavedVariables", "BadbUI.lua"),
    addon: join(wow, "Interface", "AddOns", "BadbUI"),
  }
}
function optional<T>(read: Promise<T>) {
  return read.catch((error: NodeJS.ErrnoException) => {
    if (error.code !== "ENOENT") throw error
    return undefined
  })
}

export function declaresGuildExport(toc: string) {
  return [...toc.matchAll(/^##[ \t]+SavedVariables:[ \t]*([^\r\n]*)/gmi)]
    .some((match) => match[1]!.split(",").some((name) => name.trim() === "BadbUI_GuildExport"))
}

export async function guildPaths(target: Paths): Promise<Paths & { legacySaved?: string }> {
  const core = await optional(readFile(join(target.addon, "BadbUI.toc"), "utf8"))
  if (core === undefined) throw new Error("Addon non trovato. Installa BadbUI nella cartella client indicata")

  const addon = join(dirname(target.addon), "BadbUI_Guild")
  const guild = await optional(readFile(join(addon, "BadbUI_Guild.toc"), "utf8"))
  if (guild !== undefined) {
    if (!declaresGuildExport(guild)) throw new Error("TOC di BadbUI_Guild non valido. Reinstalla il modulo gilda")
    return { addon, saved: join(dirname(target.saved), "BadbUI_Guild.lua"), legacySaved: target.saved }
  }
  if (declaresGuildExport(core)) return target
  throw new Error("Installa BadbUI_Guild per sincronizzare i dati di gilda")
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
async function guildInput(guild: Awaited<ReturnType<typeof guildPaths>>) {
  const text = await optional(readSavedVariables(guild.saved))
  if (text !== undefined) return decode(text)
  if (guild.legacySaved) {
    const old = await optional(readSavedVariables(guild.legacySaved))
    if (old !== undefined && Lua.parse(old).BadbUI_GuildExport) {
      const { actions, characters, client, version } = decode(old)
      if (actions.length > 0) {
        const signedUp = new Set(actions.flatMap((action) => action.type === "signup" ? [action.character] : []))
        return { actions, characters: characters.filter((character) => signedUp.has(character.name)), client, version }
      }
    }
    throw new Error("Entra in gioco con BadbUI_Guild attivo ed esegui /reload per esportare i dati")
  }
  throw new Error("Entra in gioco con BadbUI attivo ed esegui /reload per esportare i dati")
}

export async function synchronize(client: Client, target: Paths) {
  const guild = await guildPaths(target)
  const input = await guildInput(guild)
  const result = await client.addon.sync(input)
  // Rigenera dai dati tipizzati ricevuti; non scrive codice Lua restituito da un server remoto.
  const lua = `-- Dati del server Badb; caricati al prossimo /reload.\n${Lua.stringify("BadbUI_GuildSync", result.bundle)}`
  await atomic(join(guild.addon, "Data", "GuildSync.lua"), lua, 0o644, async () => {
    const current = await guildPaths(target)
    if (current.addon !== guild.addon) throw new Error("L'installazione gilda è cambiata. Riprova la sincronizzazione")
  })
  return result.bundle
}
