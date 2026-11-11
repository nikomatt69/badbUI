# BadbUI — static website

A separate, dependency-free static website for **BadbUI 1.2.1**, the World of
Warcraft: Forever addon. It lives entirely in this `site/` folder and is
independent of the Bun monorepo in the repository root: no build step, no
package installation, no framework. Plain HTML, CSS and JavaScript, plus
Three.js loaded from a CDN on the pages that use a 3D background.

- Addon documented: BadbUI **1.2.1** (`## Interface: 16001`, WoW Forever client 1.60.x)
- Language: English only
- Design: Polestar-inspired midnight navy background `#050914`, warm amber
  accent `#f5b94d`, 1px hairlines, clean system-font typography
- Three.js (only external dependency, via CDN):
  `https://unpkg.com/three@0.160.0/build/three.min.js`

## Run it locally

Requires Node.js (any current LTS; nothing to install).

```sh
node site/serve.mjs
```

Then open <http://127.0.0.1:4173/>. The server serves the `site/` folder on
port **4173**, picks the correct MIME type per file, redirects directory URLs
to their trailing-slash form, serves a directory's `index.html`, and answers
unknown paths with the site's `404.html` when present (plain-text `404`
otherwise). Stop it with Ctrl+C. `PORT` and `HOST` environment variables
override the defaults, for example `PORT=4174 node site/serve.mjs`.

Before publishing, validate the pages:

```sh
node site/check.mjs
```

The checker walks every `.html` file under `site/`, confirms each one has a
non-empty `<title>`, verifies that every local `src`/`href` asset it
references exists on disk (external `http(s)`, protocol-relative, `#`,
`data:`, `mailto:` and `tel:` references are skipped), prints a per-file
PASS/FAIL report with a summary, and exits non-zero when anything fails.

You can also open any page directly from disk, but some browsers restrict
module scripts and fetches on `file://` URLs, so the local server above is
the reliable preview.

## Structure

```text
site/
├── README.md        this file: run, publish and editing notes
├── serve.mjs        zero-dependency Node preview server (port 4173)
├── check.mjs        zero-dependency pre-publish checker
├── index.html       landing page: what BadbUI is, download, module overview
└── *.html           one page per topic (modules, guides, macros, support…)
    └── assets/      shared CSS, JavaScript, images and fonts
```

Conventions for the HTML pages:

- One shared stylesheet and script in `assets/`; pages link them with
  relative paths so the checker can verify every reference.
- Each page carries its own descriptive `<title>` and a single `<h1>`.
- Inline SVG or CSS for icons and decoration; raster images only where a
  screenshot or texture genuinely helps, kept small.
- Three.js is loaded only on pages with a 3D scene, pinned to the CDN URL
  above, with a static navy fallback if the CDN is unreachable.
- No trackers, no cookies, no external fonts: system font stack only.

## What the site documents

BadbUI is one addon that replaces the usual pile of single-purpose add-ons
for WoW Forever — bags, auction, combat, encounters, world, quests, loot and
quality-of-life tools share one panel (`/badb`), one profile system and one
design system.

| Module | Command | What it covers |
| --- | --- | --- |
| Bags | `/badb bags` | Unified bags + bank search across all characters |
| Auction | `/badb` → Auction | Prices, lists and selling helpers |
| Combat | `/badb` → Combat | Damage/healing meters and threat |
| Encounters | `/badb` → Encounters | Boss timers, battlegrounds, instance journal |
| World | `/badb` → World | Map coordinates, waypoints, gathering nodes, rares |
| Quests + QuestTracker | `/badb` → Quests | Quest journal, leveling and on-screen tracker |
| Loot | `/badb` → Loot | Loot history, item scoring, best-in-slot |
| QoL | `/badb` → QoL | Automations, movable frames, Lua errors, group order |
| SystemProfile | `/badb system` | Adaptive PC/graphics profile |
| Arena | `/badb arena` | PvP opponent frames (battlegrounds and world PvP) |
| Professions | `/badb prof` | Professions and configured cooldowns |
| Suite | `/badb` → Suite | Which installed add-ons each module replaces, honestly graded |
| Updates | `/badb update` | Check and confirm addon updates via the companion |
| Presets & wizard | `/badb setup` | Per-class/role presets and guided first setup |
| Macros | `/badb macro` | 6,000+ ready-made macros for every class and talent tree |
| Guides | `/badb` → Guides | Offline in-game guides, mirrored on the site |
| Backups | `/badb` → Management | Export, import and restore of settings |

### Honest limits (keep these on the site)

The site states these plainly, and edits must not soften them:

- **Forever has no arenas.** The Arena module shows PvP opponents in
  battlegrounds and world PvP; it works in arena instances only if a client
  ever exposes them.
- **Addons cannot read your GPU.** SystemProfile infers a sensible graphics
  profile from client-visible signals; it never reports hardware it cannot
  see, and no page may claim GPU detection.
- **Questie coverage is partial.** The quests module does not replace a full
  quest database; the Suite page grades coverage per module as full or
  partial, and the site keeps that grading.
- Forever restricts combat add-on APIs (secret values, no combat-log
  parsing), so combat features degrade gracefully where an API is missing.

## Publish it

Any static host works, because there is nothing to build:

1. Run `node site/check.mjs` and fix every FAIL line.
2. Upload the **contents** of `site/` (the HTML pages and `assets/`) to the
   host's web root. `README.md`, `serve.mjs` and `check.mjs` are tooling:
   harmless if uploaded, fine to leave behind.
3. Make sure the host serves `index.html` for `/` and `404.html` for unknown
   paths (the default on GitHub Pages, Netlify, Cloudflare Pages, Vercel
   static, S3 + CloudFront and nginx `try_files` setups).

Host recipes, briefly: on GitHub Pages publish from a branch folder or an
Actions artifact containing the site contents; on Netlify or Cloudflare
Pages set the publish/output directory to the uploaded contents with no
build command; on a plain web server point the document root at the
contents and fall back to `404.html`.

## Replace the download links and the support handle

Download and support links are the only per-release details baked into the
pages. To point them at a real release:

1. Build or locate the release archive (`BadbUI-1.2.1.zip`, produced by the
   addon's packaging in the repository root).
2. Find every download anchor in the pages:

   ```sh
   grep -rn "download" site --include="*.html"
   ```

3. In each match, set the anchor's `href` to the published archive URL (a
   release-asset URL or a file you uploaded next to the pages) and update
   the visible version text to match the archive. Relative links to a file
   placed inside `site/` are verified by `node site/check.mjs`; absolute
   `https://` links are skipped by the checker, so confirm those by opening
   the page and clicking through.
4. Find the support handle the same way:

   ```sh
   grep -rn -i "revolut" site --include="*.html"
   ```

5. Replace the handle in the visible text and in the `revolut.me` link with
   the current one (for example `https://revolut.me/<handle>`), keeping the
   wording that BadbUI is free and tips are voluntary.
6. Re-run `node site/check.mjs`, then preview with `node site/serve.mjs`
   and click each changed link once before publishing.

## Editing notes

- Keep the palette to the two tokens above plus tints of them, 1px
  hairlines for structure, and the system font stack — no webfonts.
- Keep the honest-limits wording intact when touching module copy, and keep
  coverage grades on the Suite page in sync with `/badb` → Suite in game.
- After any edit: `node site/check.mjs` must pass and every page must open
  from `node site/serve.mjs` with no console errors.
