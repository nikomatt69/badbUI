// Blog e guide: stesso modello, distinti da "kind". Il corpo e' Markdown, ripulito dal client al rendering.
import { type Schema } from "@badb/core"
import type { z } from "zod"
import { Fail, id, json, touch, type Ctx } from "./ctx"

type Row = {
  id: string
  kind: "blog" | "guide"
  slug: string
  title: string
  excerpt: string
  body: string
  category: string
  tags: string
  author: string | null
  published: number | null
  created: number
  updated: number
}

const SELECT = `SELECT post.*, user.name AS author FROM post LEFT JOIN user ON user.id = post.author_id`

function toPost(row: Row): Schema.Post {
  return {
    id: row.id,
    kind: row.kind,
    slug: row.slug,
    title: row.title,
    excerpt: row.excerpt,
    body: row.body,
    category: row.category,
    tags: json<string[]>(row.tags, []),
    author: row.author,
    published: row.published,
    created: row.created,
    updated: row.updated,
  }
}

function summary(post: Schema.Post): Schema.PostSummary {
  const { body: _, ...rest } = post
  return rest
}

export function slugify(title: string) {
  const slug = title
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 70)
  return slug || "post"
}

/** Le bozze (published = null) le vedono solo gli ufficiali. */
export function list(ctx: Ctx, kind: "blog" | "guide" | undefined, drafts: boolean, limit = 100) {
  return ctx.db
    .query<Row, []>(`${SELECT} ORDER BY COALESCE(post.published, post.created) DESC`)
    .all()
    .filter((row) => (!kind || row.kind === kind) && (drafts || row.published !== null))
    .slice(0, limit)
    .map((row) => summary(toPost(row)))
}

export function get(ctx: Ctx, kind: string, slug: string, drafts: boolean) {
  const row = ctx.db.query<Row, [string, string]>(`${SELECT} WHERE post.kind = ? AND post.slug = ?`).get(kind, slug)
  if (!row || (!drafts && row.published === null)) throw new Fail(404, "Pagina non trovata")
  return toPost(row)
}

function byId(ctx: Ctx, post: string) {
  const row = ctx.db.query<Row, [string]>(`${SELECT} WHERE post.id = ?`).get(post)
  if (!row) throw new Fail(404, "Pagina non trovata")
  return toPost(row)
}

type Input = z.infer<typeof Schema.PostInput>

function unique(ctx: Ctx, kind: string, wanted: string, self?: string) {
  const taken = (slug: string) => {
    const row = ctx.db.query<{ id: string }, [string, string]>("SELECT id FROM post WHERE kind = ? AND slug = ?").get(kind, slug)
    return !!row && row.id !== self
  }
  if (!taken(wanted)) return wanted
  const free = Array.from({ length: 50 }, (_, i) => `${wanted}-${i + 2}`).find((slug) => !taken(slug))
  return free ?? `${wanted}-${id().slice(0, 6)}`
}

export function create(ctx: Ctx, author: Schema.User, input: Input) {
  const post = id()
  const slug = unique(ctx, input.kind, input.slug || slugify(input.title))
  ctx.db.run(
    `INSERT INTO post (id, kind, slug, title, excerpt, body, category, tags, author_id, published, created, updated)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [post, input.kind, slug, input.title, input.excerpt, input.body, input.category, JSON.stringify(input.tags), author.id, input.published ? ctx.now() : null, ctx.now(), ctx.now()],
  )
  if (input.published) ctx.announce(`${input.kind === "blog" ? "📰 Nuovo articolo" : "📘 Nuova guida"}: **${input.title}**`)
  touch(ctx, { type: "post", id: post })
  return byId(ctx, post)
}

export function update(ctx: Ctx, post: string, input: Input) {
  const current = byId(ctx, post)
  const slug = unique(ctx, input.kind, input.slug || current.slug, post)
  const published = input.published ? (current.published ?? ctx.now()) : null
  ctx.db.run("UPDATE post SET kind = ?, slug = ?, title = ?, excerpt = ?, body = ?, category = ?, tags = ?, published = ?, updated = ? WHERE id = ?", [
    input.kind,
    slug,
    input.title,
    input.excerpt,
    input.body,
    input.category,
    JSON.stringify(input.tags),
    published,
    ctx.now(),
    post,
  ])
  if (published && !current.published) ctx.announce(`${input.kind === "blog" ? "📰 Nuovo articolo" : "📘 Nuova guida"}: **${input.title}**`)
  touch(ctx, { type: "post", id: post })
  return byId(ctx, post)
}

export function remove(ctx: Ctx, post: string) {
  byId(ctx, post)
  ctx.db.run("DELETE FROM post WHERE id = ?", [post])
  touch(ctx, { type: "post", id: post })
}
