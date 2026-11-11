# Professioni

Apri **Gioco → Professioni** con `/badb prof`. Il modulo mostra i gradi delle professioni del personaggio corrente e i tempi di recupero che hai configurato. Non contiene ricette, database o elenchi di incantesimi inventati.

- **Gradi.** `/badb prof list` legge `GetProfessions`/`GetProfessionInfo` (sondate con esistenza e `pcall`, valori filtrati da `Badb.Compat.IsSecret`) e salva uno snapshot per personaggio in `Badb.DB:GetStore("professions")` (`version = 1`, massimo 50 personaggi, massimo 12 professioni). Se l'API manca, la pagina mostra "Professioni non disponibili su questo client."
- **Tempi di recupero.** Aggiungi solo gli ID che ti interessano: `/badb prof add <ID incantesimo>`, `/badb prof remove <ID>`, `/badb prof clear` (massimo 20). BadbUI interroga `GetSpellCooldown`/`GetSpellInfo`/`GetTime` sondati e mostra il tempo restante o "Pronto". Nessun cooldown giornaliero/settimanale viene dedotto: su Forever non è verificata un'API legale che elenchi i cooldown delle professioni, quindi non viene inventato nulla.
- **Aggiornamento.** Lo snapshot si aggiorna all'attivazione, a `SKILL_LINES_CHANGED` e al logout. `/badb prof refresh` forza la rilettura.

## Copertura dichiarata

`replaces` è vuoto: **nessuna sostituzione dichiarata**. Rispetto agli addon per professioni/tradeskill, la copertura è al più parziale (gradi + cooldown scelti dall'utente) e mancano ricette, materiali, code di crafting e cooldown appresi automaticamente; per questo non viene dichiarata alcuna riga `full` o `partial` nella Suite finché l'integratore non decide una mappatura onesta.

## Gilda: cosa copre già BadbUI_Guild (non duplicato qui)

Il bridge separato `packages/guild-addon` (`BadbUI_Guild`, richiede BadbUI) + companion/server coprono già, senza duplicati in questo modulo:

- calendario raid, iscrizioni (`yes/no/maybe/bench`), disponibilità settimanale (maschera 21 slot) e azioni accodate nelle SavedVariables per il companion;
- roster catturato da `GetNumGuildMembers`/`GetGuildRosterInfo` e snapshot armory (equipaggiamento, professioni, livello) da API del client, solo su interface 16001;
- boss/tattiche, diario e guide di gilda ricevuti dal server; pannello con `/badb guild` (alias `/badb gilda`), scansione con `/badb guildscan`.

Azioni ufficiali di gilda (inviti, espulsioni, gradi) **non** sono implementate: le API Lua di gilda per invitare/espellere sono protette o richiedono conferme del client, quindi BadbUI non le automatizza e non le aggira.

### Nuovo: export roster di sola lettura

`/badb guild export` (nel bridge, `Guild:ExportRoster()`) restituisce il roster già catturato come testo `name;class;level;rank` ordinato per nome, con campi sanificati (`;`, `|`, newline rimossi). Se il roster è vuoto ritorna un errore esplicito invece di una stringa vuota. Non usa nessuna API protetta: legge solo `BadbUI_GuildExport.roster`.

## Limiti noti e verifica in gioco

Da verificare sul client Forever reale: esistenza/forma di `GetProfessions`/`GetProfessionInfo` (ritorni multipli), `GetSpellCooldown` per gli ID scelti, evento `SKILL_LINES_CHANGED`. Il codice degrada a messaggio chiaro se mancano. Salute/minaccia segrete e combat log illeggibile non sono usati da questo modulo.
