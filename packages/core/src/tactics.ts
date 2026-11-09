// Motore "classi migliori per boss": ogni boss dichiara quanto la sua tattica richiede certe capacita'
// (pesi 0-3), ogni spec dichiara quanto le possiede (0-3). Il punteggio e' la copertura pesata.
//
// La matrice predefinita descrive i kit storici delle classi (confidenza C: Forever ha rielaborato
// tutte le classi, vedi packages/addon/docs/FOREVER_FACTS.md). Gli ufficiali la correggono dal sito:
// nessun numero qui dentro e' un dato di gioco ufficiale.
import { classIds, classes, findSpec, specKey, type ClassId, type Raid, type Role } from "./game"

export const tagIds = [
  "st",
  "cleave",
  "aoe",
  "burst",
  "ranged",
  "melee",
  "mobility",
  "interrupt",
  "cc",
  "kite",
  "purge",
  "dispel-magic",
  "decurse",
  "poison",
  "disease",
  "fear",
  "raid-heal",
  "tank-heal",
  "tank-single",
  "add-tank",
  "tank-swap",
  "threat",
  "utility",
] as const
export type TagId = (typeof tagIds)[number]

export type Tag = {
  id: TagId
  label: string
  hint: string
  /** Ruoli per cui la capacita' conta nel punteggio. */
  roles: Role[]
  /** Capacita' "a copertura": servono N giocatori che la abbiano, non conta la media. */
  coverage: boolean
}

const tag = (id: TagId, label: string, hint: string, roles: Role[], coverage = false): Tag => ({
  id,
  label,
  hint,
  roles,
  coverage,
})

export const tags: Record<TagId, Tag> = {
  st: tag("st", "Singolo bersaglio", "Danno prolungato su un bersaglio", ["dps"]),
  cleave: tag("cleave", "Cleave", "Due o tre bersagli vicini", ["dps"]),
  aoe: tag("aoe", "Area", "Molti add da abbattere insieme", ["dps"]),
  burst: tag("burst", "Burst", "Finestre brevi di danno alto", ["dps"]),
  ranged: tag("ranged", "Favorisce i ranged", "Il corpo a corpo e' penalizzato", ["dps"]),
  melee: tag("melee", "Favorisce i melee", "I ranged sono penalizzati", ["dps"]),
  mobility: tag("mobility", "Movimento", "Si combatte spostandosi spesso", ["dps", "healer", "tank"]),
  interrupt: tag("interrupt", "Interruzioni", "Lanci da interrompere", ["dps", "tank"], true),
  cc: tag("cc", "Controllo", "Add da tenere fermi", ["dps"], true),
  kite: tag("kite", "Kiting", "Add da rallentare e portare a spasso", ["dps"], true),
  purge: tag("purge", "Rimozione buff", "Buff nemici da togliere", ["dps", "healer"], true),
  "dispel-magic": tag("dispel-magic", "Dissolvi magia", "Debuff magici sugli alleati", ["healer", "dps"], true),
  decurse: tag("decurse", "Maledizioni", "Maledizioni da rimuovere", ["healer", "dps"], true),
  poison: tag("poison", "Veleni", "Veleni da rimuovere", ["healer", "dps"], true),
  disease: tag("disease", "Malattie", "Malattie da rimuovere", ["healer", "dps"], true),
  fear: tag("fear", "Paura", "Paure da prevenire o spezzare", ["tank", "healer", "dps"], true),
  "raid-heal": tag("raid-heal", "Cure di raid", "Danno diffuso su tutto il gruppo", ["healer"]),
  "tank-heal": tag("tank-heal", "Cure sul tank", "Colpi pesanti su un bersaglio", ["healer"]),
  "tank-single": tag("tank-single", "Tank sul boss", "Mitigazione contro colpi pesanti", ["tank"]),
  "add-tank": tag("add-tank", "Tank sugli add", "Minaccia ad area su piu' nemici", ["tank"]),
  "tank-swap": tag("tank-swap", "Cambio tank", "Provocazioni e cambi sul boss", ["tank"], true),
  threat: tag("threat", "Minaccia", "Serve minaccia alta e stabile", ["tank"]),
  utility: tag("utility", "Utilita'", "Resurrezioni in combattimento, buff, risorse", ["tank", "healer", "dps"]),
}

export const tagList = tagIds.map((id) => tags[id])

/** Pesi della tattica di un boss: 0 = irrilevante, 3 = decisivo. */
export type Weights = Partial<Record<TagId, number>>
export type Caps = Partial<Record<TagId, number>>
/** Capacita' per spec, chiave "classe/spec". */
export type Matrix = Record<string, Caps>

export const defaults: Matrix = {
  "warrior/arms": { st: 2, cleave: 3, aoe: 2, burst: 2, mobility: 2, interrupt: 3, fear: 3 },
  "warrior/fury": { st: 3, cleave: 3, aoe: 2, burst: 2, mobility: 2, interrupt: 3, fear: 3 },
  "warrior/protection": {
    "tank-single": 3,
    "add-tank": 2,
    "tank-swap": 3,
    threat: 3,
    interrupt: 3,
    fear: 3,
    mobility: 2,
  },
  "paladin/holy": { "tank-heal": 3, "raid-heal": 1, "dispel-magic": 3, poison: 3, disease: 3, mobility: 1, utility: 3 },
  "paladin/protection": {
    "tank-single": 2,
    "add-tank": 3,
    "tank-swap": 1,
    threat: 2,
    "dispel-magic": 3,
    poison: 3,
    disease: 3,
    utility: 3,
    mobility: 1,
  },
  "paladin/retribution": {
    st: 2,
    cleave: 2,
    aoe: 1,
    burst: 2,
    interrupt: 1,
    "dispel-magic": 3,
    poison: 3,
    disease: 3,
    utility: 3,
    mobility: 1,
  },
  "hunter/beast-mastery": { st: 3, cleave: 1, aoe: 1, burst: 2, mobility: 3, kite: 3, cc: 2, purge: 1, utility: 2 },
  "hunter/marksmanship": { st: 3, cleave: 1, aoe: 2, burst: 2, mobility: 3, kite: 3, cc: 2, purge: 1, utility: 2 },
  "hunter/survival": { st: 2, cleave: 1, aoe: 2, burst: 1, mobility: 3, kite: 3, cc: 3, purge: 1, utility: 1 },
  "rogue/assassination": { st: 3, cleave: 1, burst: 3, interrupt: 3, mobility: 2, cc: 2 },
  "rogue/combat": { st: 3, cleave: 3, aoe: 1, burst: 2, interrupt: 3, mobility: 2, cc: 2 },
  "rogue/subtlety": { st: 2, cleave: 1, burst: 3, interrupt: 3, mobility: 3, cc: 3 },
  "priest/discipline": {
    "tank-heal": 3,
    "raid-heal": 2,
    "dispel-magic": 3,
    disease: 3,
    purge: 3,
    fear: 1,
    cc: 1,
    utility: 2,
    mobility: 2,
  },
  "priest/holy": {
    "tank-heal": 2,
    "raid-heal": 3,
    "dispel-magic": 3,
    disease: 3,
    purge: 3,
    fear: 1,
    cc: 1,
    utility: 2,
    mobility: 1,
  },
  "priest/shadow": {
    st: 2,
    cleave: 2,
    burst: 1,
    "dispel-magic": 3,
    disease: 3,
    purge: 3,
    cc: 1,
    mobility: 2,
    utility: 2,
  },
  "shaman/elemental": {
    st: 2,
    cleave: 3,
    aoe: 2,
    burst: 3,
    interrupt: 3,
    purge: 3,
    poison: 3,
    disease: 3,
    fear: 3,
    mobility: 1,
    utility: 2,
  },
  "shaman/enhancement": {
    st: 2,
    cleave: 2,
    aoe: 1,
    burst: 2,
    interrupt: 3,
    purge: 3,
    poison: 3,
    disease: 3,
    fear: 3,
    mobility: 1,
    utility: 3,
  },
  "shaman/restoration": {
    "raid-heal": 3,
    "tank-heal": 2,
    purge: 3,
    poison: 3,
    disease: 3,
    fear: 3,
    mobility: 1,
    utility: 3,
  },
  "mage/arcane": { st: 2, cleave: 2, aoe: 3, burst: 3, decurse: 3, cc: 3, interrupt: 2, mobility: 2, kite: 2, utility: 2 },
  "mage/fire": { st: 3, cleave: 2, aoe: 3, burst: 3, decurse: 3, cc: 3, interrupt: 2, mobility: 1, kite: 1, utility: 2 },
  "mage/frost": { st: 3, cleave: 1, aoe: 3, burst: 2, decurse: 3, cc: 3, interrupt: 2, mobility: 2, kite: 3, utility: 2 },
  "warlock/affliction": { st: 3, cleave: 3, aoe: 2, burst: 1, mobility: 3, cc: 2, "dispel-magic": 1, utility: 3 },
  "warlock/demonology": { st: 2, cleave: 2, aoe: 2, burst: 1, mobility: 2, cc: 2, "dispel-magic": 1, utility: 3 },
  "warlock/destruction": { st: 3, cleave: 2, aoe: 3, burst: 3, mobility: 1, cc: 2, "dispel-magic": 1, utility: 3 },
  "druid/balance": { st: 2, cleave: 2, aoe: 3, burst: 2, decurse: 3, poison: 3, cc: 2, mobility: 2, utility: 3 },
  "druid/feral": {
    st: 3,
    cleave: 2,
    aoe: 1,
    burst: 2,
    "tank-single": 2,
    "add-tank": 3,
    "tank-swap": 3,
    threat: 3,
    interrupt: 1,
    decurse: 3,
    poison: 3,
    mobility: 3,
    utility: 3,
  },
  "druid/restoration": { "raid-heal": 2, "tank-heal": 2, decurse: 3, poison: 3, mobility: 3, utility: 3 },
}

function clamp(n: unknown) {
  if (typeof n !== "number" || !Number.isFinite(n)) return 0
  return Math.max(0, Math.min(3, Math.round(n)))
}

/** Ripulisce pesi o capacita' arrivati dall'esterno: solo tag noti, valori 1-3. */
export function sanitize(input: unknown): Weights {
  if (!input || typeof input !== "object") return {}
  const source = input as Record<string, unknown>
  return Object.fromEntries(tagIds.map((id) => [id, clamp(source[id])] as const).filter((e) => e[1] > 0))
}

/** Matrice effettiva: predefinita + correzioni degli ufficiali. */
export function matrix(overrides?: Record<string, unknown> | null): Matrix {
  if (!overrides) return defaults
  return Object.fromEntries(
    Object.keys(defaults).map((key) => {
      const patch = overrides[key]
      if (!patch || typeof patch !== "object") return [key, defaults[key]!]
      const fixed = Object.fromEntries(
        tagIds.filter((id) => id in (patch as object)).map((id) => [id, clamp((patch as Record<string, unknown>)[id])]),
      )
      return [key, { ...defaults[key], ...fixed }]
    }),
  )
}

/** Capacita' di una spec su un tag (0-3). "ranged"/"melee" derivano dalla distanza di combattimento. */
export function cap(m: Matrix, cls: ClassId, spec: string, id: TagId) {
  if (id === "ranged" || id === "melee") return findSpec(cls, spec)?.range === id ? 3 : 0
  return m[specKey(cls, spec)]?.[id] ?? 0
}

export type Fit = {
  cls: ClassId
  spec: string
  role: Role
  /** 0-100, oppure null se la tattica non dice nulla per questo ruolo. */
  score: number | null
  strengths: TagId[]
  gaps: TagId[]
}

export function fit(m: Matrix, weights: Weights, cls: ClassId, spec: string, role: Role): Fit {
  const relevant = tagIds.filter((id) => (weights[id] ?? 0) > 0 && tags[id].roles.includes(role))
  const total = relevant.reduce((sum, id) => sum + (weights[id] ?? 0) * 3, 0)
  const got = relevant.reduce((sum, id) => sum + (weights[id] ?? 0) * cap(m, cls, spec, id), 0)
  return {
    cls,
    spec,
    role,
    score: total === 0 ? null : Math.round((got / total) * 100),
    strengths: relevant.filter((id) => cap(m, cls, spec, id) >= 2),
    gaps: relevant.filter((id) => (weights[id] ?? 0) >= 2 && cap(m, cls, spec, id) === 0),
  }
}

/** Classifica di tutte le spec per ruolo, dalla piu' adatta. */
export function rank(m: Matrix, weights: Weights): Record<Role, Fit[]> {
  const all = classIds.flatMap((cls) =>
    classes[cls].specs.flatMap((s) => s.roles.map((role) => fit(m, weights, cls, s.id, role))),
  )
  const by = (role: Role) =>
    all
      .filter((f) => f.role === role)
      .toSorted((a, b) => (b.score ?? -1) - (a.score ?? -1) || a.cls.localeCompare(b.cls) || a.spec.localeCompare(b.spec))
  return { tank: by("tank"), healer: by("healer"), dps: by("dps") }
}

/** Classi ordinate per miglior spec in un ruolo: la risposta breve a "chi porto su questo boss?". */
export function best(m: Matrix, weights: Weights, role: Role, limit = 5) {
  const seen = new Set<ClassId>()
  return rank(m, weights)
    [role].filter((f) => f.score !== null)
    .filter((f) => (seen.has(f.cls) ? false : (seen.add(f.cls), true)))
    .slice(0, limit)
}

/** Giocatori richiesti per una capacita' a copertura, in base al peso e alla dimensione del raid. */
export function need(weight: number, size: number) {
  if (weight <= 0) return 0
  return Math.max(1, Math.round((weight * size) / 20))
}

export type Player = { name: string; cls: ClassId; spec: string | null; role: Role }

export type Coverage = { tag: TagId; have: number; need: number; ok: boolean; who: string[] }

export type Analysis = {
  roles: Record<Role, { have: number; need: number }>
  coverage: Coverage[]
  /** Media dei punteggi dei presenti (0-100), null senza dati. */
  score: number | null
  warnings: string[]
}

/** Confronta un roster con la tattica di un boss: ruoli, coperture mancanti, adattamento medio. */
export function analyze(m: Matrix, weights: Weights, roster: Player[], raid: Pick<Raid, "size" | "comp">): Analysis {
  const count = (role: Role) => roster.filter((p) => p.role === role).length
  const roleCount = {
    tank: { have: count("tank"), need: raid.comp.tank },
    healer: { have: count("healer"), need: raid.comp.healer },
    dps: { have: count("dps"), need: raid.comp.dps },
  }
  const coverage = tagIds
    .filter((id) => tags[id].coverage && (weights[id] ?? 0) > 0)
    .map((id) => {
      const who = roster
        .filter((p) => p.spec && tags[id].roles.includes(p.role) && cap(m, p.cls, p.spec, id) >= 2)
        .map((p) => p.name)
      const wanted = need(weights[id] ?? 0, raid.size)
      return { tag: id, have: who.length, need: wanted, ok: who.length >= wanted, who }
    })
  const scores = roster
    .filter((p) => p.spec)
    .map((p) => fit(m, weights, p.cls, p.spec!, p.role).score)
    .filter((s): s is number => s !== null)
  const warnings = [
    ...(["tank", "healer", "dps"] as const)
      .filter((role) => roleCount[role].have < roleCount[role].need)
      .map((role) => `Mancano ${roleCount[role].need - roleCount[role].have} ${role === "dps" ? "DPS" : role}`),
    ...coverage
      .filter((c) => !c.ok)
      .map((c) => `${tags[c.tag].label}: ${c.have}/${c.need}`),
  ]
  return {
    roles: roleCount,
    coverage,
    score: scores.length === 0 ? null : Math.round(scores.reduce((a, b) => a + b, 0) / scores.length),
    warnings,
  }
}
