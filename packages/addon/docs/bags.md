# Inventario

Apri **/badb → Gioco → Inventario** o digita **/badb bags**. Seleziona Borse, Banca o Tutte le fonti e scegli il personaggio. La ricerca ignora maiuscole e accenti e accetta più parole o un ID oggetto. Ogni riga mostra la quantità di una variante per personaggio e fonte, anche se è distribuita in più slot. Passa il puntatore su un oggetto per leggerne il tooltip e usa il modificatore dei link in chat per inserirlo nella chat aperta.

- **/badb bags <testo>** apre la vista Borse con la ricerca precompilata.
- **/badb bags bank** apre la vista Banca. Visita un banchiere per acquisire il primo inventario della banca personale. Alla chiusura la vista usa l'ultima acquisizione.
- **Borse di WoW** apre la finestra del client per spostare o usare gli oggetti. Puoi anche aprirla con il normale tasto delle borse.
- In gioco trovi gli stessi passaggi in **Guide → Guida all'inventario**.

## Dati e compatibilità

`BadbUIDB.data.bags` conserva una copia locale di borse e banca personale per gli ultimi 24 personaggi, identificati da nome e reame. Alla lettura del salvataggio vengono scartate le acquisizioni più vecchie di 90 giorni e ogni fonte ha un limite di 1024 slot. Il cambio profilo conserva l'archivio. Se il client restituisce dati illeggibili, BadbUI conserva l'ultimo inventario disponibile.

`BadbUI.Bags:Find(query, scope, character)` restituisce le righe di ricerca del modulo attivo. `scope` accetta `"bags"`, `"bank"` o `"all"`. `character` è la chiave nome-reame, `"all"` o il personaggio corrente per impostazione predefinita. Ogni riga espone `item` (ID, quantità e link quando disponibile), `label`, `source`, `live`, `key` e `owner`. Tratta le righe e gli oggetti come dati di sola lettura.

BadbUI sonda `C_Container.GetContainerNumSlots`, `C_Container.GetContainerItemInfo`, `Enum.BagIndex` e, per il portachiavi, `GetKeyRingSize`. Usa le schede della banca personale quando il client ne espone gli indici. Blizzard documenta la vista unificata delle borse di Forever. La banca, il portachiavi e l'interazione con i tooltip devono ancora essere provati nel client Forever. [Panoramica Blizzard di WoW: Forever](https://news.blizzard.com/en-us/article/24315821/wow-foreverwhats-new-and-what-feels-familiar)

## Copertura Suite

- **Baganator:** parziale. Ricerca e visualizzazione unificate di borse e banca. L'uso o lo spostamento degli oggetti passa dalle finestre del client. Categorie personalizzate, ordinamento e trasferimenti rapidi rimangono scoperti.
- **Syndicator:** parziale. Conserva borse e banca personale per personaggio. Posta, equipaggiamento, aste e banca di gilda rimangono scoperti.
