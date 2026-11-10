import { scrypt, timingSafeEqual } from "node:crypto"
import type { Passwords } from "./storage"
const parameters = { N: 32768, r: 8, p: 3, maxmem: 64 * 1024 * 1024 }
const derive = (password: string, salt: string) =>
  new Promise<Buffer>((resolve, reject) => {
    scrypt(password, salt, 64, parameters, (error, result) => (error ? reject(error) : resolve(result)))
  })
/** Codifica portabile con parametri fissi: nessun parametro costoso controllato dalla richiesta. */
export const passwords: Passwords = {
  async hash(password) {
    const salt = Buffer.from(crypto.getRandomValues(new Uint8Array(16))).toString("hex")
    return `$scrypt$32768$8$3$${salt}$${(await derive(password, salt)).toString("hex")}`
  },
  async verify(password, encoded) {
    const parts = encoded.split("$")
    if (
      parts.length !== 7 ||
      parts.slice(1, 5).join("$") !== "scrypt$32768$8$3" ||
      !/^[a-f0-9]{32}$/.test(parts[5]!) ||
      !/^[a-f0-9]{128}$/.test(parts[6]!)
    )
      return false
    return timingSafeEqual(await derive(password, parts[5]!), Buffer.from(parts[6]!, "hex"))
  },
}
