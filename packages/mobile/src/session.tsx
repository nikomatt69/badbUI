import { createContext, useContext, useState, useEffect, type ReactNode } from "react"
import * as SecureStore from "expo-secure-store"
import { createClient, DEFAULT_SERVER_URL, type Client, type Schema } from "@badb/sdk"
const INITIAL = process.env.EXPO_PUBLIC_BADB_SERVER ?? DEFAULT_SERVER_URL
type State = {
  api: Client
  me: Schema.Me | null
  ready: boolean
  error: string
  server: string
  revision: number
  connect: (server: string, code: string) => Promise<void>
  logout: () => Promise<void>
  refresh: () => Promise<void>
}
const Context = createContext<State | null>(null)
export function SessionProvider({ children }: { children: ReactNode }) {
  const [server, setServer] = useState(INITIAL)
  const [token, setToken] = useState<string | null>(null)
  const [me, setMe] = useState<Schema.Me | null>(null)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState("")
  const [revision, setRevision] = useState(0)
  const api = createClient({ url: server, token })
  useEffect(() => {
    let active = true
    SecureStore.getItemAsync("badb.connection")
      .then(async (raw) => {
        if (!raw || !active) return
        const saved = JSON.parse(raw) as { server: string; token: string }
        const client = createClient({ url: saved.server, token: saved.token })
        const user = await client.auth.me()
        if (active) {
          setServer(saved.server)
          setToken(saved.token)
          setMe(user)
        }
      })
      .catch((e: Error) => {
        if (active) setError(e.message)
      })
      .finally(() => {
        if (active) setReady(true)
      })
    return () => {
      active = false
    }
  }, [])
  async function refresh() {
    if (token) setMe(await api.auth.me())
    setRevision((n) => n + 1)
  }
  async function connect(address: string, code: string) {
    const url = new URL(address.trim())
    if (!["http:", "https:"].includes(url.protocol)) throw new Error("Indirizzo server non valido")
    const next = createClient({ url: url.origin })
    const session = await next.auth.redeem({ code: code.trim().toUpperCase(), label: "App Fratelli di Azeroth" })
    const linked = await createClient({ url: url.origin, token: session.token }).auth.me()
    await SecureStore.setItemAsync("badb.connection", JSON.stringify({ server: url.origin, token: session.token }))
    setServer(url.origin)
    setToken(session.token)
    setMe(linked)
    setError("")
    setRevision((n) => n + 1)
  }
  async function logout() {
    await api.auth.logout()
    await SecureStore.deleteItemAsync("badb.connection")
    setToken(null)
    setMe(null)
    setRevision((n) => n + 1)
  }
  return (
    <Context.Provider value={{ api, server, me, ready, error, revision, connect, logout, refresh }}>
      {children}
    </Context.Provider>
  )
}
export function useSession() {
  const session = useContext(Context)
  if (!session) throw new Error("Session provider missing")
  return session
}
