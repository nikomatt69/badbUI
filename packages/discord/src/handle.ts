import { Game } from "@badb/core"
import type { Client } from "@badb/sdk"
export type Command = { name: string; user: string; username: string; args: Record<string, string | null> }
export async function handle(api: Client, command: Command) {
  const user = api.as(command.user)
  const text = (key: string) => command.args[key] ?? ""
  switch (command.name) {
    case "collega": {
      const linked = await api.auth.discord({
        code: text("codice"),
        discordId: command.user,
        discordName: command.username,
      })
      return `Collegato come ${linked.name}. Puoi usare /disponibilita e /prenota.`
    }
    case "disponibilita": {
      const result = await user.availability.say(text("testo"))
      return `Disponibilità aggiornata · settimana ${result.week}.\n${Game.dayShort
        .map(
          (d, i) =>
            `${d}: ${
              Game.slotList
                .filter((_, s) => result.entry.mask[i * 3 + s] === "1")
                .map((s) => s.label)
                .join(", ") || "—"
            }`,
        )
        .join("\n")}`
    }
    case "raid": {
      const events = await api.event.list()
      return events.length
        ? events
            .slice(0, 12)
            .map(
              (e) =>
                `${e.title} · ${e.date} ${String(Math.floor(e.start / 60)).padStart(2, "0")}:${String(e.start % 60).padStart(2, "0")} Europe/Rome · ${e.signups.filter((s) => s.status === "yes").length} presenti · ${e.status}\nCodice: ${e.id}`,
            )
            .join("\n\n")
        : "Nessun raid in programma."
    }
    case "prenota": {
      const me = await user.auth.me()
      const character = text("personaggio")
        ? me.characters.find((c) => c.name.toLowerCase() === text("personaggio").toLowerCase())
        : (me.characters.find((c) => c.main) ?? me.characters[0])
      if (!character) throw new Error("Aggiungi o sincronizza il personaggio dal sito o dall’addon.")
      const status = text("presenza")
      if (status !== "yes" && status !== "maybe" && status !== "no") throw new Error("Presenza non valida")
      const event = await user.event.signup(text("evento"), { status, characterId: character.id })
      return `${character.name} · ${event.title}: ${status === "yes" ? "presente" : status === "no" ? "assente" : "forse"}.`
    }
    case "armory": {
      const character = await api.character.get(text("nome"))
      return `${character.name} · livello ${character.level} · ${Game.classes[character.cls].label} · ${Game.findSpec(character.cls, character.spec)?.label ?? "Spec non rilevata"}\n${character.gear.length} oggetti · ${character.source === "addon" ? "dati ricevuti dall’addon Forever" : "scheda manuale"}\nAggiornato: ${new Date(character.updated).toISOString()}`
    }
    case "boss": {
      const bosses = await api.boss.list()
      return bosses.length
        ? bosses
            .map(
              (b) =>
                `${b.name} · ${Game.findRaid(b.raid)?.label} · confidenza ${b.confidence}\n${b.notes.slice(0, 400)}`,
            )
            .join("\n\n")
        : "Nessuna tattica configurata dagli ufficiali."
    }
    default:
      throw new Error("Comando sconosciuto")
  }
}
