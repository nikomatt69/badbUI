import { createSignal } from "solid-js"
import { createClient, ApiError, type Schema } from "@badb/sdk"
// Sessione limitata alla scheda. Logout la revoca anche sul server.
const [token, setToken] = createSignal(sessionStorage.getItem("badb.session"))
export const api = createClient({
  url: import.meta.env.VITE_BADB_SERVER ?? (import.meta.env.DEV ? "http://localhost:4096" : location.origin),
  token,
})
export const [me, setMe] = createSignal<Schema.Me | null>(null)
export const [revision, setRevision] = createSignal(0)
export const refresh = () => setRevision((n) => n + 1)
export const [notice, setNotice] = createSignal("")
export const [pending, setPending] = createSignal(false)
export async function loadMe() {
  if (!token()) return setMe(null)
  try {
    setMe(await api.auth.me())
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) session(null)
    else throw error
  }
}
export function session(value: string | null) {
  setToken(value)
  if (value) sessionStorage.setItem("badb.session", value)
  else {
    sessionStorage.removeItem("badb.session")
    setMe(null)
  }
  refresh()
}
export async function act(work: () => Promise<unknown>, message = "Salvato.") {
  if (pending()) return
  setPending(true)
  setNotice("")
  try {
    await work()
    await loadMe()
    refresh()
    setNotice(message)
  } catch (error) {
    setNotice(
      error instanceof ApiError
        ? [error.message, ...error.issues.map((i) => `${i.path}: ${i.message}`)].join(" · ")
        : error instanceof Error
          ? error.message
          : "Operazione non riuscita",
    )
  } finally {
    setPending(false)
  }
}
export const form = (event: SubmitEvent) => {
  event.preventDefault()
  return new FormData(event.currentTarget as HTMLFormElement)
}
export const field = (data: FormData, key: string) => String(data.get(key) ?? "")
export const clock = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`
export const minutes = (value: string) => {
  const [h, m] = value.split(":").map(Number)
  return h! * 60 + m!
}
