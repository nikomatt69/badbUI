-- Profili (DB) e pagina Import / Export: nomi, riferimenti, spec, stringhe malformate, anteprima.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end
local function falsy(v, msg) if v then error((msg or "atteso falso") .. " (" .. tostring(v) .. ")", 2) end end
local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end
local function click(frame, ...) frame.__scripts.OnClick(frame, ...) end

local T = {}
local CHAR = "Tester - Forever"

local function withSpec(group, fn)
    local prev = _G.GetActiveTalentGroup
    _G.GetActiveTalentGroup = function() return group end
    local ok, err = pcall(fn)
    _G.GetActiveTalentGroup = prev
    if not ok then error(err, 0) end
end

---------------------------------------------------------------------------
-- Nomi
---------------------------------------------------------------------------
T["nomi: vuoti, spazi, troppo lunghi, codici colore e duplicati rifiutati"] = function()
    local DB = BadbUI.DB
    for _, bad in ipairs({ "", "   ", string.rep("x", 49), "|cffff0000Rosso|r", "a\nb" }) do
        falsy((DB:NewProfile(bad)), "accettato: " .. bad)
    end
    falsy((DB:NewProfile(nil)))
    falsy((DB:NewProfile(42)))
    falsy((DB:NewProfile("Default")), "duplicato")
    falsy((DB:CopyProfile("Default", "Default")))
    falsy((DB:CopyProfile("Inesistente", "X")))
end

T["nomi: gli spazi ai lati vengono tolti e il nome normalizzato e' restituito"] = function()
    local DB = BadbUI.DB
    local ok, name = DB:NewProfile("  Raid  ")
    eq(ok, true); eq(name, "Raid")
    truthy(DB:ProfileExists("Raid"))
    falsy((DB:NewProfile("Raid ")), "duplicato dopo il trim")
    local ok2, copy = DB:CopyProfile("Raid", " Raid 2")
    eq(ok2, true); eq(copy, "Raid 2")
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------
T["NewProfile: profilo con i default, non attivato"] = function()
    local DB = BadbUI.DB
    eq(DB:NewProfile("Vuoto"), true)
    eq(DB:GetProfileName(), "Default")
    truthy(BadbUIDB.profiles.Vuoto.modules.Scaling, "default dei moduli presenti")
end

T["CopyProfile: copia indipendente"] = function()
    local DB = BadbUI.DB
    DB:Set("Scaling", "uiScale", 0.8)
    DB:CopyProfile("Default", "Copia")
    BadbUIDB.profiles.Copia.modules.Scaling.uiScale = 0.5
    eq(DB:Get("Scaling", "uiScale"), 0.8)
end

T["RenameProfile: stessa tabella, personaggi e spec riallineati"] = function()
    local DB = BadbUI.DB
    local tbl = DB.profile
    DB:SetSpecProfile(2, "Default")
    BadbUIDB.profileKeys["Alt - Forever"] = "Default"
    BadbUIDB.specProfiles["Alt - Forever"] = { [1] = "Default" }
    local ok, name = DB:RenameProfile("Default", "Principale")
    eq(ok, true); eq(name, "Principale")
    eq(DB:GetProfileName(), "Principale")
    truthy(DB.profile == tbl, "nessuna copia del profilo attivo")
    truthy(BadbUIDB.profiles.Principale == tbl)
    falsy(BadbUIDB.profiles.Default)
    eq(BadbUIDB.profileKeys[CHAR], "Principale")
    eq(BadbUIDB.profileKeys["Alt - Forever"], "Principale")
    eq(DB:GetSpecProfile(2), "Principale")
    eq(BadbUIDB.specProfiles["Alt - Forever"][1], "Principale")
end

T["RenameProfile: collisioni, nome uguale, inesistente, non valido"] = function()
    local DB = BadbUI.DB
    DB:NewProfile("A")
    falsy((DB:RenameProfile("A", "Default")))
    falsy((DB:RenameProfile("A", "A")))
    falsy((DB:RenameProfile("Z", "Y")))
    falsy((DB:RenameProfile("A", "  ")))
    truthy(DB:ProfileExists("A"), "il profilo resta intatto dopo i rifiuti")
end

T["RenameProfile tramite la shell (UI:RenameProfile) usa la logica del DB"] = function()
    local UI, DB = BadbUI.ConfigUI, BadbUI.DB
    DB:NewProfile("Vecchio")
    DB:SetSpecProfile(1, "Vecchio")
    eq((UI:RenameProfile("Vecchio", "Nuovo")), true)
    eq(DB:GetSpecProfile(1), "Nuovo")
end

T["DeleteProfile: attivo rifiutato, riferimenti puliti, doppio delete fallisce"] = function()
    local DB = BadbUI.DB
    falsy((DB:DeleteProfile("Default")))
    DB:NewProfile("Pvp")
    DB:SetSpecProfile(1, "Pvp")
    BadbUIDB.profileKeys["Alt - Forever"] = "Pvp"
    BadbUIDB.specProfiles["Alt - Forever"] = { [2] = "Pvp" }
    eq(DB:DeleteProfile("Pvp"), true)
    falsy(DB:GetSpecProfile(1))
    falsy(BadbUIDB.profileKeys["Alt - Forever"])
    falsy(BadbUIDB.specProfiles["Alt - Forever"][2])
    falsy((DB:DeleteProfile("Pvp")))
end

T["GetProfileUsers: personaggi ordinati"] = function()
    local DB = BadbUI.DB
    BadbUIDB.profileKeys["Zeta - Forever"] = "Default"
    BadbUIDB.profileKeys["Alfa - Forever"] = "Default"
    local u = DB:GetProfileUsers("Default")
    eq(#u, 3); eq(u[1], "Alfa - Forever"); eq(u[3], "Zeta - Forever")
end

T["BADB_PROFILES_UPDATED a ogni modifica dell'elenco"] = function()
    local DB, Events = BadbUI.DB, BadbUI.Events
    local n, owner = 0, {}
    Events:On(owner, "BADB_PROFILES_UPDATED", function() n = n + 1 end)
    DB:NewProfile("E1"); DB:CopyProfile("E1", "E2"); DB:RenameProfile("E2", "E3"); DB:DeleteProfile("E3")
    Events:Off(owner, "BADB_PROFILES_UPDATED")
    eq(n, 4)
end

---------------------------------------------------------------------------
-- Specializzazione
---------------------------------------------------------------------------
T["spec: il cambio attiva il profilo associato"] = function()
    local DB = BadbUI.DB
    DB:NewProfile("Heal")
    DB:SetSpecProfile(2, "Heal")
    withSpec(2, function() BadbUI.Events:Fire("ACTIVE_TALENT_GROUP_CHANGED") end)
    eq(DB:GetProfileName(), "Heal")
end

T["spec: in combattimento il cambio aspetta l'uscita dal combattimento"] = function(Mock)
    local DB = BadbUI.DB
    DB:NewProfile("Heal")
    DB:SetSpecProfile(2, "Heal")
    Mock.combat = true
    withSpec(2, function() BadbUI.Events:Fire("ACTIVE_TALENT_GROUP_CHANGED") end)
    eq(DB:GetProfileName(), "Default")
    Mock.combat = false
    withSpec(2, function() BadbUI.Events:Fire("PLAYER_REGEN_ENABLED") end)
    eq(DB:GetProfileName(), "Heal")
end

T["spec: un profilo eliminato altrove non viene ricreato vuoto"] = function()
    local DB = BadbUI.DB
    DB:SetSpecProfile(2, "Fantasma") -- es. eliminato da un altro personaggio sullo stesso account
    withSpec(2, function() BadbUI.Events:Fire("ACTIVE_TALENT_GROUP_CHANGED") end)
    eq(DB:GetProfileName(), "Default")
    falsy(BadbUIDB.profiles.Fantasma, "nessun profilo vuoto creato")
    falsy(DB:GetSpecProfile(2), "assegnazione orfana rimossa")
end

---------------------------------------------------------------------------
-- Import / export (DB)
---------------------------------------------------------------------------
T["import: roundtrip completo con layout Edit Mode"] = function()
    local DB = BadbUI.DB
    DB:Set("Scaling", "uiScale", 0.83)
    DB:Set("EditModeBridge", "layoutString", "0 50 0 0 7")
    local str = DB:ExportProfile()
    truthy(str:find("^BADB1:"))
    local ok, name = DB:ImportProfile(str, "Copia")
    eq(ok, true); eq(name, "Copia")
    eq(BadbUIDB.profiles.Copia.modules.Scaling.uiScale, 0.83)
    eq(BadbUIDB.profiles.Copia.modules.EditModeBridge.layoutString, "0 50 0 0 7")
end

T["import: stringhe vuote, spazzatura, altri addon, nil"] = function()
    local DB = BadbUI.DB
    for i, bad in ipairs({ "", "   ", "ciao", "BADB1:", "BADB1::", "AEGIS1:abc:00000000", "!WA:2!abcdef", "BADB1:@@@@:00000000" }) do
        local ok, err = DB:ImportProfile(bad, "X" .. i)
        falsy(ok, "accettata: " .. bad)
        truthy(type(err) == "string" and #err > 0, "messaggio d'errore per: " .. bad)
    end
    falsy((DB:ImportProfile(nil, "N")))
    eq(#DB:ListProfiles(), 1, "nessun profilo creato")
end

T["import: stringa troncata o modificata rifiutata dal checksum"] = function()
    local DB = BadbUI.DB
    local str = DB:ExportProfile()
    falsy((DB:ImportProfile(str:sub(1, #str - 20) .. str:sub(-9), "T")))
    local body = str:match("^BADB1:([^:]+):")
    local c = body:sub(11, 11)
    local tampered = "BADB1:" .. body:sub(1, 10) .. (c == "A" and "B" or "A") .. body:sub(12) .. str:match("(:%x+)$")
    local ok, err = DB:ImportProfile(tampered, "F")
    falsy(ok); truthy(err:find("checksum") or err:find("base64") or err:find("corrotti"), err)
end

T["import: versione futura rifiutata con messaggio chiaro"] = function()
    local DB = BadbUI.DB
    local ok, err = DB:ImportProfile((DB:ExportProfile():gsub("^BADB1:", "BADB9:")), "Futuro")
    falsy(ok); truthy(err:find("recente"), err)
end

T["import: spazi e a capo del copia/incolla tollerati"] = function()
    local DB = BadbUI.DB
    local s = DB:ExportProfile()
    local spaced = "  " .. s:sub(1, 20) .. "\n" .. s:sub(21, 40) .. " \r\n" .. s:sub(41) .. "\n"
    eq((DB:ImportProfile(spaced, "Spazi")), true)
end

T["import: nome esistente o non valido rifiutato"] = function()
    local DB = BadbUI.DB
    local s = DB:ExportProfile()
    falsy((DB:ImportProfile(s, "Default")))
    falsy((DB:ImportProfile(s, "")))
    falsy((DB:ImportProfile(s, string.rep("n", 60))))
end

T["import: struttura annidata abnorme rifiutata"] = function()
    local DB = BadbUI.DB
    local deep, cur = {}, nil
    cur = deep
    for _ = 1, 60 do cur.x = {}; cur = cur.x end
    local ok, err = DB:ImportProfile(BadbUI.Serializer:Export("profile", deep), "Profondo")
    falsy(ok); truthy(err:find("profonda"), err)
end

T["import: forma errata (modules non tabella, voci non tabella) gestita"] = function()
    local DB = BadbUI.DB
    falsy((DB:ImportProfile(BadbUI.Serializer:Export("profile", { modules = "x" }), "M")))
    falsy((DB:ImportProfile(BadbUI.Serializer:Export("profile", "solo testo"), "S")))
    local ok = DB:ImportProfile(BadbUI.Serializer:Export("profile", { modules = { Scaling = 5, [3] = {} }, frames = { F = true } }), "Pulito")
    eq(ok, true)
    local p = BadbUIDB.profiles.Pulito
    eq(type(p.modules.Scaling), "table", "voce non valida sostituita dai default")
    falsy(p.modules[3]); falsy(p.frames.F)
end

T["import: le stringhe nei valori restano dati (nessuna esecuzione)"] = function()
    local DB = BadbUI.DB
    local evil = "os.exit(1) --]] error('x')"
    DB:Set("Scaling", "nota", evil)
    DB:ImportProfile(DB:ExportProfile(), "Sicuro")
    eq(BadbUIDB.profiles.Sicuro.modules.Scaling.nota, evil)
end

T["import: modulo esportato non e' importabile come profilo"] = function()
    local DB = BadbUI.DB
    falsy((DB:ImportProfile(DB:ExportModule("Scaling"), "Mod")))
end

T["ImportIntoActive: sostituisce e reintegra i default"] = function()
    local DB = BadbUI.DB
    DB:NewProfile("Src")
    BadbUIDB.profiles.Src.modules.Scaling.uiScale = 0.42
    BadbUIDB.profiles.Src.modules.Hider = nil
    eq((DB:ImportIntoActive(DB:ExportProfile("Src"))), true)
    eq(DB:GetProfileName(), "Default")
    eq(DB:Get("Scaling", "uiScale"), 0.42)
    truthy(DB.profile.modules.Hider, "default reintegrati")
    falsy((DB:ImportIntoActive("spazzatura")))
end

T["modulo: export/import e casi d'errore"] = function()
    local DB = BadbUI.DB
    DB:Set("Scaling", "uiScale", 0.77)
    local s = DB:ExportModule("Scaling")
    DB:Set("Scaling", "uiScale", 0.5)
    local ok, name = DB:ImportModule(s)
    eq(ok, true); eq(name, "Scaling")
    eq(DB:Get("Scaling", "uiScale"), 0.77)
    falsy((DB:ExportModule("Inesistente")))
    falsy((DB:ImportModule(DB:ExportProfile())), "un profilo non e' un modulo")
    local ok2, err = DB:ImportModule(BadbUI.Serializer:Export("module:NonInstallato", { a = 1 }))
    falsy(ok2); truthy(err:find("sconosciuto"), err)
end

T["PreviewImport: descrive senza applicare"] = function()
    local DB = BadbUI.DB
    DB:Set("EditModeBridge", "layoutString", "abc")
    DB.profile.modules.ModuloFuturo = { enabled = true }
    DB.profile.frames.PlayerFrame = { alpha = 0.5 }
    local before, frames = #DB:ListProfiles(), 0
    for _, v in pairs(DB.profile.frames) do if type(v) == "table" then frames = frames + 1 end end
    local info = DB:PreviewImport(DB:ExportProfile())
    eq(info.kind, "profile"); eq(info.hasLayout, true); eq(info.frames, frames)
    truthy(frames >= 1)
    truthy(has(info.modules, "Scaling")); truthy(has(info.unknown, "ModuloFuturo"))
    eq(#DB:ListProfiles(), before)
    local m = DB:PreviewImport(DB:ExportModule("Scaling"))
    eq(m.kind, "module:Scaling"); eq(m.modules[1], "Scaling")
    falsy((DB:PreviewImport("spazzatura")))
    falsy((DB:PreviewImport(BadbUI.Serializer:Export("layout", {}))), "tipo non supportato")
end

---------------------------------------------------------------------------
-- Badb.ImportExport (logica della pagina)
---------------------------------------------------------------------------
T["IO:Analyze: azioni disponibili per tipo di stringa"] = function()
    local IO, DB = BadbUI.ImportExport, BadbUI.DB
    local a = IO:Analyze(DB:ExportProfile())
    eq(a.ok, true); eq(a.actions.new, true); eq(a.actions.replace, true); falsy(a.actions.module)
    local b = IO:Analyze(DB:ExportModule("Scaling"))
    eq(b.ok, true); eq(b.actions.module, true); falsy(b.actions.new)
    local c = IO:Analyze("   ")
    falsy(c.ok); truthy(c.empty)
    local d = IO:Analyze(BadbUI.Serializer:Export("module:NonInstallato", {}))
    falsy(d.ok); truthy(d.error:find("installato"))
    falsy(IO:Analyze(string.rep("A", 500001)).ok, "input enorme rifiutato")
    truthy(IO:Describe(a):find("Profilo completo"))
    truthy(IO:Describe(d):find("installato"))
    truthy(IO:Describe(nil):find("Analizza"))
end

T["IO:Apply: nuovo profilo attivato, nome libero automatico"] = function()
    local IO, DB = BadbUI.ImportExport, BadbUI.DB
    local s = DB:ExportProfile()
    local ok, name = IO:Apply("new", s)
    eq(ok, true); eq(DB:GetProfileName(), name)
    local ok2, name2 = IO:Apply("new", s)
    eq(ok2, true); truthy(name2 ~= name, "secondo import con nome diverso")
    falsy((IO:Apply("module", s)), "azione non valida per un profilo")
    falsy((IO:Apply("new", "spazzatura")))
end

T["IO:Export: profilo e modulo, errori per sorgenti inesistenti"] = function()
    local IO = BadbUI.ImportExport
    truthy(IO:Export("profile"):find("^BADB1:"))
    truthy(IO:Export("module", "Scaling"):find("^BADB1:"))
    falsy((IO:Export("profile", "Nessuno")))
    falsy((IO:Export("module", "Nessuno")))
end

---------------------------------------------------------------------------
-- Pagina nella shell
---------------------------------------------------------------------------
T["pagina: registrata in Gestione dopo Profili, trovabile con la ricerca"] = function()
    local UI = BadbUI.ConfigUI
    local keys = {}
    for _, p in ipairs(UI:CollectPages()) do keys[#keys + 1] = p.key end
    local iProf, iIO
    for i, k in ipairs(keys) do if k == "profiles" then iProf = i elseif k == "io" then iIO = i end end
    truthy(iIO, "pagina io presente"); truthy(iProf < iIO, "dopo Profili")
    local found = false
    for _, r in ipairs(UI:Search("condividi")) do if r.key == "io" then found = true end end
    truthy(found, "keyword di ricerca")
end

T["pagina: si costruisce, esporta, analizza e importa senza errori"] = function()
    local UI, IO, DB = BadbUI.ConfigUI, BadbUI.ImportExport, BadbUI.DB
    eq(UI:Open("io"), true)
    truthy(IO.built, "pagina costruita")
    IO:DoExport()
    local s = IO.area.edit:GetText()
    truthy(s:find("^BADB1:"), "stringa nell'area di testo")
    IO:DoAnalyze()
    truthy(IO.state.analysis.ok)
    truthy(IO.state.name and IO.state.name ~= "", "nome proposto")
    IO:DoApply("new")
    eq(DB:GetProfileName(), IO.state.name or DB:GetProfileName())
    eq(#DB:ListProfiles(), 2)
    for _, l in ipairs(BadbUI.Logger.buffer) do falsy(l:find("ERROR"), l) end
end

T["pagina: sostituire il profilo attivo chiede conferma"] = function()
    local UI, IO, DB = BadbUI.ConfigUI, BadbUI.ImportExport, BadbUI.DB
    DB:NewProfile("Src")
    BadbUIDB.profiles.Src.modules.Scaling.uiScale = 0.44
    UI:Open("io")
    IO.area.edit:SetText(DB:ExportProfile("Src"))
    IO:DoAnalyze()
    IO:DoApply("replace")
    eq(DB:Get("Scaling", "uiScale"), 0.71, "niente cambia prima della conferma")
    click(UI.confirmFrame.yes)
    eq(DB:Get("Scaling", "uiScale"), 0.44)
end

T["pagina: Profili > Importa apre Import / Export"] = function()
    local UI, IO = BadbUI.ConfigUI, BadbUI.ImportExport
    eq(IO:OpenImport(), true)
    eq(UI.State().page, "io")
end

T["slash: /badb import e /badb io aprono la pagina"] = function()
    local UI = BadbUI.ConfigUI
    eq(BadbUI.Slash:Dispatch("import"), true)
    eq(UI.State().page, "io")
    UI:Open("overview")
    eq(BadbUI.Slash:Dispatch("io"), true)
    eq(UI.State().page, "io")
end

return T
