import { Client, GatewayIntentBits, MessageFlags, escapeMarkdown } from "discord.js"
import { createClient, DEFAULT_SERVER_URL } from "@badb/sdk"
import { handle } from "./handle"
const token = process.env.DISCORD_TOKEN
const secret = process.env.BADB_BOT_SECRET
const guild = process.env.DISCORD_GUILD_ID
if (!token || !secret || !guild) throw new Error("Imposta DISCORD_TOKEN, BADB_BOT_SECRET e DISCORD_GUILD_ID")
const api = createClient({ url: process.env.BADB_SERVER ?? DEFAULT_SERVER_URL, bot: secret })
const discord = new Client({ intents: [GatewayIntentBits.Guilds] })
discord.once("clientReady", () => console.log("Bot Fratelli di Azeroth collegato"))
discord.on("error", (error) => console.error(error.message))
discord.on("interactionCreate", async (interaction) => {
  if (!interaction.isChatInputCommand() || interaction.guildId !== guild) return
  await interaction.deferReply({ flags: MessageFlags.Ephemeral })
  try {
    const args = Object.fromEntries(
      interaction.options.data.map((o) => [o.name, typeof o.value === "string" ? o.value : null]),
    )
    const content = await handle(api, {
      name: interaction.commandName,
      user: interaction.user.id,
      username: interaction.user.username,
      args,
    })
    await interaction.editReply({ content: escapeMarkdown(content).slice(0, 1900), allowedMentions: { parse: [] } })
  } catch (error) {
    await interaction.editReply({
      content: escapeMarkdown(error instanceof Error ? error.message : "Operazione non riuscita").slice(0, 1900),
      allowedMentions: { parse: [] },
    })
  }
})
process.on("SIGINT", () => discord.destroy())
process.on("SIGTERM", () => discord.destroy())
await discord.login(token)
