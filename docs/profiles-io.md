# Profili e Import / Export

File: `Core/Database.lua` (logica profili e stringhe), `Config/ImportExport.lua` (pagina e `Badb.ImportExport`). Test: `tests/profiles_io_test.lua`.

## Profili (`Badb.DB`)
| Chiamata | Note |
|---|---|
| `DB.NormalizeName(nome)` | trim; rifiuta vuoto, oltre 48 caratteri (`DB.MAX_NAME`), `\|` (codici colore) e caratteri di controllo. Ritorna il nome normalizzato o `nil, errore`. |
| `DB:NewProfile(nome)` | profilo con i soli default, non attivato. `ok, nome` oppure `false, errore`. |
| `DB:CopyProfile(da, a)` | copia profonda indipendente; stesse regole sui nomi. |
| `DB:RenameProfile(vecchio, nuovo)` | sposta la stessa tabella (nessuna copia) e riallinea `profileKeys` e `specProfiles` di tutti i personaggi. Il profilo attivo resta attivo. `UI:RenameProfile`/`UI:CopyProfile` della shell delegano qui. |
| `DB:DeleteProfile(nome)` | rifiuta il profilo attivo e i profili inesistenti; rimuove ogni riferimento (personaggi e spec). |
| `DB:GetProfileUsers(nome)`, `DB:ProfileExists(nome)`, `DB:GetSpecProfile(i)` | lettura. |

Ogni modifica all'elenco emette `BADB_PROFILES_UPDATED`.

Specializzazione: se il profilo associato alla spec non esiste piu' (es. eliminato da un altro personaggio dello stesso account) non viene ricreato vuoto: l'assegnazione orfana viene rimossa con un avviso. In combattimento il cambio resta in coda fino a `PLAYER_REGEN_ENABLED`.

## Stringhe
| Chiamata | Note |
|---|---|
| `DB:ImportProfile(str, nome)` | crea un nuovo profilo; `ok, nome`. La forma viene verificata: `modules`/`frames` devono essere tabelle, le voci non tabella sono scartate e sostituite dai default. |
| `DB:ImportIntoActive(str)` | sostituisce il contenuto del profilo attivo (la UI chiede conferma). |
| `DB:ExportModule(nome[, profilo])` / `DB:ImportModule(str)` | solo le opzioni di un modulo, tipo `module:<Nome>`; rifiuta moduli non installati. |
| `DB:PreviewImport(str)` | analisi senza effetti: `{ kind, addon, modules, unknown, frames, hasLayout }`. |

Rifiutati con messaggio: input vuoto, formati di altri addon, base64 non valido, checksum errato (stringa troncata o modificata), versione futura, annidamento oltre 40 livelli, tipo sbagliato. Spazi e a capo del copia/incolla sono tollerati. Il parser non usa `loadstring`: i valori restano dati.

## Pagina "Import / Export" (`/badb io`, `/badb import`)
Gestione > Import / Export, dopo Profili. Esporta il profilo completo (qualsiasi profilo) o le opzioni di un modulo; la stringa viene selezionata per Ctrl+C. Per importare: incolla, **Analizza**, leggi l'anteprima (moduli, frame, layout Edit Mode, moduli ignorati perche' non installati), poi scegli:
- **Importa come nuovo profilo** (nome proposto libero e modificabile, poi attivato),
- **Sostituisci profilo attivo** (con conferma),
- **Importa nel profilo attivo** per le stringhe di un modulo.

Modificare il testo dopo l'analisi annulla l'anteprima: non si puo' applicare una stringa diversa da quella analizzata. Il pulsante Importa della pagina Profili apre questa pagina.

Logica pura in `Badb.ImportExport`: `Export(kind, target)`, `Analyze(str)`, `Describe(analisi)`, `Apply(azione, str, nome)`, `DefaultName()`, `OpenImport()`, `OpenExport(kind, target)`.
