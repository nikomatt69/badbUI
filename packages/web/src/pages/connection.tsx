import { For, Show, createResource, createSignal } from "solid-js"
import { Addon, Game, type Schema } from "@badb/core"
import { api, me, revision, act, pending } from "../state"
import { Gate, Heading, Empty } from "../ui"
export function Connection() {
  const [status] = createResource(
    () => (me() ? revision() : false),
    () => api.addon.status(),
  )
  const [code, setCode] = createSignal<{ code: string; expires: number }>()
  const [file, setFile] = createSignal<File>()
  const [preview, setPreview] = createSignal<Schema.AddonSync>()
  const [error, setError] = createSignal("")
  async function read(selected: File | undefined) {
    setFile(selected)
    setPreview(undefined)
    setError("")
    if (!selected) return
    if (selected.size > 8_000_000) {
      setError("Il file supera il limite di 8 MB.")
      return
    }
    try {
      setPreview(Addon.decode(await selected.text()))
    } catch (e) {
      setError(e instanceof Error ? e.message : "File non valido")
    }
  }
  return (
    <>
      <Heading
        label="IL CLIENT, COLLEGATO ALLA GILDA"
        title="La tua armory. Quella vera."
        text="Equipaggiamento, livello e professioni arrivano dal tuo client Forever. Qui puoi collegarlo e controllare l’ultima importazione."
      />
      <section class="panel">
        <h2>1. Installa l’addon e il companion</h2>
        <p>Il companion gira sul PC di gioco e invia i dati allo stesso server del sito. Non serve Discord.</p>
        <div class="filters">
          <a class="button primary" href="/downloads/BadbUI-latest.zip" download="">
            Scarica addon WoW ↧
          </a>
          <a class="button" href="/downloads/Fratelli-Companion-latest.zip" download="">
            Scarica companion ↧
          </a>
        </div>
        <a class="text-link" href="#/download">Versione attuale e istruzioni di installazione ↗</a>
        <p>
          Estrai l’addon in <code>Interface/AddOns</code>. Il companion richiede Bun e include le istruzioni per
          Windows, macOS e Linux. In gioco apri <code>/badb gilda</code>.
        </p>
      </section>
      <Gate>
        <section class="panel">
          <h2>2. Collega il tuo account</h2>
          <p>Il codice serve solo al companion. Non contiene la tua password e scade dopo dieci minuti.</p>
          <button
            class="button primary"
            disabled={pending()}
            onClick={() => act(async () => setCode(await api.auth.link("addon")), "Codice addon generato.")}
          >
            Genera codice addon ↗
          </button>
          <Show when={code()}>
            {(value) => (
              <div class="link-code">
                <code>{value().code}</code>
                <p>Valido fino alle {new Date(value().expires).toLocaleTimeString("it-IT")}</p>
                <p>Nel terminale, dalla cartella del companion:</p>
                <pre class="command-block">{`bun companion.mjs login ${value().code} --wow "<cartella client Forever>" --account "<account WTF>"\nbun companion.mjs watch`}</pre>
              </div>
            )}
          </Show>
          <p>
            Dopo aver avviato il companion: fai <code>/reload</code> in gioco, attendi “Dati pronti”, poi un altro{" "}
            <code>/reload</code> per ricevere la risposta.
          </p>
        </section>
        <section class="panel">
          <h2>3. Stato della sincronizzazione</h2>
          <Show
            when={status()}
            fallback={
              <Empty>
                Nessuna scansione ricevuta dal tuo account. Dopo il collegamento i dati reali compariranno qui e
                nell’armory.
              </Empty>
            }
          >
            {(value) => (
              <>
                <p class="eyebrow">ULTIMO INVIO RICEVUTO {new Date(value().received).toLocaleString("it-IT")}</p>
                <p>
                  Client {value().client?.version ?? "non registrato"} · build{" "}
                  {value().client?.build ?? "non registrata"}
                </p>
                <div class="composition">
                  <div>
                    <strong>{value().characters}</strong>
                    <span>Personaggi</span>
                  </div>
                  <div>
                    <strong>{value().roster}</strong>
                    <span>Voci roster</span>
                  </div>
                  <div>
                    <strong>{value().actions}</strong>
                    <span>Azioni ricevute</span>
                  </div>
                </div>
                <For each={value().rejected}>
                  {(failure) => (
                    <p role="alert">
                      {failure.id}: {failure.error}
                    </p>
                  )}
                </For>
                <a class="button" href="#/armory">
                  Apri l’armory ↗
                </a>
              </>
            )}
          </Show>
          <button class="text-link" onClick={() => act(async () => {}, "Stato aggiornato.")}>
            Controlla aggiornamenti
          </button>
        </section>
        <details class="panel">
          <summary>Importa uno snapshot senza companion</summary>
          <p>
            Seleziona <code>WTF/Account/&lt;account&gt;/SavedVariables/BadbUI.lua</code> dopo un /reload o logout. Il
            sito legge soltanto i dati esportati dal modulo gilda; il file Lua non viene eseguito.
          </p>
          <label>
            File SavedVariables
            <input
              type="file"
              accept=".lua"
              onChange={(event) => {
                void read(event.currentTarget.files?.[0])
              }}
            />
          </label>
          <Show when={error()}>
            <p role="alert">{error()}</p>
          </Show>
          <Show when={preview()}>
            {(input) => (
              <div class="stack">
                <p>
                  {file()?.name}: {input().characters.length} personaggi · {input().roster.length} voci roster ·{" "}
                  {input().actions.length} azioni.
                </p>
                <For each={input().characters}>
                  {(character) => (
                    <p style={{ color: Game.classes[character.cls].color }}>
                      {character.name} · livello {character.level} · {character.gear.length} oggetti
                    </p>
                  )}
                </For>
                <button
                  class="button primary"
                  disabled={pending()}
                  onClick={() =>
                    act(async () => {
                      await api.addon.sync(input())
                      setPreview(undefined)
                    }, "Scansione Forever importata nell’armory.")
                  }
                >
                  Importa questi dati reali ↗
                </button>
              </div>
            )}
          </Show>
        </details>
      </Gate>
    </>
  )
}
