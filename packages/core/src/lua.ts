// Lettura e scrittura di tabelle Lua (file SavedVariables di WoW e file dati dell'addon).
// Solo dati: niente funzioni, niente espressioni. Il parser non esegue nulla.

export type LuaValue = string | number | boolean | null | LuaValue[] | { [key: string]: LuaValue }

class Reader {
  pos = 0
  constructor(readonly src: string) {}

  fail(message: string): never {
    const line = this.src.slice(0, this.pos).split("\n").length
    throw new Error(`Lua: ${message} (riga ${line})`)
  }

  skip() {
    for (;;) {
      const c = this.src[this.pos]
      if (c === " " || c === "\t" || c === "\n" || c === "\r") {
        this.pos++
        continue
      }
      if (c === "-" && this.src[this.pos + 1] === "-") {
        const long = /^--\[(=*)\[/.exec(this.src.slice(this.pos, this.pos + 16))
        if (long) {
          const close = this.src.indexOf(`]${long[1]}]`, this.pos)
          this.pos = close === -1 ? this.src.length : close + long[1]!.length + 2
          continue
        }
        const eol = this.src.indexOf("\n", this.pos)
        this.pos = eol === -1 ? this.src.length : eol + 1
        continue
      }
      return
    }
  }

  peek() {
    this.skip()
    return this.src[this.pos]
  }

  eat(token: string) {
    this.skip()
    if (!this.src.startsWith(token, this.pos)) return false
    this.pos += token.length
    return true
  }

  expect(token: string) {
    if (!this.eat(token)) this.fail(`atteso '${token}'`)
  }

  name() {
    this.skip()
    const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(this.src.slice(this.pos, this.pos + 256))
    if (!match) return undefined
    this.pos += match[0].length
    return match[0]
  }

  string(): string {
    const quote = this.src[this.pos]!
    this.pos++
    const bytes: number[] = []
    const encoder = new TextEncoder()
    for (;;) {
      const c = this.src[this.pos]
      if (c === undefined) this.fail("stringa non chiusa")
      if (c === quote) {
        this.pos++
        return new TextDecoder().decode(new Uint8Array(bytes))
      }
      if (c !== "\\") {
        // Copia il code point intero: le coppie surrogate non vanno spezzate.
        const point = String.fromCodePoint(this.src.codePointAt(this.pos)!)
        bytes.push(...encoder.encode(point))
        this.pos += point.length
        continue
      }
      const next = this.src[this.pos + 1]
      const digits = /^\d{1,3}/.exec(this.src.slice(this.pos + 1, this.pos + 4))
      if (digits) {
        bytes.push(Number(digits[0]) & 0xff)
        this.pos += 1 + digits[0].length
        continue
      }
      const simple: Record<string, number> = { n: 10, r: 13, t: 9, a: 7, b: 8, f: 12, v: 11, "\\": 92, '"': 34, "'": 39, "\n": 10 }
      if (next === undefined || simple[next] === undefined) this.fail("sequenza di escape sconosciuta")
      bytes.push(simple[next]!)
      this.pos += 2
    }
  }

  long(): string | undefined {
    const open = /^\[(=*)\[/.exec(this.src.slice(this.pos, this.pos + 16))
    if (!open) return undefined
    const start = this.pos + open[0].length
    const close = this.src.indexOf(`]${open[1]}]`, start)
    if (close === -1) this.fail("stringa lunga non chiusa")
    this.pos = close + open[1]!.length + 2
    const body = this.src.slice(start, close)
    return body.startsWith("\n") ? body.slice(1) : body
  }

  value(depth: number): LuaValue {
    if (depth > 64) this.fail("tabella troppo annidata")
    const c = this.peek()
    if (c === undefined) this.fail("valore mancante")
    if (c === "{") return this.table(depth)
    if (c === '"' || c === "'") return this.string()
    if (c === "[") {
      const text = this.long()
      if (text === undefined) this.fail("valore non valido")
      return text
    }
    const number = /^-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/.exec(this.src.slice(this.pos, this.pos + 64))
    if (number) {
      this.pos += number[0].length
      return Number(number[0])
    }
    const word = this.name()
    if (word === "true") return true
    if (word === "false") return false
    if (word === "nil") return null
    return this.fail(`valore non supportato${word ? `: ${word}` : ""}`)
  }

  table(depth: number): LuaValue {
    this.expect("{")
    const fields = new Map<string | number, LuaValue>()
    const state = { next: 1 }
    for (;;) {
      if (this.eat("}")) break
      const c = this.peek()
      const keyed = (() => {
        if (c === "[" && !/^\[=*\[/.test(this.src.slice(this.pos, this.pos + 16))) {
          this.pos++
          const key = this.value(depth + 1)
          this.expect("]")
          this.expect("=")
          if (typeof key !== "string" && typeof key !== "number") this.fail("chiave non supportata")
          return key
        }
        const save = this.pos
        const word = this.name()
        if (word && this.peek() === "=" && this.src[this.pos + 1] !== "=") {
          this.pos++
          return word
        }
        this.pos = save
        return undefined
      })()
      const item = this.value(depth + 1)
      if (keyed === undefined) fields.set(state.next++, item)
      if (keyed !== undefined) fields.set(keyed, item)
      if (!this.eat(",") && !this.eat(";")) {
        this.expect("}")
        break
      }
    }
    const keys = [...fields.keys()]
    const array = keys.length > 0 && keys.every((k) => typeof k === "number" && Number.isInteger(k) && k >= 1 && k <= keys.length)
    if (array) return Array.from({ length: keys.length }, (_, i) => fields.get(i + 1) ?? null)
    const out: { [key: string]: LuaValue } = {}
    for (const [key, item] of fields) {
      if (item === null) continue
      Object.defineProperty(out, String(key), { value: item, enumerable: true, writable: true, configurable: true })
    }
    return out
  }
}

/** Legge un file di assegnazioni globali ("Nome = valore") e restituisce { Nome: valore }. */
export function parse(src: string): Record<string, LuaValue> {
  const reader = new Reader(src.replace(/^﻿/, ""))
  const out: Record<string, LuaValue> = {}
  for (;;) {
    if (reader.peek() === undefined) return out
    const name = reader.name() ?? reader.fail("atteso un nome di variabile")
    reader.expect("=")
    Object.defineProperty(out, name, {
      value: reader.value(0),
      enumerable: true,
      writable: true,
      configurable: true,
    })
    reader.eat(";")
  }
}

function quote(text: string) {
  const escaped = text
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\0/g, "\\000")
    // "|" apre le sequenze di colore/link del client: i dati remoti non devono poterne iniettare.
    .replace(/\|/g, "||")
  return `"${escaped}"`
}

function write(value: unknown, indent: string): string | undefined {
  if (value === null || value === undefined) return undefined
  if (typeof value === "string") return quote(value)
  if (typeof value === "boolean") return value ? "true" : "false"
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : undefined
  const inner = `${indent}  `
  if (Array.isArray(value)) {
    const items = value.map((item) => write(item, inner) ?? "false")
    if (items.length === 0) return "{}"
    return `{\n${items.map((item) => `${inner}${item},\n`).join("")}${indent}}`
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .map(([key, item]) => [key, write(item, inner)] as const)
      .filter((entry): entry is readonly [string, string] => entry[1] !== undefined)
    if (entries.length === 0) return "{}"
    return `{\n${entries.map(([key, item]) => `${inner}[${quote(key)}] = ${item},\n`).join("")}${indent}}`
  }
  return undefined
}

/** Serializza un valore JSON come assegnazione globale Lua. Le stringhe sono sempre letterali sicuri. */
export function stringify(name: string, value: unknown) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error("Nome di variabile Lua non valido")
  return `${name} = ${write(value, "") ?? "nil"}\n`
}
