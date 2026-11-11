# Bottino ed equipaggiamento

Apri `/badb loot`. Nella scheda **Confronta** inserisci un ID oppure un link oggetto. Per confrontare due oggetti, inserisci un riferimento dello stesso tipo di equipaggiamento. **Pesi delle statistiche** apre le preferenze del profilo. Le statistiche iniziano tutte con peso zero. Il calcolo somma ogni valore riportato dal client moltiplicato per il suo peso.

**Preferiti bottino** conserva fino a 100 obiettivi personali condivisi fra i profili. **Bottini osservati** memorizza le ultime 240 combinazioni oggetto e zona, per 90 giorni, quando il client rende disponibile il contenuto del bottino. La registrazione si può disattivare per profilo. I tooltip con punteggio e preferiti sono facoltativi e vengono mostrati fuori combattimento.

BadbUI usa `C_Item.GetItemInfo`, `C_Item.GetItemStats`, `GetLootSlotLink` e le API native dei tooltip quando disponibili. `BadbUI.Loot:Compare(candidate, baseline?)` restituisce il risultato, il riferimento e la differenza, oppure `nil` e un codice di stato. I pesi sono nel profilo, l'archivio versionato in `BadbUIDB.data.loot`.

La copertura di Pawn, AtlasLootClassic e AtlasBIStooltips è parziale. Effetti, incavi, DPS delle armi, suggerimenti automatici, percentuali di drop, fonti precompilate e liste BiS sono fuori dal calcolo e dall'archivio. La guida in gioco si apre con `/badb guide open loot:confronto`.
