import { Bus, type Config, type Ctx } from "./ctx"
import { open } from "./db"
import { announce } from "./notify"
export function context(config: Config, overrides: Partial<Ctx> = {}): Ctx {
  return {
    db: open(config.db),
    config,
    bus: new Bus(),
    now: () => Date.now(),
    announce: (text) => {
      void announce(config.webhook, text)
    },
    passwords: {
      hash: (password) => Bun.password.hash(password),
      verify: (password, hash) => Bun.password.verify(password, hash),
    },
    ...overrides,
  }
}
