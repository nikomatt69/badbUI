# Comodità di gioco

Apri **Gioco → Comodità di gioco** con `/badb qol`. Le automazioni si attivano singolarmente e seguono il profilo corrente.

- **Bottino automatico.** Usa la preferenza nativa di WoW. BadbUI ripristina il valore precedente quando disattivi il controllo, spegni il modulo o passi a un profilo che lascia la preferenza al client.
- **Riparazioni.** Apri un mercante abilitato a riparare. BadbUI effettua un tentativo per visita, con oro personale, se il costo rientra nel limite del profilo e il saldo è sufficiente. Tieni premuto Maiusc per saltare la visita.
- **Cianfrusaglie.** Apri un mercante e poi `/badb qol`. La vendita richiede conferma e usa la classificazione del client. Se nel frattempo il contenuto delle borse o il mercante cambiano, conferma nuovamente dopo aver controllato il nuovo conteggio.
- **Missioni.** Apri il dettaglio presso un PNG. BadbUI può accettare o consegnare dal dialogo attivo. Le missioni da oggetti, le offerte automatiche, le missioni condivise, le consegne che richiedono denaro o valuta e le scelte tra ricompense restano manuali. Maiusc sospende l'automazione.

La guida in gioco è disponibile anche con `/badb guide open qol:automation`.

## Implementazione e copertura

Il modulo `QoL` salva `autoLoot`, `autoRepair`, `repairCap`, `autoAccept` e `autoComplete` nel profilo. La preferenza nativa `autoLootDefault` passa dal servizio BadbUI dei CVar. Le azioni di mercante e missione usano le API native e verificano contesto e valori protetti prima della chiamata. Le azioni sospese durante il combattimento richiedono una nuova interazione.

La copertura di **Leatrix Plus** è parziale. Questa pagina copre bottino, riparazione personale, vendita nativa confermata e dialoghi semplici. Il supporto per fondi di gilda, esclusioni personalizzate dalle vendite, voli e altre automazioni resta da implementare. Finestre mobili, errori generici, ordinamento avanzato dei gruppi, aure avanzate e grafica Mac restano nelle rispettive aree. Le API presenti nel codice UI di Forever sono state confrontate con i riferimenti del client e la logica è verificata in Lua con mock. Rimane da provare ogni azione sul client effettivo. [Mercante Forever](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua), [API del mercante](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MerchantFrameDocumentation.lua), [Dialoghi delle missioni Forever](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestFrame.lua).
