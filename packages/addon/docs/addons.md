# Gestione degli addon (X-Perl e compagni)

`scripts/addons.py` installa, aggiorna e rimuove gli addon elencati in `scripts/addons.json`.
Solo Python 3.8+ (libreria standard), funziona su macOS, Windows e Linux.

```
python3 scripts/addons.py list                       # cosa c'e' nel manifest e cosa e' installato
python3 scripts/addons.py install essentials         # X-Perl + BigWigs + Details!
python3 scripts/addons.py install pvp                # + Plater + WeakAuras
python3 scripts/addons.py install bigwigs plater     # id singoli
python3 scripts/addons.py install-zip xperl ~/Downloads/X-Perl.zip
python3 scripts/addons.py update [--check]
python3 scripts/addons.py remove plater
python3 scripts/addons.py doctor                     # conflitti con BadbUI e tra addon
python3 scripts/addons.py install-badbui [--link]    # copia (o symlink di sviluppo) di BadbUI
```
Opzioni globali: `--dir <AddOns>` (o `WOW_ADDONS_DIR`), `--dry-run`, `--force`.
La cartella AddOns viene rilevata nei percorsi standard se ce n'e' una sola.

## X-Perl su Forever
Le release normali di X-Perl/Z-Perl **non funzionano** sul client Forever; esistono adattamenti non ufficiali
(X-Perl Forever, MetaPerl, C-Perl, F-Perl). Il manifest usa
[X-Perl Forever](https://www.curseforge.com/wow/addons/x-perl-unitframes-forever). CurseForge consente il
download da API solo con una chiave gratuita ([console.curseforge.com](https://console.curseforge.com)):

* con `CURSEFORGE_API_KEY` impostata, `install xperl` scarica da solo;
* senza chiave lo script stampa la pagina: scarichi lo zip a mano e usi `install-zip xperl <file.zip>`.

**X-Perl sostituisce i frame unita'**: usalo al posto del modulo UnitFrames di BadbUI
(`/badb disable UnitFrames`). `doctor` e `/badb doctor` lo segnalano.

## Fonti e cosa viene installato
| id | Fonte | Note |
|---|---|---|
| xperl | CurseForge (chiave o manuale) | fork non ufficiale per Forever |
| elvui | GitHub `tukui-org/ElvUI` ramo `main` | puo' essere piu' avanti del client |
| bigwigs, dbm, plater, bartender4, weakauras | ultima release GitHub | zip ufficiali di release |
| details | CurseForge (chiave o manuale) | il meter nativo di Forever puo' bastare |

Aggiungere un addon: una voce in `scripts/addons.json` (tipi `github-release`, `github-archive`, `curseforge`,
`manual`); il manifest viene validato a ogni avvio e dai test.

**Nessun addon e' garantito su Forever**: dove le fonti sono incerte il campo `forever` del manifest lo dice
(vedi anche [FOREVER_FACTS.md](FOREVER_FACTS.md)). Il codice degli addon non e' incluso in BadbUI: si scarica
dalla fonte dell'autore, con la sua licenza.

## Sicurezza
* Solo HTTPS e solo host noti (GitHub, CurseForge), controllati anche a ogni redirect.
* Zip con percorsi fuori cartella (`..`, assoluti) rifiutati; si estraggono solo le cartelle con un `.toc`.
* Ogni cartella sostituita o rimossa finisce prima in `AddOns/.badbui-backup/<data>/`.
* Una cartella che non ha installato lo script richiede `--force`; `BadbUI` e' riservata a `install-badbui`.
* `.badbui-addons.json` in AddOns ricorda cosa ha installato lo script (solo quello viene aggiornato o rimosso).

## Lato gioco
`/badb` > Integrazioni rileva X-Perl (solo rilevamento, nessun profilo catturato: struttura non verificata) e
`/badb doctor` avvisa del conflitto con UnitFrames/GroupFrames.

## Test
`python3 tests/scripts/test_addons.py` (nessuna rete): manifest, rete consentita, zip pericolosi, installazione,
backup, `--force`, `--dry-run`, rimozione, conflitti.
