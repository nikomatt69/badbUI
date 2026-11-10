/** Operazioni SQL sincrone del dominio. Implementate da Bun SQLite e dal Durable Object Cloudflare. */
export type SqlValue = string | number | bigint | boolean | null | Uint8Array
export interface Storage {
  query<T = Record<string, unknown>, P extends SqlValue[] = SqlValue[]>(
    sql: string,
  ): {
    get(...values: P): T | null
    all(...values: P): T[]
  }
  run(sql: string, values?: SqlValue[]): { changes: number }
  transaction<T>(work: () => T): () => T
  close(): void
}
export type Passwords = {
  hash: (password: string) => Promise<string>
  verify: (password: string, hash: string) => Promise<boolean>
}
