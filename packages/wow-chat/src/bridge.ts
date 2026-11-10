import { readFile, stat, mkdir, writeFile, rename } from "node:fs/promises"
import { dirname, join } from "node:path"
import { Lua } from "@badb/core"
import { Bundle, decode, type ChatRequest, type Receipt } from "./protocol"

export async function atomic(file: string, text: string, mode = 0o600) {
  await mkdir(dirname(file), { recursive: true })
  const temporary = `${file}.${crypto.randomUUID()}.tmp`
  await writeFile(temporary, text, { mode })
  await rename(temporary, file)
}
export async function stableRead(file: string) {
  const before = await stat(file)
  if (before.size > 8_000_000) throw new Error("SavedVariables exceed the 8 MB limit")
  const text = await readFile(file, "utf8")
  const after = await stat(file)
  if (before.mtimeMs !== after.mtimeMs || before.size !== after.size)
    throw new Error("WoW is writing SavedVariables; waiting for the next pass")
  return text
}
export interface Engine {
  catalog(): Promise<Pick<Bundle, "providers" | "auth" | "configJSON">>
  execute(request: ChatRequest, previous: Receipt[]): Promise<Pick<Receipt, "text" | "sources" | "session">>
}
export class Bridge {
  private bundle: Bundle = { version: 1, generated: 0, receipts: [], providers: [], auth: {}, configJSON: "{}" }
  private loaded = false
  private busy = false
  constructor(
    readonly saved: string,
    readonly addon: string,
    readonly engine: Engine,
  ) {}
  private get output() {
    return join(this.addon, "Data", "ChatbotSync.lua")
  }
  private async persist() {
    this.bundle.generated = Math.floor(Date.now() / 1000)
    // Lua.stringify also escapes WoW display pipes. This file is a data
    // journal, not rendered text: the addon escapes each value when displayed.
    // Keep literal pipes here so read/write cycles never double them again.
    await atomic(this.output, Lua.stringify("BadbUI_ChatbotSync", this.bundle).replace(/\|\|/g, "|"))
  }
  async synchronize() {
    if (this.busy) return 0
    this.busy = true
    try {
      await stat(join(this.addon, "BadbUI.toc"))
      if (!this.loaded) {
        const file = Bun.file(this.output)
        if (await file.exists()) {
          const value = Lua.parse(await file.text()).BadbUI_ChatbotSync
          if (value) this.bundle = Bundle.parse(value)
        }
        Object.assign(this.bundle, await this.engine.catalog())
        await this.persist()
        this.loaded = true
      }
      if (!(await Bun.file(this.saved).exists())) return 0
      const text = await stableRead(this.saved)
      if (!text.includes("BadbUI_ChatbotExport")) return 0
      const input = decode(text)
      let processed = 0
      for (const request of input.requests) {
        if (this.bundle.receipts.some((r) => r.id === request.id)) continue
        let receipt: Receipt
        try {
          // Old exports must not replay paid generations after receipt rotation.
          if (request.at < Math.floor(Date.now() / 1000) - 86400 * 7) throw new Error("Expired export")
          const result = await this.engine.execute(request, this.bundle.receipts)
          receipt = {
            id: request.id,
            character: request.character,
            generation: request.generation,
            kind: request.kind,
            question: request.kind === "ask" ? request.payload.text : undefined,
            status: "ok",
            ...result,
          }
        } catch {
          // Provider errors may contain credentials or payloads. Never serialize them.
          receipt = {
            id: request.id,
            character: request.character,
            generation: request.generation,
            kind: request.kind,
            question: request.kind === "ask" ? request.payload.text : undefined,
            status: "error",
            text: "Request failed. Check the selected provider/model, credentials, search backend and advanced JSON settings, then retry. No successful answer was generated.",
            sources: [],
          }
        }
        this.bundle.receipts.push(receipt)
        this.bundle.receipts = this.bundle.receipts.slice(-500)
        // Persist every receipt before the next paid operation. A process crash
        // during model generation itself cannot guarantee exactly-once billing.
        await this.persist()
        processed++
        if (request.kind !== "ask") {
          Object.assign(this.bundle, await this.engine.catalog())
          await this.persist()
        }
      }
      return processed
    } finally {
      this.busy = false
    }
  }
}
