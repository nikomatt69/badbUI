import { test, expect } from "bun:test"
import { mkdtemp, mkdir, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Lua } from "@badb/core"
import { Bridge } from "../src/bridge"
import { Bundle, decode, prompt, publicConfig } from "../src/protocol"

import { request } from "./fixtures"

test("data-only Lua decoding preserves selected quests and refuses executable input", () => {
  const r = request()
  const input = decode(Lua.stringify("BadbUI_ChatbotExport", { version: 1, requests: [r] }))
  expect(input.requests[0]).toEqual(r)
  expect(prompt(r)).toContain("Westfall")
  expect(() => decode('BadbUI_ChatbotExport = os.execute("bad")')).toThrow()
  expect(() => prompt({ ...r, character: "Other" })).toThrow("identity")
})
test("Lua round trip preserves empty nested model, variant, auth and source arrays", () => {
  const value: Bundle = {
    version: 1,
    generated: 1,
    configJSON: "{}",
    auth: { fixture: [] },
    providers: [
      { id: "fixture", name: "Fixture", connected: true, models: [{ id: "fixture", name: "Fixture", variants: [] }] },
      { id: "empty", name: "Empty", connected: false, models: [] },
    ],
    receipts: [
      { id: "id", character: "Player-1", generation: 1, kind: "ask", status: "error", text: "Failed", sources: [] },
    ],
  }
  const decoded = Lua.parse(Lua.stringify("Bundle", value)).Bundle
  expect(Bundle.parse(decoded)).toEqual(value)
})
test("bridge persists replies, deduplicates across restarts, and never modifies SavedVariables", async () => {
  const dir = await mkdtemp(join(tmpdir(), "badb-chat-"))
  try {
    const addon = join(dir, "BadbUI"),
      saved = join(dir, "Saved.lua")
    await mkdir(addon)
    await Bun.write(join(addon, "BadbUI.toc"), "test")
    const original = Lua.stringify("BadbUI_ChatbotExport", { version: 1, requests: [request()] })
    await Bun.write(saved, original)
    let count = 0
    const engine = {
      catalog: async () => ({ providers: [], auth: {}, configJSON: "{}" }),
      execute: async () => {
        count++
        return {
          text: 'Answer "safe"\n|Hbad|h',
          sources: ["https://www.wowhead.com/classic/quest=12"],
          session: "session-1",
        }
      },
    }
    const bridge = new Bridge(saved, addon, engine)
    expect(await bridge.synchronize()).toBe(1)
    expect(await bridge.synchronize()).toBe(0)
    expect(await new Bridge(saved, addon, engine).synchronize()).toBe(0)
    expect(count).toBe(1)
    expect(await readFile(saved, "utf8")).toBe(original)
    const output = await readFile(join(addon, "Data/ChatbotSync.lua"), "utf8")
    expect(output).toContain("wowhead.com")
    expect(() => Lua.parse(output)).not.toThrow()
    expect(Bundle.parse(Lua.parse(output).BadbUI_ChatbotSync).receipts[0]?.text).toBe('Answer "safe"\n|Hbad|h')
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
})
test("provider failures produce safe receipts and do not leak credentials", async () => {
  const dir = await mkdtemp(join(tmpdir(), "badb-chat-fail-"))
  try {
    const addon = join(dir, "BadbUI"),
      saved = join(dir, "Saved.lua")
    await mkdir(addon)
    await Bun.write(join(addon, "BadbUI.toc"), "test")
    await Bun.write(saved, Lua.stringify("BadbUI_ChatbotExport", { version: 1, requests: [request()] }))
    const engine = {
      catalog: async () => ({ providers: [], auth: {}, configJSON: "{}" }),
      execute: async () => {
        throw new Error("secret-api-key")
      },
    }
    await new Bridge(saved, addon, engine).synchronize()
    const output = await readFile(join(addon, "Data/ChatbotSync.lua"), "utf8")
    expect(output).not.toContain("secret-api-key")
    expect(output).toContain('"error"')
    expect(
      publicConfig({
        provider: {
          test: { options: { apiKey: "secret", headers: { Authorization: "secret" }, baseURL: "https://example.com" } },
        },
      }),
    ).toEqual({ provider: { test: { options: { baseURL: "https://example.com" } } } })
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
})
