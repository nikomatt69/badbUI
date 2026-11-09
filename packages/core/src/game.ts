// Dati di gioco condivisi da server, sito, app, bot e addon.
// Fonte: packages/addon/docs/FOREVER_FACTS.md (9 classi, 3 alberi, raid 10/20/40).

export const roles = ["tank", "healer", "dps"] as const
export type Role = (typeof roles)[number]

export const roleLabel: Record<Role, string> = { tank: "Tank", healer: "Healer", dps: "DPS" }

export const classIds = [
  "warrior",
  "paladin",
  "hunter",
  "rogue",
  "priest",
  "shaman",
  "mage",
  "warlock",
  "druid",
] as const
export type ClassId = (typeof classIds)[number]

export type Spec = {
  id: string
  label: string
  roles: Role[]
  range: "melee" | "ranged"
}

export type ClassInfo = {
  id: ClassId
  label: string
  color: string
  specs: Spec[]
}

const spec = (id: string, label: string, roles: Role[], range: Spec["range"]): Spec => ({ id, label, roles, range })

export const classes: Record<ClassId, ClassInfo> = {
  warrior: {
    id: "warrior",
    label: "Guerriero",
    color: "#C69B6D",
    specs: [
      spec("arms", "Armi", ["dps"], "melee"),
      spec("fury", "Furia", ["dps"], "melee"),
      spec("protection", "Protezione", ["tank"], "melee"),
    ],
  },
  paladin: {
    id: "paladin",
    label: "Paladino",
    color: "#F48CBA",
    specs: [
      spec("holy", "Sacro", ["healer"], "ranged"),
      spec("protection", "Protezione", ["tank"], "melee"),
      spec("retribution", "Castigo", ["dps"], "melee"),
    ],
  },
  hunter: {
    id: "hunter",
    label: "Cacciatore",
    color: "#AAD372",
    specs: [
      spec("beast-mastery", "Affinità Animale", ["dps"], "ranged"),
      spec("marksmanship", "Precisione di Tiro", ["dps"], "ranged"),
      spec("survival", "Sopravvivenza", ["dps"], "ranged"),
    ],
  },
  rogue: {
    id: "rogue",
    label: "Ladro",
    color: "#FFF468",
    specs: [
      spec("assassination", "Assassinio", ["dps"], "melee"),
      spec("combat", "Combattimento", ["dps"], "melee"),
      spec("subtlety", "Scaltrezza", ["dps"], "melee"),
    ],
  },
  priest: {
    id: "priest",
    label: "Sacerdote",
    color: "#FFFFFF",
    specs: [
      spec("discipline", "Disciplina", ["healer"], "ranged"),
      spec("holy", "Sacro", ["healer"], "ranged"),
      spec("shadow", "Ombra", ["dps"], "ranged"),
    ],
  },
  shaman: {
    id: "shaman",
    label: "Sciamano",
    color: "#0070DD",
    specs: [
      spec("elemental", "Elementale", ["dps"], "ranged"),
      spec("enhancement", "Potenziamento", ["dps"], "melee"),
      spec("restoration", "Rigenerazione", ["healer"], "ranged"),
    ],
  },
  mage: {
    id: "mage",
    label: "Mago",
    color: "#3FC7EB",
    specs: [
      spec("arcane", "Arcano", ["dps"], "ranged"),
      spec("fire", "Fuoco", ["dps"], "ranged"),
      spec("frost", "Gelo", ["dps"], "ranged"),
    ],
  },
  warlock: {
    id: "warlock",
    label: "Stregone",
    color: "#8788EE",
    specs: [
      spec("affliction", "Afflizione", ["dps"], "ranged"),
      spec("demonology", "Demonologia", ["dps"], "ranged"),
      spec("destruction", "Distruzione", ["dps"], "ranged"),
    ],
  },
  druid: {
    id: "druid",
    label: "Druido",
    color: "#FF7C0A",
    specs: [
      spec("balance", "Equilibrio", ["dps"], "ranged"),
      spec("feral", "Combattimento Ferino", ["tank", "dps"], "melee"),
      spec("restoration", "Rigenerazione", ["healer"], "ranged"),
    ],
  },
}

export const classList = classIds.map((id) => classes[id])

export function isClass(value: unknown): value is ClassId {
  return typeof value === "string" && (classIds as readonly string[]).includes(value)
}

export function findSpec(cls: ClassId, id: string | null | undefined) {
  return classes[cls].specs.find((s) => s.id === id)
}

/** Chiave univoca di una spec: "mage/frost". */
export function specKey(cls: ClassId, id: string) {
  return `${cls}/${id}`
}

/** Ruolo coerente con classe e spec: se quello richiesto non e' possibile si usa il primo della spec. */
export function resolveRole(cls: ClassId, id: string | null | undefined, wanted?: Role | null): Role {
  const found = findSpec(cls, id)
  if (!found) {
    const possible = new Set(classes[cls].specs.flatMap((s) => s.roles))
    if (wanted && possible.has(wanted)) return wanted
    return "dps"
  }
  if (wanted && found.roles.includes(wanted)) return wanted
  return found.roles[0] ?? "dps"
}

export type Raid = {
  id: string
  label: string
  size: 10 | 20 | 40
  /** Composizione indicativa: e' un punto di partenza, ogni gruppo puo' cambiarla. */
  comp: Record<Role, number>
}

export const raids: Raid[] = [
  { id: "barrow-deeps", label: "Barrow Deeps", size: 10, comp: { tank: 2, healer: 3, dps: 5 } },
  { id: "hyjal-summit", label: "Hyjal Summit", size: 20, comp: { tank: 3, healer: 5, dps: 12 } },
  { id: "onyxia", label: "Onyxia's Lair", size: 40, comp: { tank: 4, healer: 10, dps: 26 } },
]

export function findRaid(id: string) {
  return raids.find((r) => r.id === id)
}

export const slotIds = ["mattina", "pomeriggio", "sera"] as const
export type SlotId = (typeof slotIds)[number]

export type Slot = { id: SlotId; label: string; start: number; end: number }

/** Fasce orarie dei tre gruppi raid, in minuti dalla mezzanotte. */
export const slots: Record<SlotId, Slot> = {
  mattina: { id: "mattina", label: "Mattina", start: 6 * 60, end: 13 * 60 },
  pomeriggio: { id: "pomeriggio", label: "Pomeriggio", start: 13 * 60, end: 19 * 60 },
  sera: { id: "sera", label: "Sera", start: 19 * 60, end: 24 * 60 },
}

export const slotList = slotIds.map((id) => slots[id])

export const dayLabels = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"] as const
export const dayShort = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"] as const

export const ranks = ["guest", "member", "officer", "gm"] as const
export type Rank = (typeof ranks)[number]
export const rankLabel: Record<Rank, string> = {
  guest: "Ospite",
  member: "Membro",
  officer: "Ufficiale",
  gm: "Capogilda",
}

export function rankAtLeast(rank: Rank, min: Rank) {
  return ranks.indexOf(rank) >= ranks.indexOf(min)
}

/** Slot dell'equipaggiamento nell'ordine di GetInventorySlotInfo (1-19, senza la 4 = camicia opzionale). */
export const gearSlots = [
  { id: 1, label: "Testa" },
  { id: 2, label: "Collo" },
  { id: 3, label: "Spalle" },
  { id: 15, label: "Schiena" },
  { id: 5, label: "Torso" },
  { id: 9, label: "Polsi" },
  { id: 10, label: "Mani" },
  { id: 6, label: "Vita" },
  { id: 7, label: "Gambe" },
  { id: 8, label: "Piedi" },
  { id: 11, label: "Anello 1" },
  { id: 12, label: "Anello 2" },
  { id: 13, label: "Monile 1" },
  { id: 14, label: "Monile 2" },
  { id: 16, label: "Mano primaria" },
  { id: 17, label: "Mano secondaria" },
  { id: 18, label: "A distanza" },
] as const

export const qualityColor = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000"] as const
