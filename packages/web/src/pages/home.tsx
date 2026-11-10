import { For, Show, createResource } from "solid-js"
import { Game } from "@badb/core"
import { api, revision, clock } from "../state"
import { Empty } from "../ui"
export function Home() {
  const [data] = createResource(revision, () => api.home())
  const [groups] = createResource(revision, () => api.group.list())
  return (
    <Show when={data()}>
      {(home) => (
        <>
          <section class="hero">
            <div class="hero-copy">
              <div class="eyebrow">
                <span class="status-dot" /> {home().guild.name.toUpperCase()} · RECLUTAMENTO APERTO
              </div>
              <h1>
                Stesso stendardo.
                <br />
                <em>Il tuo orario.</em>
              </h1>
              <p>{home().guild.motto}</p>
              <div class="hero-actions">
                <a class="button primary" href="#/raid">
                  Trova il tuo prossimo raid ↗
                </a>
                <a class="text-link" href="#/disponibilita">
                  Segna quando ci sei →
                </a>
              </div>
              <div class="hero-stats">
                <div>
                  <strong>{home().members.toString().padStart(2, "0")}</strong>
                  <span>MEMBRI</span>
                </div>
                <div>
                  <strong>{home().characters.toString().padStart(2, "0")}</strong>
                  <span>PERSONAGGI</span>
                </div>
                <div>
                  <strong>{(groups()?.length ?? 0).toString().padStart(2, "0")}</strong>
                  <span>GRUPPI RAID</span>
                </div>
              </div>
            </div>
            <div class="hero-art" aria-hidden="true">
              <div class="orbit orbit-one" />
              <div class="orbit orbit-two" />
              <div class="rune">ᚠ</div>
              <span class="art-label">
                EST. IN AZEROTH
                <br />
                READY WHEN YOU ARE.
              </span>
              <span class="coordinates">40° / 20° / 10°</span>
            </div>
          </section>
          <div class="section-line">
            <h2>Tre modi di esserci.</h2>
            <span class="tiny muted">UNA SOLA GILDA</span>
          </div>
          <div class="group-grid">
            <For each={groups()}>
              {(g, i) => (
                <a class={`group-card slot-${g.slot}`} href="#/raid">
                  <span class="card-index">
                    0{i() + 1} / {g.slot.toUpperCase()}
                  </span>
                  <span class="group-symbol">{["☼", "◒", "☾"][i() % 3]}</span>
                  <h3>{g.name}</h3>
                  <p>
                    {g.days.map((d) => Game.dayShort[d]).join(" · ")} / {clock(g.start)}
                  </p>
                  <div class="card-foot">
                    <span>
                      {g.members.length} membri · {Game.findRaid(g.raid)?.size} posti
                    </span>
                    <span>↗</span>
                  </div>
                </a>
              )}
            </For>
          </div>
          <div class="home-columns">
            <section>
              <div class="section-line">
                <h2>Prossimi pull</h2>
                <a href="#/raid">Calendario ↗</a>
              </div>
              <Show
                when={home().events.length}
                fallback={
                  <Empty>
                    Il calendario aspetta il primo raid. Gli ufficiali possono pianificarlo dalla sezione Raid.
                  </Empty>
                }
              >
                <For each={home().events}>
                  {(e) => (
                    <a class="event-row" href="#/raid">
                      <div class="date-block">
                        <strong>{e.date.slice(-2)}</strong>
                        <span>{new Date(e.startsAt).toLocaleDateString("it-IT", { month: "short" })}</span>
                      </div>
                      <div>
                        <h3>{e.title}</h3>
                        <p>
                          {e.group ?? "Raid di gilda"} · {clock(e.start)}
                        </p>
                      </div>
                      <span class="badge">{e.signups.filter((s) => s.status === "yes").length} iscritti</span>
                      <span>↗</span>
                    </a>
                  )}
                </For>
              </Show>
            </section>
            <section>
              <div class="section-line">
                <h2>Dal campo base</h2>
                <a href="#/blog">Il diario ↗</a>
              </div>
              <For each={home().news}>
                {(p) => (
                  <a class="news-row" href="#/blog">
                    <span class="eyebrow muted">{p.category || "DIARIO"}</span>
                    <h3>{p.title}</h3>
                    <p>{p.excerpt}</p>
                  </a>
                )}
              </For>
              <Show when={home().guild.discordInvite}>
                <a class="discord-card" href={home().guild.discordInvite} target="_blank" rel="noreferrer">
                  <div class="tiny">IL RAID COMINCIA IN VOCALE</div>
                  <h3>Ci trovi su Discord. ↗</h3>
                </a>
              </Show>
            </section>
          </div>
        </>
      )}
    </Show>
  )
}
