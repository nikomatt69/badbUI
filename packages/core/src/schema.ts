// Contratto dati del server centrale: e' l'unica fonte per server, SDK, sito, app, bot e companion.
import { z } from "zod"
import { validRange, type Range } from "./availability"
import { classIds, ranks, roles, slotIds, type ClassId, type Rank, type Role, type SlotId } from "./game"
import { tagIds, type Analysis, type Fit, type Matrix, type Weights } from "./tactics"

const text = (max: number) => z.string().trim().max(max)
const name = (max: number) => z.string().trim().min(1).max(max)

export const Cls = z.enum(classIds)
export const RoleSchema = z.enum(roles)
export const SlotSchema = z.enum(slotIds)
export const RankSchema = z.enum(ranks)
export const DateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)

export const RangeSchema = z
  .object({
    day: z.number().int().min(0).max(6),
    start: z.number().int().min(0).max(1440),
    end: z.number().int().min(0).max(1440),
  })
  .refine(validRange, "Intervallo non valido")

export const WeightsSchema = z.partialRecord(z.enum(tagIds), z.number().int().min(0).max(3))

// ── Account ─────────────────────────────────────────────────────────────────────────────────────
export const Credentials = z.object({
  setupKey: z.string().max(128).optional(),
  name: z
    .string()
    .trim()
    .min(2)
    .max(24)
    .regex(/^[\p{L}\p{N}_.-]+$/u, "Solo lettere, numeri, punto, trattino e underscore"),
  password: z.string().min(8).max(200),
})

export const LinkKind = z.enum(["discord", "addon", "mobile"])
export const LinkRedeem = z.object({ code: name(16), label: text(60).optional() })
export const DiscordLink = z.object({
  code: name(16),
  discordId: z.string().regex(/^\d{5,25}$/),
  discordName: text(60).optional(),
})

export type User = {
  id: string
  name: string
  rank: Rank
  discordId: string | null
  discordName: string | null
  created: number
}

// ── Personaggi e armory ─────────────────────────────────────────────────────────────────────────
export const GearItem = z.object({
  slot: z.number().int().min(1).max(19),
  id: z.number().int().min(1).max(9_999_999),
  name: text(120).default(""),
  quality: z.number().int().min(0).max(7).default(1),
  ilvl: z.number().int().min(0).max(9999).optional(),
})
export type GearItem = z.infer<typeof GearItem>

export const Profession = z.object({ name: name(40), rank: z.number().int().min(0).max(999) })
export type Profession = z.infer<typeof Profession>

export const CharacterInput = z.object({
  name: z
    .string()
    .trim()
    .min(2)
    .max(48)
    .regex(/^[\p{L}'-]+(?: [\p{L}'-]+)*$/u, "Nome personaggio non valido"),
  realm: text(40).default(""),
  cls: Cls,
  spec: text(24).nullable().default(null),
  role: RoleSchema.optional(),
  level: z.number().int().min(1).max(60).default(60),
  race: text(24).nullable().default(null),
  main: z.boolean().default(false),
})

export const CharacterOwner = z.object({ userId: name(64).nullable() })

export const CharacterPatch = z.object({
  realm: text(40).optional(),
  cls: Cls.optional(),
  spec: text(24).nullable().optional(),
  role: RoleSchema.optional(),
  level: z.number().int().min(1).max(60).optional(),
  race: text(24).nullable().optional(),
  main: z.boolean().optional(),
})

export type Character = {
  id: string
  userId: string | null
  owner: string | null
  name: string
  realm: string
  cls: ClassId
  spec: string | null
  role: Role
  level: number
  race: string | null
  guildRank: string | null
  main: boolean
  itemLevel: number | null
  gear: GearItem[]
  professions: Profession[]
  updated: number
  source: "site" | "addon"
  /** Istante della scansione nel client, distinto dall'arrivo sul server. */
  scannedAt: number | null
  client: { version: string; build: string; interface: number } | null
}

// ── Candidature ─────────────────────────────────────────────────────────────────────────────────
export const ApplicationInput = z.object({
  name: CharacterInput.shape.name,
  cls: Cls,
  spec: text(24).nullable().default(null),
  role: RoleSchema,
  discord: text(60).default(""),
  experience: text(2000).default(""),
  about: text(2000).default(""),
  slots: z.array(SlotSchema).max(3).default([]),
  ranges: z.array(RangeSchema).max(42).default([]),
})

export const ApplicationReview = z.object({
  status: z.enum(["pending", "accepted", "rejected"]).optional(),
  feePaid: z.boolean().optional(),
  note: text(1000).optional(),
})

export type Application = {
  id: string
  userId: string | null
  account: string | null
  name: string
  cls: ClassId
  spec: string | null
  role: Role
  discord: string
  experience: string
  about: string
  slots: SlotId[]
  ranges: Range[]
  feePaid: boolean
  status: "pending" | "accepted" | "rejected"
  note: string
  created: number
  reviewed: number | null
}

// ── Disponibilita' ──────────────────────────────────────────────────────────────────────────────
export const AvailabilityInput = z.object({
  week: DateSchema,
  ranges: z.array(RangeSchema).max(42),
  /** replace = sostituisce la settimana, add = aggiunge, remove = toglie gli intervalli. */
  mode: z.enum(["replace", "add", "remove"]).default("replace"),
  note: text(200).optional(),
})
export const AvailabilityText = z.object({ text: name(200) })

export type Availability = {
  userId: string
  name: string
  cls: ClassId | null
  ranges: Range[]
  mask: string
  note: string
  source: Source
  updated: number
}

export type Week = { week: string; people: Availability[] }

export const sources = ["site", "mobile", "discord", "addon"] as const
export type Source = (typeof sources)[number]

// ── Gruppi raid, eventi e prenotazioni ──────────────────────────────────────────────────────────
export const Comp = z.object({
  tank: z.number().int().min(0).max(40),
  healer: z.number().int().min(0).max(40),
  dps: z.number().int().min(0).max(40),
})

export const GroupInput = z.object({
  name: name(40),
  slot: SlotSchema,
  raid: name(40),
  days: z.array(z.number().int().min(0).max(6)).max(7).default([]),
  start: z.number().int().min(0).max(1439),
  duration: z.number().int().min(30).max(600).default(180),
  leaderId: z.string().nullable().default(null),
  description: text(500).default(""),
  comp: Comp.optional(),
})

export const MemberInput = z.object({ characterId: name(64), bench: z.boolean().default(false) })

export type Member = {
  characterId: string
  userId: string | null
  name: string
  cls: ClassId
  spec: string | null
  role: Role
  bench: boolean
}

export type Group = {
  id: string
  name: string
  slot: SlotId
  raid: string
  days: number[]
  start: number
  duration: number
  leaderId: string | null
  leader: string | null
  description: string
  comp: Record<Role, number>
  members: Member[]
}

export const EventInput = z.object({
  groupId: z.string().nullable().default(null),
  raid: name(40),
  title: text(80).default(""),
  date: DateSchema,
  start: z.number().int().min(0).max(1439),
  duration: z.number().int().min(30).max(600).default(180),
  note: text(1000).default(""),
})

// Le patch non usano .partial(): i default di EventInput riempirebbero i campi omessi.
export const EventPatch = z.object({
  groupId: z.string().nullable().optional(),
  raid: name(40).optional(),
  title: text(80).optional(),
  date: DateSchema.optional(),
  start: z.number().int().min(0).max(1439).optional(),
  duration: z.number().int().min(30).max(600).optional(),
  note: text(1000).optional(),
  status: z.enum(["open", "locked", "done", "cancelled"]).optional(),
})

export const signupStatuses = ["yes", "maybe", "no"] as const
export const SignupInput = z.object({
  characterId: name(64).optional(),
  status: z.enum(signupStatuses),
  role: RoleSchema.optional(),
  note: text(200).default(""),
})
export const PickInput = z.object({ characterId: name(64), picked: z.boolean() })

export type Signup = {
  characterId: string
  userId: string | null
  name: string
  cls: ClassId
  spec: string | null
  role: Role
  status: (typeof signupStatuses)[number]
  note: string
  picked: boolean
  source: Source
  updated: number
}

export type RaidEvent = {
  id: string
  groupId: string | null
  group: string | null
  raid: string
  title: string
  date: string
  start: number
  startsAt: number
  duration: number
  note: string
  status: "open" | "locked" | "done" | "cancelled"
  comp: Record<Role, number>
  signups: Signup[]
}

// ── Boss e tattiche ─────────────────────────────────────────────────────────────────────────────
export const BossInput = z.object({
  raid: name(40),
  name: name(60),
  order: z.number().int().min(0).max(99).default(0),
  weights: WeightsSchema.default({}),
  notes: text(4000).default(""),
  confidence: z.enum(["A", "B", "C"]).default("C"),
})

export type Boss = {
  id: string
  raid: string
  name: string
  order: number
  weights: Weights
  notes: string
  confidence: "A" | "B" | "C"
  /** Le tre classi/spec migliori per ruolo, calcolate dal server con la matrice attiva. */
  best: Record<Role, Fit[]>
}

export type BossDetail = Boss & { rank: Record<Role, Fit[]> }
export type EventAnalysis = { boss: Pick<Boss, "id" | "name" | "weights">; analysis: Analysis }[]

export const MatrixPatch = z.record(z.string().max(40), WeightsSchema)
export type Capabilities = { matrix: Matrix; overrides: Matrix }

// ── Blog e guide ────────────────────────────────────────────────────────────────────────────────
export const PostInput = z.object({
  kind: z.enum(["blog", "guide"]),
  title: name(120),
  slug: z
    .string()
    .trim()
    .max(80)
    .regex(/^[a-z0-9-]*$/)
    .optional(),
  excerpt: text(300).default(""),
  body: text(60_000).default(""),
  category: text(40).default(""),
  tags: z.array(name(30)).max(10).default([]),
  published: z.boolean().default(true),
})

export type Post = {
  id: string
  kind: "blog" | "guide"
  slug: string
  title: string
  excerpt: string
  body: string
  category: string
  tags: string[]
  author: string | null
  published: number | null
  created: number
  updated: number
}

export type PostSummary = Omit<Post, "body">

// ── Gilda ───────────────────────────────────────────────────────────────────────────────────────
export const GuildInput = z.object({
  name: name(40),
  realm: text(40),
  motto: text(160),
  about: text(8000),
  discordInvite: z.union([
    z.literal(""),
    z
      .url()
      .max(200)
      .regex(/^https:\/\//),
  ]),
  /** Tassa di candidatura in argenti (0 = nessuna). Si paga in gioco, il sito la annota soltanto. */
  feeSilver: z.number().int().min(0).max(100_000),
  /** Sezione di Wowhead usata per i link agli oggetti, es. "classic". */
  wowhead: z
    .string()
    .trim()
    .max(40)
    .regex(/^[a-z0-9-]*$/),
  recruiting: z.array(Cls).max(9),
})
export type Guild = z.infer<typeof GuildInput>

export type Home = {
  guild: Guild
  members: number
  characters: number
  news: PostSummary[]
  events: RaidEvent[]
}

export type Member_ = User & { characters: Character[] }
export type Me = { user: User; characters: Character[]; application: Application | null }
export const RankPatch = z.object({ rank: RankSchema })

// ── Sincronizzazione addon (via companion) ──────────────────────────────────────────────────────
// L'addon non puo' fare richieste di rete: scrive una coda nelle SavedVariables, il companion la
// invia e riscrive il file dati che l'addon carica al prossimo /reload.
export const AddonAction = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("signup"),
    id: name(64),
    at: z.number().int().nonnegative(),
    eventId: name(64),
    character: CharacterInput.shape.name,
    status: z.enum(signupStatuses),
    note: text(200).default(""),
  }),
  z.object({
    type: z.literal("availability"),
    id: name(64),
    at: z.number().int().nonnegative(),
    week: DateSchema,
    mask: z.string().regex(/^[01]{21}$/),
  }),
])
export type AddonAction = z.infer<typeof AddonAction>

export const AddonCharacter = z.object({
  name: CharacterInput.shape.name,
  realm: text(40).default(""),
  cls: Cls,
  spec: text(24).nullable().default(null),
  role: RoleSchema.optional(),
  level: z.number().int().min(1).max(60),
  race: text(24).nullable().default(null),
  guildRank: text(40).nullable().default(null),
  itemLevel: z.number().int().min(0).max(9999).nullable().default(null),
  gear: z.array(GearItem).max(19).default([]),
  professions: z.array(Profession).max(8).default([]),
  scanned: z.number().int().nonnegative().default(0),
})
export type AddonCharacter = z.infer<typeof AddonCharacter>

export const RosterEntry = z.object({
  name: CharacterInput.shape.name,
  cls: Cls,
  level: z.number().int().min(1).max(60),
  guildRank: text(40).nullable().default(null),
})

export const AddonSync = z.object({
  version: text(20).default(""),
  client: z.object({ version: text(40), build: text(40), interface: z.number().int() }).optional(),
  characters: z.array(AddonCharacter).max(20).default([]),
  /** Roster di gilda visto in gioco: aggiorna l'armory anche per chi non usa l'addon. */
  roster: z.array(RosterEntry).max(1000).default([]),
  rosterAt: z.number().int().nonnegative().default(0),
  actions: z.array(AddonAction).max(200).default([]),
})
export type AddonSync = z.infer<typeof AddonSync>

/** Pacchetto che il companion scrive in Data/GuildSync.lua. Compatto: l'addon lo ritrasmette in gilda. */
export type Bundle = {
  rev: number
  generated: number
  week: string
  guild: Pick<Guild, "name" | "realm" | "motto">
  user: { name: string; rank: Rank } | null
  /** Id delle azioni ricevute: l'addon le toglie dalla coda. */
  applied: string[]
  rejected: { id: string; error: string }[]
  events: {
    id: string
    title: string
    raid: string
    group: string | null
    date: string
    start: number
    startsAt: number
    duration: number
    status: RaidEvent["status"]
    note: string
    comp: Record<Role, number>
    signups: { name: string; cls: ClassId; role: Role; status: Signup["status"]; picked: boolean }[]
  }[]
  groups: { id: string; name: string; slot: SlotId; raid: string; days: number[]; start: number; members: string[] }[]
  /** Settimana corrente e successiva: nome -> maschera a 21 bit. */
  availability: { week: string; people: { name: string; cls: ClassId | null; mask: string }[] }[]
  bosses: {
    id: string
    raid: string
    name: string
    notes: string
    tags: string[]
    best: Record<Role, { cls: ClassId; spec: string; label: string; score: number | null }[]>
  }[]
  news: { title: string; excerpt: string; published: number }[]
  guides: { title: string; body: string }[]
  armory: Pick<Character, "name" | "cls" | "level" | "spec" | "role" | "gear" | "scannedAt">[]
}

export type SyncResult = { bundle: Bundle; lua: string }

export type BusEvent = {
  type:
    | "connected"
    | "availability"
    | "event"
    | "group"
    | "application"
    | "post"
    | "boss"
    | "character"
    | "guild"
    | "user"
  id?: string
}

export type ApiError = { error: string; issues?: { path: string; message: string }[] }

export type AddonConnection = {
  userId: string
  name: string
  received: number
  client: AddonSync["client"] | null
  characters: number
  roster: number
  actions: number
  rejected: Bundle["rejected"]
}
