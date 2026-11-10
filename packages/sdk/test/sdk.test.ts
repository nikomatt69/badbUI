import { expect, test } from "bun:test"
import { context, create } from "@badb/server"
import { ApiError, createClient } from "../src"

function setup() {
  const ctx = context(
    { db: ":memory:", tz: "Europe/Rome", origins: [], bot: "s3cret", webhook: "", web: "" },
    { announce: () => {} },
  )
  const app = create(ctx)
  const local: typeof fetch = Object.assign(
    async (input: RequestInfo | URL, init?: RequestInit) => app.request(String(input), init),
    { preconnect: fetch.preconnect },
  )
  return { ctx, local }
}

test("flusso completo attraverso l'SDK", async () => {
  const { local } = setup()
  const session = { token: null as string | null }
  const client = createClient({ url: "http://badb.test/", token: () => session.token, fetch: local })
  session.token = (await client.auth.register({ name: "Capo", password: "password123" })).token
  expect((await client.auth.me()).user.rank).toBe("gm")
  const character = await client.character.save({ name: "Capone", cls: "warrior", spec: "protection" })
  expect(character.role).toBe("tank")
  const said = await client.availability.say("tutta la settimana sera")
  expect(said.entry.mask).toBe("001".repeat(7))
  const group = await client.group.create({ name: "Sera", slot: "sera", raid: "onyxia", start: 1260, days: [2] })
  const [event] = await client.group.schedule(group.id, said.week)
  await client.event.signup(event!.id, { status: "yes" })
  expect((await client.event.list({ from: event!.startsAt - 1, to: event!.startsAt + 1 }))[0]!.signups[0]!.name).toBe(
    "Capone",
  )
  const failure = await client.event.get("nope").catch((error) => error)
  expect(failure).toBeInstanceOf(ApiError)
  expect(failure.status).toBe(404)
  const invalid = await client.character.save({ name: "1", cls: "mage" }).catch((error) => error)
  expect(invalid.issues[0].path).toBe("name")

  // Il bot agisce per l'utente Discord collegato.
  const link = await client.auth.link("discord")
  const bot = createClient({ url: "http://badb.test", bot: "s3cret", fetch: local })
  await bot.auth.discord({ code: link.code, discordId: "4242424242" })
  const viaBot = await bot.as("4242424242").availability.say("non ci sono lunedì")
  expect(viaBot.entry.mask.slice(0, 3)).toBe("000")
  expect(viaBot.entry.source).toBe("discord")
})

test("subscribe riceve gli eventi e si chiude", async () => {
  const { local } = setup()
  const client = createClient({ url: "http://badb.test", fetch: local })
  const seen: string[] = []
  const done = Promise.withResolvers<void>()
  const stop = client.subscribe((event) => {
    seen.push(event.type)
    if (event.type === "user") done.resolve()
  })
  await Bun.sleep(20)
  await client.auth.register({ name: "Capo", password: "password123" })
  await done.promise
  stop()
  expect(seen).toEqual(["connected", "user"])
})
