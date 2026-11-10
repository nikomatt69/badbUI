import { For, Show, createResource, createSignal } from "solid-js"
import { Game, Availability } from "@badb/core"
import { api, me, session, act, form, field, revision, clock, minutes } from "../state"
import { Gate, Heading, Submit, ClassFields, DeleteAction } from "../ui"
export function Profile() {
  const [register, setRegister] = createSignal(false)
  const [setup] = createResource(revision, () => api.auth.setup())
  const [code, setCode] = createSignal<{ code: string; expires: number; kind: string }>()
  return (
    <>
      <Heading label="IL TUO CAMPO BASE" title={me() ? `Bentornato, ${me()!.user.name}.` : "Il party ti aspetta."} />
      <Show
        when={me()}
        fallback={
          <section class="panel auth-panel">
            <h2>{register() ? "Crea il tuo account" : "Accedi alla gilda"}</h2>
            <form
              class="stack"
              onSubmit={(e) => {
                const d = form(e)
                void act(async () => {
                  const input = {
                    name: field(d, "name"),
                    password: field(d, "password"),
                    setupKey: field(d, "setupKey") || undefined,
                  }
                  const result = await (register() ? api.auth.register(input) : api.auth.login(input))
                  session(result.token)
                }, "Accesso effettuato.")
              }}
            >
              <label>
                Nome account
                <input name="name" required minLength={2} maxLength={24} autocomplete="username" />
              </label>
              <label>
                Password
                <input
                  type="password"
                  name="password"
                  required
                  minLength={8}
                  maxLength={200}
                  autocomplete={register() ? "new-password" : "current-password"}
                />
              </label>
              <Show when={register() && setup()?.required}>
                <label>
                  Codice installazione
                  <input name="setupKey" type="password" autocomplete="off" required maxLength={128} />
                </label>
                <p class="tiny muted">
                  Serve solo a creare il primo capogilda; gli altri membri si registrano normalmente.
                </p>
              </Show>
              <Submit>{register() ? "Crea account" : "Accedi"} ↗</Submit>
            </form>
            <button class="text-link" onClick={() => setRegister(!register())}>
              {register() ? "Hai già un account? Accedi" : "Nuovo in gilda? Crea un account"}
            </button>
          </section>
        }
      >
        {(user) => (
          <>
            <section class="panel">
              <div class="section-line">
                <div>
                  <span class="eyebrow">{Game.rankLabel[user().user.rank]}</span>
                  <h2>{user().user.name}</h2>
                </div>
                <button
                  class="button"
                  onClick={() =>
                    act(async () => {
                      await api.auth.logout()
                      session(null)
                    }, "Sei uscito.")
                  }
                >
                  Esci
                </button>
              </div>
              <h3>Collega WoW Forever</h3>
              <p>Importa equipaggiamento e personaggi reali e controlla lo stato del collegamento.</p>
              <a class="button primary" href="#/collegamento">
                Collega la tua armory ↗
              </a>
              <h3>Altri dispositivi</h3>
              <p>Il codice è monouso e scade dopo 10 minuti. Generane uno diverso per ogni collegamento.</p>
              <div class="filters">
                <For each={["discord", "addon", "mobile"] as const}>
                  {(kind) => (
                    <button
                      class="button"
                      onClick={() =>
                        act(async () => setCode({ ...(await api.auth.link(kind)), kind }), "Codice generato.")
                      }
                    >
                      Collega {kind} ↗
                    </button>
                  )}
                </For>
              </div>
              <Show when={code()}>
                {(c) => (
                  <div class="link-code">
                    <code>{c().code}</code>
                    <p>Scade alle {new Date(c().expires).toLocaleTimeString("it-IT")}</p>
                    <p>
                      {c().kind === "discord"
                        ? `Su Discord: /collega codice:${c().code}`
                        : c().kind === "mobile"
                          ? "Apri l’app, inserisci l’indirizzo del server e questo codice."
                          : `bun run --cwd packages/companion start login ${c().code} --wow "<cartella client Forever>" --account "<account WTF>"`}
                    </p>
                  </div>
                )}
              </Show>
              <Show when={user().user.discordId}>
                <p>
                  Discord collegato: {user().user.discordName ?? user().user.discordId}{" "}
                  <button class="text-link" onClick={() => act(() => api.auth.unlinkDiscord())}>
                    Scollega
                  </button>
                </p>
              </Show>
            </section>
            <section class="panel">
              <h2>I tuoi personaggi</h2>
              <p>
                Le schede manuali sono dichiarazioni del giocatore. Solo le scansioni dell’addon contengono
                equipaggiamento letto da Forever.
              </p>
              <For each={user().characters}>
                {(c) => (
                  <div class="event-row">
                    <strong style={{ color: Game.classes[c.cls].color }}>{c.name}</strong>
                    <span>
                      {c.main ? "Principale · " : ""}
                      {c.source === "addon" ? "Letto in gioco" : "Manuale"}
                    </span>
                    <Show when={!c.main}>
                      <button class="text-link" onClick={() => act(() => api.character.patch(c.id, { main: true }))}>
                        Usa come principale
                      </button>
                    </Show>
                    <button class="text-link" onClick={() => act(() => api.character.remove(c.id))}>
                      Scollega
                    </button>
                  </div>
                )}
              </For>
              <details>
                <summary>Aggiungi personaggio manualmente</summary>
                <form
                  class="form-grid"
                  onSubmit={(e) => {
                    const d = form(e)
                    void act(() =>
                      api.character.save({
                        name: field(d, "name"),
                        cls: field(d, "cls") as Game.ClassId,
                        spec: field(d, "spec") || null,
                        role: field(d, "role") as Game.Role,
                        level: Number(d.get("level")),
                      }),
                    )
                  }}
                >
                  <label>
                    Nome in gioco
                    <input name="name" required minLength={2} maxLength={48} />
                  </label>
                  <ClassFields />
                  <label>
                    Livello
                    <input type="number" name="level" value="1" min="1" max="60" required />
                  </label>
                  <Submit>Aggiungi</Submit>
                </form>
              </details>
            </section>
          </>
        )}
      </Show>
    </>
  )
}
export function Application() {
  const [guild] = createResource(revision, () => api.guild.get())
  return (
    <>
      <Heading
        label="UN POSTO SOTTO LO STENDARDO"
        title="Facciamo party?"
        text="Raccontaci chi sei e quando giochi. Gli ufficiali troveranno il gruppo adatto a te."
      />
      <Gate>
        <Show when={me()?.application}>
          <div class="notice">
            Ultima candidatura: {me()!.application!.status} · {me()!.application!.name}
          </div>
        </Show>
        <section class="panel">
          <form
            class="form-grid"
            onSubmit={(e) => {
              const d = form(e)
              const slots = d.getAll("slots") as Game.SlotId[]
              void act(
                () =>
                  api.application.submit({
                    name: field(d, "name"),
                    cls: field(d, "cls") as Game.ClassId,
                    spec: field(d, "spec") || null,
                    role: field(d, "role") as Game.Role,
                    discord: field(d, "discord"),
                    experience: field(d, "experience"),
                    about: field(d, "about"),
                    slots,
                  }),
                "Candidatura inviata agli ufficiali.",
              )
            }}
          >
            <label>
              Personaggio
              <input name="name" required minLength={2} maxLength={48} />
            </label>
            <ClassFields />
            <label>
              Discord
              <input name="discord" maxLength={60} />
            </label>
            <fieldset class="full">
              <legend>Quando giochi di solito?</legend>
              <For each={Game.slotList}>
                {(s) => (
                  <label class="check">
                    <input type="checkbox" name="slots" value={s.id} />
                    {s.label}
                  </label>
                )}
              </For>
            </fieldset>
            <label class="full">
              Esperienza in gioco
              <textarea name="experience" maxLength={2000} />
            </label>
            <label class="full">
              Due parole su di te
              <textarea name="about" maxLength={2000} />
            </label>
            <p>
              {guild()?.feeSilver
                ? `Contributo di candidatura: ${guild()!.feeSilver} argenti, da consegnare in gioco. Nessun pagamento sul sito.`
                : "La candidatura è gratuita."}
            </p>
            <Submit>Invia candidatura ↗</Submit>
          </form>
        </section>
      </Gate>
    </>
  )
}
export function Admin() {
  const isOfficer = () => me() && Game.rankAtLeast(me()!.user.rank, "officer")
  const [applications] = createResource(
    () => (isOfficer() ? revision() : false),
    () => api.application.list(),
  )
  const [members] = createResource(
    () => (isOfficer() ? revision() : false),
    () => api.member.list(),
  )
  const [connections] = createResource(
    () => (isOfficer() ? revision() : false),
    () => api.addon.connections(),
  )
  const [groups] = createResource(
    () => (isOfficer() ? revision() : false),
    () => api.group.list(),
  )
  const [guild] = createResource(
    () => (isOfficer() ? revision() : false),
    () => api.guild.get(),
  )
  return (
    <>
      <Heading label="TAVOLO DEGLI UFFICIALI" title="Facciamo funzionare la gilda." />
      <Show when={isOfficer()} fallback={<p>Sezione riservata agli ufficiali.</p>}>
        <section class="panel">
          <h2>Armory e client collegati</h2>
          <a class="button" href="#/collegamento">
            Collega o importa uno snapshot ↗
          </a>
          <For each={connections()}>
            {(connection) => (
              <div class="member-row">
                <strong>{connection.name}</strong>
                <span>
                  {new Date(connection.received).toLocaleString("it-IT")} · {connection.characters} personaggi · build{" "}
                  {connection.client?.build ?? "non registrata"}
                </span>
                <span>
                  {connection.rejected.length
                    ? `${connection.rejected.length} errori da correggere`
                    : "Ultimo invio ricevuto"}
                </span>
              </div>
            )}
          </For>
          <Show when={!connections()?.length}>
            <p>Nessun client ancora collegato. I dati dell’armory verranno mostrati alla prima scansione reale.</p>
          </Show>
        </section>
        <section class="panel">
          <h2>Candidature</h2>
          <For each={applications()}>
            {(a) => (
              <details>
                <summary>
                  {a.name} · {Game.classes[a.cls].label} · {a.status}
                </summary>
                <p>
                  Account: {a.account} · Discord: {a.discord}
                </p>
                <p>{a.experience}</p>
                <p>{a.about}</p>
                <p>Orari: {a.slots.join(", ")}</p>
                <form
                  class="form-grid"
                  onSubmit={(e) => {
                    const d = form(e)
                    void act(() =>
                      api.application.review(a.id, {
                        status: field(d, "status") as typeof a.status,
                        feePaid: d.has("fee"),
                        note: field(d, "note"),
                      }),
                    )
                  }}
                >
                  <label>
                    Esito
                    <select name="status" value={a.status}>
                      <option value="pending">In attesa</option>
                      <option value="accepted">Accettata</option>
                      <option value="rejected">Rifiutata</option>
                    </select>
                  </label>
                  <label class="check">
                    <input name="fee" type="checkbox" checked={a.feePaid} />
                    Contributo ricevuto in gioco
                  </label>
                  <label>
                    Nota interna
                    <textarea name="note" value={a.note} />
                  </label>
                  <Submit>Salva esito</Submit>
                </form>
              </details>
            )}
          </For>
          <Show when={!applications()?.length}>
            <p>Nessuna candidatura.</p>
          </Show>
        </section>
        <section class="panel">
          <h2>Membri e permessi</h2>
          <p>
            Tu e il tuo amico potete avere entrambi il grado Capogilda: stessi permessi completi. Resta sempre almeno un
            capogilda.
          </p>
          <For each={members()}>
            {(m) => (
              <div class="member-row">
                <strong>{m.name}</strong>
                <span>{m.characters.map((c) => c.name).join(", ") || "Nessun personaggio"}</span>
                <label>
                  Grado
                  <select
                    aria-label={`Grado ${m.name}`}
                    value={m.rank}
                    onChange={(e) => act(() => api.member.rank(m.id, e.currentTarget.value as Game.Rank))}
                  >
                    <For each={Game.ranks}>{(r) => <option value={r}>{Game.rankLabel[r]}</option>}</For>
                  </select>
                </label>
              </div>
            )}
          </For>
        </section>
        <section class="panel">
          <h2>Gruppi raid</h2>
          <details>
            <summary>Crea un nuovo gruppo</summary>
            <form
              class="form-grid"
              onSubmit={(e) => {
                const d = form(e)
                void act(
                  () =>
                    api.group.create({
                      name: field(d, "name"),
                      slot: field(d, "slot") as Game.SlotId,
                      raid: field(d, "raid"),
                      start: minutes(field(d, "time")),
                      days: d.getAll("days").map(Number),
                    }),
                  "Gruppo creato.",
                )
              }}
            >
              <label>
                Nome
                <input name="name" maxLength={40} required />
              </label>
              <label>
                Fascia
                <select name="slot">
                  <For each={Game.slotList}>{(slot) => <option value={slot.id}>{slot.label}</option>}</For>
                </select>
              </label>
              <label>
                Raid
                <select name="raid">
                  <For each={Game.raids}>{(raid) => <option value={raid.id}>{raid.label}</option>}</For>
                </select>
              </label>
              <label>
                Ora
                <input name="time" type="time" value="21:00" required />
              </label>
              <fieldset class="full">
                <legend>Giorni</legend>
                <For each={Game.dayShort}>
                  {(day, i) => (
                    <label class="check">
                      <input name="days" type="checkbox" value={i()} />
                      {day}
                    </label>
                  )}
                </For>
              </fieldset>
              <Submit>Crea gruppo</Submit>
            </form>
          </details>
          <For each={groups()}>
            {(g) => (
              <details>
                <summary>
                  {g.name} · {clock(g.start)}
                </summary>
                <form
                  class="form-grid"
                  onSubmit={(e) => {
                    const d = form(e)
                    void act(() =>
                      api.group.update(g.id, {
                        ...g,
                        name: field(d, "name"),
                        raid: field(d, "raid"),
                        start: minutes(field(d, "time")),
                        leaderId: field(d, "leader") || null,
                        days: d.getAll("days").map(Number),
                        slot: field(d, "slot") as Game.SlotId,
                        description: field(d, "description"),
                        duration: Number(d.get("duration")),
                        comp: {
                          tank: Number(d.get("tank")),
                          healer: Number(d.get("healer")),
                          dps: Number(d.get("dps")),
                        },
                      }),
                    )
                  }}
                >
                  <label>
                    Nome
                    <input name="name" value={g.name} required />
                  </label>
                  <label>
                    Raid
                    <select name="raid" value={g.raid}>
                      <For each={Game.raids}>{(r) => <option value={r.id}>{r.label}</option>}</For>
                    </select>
                  </label>
                  <label>
                    Ora
                    <input name="time" type="time" value={clock(g.start)} required />
                  </label>
                  <label>
                    Capogruppo
                    <select name="leader" value={g.leaderId ?? ""}>
                      <option value="">Solo ufficiali</option>
                      <For each={members()?.filter((m) => m.rank !== "guest")}>
                        {(m) => <option value={m.id}>{m.name}</option>}
                      </For>
                    </select>
                  </label>
                  <fieldset class="full">
                    <legend>Giorni</legend>
                    <For each={Game.dayShort}>
                      {(d, i) => (
                        <label class="check">
                          <input type="checkbox" name="days" value={i()} checked={g.days.includes(i())} />
                          {d}
                        </label>
                      )}
                    </For>
                  </fieldset>
                  <label>
                    Fascia
                    <select name="slot" value={g.slot}>
                      <For each={Game.slotList}>{(slot) => <option value={slot.id}>{slot.label}</option>}</For>
                    </select>
                  </label>
                  <label>
                    Durata (minuti)
                    <input name="duration" type="number" min="30" max="600" value={g.duration} required />
                  </label>
                  <label class="full">
                    Descrizione
                    <textarea name="description" maxLength={500} value={g.description} />
                  </label>
                  <For each={Game.roles}>
                    {(role) => (
                      <label>
                        Posti {Game.roleLabel[role]}
                        <input name={role} type="number" min="0" max="40" value={g.comp[role]} required />
                      </label>
                    )}
                  </For>
                  <Submit>Salva gruppo</Submit>
                </form>
                <DeleteAction label="Elimina gruppo" onDelete={() => api.group.remove(g.id)} />
                <h3>Formazione fissa</h3>
                <For each={g.members}>
                  {(m) => (
                    <div class="member-row">
                      <span>
                        {m.name} · {m.bench ? "Riserva" : "Titolare"}
                      </span>
                      <button class="text-link" onClick={() => act(() => api.group.removeMember(g.id, m.characterId))}>
                        Rimuovi
                      </button>
                    </div>
                  )}
                </For>
                <form
                  class="inline-form"
                  onSubmit={(e) => {
                    const d = form(e)
                    void act(() =>
                      api.group.setMember(g.id, { characterId: field(d, "character"), bench: d.has("bench") }),
                    )
                  }}
                >
                  <label>
                    Personaggio
                    <select name="character" required>
                      <For each={members()?.flatMap((m) => m.characters)}>
                        {(c) => <option value={c.id}>{c.name}</option>}
                      </For>
                    </select>
                  </label>
                  <label class="check">
                    <input type="checkbox" name="bench" />
                    Riserva
                  </label>
                  <Submit>Aggiungi al gruppo</Submit>
                </form>
              </details>
            )}
          </For>
        </section>
        <Show when={me()?.user.rank === "gm" && guild()}>
          <section class="panel">
            <h2>Identità della gilda</h2>
            <form
              class="form-grid"
              onSubmit={(e) => {
                const d = form(e)
                void act(() =>
                  api.guild.set({
                    ...guild()!,
                    name: field(d, "name"),
                    realm: field(d, "realm"),
                    motto: field(d, "motto"),
                    about: field(d, "about"),
                    discordInvite: field(d, "discord"),
                    feeSilver: Number(d.get("fee")),
                  }),
                )
              }}
            >
              <label>
                Nome
                <input name="name" required value={guild()?.name} />
              </label>
              <label>
                Ruleset / reame
                <input name="realm" value={guild()?.realm} />
              </label>
              <label class="full">
                Motto
                <input name="motto" value={guild()?.motto} />
              </label>
              <label class="full">
                La gilda
                <textarea name="about" value={guild()?.about} />
              </label>
              <label>
                Invito Discord
                <input name="discord" type="url" value={guild()?.discordInvite} />
              </label>
              <label>
                Contributo (argenti)
                <input name="fee" type="number" min="0" max="100000" value={guild()?.feeSilver} />
              </label>
              <Submit>Salva gilda</Submit>
            </form>
          </section>
        </Show>
      </Show>
    </>
  )
}
