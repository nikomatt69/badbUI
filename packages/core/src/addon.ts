import * as Lua from "./lua"
import * as Schema from "./schema"

/** Il parser accetta soltanto tabelle di dati. Non esegue il file Lua del client. */
export function decode(text: string) {
  const globals = Lua.parse(text)
  const value = globals.BadbUI_GuildExport
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("BadbUI_GuildExport assente: entra in gioco con l’addon aggiornato e fai /reload")
  const array = (value: Lua.LuaValue | undefined) => (value && typeof value === "object" ? Object.values(value) : [])
  const raw = value as Record<string, Lua.LuaValue>
  return Schema.AddonSync.parse({
    ...raw,
    characters: array(raw.characters).map((c) =>
      c && typeof c === "object" && !Array.isArray(c)
        ? { ...c, gear: array(c.gear), professions: array(c.professions) }
        : c,
    ),
    roster: array(raw.roster),
    actions: array(raw.actions),
  })
}
