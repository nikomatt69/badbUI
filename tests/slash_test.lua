-- Test del router dei comandi slash.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end
local function noThrow(fn, msg)
    local ok, err = pcall(fn)
    if not ok then error((msg or "errore inatteso") .. ": " .. tostring(err), 2) end
end

local T = {}

local function newModule(name, info, enabled)
    local m = BadbUI.Modules:New(name, info)
    if enabled ~= false then BadbUI.Modules:SetEnabled(name, true) end
    return m
end

local function chatHas(Mock, text)
    for _, l in ipairs(Mock.chat) do if l:find(text, 1, true) then return true end end
    return false
end

local function countChat(Mock, text)
    local n = 0
    for _, l in ipairs(Mock.chat) do if l:find(text, 1, true) then n = n + 1 end end
    return n
end

T["EditDistance"] = function()
    local d = BadbUI.Slash.EditDistance
    eq(d("", ""), 0); eq(d("abc", ""), 3); eq(d("", "abc"), 3)
    eq(d("unlock", "unlock"), 0); eq(d("unlok", "unlock"), 1); eq(d("kitten", "sitting"), 3)
    eq(d("ab", "ba"), 2)
    eq(d(nil, "ab"), 2)
end

T["comandi base: config apre la finestra, con pagina"] = function()
    local UI = BadbUI.ConfigUI
    eq(BadbUI.Slash:Dispatch(""), true)
    truthy(UI.frame and UI.frame:IsShown(), "finestra aperta")
    UI:Close()
    BadbUI.Slash:Dispatch("config profili")
    eq(UI.current, "profiles")
    BadbUI.Slash:Dispatch("config")
    eq(UI.frame:IsShown(), true)
    SlashCmdList.BADBUI("CONFIG about")
    eq(UI.current, "about", "entry point registrato in SlashCmdList, case-insensitive")
    eq(SLASH_BADBUI1, "/badb"); eq(SLASH_BADBUI2, "/bui")
end

T["comandi base: profile, enable, disable, unlock, debug"] = function(Mock)
    local DB = BadbUI.DB
    BadbUI.Slash:Dispatch("profile")
    truthy(chatHas(Mock, "Profili: Default (attivo: Default)"))
    BadbUI.Slash:Dispatch("profile Nuovo")
    eq(DB:GetProfileName(), "Nuovo")
    BadbUI.Slash:Dispatch("disable Scaling")
    eq(BadbUI.Modules:Get("Hider").enabled, true)
    BadbUI.Slash:Dispatch("disable Hider")
    eq(BadbUI.Modules:Get("Hider").enabled, false)
    BadbUI.Slash:Dispatch("enable Hider")
    eq(BadbUI.Modules:Get("Hider").enabled, true)
    BadbUI.Slash:Dispatch("unlock")
    eq(BadbUI.FrameManager.unlocked, true)
    BadbUI.Slash:Dispatch("unlock")
    eq(BadbUI.FrameManager.unlocked, false)
    local lvl = BadbUI.Logger.level
    BadbUI.Slash:Dispatch("debug")
    truthy(BadbUI.Logger.level ~= lvl)
    BadbUI.Slash:Dispatch("debug")
    eq(BadbUI.Logger.level, lvl)
end

T["comandi base: export e log aprono la TextBox"] = function()
    local UI = BadbUI.ConfigUI
    BadbUI.Slash:Dispatch("export")
    truthy(UI.textBoxFrame.edit:GetText():find("BADB1", 1, true))
    BadbUI.Logger:Info("riga di test")
    BadbUI.Slash:Dispatch("log")
    truthy(UI.textBoxFrame.edit:GetText():find("riga di test", 1, true))
end

T["comandi base: setup e undo con guardie"] = function(Mock)
    local toggled, undone = 0, 0
    BadbUI.Wizard = { Toggle = function() toggled = toggled + 1 end }
    BadbUI.Presets = { Undo = function() undone = undone + 1 end }
    BadbUI.Slash:Dispatch("setup"); BadbUI.Slash:Dispatch("wizard")
    eq(toggled, 2)
    BadbUI.Slash:Dispatch("undo")
    eq(undone, 1)
    -- moduli mancanti: avviso, non errore
    BadbUI.Wizard, BadbUI.Presets = nil, nil
    eq(BadbUI.Slash:Dispatch("setup"), true)
    eq(BadbUI.Slash:Dispatch("undo"), true)
    truthy(chatHas(Mock, "non disponibil"))
end

T["help: elenca comandi base e di modulo"] = function(Mock)
    BadbUI.Modules:Get("Presets").commands = nil -- isola il modulo finto dal vero comando "preset"
    newModule("Pr", { commands = { preset = { help = "preset <chiave> | list", fn = function() end } } })
    BadbUI.Slash:Register("extra", function() end, "comando esterno")
    BadbUI.Slash:Dispatch("help")
    for _, c in ipairs({ "config", "unlock", "profile", "export", "enable", "disable", "setup", "undo", "debug", "log", "help" }) do
        truthy(chatHas(Mock, "/badb " .. c .. " "), "help include " .. c)
    end
    truthy(chatHas(Mock, "/badb preset - preset <chiave> | list"), "comando del modulo")
    truthy(chatHas(Mock, "/badb extra - comando esterno"), "comando registrato")
    -- comando sconosciuto senza suggerimento: mostra l'help
    local before = #Mock.chat
    local ok, why = BadbUI.Slash:Dispatch("qqqqqqqqqq")
    eq(ok, false); eq(why, "unknown")
    truthy(#Mock.chat > before + 5, "help mostrato")
end

T["moduli: comandi scoperti a ogni invocazione, args passati"] = function()
    BadbUI.Modules:Get("Presets").commands = nil -- isola il modulo finto dal vero comando "preset"
    local got
    BadbUI.Slash:Dispatch("preset prova") -- ancora inesistente
    newModule("Pr", { commands = { Preset = { help = "h", fn = function(args) got = args end } } })
    eq(BadbUI.Slash:Dispatch("preset  dps raid  "), true)
    eq(got, "dps raid", "argomenti ripuliti")
    eq(BadbUI.Slash:Dispatch("PRESET"), true)
    eq(got, "", "senza argomenti = stringa vuota")
    -- comando aggiunto a runtime a un modulo esistente
    local ran
    BadbUI.Modules:Get("Pr").commands.nuovo = { help = "n", fn = function() ran = true end }
    BadbUI.Slash:Dispatch("nuovo")
    truthy(ran, "scoperto senza ricaricare")
    local found
    for _, c in ipairs(BadbUI.Slash:List()) do if c.name == "nuovo" and c.module == "Pr" then found = true end end
    truthy(found, "List() include il comando con il modulo")
end

T["moduli: modulo disattivato segnalato nell'help ma eseguibile"] = function(Mock)
    local ran
    newModule("Off", { commands = { fuori = { help = "x", fn = function() ran = true end } } }, false)
    BadbUI.Slash:Dispatch("help")
    truthy(chatHas(Mock, "modulo disattivato"))
    BadbUI.Slash:Dispatch("fuori")
    truthy(ran)
end

T["moduli: voci non valide ignorate con un solo avviso"] = function(Mock)
    newModule("Bad", { commands = {
        senzafn = { help = "x" },
        stringa = "no",
        ["nome con spazi"] = { fn = function() end },
        buono = { fn = function() end },
        [5] = { fn = function() end },
    } })
    local map = BadbUI.Slash:Resolve()
    truthy(map.buono, "voce valida presente")
    eq(map.senzafn, nil); eq(map.stringa, nil); eq(map["nome con spazi"], nil); eq(map["5"], nil, "chiave non stringa ignorata")
    BadbUI.Slash:Resolve(); BadbUI.Slash:Resolve()
    eq(countChat(Mock, "'senzafn' del modulo Bad non valido"), 1, "avviso una volta sola")
    newModule("Strano", { commands = "non una tabella" })
    noThrow(function() BadbUI.Slash:Resolve() end)
end

T["collisioni: vince il primo modulo per ordine di caricamento, con warning"] = function(Mock)
    local who = {}
    newModule("Primo", { commands = { dup = { help = "uno", fn = function() who[#who + 1] = "primo" end } } })
    newModule("Secondo", { commands = { dup = { help = "due", fn = function() who[#who + 1] = "secondo" end } } })
    BadbUI.Slash:Dispatch("dup")
    eq(who[1], "primo"); eq(#who, 1)
    local _, _, collisions = BadbUI.Slash:Resolve()
    eq(#collisions, 1)
    eq(collisions[1].winner, "Primo"); eq(collisions[1].loser, "Secondo")
    truthy(chatHas(Mock, "Comando 'dup' duplicato: vince Primo, ignorato Secondo"))
    BadbUI.Slash:Dispatch("dup"); BadbUI.Slash:Dispatch("dup")
    eq(countChat(Mock, "duplicato"), 1, "warning una sola volta")
    eq(#BadbUI.Slash.lastCollisions, 1)
end

T["collisioni: un comando di modulo non puo' sostituire uno base"] = function()
    local hijack
    newModule("Cattivo", { commands = { config = { help = "x", fn = function() hijack = true end },
        help = { fn = function() hijack = true end } } })
    BadbUI.Slash:Dispatch("config")
    BadbUI.Slash:Dispatch("help")
    eq(hijack, nil, "vincono i comandi base")
    local _, _, c = BadbUI.Slash:Resolve()
    eq(#c, 2)
end

T["suggerimenti: intendevi X?"] = function(Mock)
    local S = BadbUI.Slash
    eq(S:Suggest("unlok"), "unlock")
    eq(S:Suggest("prfile"), "profile")
    eq(S:Suggest("PROFILE"), "profile", "case-insensitive")
    eq(S:Suggest("conf"), "config", "prefisso")
    eq(S:Suggest("dsiable"), "disable")
    eq(S:Suggest("zzzzzzzz"), nil)
    eq(S:Suggest(""), nil)
    eq(S:Suggest(nil), nil)
    newModule("Pr", { commands = { preset = { help = "p", fn = function() end } } })
    eq(S:Suggest("presset"), "preset", "include i comandi dei moduli")
    local ok, why, sug = S:Dispatch("unlok")
    eq(ok, false); eq(why, "unknown"); eq(sug, "unlock")
    truthy(chatHas(Mock, "Intendevi 'unlock'?"))
end

T["errori: un fn che lancia non rompe la chat"] = function(Mock)
    newModule("Rotto", { commands = { boom = { help = "x", fn = function() error("kaboom") end },
        nilindex = { help = "x", fn = function() local t; return t.x end } } })
    local ok, why, msg
    noThrow(function() ok, why, msg = BadbUI.Slash:Dispatch("boom") end)
    eq(ok, false); eq(why, "error")
    truthy(msg:find("kaboom", 1, true))
    truthy(chatHas(Mock, "Comando 'boom'"), "Logger:Error in chat")
    local found
    for _, l in ipairs(BadbUI.Logger.buffer) do if l:find("ERROR: Comando 'boom'", 1, true) then found = true end end
    truthy(found, "Logger:Error nel buffer")
    noThrow(function() SlashCmdList.BADBUI("nilindex") end)
    -- i comandi successivi funzionano
    eq(BadbUI.Slash:Dispatch("help"), true)
end

T["errori: comando base che lancia (modulo mancante) non rompe"] = function()
    local FM = BadbUI.FrameManager
    local orig = FM.SetUnlocked
    FM.SetUnlocked = function() error("sblocco rotto") end
    local ok, why = BadbUI.Slash:Dispatch("unlock")
    FM.SetUnlocked = orig
    eq(ok, false); eq(why, "error")
end

T["Register: validazione, sovrascrittura, riservati, Unregister"] = function()
    local S = BadbUI.Slash
    local got
    eq(S:Register("ciao", function(a) got = a end, "saluta"), true)
    S:Dispatch("ciao mondo")
    eq(got, "mondo")
    eq(S:Register("ciao", function(a) got = "v2:" .. a end), true, "ri-registrazione sostituisce")
    S:Dispatch("ciao x")
    eq(got, "v2:x")
    eq(#S.registeredOrder, 1, "nessun duplicato")
    local ok, err = S:Register("config", function() end)
    eq(ok, false); truthy(err, "nome base riservato")
    eq((S:Register("", function() end)), false)
    eq((S:Register("a b", function() end)), false)
    eq((S:Register(nil, function() end)), false)
    eq((S:Register("ok", "non fn")), false)
    eq((S:Register(5, function() end)), false)
    -- un comando registrato batte quello di un modulo omonimo
    local who
    newModule("M", { commands = { ciao = { fn = function() who = "modulo" end } } })
    S:Dispatch("ciao")
    eq(who, nil, "vince il registrato")
    eq(S:Unregister("ciao"), true)
    eq(S:Unregister("ciao"), false)
    S:Dispatch("ciao")
    eq(who, "modulo", "tolto il registrato, vince il modulo")
end

T["Dispatch: input strani"] = function()
    local S = BadbUI.Slash
    noThrow(function() S:Dispatch(nil) end)
    noThrow(function() S:Dispatch(42) end)
    noThrow(function() S:Dispatch("   ") end)
    noThrow(function() S:Dispatch(string.rep("x", 5000)) end)
    noThrow(function() S:Dispatch("profile " .. string.rep("%", 50)) end)
    noThrow(function() SlashCmdList.BADBUI(nil) end)
    eq(S:Dispatch("   "), true, "solo spazi = comando vuoto (config)")
end

return T
