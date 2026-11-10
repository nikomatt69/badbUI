import { SlashCommandBuilder } from "discord.js"
export const commands = [
  new SlashCommandBuilder()
    .setName("collega")
    .setDescription("Collega Discord al tuo account Fratelli di Azeroth con un codice del sito")
    .addStringOption((o) => o.setName("codice").setDescription("Codice monouso del sito").setRequired(true)),
  new SlashCommandBuilder()
    .setName("disponibilita")
    .setDescription("Aggiorna quando puoi giocare questa settimana")
    .addStringOption((o) =>
      o.setName("testo").setDescription("Es. ci sono mercoledì dalle 20 alle 23").setRequired(true).setMaxLength(200),
    ),
  new SlashCommandBuilder().setName("raid").setDescription("Mostra i prossimi raid e i codici per prenotarti"),
  new SlashCommandBuilder()
    .setName("prenota")
    .setDescription("Conferma o modifica la tua presenza a un raid")
    .addStringOption((o) => o.setName("evento").setDescription("Codice mostrato da /raid").setRequired(true))
    .addStringOption((o) =>
      o
        .setName("presenza")
        .setDescription("La tua risposta")
        .setRequired(true)
        .addChoices(
          { name: "Ci sono", value: "yes" },
          { name: "Forse", value: "maybe" },
          { name: "Non ci sono", value: "no" },
        ),
    )
    .addStringOption((o) =>
      o.setName("personaggio").setDescription("Nome del tuo personaggio; altrimenti usa il principale"),
    ),
  new SlashCommandBuilder()
    .setName("armory")
    .setDescription("Cerca un personaggio della gilda")
    .addStringOption((o) => o.setName("nome").setDescription("Nome completo in gioco").setRequired(true)),
  new SlashCommandBuilder().setName("boss").setDescription("Elenca i boss e le note tattiche della gilda"),
].map((c) => c.toJSON())
