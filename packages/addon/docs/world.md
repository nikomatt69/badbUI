# Waypoint

Apri **/badb → Gioco → Waypoint** o digita **/badb waypoint**. Puoi salvare la posizione del personaggio, importare il segnaposto già visibile sulla mappa di WoW oppure inserire l'ID mappa e le coordinate da 0 a 100. L'ID viene precompilato dalla mappa aperta o dalla zona attuale. Per salvare direttamente nella zona attuale usa **/badb waypoint 35,7 42,5 Nome**. La ricerca usa il nome del waypoint e la mappa.

Seleziona un punto e scegli **Segui** per vedere la destinazione e la distanza in linea d'aria quando entrambe le posizioni sono sulla stessa mappa e il client ne espone la scala. Il monitor si sposta con **/badb unlock** e si può spegnere per profilo. **Segna sulla mappa** usa l'unico segnaposto personale di WoW. **Ripristina segnaposto** ripristina il punto precedente quando BadbUI riconosce ancora il proprio. Anche disattivare il modulo ripristina il punto precedente, fuori combattimento. BadbUI conserva la proprietà del segnaposto per la sessione corrente. [Codice Blizzard della mappa e del controllo per i segnaposto](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMapTemplates.lua)

## Dati e API

`BadbUIDB.data.world` conserva fino a 100 waypoint per account. La destinazione attiva è di sessione. `BadbUI.World:List()` restituisce copie dei waypoint con `id`, `label`, `map`, `x` e `y`. `BadbUI.World:Add(mapID, x, y, label)` aggiunge un punto con rapporti da 0 a 1 e restituisce l'ID. `BadbUI.World:Track(id)` seleziona una destinazione e `Track(nil)` la cancella dal monitor.

Il modulo sonda `C_Map.GetBestMapForUnit`, `GetPlayerMapPosition`, `GetMapInfo`, `GetMapWorldSize`, le API del segnaposto e `UiMapPoint.CreateFromCoordinates`. Se il client non espone la posizione o non accetta il segnaposto su una mappa, il salvataggio manuale e la lista restano disponibili. La resa grafica e le API di mappa vanno verificate nel client Forever.

## Copertura Suite

- **TomTom:** parziale. Waypoint salvati, coordinate, distanza sulla stessa mappa e segnaposto nativo. Freccia, percorsi e segnalini sulla minimappa restano scoperti.
- Le modifiche alla mappa di Leatrix Maps, le mappe di Atlas, i nodi di GatherMate2 e gli avvisi di RareScanner rimangono fuori dal modulo.
