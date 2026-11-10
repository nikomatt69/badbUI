import { expect, test } from "bun:test"
import { context, create } from "@badb/server"
import { createClient } from "@badb/sdk"
import { handle } from "../src/handle"
test("Discord collega un account e aggiorna lo stesso calendario del sito", async () => {
  const ctx = context({ db: ":memory:", tz: "Europe/Rome", origins: [], bot: "shared-secret", webhook: "", web: "" })
  try {
    const app = create(ctx)
    const send: typeof fetch = Object.assign(
      async (input: RequestInfo | URL, init?: RequestInit) => app.request(String(input), init),
      { preconnect: fetch.preconnect },
    )
    const auth = await createClient({ url: "http://test", fetch: send }).auth.register({
      name: "Capo",
      password: "password123",
    })
    const web = createClient({ url: "http://test", token: auth.token, fetch: send })
    const bot = createClient({ url: "http://test", bot: "shared-secret", fetch: send })
    const command = { user: "123456789", username: "capo", args: {} }
    await expect(handle(bot, { ...command, name: "disponibilita", args: { testo: "lunedì sera" } })).rejects.toThrow(
      "collegato",
    )
    const link = await web.auth.link("discord")
    expect(await handle(bot, { ...command, name: "collega", args: { codice: link.code } })).toContain("Collegato")
    expect(
      await handle(bot, { ...command, name: "disponibilita", args: { testo: "tutta la settimana sera" } }),
    ).toContain("Disponibilità aggiornata")
    expect((await web.availability.week()).people[0]?.mask).toBe("001".repeat(7))
    await web.character.save({ name: "Capone", cls: "warrior", spec: "protection" })
    const event = await web.event.create({ raid: "barrow-deeps", date: "2026-12-12", start: 1260 })
    await handle(bot, { ...command, name: "prenota", args: { evento: event.id, presenza: "yes" } })
    expect((await web.event.get(event.id)).signups[0]).toMatchObject({
      name: "Capone",
      status: "yes",
      source: "discord",
    })
  } finally {
    ctx.db.close()
  }
})
