// Impostazioni della gilda e dati della home.
import { Game, type Schema } from "@badb/core"
import { json, touch, type Ctx } from "./ctx"
import * as Post from "./post"
import * as Raid from "./raid"

export const defaults: Schema.Guild = {
  name: "Badb",
  realm: "",
  motto: "Una gilda, tre fasce orarie, nessuna scusa.",
  about: "",
  discordInvite: "",
  feeSilver: 3,
  wowhead: "classic",
  recruiting: [...Game.classIds],
}

export function get(ctx: Ctx): Schema.Guild {
  const row = ctx.db.query<{ value: string }, []>("SELECT value FROM setting WHERE key = 'guild'").get()
  return { ...defaults, ...json<Partial<Schema.Guild>>(row?.value, {}) }
}

export function set(ctx: Ctx, input: Schema.Guild) {
  ctx.db.run("INSERT INTO setting (key, value) VALUES ('guild', ?1) ON CONFLICT(key) DO UPDATE SET value = ?1", [JSON.stringify(input)])
  touch(ctx, { type: "guild" })
  return get(ctx)
}

export function home(ctx: Ctx): Schema.Home {
  const count = (sql: string) => ctx.db.query<{ n: number }, []>(sql).get()?.n ?? 0
  return {
    guild: get(ctx),
    members: count("SELECT COUNT(*) AS n FROM user WHERE rank != 'guest'"),
    characters: count("SELECT COUNT(*) AS n FROM character WHERE in_guild = 1"),
    news: Post.list(ctx, "blog", false, 4),
    events: Raid.upcoming(ctx, 5),
  }
}
