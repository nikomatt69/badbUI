import type { Storage, SqlValue } from "@badb/server/storage"
import { migrations } from "@badb/server/migrations"

/** Conserva il contratto SQL del dominio usando lo SQLite sincrono del Durable Object. */
export function storage(state: DurableObjectState): Storage {
  const sql = state.storage.sql
  // Le query della gilda usano solo numeri, testo e null. Nessun valore opaco attraversa l'adapter.
  const bind = (values: SqlValue[]) =>
    values.map((v) =>
      typeof v === "boolean"
        ? Number(v)
        : typeof v === "bigint"
          ? Number(v)
          : v instanceof Uint8Array
            ? (v.buffer.slice(v.byteOffset, v.byteOffset + v.byteLength) as ArrayBuffer)
            : v,
    )
  const db: Storage = {
    query<T, P extends SqlValue[]>(query: string) {
      const all = (...values: P): T[] => [...sql.exec(query, ...bind(values))] as T[]
      return { all, get: (...values: P) => all(...values)[0] ?? null }
    },
    run(query, values = []) {
      // rowsWritten include gli indici; changes() restituisce solo le righe della statement,
      // come bun:sqlite. L'idempotenza delle azioni dipende da questa distinzione.
      sql.exec(query, ...bind(values)).toArray()
      const changed = sql.exec<{ n: number }>("SELECT changes() AS n").one().n
      return { changes: changed }
    },
    transaction(work) {
      return () => state.storage.transactionSync(work)
    },
    close() {},
  }
  sql.exec("CREATE TABLE IF NOT EXISTS _badb_migration (version INTEGER PRIMARY KEY)")
  const version = sql
    .exec<{ version: number }>("SELECT COALESCE(MAX(version), 0) AS version FROM _badb_migration")
    .one().version
  migrations.slice(version).forEach((migration, i) => {
    state.storage.transactionSync(() => {
      sql.exec(migration)
      sql.exec("INSERT INTO _badb_migration (version) VALUES (?)", version + i + 1)
    })
  })
  return db
}
