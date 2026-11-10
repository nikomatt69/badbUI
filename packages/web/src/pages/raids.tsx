import { For, Show, createResource, createSignal } from "solid-js"
import { Availability, Game } from "@badb/core"
import { api, me, revision, act, form, field, clock, minutes } from "../state"
import { Heading, Empty, Submit, DeleteAction } from "../ui"
export function Raids() {
  const [filter, setFilter] = createSignal("")
  const [groups] = createResource(revision, () => api.group.list())
  const [events] = createResource(revision, () => api.event.list())
  const officer = () => !!me() && Game.rankAtLeast(me()!.user.rank, "officer")
  const canManage = (g: string | null) =>
    officer() || (!!me() && groups()?.find((group) => group.id === g)?.leaderId === me()!.user.id)
  const [character, setCharacter] = createSignal("")
  return (
    <>
      <Heading
        label="IL PROSSIMO PULL"
        title="Un posto nel tuo party."
        text="Scegli il gruppo, conferma la presenza e preparati. La formazione definitiva la decide il raid leader."
      />
      <div class="filters">
        <button classList={{ active: !filter() }} onClick={() => setFilter("")}>
          Tutti i raid
        </button>
        <For each={groups()}>
          {(g) => (
            <button classList={{ active: filter() === g.id }} onClick={() => setFilter(g.id)}>
              {g.name}
            </button>
          )}
        </For>
        <Show when={me()?.characters.length}>
          <label class="inline-label">
            Gioca con
            <select value={character()} onChange={(e) => setCharacter(e.currentTarget.value)}>
              <option value="">Personaggio principale</option>
              <For each={me()?.characters}>{(c) => <option value={c.id}>{c.name}</option>}</For>
            </select>
          </label>
        </Show>
      </div>
      <Show
        when={events()?.filter((e) => !filter() || filter() === e.groupId).length}
        fallback={<Empty>Nessun raid in programma per questo gruppo.</Empty>}
      >
        <div class="raid-grid">
          <For each={events()?.filter((e) => !filter() || filter() === e.groupId)}>
            {(e) => (
              <article class="panel raid-card">
                <div class="raid-top">
                  <span class="eyebrow">{e.group ?? "GILDA"}</span>
                  <span class="badge">
                    {
                      {
                        open: "Iscrizioni aperte",
                        locked: "Formazione chiusa",
                        done: "Completato",
                        cancelled: "Annullato",
                      }[e.status]
                    }
                  </span>
                </div>
                <h2>{e.title}</h2>
                <p>
                  {new Date(e.startsAt).toLocaleDateString("it-IT", {
                    weekday: "long",
                    day: "numeric",
                    month: "long",
                    timeZone: "Europe/Rome",
                  })}{" "}
                  · {clock(e.start)} · {e.duration} min
                </p>
                <p>{e.note}</p>
                <div class="composition">
                  <For each={Game.roles}>
                    {(role) => (
                      <div>
                        <strong>
                          {e.signups.filter((s) => s.role === role && s.picked && s.status === "yes").length}
                          <small> / {e.comp[role]}</small>
                        </strong>
                        <span>{Game.roleLabel[role]}</span>
                      </div>
                    )}
                  </For>
                </div>
                <div class="signup-list">
                  <For each={e.signups}>
                    {(s) => (
                      <div>
                        <span style={{ color: Game.classes[s.cls].color }}>{s.name}</span>
                        <span>
                          {Game.roleLabel[s.role]} ·{" "}
                          {{ yes: "Presente", maybe: "Forse", no: "Assente", bench: "Riserva" }[s.status]}{" "}
                          {s.picked ? "· Titolare" : ""}
                        </span>
                        <Show when={canManage(e.groupId)}>
                          <button
                            class="text-link"
                            onClick={() =>
                              act(() => api.event.pick(e.id, { characterId: s.characterId, picked: !s.picked }))
                            }
                          >
                            {s.picked ? "In riserva" : "Titolare"}
                          </button>
                        </Show>
                      </div>
                    )}
                  </For>
                </div>
                <Show when={me() && Game.rankAtLeast(me()!.user.rank, "member") && e.status === "open"}>
                  <div class="signup-actions">
                    <For
                      each={
                        [
                          ["yes", "Ci sono"],
                          ["maybe", "Forse"],
                          ["no", "Non ci sono"],
                        ] as const
                      }
                    >
                      {([status, label]) => (
                        <button
                          class="button"
                          classList={{
                            primary: e.signups.some((s) => s.userId === me()!.user.id && s.status === status),
                          }}
                          onClick={() =>
                            act(
                              () =>
                                api.event.signup(e.id, {
                                  status,
                                  ...(character() ? { characterId: character() } : {}),
                                }),
                              "Presenza aggiornata.",
                            )
                          }
                        >
                          {label}
                        </button>
                      )}
                    </For>
                  </div>
                </Show>
                <Show when={canManage(e.groupId)}>
                  <details>
                    <summary>Modifica questo raid</summary>
                    <form
                      class="form-grid"
                      onSubmit={(event) => {
                        const d = form(event)
                        void act(() =>
                          api.event.update(e.id, {
                            title: field(d, "title"),
                            date: field(d, "date"),
                            start: minutes(field(d, "time")),
                            duration: Number(d.get("duration")),
                            note: field(d, "note"),
                          }),
                        )
                      }}
                    >
                      <label>
                        Titolo
                        <input name="title" maxLength={80} value={e.title} />
                      </label>
                      <label>
                        Data
                        <input name="date" type="date" required value={e.date} />
                      </label>
                      <label>
                        Ora
                        <input name="time" type="time" required value={clock(e.start)} />
                      </label>
                      <label>
                        Durata (minuti)
                        <input name="duration" type="number" min="30" max="600" required value={e.duration} />
                      </label>
                      <label class="full">
                        Note
                        <textarea name="note" maxLength={1000} value={e.note} />
                      </label>
                      <Submit>Salva raid</Submit>
                    </form>
                    <DeleteAction label="Elimina raid" onDelete={() => api.event.remove(e.id)} />
                  </details>
                  <div class="form-actions">
                    <label>
                      Stato
                      <select
                        aria-label={`Stato ${e.title}`}
                        value={e.status}
                        onChange={(v) =>
                          act(() => api.event.update(e.id, { status: v.currentTarget.value as typeof e.status }))
                        }
                      >
                        <For each={["open", "locked", "done", "cancelled"]}>
                          {(s) => <option value={s}>{s}</option>}
                        </For>
                      </select>
                    </label>
                  </div>
                </Show>
              </article>
            )}
          </For>
        </div>
      </Show>
      <Show when={groups()?.some((g) => canManage(g.id))}>
        <section class="panel">
          <h2>Pianifica i gruppi</h2>
          <p>Genera gli eventi della settimana dagli orari del gruppo, senza duplicati.</p>
          <form
            class="inline-form"
            onSubmit={(e) => {
              const d = form(e)
              void act(
                () => api.group.schedule(field(d, "group"), Availability.weekOf(field(d, "week"))),
                "Settimana pianificata.",
              )
            }}
          >
            <label>
              Gruppo
              <select name="group">
                <For each={groups()?.filter((g) => canManage(g.id))}>
                  {(g) => <option value={g.id}>{g.name}</option>}
                </For>
              </select>
            </label>
            <label>
              Settimana
              <input type="date" name="week" value={Availability.currentWeek(new Date(), "Europe/Rome")} required />
            </label>
            <Submit>Pianifica ↗</Submit>
          </form>
        </section>
      </Show>
      <Show when={officer()}>
        <details class="panel">
          <summary>Crea un raid singolo</summary>
          <form
            class="form-grid"
            onSubmit={(e) => {
              const d = form(e)
              void act(() =>
                api.event.create({
                  title: field(d, "title"),
                  groupId: field(d, "group") || null,
                  raid: field(d, "raid"),
                  date: field(d, "date"),
                  start: minutes(field(d, "time")),
                  note: field(d, "note"),
                }),
              )
            }}
          >
            <label>
              Titolo
              <input name="title" maxLength={80} />
            </label>
            <label>
              Gruppo
              <select name="group">
                <option value="">Gilda</option>
                <For each={groups()}>{(g) => <option value={g.id}>{g.name}</option>}</For>
              </select>
            </label>
            <label>
              Raid
              <select name="raid">
                <For each={Game.raids}>{(r) => <option value={r.id}>{r.label}</option>}</For>
              </select>
            </label>
            <label>
              Data
              <input name="date" type="date" required />
            </label>
            <label>
              Ora
              <input name="time" type="time" value="21:00" required />
            </label>
            <label>
              Note
              <textarea name="note" maxLength={1000} />
            </label>
            <Submit>Crea raid</Submit>
          </form>
        </details>
      </Show>
    </>
  )
}
