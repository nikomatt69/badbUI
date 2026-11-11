# Diario missioni

Apri **/badb → Gioco → Diario missioni** o usa **/badb quests**. Cerca per titolo, zona o ID. Apri una riga per leggere gli obiettivi e **Metti in evidenza** per aggiungerla al tuo elenco. **Da consegnare** usa lo stato del registro di WoW. **Cronologia** mostra le ultime consegne osservate e gli XP ricevuti, quando il client li espone. Nel footer vedi il progresso del livello attuale.

Puoi attivare il **monitor delle missioni in evidenza** dalle opzioni del Diario. Mostra fino a cinque missioni con il prossimo obiettivo leggibile o lo stato di consegna. Il titolo riapre il Diario e **/badb unlock** permette di spostare il monitor. Per la storia, le ricompense e le aree degli obiettivi usa il registro e la mappa di WoW. I marcatori nativi dipendono dalle impostazioni del client. [Guida introduttiva ufficiale di WoW: Forever](https://news.blizzard.com/en-us/article/24315280/new-players-starter-guide-welcome-to-world-of-warcraft-forever)

## Dati e integrazione

`BadbUIDB.data.quests` conserva fino a 25 missioni in evidenza e 50 consegne ciascuno per gli ultimi 24 personaggi. La cronologia inizia quando attivi il modulo e resta condivisa tra i profili di un personaggio. Le missioni rimosse o consegnate escono da In evidenza. Il monitor si abilita per profilo.

`BadbUI.Quests:List(query, filter)` restituisce le voci di sola lettura del Diario. I filtri sono `all`, `pinned`, `ready` e `history`. `BadbUI.Quests:SetPinned(questID, true|false)` modifica il monitor locale. Per mettere in evidenza una nuova missione, la voce deve essere leggibile nel registro attivo.

Il modulo sonda `C_QuestLog.GetNumQuestLogEntries`, `GetInfo`, `GetQuestObjectives`, `ReadyForTurnIn`, `IsComplete`, `IsFailed` e le API XP. Se il registro diventa illeggibile conserva l'ultima lettura in memoria e la contrassegna. La copertura del registro dipende da ciò che il client espone, anche per sezioni compresse e dati limitati. La resa grafica del Diario e il monitor vanno verificati nel client Forever.

## Copertura Suite

- **Questie:** parziale. Registro, obiettivi, filtro di consegna e monitor delle missioni attive. Database delle missioni, marcatori aggiuntivi e condivisione di gruppo restano scoperti.
- **Polestar:** parziale. Monitor, XP e cronologia. Rotte guidate, banche dati e navigazione restano scoperti. I pacchetti dei dati e delle guide dedicate conservano le loro funzioni.
