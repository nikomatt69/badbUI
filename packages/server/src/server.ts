import { serveStatic } from "hono/bun"
import { create as api } from "./app"
import type { Ctx } from "./ctx"
export { context } from "./context"
export function create(ctx: Ctx) {
  const app = api(ctx)
  if (ctx.config.web) {
    app.use("*", serveStatic({ root: ctx.config.web }))
    app.get("*", serveStatic({ root: ctx.config.web, path: "index.html" }))
  }
  return app
}
export type App = ReturnType<typeof create>
