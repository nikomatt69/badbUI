# Statistiche di combattimento

Apri **Gioco → Statistiche di combattimento** in `/badb` oppure usa `/badb combat`. Puoi aprire il pannello automaticamente all'accesso. Trascina l'intestazione o usa `/badb unlock` per spostarlo. La posizione e le dimensioni seguono il profilo BadbUI.

- **Resoconto**. Scegli la statistica e lo scontro. Il menu include le metriche esposte dal client, lo scontro corrente, il totale della sessione e fino a 30 scontri recenti. Seleziona una riga per vedere le magie quando il client fornisce un identificatore pubblico e l'API del dettaglio.
- **Minaccia**. Usa `/badb combat threat` e seleziona un bersaglio ostile. Le percentuali indicano la soglia di aggro alla distanza di ogni partecipante. L'ordine usa la minaccia grezza quando disponibile, poi lo stato di aggro.

La guida in gioco si apre con `/badb guide open suite-combat:meter`.

## Disponibilità e copertura

Il modulo usa le API native `C_DamageMeter` e `UnitDetailedThreatSituation` / `UnitThreatSituation`, rilevate al momento dell'uso. La scheda Resoconto mantiene l'ordine dei partecipanti fornito dal client. I valori opachi del contatore vengono passati solo alle funzioni di visualizzazione consentite di `FontString`. Le barre e la graduatoria della minaccia usano esclusivamente numeri pubblici. Quando un intero insieme di dati è riservato, il pannello lo indica. [Definizioni API Blizzard per il contatore](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua), [definizioni API Blizzard per FontString](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua).

La copertura di Details!, Details! Tiny Threat e ThreatClassic2 è parziale. Lo storico è quello fornito dal client. Confronto tra giocatori, esportazione, registrazione persistente, pannelli streamer e altri plugin Details! restano fuori dalla copertura. Le letture di minaccia sono limitate al bersaglio e alle API disponibili.

Il pannello non cambia CVar, stato dei pannelli Blizzard o registro di combattimento. Posizione, dimensioni e apertura all'accesso sono le sole impostazioni salvate. I dati di combattimento vivono in memoria. A pannello chiuso gli eventi non avviano letture. A pannello aperto gli aggiornamenti ravvicinati sono accorpati ogni 250 ms.

## Verifica su Forever

La scheda Resoconto, il dettaglio delle magie, la minaccia e i valori opachi sono coperti dal mock Lua. Sul client Forever 1.60.x restano da verificare la disponibilità delle metriche dopo uno scontro, la resa dei valori opachi in istanza, le sessioni storiche e il posizionamento con diversi UI scale.
