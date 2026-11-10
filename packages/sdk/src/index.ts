// Client tipizzato del server centrale Badb. Usato da sito, app mobile, bot Discord e companion:
// dipende solo da fetch, quindi gira in browser, React Native, Bun e Node.
import type { Game, Schema, Tactics } from "@badb/core"
import type { z } from "zod"

type In<T extends z.ZodType> = z.input<T>

/** Server centrale pubblicato. I client possono sostituirlo per sviluppo o installazioni proprie. */
export const DEFAULT_SERVER_URL = "https://badb-guild.nikoemme-work.workers.dev"

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly issues: NonNullable<Schema.ApiError["issues"]> = [],
  ) {
    super(message)
  }
}

export type Options = {
  url: string
  /** Token di sessione. Una funzione permette di leggerlo dallo storage a ogni richiesta. */
  token?: string | null | (() => string | null | undefined)
  /** Solo per il bot Discord: segreto condiviso con il server. */
  bot?: string
  fetch?: typeof fetch
  timeout?: number
}

export type Session = { token: string; user: Schema.User }
export type Link = { code: string; expires: number }
export type Ok = { ok: true }
export type Said = {
  entry: Schema.Availability
  week: string
  changed: { day: number; start: number; end: number }[]
  removed: boolean
}

export function createClient(options: Options) {
  const base = options.url.replace(/\/+$/, "")
  const send = options.fetch ?? fetch

  const headers = (discord?: string) => {
    const token = typeof options.token === "function" ? options.token() : options.token
    return {
      ...(options.bot ? { authorization: `Bot ${options.bot}` } : token ? { authorization: `Bearer ${token}` } : {}),
      ...(discord ? { "x-discord-id": discord } : {}),
    }
  }

  async function request<T>(method: string, path: string, body?: unknown, discord?: string): Promise<T> {
    const response = await send(`${base}${path}`, {
      method,
      headers: { ...headers(discord), ...(body === undefined ? {} : { "content-type": "application/json" }) },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(options.timeout ?? 15_000),
    })
    const data: unknown = await response.json().catch(() => {
      throw new ApiError(response.status || 502, `Risposta JSON non valida (${response.status})`)
    })
    if (!response.ok) {
      const failure = data as Schema.ApiError
      throw new ApiError(response.status, failure.error ?? `Errore ${response.status}`, failure.issues ?? [])
    }
    return data as T
  }

  /** Le azioni disponibili per un utente. `discord` fa agire il bot per conto di quell'utente Discord. */
  const scope = (discord?: string) => {
    const get = <T>(path: string) => request<T>("GET", path, undefined, discord)
    const call = <T>(method: string, path: string, body?: unknown) => request<T>(method, path, body ?? {}, discord)
    const id = encodeURIComponent
    return {
      home: () => get<Schema.Home>("/home"),
      guild: {
        get: () => get<Schema.Guild>("/guild"),
        set: (input: In<typeof Schema.GuildInput>) => call<Schema.Guild>("PUT", "/guild", input),
      },
      auth: {
        setup: () => get<{ required: boolean }>("/auth/setup"),
        register: (input: In<typeof Schema.Credentials>) => call<Session>("POST", "/auth/register", input),
        login: (input: { name: string; password: string }) => call<Session>("POST", "/auth/login", input),
        logout: () => call<Ok>("POST", "/auth/logout"),
        me: () => get<Schema.Me>("/auth/me"),
        link: (kind: In<typeof Schema.LinkKind>) => call<Link>("POST", "/auth/link", { kind }),
        redeem: (input: In<typeof Schema.LinkRedeem>) => call<Session>("POST", "/auth/link/redeem", input),
        discord: (input: In<typeof Schema.DiscordLink>) => call<Schema.User>("POST", "/auth/discord", input),
        unlinkDiscord: () => request<Ok>("DELETE", "/auth/discord", undefined, discord),
      },
      member: {
        list: () => get<Schema.Member_[]>("/member"),
        rank: (user: string, rank: Game.Rank) => call<Schema.User>("PATCH", `/member/${id(user)}`, { rank }),
      },
      character: {
        owner: (character: string, userId: string | null) =>
          call<Schema.Character>("PUT", `/character/${id(character)}/owner`, { userId }),
        list: () => get<Schema.Character[]>("/character"),
        get: (name: string) => get<Schema.Character>(`/character/${id(name)}`),
        save: (input: In<typeof Schema.CharacterInput>) => call<Schema.Character>("POST", "/character", input),
        patch: (character: string, input: In<typeof Schema.CharacterPatch>) =>
          call<Schema.Character>("PATCH", `/character/${id(character)}`, input),
        remove: (character: string) => request<Ok>("DELETE", `/character/${id(character)}`, undefined, discord),
      },
      application: {
        list: () => get<Schema.Application[]>("/application"),
        submit: (input: In<typeof Schema.ApplicationInput>) => call<Schema.Application>("POST", "/application", input),
        review: (application: string, input: In<typeof Schema.ApplicationReview>) =>
          call<Schema.Application>("PATCH", `/application/${id(application)}`, input),
      },
      availability: {
        week: (week?: string) => get<Schema.Week>(`/availability${week ? `?week=${id(week)}` : ""}`),
        set: (input: In<typeof Schema.AvailabilityInput>) => call<Schema.Availability>("PUT", "/availability", input),
        say: (text: string) => call<Said>("POST", "/availability/text", { text }),
      },
      group: {
        list: () => get<Schema.Group[]>("/group"),
        create: (input: In<typeof Schema.GroupInput>) => call<Schema.Group>("POST", "/group", input),
        update: (group: string, input: In<typeof Schema.GroupInput>) =>
          call<Schema.Group>("PUT", `/group/${id(group)}`, input),
        remove: (group: string) => request<Ok>("DELETE", `/group/${id(group)}`, undefined, discord),
        setMember: (group: string, input: In<typeof Schema.MemberInput>) =>
          call<Schema.Group>("PUT", `/group/${id(group)}/member`, input),
        removeMember: (group: string, character: string) =>
          request<Schema.Group>("DELETE", `/group/${id(group)}/member/${id(character)}`, undefined, discord),
        schedule: (group: string, week: string) =>
          call<Schema.RaidEvent[]>("POST", `/group/${id(group)}/schedule`, { week }),
      },
      event: {
        list: (range?: { from?: number; to?: number }) => {
          const query = new URLSearchParams()
          if (range?.from !== undefined) query.set("from", String(range.from))
          if (range?.to !== undefined) query.set("to", String(range.to))
          const suffix = query.size > 0 ? `?${query}` : ""
          return get<Schema.RaidEvent[]>(`/raid/event${suffix}`)
        },
        get: (event: string) => get<Schema.RaidEvent>(`/raid/event/${id(event)}`),
        analysis: (event: string) => get<Schema.EventAnalysis>(`/raid/event/${id(event)}/analysis`),
        create: (input: In<typeof Schema.EventInput>) => call<Schema.RaidEvent>("POST", "/raid/event", input),
        update: (event: string, input: In<typeof Schema.EventPatch>) =>
          call<Schema.RaidEvent>("PATCH", `/raid/event/${id(event)}`, input),
        remove: (event: string) => request<Ok>("DELETE", `/raid/event/${id(event)}`, undefined, discord),
        signup: (event: string, input: In<typeof Schema.SignupInput>) =>
          call<Schema.RaidEvent>("PUT", `/raid/event/${id(event)}/signup`, input),
        pick: (event: string, input: In<typeof Schema.PickInput>) =>
          call<Schema.RaidEvent>("PUT", `/raid/event/${id(event)}/pick`, input),
      },
      boss: {
        list: (raid?: string) => get<Schema.Boss[]>(`/boss${raid ? `?raid=${id(raid)}` : ""}`),
        get: (boss: string) => get<Schema.BossDetail>(`/boss/${id(boss)}`),
        create: (input: In<typeof Schema.BossInput>) => call<Schema.BossDetail>("POST", "/boss", input),
        update: (boss: string, input: In<typeof Schema.BossInput>) =>
          call<Schema.BossDetail>("PUT", `/boss/${id(boss)}`, input),
        remove: (boss: string) => request<Ok>("DELETE", `/boss/${id(boss)}`, undefined, discord),
      },
      tactics: {
        get: () => get<Schema.Capabilities>("/tactics"),
        set: (patch: In<typeof Schema.MatrixPatch>) => call<Schema.Capabilities>("PUT", "/tactics", patch),
        rank: (weights: Tactics.Weights) =>
          call<Record<Game.Role, Tactics.Fit[]>>("POST", "/tactics/rank", { weights }),
      },
      post: {
        list: (kind?: "blog" | "guide") => get<Schema.PostSummary[]>(`/post${kind ? `?kind=${kind}` : ""}`),
        get: (kind: "blog" | "guide", slug: string) => get<Schema.Post>(`/post/${kind}/${id(slug)}`),
        create: (input: In<typeof Schema.PostInput>) => call<Schema.Post>("POST", "/post", input),
        update: (post: string, input: In<typeof Schema.PostInput>) =>
          call<Schema.Post>("PUT", `/post/${id(post)}`, input),
        remove: (post: string) => request<Ok>("DELETE", `/post/${id(post)}`, undefined, discord),
      },
      addon: {
        status: () => get<Schema.AddonConnection | null>("/addon/status"),
        connections: () => get<Schema.AddonConnection[]>("/addon/connections"),
        sync: (input: In<typeof Schema.AddonSync>) => call<Schema.SyncResult>("POST", "/addon/sync", input),
        bundle: () => get<Schema.SyncResult>("/addon/bundle"),
      },
    }
  }

  /**
   * Flusso eventi del server (SSE) letto con fetch: funziona dove EventSource non c'e'.
   * Si ricollega da solo; la funzione restituita lo chiude.
   */
  function subscribe(onEvent: (event: Schema.BusEvent) => void, onState?: (online: boolean) => void) {
    const controller = new AbortController()
    const wait = (ms: number) =>
      new Promise<void>((resolve) => {
        const done = () => {
          clearTimeout(timer)
          controller.signal.removeEventListener("abort", done)
          resolve()
        }
        const timer = setTimeout(done, ms)
        controller.signal.addEventListener("abort", done, { once: true })
        if (controller.signal.aborted) done()
      })
    const read = async () => {
      const response = await send(`${base}/event`, {
        headers: { accept: "text/event-stream" },
        signal: controller.signal,
      })
      if (!response.ok || !response.body) throw new ApiError(response.status, "Flusso eventi non disponibile")
      onState?.(true)
      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      const state = { buffer: "" }
      for (;;) {
        const chunk = await reader.read()
        if (chunk.done) return
        state.buffer += decoder.decode(chunk.value, { stream: true })
        const frames = state.buffer.split("\n\n")
        state.buffer = frames.pop() ?? ""
        for (const frame of frames) {
          const data = frame
            .split("\n")
            .filter((line) => line.startsWith("data:"))
            .map((line) => line.slice(5).trim())
            .join("\n")
          if (!data) continue
          const event = (() => {
            try {
              return JSON.parse(data) as Schema.BusEvent
            } catch {
              return undefined
            }
          })()
          if (event) onEvent(event)
        }
      }
    }
    const loop = async () => {
      const state = { delay: 1000 }
      while (!controller.signal.aborted) {
        const started = Date.now()
        await read().catch(() => undefined)
        onState?.(false)
        // Una connessione durata a lungo azzera l'attesa; i fallimenti ripetuti la allungano.
        state.delay = Date.now() - started > 30_000 ? 1000 : Math.min(state.delay * 2, 30_000)
        await wait(state.delay)
      }
    }
    void loop()
    return () => controller.abort()
  }

  return { ...scope(), as: scope, subscribe, url: base }
}

export type Client = ReturnType<typeof createClient>
export type { Game, Schema, Tactics } from "@badb/core"
