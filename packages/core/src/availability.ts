// Disponibilita' settimanale: intervalli orari per giorno, da cui si derivano le tre fasce raid.
import { slotIds, slotList, slots, type SlotId } from "./game"

/** Intervallo di disponibilita': day 0 = lunedi', minuti dalla mezzanotte, start < end <= 1440. */
export type Range = { day: number; start: number; end: number }

const DAY = 86_400_000
/** Sovrapposizione minima (minuti) perche' un intervallo "accenda" una fascia. */
export const OVERLAP = 60

function pad(n: number) {
  return String(n).padStart(2, "0")
}

/** Data di calendario (YYYY-MM-DD) e ora locale nel fuso indicato. */
export function local(now: Date, tz: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now)
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "00"
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    minutes: Number(get("hour")) * 60 + Number(get("minute")),
  }
}

function utc(date: string) {
  return new Date(`${date}T00:00:00Z`)
}

function iso(d: Date) {
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
}

export function isDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const d = utc(value)
  return !Number.isNaN(d.getTime()) && iso(d) === value
}

/** Indice del giorno (0 = lunedi') di una data di calendario. */
export function dayIndex(date: string) {
  return (utc(date).getUTCDay() + 6) % 7
}

export function addDays(date: string, days: number) {
  return iso(new Date(utc(date).getTime() + days * DAY))
}

/** Lunedi' della settimana che contiene la data. */
export function weekOf(date: string) {
  return addDays(date, -dayIndex(date))
}

export function currentWeek(now: Date, tz: string) {
  return weekOf(local(now, tz).date)
}

/** Converte data locale + minuti in un istante UTC (ms), rispettando l'ora legale del fuso. */
export function instant(date: string, minutes: number, tz: string) {
  const guess = utc(date).getTime() + minutes * 60_000
  // L'offset si ricava confrontando come il fuso "legge" il tentativo: due passate coprono i cambi d'ora.
  const shift = (ms: number) => {
    const seen = local(new Date(ms), tz)
    return utc(seen.date).getTime() + seen.minutes * 60_000 - ms
  }
  const first = guess - shift(guess)
  return guess - shift(first)
}

export function formatMinutes(minutes: number) {
  const m = ((minutes % 1440) + 1440) % 1440
  if (minutes === 1440) return "24:00"
  return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`
}

export function validRange(r: Range) {
  return (
    Number.isInteger(r.day) &&
    r.day >= 0 &&
    r.day <= 6 &&
    Number.isInteger(r.start) &&
    Number.isInteger(r.end) &&
    r.start >= 0 &&
    r.end <= 1440 &&
    r.start < r.end
  )
}

/** Fasce coperte da un intervallo (almeno OVERLAP minuti, o l'intero intervallo se piu' corto). */
export function slotsOf(r: Pick<Range, "start" | "end">): SlotId[] {
  const need = Math.min(OVERLAP, r.end - r.start)
  return slotList
    .filter((s) => Math.min(r.end, s.end) - Math.max(r.start, s.start) >= need && need > 0)
    .map((s) => s.id)
}

/** Unisce intervalli sovrapposti o adiacenti dello stesso giorno. */
export function merge(ranges: Range[]): Range[] {
  const sorted = ranges.filter(validRange).toSorted((a, b) => a.day - b.day || a.start - b.start)
  return sorted.reduce<Range[]>((out, r) => {
    const last = out.at(-1)
    if (last && last.day === r.day && r.start <= last.end) {
      last.end = Math.max(last.end, r.end)
      return out
    }
    out.push({ ...r })
    return out
  }, [])
}

/** Toglie un intervallo da una lista (per "non ci sono piu' lunedi' sera"). */
export function subtract(ranges: Range[], cut: Range): Range[] {
  return merge(ranges).flatMap((r) => {
    if (r.day !== cut.day || cut.end <= r.start || cut.start >= r.end) return [r]
    const left = { day: r.day, start: r.start, end: cut.start }
    const right = { day: r.day, start: cut.end, end: r.end }
    return [left, right].filter(validRange)
  })
}

export function slotRange(day: number, slot: SlotId): Range {
  return { day, start: slots[slot].start, end: slots[slot].end }
}

export type Grid<T> = Record<SlotId, T[]>[]

/** Griglia 7 giorni x 3 fasce con chi e' disponibile. */
export function grid<T extends { ranges: Range[] }>(people: T[]): Grid<T> {
  return Array.from({ length: 7 }, (_, day) => {
    const cell = (slot: SlotId) =>
      people.filter((p) => p.ranges.some((r) => r.day === day && slotsOf(r).includes(slot)))
    return { mattina: cell("mattina"), pomeriggio: cell("pomeriggio"), sera: cell("sera") }
  })
}

/** Maschera compatta per l'addon: 21 caratteri "0/1", giorno per giorno, tre fasce ciascuno. */
export function mask(ranges: Range[]) {
  return Array.from({ length: 7 }, (_, day) =>
    slotIds.map((slot) => (ranges.some((r) => r.day === day && slotsOf(r).includes(slot)) ? "1" : "0")).join(""),
  ).join("")
}

export function fromMask(value: string): Range[] {
  if (!/^[01]{21}$/.test(value)) return []
  return merge(
    [...value].flatMap((bit, i) => (bit === "1" ? [slotRange(Math.floor(i / 3), slotIds[i % 3]!)] : [])),
  )
}

const dayWords: Record<string, number> = {
  lun: 0,
  lunedi: 0,
  mar: 1,
  martedi: 1,
  mer: 2,
  mercoledi: 2,
  gio: 3,
  giovedi: 3,
  ven: 4,
  venerdi: 4,
  sab: 5,
  sabato: 5,
  dom: 6,
  domenica: 6,
}

const slotWords: Record<string, SlotId> = {
  mattina: "mattina",
  mattino: "mattina",
  mattine: "mattina",
  pomeriggio: "pomeriggio",
  pome: "pomeriggio",
  pomeriggi: "pomeriggio",
  sera: "sera",
  serata: "sera",
  sere: "sera",
  stasera: "sera",
}

function plain(text: string) {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[,;]/g, " ")
}

function clock(hour: string, minute: string | undefined) {
  const h = Number(hour)
  const m = minute ? Number(minute) : 0
  if (h > 24 || m > 59) return undefined
  return h * 60 + m
}

export type Parsed = { ok: true; ranges: Range[]; week: string; remove: boolean } | { ok: false; error: string }

/**
 * Interpreta frasi tipo "ci sono dalle 21 alle 23 giovedi'", "lun mer ven sera", "domani pomeriggio",
 * "tutta la settimana sera", "non ci sono sabato". Senza giorno vale oggi; "prossima settimana" sposta la settimana.
 */
export function parse(text: string, now: Date, tz: string): Parsed {
  const input = plain(text)
  const today = local(now, tz)
  const next = /prossima settimana|settimana prossima/.test(input)
  const week = addDays(weekOf(today.date), next ? 7 : 0)
  const remove = /\bnon\b/.test(input)
  const words = input.split(/\s+/).filter(Boolean)

  const days = new Set<number>()
  if (/tutta la settimana|tutti i giorni|ogni giorno|sempre/.test(input)) for (const d of [0, 1, 2, 3, 4, 5, 6]) days.add(d)
  if (/weekend|fine settimana/.test(input)) for (const d of [5, 6]) days.add(d)
  if (/feriali|in settimana/.test(input)) for (const d of [0, 1, 2, 3, 4]) days.add(d)
  for (const word of words) {
    const day = dayWords[word]
    if (day !== undefined) days.add(day)
    if (word === "oggi" || word === "stasera" || word === "stamattina") days.add(dayIndex(today.date))
    if (word === "domani") days.add((dayIndex(today.date) + 1) % 7)
  }
  if (days.size === 0) days.add(dayIndex(today.date))

  const spans: Pick<Range, "start" | "end">[] = []
  const time = /(?:dalle|dalla|da)?\s*(\d{1,2})(?:[:.](\d{2}))?\s*(?:-|–|alle|all'|a|fino alle|fino a)\s*(\d{1,2})(?:[:.](\d{2}))?/g
  for (const match of input.matchAll(time)) {
    const start = clock(match[1]!, match[2])
    const raw = clock(match[3]!, match[4])
    if (start === undefined || raw === undefined) return { ok: false, error: "Orario non valido" }
    // "21-01" finisce dopo mezzanotte: la disponibilita' si ferma alle 24 di quel giorno.
    const end = raw <= start ? 1440 : raw
    if (start >= end) return { ok: false, error: "Orario non valido" }
    spans.push({ start, end })
  }
  for (const word of words) {
    const slot = slotWords[word] ?? (word === "stamattina" ? "mattina" : undefined)
    if (slot) spans.push({ start: slots[slot].start, end: slots[slot].end })
  }
  if (/tutto il giorno|tutto il di/.test(input)) spans.push({ start: slots.mattina.start, end: 1440 })
  if (spans.length === 0) {
    if (!remove) return { ok: false, error: "Indica una fascia (mattina, pomeriggio, sera) o un orario (es. 21-23)" }
    spans.push({ start: 0, end: 1440 })
  }

  const ranges = merge([...days].flatMap((day) => spans.map((s) => ({ day, ...s }))))
  return { ok: true, ranges, week, remove }
}

/** Descrizione leggibile di un insieme di intervalli: "Lun 21:00-23:00, Mer 19:00-24:00". */
export function describe(ranges: Range[]) {
  const short = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
  return merge(ranges)
    .map((r) => `${short[r.day]} ${formatMinutes(r.start)}-${formatMinutes(r.end)}`)
    .join(", ")
}
