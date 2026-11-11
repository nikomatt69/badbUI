# Estendere BadbUI

BadbUI espone `BadbUI.API` con `version = 1`. I moduli inclusi fanno parte dell'addon. Per un'estensione distribuita separatamente, dichiara `## Dependencies: BadbUI` nel suo TOC e carica un file Lua come questo.

```lua
local api = BadbUI and BadbUI.API
if not api or api.version < 1 then return end

local plugin, err = api:RegisterPlugin({
    id = "MyExtension",
    title = "Mia estensione",
    version = "1.0.0",
    apiVersion = 1,
    module = {
        category = BadbUI.L["Strumenti"],
        defaults = { enabled = true, compact = false },
        options = {
            { type = "toggle", path = "compact", label = "Vista compatta" },
        },
        OnInitialize = function(self)
            self.store = api:GetStore("MyExtension")
            if self.store and not self.store.version then self.store.version = 1 end
        end,
    },
})
if not plugin then BadbUI.Logger:Warn("%s", err) end
```

- Scegli un ID univoco da 2 a 32 caratteri, con una lettera iniziale e poi lettere, numeri o underscore. L'esempio registra il modulo `Plugin_MyExtension`.
- Leggi e scrivi le preferenze del profilo con `self:Get(path)` e `self:Set(path, value)`. Per dati voluminosi, usa `API:GetStore(area)` da `OnInitialize` in poi. Versiona i dati e limita la dimensione. Lo store è condiviso dai profili e rimane fuori dall'export e dai backup di configurazione.
- Registra eventi con `self:On(event, callback)` e usa `OnDisable` per ripristinare ciò che il modulo modifica. Il ciclo di vita rimuove i listener del modulo quando viene spento. Il callback riceve il nome dell'evento come primo argomento.
- Usa i descrittori `page` e `commands` nel modulo per aggiungere una pagina al pannello e sottocomandi a `/badb`. Il pacchetto facoltativo `guides` aggiunge guide consultabili dentro il gioco.
- Usa `API:ListPlugins()` per elencare le estensioni e `API:GetModule(name)` per ottenere un modulo. `API:RegisterLocale(locale, translations)` registra le traduzioni.

I [widget di configurazione](configui.md), il [design system](UI.md), il [formato delle guide](guides.md) e il [contratto della suite](SUITE.md) documentano i descrittori e il comportamento sul client Forever.
