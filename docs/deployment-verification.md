# Verifica della pubblicazione

Data: 10 novembre 2026.

URL: https://badb-guild.nikoemme-work.workers.dev

Versione Cloudflare pubblicata: `2fed12c8-1611-4855-91a7-9d40acba4643`.

## Ambiente pubblico

- Home caricata in Safari e controllata tramite albero accessibile e screenshot: tema, font, navigazione, tre gruppi raid e contenuti iniziali visibili.
- `/` e gli asset JavaScript, CSS e font restituiscono HTTP 200.
- `/health`, `/home`, `/group`, `/character`, `/auth/setup` restituiscono JSON valido e HTTP 200.
- `/auth/setup` conferma che la creazione del primo capogilda richiede il codice installazione.
- `/availability` senza sessione restituisce HTTP 401.
- Un login con account inesistente restituisce HTTP 401, senza creare account o dati dimostrativi.
- `.env`, `.cloudflare/setup-key.txt` e route API inesistenti restituiscono HTTP 404.
- I documenti statici hanno CSP e protezioni contro inclusione in frame esterni e interpretazione errata del contenuto.

## Runtime Cloudflare locale

Il test con workerd/Miniflare esegue il bundle distribuito e verifica: protezione del primo account, login corretto/errato, utenti e gradi, disponibilità, modifica gruppi, raid, prenotazioni, scelta titolari, modifica gilda, collegamento addon, importazione equipaggiamento, ricevute idempotenti, pubblicazione post e flusso SSE. Dopo un riavvio completo controlla persistenza di account, token, armory e impostazioni; quindi verifica la revoca della sessione.

Typecheck su otto pacchetti e bundle iOS/Android riusciti. Le suite Bun per server, SDK, companion e bot sono verdi dopo l'adattamento a Cloudflare.

## Limiti della verifica

Il test nel browser riguarda la home pubblica. I flussi autenticati completi sono verificati nel runtime Cloudflare locale, non con account di prova nel database pubblico. Il primo account di produzione resta da creare dal proprietario, con password scelta da lui.

Il sito pubblicato non è stato collegato a una sessione WoW reale o a credenziali Discord reali. Il companion richiede installazione sul PC di gioco; il bot richiede un'app Discord e un processo Gateway attivo. I dati reali dell'armory compariranno solo dopo la prima scansione ricevuta dal client. Non sono state eseguite build native firmate o verifiche su un telefono fisico.

Aggiornamento del nome: Fratelli di Azeroth, applicato al sito, ai client e alle impostazioni persistenti della gilda.

## Collegamento reale del client

L’installazione locale di BadbUI è stata aggiornata alla versione 0.3.0, con backup completo dell’addon precedente e senza modificare SavedVariables o profili. Il client rilevato è Forever 1.60.1.70862. Non era ancora presente un export `BadbUI_GuildExport`: occorre aprire il gioco con il modulo aggiornato e salvare con /reload o logout.

Il sito ora distribuisce addon e companion sotto `/downloads/`, con hash SHA-256 verificati sui file scaricati dall’URL pubblico. Le route di stato e controllo client richiedono autenticazione. Il runtime Cloudflare verifica anche i permessi sulle riassegnazioni dei personaggi e lo stato delle importazioni.

Finché il proprietario non crea l’account e fornisce al companion il codice personale di collegamento, la sincronizzazione dal suo client non può essere considerata attiva. Non sono stati creati account o personaggi fittizi in produzione.

## Redeploy e controllo segreti — 10 novembre 2026, 19:22 UTC

Versione Cloudflare: `43d81cb8-319b-477b-a77d-29d6c74af5c9`.

- Ripubblicati Worker, sito e download: addon 0.3.1, companion 0.3.0 e chatbot 0.3.0. Il catalogo distribuito contiene 6.609 macro.
- Typecheck riuscito su nove pacchetti; suite Bun di core, server, SDK, companion, Discord e chatbot riuscite. Il test Miniflare del bundle Cloudflare passa, inclusa la persistenza dopo riavvio.
- Verifica HTTP pubblica: home e health 200, disponibilità senza sessione 401. JavaScript e CSS corrispondono esattamente alla build locale; dimensioni e SHA-256 dei sei URL ZIP corrispondono al manifest.
- `.env`, `.env.production`, `.dev.vars`, `.cloudflare/setup-key.txt`, `.git/config`, `wrangler.jsonc` e i sorgenti server non sono pubblicamente accessibili (404).
- Gitleaks 8.30.1: nessun segreto rilevato nei 40 commit precedenti, nei 257 file candidati alla pubblicazione, nel bundle Worker, negli asset web e nei contenuti estratti dagli ZIP pubblici. La chiave privata di installazione locale non compare nei file o nei pacchetti controllati.
- Estese le esclusioni Git alle varianti `.env.*` e `.dev.vars.*`, mantenendo versionabili gli esempi. Le directory private `.cloudflare` e `.wrangler` restano escluse.

La scansione automatica non costituisce una garanzia assoluta di assenza di credenziali. Il redeploy mantiene i dati del Durable Object e non avvia i processi esterni del bot Discord o dei client sul PC di gioco.
