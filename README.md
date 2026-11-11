# Fratelli di Azeroth — Guild companion per WoW Forever

**Sito pubblicato:** https://badb-guild.nikoemme-work.workers.dev — [primo accesso come capogilda](docs/cloudflare.md#primo-accesso).

Monorepo Bun: **un server centrale**, un dominio condiviso e un SDK usato da sito, app mobile, bot Discord e companion dell’addon. L’addon BadbUI originale rimane in `packages/addon` con i suoi moduli e test.

## Avvio locale

Richiede Bun 1.4.4. Per i test dell’addon serve LuaJIT o Lua 5.1.

```sh
bun install --frozen-lockfile
cp .env.example .env
bun run web:build
bun run start
```

Apri **http://localhost:4096**. Il sito compilato e l’API sono serviti dallo stesso processo grazie a `BADB_WEB` nell’esempio `.env`. Crea il primo account **in locale**: diventa capogilda. Gli account successivi sono ospiti; un ufficiale accetta la candidatura o cambia il grado dalla gestione. Nessun account, roster o equipaggiamento fittizio viene creato dal seed.

Durante lo sviluppo, in due terminali:

```sh
bun run dev
bun run web:dev
```

Il sito Vite è su http://localhost:5173. `BADB_ORIGINS` regola CORS; `VITE_BADB_SERVER` sceglie il server API. I valori Vite vengono letti dalla `.env` nella radice. In produzione sito e API possono condividere l’origine: rimuovi `VITE_BADB_SERVER` prima della build se vuoi URL relativi all’host.

## Pacchetti

| Pacchetto   | Responsabilità                                                                    |
| ----------- | --------------------------------------------------------------------------------- |
| `core`      | Contratti Zod, classi/raid, orari e fusi, motore tattico, parser Lua di soli dati |
| `server`    | Hono, SQLite con migrazioni, sessioni, permessi, dominio e flusso SSE             |
| `sdk`       | Client HTTP tipizzato, errori e timeout, eventi con riconnessione                 |
| `web`       | Solid + Vite: sito di gilda e gestione ufficiali                                  |
| `mobile`    | Expo Router per iOS/Android; token in SecureStore                                 |
| `discord`   | Slash command; nessun intent privilegiato e risposte private                      |
| `companion` | CLI Bun: SavedVariables → API → file dati dell’addon                              |
| `addon`     | BadbUI Lua; UI di gioco, scansione Forever e coda persistente                     |

Dipendenze: `core → server`; `core → sdk → client`. Il server non importa i client. I test di integrazione dei client usano il server in memoria. Tutte le regole e autorizzazioni vengono applicate dal server.

## Funzioni

- Home, diario di gilda, guide e candidatura con disponibilità e contributo opzionale in argenti **da consegnare in gioco**. Nessun pagamento online.
- Armory ricercabile, equipaggiamento e professioni letti dal client; schede manuali indicate separatamente.
- Disponibilità settimanali: intervalli precisi, griglia per mattina/pomeriggio/sera e frasi italiane. Calendario nel fuso della gilda; date e cambi dell’ora legale sono gestiti dal core.
- Tre gruppi iniziali: mattina, pomeriggio e sera. Giorni, raid, orari, capogruppo e formazione fissa configurabili. Pianificazione settimanale senza duplicati.
- Prenotazioni per giocatore, personaggio principale, riserve, scelta dei titolari, chiusura e annullamento degli eventi.
- Boss e requisiti tattici configurabili, classifica per ruolo e matrice di capacità modificabile dagli ufficiali.
- Profilo con codici monouso per addon, mobile e Discord; gradi ospite/membro/ufficiale/capogilda; gestione candidature e pubblicazioni.

La UI web e mobile usa Cinzel e IBM Plex Sans, bronzo, ossidiana e verde fel, con colori di classe, pannelli da grimorio e controlli accessibili. I font sono inclusi localmente con le rispettive licenze.

## Dati reali di Forever

La fonte dell’armory è **la scansione delle API del client Forever**, non Wowhead e non un dataset Classic sostitutivo. Il flusso conserva versione/build/interfaccia, istante della scansione, oggetti e professioni osservati. Le scansioni che dichiarano un’interfaccia diversa da `16001` vengono rifiutate. Snapshot precedenti non retrocedono una scheda più recente. Le modifiche manuali non sovrascrivono una scheda proveniente dal client.

Il roster letto da un ufficiale fornisce nome, classe, livello e grado; **non inventa gear o spec dei compagni**. Per l’equipaggiamento completo ciascun giocatore deve collegare il proprio addon/companion. Quando la cache degli oggetti è incompleta, l’addon attende le informazioni e non pubblica una nuova scansione parziale. I dati non accessibili dalle API restano assenti. Il formato consente nomi con cognome.

Le scansioni sono importazioni fornite dal giocatore: build e dati non sono certificati crittograficamente da Blizzard. La compatibilità delle API è sondata, ma **va ancora verificata nel client Forever reale**. Non è stata eseguita una sincronizzazione con un account di gioco reale in questo ambiente. Non è implementato un importatore Battle.net OAuth.

Nomi e dimensioni dei raid iniziali sono confermati dalla [pagina ufficiale Blizzard](https://news.blizzard.com/en-us/article/24303009/world-of-warcraft-forever-raid-overviewlocations-raid-sizes-and-attunement). Il seed include una scheda Onyxia senza pesi tattici: gli ufficiali configurano quelli verificati. La matrice iniziale delle capacità è un’ipotesi storica, esplicitamente indicata come tale; i punteggi **non sono statistiche di prestazioni, simulazioni DPS o classifiche reali di Forever**. Wowhead è soltanto un link di consultazione degli oggetti e può differire dagli oggetti modificati in gioco.

Riferimenti e limiti delle API: [provenienza dei dati](docs/data-provenance.md).

## Collegare l’addon

```sh
bun run addon:package
```

Estrai lo ZIP `dist/BadbUI-<versione>.zip` in `<client Forever>/Interface/AddOns/`. Il percorso finale è `Interface/AddOns/BadbUI/BadbUI.toc`. Il pacchetto distribuito non contiene snapshot personali.

1. Dal sito: **Profilo → Collega addon**. Il codice dura 10 minuti ed è monouso.
2. Usa la cartella **del client** che contiene `Interface` e `WTF`, e il nome esatto dell’account sotto `WTF/Account`:

```sh
bun run --cwd packages/companion start login ABCDEFGH --wow "/percorso/client Forever" --account "ACCOUNT" --server http://localhost:4096
bun run --cwd packages/companion start watch
```

3. In gioco: `/badb gilda` per calendario, disponibilità, tattiche, guide, notizie e armory ricevuti dal server. `/badb guildscan` aggiorna lo snapshot.
4. Dopo una modifica fai `/reload` per salvare le SavedVariables. Attendi **“Dati pronti”** nel companion; poi fai `/reload` per caricare la risposta. Servono due passaggi perché l’addon non ha rete e il companion lavora dopo la scrittura del gioco. Logout/login può essere usato allo stesso scopo.

Il companion legge solo `SavedVariables/BadbUI.lua`: non lo modifica mai. Scrive atomicamente `Data/GuildSync.lua`. I file Lua vengono parsati come dati, mai eseguiti dal companion. I token restano nella configurazione privata `~/.config/badb/companion.json` (permessi `0600`), fuori dai file dell’addon. Per un file diverso usa `--config`. Per un server remoto il companion richiede HTTPS.

### Aggiornare BadbUI dal gioco

Con BadbUI 1.0.1 e companion 0.3.1 o successivi, lascia attivo `watch`. Puoi anche avviare il companion solo per gli aggiornamenti, senza account di gilda:

```sh
bun companion.mjs updates --wow "<cartella client Forever>" --account "<account in WTF/Account>"
```

Fai `/reload` per leggere lo stato del catalogo, poi apri `/badb update`. Se è disponibile una release, premi **Installa aggiornamento**, conferma ed esci completamente da WoW. Attendi la conferma nel terminale prima di riaprire il gioco. Il companion consulta il catalogo ufficiale, verifica versione e SHA-256 e conserva la cartella precedente in `Interface/.badbui-update-backup`. Le SavedVariables restano in `WTF`.

Le azioni hanno ricevute persistenti: una ripetizione non duplica l’iscrizione e non trasforma un rifiuto in successo. Azioni rifiutate sono mostrate in gioco e rimosse dalla coda. Il companion deve rimanere in esecuzione sul PC. Non c’è sincronizzazione diretta addon→Internet o distribuzione tra giocatori via chat addon.

## Discord

Crea un’app Discord, aggiungi il bot alla tua gilda con gli scope `bot` e `applications.commands`. Imposta nella `.env` `DISCORD_TOKEN`, `DISCORD_APP_ID`, `DISCORD_GUILD_ID` e `BADB_BOT_SECRET` (lo stesso segreto sul server e nel bot). Non inserirli nei client pubblici.

```sh
bun packages/discord/src/register.ts
bun run discord:dev
```

Comandi: `/collega codice:…`, `/disponibilita testo:ci sono mercoledì dalle 20 alle 23`, `/raid`, `/prenota`, `/armory`, `/boss`. Il bot agisce per l’account Discord collegato; i permessi sono quelli dell’utente sul server. Opera solo nella gilda Discord configurata, con risposte private e menzioni disabilitate. Il webhook opzionale del server annuncia raid e post. Nessun bot o webhook reale è stato avviato durante lo sviluppo.

## App mobile

```sh
bun run mobile:dev
```

Apri con Expo Go compatibile con SDK 58 o con una build di sviluppo. Dal sito genera **Collega mobile**; nell’app inserisci URL del server e codice. Un telefono fisico deve raggiungere il PC tramite il suo indirizzo LAN, non `localhost`. Puoi impostare `EXPO_PUBLIC_BADB_SERVER` in `packages/mobile/.env`. In produzione usa HTTPS. La sessione è conservata con Expo SecureStore.

L’app comprende home/guide/tattiche, raid e presenze, disponibilità, armory e profilo. La gestione ufficiali e le candidature sono sul sito. Supporta aggiornamento manuale e trascinamento per ricaricare; non include notifiche push o una coda di modifiche offline. I bundle iOS/Android vengono esportati da `bun run mobile:build`; non equivale a una build firmata o a una verifica su telefono.

## Verifica

```sh
bun run typecheck
bun run test
bun run test:addon
bun run web:build
bun run mobile:build
bun run addon:package
```

La CI esegue typecheck, test TypeScript, build web/mobile, sintassi Lua e le tre suite dell’addon. I test del ponte usano un filesystem temporaneo e una API in memoria: coprono parsing sicuro, dati client, provenienza, ricevute, immutabilità del file del gioco, rifiuto di client diversi e comandi Discord sullo stesso calendario.

## Cloudflare

È disponibile anche il runtime Cloudflare Worker con Durable Object SQLite: sito e API condividono lo stesso host, e tutte le piattaforme accedono allo stesso stato persistente. [Deployment, primo accesso e configurazione dei client](docs/cloudflare.md).

```sh
bun run cloudflare:test
bun run cloudflare:deploy
```

In questa modalità il primo account richiede il codice `BADB_SETUP_KEY`, conservato nel file privato `.cloudflare/setup-key.txt`. I successivi utenti si registrano normalmente come ospiti.

## Server e distribuzione

SQLite è persistito in `BADB_DB`; tutte le migrazioni sono versionate. Per backup usa l’API backup di SQLite o arresta il server prima di copiare il database. Non copiare solo il `.sqlite` mentre il WAL è attivo.

È incluso un `Dockerfile` che compila sito e server e usa `/data/badb.sqlite` per il volume persistente. Configura HTTPS nel reverse proxy, `BADB_ORIGINS` per le origini del sito e i segreti solo sul server/bot. Registra il primo capogilda prima di rendere il servizio raggiungibile pubblicamente. La modalità Bun/Docker resta disponibile come alternativa al runtime Cloudflare.

## Armory collegata e gestione condivisa

Apri **Collega WoW** per installare i componenti, generare il codice di collegamento e controllare l’ultimo invio reale. È disponibile anche un’importazione manuale di `BadbUI.lua`, con anteprima prima dell’invio. La gestione capogilda comprende lo stato dei client, oltre a personaggi, membri, gruppi, raid, candidature, guide e diario.

Tu e il tuo amico potete essere entrambi capogilda: dopo la registrazione, assegna a entrambi il grado **Capogilda** dalla gestione membri.
