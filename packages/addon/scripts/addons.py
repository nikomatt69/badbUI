#!/usr/bin/env python3
"""BadbUI - gestore degli addon (solo libreria standard, Python 3.8+).

Installa, aggiorna e rimuove gli addon elencati in scripts/addons.json.
  python3 scripts/addons.py list
  python3 scripts/addons.py install essentials        (oppure id singoli: xperl bigwigs ...)
  python3 scripts/addons.py install-zip xperl ~/Downloads/XPerl.zip
  python3 scripts/addons.py update | remove <id> | doctor | install-badbui [--link]

Cartella AddOns: --dir, oppure variabile WOW_ADDONS_DIR, oppure rilevata nei percorsi standard.
Sicurezza: solo HTTPS verso host noti (anche nei redirect), zip senza percorsi fuori cartella,
backup di ogni cartella sostituita, e non tocca cartelle che non ha installato senza --force.
"""
import argparse
import fnmatch
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MANIFEST = os.path.join(HERE, "addons.json")
REGISTRY = ".badbui-addons.json"
BACKUPS = ".badbui-backup"
MAX_ZIP = 200 * 1024 * 1024
ALLOWED_HOSTS = {
    "api.github.com", "github.com", "codeload.github.com", "objects.githubusercontent.com",
    "release-assets.githubusercontent.com", "api.curseforge.com", "edge.forgecdn.net", "mediafilez.forgecdn.net",
}
BADBUI_DIRS = ["Core", "UI", "Config", "Modules", "Data", "Locales"]
KNOWN_CONFLICT_FOLDERS = {
    "xperl": ["XPerl", "ZPerl", "XPerl_Player", "ZPerl_Player", "MetaPerl", "CPerl", "FPerl"],
    "elvui": ["ElvUI"], "plater": ["Plater"], "bartender4": ["Bartender4"],
    "dbm": ["DBM-Core"], "bigwigs": ["BigWigs"],
}


class Fail(Exception):
    pass


# ---------------------------------------------------------------------------
# Manifest e cartelle
# ---------------------------------------------------------------------------

def load_manifest(path=MANIFEST):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    validate_manifest(data)
    return data


def validate_manifest(data):
    if not isinstance(data, dict) or data.get("schema") != 1:
        raise Fail("manifest: schema non supportato")
    ids = set()
    for a in data.get("addons", []):
        for key in ("id", "title", "role", "source"):
            if key not in a:
                raise Fail("manifest: addon senza '%s'" % key)
        if not re.fullmatch(r"[a-z0-9_-]{1,32}", a["id"]) or a["id"] in ids:
            raise Fail("manifest: id non valido o duplicato: %r" % a["id"])
        ids.add(a["id"])
        t = a["source"].get("type")
        need = {"github-release": ("repo", "asset"), "github-archive": ("repo", "ref"),
                "curseforge": ("slug",), "manual": ("page",)}.get(t)
        if need is None or any(k not in a["source"] for k in need):
            raise Fail("manifest: sorgente non valida per %s" % a["id"])
        if t.startswith("github") and not re.fullmatch(r"[A-Za-z0-9_-][\w.-]*/[A-Za-z0-9_-][\w.-]*", a["source"]["repo"]):
            raise Fail("manifest: repo non valido per %s" % a["id"])
    for name, members in data.get("bundles", {}).items():
        for m in members:
            if m not in ids:
                raise Fail("manifest: il bundle %s cita un id sconosciuto: %s" % (name, m))


def candidate_dirs():
    out = []
    if sys.platform == "darwin":
        roots = ["/Applications/World of Warcraft", os.path.expanduser("~/Applications/World of Warcraft")]
    elif sys.platform.startswith("win"):
        roots = [r"C:\Program Files (x86)\World of Warcraft", r"C:\Program Files\World of Warcraft"]
    else:
        roots = [os.path.expanduser("~/Games/world-of-warcraft/drive_c/Program Files (x86)/World of Warcraft")]
    for r in roots:
        if os.path.isdir(r):
            for sub in sorted(os.listdir(r)):
                p = os.path.join(r, sub, "Interface", "AddOns")
                if sub.startswith("_") and os.path.isdir(p):
                    out.append(p)
    return out


def addons_dir(arg):
    path = arg or os.environ.get("WOW_ADDONS_DIR")
    if not path:
        found = candidate_dirs()
        if len(found) == 1:
            path = found[0]
        elif not found:
            raise Fail("cartella AddOns non trovata: usa --dir oppure WOW_ADDONS_DIR")
        else:
            raise Fail("piu' cartelle AddOns trovate, scegline una con --dir:\n  " + "\n  ".join(found))
    path = os.path.abspath(os.path.expanduser(path))
    if not os.path.isdir(path):
        raise Fail("la cartella non esiste: %s" % path)
    return path


def read_registry(base):
    try:
        with open(os.path.join(base, REGISTRY), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_registry(base, reg):
    tmp = os.path.join(base, REGISTRY + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(reg, f, indent=2, sort_keys=True)
    os.replace(tmp, os.path.join(base, REGISTRY))


def toc_version(folder):
    name = os.path.basename(folder.rstrip("/\\"))
    for cand in (name + ".toc", name + "_Mainline.toc", name + "_Classic.toc"):
        p = os.path.join(folder, cand)
        if os.path.isfile(p):
            try:
                with open(p, encoding="utf-8", errors="replace") as f:
                    for line in f:
                        m = re.match(r"##\s*Version:\s*(.+)", line)
                        if m:
                            return m.group(1).strip()
                        if not line.startswith("##"):
                            break
            except OSError:
                pass
            return "?"
    return None


# ---------------------------------------------------------------------------
# Rete (solo HTTPS, solo host noti, anche nei redirect)
# ---------------------------------------------------------------------------

def check_url(url):
    p = urllib.parse.urlparse(url)
    if p.scheme != "https" or p.hostname not in ALLOWED_HOSTS:
        raise Fail("URL non consentito: %s" % url)


class GuardRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_opener = urllib.request.build_opener(GuardRedirect)


def http(url, headers=None, limit=None):
    check_url(url)
    h = {"User-Agent": "BadbUI-addons/1"}
    h.update(headers or {})
    token = os.environ.get("GITHUB_TOKEN")
    if token and urllib.parse.urlparse(url).hostname == "api.github.com":
        h["Authorization"] = "Bearer " + token
    try:
        with _opener.open(urllib.request.Request(url, headers=h), timeout=60) as r:
            data = r.read(limit + 1) if limit else r.read()
    except urllib.error.HTTPError as e:
        raise Fail("HTTP %s da %s%s" % (e.code, urllib.parse.urlparse(url).hostname,
                                         " (limite API GitHub: imposta GITHUB_TOKEN)" if e.code == 403 else ""))
    except urllib.error.URLError as e:
        raise Fail("rete non raggiungibile: %s" % e.reason)
    if limit and len(data) > limit:
        raise Fail("download troppo grande (>%d MB)" % (limit // 1048576))
    return data


def http_json(url, headers=None):
    try:
        return json.loads(http(url, headers).decode("utf-8"))
    except ValueError:
        raise Fail("risposta non valida da %s" % urllib.parse.urlparse(url).hostname)


# ---------------------------------------------------------------------------
# Risoluzione della sorgente -> (versione, url, nome file)  oppure  Manual
# ---------------------------------------------------------------------------

class Manual(Exception):
    def __init__(self, page, why):
        super().__init__(why)
        self.page, self.why = page, why


def pick_asset(assets, pattern):
    names = [a for a in assets if fnmatch.fnmatch(a.get("name", ""), pattern) and a.get("browser_download_url")]
    return names[0] if names else None


def resolve(addon):
    s = addon["source"]
    t = s["type"]
    if t == "github-release":
        rel = http_json("https://api.github.com/repos/%s/releases/latest" % s["repo"])
        asset = pick_asset(rel.get("assets", []), s["asset"])
        if not asset:
            raise Fail("%s: nessun file '%s' nell'ultima release" % (addon["id"], s["asset"]))
        return str(rel.get("tag_name", "?")), asset["browser_download_url"]
    if t == "github-archive":
        try:
            sha = http_json("https://api.github.com/repos/%s/commits/%s" % (s["repo"], s["ref"]))["sha"][:7]
        except (Fail, KeyError):
            sha = s["ref"]
        ref = urllib.parse.quote(s["ref"], safe="")
        return "%s@%s" % (s["ref"], sha), "https://codeload.github.com/%s/zip/refs/heads/%s" % (s["repo"], ref)
    if t == "curseforge":
        key = os.environ.get("CURSEFORGE_API_KEY")
        page = s.get("page") or "https://www.curseforge.com/wow/addons/" + s["slug"]
        if not key:
            raise Manual(page, "serve CURSEFORGE_API_KEY (gratuita su console.curseforge.com) per il download automatico")
        hdr = {"x-api-key": key, "Accept": "application/json"}
        found = http_json("https://api.curseforge.com/v1/mods/search?gameId=1&slug=%s"
                          % urllib.parse.quote(s["slug"]), hdr).get("data", [])
        if not found:
            raise Manual(page, "progetto non trovato su CurseForge")
        files = http_json("https://api.curseforge.com/v1/mods/%s/files?pageSize=20" % found[0]["id"], hdr).get("data", [])
        files = [f for f in files if f.get("downloadUrl")]
        if not files:
            raise Manual(page, "l'autore non permette il download da API")
        files.sort(key=lambda f: f.get("fileDate", ""), reverse=True)
        f = files[0]
        return str(f.get("displayName") or f.get("fileName")), f["downloadUrl"]
    raise Manual(s.get("page", ""), "installazione manuale")


# ---------------------------------------------------------------------------
# Zip: estrazione sicura delle sole cartelle addon (con .toc)
# ---------------------------------------------------------------------------

def safe_member(name):
    if name.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", name):
        return False
    return ".." not in re.split(r"[\\/]", name)


def find_addon_dirs(names):
    """Prefissi (con '/') delle cartelle addon: <cartella>/<cartella>[_Flavor].toc, profondita' <= 2."""
    prefixes = []
    for n in names:
        parts = n.split("/")
        if len(parts) in (2, 3) and parts[-1].lower().endswith(".toc"):
            folder = parts[-2]
            stem = parts[-1][:-4]
            if stem == folder or re.fullmatch(re.escape(folder) + r"[_-]\w+", stem):
                prefixes.append("/".join(parts[:-1]) + "/")
    prefixes = sorted(set(prefixes), key=len)
    out = []
    for p in prefixes:  # niente cartelle annidate dentro un'altra gia' scelta
        if not any(p.startswith(q) for q in out):
            out.append(p)
    return out


def extract_addons(zip_path, dest):
    """Estrae in dest/<NomeCartella>/...; ritorna i nomi delle cartelle."""
    with zipfile.ZipFile(zip_path) as z:
        names = [i.filename for i in z.infolist()]
        bad = [n for n in names if not safe_member(n)]
        if bad:
            raise Fail("zip non sicuro (percorsi fuori cartella): %s" % bad[0])
        if sum(i.file_size for i in z.infolist()) > 4 * MAX_ZIP:
            raise Fail("zip troppo grande una volta estratto")
        prefixes = find_addon_dirs([n for n in names if not n.endswith("/")])
        if not prefixes:
            raise Fail("lo zip non contiene cartelle addon (nessun .toc)")
        folders = []
        for p in prefixes:
            folder = p.rstrip("/").split("/")[-1]
            folders.append(folder)
            for info in z.infolist():
                if info.filename.startswith(p) and not info.filename.endswith("/"):
                    target = os.path.join(dest, folder, info.filename[len(p):])
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with z.open(info) as src, open(target, "wb") as out:
                        shutil.copyfileobj(src, out)
        return folders


# ---------------------------------------------------------------------------
# Installazione
# ---------------------------------------------------------------------------

def install_folders(base, staged, folders, owned, force, dry):
    """Sposta le cartelle da staged a base. Cartelle esistenti non nostre: serve --force. Sempre backup."""
    for f in folders:
        if f == "BadbUI":
            raise Fail("cartella 'BadbUI' riservata: usa install-badbui")
        if os.path.exists(os.path.join(base, f)) and f not in owned and not force:
            raise Fail("'%s' esiste gia' e non l'ho installata io: usa --force (ne faccio prima un backup)" % f)
    if dry:
        return
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for f in folders:
        dst = os.path.join(base, f)
        if os.path.exists(dst):
            bk = os.path.join(base, BACKUPS, stamp)
            os.makedirs(bk, exist_ok=True)
            shutil.move(dst, os.path.join(bk, f))
        shutil.move(os.path.join(staged, f), dst)


def install_one(base, addon, reg, args, zip_path=None):
    aid = addon["id"]
    owned = set(reg.get(aid, {}).get("folders", []))
    with tempfile.TemporaryDirectory(prefix="badbui-addon-") as tmp:
        version = "zip"
        if zip_path is None:
            version, url = resolve(addon)
            if args.dry_run:
                print("  [prova] %s %s <- %s" % (aid, version, url))
                return True
            print("  scarico %s %s ..." % (addon["title"], version))
            zip_path = os.path.join(tmp, "dl.zip")
            with open(zip_path, "wb") as f:
                f.write(http(url, limit=MAX_ZIP))
        staged = os.path.join(tmp, "out")
        os.makedirs(staged)
        try:
            folders = extract_addons(zip_path, staged)
        except zipfile.BadZipFile:
            raise Fail("il file scaricato non e' uno zip valido")
        install_folders(base, staged, folders, owned, args.force, args.dry_run)
        if args.dry_run:
            print("  [prova] %s: installerei %s" % (aid, ", ".join(folders)))
            return True
        for old in owned - set(folders):  # cartelle di una versione precedente non piu' presenti
            p = os.path.join(base, old)
            if os.path.isdir(p):
                bk = os.path.join(base, BACKUPS, time.strftime("%Y%m%d-%H%M%S"))
                os.makedirs(bk, exist_ok=True)
                shutil.move(p, os.path.join(bk, old))
        reg[aid] = {"version": version, "folders": folders, "installedAt": int(time.time()),
                    "source": addon["source"].get("repo") or addon["source"].get("slug", "zip")}
        write_registry(base, reg)
        print("  ok: %s %s (%s)" % (addon["title"], version, ", ".join(folders)))
    return True


def expand_targets(manifest, names):
    by_id = {a["id"]: a for a in manifest["addons"]}
    out = []
    for n in names:
        n = n.lstrip("@")
        members = manifest["bundles"].get(n) or ([n] if n in by_id else None)
        if not members:
            raise Fail("sconosciuto: %s (id: %s; bundle: %s)" % (n, ", ".join(by_id), ", ".join(manifest["bundles"])))
        for m in members:
            if m not in out:
                out.append(m)
    return [by_id[i] for i in out]


# ---------------------------------------------------------------------------
# Comandi
# ---------------------------------------------------------------------------

def cmd_list(args, manifest):
    base = None
    try:
        base = addons_dir(args.dir)
    except Fail as e:
        print("(%s)" % e)
    reg = read_registry(base) if base else {}
    print("Bundle: " + "; ".join("%s=%s" % (k, ",".join(v)) for k, v in manifest["bundles"].items()))
    for a in manifest["addons"]:
        state = "non installato"
        if base:
            r = reg.get(a["id"])
            if r:
                state = "installato " + r["version"]
            else:
                found = [f for f in KNOWN_CONFLICT_FOLDERS.get(a["id"], []) if os.path.isdir(os.path.join(base, f))]
                if found:
                    state = "presente (non gestito da script): " + ", ".join(found)
        print("- %-10s %-26s %s\n    %s\n    Forever: %s" % (a["id"], a["title"], state, a["role"], a.get("forever", "?")))
    return 0


def cmd_install(args, manifest):
    base = addons_dir(args.dir)
    reg = read_registry(base)
    failed = manual = 0
    for a in expand_targets(manifest, args.targets):
        print("%s" % a["title"])
        try:
            install_one(base, a, reg, args)
        except Manual as m:
            manual += 1
            print("  manuale: %s\n  scarica da %s e poi: python3 scripts/addons.py install-zip %s <file.zip>"
                  % (m.why, m.page, a["id"]))
        except Fail as e:
            failed += 1
            print("  ERRORE: %s" % e)
        if a.get("conflictNote"):
            print("  nota: " + a["conflictNote"])
    if failed:
        return 1
    return 3 if manual else 0


def cmd_install_zip(args, manifest):
    base = addons_dir(args.dir)
    a = expand_targets(manifest, [args.target])[0]
    if not os.path.isfile(args.zip):
        raise Fail("file non trovato: %s" % args.zip)
    install_one(base, a, read_registry(base), args, zip_path=args.zip)
    return 0


def cmd_update(args, manifest):
    base = addons_dir(args.dir)
    reg = read_registry(base)
    if not reg:
        print("Nessun addon installato da script.")
        return 0
    by_id = {a["id"]: a for a in manifest["addons"]}
    rc = 0
    for aid in sorted(reg):
        a = by_id.get(aid)
        if not a:
            continue
        try:
            version, _ = resolve(a)
        except Manual as m:
            print("%s: aggiornamento manuale (%s)" % (a["title"], m.page))
            continue
        except Fail as e:
            print("%s: ERRORE %s" % (a["title"], e))
            rc = 1
            continue
        if version == reg[aid]["version"]:
            print("%s: gia' aggiornato (%s)" % (a["title"], version))
        elif args.check:
            print("%s: disponibile %s (installato %s)" % (a["title"], version, reg[aid]["version"]))
        else:
            try:
                install_one(base, a, reg, args)
            except Fail as e:
                print("%s: ERRORE %s" % (a["title"], e))
                rc = 1
    return rc


def cmd_remove(args, manifest):
    base = addons_dir(args.dir)
    reg = read_registry(base)
    for aid in args.ids:
        r = reg.get(aid)
        if not r:
            print("%s: non installato da script, non lo tocco" % aid)
            continue
        stamp = time.strftime("%Y%m%d-%H%M%S")
        for f in r["folders"]:
            p = os.path.join(base, f)
            if os.path.isdir(p):
                if args.dry_run:
                    print("  [prova] rimuoverei %s" % f)
                    continue
                bk = os.path.join(base, BACKUPS, stamp)
                os.makedirs(bk, exist_ok=True)
                shutil.move(p, os.path.join(bk, f))
        if not args.dry_run:
            del reg[aid]
            write_registry(base, reg)
            print("%s rimosso (backup in %s)" % (aid, os.path.join(base, BACKUPS, stamp)))
    return 0


def cmd_doctor(args, manifest):
    base = addons_dir(args.dir)
    present = {}
    for aid, folders in KNOWN_CONFLICT_FOLDERS.items():
        hit = [f for f in folders if os.path.isdir(os.path.join(base, f))]
        if hit:
            present[aid] = hit
    badb = toc_version(os.path.join(base, "BadbUI"))
    print("BadbUI: %s" % (("installato " + badb) if badb else "NON installato (python3 scripts/addons.py install-badbui)"))
    warnings = 0
    by_id = {a["id"]: a for a in manifest["addons"]}
    for aid in present:
        a = by_id.get(aid, {})
        for c in a.get("conflicts", []):
            if c.startswith("addon:") and c[6:] in present:
                warnings += 1
                print("! %s e %s sono entrambi presenti: %s" % (aid, c[6:], a.get("conflictNote", "")))
            elif c.startswith("badbui:") and badb:
                warnings += 1
                print("! %s presente: puo' confliggere con il modulo %s di BadbUI. %s"
                      % (aid, c[7:], a.get("conflictNote", "")))
    print("Presenti: %s" % (", ".join("%s (%s)" % (k, "/".join(v)) for k, v in present.items()) or "nessun addon noto"))
    print("Suggerimento in gioco: /badb doctor per il controllo completo dei conflitti.")
    return 1 if warnings else 0


def cmd_install_badbui(args, manifest):
    base = addons_dir(args.dir)
    dst = os.path.join(base, "BadbUI")
    if os.path.lexists(dst):
        if os.path.islink(dst):
            os.unlink(dst)
        else:
            bk = os.path.join(base, BACKUPS, time.strftime("%Y%m%d-%H%M%S"))
            os.makedirs(bk, exist_ok=True)
            shutil.move(dst, os.path.join(bk, "BadbUI"))
    if args.link:
        os.symlink(REPO, dst)
        print("BadbUI collegato (symlink) -> %s" % REPO)
        return 0
    os.makedirs(dst)
    for d in BADBUI_DIRS:
        shutil.copytree(os.path.join(REPO, d), os.path.join(dst, d))
    shutil.copy2(os.path.join(REPO, "BadbUI.toc"), dst)
    print("BadbUI copiato in %s" % dst)
    return 0


def build_parser():
    p = argparse.ArgumentParser(description="Gestore addon BadbUI")
    p.add_argument("--dir", help="cartella Interface/AddOns (o WOW_ADDONS_DIR)")
    p.add_argument("--dry-run", action="store_true", help="mostra senza scrivere nulla")
    p.add_argument("--force", action="store_true", help="sostituisce cartelle esistenti non gestite (con backup)")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    s = sub.add_parser("install"); s.add_argument("targets", nargs="+", help="id o bundle (essentials, pvp, full)"); s.set_defaults(fn=cmd_install)
    s = sub.add_parser("install-zip"); s.add_argument("target"); s.add_argument("zip"); s.set_defaults(fn=cmd_install_zip)
    s = sub.add_parser("update"); s.add_argument("--check", action="store_true"); s.set_defaults(fn=cmd_update)
    s = sub.add_parser("remove"); s.add_argument("ids", nargs="+"); s.set_defaults(fn=cmd_remove)
    sub.add_parser("doctor").set_defaults(fn=cmd_doctor)
    s = sub.add_parser("install-badbui"); s.add_argument("--link", action="store_true", help="symlink (sviluppo)"); s.set_defaults(fn=cmd_install_badbui)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args, load_manifest())
    except Fail as e:
        print("Errore: %s" % e, file=sys.stderr)
        return 1
    except (OSError, zipfile.BadZipFile) as e:
        print("Errore di file: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
