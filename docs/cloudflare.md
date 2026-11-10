# Pubblicazione Cloudflare

L'applicazione usa un Cloudflare Worker con asset statici e un Durable Object SQLite. L'istanza nominata `badb-primary` è il server centrale di sito, mobile, bot e companion. **URL pubblico:** https://badb-guild.nikoemme-work.workers.dev

La configurazione è in `wrangler.jsonc`; le migrazioni SQL sono condivise con il server Bun.

## Primo accesso

Il sito pubblico non assegna il primo capogilda senza un codice d'installazione. Il segreto `BADB_SETUP_KEY` è configurato in Cloudflare, e una copia è conservata esclusivamente nel file locale privato `.cloudflare/setup-key.txt` (permessi `0600`, ignorato da Git). Non incollare quel codice in Discord, post, guide o candidature.

Apri il sito → **Accedi → Nuovo in gilda? Crea un account**, scegli nome/password e inserisci il codice di installazione. Solo dopo il primo account gli altri utenti possono registrarsi normalmente come ospiti, senza codice. Il codice non consente di accedere all'account già creato e non promuove account successivi.

## Comandi

```sh
bun run typecheck
bun run cloudflare:test
bun run cloudflare:deploy
```

Il test cloud esegue l'app con il runtime workerd (Miniflare): registrazione protetta, login, sessioni, permessi, disponibilità, gruppi, raid, prenotazioni, pubblicazioni, sync addon e persistenza dopo riavvio. Il deploy comprende sia sito sia API e non cancella lo storage.

Per un nuovo account Cloudflare sostituisci `account_id` e scegli un nome Worker libero in `wrangler.jsonc`. Autenticati con `bun run wrangler login`. Prima della prima pubblicazione configura il codice iniziale con `node script/cloudflare-setup-secret.mjs`; non distribuire senza segreto. Il comando crea il Worker vuoto se necessario e carica il segreto prima dell'applicazione.

## Client

Sito e API condividono l'URL del Worker. Il sito compilato usa la propria origine: non impostare `VITE_BADB_SERVER` a un indirizzo locale nella build pubblicata. L'app usa lo stesso URL; ogni utente collega la sessione con un codice mobile del sito. Per il companion specifica `--server https://<nome>.<sottodominio>.workers.dev` al login. Il bot usa `BADB_SERVER` con lo stesso URL. I valori per questa installazione sono anche in `.env.production.example`.

## Discord e gioco

Per il bot servono una vera app Discord, `DISCORD_TOKEN`, `DISCORD_APP_ID`, `DISCORD_GUILD_ID`, e lo stesso `BADB_BOT_SECRET` nel processo del bot e nel Worker:

```sh
bun run wrangler secret put BADB_BOT_SECRET
bun run wrangler secret put BADB_DISCORD_WEBHOOK
```

Il webhook è opzionale. Il bot Gateway resta un processo separato da eseguire su una macchina accesa; il Worker ospita il server centrale, non il processo Discord Gateway. Nessuna credenziale Discord reale viene generata o inventata. Il companion resta sul PC dove è installato WoW.

## Backup e aggiornamenti

I dati del Durable Object sono persistenti; una nuova versione del Worker non li azzera. Cloudflare offre le funzionalità di recupero dello storage SQLite. Conserva le vecchie migrazioni ed aggiungine di nuove; non cambiare l'istanza `badb-primary` o la classe `GuildServer` per un aggiornamento ordinario, altrimenti useresti un database differente. Le copie SQLite locali del server Bun non vengono caricate automaticamente in produzione.

## Riferimenti ufficiali

- [SQLite nei Durable Objects](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)
- [Migrazioni e ciclo di vita](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/)
- [API crypto di Node supportate nei Workers](https://developers.cloudflare.com/workers/runtime-apis/nodejs/crypto/)

## Collegamento dell’armory e due capogilda

La pagina `/#/collegamento` permette di scaricare addon e companion, generare il codice personale, vedere l’ultimo invio e importare manualmente uno snapshot `BadbUI.lua` già esportato dal client. La scansione viene validata dal server e rimane associata all’account che la invia. Una selezione del file mostra prima il riepilogo; l’importazione richiede un’azione esplicita.

La gestione ufficiali mostra anche i client collegati, build e numero di personaggi ricevuti, con eventuali errori. Il capogilda può promuovere l’amico allo stesso grado dalla gestione membri. Entrambi avranno pieni permessi; il server impedisce di rimuovere l’ultimo capogilda.

I pacchetti pubblici sono disponibili in `/downloads/`; `release.json` contiene versione, dimensioni e hash SHA-256. La build riprepara i pacchetti senza includere snapshot o credenziali. Il companion scaricabile richiede Bun.

Gli ufficiali e i capogilda possono riassegnare il collegamento di un personaggio a un account dall’armory; i dati osservati nel client restano protetti da modifiche manuali. Il pannello consente creazione, modifica e rimozione dei gruppi, configurazione dei posti per ruolo e durata, modifica dei singoli raid, e modifica/eliminazione di guide, post e boss. Le rimozioni richiedono conferma nell’interfaccia.
