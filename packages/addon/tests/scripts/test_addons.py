"""Test del gestore addon (scripts/addons.py): nessuna rete, solo file temporanei."""
import io
import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
import addons  # noqa: E402


def make_zip(path, files):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in files.items():
            z.writestr(name, data)


class Args:
    dir = None
    dry_run = False
    force = False


class ManifestTests(unittest.TestCase):
    def test_manifest_reale_valido_e_contiene_xperl(self):
        m = addons.load_manifest()
        ids = {a["id"] for a in m["addons"]}
        self.assertIn("xperl", ids)
        self.assertIn("xperl", m["bundles"]["essentials"])

    def test_manifest_rifiuta_errori(self):
        base = {"schema": 1, "bundles": {}, "addons": []}
        addons.validate_manifest(base)
        bad = [
            {"schema": 2, "addons": []},
            {"schema": 1, "bundles": {"x": ["nope"]}, "addons": []},
            {"schema": 1, "bundles": {}, "addons": [{"id": "A B", "title": "t", "role": "r", "source": {"type": "manual", "page": "p"}}]},
            {"schema": 1, "bundles": {}, "addons": [{"id": "a", "title": "t", "role": "r", "source": {"type": "ftp"}}]},
            {"schema": 1, "bundles": {}, "addons": [{"id": "a", "title": "t", "role": "r", "source": {"type": "github-release", "repo": "../x", "asset": "*"}}]},
        ]
        for b in bad:
            with self.assertRaises(addons.Fail, msg=str(b)):
                addons.validate_manifest(b)


class NetworkGuardTests(unittest.TestCase):
    def test_solo_https_e_host_noti(self):
        addons.check_url("https://api.github.com/repos/a/b")
        for url in ("http://api.github.com/x", "https://evil.example.com/a.zip", "file:///etc/passwd", "https://github.com.evil.io/x"):
            with self.assertRaises(addons.Fail, msg=url):
                addons.check_url(url)


class ZipTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_release_semplice_piu_cartelle(self):
        z = os.path.join(self.root, "a.zip")
        make_zip(z, {"Plater/Plater.toc": "## Version: 1", "Plater/a.lua": "x",
                     "Plater_Extra/Plater_Extra.toc": "", "README.md": "ignorato"})
        out = os.path.join(self.root, "out")
        os.makedirs(out)
        self.assertEqual(sorted(addons.extract_addons(z, out)), ["Plater", "Plater_Extra"])
        self.assertTrue(os.path.isfile(os.path.join(out, "Plater", "a.lua")))
        self.assertFalse(os.path.exists(os.path.join(out, "README.md")))

    def test_archivio_github_con_cartella_wrapper(self):
        z = os.path.join(self.root, "b.zip")
        make_zip(z, {"ElvUI-main/ElvUI/ElvUI.toc": "", "ElvUI-main/ElvUI/Core.lua": "x",
                     "ElvUI-main/ElvUI_Options/ElvUI_Options.toc": "", "ElvUI-main/Makefile": "x"})
        out = os.path.join(self.root, "out")
        os.makedirs(out)
        self.assertEqual(sorted(addons.extract_addons(z, out)), ["ElvUI", "ElvUI_Options"])
        self.assertTrue(os.path.isfile(os.path.join(out, "ElvUI", "Core.lua")))

    def test_toc_con_suffisso_flavor(self):
        self.assertEqual(addons.find_addon_dirs(["Foo/Foo_Mainline.toc"]), ["Foo/"])
        self.assertEqual(addons.find_addon_dirs(["Foo/Bar.toc"]), [])

    def test_percorsi_pericolosi_rifiutati(self):
        for name in ("../evil.lua", "Foo/../../evil.lua", "/abs/evil.lua", "C:/evil.lua"):
            z = os.path.join(self.root, "c.zip")
            make_zip(z, {"Foo/Foo.toc": "", name: "x"})
            out = os.path.join(self.root, "out")
            os.makedirs(out, exist_ok=True)
            with self.assertRaises(addons.Fail, msg=name):
                addons.extract_addons(z, out)
        self.assertFalse(os.path.exists(os.path.join(self.root, "evil.lua")))

    def test_zip_senza_addon(self):
        z = os.path.join(self.root, "d.zip")
        make_zip(z, {"solo/testo.txt": "x"})
        with self.assertRaises(addons.Fail):
            addons.extract_addons(z, self.root)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = os.path.join(self.tmp.name, "AddOns")
        os.makedirs(self.base)
        self.manifest = addons.load_manifest()
        self.xperl = [a for a in self.manifest["addons"] if a["id"] == "xperl"][0]
        self.zip = os.path.join(self.tmp.name, "x.zip")
        make_zip(self.zip, {"XPerl/XPerl.toc": "## Version: 9.9\n", "XPerl/main.lua": "v1"})

    def tearDown(self):
        self.tmp.cleanup()

    def install(self, **kw):
        a = Args()
        a.__dict__.update(kw)
        reg = addons.read_registry(self.base)
        addons.install_one(self.base, self.xperl, reg, a, zip_path=self.zip)

    def test_installa_registra_e_rimuove_con_backup(self):
        self.install()
        self.assertEqual(addons.toc_version(os.path.join(self.base, "XPerl")), "9.9")
        reg = addons.read_registry(self.base)
        self.assertEqual(reg["xperl"]["folders"], ["XPerl"])
        a = Args(); a.dir = self.base; a.ids = ["xperl"]
        addons.cmd_remove(a, self.manifest)
        self.assertFalse(os.path.exists(os.path.join(self.base, "XPerl")))
        self.assertNotIn("xperl", addons.read_registry(self.base))
        backups = os.listdir(os.path.join(self.base, addons.BACKUPS))
        self.assertEqual(len(backups), 1)

    def test_reinstallazione_fa_backup_della_versione_precedente(self):
        self.install()
        make_zip(self.zip, {"XPerl/XPerl.toc": "## Version: 10\n", "XPerl/main.lua": "v2"})
        self.install()
        self.assertEqual(addons.toc_version(os.path.join(self.base, "XPerl")), "10")
        bk = os.path.join(self.base, addons.BACKUPS)
        stamp = os.listdir(bk)[0]
        with open(os.path.join(bk, stamp, "XPerl", "main.lua")) as f:
            self.assertEqual(f.read(), "v1")

    def test_cartella_non_nostra_richiede_force(self):
        os.makedirs(os.path.join(self.base, "XPerl"))
        with open(os.path.join(self.base, "XPerl", "mio.lua"), "w") as f:
            f.write("dati utente")
        with self.assertRaises(addons.Fail):
            self.install()
        with open(os.path.join(self.base, "XPerl", "mio.lua")) as f:
            self.assertEqual(f.read(), "dati utente")
        self.install(force=True)
        self.assertTrue(os.path.isfile(os.path.join(self.base, "XPerl", "main.lua")))

    def test_dry_run_non_scrive(self):
        self.install(dry_run=True)
        self.assertFalse(os.path.exists(os.path.join(self.base, "XPerl")))
        self.assertEqual(addons.read_registry(self.base), {})

    def test_badbui_riservata(self):
        make_zip(self.zip, {"BadbUI/BadbUI.toc": ""})
        with self.assertRaises(addons.Fail):
            self.install(force=True)

    def test_registro_corrotto_ignorato(self):
        with open(os.path.join(self.base, addons.REGISTRY), "w") as f:
            f.write("{non json")
        self.assertEqual(addons.read_registry(self.base), {})

    def test_remove_non_tocca_cartelle_non_gestite(self):
        os.makedirs(os.path.join(self.base, "XPerl"))
        a = Args(); a.dir = self.base; a.ids = ["xperl"]; a.dry_run = False
        addons.cmd_remove(a, self.manifest)
        self.assertTrue(os.path.isdir(os.path.join(self.base, "XPerl")))

    def test_curseforge_senza_chiave_e_manuale(self):
        os.environ.pop("CURSEFORGE_API_KEY", None)
        with self.assertRaises(addons.Manual) as ctx:
            addons.resolve(self.xperl)
        self.assertIn("curseforge.com", ctx.exception.page)

    def test_target_sconosciuto_e_bundle(self):
        with self.assertRaises(addons.Fail):
            addons.expand_targets(self.manifest, ["nonesiste"])
        ids = [a["id"] for a in addons.expand_targets(self.manifest, ["essentials", "xperl"])]
        self.assertEqual(ids, self.manifest["bundles"]["essentials"])

    def test_doctor_segnala_conflitto_con_badbui(self):
        os.makedirs(os.path.join(self.base, "BadbUI"))
        with open(os.path.join(self.base, "BadbUI", "BadbUI.toc"), "w") as f:
            f.write("## Version: 1\n")
        os.makedirs(os.path.join(self.base, "XPerl"))
        a = Args(); a.dir = self.base
        self.assertEqual(addons.cmd_doctor(a, self.manifest), 1)


if __name__ == "__main__":
    unittest.main()
