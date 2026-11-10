import { For, Show, createResource, createSignal, createEffect } from "solid-js"
import { Availability, Game } from "@badb/core"
import { api, me, revision, act, form, field, pending } from "../state"
import { Gate, Heading, Submit, Empty } from "../ui"
export function AvailabilityPage() {
  const [week, setWeek] = createSignal(Availability.currentWeek(new Date(), "Europe/Rome"))
  const [mask, setMask] = createSignal("0".repeat(21))
  const [data] = createResource(
    () => (me() && Game.rankAtLeast(me()!.user.rank, "member") ? ([week(), revision()] as const) : false),
    ([w]) => api.availability.week(w),
  )
  createEffect(() => setMask(data()?.people.find((p) => p.userId === me()?.user.id)?.mask ?? "0".repeat(21)))
  const move = (days: number) => setWeek(Availability.addDays(week(), days))
  return (
    <>
      <Heading
        label="IL TEMPO È LA NOSTRA RISORSA"
        title="Chi c’è questa settimana?"
        text="Un click per dire quando giochi. Mattina, pomeriggio o sera: troviamo il momento giusto."
      />
      <Gate member>
        <section class="panel">
          <div class="section-line">
            <div class="week-control">
              <button class="icon-button" aria-label="Settimana precedente" onClick={() => move(-7)}>
                ←
              </button>
              <strong>
                {week()} — {Availability.addDays(week(), 6)}
              </strong>
              <button class="icon-button" aria-label="Settimana successiva" onClick={() => move(7)}>
                →
              </button>
            </div>
            <span class="tiny muted">EUROPE/ROME</span>
          </div>
          <div class="scroll-table">
            <table class="availability-table">
              <thead>
                <tr>
                  <th>La tua settimana</th>
                  <For each={Game.dayShort}>
                    {(day, i) => (
                      <th>
                        {day}
                        <small>{Availability.addDays(week(), i()).slice(-2)}</small>
                      </th>
                    )}
                  </For>
                </tr>
              </thead>
              <tbody>
                <For each={Game.slotList}>
                  {(slot, s) => (
                    <tr>
                      <th>
                        {slot.label}
                        <small>
                          {slot.start / 60}:00–{slot.end / 60}:00
                        </small>
                      </th>
                      <For each={Game.dayShort}>
                        {(_, d) => {
                          const index = () => d() * 3 + s()
                          return (
                            <td>
                              <button
                                disabled={pending()}
                                class="slot-cell"
                                classList={{ selected: mask()[index()] === "1" }}
                                aria-label={`${Game.dayLabels[d()]} ${slot.label}`}
                                aria-pressed={mask()[index()] === "1"}
                                onClick={() =>
                                  setMask(
                                    (m) =>
                                      m.slice(0, index()) + (m[index()] === "1" ? "0" : "1") + m.slice(index() + 1),
                                  )
                                }
                              >
                                {mask()[index()] === "1" ? "✓" : "+"}
                              </button>
                            </td>
                          )
                        }}
                      </For>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
          <div class="form-actions">
            <p class="muted">Le celle verdi indicano le fasce in cui sei disponibile.</p>
            <button
              class="button primary"
              disabled={pending()}
              onClick={() =>
                act(
                  () => api.availability.set({ week: week(), ranges: Availability.fromMask(mask()) }),
                  "Disponibilità aggiornata.",
                )
              }
            >
              Salva la settimana ↗
            </button>
          </div>
          <form
            class="inline-form"
            onSubmit={(e) => {
              const d = form(e)
              void act(() => api.availability.say(field(d, "text")), "Disponibilità aggiornata dalla frase.")
            }}
          >
            <label>
              Oppure scrivilo
              <input name="text" placeholder="Ci sono mercoledì dalle 20 alle 23" required maxLength={200} />
            </label>
            <Submit>Aggiorna</Submit>
          </form>
          <p class="tiny muted">
            Le frasi aggiornano la settimana indicata nel testo, o quella corrente. Per un’altra settimana usa la
            griglia.
          </p>
        </section>
        <div class="section-line">
          <h2>La gilda, a colpo d’occhio.</h2>
        </div>
        <div class="panel scroll-table">
          <Show when={data()?.people.length} fallback={<Empty>Nessuna disponibilità per questa settimana.</Empty>}>
            <table class="availability-table">
              <thead>
                <tr>
                  <th>Giocatore</th>
                  <For each={Game.dayShort}>
                    {(d) => (
                      <th>
                        {d}
                        <small>M / P / S</small>
                      </th>
                    )}
                  </For>
                </tr>
              </thead>
              <tbody>
                <For each={data()?.people}>
                  {(p) => (
                    <tr>
                      <th style={{ color: p.cls ? Game.classes[p.cls].color : undefined }}>
                        {p.name}
                        <small>{p.source}</small>
                      </th>
                      <For each={Game.dayShort}>
                        {(_, d) => (
                          <td>
                            <div class="mini-slots">
                              <For each={Game.slotIds}>
                                {(s, i) => (
                                  <span
                                    title={`${p.name}: ${s}`}
                                    classList={{ filled: p.mask[d() * 3 + i()] === "1" }}
                                  />
                                )}
                              </For>
                            </div>
                          </td>
                        )}
                      </For>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </Show>
        </div>
      </Gate>
    </>
  )
}
