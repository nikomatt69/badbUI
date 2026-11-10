import { For, Match, Switch, Show, createSignal, onMount, onCleanup, ErrorBoundary, Suspense } from "solid-js"
import { Game } from "@badb/core"
import { api, me, loadMe, refresh, notice, setNotice, act } from "./state"
import { Home } from "./pages/home"
import { AvailabilityPage } from "./pages/availability"
import { Raids } from "./pages/raids"
import { Armory } from "./pages/armory"
import { Library, Tactics } from "./pages/content"
import { Connection } from "./pages/connection"
import { Downloads } from "./pages/download"
import { Profile, Application, Admin } from "./pages/account"
const links = [
  ["", "01", "Quartier generale"],
  ["raid", "02", "Calendario raid"],
  ["disponibilita", "03", "Chi c’è?"],
  ["armory", "04", "Armory"],
  ["collegamento", "↗", "Collega WoW"],
  ["download", "↓", "Scarica BadbUI"],
  ["tattiche", "05", "Boss & tattiche"],
  ["guide", "06", "Guide"],
  ["blog", "07", "Diario di gilda"],
]
export function App() {
  const [path, setPath] = createSignal(location.hash.replace(/^#\/?/, ""))
  onMount(() => {
    const route = () => {
      setPath(location.hash.replace(/^#\/?/, ""))
      window.scrollTo(0, 0)
    }
    window.addEventListener("hashchange", route)
    void loadMe().catch((e: Error) => setNotice(e.message))
    const off = api.subscribe((event) => {
      if (["user", "character", "application"].includes(event.type))
        void loadMe().catch((e: Error) => setNotice(e.message))
      if (event.type !== "connected") refresh()
    })
    onCleanup(() => {
      off()
      window.removeEventListener("hashchange", route)
    })
  })
  return (
    <div class="shell">
      <aside class="sidebar">
        <a class="brand" href="#/">
          <span class="sigil">F</span>
          <span>
            <span class="brand-name">
              Fratelli<span>di Azeroth</span>
            </span>
            <span class="brand-sub">GILDA · WOW FOREVER</span>
          </span>
        </a>
        <div class="nav-label">IL NOSTRO CAMPO BASE</div>
        <nav aria-label="Navigazione principale">
          <For each={links}>
            {([url, n, label]) => (
              <a classList={{ active: path() === url }} href={`#/${url}`}>
                <small>{n}</small>
                {label}
                <span class="nav-arrow">↗</span>
              </a>
            )}
          </For>
        </nav>
        <div class="sidebar-bottom">
          <span class="tiny">UN PARTY. TRE ORARI.</span>
          <p>
            Il prossimo pull
            <br />
            comincia qui.
          </p>
          <a class="button" href="#/candidatura">
            Entra in gilda <span>↗</span>
          </a>
        </div>
      </aside>
      <div class="workspace">
        <header class="topbar">
          <a href="#/" class="mobile-brand">
            Fratelli di Azeroth /
          </a>
          <span class="tiny">
            WORLD OF WARCRAFT <span class="muted">/</span> FOREVER
          </span>
          <div class="top-actions">
            <Show when={me() && Game.rankAtLeast(me()!.user.rank, "officer")}>
              <a href="#/gestione">Gestione</a>
            </Show>
            <a class="account" href="#/profilo">
              <span class="status-dot" />
              {me()?.user.name ?? "Accedi"}
            </a>
          </div>
        </header>
        <main>
          <Show when={notice()}>
            <div role="status" class="notice">
              {notice()}
              <button aria-label="Chiudi messaggio" onClick={() => setNotice("")}>
                ×
              </button>
            </div>
          </Show>
          <ErrorBoundary
            fallback={(e, reset) => (
              <div role="alert" class="empty">
                <h2>Impossibile caricare i dati</h2>
                <p>{String(e.message ?? e)}</p>
                <button class="button" onClick={reset}>
                  Riprova
                </button>
              </div>
            )}
          >
            <Suspense
              fallback={
                <p class="empty" role="status">
                  Caricamento dal campo base…
                </p>
              }
            >
              <Switch
                fallback={
                  <div class="empty">
                    Pagina non trovata. <a href="#/">Torna alla home</a>
                  </div>
                }
              >
                <Match when={path() === ""}>
                  <Home />
                </Match>
                <Match when={path() === "raid"}>
                  <Raids />
                </Match>
                <Match when={path() === "disponibilita"}>
                  <AvailabilityPage />
                </Match>
                <Match when={path() === "collegamento"}>
                  <Connection />
                </Match>
                <Match when={path() === "download"}>
                  <Downloads />
                </Match>
                <Match when={path() === "armory"}>
                  <Armory />
                </Match>
                <Match when={path() === "tattiche"}>
                  <Tactics />
                </Match>
                <Match when={path() === "guide" || path() === "blog"}>
                  <Library kind={path() === "guide" ? "guide" : "blog"} />
                </Match>
                <Match when={path() === "profilo"}>
                  <Profile />
                </Match>
                <Match when={path() === "candidatura"}>
                  <Application />
                </Match>
                <Match when={path() === "gestione"}>
                  <Admin />
                </Match>
              </Switch>
            </Suspense>
          </ErrorBoundary>
        </main>
        <footer>
          <span>FRATELLI DI AZEROTH / GILDA</span>
          <span>Ci vediamo al prossimo pull. ↗</span>
        </footer>
      </div>
    </div>
  )
}
