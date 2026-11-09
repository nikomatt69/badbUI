// Contenuto iniziale: i tre gruppi raid, un boss d'esempio e le pagine di benvenuto.
// Si applica una sola volta (su database vuoto, all'avvio) oppure a mano con `bun run seed`.
import { Game, Tactics } from "@badb/core"
import { config, id, type Ctx } from "./ctx"
import { context } from "./server"

const groups = [
  { name: "Gruppo Mattina", slot: "mattina", start: 10 * 60, days: [5, 6] },
  { name: "Gruppo Pomeriggio", slot: "pomeriggio", start: 15 * 60, days: [5, 6] },
  { name: "Gruppo Sera", slot: "sera", start: 21 * 60, days: [2, 3, 6] },
] as const

// Unico boss precompilato: l'incontro e' quello storico e Forever puo' averlo rivisto (confidenza B).
// Gli altri raid del primo tier non hanno boss qui: li aggiungono gli ufficiali dal sito, con le tattiche reali.
const onyxia: Tactics.Weights = {
  "tank-single": 2,
  threat: 3,
  "add-tank": 2,
  aoe: 2,
  ranged: 2,
  mobility: 2,
  fear: 3,
  "raid-heal": 2,
  "tank-heal": 2,
  st: 2,
}

const welcome = `Benvenuto sul sito della gilda.

## Cosa trovi qui

- **Armory**: i personaggi della gilda, con l'equipaggiamento letto dall'addon.
- **Disponibilità**: segna quando ci sei questa settimana, dal sito, dall'app, da Discord o dal gioco.
- **Raid**: tre gruppi (mattina, pomeriggio, sera). Ti prenoti per data e vedi chi c'è.
- **Tattiche**: per ogni boss, le classi più adatte in base alla tattica.
- **Guide** e **Blog**: scritti dagli ufficiali.

Se non fai ancora parte della gilda, crea un account e compila la **candidatura**.`

const addon = `L'addon **BadbUI** porta in gioco il calendario dei raid, la disponibilità e le tattiche.

## Perché serve il companion

Il client di gioco non permette agli addon di collegarsi a internet. Il **companion** è un piccolo
programma che gira sul tuo PC: legge quello che l'addon salva, lo invia al server e riscrive il file
dati che l'addon carica al prossimo \`/reload\`.

## Collegamento

1. Sul sito apri **Profilo → Collega addon** e copia il codice.
2. Nella cartella del progetto: \`bun run --cwd packages/companion start login <codice> --wow "<cartella di WoW>"\`.
3. Lascia attivo \`bun run --cwd packages/companion start watch\` mentre giochi.
4. In gioco: \`/badb gilda\`. Dopo una prenotazione fai \`/reload\`: il companion la invia e aggiorna i dati.

Chi non usa il companion riceve comunque i dati in gioco dai compagni di gilda che lo usano.`

export function seed(ctx: Ctx) {
  ctx.db.transaction(() => {
    for (const group of groups) {
      const raid = Game.raids[0]!
      ctx.db.run(
        "INSERT INTO raid_group (id, name, slot, raid, days, start, comp, position) VALUES (?, ?, ?, ?, ?, ?, ?, (SELECT COUNT(*) FROM raid_group))",
        [id(), group.name, group.slot, raid.id, JSON.stringify(group.days), group.start, JSON.stringify(raid.comp)],
      )
    }
    ctx.db.run("INSERT INTO boss (id, raid, name, position, weights, notes, confidence) VALUES (?, 'onyxia', 'Onyxia', 0, ?, ?, 'B')", [
      id(),
      JSON.stringify(onyxia),
      "Pesi basati sull'incontro storico: fase a terra, fase in volo con cuccioli, fase finale con paura. Da verificare su Forever e correggere qui.",
    ])
    const post = (kind: string, slug: string, title: string, excerpt: string, body: string) =>
      ctx.db.run("INSERT INTO post (id, kind, slug, title, excerpt, body, category, published, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
        id(),
        kind,
        slug,
        title,
        excerpt,
        body,
        kind === "guide" ? "Addon" : "Gilda",
        ctx.now(),
        ctx.now(),
        ctx.now(),
      ])
    post("blog", "benvenuti", "Benvenuti sul sito della gilda", "Armory, disponibilità, raid e tattiche in un posto solo.", welcome)
    post("guide", "collegare-addon", "Collegare l'addon al sito", "Come funziona il companion e come collegarlo in due minuti.", addon)
    ctx.db.run("INSERT INTO setting (key, value) VALUES ('seeded', '1') ON CONFLICT(key) DO NOTHING")
  })()
}

/** All'avvio: semina solo se il database non e' mai stato seminato. */
export function ensure(ctx: Ctx) {
  if (ctx.db.query("SELECT 1 FROM setting WHERE key = 'seeded'").get()) return false
  seed(ctx)
  return true
}

if (import.meta.main) {
  const ctx = context(config())
  console.log(ensure(ctx) ? "Contenuto iniziale creato" : "Database già inizializzato: nessuna modifica")
  ctx.db.close()
}
