import { For, Show, createSignal, type JSX } from "solid-js"
import { Game } from "@badb/core"
import { me, pending, act } from "./state"
export function Heading(props: { label: string; title: string; text?: string; children?: JSX.Element }) {
  return (
    <header class="page-heading">
      <div>
        <div class="eyebrow">{props.label}</div>
        <h1>{props.title}</h1>
        <Show when={props.text}>
          <p>{props.text}</p>
        </Show>
      </div>
      {props.children}
    </header>
  )
}
export function Empty(props: { children: JSX.Element }) {
  return <div class="empty">{props.children}</div>
}
export function Submit(props: { children: JSX.Element }) {
  return (
    <button class="button primary" type="submit" disabled={pending()}>
      {pending() ? "Attendi…" : props.children}
    </button>
  )
}
export function Gate(props: { children: JSX.Element; member?: boolean }) {
  return (
    <Show
      when={me() && (!props.member || Game.rankAtLeast(me()!.user.rank, "member"))}
      fallback={
        <Empty>
          <p>
            {me()
              ? "Questa sezione è riservata ai membri della gilda. Invia la tua candidatura."
              : "Accedi per partecipare alla vita della gilda."}
          </p>
          <a class="button" href={me() ? "#/candidatura" : "#/profilo"}>
            {me() ? "Candidati" : "Accedi"} ↗
          </a>
        </Empty>
      }
    >
      {props.children}
    </Show>
  )
}
export function ClassFields() {
  const [cls, setClass] = createSignal<Game.ClassId>("warrior")
  return (
    <>
      <label>
        Classe
        <select
          name="cls"
          required
          value={cls()}
          onChange={(event) => setClass(event.currentTarget.value as Game.ClassId)}
        >
          <For each={Game.classList}>{(c) => <option value={c.id}>{c.label}</option>}</For>
        </select>
      </label>
      <label>
        Specializzazione
        <select name="spec">
          <option value="">Da definire</option>
          <For each={Game.classes[cls()].specs}>{(s) => <option value={s.id}>{s.label}</option>}</For>
        </select>
      </label>
      <label>
        Ruolo
        <select name="role">
          <For each={Game.roles}>{(r) => <option value={r}>{Game.roleLabel[r]}</option>}</For>
        </select>
      </label>
    </>
  )
}

export function DeleteAction(props: { onDelete: () => Promise<unknown>; after?: () => void; label?: string }) {
  const [confirm, setConfirm] = createSignal(false)
  return (
    <Show
      when={confirm()}
      fallback={
        <button class="text-link" type="button" onClick={() => setConfirm(true)}>
          {props.label ?? "Elimina"}
        </button>
      }
    >
      <div class="filters">
        <span>Eliminare definitivamente?</span>
        <button
          type="button"
          class="button"
          disabled={pending()}
          onClick={() =>
            act(async () => {
              await props.onDelete()
              props.after?.()
              setConfirm(false)
            }, "Elemento eliminato.")
          }
        >
          Conferma eliminazione
        </button>
        <button type="button" class="text-link" onClick={() => setConfirm(false)}>
          Annulla
        </button>
      </div>
    </Show>
  )
}
