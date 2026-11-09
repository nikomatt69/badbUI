// Contesto del server: database, configurazione, bus eventi. Ogni dominio riceve un Ctx.
import type { Database } from "bun:sqlite"
import type { Schema } from "@badb/core"
import type { z } from "zod"

export type Config = {
  db: string
  tz: string
  origins: string[]
  /** Segreto condiviso con il bot Discord. Vuoto = accesso bot disattivato. */
  bot: string
  webhook: string
  /** Cartella con il sito compilato (packages/web/dist), servita dallo stesso processo. */
  web: string
}

export function config(env: Record<string, string | undefined> = process.env): Config {
  return {
    db: env.BADB_DB ?? "./data/badb.sqlite",
    tz: env.BADB_TZ ?? "Europe/Rome",
    origins: (env.BADB_ORIGINS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    bot: env.BADB_BOT_SECRET ?? "",
    webhook: env.BADB_DISCORD_WEBHOOK ?? "",
    web: env.BADB_WEB ?? "",
  }
}

type Listener = (event: Schema.BusEvent) => void

export class Bus {
  private listeners = new Set<Listener>()

  on(fn: Listener) {
    this.listeners.add(fn)
    return () => {
      this.listeners.delete(fn)
    }
  }

  emit(event: Schema.BusEvent) {
    for (const fn of this.listeners) fn(event)
  }
}

export type Ctx = {
  db: Database
  config: Config
  bus: Bus
  now: () => number
  /** Annunci verso Discord: sostituibile nei test. */
  announce: (text: string) => void
}

/** Errore con stato HTTP: il messaggio arriva al client cosi' com'e'. */
export class Fail extends Error {
  constructor(
    readonly status: 400 | 401 | 403 | 404 | 409 | 429,
    message: string,
  ) {
    super(message)
  }
}

export function id() {
  return crypto.randomUUID().replaceAll("-", "").slice(0, 20)
}

export function json<T>(value: unknown, fallback: T): T {
  if (typeof value !== "string") return fallback
  try {
    return JSON.parse(value) as T
  } catch {
    return fallback
  }
}

export function check<T extends z.ZodType>(schema: T, input: unknown): z.infer<T> {
  const result = schema.safeParse(input)
  if (result.success) return result.data
  const error = new Fail(400, "Dati non validi") as Fail & { issues: Schema.ApiError["issues"] }
  error.issues = result.error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message }))
  throw error
}

/** Segnala una modifica: incrementa la revisione (usata dall'addon) e avvisa i client collegati. */
export function touch(ctx: Ctx, event: Schema.BusEvent) {
  ctx.db.run(
    "INSERT INTO setting (key, value) VALUES ('rev', '1') ON CONFLICT(key) DO UPDATE SET value = CAST(value AS INTEGER) + 1",
  )
  ctx.bus.emit(event)
}

export function rev(ctx: Ctx) {
  const row = ctx.db.query<{ value: string }, []>("SELECT value FROM setting WHERE key = 'rev'").get()
  return Number(row?.value ?? 0)
}
