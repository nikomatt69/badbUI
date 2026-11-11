// BadbUI static site — zero-dependency local preview server.
// Usage: node site/serve.mjs   (then open http://127.0.0.1:4173)
// Optional overrides: PORT=8080 HOST=0.0.0.0 node site/serve.mjs
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const SITE_ROOT = fileURLToPath(new URL(".", import.meta.url));
const PORT = Number(process.env.PORT) || 4173;
const HOST = process.env.HOST || "127.0.0.1";

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".avif": "image/avif",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".pdf": "application/pdf",
};

function sendText(res, status, text, headOnly) {
  res.writeHead(status, {
    "Content-Type": "text/plain; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(headOnly ? undefined : text);
}

async function sendFile(res, filePath, status, headOnly) {
  const data = await readFile(filePath);
  const type = MIME_TYPES[extname(filePath).toLowerCase()] || "application/octet-stream";
  res.writeHead(status, {
    "Content-Type": type,
    "Content-Length": data.length,
    "Cache-Control": type.startsWith("text/html") ? "no-cache" : "public, max-age=3600",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(headOnly ? undefined : data);
}

async function sendNotFound(res, headOnly) {
  // Prefer the site's own 404 page when one exists; fall back to plain text.
  try {
    await sendFile(res, join(SITE_ROOT, "404.html"), 404, headOnly);
  } catch {
    sendText(res, 404, "404 — page not found\n", headOnly);
  }
}

async function handle(req, res) {
  const headOnly = req.method === "HEAD";
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { Allow: "GET, HEAD", "Content-Type": "text/plain; charset=utf-8" });
    res.end("405 — method not allowed\n");
    return;
  }

  let urlPath;
  try {
    urlPath = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
  } catch {
    sendText(res, 400, "400 — bad request\n", headOnly);
    return;
  }

  // Resolve inside the site root and refuse path traversal outside it.
  const candidate = resolve(join(SITE_ROOT, "." + normalize(urlPath)));
  if (candidate !== SITE_ROOT && !candidate.startsWith(SITE_ROOT + sep)) {
    sendText(res, 403, "403 — forbidden\n", headOnly);
    return;
  }

  try {
    const info = await stat(candidate);
    if (info.isDirectory()) {
      if (!urlPath.endsWith("/")) {
        res.writeHead(301, { Location: urlPath + "/" });
        res.end();
        return;
      }
      await sendFile(res, join(candidate, "index.html"), 200, headOnly);
      return;
    }
    await sendFile(res, candidate, 200, headOnly);
  } catch {
    await sendNotFound(res, headOnly);
  }
}

const server = createServer((req, res) => {
  handle(req, res).catch(() => {
    if (!res.headersSent) sendText(res, 500, "500 — internal server error\n", false);
    else res.end();
  });
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use. Try: PORT=4174 node site/serve.mjs`);
  } else {
    console.error(err.message);
  }
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  console.log(`BadbUI site preview: http://${HOST}:${PORT}/ (serving ${SITE_ROOT})`);
  console.log("Press Ctrl+C to stop.");
});
