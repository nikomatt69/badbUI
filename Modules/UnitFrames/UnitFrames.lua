-- BadbUI - Unit Frames
-- Frame propri per giocatore, bersaglio, bersaglio del bersaglio, focus e gruppo, costruiti su
-- SecureUnitButtonTemplate (click = bersaglio, destro = menu, compatibili Clique).
--
-- Regole di combattimento (Forever):
--   * I bottoni secure si creano, ridimensionano e ancorano SOLO fuori combattimento: ogni
--     applicazione della config passa da Events:RunOutOfCombat("uf:apply").
--   * La visibilita' in combattimento e' affidata al client: RegisterUnitWatch per le unita'
--     e RegisterStateDriver("visibility") per il contenitore del gruppo. Nessuno snippet secure.
--   * Posizione e scala sono gestite dal FrameManager (chiavi "UF_<unita'>"): /badb unlock
--     mostra le maniglie, tasto destro ripristina la posizione predefinita.
--   * I frame Blizzard vengono nascosti riparentandoli a un frame nascosto (mai SetPoint sui frame
--     Edit Mode) e ripristinati al disable.
local _, ns = ...
local Badb = ns.Badb
local Events, Logger, Compat, FM = Badb.Events, Badb.Logger, Badb.Compat, Badb.FrameManager

local UF = ns.UF
local E, Style = UF.Elements, UF.Style

---------------------------------------------------------------------------
-- Default
---------------------------------------------------------------------------
local BASE = {
    enabled = true, hideBlizzard = true,
    width = 200, height = 40, powerHeight = 7, fontSize = 11,
    showPower = true, showName = true, showLevel = false,
    showHealthValue = true, showHealthPercent = true, showPowerText = false,
    classColor = true, reactionColor = true,
    showCastbar = false, castbarHeight = 16, castbarGap = 6,
    showAuras = false, auraSize = 20, auraMax = 8, auraOnlyMine = false, showBigAura = false,
    showLeader = false, showCombat = false, highlightTarget = false, showClassIcon = false,
}

local function with(over)
    local t = Badb.CopyTable(BASE)
    for k, v in pairs(over) do t[k] = v end
    return t
end

local UNITS = {
    { key = "player", unit = "player", title = "Giocatore",
      defaults = with({ width = 220, height = 44, powerHeight = 8, showPowerText = true, showCastbar = true,
                        castbarHeight = 18, showLeader = true, showCombat = true, reactionColor = false }),
      point = { "CENTER", -290, -170 } },
    { key = "target", unit = "target", title = "Bersaglio",
      defaults = with({ width = 220, height = 44, powerHeight = 8, showLevel = true, showCastbar = true,
                        castbarHeight = 18, showAuras = true, auraMax = 12, showCombat = true, showBigAura = true }),
      point = { "CENTER", 290, -170 } },
    { key = "targettarget", unit = "targettarget", title = "Bersaglio del bersaglio",
      defaults = with({ width = 120, height = 22, powerHeight = 0, showPower = false, showHealthValue = false,
                        fontSize = 10 }),
      point = { "CENTER", 460, -205 } },
    { key = "focus", unit = "focus", title = "Focus",
      defaults = with({ width = 180, height = 34, powerHeight = 5, showCastbar = true, showAuras = true,
                        auraMax = 6, auraOnlyMine = true, auraSize = 18, showCombat = true, showBigAura = true }),
      point = { "CENTER", -290, -60 } },
    { key = "party", unit = "party", title = "Gruppo",
      defaults = with({ width = 160, height = 36, powerHeight = 5, showHealthValue = false, showLeader = true,
                        highlightTarget = true, spacing = 10, vertical = true, showInRaid = false,
                        rangeFade = true, rangeAlpha = 0.45, showBigAura = true }),
      point = { "LEFT", 40, 120 } },
}
local UNIT_BY_KEY = {}
for _, u in ipairs(UNITS) do UNIT_BY_KEY[u.key] = u end

-- Frame Blizzard sostituiti da ciascuna unita' (quelli assenti sul client vengono ignorati).
local BLIZZARD = {
    player = { "PlayerFrame" },
    target = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    focus = { "FocusFrame" },
    party = { "PartyFrame", "CompactPartyFrame", "PartyMemberFrame1", "PartyMemberFrame2",
              "PartyMemberFrame3", "PartyMemberFrame4" },
}

---------------------------------------------------------------------------
-- Opzioni (descrittori per Config/Widgets)
-- Un solo set di controlli + selettore dell'unita' da modificare: la pagina resta corta e
-- leggibile invece di ripetere 20 controlli per 5 unita'.
---------------------------------------------------------------------------
local M -- definito sotto

local UNIT_CHOICES = {}
for _, u in ipairs(UNITS) do UNIT_CHOICES[#UNIT_CHOICES + 1] = { value = u.key, label = u.title } end

local function editKey()
    local k = M and M:Get("editUnit")
    return UNIT_BY_KEY[k] and k or "player"
end

-- Opzione legata al campo `field` dell'unita' selezionata; `only` limita le unita' a cui si applica.
local function unitOpt(o, only)
    local field = o.field
    o.field = nil
    o.get = function() return M:Get("units." .. editKey() .. "." .. field) end
    o.set = function(v) M:Set("units." .. editKey() .. "." .. field, v) end
    if only then
        local set = {}
        for _, k in ipairs(only) do set[k] = true end
        o.hidden = function() return not set[editKey()] end
    end
    return o
end

local WITH_AURAS = { "target", "focus", "party" }
local WITH_CAST = { "player", "target", "focus", "party" }
local options = {
    { type = "execute", label = "Anteprima on/off", func = function() M:TogglePreview() end,
      tooltip = "Mostra tutti i frame con dati finti, anche gruppo e focus, per configurarli da soli." },
    { type = "execute", label = "Sposta i frame", func = function() Badb.FrameManager:SetUnlocked(not Badb.FrameManager.unlocked) end,
      tooltip = "Come /badb unlock: trascina le maniglie, tasto destro ripristina la posizione." },
    { type = "select", path = "editUnit", label = "Unita' da modificare", values = UNIT_CHOICES },
    { type = "header", label = "Generale" },
    unitOpt({ type = "toggle", field = "enabled", label = "Attivo" }),
    unitOpt({ type = "toggle", field = "hideBlizzard", label = "Nascondi il frame Blizzard" }),
    unitOpt({ type = "range", field = "width", label = "Larghezza", min = 60, max = 400, step = 1 }),
    unitOpt({ type = "range", field = "height", label = "Altezza", min = 14, max = 90, step = 1 }),
    unitOpt({ type = "range", field = "powerHeight", label = "Barra risorsa (0 = nascosta)", min = 0, max = 20, step = 1 }),
    unitOpt({ type = "range", field = "fontSize", label = "Dimensione testo", min = 8, max = 18, step = 1 }),
    { type = "header", label = "Testi e colori" },
    unitOpt({ type = "toggle", field = "showName", label = "Nome" }),
    unitOpt({ type = "toggle", field = "showLevel", label = "Livello" }, { "target", "focus" }),
    unitOpt({ type = "toggle", field = "showHealthValue", label = "Vita: valore" }),
    unitOpt({ type = "toggle", field = "showHealthPercent", label = "Vita: percentuale" }),
    unitOpt({ type = "toggle", field = "showPowerText", label = "Valore risorsa" }),
    unitOpt({ type = "toggle", field = "classColor", label = "Colore di classe" }),
    unitOpt({ type = "toggle", field = "reactionColor", label = "Colore per reazione (PNG)" }),
    unitOpt({ type = "toggle", field = "showClassIcon", label = "Icona di classe (giocatori)" }),
    unitOpt({ type = "toggle", field = "showCombat", label = "Icona di combattimento" }, { "player", "target", "focus" }),
    unitOpt({ type = "toggle", field = "showLeader", label = "Icona capogruppo" }, { "player", "party" }),
    { type = "header", label = "Barra di lancio", hidden = function() return editKey() == "targettarget" end },
    unitOpt({ type = "toggle", field = "showCastbar", label = "Barra di lancio" }, WITH_CAST),
    unitOpt({ type = "range", field = "castbarHeight", label = "Altezza barra di lancio", min = 8, max = 32, step = 1 }, WITH_CAST),
    { type = "header", label = "Aure", hidden = function() return editKey() ~= "target" and editKey() ~= "focus" and editKey() ~= "party" end },
    unitOpt({ type = "toggle", field = "showAuras", label = "Aure" }, WITH_AURAS),
    unitOpt({ type = "range", field = "auraSize", label = "Dimensione aure", min = 12, max = 40, step = 1 }, WITH_AURAS),
    unitOpt({ type = "range", field = "auraMax", label = "Numero massimo aure", min = 1, max = 24, step = 1 }, WITH_AURAS),
    unitOpt({ type = "toggle", field = "auraOnlyMine", label = "Solo i miei debuff" }, WITH_AURAS),
    unitOpt({ type = "toggle", field = "showBigAura", label = "Aura grande al centro (CC, immunita', difensivi)" }, WITH_AURAS),
    { type = "header", label = "Gruppo", hidden = function() return editKey() ~= "party" end },
    unitOpt({ type = "toggle", field = "vertical", label = "Disposizione verticale" }, { "party" }),
    unitOpt({ type = "range", field = "spacing", label = "Spaziatura", min = 0, max = 40, step = 1 }, { "party" }),
    unitOpt({ type = "toggle", field = "showInRaid", label = "Mostra anche in incursione" }, { "party" }),
    unitOpt({ type = "toggle", field = "highlightTarget", label = "Evidenzia il mio bersaglio" }, { "party" }),
    unitOpt({ type = "toggle", field = "rangeFade", label = "Sfuma fuori portata" }, { "party" }),
    unitOpt({ type = "range", field = "rangeAlpha", label = "Trasparenza fuori portata", min = 0.1, max = 1, step = 0.05 }, { "party" }),
}

-- Disattivato di default come gli altri moduli che sostituiscono frame Blizzard:
-- lo attivano il wizard, un preset o l'utente.
local defaults = { enabled = false, editUnit = "player", units = {} }
for _, u in ipairs(UNITS) do defaults.units[u.key] = u.defaults end

M = Badb.Modules:New("UnitFrames", {
    title = "Unit frame",
    category = "Unit Frames",
    description = "Frame propri per giocatore, bersaglio, focus e gruppo: secure, combat-safe, compatibili con i secret values.",
    defaults = defaults,
    options = options,
    page = { title = "Unit frame", order = 30, category = "Interfaccia",
             keywords = { "player", "target", "focus", "party", "castbar", "aure", "giocatore", "bersaglio", "gruppo" } },
    commands = {
        uf = { help = "uf preview | unlock | reset <unita'>", fn = function(args) M:Command(args) end },
    },
})
Badb.UnitFrames = M -- API pubblica: M.frames[unitToken] -> frame
M.frames, M.party = {}, {}

-- Limiti per i campi numerici: un profilo importato o corrotto non deve mai rompere il layout.
local LIMITS = {
    width = { 60, 400 }, height = { 14, 90 }, powerHeight = { 0, 20 }, fontSize = { 8, 18 },
    castbarHeight = { 8, 32 }, castbarGap = { 0, 30 }, auraSize = { 12, 40 }, auraMax = { 0, 24 },
    spacing = { 0, 40 }, rangeAlpha = { 0.1, 1 },
}

-- Restituisce la config dell'unita', riparata in place se malformata (tipi sbagliati, fuori limite).
local function conf(key)
    local units = M:Get("units")
    if type(units) ~= "table" then
        M:Set("units", {}); units = M:Get("units")
    end
    local c = units[key]
    local def = UNIT_BY_KEY[key].defaults
    if type(c) ~= "table" then
        c = Badb.CopyTable(def)
        units[key] = c
    end
    for field, dv in pairs(def) do
        local v = c[field]
        if type(dv) == "number" then
            v = tonumber(v)
            if not v or v ~= v then v = dv end -- nil, stringhe non numeriche, NaN
            local lim = LIMITS[field]
            if lim then v = math.max(lim[1], math.min(lim[2], v)) end
            c[field] = v
        elseif type(dv) == "boolean" and type(v) ~= "boolean" then
            c[field] = dv
        end
    end
    return c
end
M.GetUnitConfig = function(_, key) return UNIT_BY_KEY[key] and conf(key) end

---------------------------------------------------------------------------
-- Eventi per frame
---------------------------------------------------------------------------
local UNIT_EVENTS = {
    UNIT_HEALTH = E.UpdateHealth, UNIT_MAXHEALTH = E.UpdateHealth, UNIT_CONNECTION = E.UpdateAll,
    UNIT_FLAGS = function(f) E.UpdateHealth(f); E.UpdateIndicators(f) end, UNIT_FACTION = E.UpdateHealth,
    UNIT_POWER_UPDATE = E.UpdatePower, UNIT_POWER_FREQUENT = E.UpdatePower,
    UNIT_MAXPOWER = E.UpdatePower, UNIT_DISPLAYPOWER = E.UpdatePower,
    UNIT_NAME_UPDATE = E.UpdateName, UNIT_LEVEL = E.UpdateName,
    UNIT_AURA = E.UpdateAllAuras,
    UNIT_SPELLCAST_START = function(f) E.StartCast(f, false) end,
    UNIT_SPELLCAST_DELAYED = function(f) E.StartCast(f, false) end,
    UNIT_SPELLCAST_CHANNEL_START = function(f) E.StartCast(f, true) end,
    UNIT_SPELLCAST_CHANNEL_UPDATE = function(f) E.StartCast(f, true) end,
    UNIT_SPELLCAST_STOP = E.StopCast, UNIT_SPELLCAST_FAILED = E.StopCast,
    UNIT_SPELLCAST_INTERRUPTED = E.StopCast, UNIT_SPELLCAST_CHANNEL_STOP = E.StopCast,
    UNIT_SPELLCAST_INTERRUPTIBLE = function(f) E.SetCastInterruptible(f, true) end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(f) E.SetCastInterruptible(f, false) end,
}

local GLOBAL_EVENTS = {
    PLAYER_ENTERING_WORLD = E.UpdateAll,
    GROUP_ROSTER_UPDATE = E.UpdateAll,
    RAID_TARGET_UPDATE = E.UpdateIndicators,
    PARTY_LEADER_CHANGED = E.UpdateIndicators,
    -- REGEN_DISABLED arriva un attimo prima che UnitAffectingCombat diventi vero: forziamo lo stato.
    PLAYER_REGEN_DISABLED = function(f) if f.unit == "player" then f.Combat:SetShown(f.conf.showCombat and true or false) end end,
    PLAYER_REGEN_ENABLED = function(f) if f.unit == "player" then f.Combat:Hide() end end,
}
local CHANGE_EVENT = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED", targettarget = "PLAYER_TARGET_CHANGED" }

local errors = {}
local function onEvent(f, event, ...)
    if f.preview then return end
    local fn = UNIT_EVENTS[event] or GLOBAL_EVENTS[event]
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UNIT_TARGET" then
        fn = E.UpdateAll
    end
    if not fn or not UnitExists(f.unit) then return end
    local ok, err = pcall(fn, f)
    if not ok and not errors[event] then
        errors[event] = true -- un solo messaggio per evento, niente spam in combattimento
        Logger:Error("UnitFrames %s (%s): %s", f.unit, event, err)
    end
end

local function registerEvents(f)
    f:UnregisterAllEvents()
    local unitToken = f.unit
    if unitToken ~= "targettarget" then
        for event in pairs(UNIT_EVENTS) do pcall(f.RegisterUnitEvent, f, event, unitToken) end
    else
        pcall(f.RegisterUnitEvent, f, "UNIT_TARGET", "target")
    end
    for event in pairs(GLOBAL_EVENTS) do pcall(f.RegisterEvent, f, event) end
    local change = CHANGE_EVENT[unitToken]
    if change then f:RegisterEvent(change) end
    if f.isParty then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
end

---------------------------------------------------------------------------
-- Creazione (solo fuori combattimento)
---------------------------------------------------------------------------
local function spawn(name, unitToken, parent, c)
    local f = CreateFrame("Button", name, parent or UIParent, "SecureUnitButtonTemplate")
    f.unit, f.conf = unitToken, c
    f:SetAttribute("unit", unitToken)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetScript("OnEnter", function(self)
        if UnitFrame_OnEnter then UnitFrame_OnEnter(self)
        else GameTooltip_SetDefaultAnchor(GameTooltip, self); GameTooltip:SetUnit(self.unit); GameTooltip:Show() end
    end)
    f:SetScript("OnLeave", function(self)
        if UnitFrame_OnLeave then UnitFrame_OnLeave(self) else GameTooltip:Hide() end
    end)
    f:SetScript("OnEvent", onEvent)
    f:SetScript("OnShow", function(self) pcall(E.UpdateAll, self) end)
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    _G.ClickCastFrames[f] = true
    E.Build(f)
    return f
end

local function ensureFrames()
    if M.spawned then return end
    for _, u in ipairs(UNITS) do
        local c = conf(u.key)
        if u.key == "party" then
            local header = CreateFrame("Frame", "BadbUF_Party", UIParent)
            header:SetSize(1, 1)
            M.partyHeader = header
            for i = 1, 4 do
                local f = spawn("BadbUF_Party" .. i, "party" .. i, header, c)
                f.isParty = true
                f.previewName = "Compagno " .. i
                f.previewSeed = i + 1
                M.party[i] = f
                M.frames["party" .. i] = f
            end
        else
            local f = spawn("BadbUF_" .. u.key, u.unit, UIParent, c)
            f.previewName = u.title
            f.previewSeed = #M.frames + 1
            M.frames[u.unit] = f
        end
        local anchor = u.key == "party" and M.partyHeader or M.frames[u.unit]
        anchor:SetPoint(unpack(u.point))
        FM:Register("UF_" .. u.key, { frame = anchor, title = "Unit frame: " .. u.title, category = "Unit Frames" })
    end
    M.spawned = true
end

---------------------------------------------------------------------------
-- Frame Blizzard
---------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local reparented = {}

-- I Compact party frame appartengono al modulo GroupFrames quando e' attivo: non li tocchiamo.
local function ownedElsewhere(name)
    if name ~= "CompactPartyFrame" then return false end
    local gf = Badb.Modules:Get("GroupFrames")
    return gf and gf.enabled and true or false
end

local function setBlizzardHidden(key, hidden)
    for _, name in ipairs(BLIZZARD[key]) do
        local f = _G[name]
        if hidden and ownedElsewhere(name) then f = nil end
        if f then
            if hidden and not reparented[name] then
                reparented[name] = f:GetParent() or UIParent
                f:SetParent(hiddenParent)
            elseif not hidden and reparented[name] then
                f:SetParent(reparented[name])
                reparented[name] = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Applicazione della config
---------------------------------------------------------------------------
local PARTY_VISIBILITY = "[group:raid] hide; [group:party] show; hide"
local PARTY_VISIBILITY_RAID = "[group] show; hide"

local function activate(f, c, watch)
    f.conf = c
    E.Layout(f, c)
    registerEvents(f)
    if watch then RegisterUnitWatch(f) else f:Show() end
    pcall(E.UpdateAll, f)
end

local function deactivate(f, watch)
    f:UnregisterAllEvents()
    if watch then UnregisterUnitWatch(f) end
    f:Hide()
end

local function layoutParty(c)
    local header = M.partyHeader
    local gap = c.spacing or 10
    for i, f in ipairs(M.party) do
        f:SetSize(c.width, c.height)
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("TOPLEFT", header, "TOPLEFT")
        elseif c.vertical then
            -- spazio extra per castbar sotto / aure sopra
            local extra = (c.showCastbar and (c.castbarHeight + (c.castbarGap or 6)) or 0)
                + (c.showAuras and (c.auraSize + 4) or 0)
            f:SetPoint("TOPLEFT", M.party[i - 1], "BOTTOMLEFT", 0, -(gap + extra))
        else
            f:SetPoint("TOPLEFT", M.party[i - 1], "TOPRIGHT", gap, 0)
        end
    end
    local n = 4
    if c.vertical then
        header:SetSize(c.width, c.height * n + gap * (n - 1))
    else
        header:SetSize(c.width * n + gap * (n - 1), c.height)
    end
end

function M:Apply()
    if InCombatLockdown() then
        Events:RunOutOfCombat("uf:apply", function() M:Apply() end)
        return
    end
    -- OnEnable gira prima che Modules imposti m.enabled: usiamo un flag proprio.
    if not self.active then return end
    ensureFrames()
    for _, u in ipairs(UNITS) do
        local c = conf(u.key)
        if u.key == "party" then
            local header = M.partyHeader
            if c.enabled then
                layoutParty(c)
                for _, f in ipairs(M.party) do activate(f, c, true) end
                if not M.previewing then
                    RegisterStateDriver(header, "visibility", c.showInRaid and PARTY_VISIBILITY_RAID or PARTY_VISIBILITY)
                end
            else
                UnregisterStateDriver(header, "visibility")
                header:Hide()
                for _, f in ipairs(M.party) do deactivate(f, true) end
            end
        else
            local f = M.frames[u.unit]
            if c.enabled then
                f:SetSize(c.width, c.height)
                activate(f, c, u.unit ~= "player")
            else
                deactivate(f, u.unit ~= "player")
            end
        end
        setBlizzardHidden(u.key, c.enabled and c.hideBlizzard)
    end
    if M.previewing then M:SetPreview(true) end
end

---------------------------------------------------------------------------
-- Anteprima: mostra tutti i frame con dati finti per configurarli da soli
---------------------------------------------------------------------------
local function allFrames()
    local list = {}
    for _, u in ipairs(UNITS) do
        if u.key == "party" then
            for _, f in ipairs(M.party) do list[#list + 1] = { f = f, key = "party" } end
        else
            list[#list + 1] = { f = M.frames[u.unit], key = u.key }
        end
    end
    return list
end

function M:SetPreview(state)
    if InCombatLockdown() then Logger:Warn("Anteprima non disponibile in combattimento"); return end
    if not self.active or not self.spawned then
        if state then Logger:Warn("Attiva prima il modulo Unit frame") end
        return
    end
    M.previewing = state
    for _, entry in ipairs(allFrames()) do
        local f, c = entry.f, conf(entry.key)
        if c.enabled then
            if state then
                if f.unit ~= "player" then UnregisterUnitWatch(f) end
                f.preview = true
                f:Show()
                E.Preview(f)
            elseif f.preview then
                f.preview = false
                E.Layout(f, c) -- riporta castbar/aure allo stato reale
                if f.unit ~= "player" then RegisterUnitWatch(f) end
                pcall(E.UpdateAll, f)
            end
        end
    end
    local pc = conf("party")
    if pc.enabled then
        if state then
            UnregisterStateDriver(M.partyHeader, "visibility")
            M.partyHeader:Show()
        else
            RegisterStateDriver(M.partyHeader, "visibility", pc.showInRaid and PARTY_VISIBILITY_RAID or PARTY_VISIBILITY)
        end
    end
end

function M:TogglePreview() self:SetPreview(not M.previewing) end

---------------------------------------------------------------------------
-- Aggiornamenti periodici: bersaglio del bersaglio (nessun evento dedicato) e portata del gruppo
---------------------------------------------------------------------------
local function tick()
    local tot = M.frames.targettarget
    if tot and tot:IsVisible() and not tot.preview then pcall(E.UpdateAll, tot) end

    local c = conf("party")
    if not c.enabled then return end
    for _, f in ipairs(M.party) do
        if f:IsVisible() and not f.preview then
            if c.rangeFade then
                local inRange, checked = UnitInRange(f.unit)
                if Compat.IsSecret(inRange) and f.SetAlphaFromBoolean then
                    f:SetAlphaFromBoolean(inRange, 1, c.rangeAlpha)
                elseif not Compat.IsSecret(checked) and checked and not inRange then
                    f:SetAlpha(c.rangeAlpha)
                else
                    f:SetAlpha(1)
                end
            else
                f:SetAlpha(1)
            end
        end
    end
end

-- Evidenzia nel gruppo il membro che e' il mio bersaglio.
local function highlightPartyTarget()
    local c = conf("party")
    for _, f in ipairs(M.party) do
        local isTarget = c.highlightTarget and f:IsVisible() and Compat.SafeValue(UnitIsUnit(f.unit, "target"), false)
        Style.SetHighlight(f, isTarget and "accent" or nil)
    end
end

---------------------------------------------------------------------------
-- Comandi: /badb uf preview | unlock | reset <unita'>
---------------------------------------------------------------------------
function M:ResetUnit(key)
    local u = UNIT_BY_KEY[key]
    if not u then return false, "unita' sconosciuta" end
    M:Get("units")[key] = Badb.CopyTable(u.defaults)
    if FM.registry["UF_" .. key] then FM:Restore("UF_" .. key) end
    self:Apply()
    return true
end

function M:Command(args)
    local cmd, rest = strtrim(tostring(args or "")):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "preview" or cmd == "anteprima" then
        self:TogglePreview()
    elseif cmd == "unlock" then
        FM:SetUnlocked(not FM.unlocked)
    elseif cmd == "reset" then
        local ok, err = self:ResetUnit(rest ~= "" and rest or "")
        if ok then Logger:Info("Unit frame '%s' ripristinato", rest) else Logger:Warn("Reset: %s (%s)", err, rest) end
    else
        Logger:Info("/badb uf preview | unlock | reset <player|target|targettarget|focus|party>")
    end
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------
function M:OnEnable()
    self.active = true
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module == self.name and path ~= "editUnit" then self:Apply() end
    end)
    self:On("PLAYER_TARGET_CHANGED", highlightPartyTarget)
    self:On("GROUP_ROSTER_UPDATE", highlightPartyTarget)
    self:On("PLAYER_REGEN_DISABLED", function() if M.previewing then M:SetPreview(false) end end)
    Style.OnChange(self, function() self:Apply() end)
    self.ticker = C_Timer.NewTicker(0.2, tick)
    self:Apply()
end

function M:OnProfileChanged() self:Apply() end

function M:OnDisable()
    self.active = false
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    Events:RunOutOfCombat("uf:apply", function()
        if M.previewing then M:SetPreview(false) end
        if M.spawned then
            for _, entry in ipairs(allFrames()) do deactivate(entry.f, entry.f.unit ~= "player") end
            UnregisterStateDriver(M.partyHeader, "visibility")
            M.partyHeader:Hide()
        end
        for _, u in ipairs(UNITS) do setBlizzardHidden(u.key, false) end
    end)
end
