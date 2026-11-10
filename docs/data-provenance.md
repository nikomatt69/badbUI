# Provenienza e attendibilità dei dati

Il requisito è usare dati di WoW Forever. Il codice non usa un’armory Classic come sostituto.

| Dato                                     | Fonte implementata                                                  | Limite                                                                                                        |
| ---------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Nome, classe, livello, razza             | API del giocatore in `Modules/Guild.lua`                            | I valori segreti/non leggibili vengono ignorati                                                               |
| Spec e ruolo                             | `Core/PlayerInfo.lua`, tramite API disponibili e override espliciti | Quando l’API non identifica la spec resta `null`; il ruolo applicativo può essere dedotto per le prenotazioni |
| Oggetti, qualità, livello oggetto        | Inventory e `C_Item.GetItemInfo`/fallback presenti nel client       | Si attende una cache completa; nessun gear inventato                                                          |
| Professioni                              | `GetProfessions` / `GetProfessionInfo`, se disponibili              | L’assenza dell’API non equivale a “nessuna professione”                                                       |
| Roster                                   | Snapshot completo visibile a un ufficiale                           | Non fornisce l’equipaggiamento degli altri giocatori                                                          |
| Disponibilità e presenze                 | Dichiarazioni dei membri, server centrale                           | Non sono dati forniti da Blizzard                                                                             |
| Blog e guide                             | Contenuti degli ufficiali                                           | Il seed contiene istruzioni operative                                                                         |
| Requisiti del boss e capacità delle spec | Configurazione degli ufficiali                                      | La matrice storica iniziale è ipotetica, non bilanciamento Forever misurato                                   |
| Dimensione e nome dei raid iniziali      | Blizzard News                                                       | I consigli di composizione sono impostazioni modificabili della gilda                                         |

Il server registra `client.version`, `client.build`, `client.interface` e `scannedAt` separatamente dal tempo di ricezione. Non accetta una build che dichiara un’interfaccia diversa da 16001; ciò evita importazioni accidentali da Retail/Classic, ma non autentica una scansione fornita dal giocatore.

Il companion conserva gli ID delle azioni e il server ne registra l’esito. Un vecchio snapshot non può sostituire una scansione successiva. Le schede lette dall’addon non sono modificabili manualmente, salvo la scelta del personaggio principale.

## Fonti consultate il 10 novembre 2026

- [Blizzard — Forever raid overview](https://news.blizzard.com/en-us/article/24303009/world-of-warcraft-forever-raid-overviewlocations-raid-sizes-and-attunement): fonte primaria per i tre raid, i livelli e le dimensioni.
- [API esportata dal client Forever](https://atraeau.github.io/WoW-Addons/api.json): documentazione generata dai file API del client, metadati versione 1.60.1 / build 70790 / interface 16001. È una pubblicazione comunitaria dei dati del client, non una garanzia di compatibilità su ogni build.
- [Expo SecureStore](https://docs.expo.dev/versions/latest/sdk/securestore/): conservazione della sessione mobile.
- [Discord — Application commands](https://docs.discord.com/developers/docs/interactions/slash-commands): registrazione dei comandi. Il bot usa il Gateway di discord.js, non un endpoint HTTP di interazioni.

Il precedente `packages/addon/docs/FOREVER_FACTS.md` contiene anche fonti secondarie e ipotesi: non rende i dati di gioco verificati per il solo fatto di essere nel repository.

Non sono stati forniti in questa sessione un’installazione WoW con SavedVariables reali, un account Battle.net o credenziali Discord. I test usano fixture dichiarate come tali. La prima acquisizione reale va quindi verificata con il companion collegato al client dell’utente. Il sito vuoto deve rimanere vuoto fino a quel momento.

## Hosting Cloudflare

Il Worker inoltra tutte le API allo stesso Durable Object SQLite `badb-primary`. I file del sito sono serviti dal binding statico; non esiste un database diverso per ciascun client. Le migrazioni sono condivise con il server Bun e sono tracciate in `_badb_migration` su Cloudflare, poiché Durable Objects non supporta `PRAGMA user_version`.

I test Cloudflare eseguono il bundle con workerd/Miniflare, verificano operazioni sui dati, permessi e ricevute, poi riavviano il runtime e controllano che account, sessioni e armory persistano. Questi test restano distinti dalla prima scansione di un client di gioco reale.
