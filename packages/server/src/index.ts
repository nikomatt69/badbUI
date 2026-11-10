import { config } from "./ctx"
import { ensure } from "./seed"
import { context, create } from "./server"

const settings = config()
const ctx = context(settings)
if (ensure(ctx)) console.log("Contenuto iniziale creato (gruppi, scheda raid ufficiale, pagine di benvenuto)")
const app = create(ctx)
const port = Number(process.env.PORT ?? 4096)

const server = Bun.serve({ port, fetch: app.fetch, idleTimeout: 60 })
console.log(`badb server  http://localhost:${server.port}  db=${settings.db}  tz=${settings.tz}`)
if (!settings.bot) console.log("BADB_BOT_SECRET non impostato: il bot Discord non potrà collegarsi")

const stop = () => {
  server.stop()
  ctx.db.close()
  process.exit(0)
}
process.on("SIGINT", stop)
process.on("SIGTERM", stop)
