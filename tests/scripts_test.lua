-- Test del motore di script (Modules/Scripts.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}
local function S() return BadbUI.Scripts end

T["modulo registrato e attivo, archivio vuoto"] = function()
    truthy(S(), "modulo mancante"); truthy(S().enabled)
    eq(#S():List(), 0)
end

T["Save: crea, valida i nomi, limiti di codice"] = function()
    truthy(S():Save("Mio script", { code = "x = 1" }))
    eq(#S():List(), 1)
    for _, bad in ipairs({ "", " a", "a ", "a/b", ("x"):rep(41), "a;b" }) do
        local ok = S():Save(bad, { code = "" })
        eq(ok, false, "nome accettato: '" .. bad .. "'")
    end
    local ok, err = S():Save("grande", { code = ("x"):rep(60001) })
    eq(ok, false); truthy(err:find("lungo"), "messaggio")
    eq(S():Save("t", { trigger = "inesistente" }), false, "trigger sconosciuto")
end

T["Run: esegue, le globali dello script non finiscono in _G"] = function()
    S():Save("a", { code = "mioGlobale = 42; ok = script.name" })
    truthy(S():Run("a"))
    eq(rawget(_G, "mioGlobale"), nil, "globale uscita dalla sandbox")
    eq(rawget(_G, "ok"), nil)
end

T["sandbox: funzioni vietate non disponibili, _G dello script non le riesporta"] = function()
    SendChatMessage = function() error("chiamata!") end
    S():Save("v", { code = "result = { loadstring, load, setfenv, getfenv, SendChatMessage, _G.SendChatMessage, BadbUIDB }" })
    local seen
    S():Save("v2", { code = "assert(loadstring == nil and SendChatMessage == nil and _G.SendChatMessage == nil and setfenv == nil and BadbUIDB == nil)" })
    truthy(S():Run("v2"), "funzioni vietate raggiungibili")
    eq(S():Record("v2").lastError, nil)
end

T["sandbox: legge il resto delle API (print, Badb, string)"] = function(Mock)
    S():Save("b", { code = "assert(Badb and Badb.Modules and string.format('%d', 3) == '3'); print('ciao', 1)" })
    truthy(S():Run("b"))
    eq(S():Record("b").lastError, nil)
    local found = false
    for _, l in ipairs(Mock.chat) do if l:find("ciao 1", 1, true) and l:find("script b", 1, true) then found = true end end
    truthy(found, "print dello script non in chat")
end

T["errori di sintassi e di esecuzione: registrati, niente eccezioni"] = function()
    S():Save("s", { code = "questo non e' lua (" })
    local ok, err = S():Run("s")
    eq(ok, false); truthy(err and #tostring(err) > 0)
    S():Save("e", { code = "error('boom')" })
    truthy(pcall(S().Run, S(), "e"), "l'errore e' uscito")
    truthy(S():Record("e").lastError:find("boom"), "errore non registrato")
end

T["script.on: handler per evento, isolato con pcall, rimosso allo stop"] = function(Mock)
    S():Save("h", { code = "count = 0; script.on('PLAYER_LEVEL_UP', function(ev, lvl) count = count + 1; script.data.last = lvl end)" })
    S():Run("h")
    Mock.Fire("PLAYER_LEVEL_UP", 12)
    Mock.Fire("PLAYER_LEVEL_UP", 13)
    eq(S():Record("h").data.last, 13, "dato persistente non aggiornato")
    S():Stop("h")
    Mock.Fire("PLAYER_LEVEL_UP", 14)
    eq(S():Record("h").data.last, 13, "handler ancora attivo dopo Stop")
end

T["un handler che lancia errori non ferma gli altri script"] = function(Mock)
    S():Save("bad", { code = "script.on('X_EVENT', function() error('no') end)" })
    S():Save("good", { code = "script.on('X_EVENT', function() script.data.n = (script.data.n or 0) + 1 end)" })
    S():Run("bad"); S():Run("good")
    truthy(pcall(Mock.Fire, "X_EVENT"))
    eq(S():Record("good").data.n, 1)
    truthy(S():Record("bad").lastError, "errore non registrato")
end

T["trigger event: il codice gira a ogni evento con gli argomenti"] = function(Mock)
    S():Save("t", { code = "local ev, a, b = ...; script.data.got = ev .. ':' .. a .. ':' .. b",
                    trigger = "event", event = "MY_EVENT", enabled = true })
    Mock.Fire("MY_EVENT", "uno", "due")
    eq(S():Record("t").data.got, "MY_EVENT:uno:due")
    eq(S():Record("t").runs, 1)
end

T["trigger combattimento"] = function(Mock)
    S():Save("cs", { code = "script.data.in_ = (script.data.in_ or 0) + 1", trigger = "combatStart", enabled = true })
    S():Save("ce", { code = "script.data.out = (script.data.out or 0) + 1", trigger = "combatEnd", enabled = true })
    Mock.Fire("PLAYER_REGEN_DISABLED"); Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(S():Record("cs").data.in_, 1); eq(S():Record("ce").data.out, 1)
end

T["trigger login: parte con StartAll, non se spento"] = function()
    S():Save("l1", { code = "script.data.ran = true", trigger = "login", enabled = true })
    S():Save("l2", { code = "script.data.ran = true", trigger = "login", enabled = false })
    S():StopAll(); S():Record("l1").data.ran = nil
    S():StartAll()
    eq(S():Record("l1").data.ran, true)
    eq(S():Record("l2").data.ran, nil, "script spento eseguito")
end

T["5 errori consecutivi: lo script si disattiva da solo"] = function(Mock)
    S():Save("x", { code = "error('sempre')", trigger = "event", event = "TICK_EVENT", enabled = true })
    for _ = 1, 5 do Mock.Fire("TICK_EVENT") end
    eq(S():Record("x").enabled, false, "non disattivato")
    eq(S().running.x, nil, "ancora in esecuzione")
    Mock.Fire("TICK_EVENT")
    eq(S():Record("x").errors, 5, "ha continuato a girare")
end

T["un successo azzera il contatore errori"] = function(Mock)
    S():Save("y", { code = "local _, fail = ...; if fail then error('x') end", trigger = "event", event = "FLAKY", enabled = true })
    for _ = 1, 4 do Mock.Fire("FLAKY", true) end
    Mock.Fire("FLAKY", false)
    eq(S():Record("y").errors, 0)
    eq(S():Record("y").enabled, true)
end

T["timer: limiti sui ticker, intervallo ripulito"] = function()
    local tickers = 0
    C_Timer.NewTicker = function() tickers = tickers + 1; return { Cancel = function() tickers = tickers - 1 end } end
    S():Save("tm", { code = "local n = 0; for i = 1, 10 do if script.every(1, function() end) then n = n + 1 end end; script.data.n = n" })
    S():Run("tm")
    eq(S():Record("tm").data.n, 5, "max 5 ticker per script")
    eq(tickers, 5)
    S():Stop("tm")
    eq(tickers, 0, "ticker non annullati allo stop")
    S():Save("iv", { code = "", trigger = "timer", interval = 0 / 0 })
    eq(S():Record("iv").interval, 5, "NaN non ripulito")
    S():Save("iv", { interval = 99999 }); eq(S():Record("iv").interval, 3600)
end

T["disattivare ferma lo script, eliminare lo rimuove"] = function(Mock)
    S():Save("d", { code = "script.on('E1', function() script.data.n = 1 end)", trigger = "login", enabled = true })
    truthy(S().running.d)
    S():SetScriptEnabled("d", false)
    eq(S().running.d, nil)
    truthy(S():Delete("d")); eq(S():Record("d"), nil)
    eq(S():Delete("d"), false)
end

T["export/import: andata e ritorno, importato sempre spento"] = function()
    S():Save("orig", { code = "print('x')", trigger = "event", event = "FOO", enabled = true })
    local str = S():Export("orig")
    truthy(str and str:find("^BADB1:"), "formato")
    local name = S():Import(str)
    eq(name, "orig 2", "nome non reso unico")
    local rec = S():Record(name)
    eq(rec.enabled, false, "importato attivo!")
    eq(rec.imported, true)
    eq(rec.code, "print('x')"); eq(rec.event, "FOO")
    eq(S().running[name], nil)
end

T["import: stringhe sbagliate rifiutate"] = function()
    local name, err = S():Import("non una stringa")
    eq(name, nil); truthy(err)
    local prof = BadbUI.Serializer:Export("profile", { a = 1 })
    name, err = S():Import(prof)
    eq(name, nil); truthy(err:find("tipo"), "tipo sbagliato accettato")
    eq(S():Import(nil), nil)
end

T["archivio corrotto: voci non valide ignorate, valide riparate"] = function()
    local st = BadbUI.DB:Get("Scripts", "scripts")
    st["buono"] = { code = "x=1", trigger = "boh", interval = "x", event = 5 }
    st["senza codice"] = { trigger = "login" }
    st["codice numero"] = { code = 5 }
    st["../evil"] = { code = "x=1" }
    st[42] = { code = "x=1" }
    local names = {}
    for _, s in ipairs(S():List()) do names[#names + 1] = s.name end
    eq(table.concat(names, ","), "buono")
    local r = S():Record("buono")
    eq(r.trigger, "manual"); eq(r.interval, 5); eq(r.event, "PLAYER_ENTERING_WORLD")
    BadbUI.DB:Set("Scripts", "scripts", "stringa")
    eq(#S():List(), 0, "archivio non-tabella non ripulito")
end

T["RunSnippet (/badb lua)"] = function()
    local ok, res = S():RunSnippet("return 6 * 7")
    truthy(ok); eq(res, 42)
    eq(S():RunSnippet("   "), false)
    eq(S():RunSnippet("if then"), false)
    eq((S():RunSnippet("error('x')")), false)
end

T["comandi slash: list/run/enable/disable/delete"] = function(Mock)
    S():Save("cmd", { code = "script.data.ran = true" })
    S():Command("run cmd")
    eq(S():Record("cmd").data.ran, true)
    S():Command("enable cmd"); eq(S():Record("cmd").enabled, true)
    S():Command("disable cmd"); eq(S():Record("cmd").enabled, false)
    S():Command("list")
    S():Command("delete cmd"); eq(S():Record("cmd"), nil)
    truthy(pcall(S().Command, S(), "boh"), "comando sconosciuto lancia")
    truthy(pcall(S().Command, S(), "run inesistente"))
    truthy(BadbUI.Modules:Get("Scripts").commands.script and BadbUI.Modules:Get("Scripts").commands.lua)
end

T["cambio profilo: gli script del vecchio profilo si fermano"] = function(Mock)
    S():Save("p", { code = "script.on('Q', function() end)", trigger = "login", enabled = true })
    truthy(S().running.p)
    S():OnProfileChanged()
    truthy(S().running.p, "script attivo non riavviato nel profilo")
    S():Record("p").enabled = false
    S():OnProfileChanged()
    eq(S().running.p, nil)
end

T["disattivare il modulo ferma tutto"] = function()
    S():Save("m", { code = "", trigger = "login", enabled = true })
    BadbUI.Modules:SetEnabled("Scripts", false)
    eq(next(S().running), nil)
end

T["client senza loadstring: errore chiaro, nessuna eccezione"] = function()
    local old = loadstring
    loadstring = nil
    local ok, err = S():Compile("x=1", "t")
    loadstring = old
    eq(ok, nil); truthy(err:find("dinamico"))
end

return T
