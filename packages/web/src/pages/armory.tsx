import { For, Show, createResource, createSignal } from "solid-js"
import { Game } from "@badb/core"
import { api, revision, me, act } from "../state"
import { Heading, Empty } from "../ui"
export function Armory() {
  const officer = () => me() && Game.rankAtLeast(me()!.user.rank, "officer")
  const [members] = createResource(
    () => (officer() ? revision() : false),
    () => api.member.list(),
  )
  const [data] = createResource(revision, () => api.character.list())
  const [guild] = createResource(revision, () => api.guild.get())
  const [query, setQuery] = createSignal("")
  const [cls, setCls] = createSignal("")
  const [selected, setSelected] = createSignal("")
  const list = () =>
    data()?.filter((c) => (!cls() || c.cls === cls()) && c.name.toLowerCase().includes(query().toLowerCase()))
  const current = () => data()?.find((c) => c.id === selected())
  return (
    <>
      <Heading
        label="LE PERSONE DIETRO IL PARTY"
        title="Il nostro armory."
        text="Personaggi, ruoli ed equipaggiamento. Le schede lette dall’addon riportano l’ultimo aggiornamento ricevuto."
      />
      <div class="filters">
        <a class="button primary" href="#/collegamento">
          Collega il client Forever ↗
        </a>
        <label>
          Cerca
          <input
            type="search"
            value={query()}
            onInput={(e) => setQuery(e.currentTarget.value)}
            placeholder="Nome personaggio…"
          />
        </label>
        <label>
          Classe
          <select value={cls()} onChange={(e) => setCls(e.currentTarget.value)}>
            <option value="">Tutte le classi</option>
            <For each={Game.classList}>{(c) => <option value={c.id}>{c.label}</option>}</For>
          </select>
        </label>
        <span class="muted">{list()?.length ?? 0} personaggi</span>
      </div>
      <div class="armory-layout">
        <div class="panel scroll-table">
          <Show
            when={list()?.length}
            fallback={<Empty>Nessun personaggio trovato. Collega il client Forever per importare dati reali.</Empty>}
          >
            <table>
              <thead>
                <tr>
                  <th>Personaggio</th>
                  <th>Classe / ruolo</th>
                  <th>Livello</th>
                  <th>Fonte</th>
                </tr>
              </thead>
              <tbody>
                <For each={list()}>
                  {(c) => (
                    <tr classList={{ current: selected() === c.id }}>
                      <td>
                        <button
                          class="character-name"
                          style={{ color: Game.classes[c.cls].color }}
                          onClick={() => setSelected(c.id)}
                        >
                          {c.name} {c.main ? "✦" : ""}
                        </button>
                      </td>
                      <td>
                        {Game.classes[c.cls].label}
                        <small>
                          {Game.findSpec(c.cls, c.spec)?.label ?? "Spec da definire"} · {Game.roleLabel[c.role]}
                        </small>
                      </td>
                      <td>{c.level}</td>
                      <td>{c.source === "addon" ? "Addon Forever" : "Manuale"}</td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </Show>
        </div>
        <aside class="panel character-detail">
          <Show
            when={current()}
            fallback={
              <div class="empty">
                <span class="detail-mark">✦</span>
                <h2>Ogni ruolo conta.</h2>
                <p>Seleziona un personaggio per vedere equipaggiamento e professioni.</p>
              </div>
            }
          >
            {(c) => (
              <>
                <span class="eyebrow">
                  {c().realm || "FOREVER"} / LIVELLO {c().level}
                </span>
                <h2 style={{ color: Game.classes[c().cls].color }}>{c().name}</h2>
                <Show when={officer()}>
                  <label>
                    Account collegato
                    <select
                      value={c().userId ?? ""}
                      onChange={(e) =>
                        act(
                          () => api.character.owner(c().id, e.currentTarget.value || null),
                          "Collegamento del personaggio aggiornato.",
                        )
                      }
                    >
                      <option value="">Nessun account</option>
                      <For each={members()}>{(member) => <option value={member.id}>{member.name}</option>}</For>
                    </select>
                  </label>
                </Show>
                <p>
                  {Game.classes[c().cls].label} · {Game.roleLabel[c().role]}
                </p>
                <p class="tiny muted">
                  {c().scannedAt
                    ? `SCANSIONE ${new Date(c().scannedAt!).toLocaleString("it-IT")}`
                    : "NESSUNA SCANSIONE COMPLETA"}
                </p>
                <p class="tiny muted">
                  {c().client
                    ? `CLIENT ${c().client!.version} · BUILD ${c().client!.build} · INTERFACCIA ${c().client!.interface}`
                    : c().source === "site"
                      ? "DATI DICHIARATI MANUALMENTE"
                      : "BUILD CLIENT NON REGISTRATA"}
                </p>
                <h3>Equipaggiamento {c().itemLevel !== null ? `· ilvl ${c().itemLevel}` : ""}</h3>
                <Show when={c().gear.length} fallback={<p class="muted">Equipaggiamento non ancora sincronizzato.</p>}>
                  <For each={c().gear}>
                    {(item) => (
                      <a
                        class="gear-row"
                        href={`https://www.wowhead.com/${guild()?.wowhead ? guild()!.wowhead + "/" : ""}item=${item.id}`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        <small>{Game.gearSlots.find((s) => s.id === item.slot)?.label ?? `Slot ${item.slot}`}</small>
                        <span style={{ color: Game.qualityColor[Math.min(item.quality, 5)] }}>
                          {item.name || `Oggetto ${item.id}`} ↗
                        </span>
                      </a>
                    )}
                  </For>
                </Show>
                <h3>Professioni</h3>
                <For each={c().professions}>
                  {(p) => (
                    <p>
                      {p.name} / {p.rank}
                    </p>
                  )}
                </For>
                <p class="tiny muted">
                  I link Wowhead sono un riferimento: gli oggetti modificati su Forever possono differire.
                </p>
              </>
            )}
          </Show>
        </aside>
      </div>
    </>
  )
}
