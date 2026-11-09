-- BadbUI - test del modulo Unit Frames.
-- Il mock condiviso (tests/wow_mock.lua) copre solo le API generiche: qui lo estendiamo,
-- solo per questa suite, con cio' che serve agli unit frame e con le regole del client che
-- vogliamo verificare:
--   * frame protetti: in combattimento SetPoint/SetSize/Show/Hide/SetParent/SetAttribute
--     lanciano ADDON_ACTION_BLOCKED, come il blocco reale;
--   * secret values: confronti/aritmetica falliscono (tabelle opache) e string.format con un
--     argomento secret restituisce un secret, come su Forever;
--   * PLAYER_REGEN_DISABLED arriva un attimo prima del lockdown, REGEN_ENABLED subito dopo.
-- Ogni caso parte da un ambiente pulito (runner): setup() reinstalla tutto.
local T = {}

local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function ok(v, msg) if not v then error(msg or "atteso vero", 2) end end

---------------------------------------------------------------------------
-- Estensione del mock
---------------------------------------------------------------------------
local Env -- stato del caso corrente

local function blocked(self, what)
    if Env.Mock.combat and rawget(self, "__protected") then
        error("ADDON_ACTION_BLOCKED: " .. what .. " su " .. tostring(rawget(self, "__name")), 3)
    end
end

local function setup(Mock)
    Env = { Mock = Mock, frames = {}, units = {}, auras = {}, watch = {}, drivers = {}, tickers = {} }
    local M = Mock.Methods

    -- Frame: protezione, geometria, parent, attributi, eventi per frame
    function M:IsProtected() return rawget(self, "__protected") or false end
    function M:SetPoint(...) blocked(self, "SetPoint"); self.__points = self.__points or {}; table.insert(self.__points, { ... }) end
    function M:ClearAllPoints() blocked(self, "ClearAllPoints"); self.__points = {} end
    function M:GetNumPoints() return #(rawget(self, "__points") or {}) end
    function M:GetPoint(i) return unpack((rawget(self, "__points") or {})[i or 1] or {}) end
    function M:SetSize(w, h) blocked(self, "SetSize"); self.__width, self.__height = w, h end
    function M:SetWidth(w) blocked(self, "SetWidth"); self.__width = w end
    function M:SetHeight(h) blocked(self, "SetHeight"); self.__height = h end
    function M:GetHeight() return rawget(self, "__height") or 0 end
    function M:Show() blocked(self, "Show"); self.__shown = true end
    function M:Hide() blocked(self, "Hide"); self.__shown = false end
    function M:SetShown(v) if v then self:Show() else self:Hide() end end
    function M:IsVisible()
        local o = self
        while o do
            if not rawget(o, "__shown") then return false end
            o = rawget(o, "__parent")
        end
        return true
    end
    function M:SetParent(p) blocked(self, "SetParent"); self.__parent = p end
    function M:GetParent() return rawget(self, "__parent") end
    function M:SetAttribute(k, v) blocked(self, "SetAttribute"); self.__attr = self.__attr or {}; self.__attr[k] = v end
    function M:GetAttribute(k) return (rawget(self, "__attr") or {})[k] end
    function M:RegisterEvent(e) self.__ev = self.__ev or {}; self.__ev[e] = true end
    function M:RegisterUnitEvent(e, ...) self.__ev = self.__ev or {}; self.__ev[e] = { ... } end
    function M:UnregisterAllEvents() self.__ev = {} end
    function M:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
    -- StatusBar
    function M:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
    function M:SetValue(v) self.__value = v end
    function M:GetValue() return rawget(self, "__value") end
    function M:SetStatusBarColor(r, g, b) self.__bar = { r, g, b } end

    local origCreate = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        if template and template:find("Secure") and Mock.combat then
            error("ADDON_ACTION_BLOCKED: CreateFrame secure in combattimento")
        end
        local o = origCreate(kind, name, parent, template)
        if template and template:find("Secure") then o.__protected = true end
        table.insert(Env.frames, o)
        return o
    end

    -- Frame Blizzard da sostituire (protetti come nel client)
    for _, n in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "TargetFrameToT", "CompactPartyFrame" }) do
        local f = Mock.NewObject("Button")
        f.__name, f.__parent, f.__protected = n, UIParent, true
        _G[n] = f
    end
    TargetFrameToT.__parent = TargetFrame

    -- Unita'
    local function U(t) return Env.units[t] end
    local function field(k, d) return function(t) local u = U(t); if u and u[k] ~= nil then return u[k] end; return d end end
    UnitExists = function(t) return U(t) ~= nil end
    UnitName = field("name", nil)
    UnitHealth, UnitHealthMax = field("health", 0), field("healthMax", 0)
    UnitPower, UnitPowerMax = field("power", 0), field("powerMax", 0)
    UnitPowerType = function(t) local u = U(t); return 0, u and u.powerToken or "MANA" end
    UnitLevel = field("level", 1)
    UnitIsConnected = field("connected", true)
    UnitIsDead, UnitIsGhost = field("dead", false), field("ghost", false)
    UnitIsPlayer = field("isPlayer", false)
    UnitClass = function(t) local u = U(t); return u and u.className, u and u.class end
    UnitReaction = field("reaction", nil)
    UnitIsTapDenied = field("tapDenied", false)
    UnitIsGroupLeader = field("leader", false)
    UnitAffectingCombat = function() return Mock.combat end
    UnitInRange = function(t) local u = U(t); return u and u.inRange, u and u.rangeChecked end
    UnitIsUnit = function(a, b) return a == b end
    UnitCastingInfo = function(t) local u = U(t); if u and u.cast then return unpack(u.cast) end end
    UnitChannelInfo = function(t) local u = U(t); if u and u.channel then return unpack(u.channel) end end
    UnitHealthPercent = function(t) local u = U(t); return u and u.healthPercent end
    GetRaidTargetIndex = field("raidIcon", nil)
    SetRaidTargetIconTexture = function() end
    CurveConstants = { ScaleTo100 = "ScaleTo100" }
    AbbreviateNumbers = function(v) if issecretvalue(v) then return v end; return tostring(v) end
    GetCreatureDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
    C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
        local list = Env.auras[unit .. ":" .. (filter:find("HARMFUL") and "HARMFUL" or "HELPFUL")]
        return list and list[i]
    end }
    RegisterUnitWatch = function(f) blocked(f, "RegisterUnitWatch"); Env.watch[f] = true end
    UnregisterUnitWatch = function(f) blocked(f, "UnregisterUnitWatch"); Env.watch[f] = nil end
    RegisterStateDriver = function(f, _, cond) Env.drivers[f] = cond end
    UnregisterStateDriver = function(f) Env.drivers[f] = nil end
    C_Timer.NewTicker = function(_, fn)
        local t = { fn = fn }
        function t:Cancel() self.cancelled = true end
        table.insert(Env.tickers, t)
        return t
    end
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    RAID_CLASS_COLORS = setmetatable({ MAGE = { r = 0.25, g = 0.78, b = 0.92 } },
        { __index = function() return { r = 0.5, g = 0.5, b = 0.5 } end })
    PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
    DebuffTypeColor = { Magic = { r = 0.2, g = 0.6, b = 1 } }
    GameTooltip = Mock.NewObject("GameTooltip")
    GameTooltip_Hide = function() end

    -- Come su Forever: formattare un valore secret produce una stringa secret.
    Env.rawFormat = string.format
    string.format = function(fmt, ...)
        for i = 1, select("#", ...) do
            if issecretvalue((select(i, ...))) then return Mock.Secret() end
        end
        return Env.rawFormat(fmt, ...)
    end

    Env.errorsBefore = 0
    for _, l in ipairs(BadbUI.Logger.buffer) do if l:find("ERROR") then Env.errorsBefore = Env.errorsBefore + 1 end end
end

local function teardown()
    if Env and Env.rawFormat then string.format = Env.rawFormat end
end

-- Eventi: bus interno + script OnEvent dei frame registrati (con filtro per unita').
local function fire(event, ...)
    Env.Mock.Fire(event, ...)
    local unit = ...
    for _, f in ipairs(Env.frames) do
        local reg = rawget(f, "__ev") and f.__ev[event]
        local script = f.__scripts and f.__scripts.OnEvent
        if reg and script then
            local pass = true
            if type(reg) == "table" and #reg > 0 then
                pass = false
                for _, u in ipairs(reg) do if u == unit then pass = true end end
            end
            if pass then script(f, event, ...) end
        end
    end
end

-- Il mock trasforma ogni Set* sconosciuto in un no-op: per simulare un client SENZA un'API
-- (o con un'API registrata) la si imposta come campo diretto dell'oggetto.
local function api(obj, name, fn) rawset(obj, name, fn or false) end

local function enterCombat() fire("PLAYER_REGEN_DISABLED"); Env.Mock.combat = true end
local function leaveCombat() Env.Mock.combat = false; fire("PLAYER_REGEN_ENABLED") end
local function tick() for _, t in ipairs(Env.tickers) do if not t.cancelled then t.fn() end end end

local function noErrors(msg)
    local errs = {}
    for _, l in ipairs(BadbUI.Logger.buffer) do if l:find("ERROR") then errs[#errs + 1] = l end end
    if #errs > Env.errorsBefore then error((msg or "errori nel log") .. ": " .. table.concat(errs, " | "), 2) end
end

local function defaultUnits()
    Env.units.player = { name = "Niko", health = 800, healthMax = 1000, power = 300, powerMax = 500,
        level = 60, isPlayer = true, class = "MAGE", className = "Mago" }
    Env.units.target = { name = "Lupo", health = 250, healthMax = 1000, level = 58, reaction = 2 }
end

local function enable()
    BadbUI.Modules:SetEnabled("UnitFrames", true)
    return BadbUI.UnitFrames
end

local function start(Mock)
    setup(Mock)
    defaultUnits()
    return enable()
end

local function case(name, fn)
    T[name] = function(Mock)
        local okRun, err = pcall(fn, Mock)
        teardown()
        if not okRun then error(err, 0) end
    end
end

---------------------------------------------------------------------------
-- Casi
---------------------------------------------------------------------------
case("disattivato di default: nessun frame creato al login", function(Mock)
    setup(Mock)
    local UF = BadbUI.UnitFrames
    ok(not UF.enabled, "modulo spento di default")
    ok(not UF.spawned, "nessun frame")
    eq(PlayerFrame:GetParent(), UIParent, "PlayerFrame intatto")
end)

case("attivazione: crea tutti i frame secure senza errori", function(Mock)
    local UF = start(Mock)
    ok(UF.enabled and UF.spawned, "attivo e creato")
    for _, t in ipairs({ "player", "target", "targettarget", "focus", "party1", "party4" }) do
        ok(UF.frames[t], "frame " .. t)
        ok(UF.frames[t]:IsProtected(), t .. " protetto")
    end
    local f = UF.frames.target
    eq(f:GetAttribute("unit"), "target", "attributo unit")
    eq(f:GetAttribute("*type1"), "target", "click sinistro = bersaglio")
    eq(f:GetAttribute("*type2"), "togglemenu", "click destro = menu")
    ok(ClickCastFrames[f], "registrato per il click casting")
    noErrors()
end)

case("visibilita' affidata al client: unit watch e state driver, nessuno snippet", function(Mock)
    local UF = start(Mock)
    ok(Env.watch[UF.frames.target], "watch target")
    ok(Env.watch[UF.frames.focus], "watch focus")
    ok(Env.watch[UF.frames.party3], "watch party3")
    ok(not Env.watch[UF.frames.player], "player sempre visibile")
    eq(Env.drivers[UF.partyHeader], "[group:raid] hide; [group:party] show; hide", "driver gruppo")
end)

case("frame Blizzard nascosti riparentandoli, mai spostati", function(Mock)
    start(Mock)
    ok(PlayerFrame:GetParent() ~= UIParent, "PlayerFrame riparentato")
    ok(not PlayerFrame:GetParent():IsShown(), "parent nascosto")
    eq(PlayerFrame:GetNumPoints(), 0, "nessun SetPoint su PlayerFrame")
    ok(TargetFrame:GetParent() ~= UIParent, "TargetFrame")
    ok(FocusFrame:GetParent() ~= UIParent, "FocusFrame")
    ok(PartyFrame:GetParent() ~= UIParent, "PartyFrame")
end)

case("CompactPartyFrame lasciato a GroupFrames quando quel modulo e' attivo", function(Mock)
    setup(Mock)
    defaultUnits()
    BadbUI.Modules:SetEnabled("GroupFrames", true)
    enable()
    eq(CompactPartyFrame:GetParent(), UIParent, "non toccato")
    ok(PartyFrame:GetParent() ~= UIParent, "PartyFrame classico nascosto comunque")
end)

case("frame Blizzard assenti sul client: nessun errore", function(Mock)
    setup(Mock)
    defaultUnits()
    FocusFrame, PartyFrame, TargetFrameToT = nil, nil, nil
    enable()
    noErrors()
end)

case("vita: barra, testo valore+percentuale e nome", function(Mock)
    local UF = start(Mock)
    local f = UF.frames.player
    eq(f.Health:GetValue(), 800, "valore")
    eq(f.Health.__max, 1000, "massimo")
    eq(f.HealthText:GetText(), "800  |cffb4bdcf80%|r", "testo")
    eq(f.Name:GetText(), "Niko", "nome")
end)

case("colori: classe per i giocatori, reazione per i PNG ostili", function(Mock)
    local UF = start(Mock)
    eq(UF.frames.player.Health.__bar[1], 0.25, "colore classe mago")
    local hostile = BadbUI.UnitFrames and select(2, pcall(function() return UF.frames.target.Health.__bar end))
    ok(hostile[1] > 0.9, "rosso ostile")
end)

case("UNIT_HEALTH aggiorna solo l'unita' giusta", function(Mock)
    local UF = start(Mock)
    Env.units.target.health = 100
    fire("UNIT_HEALTH", "target")
    eq(UF.frames.target.Health:GetValue(), 100, "target")
    eq(UF.frames.player.Health:GetValue(), 800, "player invariato")
end)

case("secret values: la vita opaca va alla barra, il testo usa la percentuale del client", function(Mock)
    local UF = start(Mock)
    local cur, max = Mock.Secret(), Mock.Secret()
    Env.units.target.health, Env.units.target.healthMax, Env.units.target.healthPercent = cur, max, 42
    fire("UNIT_HEALTH", "target")
    local f = UF.frames.target
    eq(f.Health:GetValue(), cur, "SetValue riceve il secret")
    ok(f.HealthText:GetText() ~= nil, "testo impostato")
    noErrors()
end)

case("secret values: percentuale non disponibile, testo solo valore", function(Mock)
    local UF = start(Mock)
    UnitHealthPercent = nil
    Env.units.target.health, Env.units.target.healthMax = Mock.Secret(), Mock.Secret()
    fire("UNIT_HEALTH", "target")
    ok(issecretvalue(UF.frames.target.HealthText:GetText()), "valore abbreviato secret")
    noErrors()
end)

case("secret values: reazione, classe e livello opachi usano colori neutri", function(Mock)
    local UF = start(Mock)
    Env.units.target.reaction = Mock.Secret()
    Env.units.target.level = Mock.Secret()
    Env.units.target.isPlayer = Mock.Secret()
    fire("PLAYER_TARGET_CHANGED")
    noErrors()
    ok(UF.frames.target.Health.__bar[2] > 0.7, "verde neutro di riserva")
end)

case("unita' morta, spirito e offline mostrano lo stato", function(Mock)
    local UF = start(Mock)
    Env.units.target = { name = "X", health = 0, healthMax = 1000, dead = true }
    fire("PLAYER_TARGET_CHANGED")
    eq(UF.frames.target.HealthText:GetText(), "Morto", "morto")
    Env.units.target = { name = "X", health = 1, healthMax = 1000, ghost = true }
    fire("PLAYER_TARGET_CHANGED")
    eq(UF.frames.target.HealthText:GetText(), "Spirito", "spirito")
    Env.units.target = { name = "X", health = 500, healthMax = 1000, connected = false, isPlayer = true }
    fire("PLAYER_TARGET_CHANGED")
    eq(UF.frames.target.HealthText:GetText(), "Offline", "offline")
end)

case("vita massima zero e numeri grandi", function(Mock)
    local UF = start(Mock)
    Env.units.target = { name = "Z", health = 0, healthMax = 0 }
    fire("PLAYER_TARGET_CHANGED")
    eq(UF.frames.target.HealthText:GetText(), "0  |cffb4bdcf0%|r", "nessuna divisione per zero")
    Env.units.target = { name = "Boss", health = 2500000, healthMax = 5000000 }
    fire("PLAYER_TARGET_CHANGED")
    eq(UF.frames.target.HealthText:GetText(), "2.5M  |cffb4bdcf50%|r", "abbreviazione milioni")
end)

case("bersaglio inesistente: nessun aggiornamento e nessun errore", function(Mock)
    local UF = start(Mock)
    Env.units.target = nil
    fire("PLAYER_TARGET_CHANGED")
    fire("UNIT_HEALTH", "target")
    noErrors()
    ok(UF.frames.focus, "focus esiste anche senza unita'")
end)

case("castbar con tempi normali: avanza e si chiude a fine lancio", function(Mock)
    local UF = start(Mock)
    Mock.time = 1000
    Env.units.target.cast = { "Palla di fuoco", "Palla di fuoco", 135812, 1000000, 1003000, false, "id", false }
    fire("UNIT_SPELLCAST_START", "target")
    local cast = UF.frames.target.Castbar
    ok(cast:IsShown(), "visibile")
    eq(cast.Text:GetText(), "Palla di fuoco", "nome")
    Mock.time = 1001.5
    cast:GetScript("OnUpdate")(cast, 0.1)
    eq(cast:GetValue(), 1.5, "progresso")
    Mock.time = 1004
    cast:GetScript("OnUpdate")(cast, 0.1)
    ok(not cast:IsShown(), "chiusa")
end)

case("castbar canalizzata: scorre all'indietro", function(Mock)
    local UF = start(Mock)
    Mock.time = 1000
    Env.units.target.channel = { "Evocazione", "Evocazione", 1, 1000000, 1004000, false, false }
    fire("UNIT_SPELLCAST_CHANNEL_START", "target")
    local cast = UF.frames.target.Castbar
    Mock.time = 1001
    cast:GetScript("OnUpdate")(cast, 0.1)
    eq(cast:GetValue(), 3, "tempo rimanente")
    fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    ok(not cast:IsShown(), "stop")
end)

case("castbar con tempi secret: nessuna aritmetica, barra piena come riserva", function(Mock)
    local UF = start(Mock)
    api(UF.frames.target.Castbar, "SetTimerDuration")
    Env.units.target.cast = { "Ombra", "Ombra", 1, Mock.Secret(), Mock.Secret(), false, "id", Mock.Secret() }
    fire("UNIT_SPELLCAST_START", "target")
    local cast = UF.frames.target.Castbar
    ok(cast:IsShown(), "visibile")
    eq(cast:GetScript("OnUpdate"), nil, "nessun OnUpdate")
    eq(cast:GetValue(), 1, "barra piena")
    noErrors()
    fire("UNIT_SPELLCAST_STOP", "target")
    ok(not cast:IsShown(), "STOP nasconde")
end)

case("castbar con tempi secret e API a durata: animazione delegata al client", function(Mock)
    local UF = start(Mock)
    local dur = {}
    UnitCastingDuration = function() return dur end
    local got
    api(UF.frames.target.Castbar, "SetTimerDuration", function(_, d) got = d end)
    Env.units.target.cast = { "Ombra", "Ombra", 1, Mock.Secret(), Mock.Secret(), false, "id", false }
    fire("UNIT_SPELLCAST_START", "target")
    eq(got, dur, "durata passata alla barra")
    UnitCastingDuration = nil
    noErrors()
end)

case("castbar: colore interrompibile / non interrompibile", function(Mock)
    local UF = start(Mock)
    Env.units.target.cast = { "Cura", "Cura", 1, 1000000, 1002000, false, "id", false }
    fire("UNIT_SPELLCAST_START", "target")
    local cast = UF.frames.target.Castbar
    local locked = 0.55
    fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    eq(cast.__bar[1], locked, "grigio")
    fire("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
    ok(cast.__bar[1] ~= locked, "accento")
end)

case("castbar disattivata: gli eventi di lancio non la mostrano", function(Mock)
    local UF = start(Mock)
    UF:Set("units.target.showCastbar", false)
    Env.units.target.cast = { "Cura", "Cura", 1, 1000000, 1002000, false, "id", false }
    fire("UNIT_SPELLCAST_START", "target")
    ok(not UF.frames.target.Castbar:IsShown(), "nascosta")
end)

case("aure: debuff prima dei buff, limite massimo, campi secret tollerati", function(Mock)
    local UF = start(Mock)
    Env.auras["target:HARMFUL"] = {
        { icon = 1, applications = 3, duration = 10, expirationTime = 1005, auraInstanceID = 11, dispelName = "Magic" },
        { icon = 2, applications = Mock.Secret(), duration = Mock.Secret(), expirationTime = Mock.Secret(),
          auraInstanceID = 12, dispelName = Mock.Secret() },
    }
    local buffs = {}
    for i = 1, 30 do buffs[i] = { icon = 100 + i, applications = 0, duration = 0, expirationTime = 0, auraInstanceID = 100 + i } end
    Env.auras["target:HELPFUL"] = buffs
    fire("UNIT_AURA", "target")
    local a = UF.frames.target.Auras
    local shown = 0
    for _, b in ipairs(a.buttons) do if b:IsShown() then shown = shown + 1 end end
    eq(shown, 12, "massimo 12 sul bersaglio")
    eq(a.buttons[1].Icon:GetTexture(), 1, "primo debuff")
    eq(a.buttons[1].Count:GetText(), 3, "stack")
    eq(a.buttons[3].Icon:GetTexture(), 101, "poi i buff")
    noErrors()
end)

case("aure: meno aure di prima nasconde i pulsanti in eccesso", function(Mock)
    local UF = start(Mock)
    Env.auras["target:HELPFUL"] = { { icon = 1, applications = 0, duration = 0, expirationTime = 0 },
                                    { icon = 2, applications = 0, duration = 0, expirationTime = 0 } }
    fire("UNIT_AURA", "target")
    Env.auras["target:HELPFUL"] = { { icon = 1, applications = 0, duration = 0, expirationTime = 0 } }
    fire("UNIT_AURA", "target")
    local a = UF.frames.target.Auras
    ok(a.buttons[1]:IsShown() and not a.buttons[2]:IsShown(), "solo una visibile")
end)

case("combattimento: un'opzione cambiata viene applicata solo all'uscita", function(Mock)
    local UF = start(Mock)
    enterCombat()
    UF:Set("units.player.width", 300)
    eq(UF.frames.player:GetWidth(), 220, "invariata in combattimento")
    noErrors("nessun ADDON_ACTION_BLOCKED")
    leaveCombat()
    eq(UF.frames.player:GetWidth(), 300, "applicata")
end)

case("combattimento: vita e icona di combattimento si aggiornano (elementi non protetti)", function(Mock)
    local UF = start(Mock)
    enterCombat()
    Env.units.player.health = 123
    fire("UNIT_HEALTH", "player")
    eq(UF.frames.player.Health:GetValue(), 123, "barra")
    ok(UF.frames.player.Combat:IsShown(), "icona combattimento")
    leaveCombat()
    ok(not UF.frames.player.Combat:IsShown(), "icona nascosta")
    noErrors()
end)

case("attivazione in combattimento: rimandata, nessun frame secure creato nel lockdown", function(Mock)
    setup(Mock)
    defaultUnits()
    Mock.combat = true
    local UF = enable()
    ok(not UF.spawned, "nessun frame creato")
    noErrors()
    leaveCombat()
    ok(UF.spawned, "creati all'uscita")
end)

case("anteprima: tutti i frame con dati finti, anche il gruppo da soli", function(Mock)
    local UF = start(Mock)
    UF:SetPreview(true)
    ok(UF.partyHeader:IsShown(), "gruppo visibile")
    eq(Env.drivers[UF.partyHeader], nil, "driver sospeso")
    eq(UF.frames.party1.Name:GetText(), "Compagno 1", "nome finto")
    ok(not Env.watch[UF.frames.focus], "watch sospeso")
    UF:SetPreview(false)
    ok(Env.watch[UF.frames.focus], "watch ripristinato")
    ok(Env.drivers[UF.partyHeader], "driver ripristinato")
end)

case("anteprima: il combattimento la chiude prima del lockdown", function(Mock)
    local UF = start(Mock)
    UF:SetPreview(true)
    enterCombat()
    leaveCombat()
    ok(not UF.previewing, "chiusa")
    ok(Env.watch[UF.frames.party1], "watch ripristinato")
    noErrors()
end)

case("anteprima rifiutata in combattimento o a modulo spento", function(Mock)
    local UF = start(Mock)
    Mock.combat = true
    UF:SetPreview(true)
    ok(not UF.previewing, "rifiutata in combattimento")
    Mock.combat = false
    BadbUI.Modules:SetEnabled("UnitFrames", false)
    UF:SetPreview(true)
    ok(not UF.previewing, "rifiutata a modulo spento")
end)

case("gruppo: sfuma i fuori portata, anche con portata secret", function(Mock)
    local UF = start(Mock)
    Env.units.party1 = { name = "Lontano", health = 1, healthMax = 1, inRange = false, rangeChecked = true }
    Env.units.party2 = { name = "Vicino", health = 1, healthMax = 1, inRange = true, rangeChecked = true }
    Env.units.party3 = { name = "Opaco", health = 1, healthMax = 1, inRange = Mock.Secret(), rangeChecked = Mock.Secret() }
    UF.partyHeader.__shown = true
    for i = 1, 3 do api(UF.party[i], "SetAlphaFromBoolean") end
    tick()
    eq(UF.party[1]:GetAlpha(), 0.45, "fuori portata")
    eq(UF.party[2]:GetAlpha(), 1, "in portata")
    eq(UF.party[3]:GetAlpha(), 1, "secret senza SetAlphaFromBoolean")
    noErrors()
end)

case("gruppo: con SetAlphaFromBoolean la portata secret e' delegata al client", function(Mock)
    local UF = start(Mock)
    local got
    api(UF.party[1], "SetAlphaFromBoolean", function(self, b, yes, no) got = { b, yes, no } end)
    local secret = Mock.Secret()
    Env.units.party1 = { name = "Opaco", health = 1, healthMax = 1, inRange = secret, rangeChecked = Mock.Secret() }
    UF.partyHeader.__shown = true
    tick()
    ok(got and got[1] == secret and got[3] == 0.45, "delegato con alpha fuori portata")
end)

case("gruppo: evidenzia il membro che e' il mio bersaglio", function(Mock)
    local UF = start(Mock)
    UF.partyHeader.__shown = true
    UnitIsUnit = function(a, b) return a == "party2" and b == "target" end
    fire("PLAYER_TARGET_CHANGED")
    local accent = UF.party[2].badbBorder[1].__vc
    local normal = UF.party[1].badbBorder[1].__vc
    ok(accent[1] ~= normal[1], "bordo d'accento solo su party2")
end)

case("gruppo: layout verticale/orizzontale e opzione incursione", function(Mock)
    local UF = start(Mock)
    local p2 = UF.party[2]
    local _, rel, relPoint = p2:GetPoint(1)
    eq(rel, UF.party[1], "ancorato al precedente")
    eq(relPoint, "BOTTOMLEFT", "verticale")
    UF:Set("units.party.vertical", false)
    _, rel, relPoint = p2:GetPoint(1)
    eq(relPoint, "TOPRIGHT", "orizzontale")
    UF:Set("units.party.showInRaid", true)
    eq(Env.drivers[UF.partyHeader], "[group] show; hide", "driver incursione")
end)

case("disattivare un'unita' ripristina il suo frame Blizzard", function(Mock)
    local UF = start(Mock)
    UF:Set("units.focus.enabled", false)
    eq(FocusFrame:GetParent(), UIParent, "FocusFrame tornato")
    ok(not UF.frames.focus:IsShown(), "frame BadbUI nascosto")
    ok(not Env.watch[UF.frames.focus], "watch rimosso")
    UF:Set("units.focus.enabled", true)
    ok(FocusFrame:GetParent() ~= UIParent, "di nuovo nascosto")
end)

case("hideBlizzard spento lascia visibile il frame Blizzard", function(Mock)
    local UF = start(Mock)
    UF:Set("units.player.hideBlizzard", false)
    eq(PlayerFrame:GetParent(), UIParent, "visibile")
end)

case("config malformata (import corrotto): riparata senza errori", function(Mock)
    local UF = start(Mock)
    local units = UF:Get("units")
    units.player.width = "enorme"
    units.player.height = 0 / 0
    units.player.showName = "si"
    units.target.width = 99999
    units.focus = "rotto"
    UF:Apply()
    noErrors()
    eq(UF.frames.player:GetWidth(), 220, "default al posto di una stringa")
    eq(UF.frames.player:GetHeight(), 44, "default al posto di NaN")
    eq(UF:Get("units.player.showName"), true, "booleano ripristinato")
    eq(UF.frames.target:GetWidth(), 400, "limitato al massimo")
    eq(type(UF:Get("units.focus")), "table", "unita' ricostruita")
end)

case("cambio profilo in combattimento: applicato all'uscita", function(Mock)
    local UF = start(Mock)
    BadbUI.DB:CopyProfile("Default", "Raid")
    BadbUI.DB.sv.profiles.Raid.modules.UnitFrames.units.target.width = 260
    enterCombat()
    BadbUI.DB:SetProfile("Raid")
    eq(UF.frames.target:GetWidth(), 220, "invariato in combattimento")
    leaveCombat()
    eq(UF.frames.target:GetWidth(), 260, "profilo applicato")
    noErrors()
end)

case("cambio profilo verso un profilo con il modulo spento: tutto ripristinato", function(Mock)
    local UF = start(Mock)
    BadbUI.DB:CopyProfile("Default", "Vanilla")
    BadbUI.DB.sv.profiles.Vanilla.modules.UnitFrames.enabled = false
    BadbUI.DB:SetProfile("Vanilla")
    ok(not UF.enabled, "spento")
    eq(PlayerFrame:GetParent(), UIParent, "PlayerFrame ripristinato")
    noErrors()
end)

case("cambio tema: i frame vengono ri-skinnati", function(Mock)
    local UF = start(Mock)
    BadbUI.Theme = { Get = function(_, key) if key == "bg" then return 0.1, 0.2, 0.3, 1 end end }
    BadbUI.Events:Fire("BADB_THEME_CHANGED")
    eq(UF.frames.player.badbBg.__vc[2], 0.2, "colore dal tema")
    BadbUI.Theme = nil
end)

case("tema che lancia errori: si usa la palette di riserva", function(Mock)
    local UF = start(Mock)
    BadbUI.Theme = { Get = function() error("rotto") end, textures = {}, fonts = {} }
    BadbUI.Events:Fire("BADB_THEME_CHANGED")
    noErrors()
    ok(UF.frames.player.badbBg.__vc[1] < 0.2, "fondo notturno di riserva")
    BadbUI.Theme = nil
end)

case("disattivare il modulo in combattimento: rimandato, poi tutto ripristinato", function(Mock)
    local UF = start(Mock)
    enterCombat()
    BadbUI.Modules:SetEnabled("UnitFrames", false)
    ok(TargetFrame:GetParent() ~= UIParent, "ancora nascosto")
    leaveCombat()
    eq(TargetFrame:GetParent(), UIParent, "TargetFrame")
    eq(PartyFrame:GetParent(), UIParent, "PartyFrame")
    ok(not UF.frames.player:IsShown(), "frame nascosti")
    ok(not Env.watch[UF.frames.target], "nessun watch residuo")
    eq(Env.drivers[UF.partyHeader], nil, "nessun driver residuo")
    ok(Env.tickers[1].cancelled, "ticker fermato")
    noErrors()
end)

case("riattivare non ricrea i frame (nessun nome globale duplicato)", function(Mock)
    local UF = start(Mock)
    local before = UF.frames.player
    BadbUI.Modules:SetEnabled("UnitFrames", false)
    BadbUI.Modules:SetEnabled("UnitFrames", true)
    eq(UF.frames.player, before, "stesso frame")
    ok(UF.frames.player:IsShown(), "visibile")
    noErrors()
end)

case("posizioni gestite dal FrameManager: chiavi registrate e movibili", function(Mock)
    start(Mock)
    local FM = BadbUI.FrameManager
    for _, k in ipairs({ "UF_player", "UF_target", "UF_targettarget", "UF_focus", "UF_party" }) do
        ok(FM.registry[k], "registrato " .. k)
    end
end)

case("comandi /badb uf: reset di un'unita' e argomenti errati", function(Mock)
    local UF = start(Mock)
    UF:Set("units.target.width", 333)
    UF:Command("reset target")
    eq(UF:Get("units.target.width"), 220, "default ripristinati")
    UF:Command("reset inesistente")
    UF:Command(nil)
    UF:Command("preview")
    ok(UF.previewing, "anteprima da comando")
    noErrors()
end)

case("opzioni: il selettore cambia l'unita' modificata senza riapplicare", function(Mock)
    local UF = start(Mock)
    local widthOpt
    for _, o in ipairs(UF.options) do if o.label == "Larghezza" then widthOpt = o end end
    eq(widthOpt.get(), 220, "player")
    UF:Set("editUnit", "focus")
    eq(widthOpt.get(), 180, "focus")
    widthOpt.set(190)
    eq(UF.frames.focus:GetWidth(), 190, "applicato al focus")
    local auraOpt
    for _, o in ipairs(UF.options) do if o.label == "Aure" and o.type == "toggle" then auraOpt = o end end
    ok(not auraOpt.hidden(), "aure visibili per il focus")
    UF:Set("editUnit", "player")
    ok(auraOpt.hidden(), "aure nascoste per il giocatore")
    UF:Set("editUnit", "sconosciuta")
    eq(widthOpt.get(), 220, "valore sconosciuto => player")
end)

case("icona combattimento sul bersaglio: normale, secret delegato, secret senza API", function(Mock)
    local UF = start(Mock)
    UnitAffectingCombat = function(u) return u == "target" end
    fire("UNIT_FLAGS", "target")
    ok(UF.frames.target.Combat:IsShown(), "bersaglio in combattimento")
    UnitAffectingCombat = function() return false end
    fire("UNIT_FLAGS", "target")
    ok(not UF.frames.target.Combat:IsShown(), "fuori combattimento")
    local secret = Mock.Secret()
    UnitAffectingCombat = function() return secret end
    api(UF.frames.target.Combat, "SetAlphaFromBoolean")
    fire("UNIT_FLAGS", "target")
    ok(not UF.frames.target.Combat:IsShown(), "secret senza SetAlphaFromBoolean: nascosta")
    local got
    api(UF.frames.target.Combat, "SetAlphaFromBoolean", function(_, b, yes, no) got = { b, yes, no } end)
    fire("UNIT_FLAGS", "target")
    ok(UF.frames.target.Combat:IsShown() and got[1] == secret and got[3] == 0, "delegato al client")
    noErrors()
end)

case("icona di classe solo per i giocatori con classe leggibile", function(Mock)
    local UF = start(Mock)
    CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }
    UF:Set("units.target.showClassIcon", true)
    ok(not UF.frames.target.ClassIcon:IsShown(), "PNG: nessuna icona")
    Env.units.target = { name = "Mago", health = 1, healthMax = 1, isPlayer = true, class = "MAGE" }
    fire("PLAYER_TARGET_CHANGED")
    ok(UF.frames.target.ClassIcon:IsShown(), "giocatore: icona")
    eq(UF.frames.target.ClassIcon.__texcoord[1], 0.25, "coordinate della classe")
    Env.units.target.class = Mock.Secret()
    fire("PLAYER_TARGET_CHANGED")
    ok(not UF.frames.target.ClassIcon:IsShown(), "classe secret: nascosta")
    noErrors()
end)

case("aura grande: CC curato al centro, priorita' e opzione", function(Mock)
    local UF = start(Mock)
    local f = UF.frames.target
    Env.auras["target:HARMFUL"] = { { spellId = 116, icon = 7, applications = 0, duration = 5, expirationTime = 105, auraInstanceID = 1 },
                                    { spellId = 118, icon = 8, applications = 0, duration = 8, expirationTime = 108, auraInstanceID = 2 } }
    Env.auras["target:HELPFUL"] = { { spellId = 871, icon = 9, applications = 0, duration = 10, expirationTime = 110, auraInstanceID = 3 } }
    fire("UNIT_AURA", "target")
    ok(f.BigAura and f.BigAura:IsShown(), "aura grande visibile")
    eq(f.BigAura.icon:GetTexture(), 8, "Polymorph batte difensivi e rallentamenti")
    Env.auras["target:HARMFUL"] = {}
    fire("UNIT_AURA", "target")
    eq(f.BigAura.icon:GetTexture(), 9, "poi il difensivo")
    Env.auras["target:HELPFUL"] = {}
    fire("UNIT_AURA", "target")
    ok(not f.BigAura:IsShown(), "niente di curato: nascosta")
    Env.auras["target:HARMFUL"] = { { spellId = 118, icon = 8, applications = 0, duration = Mock.Secret(),
                                      expirationTime = Mock.Secret(), auraInstanceID = 2 } }
    fire("UNIT_AURA", "target")
    ok(f.BigAura:IsShown(), "durate secret tollerate")
    UF:Set("units.target.showBigAura", false)
    fire("UNIT_AURA", "target")
    ok(not f.BigAura:IsShown(), "opzione spenta")
    noErrors()
end)

case("aura grande: database Auras spento, nessun errore", function(Mock)
    local UF = start(Mock)
    Env.auras["target:HARMFUL"] = { { spellId = 118, icon = 8, applications = 0, duration = 8, expirationTime = 108, auraInstanceID = 2 } }
    BadbUI.Modules:SetEnabled("Auras", false)
    fire("UNIT_AURA", "target")
    ok(not (UF.frames.target.BigAura and UF.frames.target.BigAura:IsShown()), "nascosta")
    noErrors()
end)

return T
