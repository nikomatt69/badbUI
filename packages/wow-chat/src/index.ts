#!/usr/bin/env bun
import { parseArgs } from "node:util"
import { resolve, join } from "node:path"
import { homedir } from "node:os"
import { mkdir, rm } from "node:fs/promises"
import { Bridge } from "./bridge"
import { createEngine } from "./engine"

const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    wow: { type: "string" },
    account: { type: "string" },
    runtime: { type: "string" },
    once: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  },
})
async function main() {
  if (values.help) {
    console.log(`BadbUI Chatbot · nikcli embedded SDK
Usage: bun run chat:dev --wow "<WoW client folder>" --account "<WTF account>"
--runtime <folder>  Private nikcli instance (default ~/.config/badb/wow-chat)
--once              Process the queue once, then exit

In WoW: /badb chat, Settings → Refresh providers, choose provider/model,
attach quests, Send & reload, wait for Reply ready, then Check replies.
Uses nikcli's provider authentication store. No guild login is required.`)
    return
  }
  if (!values.wow || !values.account || /[\\/]|^\.{1,2}$/.test(values.account))
    throw new Error("Provide --wow and a valid --account. See --help.")
  const directory = resolve(values.runtime ?? join(homedir(), ".config", "badb", "wow-chat"))
  const wow = resolve(values.wow)
  const addon = join(wow, "Interface", "AddOns", "BadbUI")
  if (!(await Bun.file(join(addon, "BadbUI.toc")).exists()))
    throw new Error("BadbUI was not found in the selected WoW client folder.")
  await mkdir(directory, { recursive: true, mode: 0o700 })
  const lock = join(directory, "bridge.lock")
  try {
    await mkdir(lock)
  } catch {
    throw new Error(`Another AI runtime may be active. If it stopped unexpectedly, remove ${lock} before restarting.`)
  }
  let running = true
  process.on("SIGINT", () => {
    running = false
  })
  process.on("SIGTERM", () => {
    running = false
  })
  try {
    const engine = await createEngine(directory)
    const bridge = new Bridge(
      join(wow, "WTF", "Account", values.account, "SavedVariables", "BadbUI.lua"),
      addon,
      engine,
    )
    console.log("Chatbot ready · open /badb chat in WoW. Providers and models are configured in the addon.")
    do {
      try {
        const count = await bridge.synchronize()
        if (count) console.log(`Reply ready · ${count} request(s) processed. Use Check replies in WoW.`)
      } catch (error) {
        // Parsing errors do not include character data or provider responses.
        console.error(
          error instanceof Error && /WoW is writing|8 MB/.test(error.message)
            ? error.message
            : "Waiting for a valid addon export. Update BadbUI, then /reload.",
        )
        if (values.once) throw new Error("Could not process the addon export")
      }
      if (values.once) break
      if (running) await Bun.sleep(2000)
    } while (running)
  } finally {
    await rm(lock, { recursive: true, force: true })
  }
}
main().then(
  () => process.exit(0),
  (error: unknown) => {
    console.error(error instanceof Error ? error.message : "Chatbot startup failed")
    process.exit(1)
  },
)
