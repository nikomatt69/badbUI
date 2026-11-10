import { For, Show, createResource, createSignal, createEffect, on } from "solid-js"
import { Markdown } from "../markdown"
import { Game, Tactics as Engine, type Schema } from "@badb/core"
import { api, revision, me, act, field, form } from "../state"
import { Empty, Heading, Submit, DeleteAction } from "../ui"
// Corpo reso come testo: niente HTML remoto e niente script nei post.
export function Library(props: { kind: "blog" | "guide" }) {
  const [posts] = createResource(
    () => [props.kind, revision()] as const,
    ([kind]) => api.post.list(kind),
  )
  const [slug, setSlug] = createSignal("")
  createEffect(
    on(
      () => props.kind,
      () => setSlug(""),
      { defer: true },
    ),
  )
  const [post] = createResource(
    () => (slug() ? ([props.kind, slug(), revision()] as const) : false),
    ([kind, s]) => api.post.get(kind, s),
  )
  const officer = () => me() && Game.rankAtLeast(me()!.user.rank, "officer")
  return (
    <>
      <Heading
        label={props.kind === "guide" ? "SAPERE CONDIVISO" : "STORIE DAL CAMPO BASE"}
        title={props.kind === "guide" ? "Un pull alla volta." : "Il diario di gilda."}
        text={
          props.kind === "guide"
            ? "Guide, preparazione e tutto quello che impariamo insieme."
            : "Novità, annunci e piccoli traguardi della nostra gilda."
        }
      />
      <Show when={!!slug() && post()}>
        {(p) => (
          <article class="panel article">
            <button class="text-link" onClick={() => setSlug("")}>
              ← Torna all’elenco
            </button>
            <span class="eyebrow">
              {p().category} {p().published === null ? " / BOZZA" : ""}
            </span>
            <h2>{p().title}</h2>
            <p class="lead">{p().excerpt}</p>
            <Markdown text={p().body} />
            <Show when={officer()}>
              <button
                class="button"
                onClick={() =>
                  act(
                    () => api.post.update(p().id, { ...p(), published: p().published === null }),
                    "Pubblicazione aggiornata.",
                  )
                }
              >
                {p().published === null ? "Pubblica" : "Rendi bozza"}
              </button>
              <details>
                <summary>Modifica contenuto</summary>
                <form
                  class="form-grid"
                  onSubmit={(e) => {
                    const d = form(e)
                    void act(
                      () =>
                        api.post.update(p().id, {
                          ...p(),
                          title: field(d, "title"),
                          excerpt: field(d, "excerpt"),
                          body: field(d, "body"),
                          category: field(d, "category"),
                          tags: field(d, "tags")
                            .split(",")
                            .map((t) => t.trim())
                            .filter(Boolean),
                          published: d.has("published"),
                        }),
                      "Contenuto aggiornato.",
                    )
                  }}
                >
                  <label>
                    Titolo
                    <input name="title" required maxLength={120} value={p().title} />
                  </label>
                  <label>
                    Categoria
                    <input name="category" maxLength={40} value={p().category} />
                  </label>
                  <label class="full">
                    Introduzione
                    <input name="excerpt" maxLength={300} value={p().excerpt} />
                  </label>
                  <label class="full">
                    Testo
                    <textarea name="body" rows={14} maxLength={60000} value={p().body} />
                  </label>
                  <label class="full">
                    Tag separati da virgole
                    <input name="tags" value={p().tags.join(", ")} />
                  </label>
                  <label class="check">
                    <input name="published" type="checkbox" checked={p().published !== null} />
                    Pubblicato
                  </label>
                  <Submit>Salva modifiche</Submit>
                </form>
              </details>
              <DeleteAction onDelete={() => api.post.remove(p().id)} after={() => setSlug("")} />
            </Show>
          </article>
        )}
      </Show>
      <Show when={!slug()}>
        <div class="content-grid">
          <For each={posts()}>
            {(p) => (
              <button class="panel post-card" onClick={() => setSlug(p.slug)}>
                <span class="eyebrow">
                  {p.category || props.kind} {p.published === null ? "/ BOZZA" : ""}
                </span>
                <h2>{p.title}</h2>
                <p>{p.excerpt}</p>
                <span class="text-link">Leggi {props.kind === "guide" ? "la guida" : "il post"} ↗</span>
              </button>
            )}
          </For>
        </div>
        <Show when={!posts()?.length}>
          <Empty>Nessun contenuto pubblicato.</Empty>
        </Show>
      </Show>
      <Show when={officer()}>
        <details class="panel">
          <summary>Scrivi {props.kind === "guide" ? "una guida" : "un post"}</summary>
          <form
            class="form-grid"
            onSubmit={(e) => {
              const d = form(e)
              void act(
                () =>
                  api.post.create({
                    kind: props.kind,
                    title: field(d, "title"),
                    excerpt: field(d, "excerpt"),
                    body: field(d, "body"),
                    category: field(d, "category"),
                    published: d.has("published"),
                  }),
                "Contenuto salvato.",
              )
            }}
          >
            <label>
              Titolo
              <input required name="title" maxLength={120} />
            </label>
            <label>
              Categoria
              <input name="category" maxLength={40} />
            </label>
            <label class="full">
              Introduzione
              <input name="excerpt" maxLength={300} />
            </label>
            <label class="full">
              Testo
              <textarea rows={12} required name="body" maxLength={60000} />
            </label>
            <label class="check">
              <input type="checkbox" name="published" />
              Pubblica subito
            </label>
            <Submit>Salva contenuto</Submit>
          </form>
        </details>
      </Show>
    </>
  )
}
export function Tactics() {
  const [bosses] = createResource(revision, () => api.boss.list())
  const [raid, setRaid] = createSignal("")
  const [capabilities] = createResource(revision, () => api.tactics.get())
  const [specialization, setSpecialization] = createSignal("warrior/arms")
  return (
    <>
      <Heading
        label="PREPARAZIONE, PRIMA DEL DPS"
        title="La classe giusta. Il piano giusto."
        text="Il motore confronta i requisiti del boss con le capacità delle specializzazioni. Sono indicazioni tattiche, non una classifica di DPS."
      />
      <div class="notice">
        Confidenza A: verificata dalla gilda · B: incontro storico da verificare · C: ipotesi. Forever modifica le
        classi: gli ufficiali aggiornano pesi e capacità.
      </div>
      <div class="filters">
        <button classList={{ active: !raid() }} onClick={() => setRaid("")}>
          Tutti i raid
        </button>
        <For each={Game.raids}>
          {(r) => (
            <button classList={{ active: raid() === r.id }} onClick={() => setRaid(r.id)}>
              {r.label}
            </button>
          )}
        </For>
      </div>
      <For each={bosses()?.filter((b) => !raid() || b.raid === raid())}>
        {(b) => (
          <section class="panel boss-panel">
            <span class="eyebrow">
              {Game.findRaid(b.raid)?.label} / CONFIDENZA {b.confidence}
            </span>
            <h2>{b.name}</h2>
            <p class="post-body">{b.notes}</p>
            <div class="tags">
              <For each={Engine.tagIds.filter((t) => (b.weights[t] ?? 0) >= 2)}>
                {(t) => <span class="badge">{Engine.tags[t].label}</span>}
              </For>
            </div>
            <div class="group-grid">
              <For each={Game.roles}>
                {(r) => (
                  <div>
                    <h3>{Game.roleLabel[r]}</h3>
                    <For each={b.best[r]}>
                      {(fit) => (
                        <div class="fit-row">
                          <span style={{ color: Game.classes[fit.cls].color }}>
                            {Game.classes[fit.cls].label}
                            <small>{Game.findSpec(fit.cls, fit.spec)?.label}</small>
                          </span>
                          <strong>
                            {fit.score === null ? "—" : Math.round(fit.score)}
                            <small>punti</small>
                          </strong>
                        </div>
                      )}
                    </For>
                  </div>
                )}
              </For>
            </div>
            <Show when={me() && Game.rankAtLeast(me()!.user.rank, "officer")}>
              <details>
                <summary>Aggiorna tattica e requisiti</summary>
                <BossEditor boss={b} />
                <DeleteAction label="Elimina boss" onDelete={() => api.boss.remove(b.id)} />
              </details>
            </Show>
          </section>
        )}
      </For>
      <Show when={!bosses()?.filter((b) => !raid() || b.raid === raid()).length}>
        <Empty>Nessun boss configurato per questo raid.</Empty>
      </Show>
      <Show when={me() && Game.rankAtLeast(me()!.user.rank, "officer")}>
        <details class="panel">
          <summary>Aggiungi boss</summary>
          <BossEditor />
        </details>
        <details class="panel">
          <summary>Correggi le capacità di una specializzazione</summary>
          <form
            class="form-grid"
            onSubmit={(e) => {
              const d = form(e)
              const weights = Object.fromEntries(Engine.tagIds.map((t) => [t, Number(d.get(t))]))
              void act(() => api.tactics.set({ [field(d, "spec")]: weights }))
            }}
          >
            <label>
              Specializzazione
              <select name="spec" value={specialization()} onChange={(e) => setSpecialization(e.currentTarget.value)}>
                <For each={Game.classList}>
                  {(c) => (
                    <For each={c.specs}>
                      {(s) => (
                        <option value={`${c.id}/${s.id}`}>
                          {c.label} · {s.label}
                        </option>
                      )}
                    </For>
                  )}
                </For>
              </select>
            </label>
            <p>Valori da 0 a 3. Questo modulo salva tutti i valori della specializzazione scelta.</p>
            <For each={Engine.tagIds}>
              {(t) => (
                <label>
                  {Engine.tags[t].label}
                  <input
                    name={t}
                    type="number"
                    min="0"
                    max="3"
                    value={capabilities()?.matrix[specialization()]?.[t] ?? 0}
                    required
                  />
                </label>
              )}
            </For>
            <Submit>Salva matrice</Submit>
          </form>
        </details>
      </Show>
    </>
  )
}
function BossEditor(props: { boss?: Schema.Boss }) {
  return (
    <form
      class="form-grid"
      onSubmit={(e) => {
        const d = form(e)
        const input = {
          name: field(d, "name"),
          raid: field(d, "raid"),
          notes: field(d, "notes"),
          confidence: field(d, "confidence") as "A" | "B" | "C",
          weights: Object.fromEntries(Engine.tagIds.map((t) => [t, Number(d.get(t))])),
        }
        void act(() => (props.boss ? api.boss.update(props.boss.id, input) : api.boss.create(input)))
      }}
    >
      <label>
        Nome
        <input name="name" value={props.boss?.name ?? ""} required maxLength={60} />
      </label>
      <label>
        Raid
        <select name="raid" value={props.boss?.raid}>
          <For each={Game.raids}>{(r) => <option value={r.id}>{r.label}</option>}</For>
        </select>
      </label>
      <label>
        Confidenza
        <select name="confidence" value={props.boss?.confidence ?? "C"}>
          <option>A</option>
          <option>B</option>
          <option>C</option>
        </select>
      </label>
      <label class="full">
        Tattica
        <textarea name="notes" value={props.boss?.notes ?? ""} maxLength={4000} />
      </label>
      <For each={Engine.tagIds}>
        {(t) => (
          <label>
            {Engine.tags[t].label}
            <input name={t} type="number" min="0" max="3" value={props.boss?.weights[t] ?? 0} required />
          </label>
        )}
      </For>
      <Submit>Salva boss</Submit>
    </form>
  )
}
