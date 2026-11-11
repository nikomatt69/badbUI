// BadbUI static site — zero-dependency pre-publish checker.
// Usage: node site/check.mjs
// Verifies every .html file under site/: a non-empty <title> is present and
// every local src/href asset it references exists on disk. External
// (http/https), protocol-relative, fragment (#), data:, mailto: and tel:
// references are skipped. Prints a per-file PASS/FAIL report plus a summary
// and exits 0 only when every file passes.
import { readdir, readFile, stat } from "node:fs/promises";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SITE_ROOT = fileURLToPath(new URL(".", import.meta.url));
const ATTR_RE = /(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;
const TITLE_RE = /<title[^>]*>([\s\S]*?)<\/title>/i;

async function collectHtml(dir) {
  const found = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) found.push(...(await collectHtml(full)));
    else if (entry.isFile() && extname(entry.name).toLowerCase() === ".html") found.push(full);
  }
  return found.sort();
}

function localRefs(html) {
  const refs = [];
  for (const match of html.matchAll(ATTR_RE)) {
    const raw = (match[1] ?? match[2] ?? "").trim();
    if (!raw || raw.startsWith("#")) continue;
    if (/^(?:https?:)?\/\//i.test(raw)) continue;
    if (/^(?:data|mailto|tel|javascript):/i.test(raw)) continue;
    const clean = raw.split(/[?#]/)[0];
    if (clean) refs.push({ raw, clean });
  }
  return refs;
}

async function refExists(htmlFile, ref) {
  let decoded;
  try {
    decoded = decodeURIComponent(ref.clean);
  } catch {
    return false;
  }
  const target = decoded.startsWith("/")
    ? resolve(join(SITE_ROOT, "." + decoded))
    : resolve(join(dirname(htmlFile), decoded));
  try {
    const info = await stat(target);
    if (info.isDirectory()) await stat(join(target, "index.html"));
    return true;
  } catch {
    return false;
  }
}

const htmlFiles = await collectHtml(SITE_ROOT).catch(() => []);
let passed = 0;

if (htmlFiles.length === 0) {
  console.log("FAIL  no .html files found under site/");
} else {
  for (const file of htmlFiles) {
    const rel = file.slice(SITE_ROOT.length);
    const problems = [];
    let html;
    try {
      html = await readFile(file, "utf8");
    } catch (err) {
      console.log(`FAIL  ${rel} — unreadable (${err.code || err.message})`);
      continue;
    }
    const title = TITLE_RE.exec(html)?.[1]?.trim();
    if (!title) problems.push("missing or empty <title>");
    const refs = localRefs(html);
    let missing = 0;
    for (const ref of refs) {
      if (!(await refExists(file, ref))) {
        missing += 1;
        problems.push(`missing asset: ${ref.raw}`);
      }
    }
    if (problems.length === 0) {
      passed += 1;
      console.log(`PASS  ${rel} — title ok, ${refs.length} local reference(s) ok`);
    } else {
      console.log(`FAIL  ${rel}`);
      for (const problem of problems) console.log(`      - ${problem}`);
    }
  }
}

console.log(
  `\n${passed}/${htmlFiles.length} HTML file(s) passed` +
    (passed === htmlFiles.length && htmlFiles.length > 0 ? " — PASS" : " — FAIL"),
);
process.exit(passed === htmlFiles.length && htmlFiles.length > 0 ? 0 : 1);
