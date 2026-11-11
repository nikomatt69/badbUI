# Casa d'aste

Parla con un banditore, digita `/badb auction` e cerca un oggetto per nome. Ogni pressione di **Cerca** invia una richiesta, con il limite di frequenza del client. Il risultato mostra il minimo riportato dal client, la quantità quando disponibile e le eventuali varianti. Le ricerche possono contenere solo la prima pagina. Per salvare un termine usa **Salva ricerca** e richiamalo dal menu. Le selezioni del menu non avviano richieste.

**Storico** mostra le osservazioni locali, una al giorno per mercato e variante. Seleziona un oggetto per confrontare fino a 21 giorni di osservazioni. Il modulo conserva l'ultima rilevazione del giorno e separa reame, fazione e zona del banditore. Questi valori rappresentano le offerte viste al momento della ricerca. Per preparare una vendita, confronta prezzi correnti e storico, poi inserisci e conferma il prezzo nella finestra Blizzard.

In **Gioco → Casa d'aste** puoi attivare **Ultimo prezzo delle merci nel tooltip**. Mostra l'ultima osservazione con luogo e data, solo per le merci identificate dal client senza varianti e fuori combattimento. Guida in gioco con `/badb guide open auction:market`.

## Dati e copertura

Le impostazioni del tooltip seguono il profilo. L'archivio locale `BadbUIDB.data.auction` contiene fino a 500 combinazioni di mercato e variante, 21 giorni di osservazioni e 24 ricerche salvate condivise fra i profili. I dati provengono da `C_AuctionHouse`; gli acquisti e le inserzioni passano dai controlli nativi Blizzard. Un'altra ricerca intercettata durante quella di BadbUI annulla l'attesa e l'utente può riprovare.

La copertura di Auctionator è **parziale**. Include ricerca per nome, salvataggio dei termini, storico dei minimi osservati e tooltip opzionale per merci senza varianti. Rimangono scansioni estese, liste di acquisto strutturate, storico delle transazioni, automazioni di vendita e integrazione con le professioni. Il flusso è verificato con mock Lua e resta da provare nel client Forever. [Riferimento API Forever](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua).
