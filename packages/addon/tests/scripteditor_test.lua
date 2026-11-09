-- Test dell'editor di script (Config/ScriptEditor.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}
local function E() return BadbUI.ScriptEditor end
local function S() return BadbUI.Scripts end

local function fill(name, code, trigger, param, enabled)
    E().nameBox:SetText(name); E().code:SetText(code)
    E().fields.trigger = trigger or "manual"; E().fields.enabled = enabled or false
    E().param:SetText(param or "")
end

T["Open costruisce la finestra una volta sola"] = function()
    E():Open()
    local w = E().win
    truthy(w, "finestra non creata")
    E():Open()
    eq(E().win, w, "finestra ricreata")
    truthy(E().code and E().nameBox and E().trigger and E().enabled)
end

T["Salva: nuovo script con evento, parametro in maiuscolo"] = function()
    E():Open()
    fill("nuovo", "x = 1", "event", "player_level_up", true)
    truthy(E():Save())
    local rec = S():Record("nuovo")
    eq(rec.trigger, "event"); eq(rec.event, "PLAYER_LEVEL_UP"); eq(rec.enabled, true); eq(rec.code, "x = 1")
    eq(E().current, "nuovo")
end

T["Salva: trigger timer legge i secondi, valore non numerico = 5"] = function()
    E():Open()
    fill("tm", "", "timer", "12"); truthy(E():Save()); eq(S():Record("tm").interval, 12)
    fill("tm", "", "timer", "abc"); truthy(E():Save()); eq(S():Record("tm").interval, 5)
end

T["Salva: nome non valido non salva e segnala l'errore"] = function()
    E():Open()
    fill("a/b", "x=1")
    eq(E():Save(), false)
    eq(S():Record("a/b"), nil)
    truthy(E().status:GetText():find("nome non valido"), "messaggio d'errore mancante")
end

T["rinominare sposta lo script (il vecchio sparisce)"] = function()
    E():Open()
    fill("vecchio", "x=1"); E():Save()
    E().nameBox:SetText("nuovo nome")
    truthy(E():Save())
    eq(S():Record("vecchio"), nil, "il vecchio nome esiste ancora")
    truthy(S():Record("nuovo nome"))
end

T["Select carica i campi; Nuovo li azzera con il modello"] = function()
    E():Open()
    S():Save("caricami", { code = "-- ciao", trigger = "combatEnd", enabled = false })
    E():Select("caricami")
    eq(E().nameBox:GetText(), "caricami"); eq(E().code:GetText(), "-- ciao"); eq(E().fields.trigger, "combatEnd")
    E():New()
    eq(E().current, nil); eq(E().nameBox:GetText(), "")
    truthy(E().code:GetText():find("script.on", 1, true), "modello non caricato")
end

T["Elimina e Esegui"] = function()
    E():Open()
    fill("run me", "script.data.ok = true"); E():Run()
    eq(S():Record("run me").data.ok, true)
    E():Delete()
    eq(S():Record("run me"), nil); eq(E().current, nil)
end

T["Esporta mostra la stringa, Importa crea uno script spento"] = function()
    E():Open()
    fill("exp", "print(1)"); E():Save()
    E():Export()
    local str = E().dialog.box:GetText()
    truthy(str:find("^BADB1:"), "stringa export")
    E():ImportDialog()
    E().dialog.box:SetText(str)
    E().dialog.onOk(str)
    truthy(S():Record("exp 2"), "import non creato")
    eq(S():Record("exp 2").enabled, false)
    E().dialog.onOk("spazzatura")
    truthy(E().status:GetText():find("Import fallito"), "errore import non mostrato")
end

T["comando /badb script edit apre l'editor"] = function()
    S():Command("edit")
    truthy(E().win)
end

return T
