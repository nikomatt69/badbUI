// SQLite (bun:sqlite) con migrazioni versionate: ogni voce si applica una sola volta, in ordine.
import { Database } from "bun:sqlite"
import { mkdirSync } from "node:fs"
import { dirname } from "node:path"
import type { Storage, SqlValue } from "./storage"

import { migrations } from "./migrations"

export function open(path: string) {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true })
  const db = new Database(path, { create: true, strict: true })
  db.run("PRAGMA journal_mode = WAL")
  db.run("PRAGMA foreign_keys = ON")
  db.run("PRAGMA busy_timeout = 5000")
  const version = db.query<{ user_version: number }, []>("PRAGMA user_version").get()?.user_version ?? 0
  migrations.slice(version).forEach((sql, index) => {
    db.transaction(() => {
      db.run(sql)
      db.run(`PRAGMA user_version = ${version + index + 1}`)
    })()
  })
  const storage: Storage = {
    query<T, P extends SqlValue[]>(query: string) {
      const statement = db.query<T, SqlValue[]>(query)
      return { get: (...values: P) => statement.get(...values), all: (...values: P) => statement.all(...values) }
    },
    run: (query, values = []) => db.run(query, values),
    transaction: (work) => db.transaction(work),
    close: () => db.close(),
  }
  return storage
}
