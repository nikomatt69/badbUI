import { For, Show, createResource, onCleanup } from "solid-js"
import "./download.css"

type Artifact = {
  kind: string
  version: string
  name: string
  url: string
  latestUrl: string
  bytes: number
  sha256: string
}
type Release = { version: string; macroCount: number; artifacts: Artifact[] }

function isArtifact(value: unknown): value is Artifact {
  if (!value || typeof value !== "object") return false
  const a = value as Record<string, unknown>
  return typeof a.kind === "string" && typeof a.version === "string"
    && typeof a.name === "string" && typeof a.bytes === "number" && a.bytes > 0
    && typeof a.sha256 === "string" && /^[a-f0-9]{64}$/.test(a.sha256)
    && typeof a.url === "string" && /^\/downloads\/[\w.-]+\.zip$/.test(a.url)
    && typeof a.latestUrl === "string" && /^\/downloads\/[\w.-]+\.zip$/.test(a.latestUrl)
}

export function Downloads() {
  let controller: AbortController | undefined
  onCleanup(() => controller?.abort())
  const [result, { refetch }] = createResource(async (): Promise<{ data?: Release; error?: string }> => {
    controller?.abort()
    const request = new AbortController()
    controller = request
    const timeout = setTimeout(() => request.abort(), 10000)
    try {
      const response = await fetch("/downloads/release.json", { cache: "no-cache", signal: request.signal })
      if (!response.ok) throw new Error("Dati della release non disponibili. Riprova tra poco.")
      const data = await response.json()
      if (!data || typeof data.version !== "string" || !Number.isSafeInteger(data.macroCount)
        || !Array.isArray(data.artifacts) || !data.artifacts.every(isArtifact)
        || !data.artifacts.some((a: Artifact) => a.kind === "addon")) {
        throw new Error("Il catalogo dei download non è disponibile. Riprova tra poco.")
      }
      return { data }
    } catch (error) {
      return { error: error instanceof Error ? error.message : "Impossibile controllare la release." }
    } finally {
      clearTimeout(timeout)
    }
  })
  const artifact = (kind: Artifact["kind"]) => result()?.data?.artifacts.find((a) => a.kind === kind)
  const count = () => result()?.data?.macroCount.toLocaleString("it-IT") ?? "6.000+"
  return (
    <>
      <header class="download-heading">
        <div class="eyebrow"><span class="status-dot" /> DOWNLOAD UFFICIALE · WOW FOREVER</div>
        <h1>Il tuo campo base.<br /><em>Anche in Azeroth.</em></h1>
        <p>BadbUI riunisce interfaccia, profili e macro in un solo pannello. Scarica l’addon, scegli quello che ti serve e prepara il prossimo pull.</p>
      </header>
      <Show when={result()?.error}>
        <div class="notice" role="alert">
          {result()?.error}
          <button class="text-link" onClick={() => void refetch()} disabled={result.loading}>Riprova</button>
        </div>
      </Show>
      <div class="download-layout">
        <section class="download-card" aria-labelledby="addon-download-title">
          <div class="download-card-top"><span class="tiny">ADDON / LUA</span><span class="badge">{artifact("addon") ? `v${artifact("addon")!.version}` : "Release attuale"}</span></div>
          <div class="download-emblem" aria-hidden="true">B<span>UI</span></div>
          <h2 id="addon-download-title">BadbUI</h2>
          <p>La configurazione della tua interfaccia, le macro per ogni specializzazione e il collegamento alla gilda. Tutto a portata di <code>/badb</code>.</p>
          <a class="button primary download-primary" href={artifact("addon")?.url ?? "/downloads/BadbUI-latest.zip"} download="">Scarica BadbUI ZIP <span aria-hidden="true">↧</span></a>
          <p class="download-file">{artifact("addon")?.name ?? "BadbUI-latest.zip"}<Show when={artifact("addon")}> · {Math.ceil(artifact("addon")!.bytes / 1024)} KB</Show> · Nessun login richiesto</p>
          <div class="download-metrics">
            <div><strong>{count()}</strong><span>MACRO IN INGLESE</span></div>
            <div><strong>09</strong><span>CLASSI</span></div>
            <div><strong>27</strong><span>SPECIALIZZAZIONI</span></div>
          </div>
          <Show when={artifact("addon")}>
            <details class="download-checksum"><summary>Verifica del file · SHA-256</summary><code>{artifact("addon")!.sha256}</code></details>
          </Show>
        </section>
        <section class="download-install" aria-labelledby="install-title">
          <div class="eyebrow muted">DALLA CARTELLA AL PRIMO PULL</div>
          <h2 id="install-title">Installalo in tre passi.</h2>
          <ol class="download-steps">
            <li><span>01</span><div><h3>Estrai lo ZIP</h3><p>Chiudi WoW. Apri il file e individua la cartella <code>BadbUI</code>.</p></div></li>
            <li><span>02</span><div><h3>Mettilo nel client Forever</h3><p>Copia la cartella in <code>_forever_/Interface/AddOns/</code>. Il file finale deve essere <code>AddOns/BadbUI/BadbUI.toc</code>.</p></div></li>
            <li><span>03</span><div><h3>Apri il tuo pannello</h3><p>Avvia WoW, abilita BadbUI e scrivi <code>/badb</code>. In Opzioni → AddOn puoi espandere il <strong>+</strong> accanto a BadbUI e aprire il pannello o le macro.</p></div></li>
          </ol>
          <div class="download-update"><span class="tiny">HAI GIÀ BADBUI?</span><p>Chiudi il gioco e sostituisci la cartella dell’addon. Conserva la cartella <code>WTF</code>: contiene profili e impostazioni. Se usi il companion, conserva anche <code>Data/GuildSync.lua</code>.</p></div>
        </section>
      </div>
      <section class="download-features">
        <div><span class="tiny">01 / MACRO</span><h3>Il bersaglio giusto.</h3><p>Focus, mouseover, party1–4, raid1–40, boss1–5 e bersaglio del bersaglio. Cure, dispel, buff, resurrezioni, danno e controllo.</p></div>
        <div><span class="tiny">02 / CATALOGO</span><h3>Scegli. Attiva. Gioca.</h3><p>Filtra per classe, specializzazione, PvE, PvP e bersaglio. Cerca una spell e sfoglia pagine da 100 macro con <code>/badb macro</code>.</p></div>
        <div><span class="tiny">03 / INTERFACCIA</span><h3>Un pannello, il tuo stile.</h3><p>Gestisci moduli, profili e layout. Il menu AddOn di WoW include collegamenti al pannello, alle macro, ai profili e all’aiuto.</p></div>
      </section>
      <section class="panel download-companion">
        <div><div class="eyebrow muted">FACOLTATIVO / WINDOWS · MACOS · LINUX</div><h2>Collega il gioco alla gilda.</h2><p>Il companion sincronizza armory e dati di gilda con il sito. Per usare interfaccia e macro basta l’addon. Il companion richiede Bun.</p><a class="text-link" href="#/collegamento">Istruzioni di collegamento ↗</a></div>
        <a class="button" href={artifact("companion")?.url ?? "/downloads/Fratelli-Companion-latest.zip"} download="">Scarica companion ↧</a>
      </section>
      <div class="section-line"><h2>Prima del prossimo pull.</h2><span class="tiny muted">DOMANDE FREQUENTI</span></div>
      <For each={[
        ["Posso attivare tutte le macro?", "Il catalogo offre migliaia di scelte, ma il client ha un numero limitato di slot. Attiva le macro che usi davvero; le altre restano consultabili nel catalogo."],
        ["Le macro arena funzionano su Forever?", "Le versioni arena1–5 sono template di compatibilità per client con arene. Forever attualmente non offre arene. Per i compagni si usano le versioni party1–4."],
        ["Le macro sono già state provate nel gioco?", "Il catalogo è verificato con API simulate. Spell, talenti, immunità e unità boss vanno verificati nel client reale. Puoi leggere e modificare ogni macro dal pannello Code."],
      ]}>{([question, answer]) => <details class="panel"><summary>{question}</summary><p>{answer}</p></details>}</For>
    </>
  )
}
