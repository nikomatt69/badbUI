import { config } from "./ctx"
import { context } from "./context"
import { ensure } from "./seed"
const ctx = context(config())
console.log(ensure(ctx) ? "Contenuto iniziale creato" : "Database già inizializzato")
ctx.db.close()
