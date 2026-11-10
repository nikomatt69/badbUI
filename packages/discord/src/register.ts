import { REST, Routes } from "discord.js"
import { commands } from "./commands"
const token = process.env.DISCORD_TOKEN
const app = process.env.DISCORD_APP_ID
const guild = process.env.DISCORD_GUILD_ID
if (!token || !app || !guild) throw new Error("Imposta DISCORD_TOKEN, DISCORD_APP_ID e DISCORD_GUILD_ID")
await new REST({ version: "10" }).setToken(token).put(Routes.applicationGuildCommands(app, guild), { body: commands })
console.log("Comandi Fratelli di Azeroth registrati nella gilda Discord configurata")
