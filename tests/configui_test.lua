-- Test della shell: ConfigUI v2 (indice pagine, ricerca, servizi) e widget.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end
local function noThrow(fn, msg)
    local ok, err = pcall(fn)
    if not ok then error((msg or "errore inatteso") .. ": " .. tostring(err), 2) end
end

local T = {}

local function newModule(name, info)
    local m = BadbUI.Modules:New(name, info)
    BadbUI.Modules:SetEnabled(name, true)
    return m
end

local function keysOf(pages)
    local out = {}
    for _, p in ipairs(pages) do out[#out + 1] = p.key end
    return out
end

local function indexOf(list, key)
    for i, k in ipairs(list) do if k == key then return i end end
end

local function logHas(text)
    for _, l in ipairs(BadbUI.Logger.buffer) do if l:find(text, 1, true) then return true end end
    return false
end

local function click(frame, ...) frame.__scripts.OnClick(frame, ...) end

---------------------------------------------------------------------------
-- Indice pagine / ordinamento / risoluzione
---------------------------------------------------------------------------
T["indice: pagine core sempre presenti e ordinate"] = function()
    local keys = keysOf(BadbUI.ConfigUI:CollectPages())
    for _, k in ipairs({ "overview", "profiles", "modules", "frames", "about" }) do
        truthy(indexOf(keys, k), "manca la pagina core " .. k)
    end
    truthy(indexOf(keys, "overview") < indexOf(keys, "profiles"), "Panoramica prima di Profili")
    truthy(indexOf(keys, "profiles") < indexOf(keys, "modules"), "Profili prima di Moduli")
    truthy(indexOf(keys, "modules") < indexOf(keys, "about"), "Informazioni in fondo a Gestione")
end

T["indice: moduli con page ordinati per categoria e order"] = function()
    local UI = BadbUI.ConfigUI
    newModule("FakeA", { title = "Alfa", page = { title = "Pagina Alfa", order = 30, category = "Strumenti", build = function() return 50 end } })
    newModule("FakeB", { title = "Beta", page = { order = 10, category = "Strumenti", build = function() return 50 end } })
    newModule("FakeC", { title = "Gamma", page = { order = 5, category = "Contenuti", build = function() return 50 end } })
    newModule("FakeD", { title = "Delta", page = { order = 1, category = "Gestione", build = function() return 50 end } })
    newModule("FakeE", { title = "Nopage" })
    newModule("FakeF", { title = "Strana", page = { order = 1, category = "Zeta", build = function() return 50 end } })
    newModule("FakeG", { title = "Rotta", page = "non una tabella" })
    local keys = keysOf(UI:CollectPages())
    truthy(indexOf(keys, "mod:FakeB") < indexOf(keys, "mod:FakeA"), "order 10 prima di 30")
    truthy(indexOf(keys, "mod:FakeA") < indexOf(keys, "mod:FakeC"), "Strumenti prima di Contenuti")
    truthy(indexOf(keys, "mod:FakeD") < indexOf(keys, "modules"), "order 1 in Gestione prima di Moduli (900)")
    truthy(indexOf(keys, "mod:FakeC") < indexOf(keys, "mod:FakeF"), "categoria sconosciuta dopo quelle note")
    eq(indexOf(keys, "mod:FakeE"), nil, "modulo senza page non in sidebar")
    eq(indexOf(keys, "mod:FakeG"), nil, "page non tabella ignorata")
    local rec = UI:FindPage("mod:FakeB")
    eq(rec.title, "Beta", "titolo di ripiego = titolo modulo")
    eq(UI:FindPage("mod:FakeA").title, "Pagina Alfa")
    eq(UI:FindPage("nonesiste"), nil)
    eq(UI:FindPage(42), nil)
end

T["indice: categoria/order mancanti hanno valori di ripiego"] = function()
    local UI = BadbUI.ConfigUI
    newModule("FakeA", { page = { build = function() return 10 end } })
    local rec = UI:FindPage("mod:FakeA")
    eq(rec.category, "Strumenti")
    eq(rec.order, 100)
    eq(rec.title, "FakeA")
end

T["sidebar: gruppi nell'ordine Gestione, Interfaccia, Strumenti, Contenuti"] = function()
    local UI = BadbUI.ConfigUI
    newModule("FakeA", { page = { category = "Contenuti", build = function() return 10 end } })
    newModule("FakeB", { page = { category = "Strumenti", build = function() return 10 end } })
    local cats = {}
    for _, g in ipairs(UI:GetSidebarModel()) do cats[#cats + 1] = g.category end
    eq(table.concat(cats, ","), "Gestione,Interfaccia,Strumenti,Contenuti")
end

T["risoluzione: chiave, nome modulo, titolo"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Guides", { title = "Guide", page = { title = "Libreria guide", build = function() return 10 end } })
    eq(UI:ResolveKey("profiles"), "profiles")
    eq(UI:ResolveKey("mod:Guides"), "mod:Guides")
    eq(UI:ResolveKey("Guides"), "mod:Guides")
    eq(UI:ResolveKey("guides"), "mod:Guides", "case-insensitive sul nome modulo")
    eq(UI:ResolveKey("LIBRERIA GUIDE"), "mod:Guides", "titolo pagina")
    eq(UI:ResolveKey("profili"), "profiles")
    eq(UI:ResolveKey("xyz"), nil)
    eq(UI:ResolveKey(""), nil)
    eq(UI:ResolveKey(nil), nil)
    eq(UI:ResolveKey({}), nil)
end

T["RegisterPage: pagine non di modulo"] = function()
    local UI = BadbUI.ConfigUI
    local ok = UI:RegisterPage("extra", { title = "Extra", category = "Contenuti", order = 1, build = function() return 20 end })
    eq(ok, true)
    truthy(indexOf(keysOf(UI:CollectPages()), "extra"), "pagina registrata in indice")
    local bad, err = UI:RegisterPage("profiles", { build = function() end })
    eq(bad, false); truthy(err, "chiave core riservata")
    eq((UI:RegisterPage("mod:X", { build = function() end })), false, "prefisso mod: riservato")
    eq((UI:RegisterPage("y", {})), false, "serve build")
    eq((UI:RegisterPage("", { build = function() end })), false)
    eq((UI:RegisterPage(nil, nil)), false)
    -- ri-registrare la stessa chiave la sostituisce senza duplicarla
    UI:RegisterPage("extra", { title = "Extra2", build = function() return 20 end })
    local n = 0
    for _, p in ipairs(UI:CollectPages()) do if p.key == "extra" then n = n + 1 end end
    eq(n, 1)
    eq(UI:FindPage("extra").title, "Extra2")
    eq(UI:UnregisterPage("extra"), true)
    eq(UI:FindPage("extra"), nil)
    eq(UI:UnregisterPage("extra"), false)
end

T["pagina letta a runtime: modulo aggiunto dopo la creazione della finestra"] = function()
    local UI = BadbUI.ConfigUI
    UI:Open()
    newModule("Tardivo", { page = { title = "Tardiva", build = function() return 10 end } })
    UI:RebuildSidebar()
    local found
    for _, b in ipairs(UI.sbButtons) do if b:IsShown() and b.key == "mod:Tardivo" then found = true end end
    truthy(found, "il pulsante della nuova pagina compare nella sidebar")
end

---------------------------------------------------------------------------
-- Costruzione pagine, errori isolati
---------------------------------------------------------------------------
T["build: riceve ctx e l'altezza viene usata"] = function()
    local UI = BadbUI.ConfigUI
    local seen
    newModule("FakeA", { page = { title = "A", build = function(parent, ctx) seen = ctx; return 321 end } })
    eq(UI:Open("mod:FakeA"), true)
    truthy(seen and seen.UI == UI and seen.W == BadbUI.Widgets, "ctx.UI e ctx.W")
    eq(UI.current, "mod:FakeA")
    eq(UI.pageFrames["mod:FakeA"].height, 321)
    eq(UI.content.__scripts ~= nil, true)
end

T["errore in build: isolato, box errore, Logger:Error"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Bad", { page = { title = "Rotta", build = function() error("boom nel build") end } })
    newModule("Good", { page = { title = "Buona", build = function() return 40 end } })
    noThrow(function() UI:Open("mod:Bad") end, "la shell non deve rompersi")
    local entry = UI.pageFrames["mod:Bad"]
    truthy(entry.failed, "pagina marcata fallita")
    truthy(entry.buildError:find("boom nel build", 1, true), "messaggio conservato")
    truthy(entry.errorFrame and entry.errorFrame.message:GetText():find("boom nel build", 1, true), "il box mostra il messaggio")
    truthy(logHas("ERROR: Pagina 'Rotta'"), "Logger:Error chiamato")
    noThrow(function() UI:SelectPage("mod:Good") end)
    eq(UI.current, "mod:Good")
    eq(UI.pageFrames["mod:Good"].failed, nil)
    noThrow(function() UI:Open("mod:Bad") end, "riaprire la pagina fallita")
end

T["build che ritorna valori strani non rompe nulla"] = function()
    local UI = BadbUI.ConfigUI
    newModule("A1", { page = { build = function() return "abc" end } })
    newModule("A2", { page = { build = function() return nil end } })
    newModule("A3", { page = { build = function() return -50 end } })
    newModule("A4", { page = { build = function() return 1e12 end } })
    for _, n in ipairs({ "A1", "A2", "A3", "A4" }) do
        noThrow(function() UI:Open("mod:" .. n) end, n)
        local h = UI.pageFrames["mod:" .. n].height
        truthy(h >= 40 and h <= 20000, "altezza clampata per " .. n .. ": " .. tostring(h))
    end
end

T["page senza build: opzioni generate dal descrittore"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Opt", { title = "Opzioni", defaults = { x = true }, options = { { type = "toggle", path = "x", label = "Uno" } },
        page = { title = "Pagina Opt" } })
    noThrow(function() UI:Open("mod:Opt") end)
    eq(UI.pageFrames["mod:Opt"].failed, nil)
end

T["errore in refresh: segnalato senza rompere la shell"] = function()
    local UI = BadbUI.ConfigUI
    local calls = 0
    newModule("R", { page = { title = "R", build = function() return 40 end,
        refresh = function() calls = calls + 1; error("refresh rotto") end } })
    noThrow(function() UI:Open("mod:R") end)
    eq(calls, 1, "refresh chiamato all'apertura")
    local entry = UI.pageFrames["mod:R"]
    truthy(entry.lastErr:find("refresh rotto", 1, true), "errore registrato")
    truthy(UI.refreshError:GetText():find("refresh rotto", 1, true), "banner errore visibile")
    truthy(logHas("refresh rotto"), "Logger:Error")
    noThrow(function() UI:Refresh() end)
    eq(calls, 2, "refresh richiamato da UI:Refresh")
    -- il log non viene inondato dallo stesso errore
    local before = #BadbUI.Logger.buffer
    UI:Refresh()
    eq(#BadbUI.Logger.buffer, before, "errore identico non ripetuto nel log")
end

T["refresh: chiamato su cambio profilo e a opzione cambiata (coalescata)"] = function()
    local UI = BadbUI.ConfigUI
    local calls = 0
    newModule("R", { page = { title = "R", build = function() return 40 end, refresh = function() calls = calls + 1 end } })
    UI:Open("mod:R")
    local base = calls
    BadbUI.Events:Fire("BADB_PROFILE_CHANGED", "Default")
    eq(calls, base + 1)
    UI.frame:Show()
    BadbUI.Events:Fire("BADB_OPTION_CHANGED", "R", "x", 1)
    BadbUI.Events:Fire("BADB_OPTION_CHANGED", "R", "x", 2)
    eq(calls, base + 1, "non ancora: coalescato")
    UI.refreshDriver.__scripts.OnUpdate(UI.refreshDriver, 0.016)
    eq(calls, base + 2, "un solo refresh per piu' eventi")
end

T["modulo disattivato: pagina con avviso, build non eseguito, poi riattivato"] = function()
    local UI = BadbUI.ConfigUI
    local built = 0
    newModule("Off", { page = { title = "Off", build = function() built = built + 1; return 40 end } })
    BadbUI.Modules:SetEnabled("Off", false)
    eq(UI:FindPage("mod:Off").enabled, false)
    UI:Open("mod:Off")
    eq(built, 0, "pagina non costruita se il modulo e' disattivo")
    BadbUI.Modules:SetEnabled("Off", true)
    UI:SelectPage("mod:Off")
    eq(built, 1, "costruita dopo l'attivazione")
    eq(UI.pageFrames["mod:Off"].failed, nil)
end

T["pagine core: tutte costruibili senza errori"] = function()
    local UI = BadbUI.ConfigUI
    for _, k in ipairs({ "overview", "profiles", "modules", "frames", "about" }) do
        eq(UI:Open(k), true, k)
        local e = UI.pageFrames[k]
        truthy(e, "pagina " .. k .. " costruita")
        eq(e.failed, nil, "pagina core " .. k .. " fallita: " .. tostring(e.buildError))
        eq(e.lastErr, nil, "refresh di " .. k .. ": " .. tostring(e.lastErr))
    end
end

T["Open: stato salvato e ripristinato"] = function()
    local UI = BadbUI.ConfigUI
    BadbUI.DB.sv.global.ui = { page = "profiles", scale = 1.2 }
    UI:Open()
    eq(UI.current, "profiles", "riapre l'ultima pagina")
    eq(BadbUI.DB.sv.global.ui.page, "profiles")
    UI:SelectPage("about")
    eq(BadbUI.DB.sv.global.ui.page, "about")
    eq(UI:SetScale(1.234), 1.25, "scala arrotondata a 0.05")
    eq(BadbUI.DB.sv.global.ui.scale, 1.25)
    eq(UI:SetScale(99), 1.5, "scala limitata")
    eq(UI:SetScale(0), 0.6)
    UI:ResetWindow()
    eq(BadbUI.DB.sv.global.ui.scale, nil)
end

T["finestra: nome globale, ESC, Settings"] = function()
    local UI = BadbUI.ConfigUI
    eq(UI.frame, nil, "costruzione lazy: nessuna finestra prima di Open")
    UI:Open()
    truthy(BadbUIConfigFrame == UI.frame, "BadbUIConfigFrame esiste")
    local found
    for _, n in ipairs(UISpecialFrames) do if n == "BadbUIConfigFrame" then found = true end end
    truthy(found, "ESC chiude la finestra (UISpecialFrames)")
    local n = #UISpecialFrames
    UI:Open(); UI:Open()
    eq(#UISpecialFrames, n, "nessun duplicato in UISpecialFrames")
    truthy(UI.panel and UI.panel.openButton, "pannello leggero in Settings con pulsante")
    UI:Close()
    eq(UI.frame:IsShown(), false)
    click(UI.panel.openButton)
    eq(UI.frame:IsShown(), true, "il pulsante apre la finestra")
    UI:Toggle()
    eq(UI.frame:IsShown(), false)
end

T["Open con chiave sconosciuta o argomenti strani"] = function()
    local UI = BadbUI.ConfigUI
    noThrow(function() UI:Open("non-esiste") end)
    eq(UI.current, "overview")
    noThrow(function() UI:Open(42) end)
    noThrow(function() UI:Open({}) end)
    noThrow(function() UI:Refresh() end)
end

T["UI:Refresh senza finestra costruita e firme storiche"] = function()
    local UI = BadbUI.ConfigUI
    noThrow(function() UI:Refresh() end)
    eq(type(UI.TextBox), "function")
    eq(type(UI.Open), "function")
    eq(type(UI.Refresh), "function")
    eq(type(UI.Confirm), "function")
    eq(type(UI.Toast), "function")
    eq(type(UI.OpenPage), "function")
    eq(type(UI.RegisterPage), "function")
end

T["OpenPage: modulo con pagina, senza pagina, inesistente"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Pg", { page = { title = "Pg", build = function() return 30 end } })
    newModule("NoPg", { title = "Senza pagina", options = { { type = "toggle", path = "enabled", label = "Opzione" } } })
    eq(UI:OpenPage("Pg"), true)
    eq(UI.current, "mod:Pg")
    eq(UI:OpenPage("NoPg"), true)
    eq(UI.current, "modules", "senza pagina apre Moduli")
    truthy(UI.moduleSections.NoPg.expanded, "e ne espande la sezione")
    eq(UI:OpenPage("Inesistente"), false)
    eq(UI:OpenPage(nil), false)
end

---------------------------------------------------------------------------
-- Ricerca
---------------------------------------------------------------------------
T["ricerca: titoli pagina, titoli modulo e label opzioni (case-insensitive)"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Zeta", { title = "Zeta Mod", options = {
        { type = "toggle", path = "enabled", label = "Mostra Xilofono grandi" },
        { type = "header", label = "Sezione Xilofono" },
        { type = "toggle", path = "enabled", label = "Altro" },
        { type = "separator" },
        "garbage", 42,
    } })
    newModule("Pgm", { title = "Modulo con pagina", page = { title = "Preset ruolo", build = function() return 10 end } })
    local r = UI:Search("XILOFONO")
    eq(#r, 2, "due label con 'xilofono'")
    eq(r[1].kind, "option"); eq(r[1].key, "modules"); eq(r[1].module, "Zeta")
    local p = UI:Search("preset")
    eq(p[1].kind, "page"); eq(p[1].key, "mod:Pgm")
    local prof = UI:Search("profil")
    eq(prof[1].key, "profiles", "pagina core per titolo")
    local m = UI:Search("zeta mod")
    eq(m[1].kind, "module"); eq(m[1].key, "modules", "modulo senza pagina porta a Moduli")
    eq(m[1].module, "Zeta")
    local mp = UI:Search("modulo con")
    eq(mp[1].key, "mod:Pgm", "modulo con pagina porta alla sua pagina")
    -- parole chiave delle pagine core
    truthy(#UI:Search("sblocca") >= 1, "keyword pagina Frame")
end

T["ricerca: query vuote o strane, limite risultati"] = function()
    local UI = BadbUI.ConfigUI
    eq(#UI:Search(""), 0)
    eq(#UI:Search("   "), 0)
    eq(#UI:Search(nil), 0)
    eq(#UI:Search(42), 0)
    eq(#UI:Search("%[(.*"), 0, "nessun pattern Lua: ricerca letterale")
    local opts = {}
    for i = 1, 100 do opts[#opts + 1] = { type = "toggle", path = "enabled", label = "Opzione " .. i } end
    newModule("Many", { options = opts })
    eq(#UI:Search("opzione"), 30, "max 30 risultati")
end

T["ricerca: UI (box, risultati cliccabili, apertura pagina)"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Zeta", { title = "Zeta Mod", options = { { type = "toggle", path = "enabled", label = "Mostra Xilofono" } } })
    UI:Open()
    UI.searchBox:SetText("xilofono")
    UI.searchBox.__scripts.OnTextChanged(UI.searchBox, true)
    eq(UI.searchPanel:IsShown(), true)
    local row = UI.searchRows[1]
    truthy(row and row:IsShown(), "riga risultato")
    truthy(row.text:GetText():find("Mostra Xilofono", 1, true))
    click(row)
    eq(UI.current, "modules", "il click apre la pagina")
    truthy(UI.moduleSections.Zeta.expanded, "e la sezione del modulo")
    eq(UI.searchPanel:IsShown(), false, "pannello chiuso")
    eq(UI.searchBox:GetText(), "")
    -- nessun risultato nasconde il pannello
    UI.searchBox:SetText("qqqqqqq")
    UI.searchBox.__scripts.OnTextChanged(UI.searchBox, true)
    eq(UI.searchPanel:IsShown(), false)
    -- Invio apre il primo risultato
    UI.searchBox:SetText("profili")
    UI.searchBox.__scripts.OnTextChanged(UI.searchBox, true)
    UI.searchBox.__scripts.OnEnterPressed(UI.searchBox)
    eq(UI.current, "profiles")
    UI.searchBox.__scripts.OnEscapePressed(UI.searchBox)
end

---------------------------------------------------------------------------
-- Profili
---------------------------------------------------------------------------
T["profili: rinomina (attivo), copia, doppioni, import"] = function()
    local UI, DB = BadbUI.ConfigUI, BadbUI.DB
    DB:CopyProfile("Default", "Altro")
    eq(UI:CopyProfile("Default", "Altro"), false, "nome gia' esistente")
    eq(UI:CopyProfile("Default", "  "), false, "nome vuoto")
    eq(UI:CopyProfile("Default", "Copia"), true)
    DB:SetSpecProfile(1, "Default")
    local ok = UI:RenameProfile("Default", "Principale")
    eq(ok, true)
    eq(DB:GetProfileName(), "Principale", "il profilo attivo segue il rename")
    eq(DB.sv.profiles.Default, nil, "vecchio nome eliminato")
    truthy(DB.sv.profiles.Principale, "nuovo nome presente")
    eq(DB.sv.specProfiles[DB.char][1], "Principale", "profilo per spec aggiornato")
    eq(DB.sv.profileKeys[DB.char], "Principale")
    eq((UI:RenameProfile("Principale", "Altro")), false, "collisione")
    eq((UI:RenameProfile("Principale", "")), false)
    eq((UI:RenameProfile("Inesistente", "X")), false)
    -- import: export + import crea un profilo con nome univoco
    local str = DB:ExportProfile()
    local a, _, n1 = UI:ImportProfileString(str)
    local b, _, n2 = UI:ImportProfileString(str)
    eq(a, true); eq(b, true)
    truthy(n1 ~= n2, "nomi univoci anche con data identica")
    eq((UI:ImportProfileString("spazzatura")), false, "stringa non valida")
end

T["profili: pagina costruita con azioni sulla lista"] = function()
    local UI, DB = BadbUI.ConfigUI, BadbUI.DB
    DB:CopyProfile("Default", "Secondario")
    UI:Open("profiles")
    eq(UI.pageFrames.profiles.failed, nil)
end

---------------------------------------------------------------------------
-- Avvisi / azioni recenti
---------------------------------------------------------------------------
T["avvisi: frame sbloccati e combattimento"] = function(Mock)
    local UI = BadbUI.ConfigUI
    local function has(sub)
        for _, w in ipairs(UI:GetWarnings()) do if w.text:find(sub, 1, true) then return w end end
    end
    eq(has("sbloccati"), nil)
    BadbUI.FrameManager:SetUnlocked(true)
    local w = has("sbloccati")
    truthy(w and w.action, "avviso con azione")
    w.action()
    eq(BadbUI.FrameManager.unlocked, false)
    Mock.combat = true
    truthy(has("In combattimento"))
    Mock.combat = false
    BadbUI.Logger:Error("qualcosa")
    truthy(has("errori nel log"))
end

T["ultime azioni: eventi registrati"] = function()
    local UI = BadbUI.ConfigUI
    BadbUI.Events:Fire("BADB_PROFILE_CHANGED", "Prova")
    truthy(UI.actions[1].text:find("Prova", 1, true))
    BadbUI.Events:Fire("BADB_PRESET_APPLIED", "dps-raid", "merge")
    truthy(UI.actions[1].text:find("dps-raid", 1, true))
    for i = 1, 40 do UI:RecordAction("a" .. i) end
    eq(#UI.actions, 20, "buffer limitato")
end

---------------------------------------------------------------------------
-- Frame page
---------------------------------------------------------------------------
T["pagina Frame: costruita con frame registrati"] = function()
    local UI = BadbUI.ConfigUI
    local f = CreateFrame("Frame", "TestScalable")
    BadbUI.FrameManager:Register("TestScalable", { frame = "TestScalable", title = "Prova", category = "Test", scalable = true, hideable = true })
    BadbUI.FrameManager:Register("TestBroken", { frame = "NonEsiste", category = "Test", movable = false })
    noThrow(function() UI:Open("frames") end)
    eq(UI.pageFrames.frames.failed, nil, tostring(UI.pageFrames.frames.buildError))
    noThrow(function() UI:Refresh() end)
    eq(UI.pageFrames.frames.lastErr, nil)
end

---------------------------------------------------------------------------
-- Servizi: TextBox / Confirm / Toast
---------------------------------------------------------------------------
T["TextBox: firma storica (. e :), accept, chiusura"] = function()
    local UI = BadbUI.ConfigUI
    UI.TextBox("Titolo", "contenuto")
    local f = UI.textBoxFrame
    truthy(f, "frame creato")
    eq(f.edit:GetText(), "contenuto")
    eq(f.title:GetText(), "Titolo")
    eq(f.ok:GetText(), "Chiudi")
    eq(f:IsShown(), true)
    local got
    UI:TextBox("Importa", "", function(txt) got = txt end)
    eq(f.ok:GetText(), "Importa")
    f.edit:SetText("stringa incollata")
    click(f.ok)
    eq(got, "stringa incollata")
    eq(f:IsShown(), false)
    noThrow(function() UI.TextBox("X", nil) end, "testo nil")
    noThrow(function() UI.TextBox(nil, 42) end, "titolo nil")
    -- errore in onAccept isolato
    UI.TextBox("E", "", function() error("accept rotto") end)
    noThrow(function() click(f.ok) end)
    truthy(logHas("accept rotto"))
    -- testo enorme limitato
    UI.TextBox("Grande", string.rep("x", 600000))
    eq(#f.edit:GetText(), 500000)
    local found
    for _, n in ipairs(UISpecialFrames) do if n == "BadbUITextBox" then found = true end end
    truthy(found, "ESC chiude la TextBox")
end

T["TextBox: usata dai comandi export e log"] = function()
    local UI = BadbUI.ConfigUI
    BadbUI.Slash:Dispatch("export")
    truthy(UI.textBoxFrame.edit:GetText():find("BADB1", 1, true), "stringa di export nella TextBox")
end

T["Confirm: si, no, ESC, coda ed errori"] = function()
    local UI = BadbUI.ConfigUI
    local yes, no = 0, 0
    eq(UI:Confirm("Sicuro?", function() yes = yes + 1 end, function() no = no + 1 end), true)
    local f = UI.confirmFrame
    eq(f.text:GetText(), "Sicuro?")
    eq(f:IsShown(), true)
    click(f.yes)
    eq(yes, 1); eq(no, 0); eq(f:IsShown(), false)
    UI:Confirm("Ancora?", function() yes = yes + 1 end, function() no = no + 1 end)
    click(f.no)
    eq(yes, 1); eq(no, 1)
    -- ESC (il frame viene nascosto da UISpecialFrames) = No
    UI:Confirm("Esc?", function() yes = yes + 1 end, function() no = no + 1 end)
    f.__scripts.OnHide(f)
    eq(no, 2); eq(yes, 1)
    -- senza onNo
    UI:Confirm("Solo si", function() yes = yes + 1 end)
    noThrow(function() click(f.no) end)
    -- coda: la seconda conferma compare dopo la prima
    UI.Confirm("Prima", function() yes = yes + 10 end)
    UI.Confirm("Seconda", function() yes = yes + 100 end)
    eq(f.text:GetText(), "Prima")
    click(f.yes)
    eq(f.text:GetText(), "Seconda")
    eq(f:IsShown(), true)
    click(f.yes)
    eq(yes, 1 + 10 + 100)
    -- callback che lancia: isolato, coda continua
    UI:Confirm("Rotta", function() error("yes rotto") end)
    noThrow(function() click(f.yes) end)
    truthy(logHas("yes rotto"))
    noThrow(function() UI:Confirm(nil, nil) end)
    click(f.no)
end

T["Toast: max 3 visibili, coda, scadenza, dedup"] = function()
    local UI = BadbUI.ConfigUI
    for i = 1, 5 do UI:Toast("messaggio " .. i, "ok") end
    eq(UI.toasts:Count(), 3, "max 3 visibili")
    eq(#UI.toasts.pending, 2, "gli altri in coda")
    eq(UI.toastFrames[1].text:GetText(), "messaggio 1")
    eq(UI.toastFrames[3]:IsShown(), true)
    local drv = UI.toastDriver
    drv.__scripts.OnUpdate(drv, 2)
    eq(UI.toasts:Count(), 3, "non ancora scaduti")
    drv.__scripts.OnUpdate(drv, 2.5)
    -- scaduti i primi 3: entrano i due in attesa
    eq(UI.toasts:Count(), 2)
    eq(UI.toastFrames[1].text:GetText(), "messaggio 4")
    eq(UI.toastFrames[3]:IsShown(), false, "frame in eccesso nascosto")
    drv.__scripts.OnUpdate(drv, 5)
    eq(UI.toasts:Count(), 0)
    eq(drv.__scripts.OnUpdate, nil, "driver spento a coda vuota")
    -- dedup: stesso testo = niente doppioni
    UI:Toast("uguale"); UI:Toast("uguale")
    eq(UI.toasts:Count(), 1)
    -- livello sconosciuto, testi strani
    noThrow(function() UI:Toast("x", "boh") end)
    noThrow(function() UI:Toast(nil) end)
    noThrow(function() UI:Toast(12345, "error") end)
    noThrow(function() UI.Toast("senza due punti") end)
    noThrow(function() UI:Toast(string.rep("z", 1000)) end)
    for _, it in ipairs(UI.toasts.items) do truthy(#it.text <= 200, "testo troncato") end
end

T["coda toast pura"] = function()
    local q = BadbUI.ConfigUI.NewToastQueue(2, 1)
    q:Push("a"); q:Push("b"); q:Push("c")
    eq(q:Count(), 2); eq(#q.pending, 1)
    eq(q:Push("", "info"), nil, "testo vuoto ignorato")
    eq(q.items[1].level, "info")
    eq(q:Tick(0.5), false)
    eq(q:Tick(0.6), true)
    eq(q.items[1].text, "c")
    for i = 1, 50 do q:Push("p" .. i) end
    truthy(#q.pending <= 20, "pending limitata")
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------
T["widget: NormalizeChoices"] = function()
    local W = BadbUI.Widgets
    local c = W.NormalizeChoices({ "a", "b" })
    eq(#c, 2); eq(c[1].value, "a"); eq(c[1].label, "a")
    c = W.NormalizeChoices({ { value = 1, label = "Uno" }, { 2, "Due" }, { value = 3, text = "Tre" } })
    eq(c[1].label, "Uno"); eq(c[2].value, 2); eq(c[2].label, "Due"); eq(c[3].label, "Tre", "formato select storico")
    c = W.NormalizeChoices({ z = "Zeta", a = "Alfa" })
    eq(c[1].value, "a", "mappa ordinata per etichetta"); eq(c[2].value, "z")
    eq(#W.NormalizeChoices(function() return { "x" } end), 1)
    eq(#W.NormalizeChoices(function() error("no") end), 0)
    eq(#W.NormalizeChoices(nil), 0)
    eq(#W.NormalizeChoices(42), 0)
    eq(#W.NormalizeChoices({ {}, "ok" }), 1, "voci senza valore scartate")
end

T["widget: ParseColor"] = function()
    local W = BadbUI.Widgets
    local r, g, b, a = W.ParseColor({ 0.5, 0.25, 1 })
    eq(r, 0.5); eq(g, 0.25); eq(b, 1); eq(a, 1)
    r, g, b, a = W.ParseColor({ r = 1, g = 0, b = 0, a = 0.5 })
    eq(r, 1); eq(a, 0.5)
    r, g, b = W.ParseColor("ff0000")
    eq(r, 1); eq(g, 0)
    r, g, b, a = W.ParseColor("#80ff0000")
    eq(a > 0.49 and a < 0.51, true); eq(r, 1)
    r, g, b, a = W.ParseColor("zzz")
    eq(r, 1); eq(g, 1); eq(b, 1); eq(a, 1)
    r = W.ParseColor(nil); eq(r, 1)
    r = W.ParseColor({ 5, -3, "x" }); eq(r, 1)
    r = W.ParseColor({ r = 0 / 0, g = 0, b = 0 }); eq(r, 1, "NaN scartato")
end

T["widget: Validate"] = function()
    local W = BadbUI.Widgets
    eq((W.Validate(nil)), false)
    eq((W.Validate(42)), false)
    eq((W.Validate({})), false, "type mancante")
    eq((W.Validate({ type = "toggle", label = "x" })), false, "senza path/get")
    eq((W.Validate({ type = "toggle", label = "x", path = "a" }, { Get = function() end })), true, "path con modulo")
    eq((W.Validate({ type = "toggle", label = "x", get = function() end, set = function() end })), true)
    eq((W.Validate({ type = "range", path = "a", min = 5, max = 1 }, {})), false, "min>=max")
    eq((W.Validate({ type = "range", path = "a" }, {})), false)
    eq((W.Validate({ type = "dropdown", path = "a" }, {})), false, "values mancante")
    eq((W.Validate({ type = "execute", label = "x" })), false, "func mancante")
    eq((W.Validate({ type = "list" })), false)
    eq((W.Validate({ type = "label", label = "x" })), true)
    eq((W.Validate({ type = "custom" })), true, "tipi custom: validati dal builder")
    eq(W.OptionLabel({ label = "L" }), "L")
    eq(W.OptionLabel({ label = 5 }), nil)
    eq(W.OptionLabel("x"), nil)
end

T["widget: builder con descrittori errati o mancanti non lanciano"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local names = {}
    for name in pairs(W.Builders) do names[#names + 1] = name end
    truthy(#names >= 11, "builder ufficiali presenti")
    for _, name in ipairs({ "dropdown", "text", "color", "label", "separator", "list", "toggle", "range", "execute", "header", "select" }) do
        truthy(W.Builders[name], "builder " .. name)
    end
    local bad = { nil, 42, "x", {}, { type = name }, { label = 5 }, { type = "range", min = "a" },
        { path = {}, label = {} }, { items = 5 }, { values = "x" }, { func = "no" } }
    for _, name in ipairs(names) do
        local variants = { {}, { type = name }, { type = name, label = {} }, { type = name, path = 5, min = {}, max = "x", values = 3, items = "z", func = 1 } }
        for i = 1, 12 do variants[#variants + 1] = bad[i] end
        for _, opt in ipairs(variants) do
            local ok, err = pcall(W.Builders[name], parent, nil, opt)
            if not ok then error("builder " .. name .. " ha lanciato: " .. tostring(err)) end
        end
        noThrow(function() W.Builders[name](parent, nil, nil) end, name .. " con opt nil")
        noThrow(function() W.Builders[name](parent, {}, {}) end, name .. " con modulo vuoto")
    end
    local fs, h = W.Builders.toggle(parent, nil, nil)
    truthy(h > 0, "ritorna comunque una riga (errore)")
    truthy(logHas("Opzione non valida"), "problema registrato")
end

T["widget: Build, altezze, hidden/disabled/tooltip"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local store = { a = true, b = 0.5, c = "uno" }
    local hide, dis = false, false
    local mod = { Get = function(_, p) return store[p] end, Set = function(_, p, v) store[p] = v end,
        options = {
            { type = "header", label = "Titolo" },
            { type = "toggle", path = "a", label = "Toggle", tooltip = "aiuto" },
            { type = "range", path = "b", label = "Range", min = 0, max = 1, step = 0.1 },
            { type = "dropdown", path = "c", label = "Scelta", values = { "uno", "due" }, hidden = function() return hide end },
            { type = "execute", label = "Vai", func = function() store.ran = true end, disabled = function() return dis end },
            { type = "separator" },
            { type = "label", text = "Una riga di testo" },
            { type = "boh", label = "tipo sconosciuto" },
            "spazzatura",
            { type = "text", label = "Nome" },
        } }
    local h, widgets, group = W:Build(parent, mod, 0)
    eq(#widgets, 10, "un widget per descrittore, anche per quelli errati")
    eq(#group.entries, 10)
    truthy(h > 28 + 28 + 40 + 46 + 30, "altezza coerente: " .. h)
    eq(widgets[2].badbTooltip, "aiuto")
    -- hidden dinamico
    local h1 = group.height
    hide = true
    local h2 = group:Refresh()
    eq(h2, h1 - 46, "elemento nascosto non occupa spazio")
    eq(widgets[4]:IsShown(), false)
    hide = false
    eq(group:Refresh(), h1)
    eq(widgets[4]:IsShown(), true)
    -- disabled dinamico
    eq(widgets[5].badbDisabled, false)
    dis = true
    group:Refresh()
    eq(widgets[5].badbDisabled, true)
    eq(widgets[5].__alpha, 0.5, "widget disabilitato attenuato")
    dis = false
    group:Refresh()
    eq(widgets[5].__alpha, 1)
    -- startY rispettato
    local h3 = W:Build(parent, { options = { { type = "header", label = "x" } } }, 100)
    eq(h3, 128)
    -- opzioni esplicite senza modulo, e lista non valida
    local h4, w4 = W:Build(parent, nil, 0, { { type = "label", text = "ciao" } })
    eq(#w4, 1); truthy(h4 > 0)
    local h5, w5 = W:Build(parent, { options = "non una lista" }, 0)
    eq(h5, 0); eq(#w5, 0)
    -- hidden/disabled che lanciano errori: ignorati
    local _, _, g6 = W:Build(parent, nil, 0, { { type = "label", text = "x", hidden = function() error("no") end, disabled = function() error("no") end } })
    noThrow(function() g6:Refresh() end)
end

T["widget: toggle/range/execute storici restano compatibili"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local store = { on = false, v = 0.3 }
    local mod = { Get = function(_, p) return store[p] end, Set = function(_, p, v) store[p] = v end }
    local cb = W.Builders.toggle(parent, mod, { type = "toggle", path = "on", label = "T" })
    cb.GetChecked = function() return true end
    cb.__scripts.OnClick(cb)
    eq(store.on, true)
    local s, h, x, y = W.Builders.range(parent, mod, { type = "range", path = "v", label = "R", min = 0, max = 1, step = 0.1 })
    eq(h, 40); eq(x, 20); eq(y, 14, "stessi offset del layout storico")
    s.__scripts.OnValueChanged(s, 0.8, true)
    eq(store.v, 0.8)
    s.__scripts.OnValueChanged(s, 0.1, false)
    eq(store.v, 0.8, "niente set senza input utente")
    local ran
    local b = W.Builders.execute(parent, mod, { type = "execute", label = "E", func = function() ran = true end })
    click(b)
    truthy(ran)
    -- setter che lancia: isolato
    local cb2 = W.Builders.toggle(parent, nil, { type = "toggle", label = "T2", get = function() return false end, set = function() error("set rotto") end })
    noThrow(function() click(cb2) end)
    truthy(logHas("set rotto"))
    local bx = W.Builders.execute(parent, nil, { type = "execute", label = "E2", func = function() error("func rotta") end })
    noThrow(function() click(bx) end)
    truthy(logHas("func rotta"))
end

T["widget: select (da main) come alias di dropdown"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local val = "b"
    local box = W.Builders.select(parent, nil, { type = "select", label = "S", values = { { value = "a", text = "A" }, { value = "b", text = "B" } },
        get = function() return val end, set = function(v) val = v end })
    local ch = box.GetChoices()
    eq(#ch, 2); eq(ch[1].label, "A")
    box:SetValue("a")
    eq(val, "a")
end

T["widget: dropdown (menu e fallback senza template)"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local val, calls = "b", 0
    local opt = { type = "dropdown", label = "D", values = function() calls = calls + 1; return { "a", "b", "c" } end,
        get = function() return val end, set = function(v) val = v end }
    local box = W.Builders.dropdown(parent, nil, opt)
    eq(box.badbMode, "menu")
    box:SetValue("c")
    eq(val, "c")
    -- fallback: il template non esiste
    local orig = CreateFrame
    CreateFrame = function(kind, name, p, tpl)
        if tpl == "WowStyle1DropdownTemplate" then error("template inesistente") end
        return orig(kind, name, p, tpl)
    end
    local ok, box2 = pcall(W.Builders.dropdown, parent, nil, opt)
    CreateFrame = orig
    truthy(ok, "non deve lanciare")
    eq(box2.badbMode, "cycle")
    eq(box2.button:GetText(), "c")
    click(box2.button)
    eq(val, "a", "cicla al valore successivo (dopo c torna ad a)")
    click(box2.button)
    eq(val, "b")
    -- valori vuoti: nessun errore
    local box3 = W.Builders.dropdown(parent, nil, { type = "dropdown", label = "V", values = {}, get = function() end, set = function() end })
    noThrow(function() box3:SetValue("x") end)
end

T["widget: text con validazione"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local val = "ciao"
    local box = W.Builders.text(parent, nil, { type = "text", label = "T", get = function() return val end, set = function(v) val = v end,
        validate = function(t) if #t < 3 then return false, "troppo corto" end return true, t:upper() end })
    eq(box.edit:GetText(), "ciao")
    box.edit:SetText("ab")
    eq(box.Commit(), false)
    truthy(box.err:GetText():find("troppo corto", 1, true), "messaggio di validazione")
    eq(val, "ciao", "valore invariato")
    eq(box.edit:GetText(), "ciao", "testo ripristinato")
    box.edit:SetText("nuovo")
    eq(box.Commit(), true)
    eq(val, "NUOVO", "valore convertito dal validatore")
    box.edit:SetText("zzz")
    box.edit.__scripts.OnEnterPressed(box.edit)
    eq(val, "ZZZ")
    -- numerico
    local n = 5
    local nb = W.Builders.text(parent, nil, { type = "text", label = "N", numeric = true, get = function() return n end, set = function(v) n = v end })
    nb.edit:SetText("12.5"); eq(nb.Commit(), true); eq(n, 12.5)
    nb.edit:SetText("abc"); eq(nb.Commit(), false); eq(n, 12.5)
    -- validate che lancia
    local vb = W.Builders.text(parent, nil, { type = "text", label = "V", get = function() return "" end, set = function() end,
        validate = function() error("validate rotto") end })
    vb.edit:SetText("x")
    noThrow(function() vb.Commit() end)
    eq(vb.Commit(), true, "dopo il ripristino il testo coincide: niente da fare")
    -- path con modulo
    local store = {}
    local mod = { Get = function(_, p) return store[p] end, Set = function(_, p, v) store[p] = v end }
    local mb = W.Builders.text(parent, mod, { type = "text", label = "P", path = "nome" })
    mb.edit:SetText("salvato"); mb.Commit()
    eq(store.nome, "salvato")
    -- ESC ripristina
    mb.edit:SetText("sporco")
    mb.edit.__scripts.OnEscapePressed(mb.edit)
    eq(mb.edit:GetText(), "salvato")
end

T["widget: color con ColorPicker"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local color, shown = { r = 1, g = 0, b = 0, a = 1 }, nil
    local picked = { 0.1, 0.2, 0.3 }
    ColorPickerFrame = {
        SetupColorPickerAndShow = function(_, info) shown = info end,
        GetColorRGB = function() return picked[1], picked[2], picked[3] end,
    }
    local box = W.Builders.color(parent, nil, { type = "color", label = "C",
        get = function() return color end, set = function(r, g, b, a) color = { r = r, g = g, b = b, a = a } end })
    click(box.button)
    truthy(shown, "ColorPicker aperto")
    eq(shown.r, 1); eq(shown.g, 0)
    shown.swatchFunc()
    eq(color.r, 0.1); eq(color.b, 0.3)
    shown.cancelFunc()
    eq(color.r, 1, "annulla ripristina")
    -- modulo + path: salva tabella
    local store = {}
    local mod = { Get = function(_, p) return store[p] end, Set = function(_, p, v) store[p] = v end }
    local b2 = W.Builders.color(parent, mod, { type = "color", label = "C2", path = "col" })
    b2:SetColor(0.5, 0.5, 0.5)
    eq(store.col.r, 0.5); eq(store.col.a, 1)
    -- picker assente: errore registrato, non lanciato
    ColorPickerFrame = nil
    noThrow(function() click(box.button) end)
    truthy(logHas("Selettore colore"))
    -- API legacy
    ColorPickerFrame = { SetColorRGB = function() end, Show = function() end, GetColorRGB = function() return 0.9, 0.9, 0.9 end }
    click(box.button)
    ColorPickerFrame.func()
    eq(color.r, 0.9)
    ColorPickerFrame = nil
end

T["widget: label altezza, separator"] = function()
    local W = BadbUI.Widgets
    local parent = CreateFrame("Frame")
    local short = select(2, W.Builders.label(parent, nil, { type = "label", text = "ciao" }))
    local long = select(2, W.Builders.label(parent, nil, { type = "label", text = string.rep("parola ", 120) }))
    truthy(long > short * 3, "testo lungo = piu' righe")
    local multi = select(2, W.Builders.label(parent, nil, { type = "label", text = "a\nb\nc" }))
    truthy(multi > short, "a capo espliciti")
    eq(W.EstimateTextHeight("", 100, 10), 10)
    eq(W.EstimateTextHeight("a\nb", 100, 10), 20)
    local dyn = "uno"
    local fs = W.Builders.label(parent, nil, { type = "label", text = function() return dyn end })
    dyn = "due"
    fs.Refresh()
    eq(fs:GetText(), "due", "testo dinamico")
    local sep, h = W.Builders.separator(parent, nil, { type = "separator" })
    truthy(sep and h > 0)
end

T["widget: list con righe, azioni, conferma ed errori"] = function()
    local W, UI = BadbUI.Widgets, BadbUI.ConfigUI
    local parent = CreateFrame("Frame")
    local data = { "uno", "due", "tre" }
    local acted = {}
    local box = W.Builders.list(parent, nil, { type = "list", label = "Elenco", height = 100, items = function()
        local rows = {}
        for i, d in ipairs(data) do
            rows[#rows + 1] = { text = d, detail = "n" .. i, onClick = function() acted[#acted + 1] = "click:" .. d end, actions = {
                { label = "Del", func = function(item) acted[#acted + 1] = "del:" .. item.text; table.remove(data, 1) end,
                  confirm = "Eliminare?" },
                { label = "Info", func = function() acted[#acted + 1] = "info" end, disabled = function() return i == 2 end },
                { label = "Boom", func = function() error("azione rotta") end },
            } }
        end
        return rows
    end })
    eq(box.badbCount, 3)
    eq(box.rows[1].text:GetText(), "uno")
    eq(box.rows[3]:IsShown(), true)
    click(box.rows[2])
    eq(acted[1], "click:due")
    click(box.rows[1].actionButtons[2])
    eq(acted[2], "info")
    click(box.rows[2].actionButtons[2])
    eq(#acted, 2, "azione disabilitata non eseguita")
    -- azione con conferma
    click(box.rows[1].actionButtons[1])
    eq(#acted, 2, "in attesa di conferma")
    eq(UI.confirmFrame.text:GetText(), "Eliminare?")
    click(UI.confirmFrame.yes)
    eq(acted[3], "del:uno")
    eq(box.badbCount, 2, "lista aggiornata dopo l'azione")
    eq(box.rows[3]:IsShown(), false, "riga in eccesso nascosta")
    -- annulla
    click(box.rows[1].actionButtons[1])
    click(UI.confirmFrame.no)
    eq(box.badbCount, 2)
    -- errore nell'azione
    noThrow(function() click(box.rows[1].actionButtons[3]) end)
    truthy(logHas("azione rotta"))
    -- items che lancia / ritorna spazzatura / enorme
    local bad = W.Builders.list(parent, nil, { type = "list", items = function() error("items rotto") end })
    eq(bad.badbCount, 0)
    truthy(logHas("items rotto"))
    local junk = W.Builders.list(parent, nil, { type = "list", items = function() return { 5, "x", false, { text = 1 } } end })
    eq(junk.badbCount, 4)
    local big = {}
    for i = 1, 1000 do big[i] = { text = "r" .. i } end
    local huge = W.Builders.list(parent, nil, { type = "list", items = big })
    eq(huge.badbCount, 300, "righe limitate")
    local empty = W.Builders.list(parent, nil, { type = "list", items = {}, empty = "Vuoto" })
    eq(empty.badbCount, 0)
end

T["firme: metodo (:) e funzione (.) equivalenti per TextBox, Confirm, Toast, Open, OpenPage, Refresh"] = function()
    local UI = BadbUI.ConfigUI
    newModule("Pg", { page = { title = "Pg", build = function() return 30 end } })
    -- TextBox
    UI.TextBox("T1", "uno"); eq(UI.textBoxFrame.edit:GetText(), "uno")
    UI:TextBox("T2", "due"); eq(UI.textBoxFrame.edit:GetText(), "due")
    eq(UI.textBoxFrame.title:GetText(), "T2")
    local got
    UI.TextBox("T", "", function(t) got = t end)
    UI.textBoxFrame.edit:SetText("a"); click(UI.textBoxFrame.ok); eq(got, "a")
    UI:TextBox("T", "", function(t) got = t .. "!" end)
    UI.textBoxFrame.edit:SetText("b"); click(UI.textBoxFrame.ok); eq(got, "b!")
    -- Confirm
    local y = 0
    UI.Confirm("dot", function() y = y + 1 end); eq(UI.confirmFrame.text:GetText(), "dot"); click(UI.confirmFrame.yes)
    UI:Confirm("colon", function() y = y + 1 end); eq(UI.confirmFrame.text:GetText(), "colon"); click(UI.confirmFrame.yes)
    eq(y, 2)
    -- Toast
    UI.Toast("dot-toast"); UI:Toast("colon-toast")
    eq(UI.toasts.items[1].text, "dot-toast"); eq(UI.toasts.items[2].text, "colon-toast")
    -- Open / OpenPage / Refresh
    eq(UI.Open("profiles"), true); eq(UI.current, "profiles")
    eq(UI:Open("about"), true); eq(UI.current, "about")
    eq(UI.OpenPage("Pg"), true); eq(UI.current, "mod:Pg")
    eq(UI:OpenPage("profiles"), false, "profiles non e' un modulo")
    noThrow(function() UI.Refresh() end)
    noThrow(function() UI:Refresh() end)
    -- chiamate come fanno altri file: Badb.ConfigUI.TextBox(...) e Badb.ConfigUI:TextBox(...)
    BadbUI.ConfigUI.TextBox("X", "y")
    BadbUI.ConfigUI:TextBox("X", "y")
end

return T
