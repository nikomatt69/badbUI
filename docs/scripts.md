# Script (modulo `Scripts`)

Un solo addon, scriptabile: scrivi Lua dentro BadbUI, salvato nel profilo (quindi nell'export `BADB1:`).
Editor in gioco: `/badb script edit` o pagina **Principale** > Script. Codice: `Modules/Scripts.lua`, `Config/ScriptEditor.lua`.

## Trigger
| Trigger | Quando gira il codice |
|---|---|
| `manual` | solo con Esegui / `/badb script run <nome>` |
| `login` | all'avvio e dopo `/reload`; puo' registrare i suoi handler con `script.on` |
| `event` | a ogni occorrenza di un evento di gioco, con gli argomenti in `...` |
| `combatStart` / `combatEnd` | entrando / uscendo dal combattimento |
| `timer` | ogni N secondi (0.5 - 3600) |

## API dentro lo script
```lua
script.name                      -- nome dello script
script.data                      -- tabella salvata nel profilo (sopravvive a /reload)
script.on("PLAYER_LEVEL_UP", function(event, level) ... end)
script.after(3, function() ... end)       -- una volta
script.every(10, function() ... end)      -- max 5 attivi per script
script.log(...) / print(...)              -- messaggi in chat con il nome dello script
script.stop()
Badb                              -- tutta l'API di BadbUI: Modules, Theme, FrameManager, Events...
```
Esempio (script con trigger `login`):
```lua
script.on("PLAYER_LEVEL_UP", function(event, level)
    script.data.lastLevel = level
    print("Livello " .. level .. "!")
end)
```

## Comandi
`/badb script list|edit [nome]|run|stop|enable|disable|delete|export|import <...>` e `/badb lua <codice>` (una riga, non salvata).

## Limiti e sicurezza
* Le variabili globali create da uno script restano allo script (ambiente isolato); `loadstring`, `setfenv`, `SendChatMessage`,
  `SendMail`, `Logout`... e le SavedVariables non sono raggiungibili.
* **E' codice dell'utente con i suoi permessi**: la sandbox evita errori e usi accidentali, non e' un confine di sicurezza contro
  codice ostile. Per questo gli script **importati partono sempre spenti**: leggili prima di attivarli.
* Dopo 5 errori consecutivi uno script si spegne da solo (`ultimo errore` visibile nell'editor).
* Il client non permette di limitare il tempo di esecuzione: un ciclo infinito blocca il gioco, come in qualunque addon.
* Valgono le restrizioni di Forever: niente combat log, valori *secret* in combattimento, niente azioni su frame protetti in combattimento.
* Non verificato in gioco se Forever consente `loadstring` agli addon: in tal caso Compile risponde "questo client non permette di eseguire codice dinamico".

## Test
`tests/scripts_test.lua` (motore, sandbox, trigger, errori, import/export, archivio corrotto) e `tests/scripteditor_test.lua`.
