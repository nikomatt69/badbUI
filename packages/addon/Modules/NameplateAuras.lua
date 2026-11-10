-- BadbUI - NameplateAuras
-- Aure curate sulle nameplate Blizzard, al posto della fila di debuff generica:
--   * sopra la barra: i TUOI debuff (DoT, rallentamenti, maledizioni), curati per classe o tutti;
--   * a destra: il controllo piu' importante sull'unita' (stun/fear/poly > silence > root), grande;
--   * a sinistra: immunita', difensivi e offensivi attivi del nemico, "sta bevendo".
-- Tutto viene dalle API aure (Badb.Auras), non dal combat log che su Forever non esiste.
-- Le nameplate "forbidden" (amiche in istanza) non si toccano: GetNamePlateForUnit(unit, issecure())
-- le esclude. Disattivando il modulo si ripristinano le aure Blizzard.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat, Auras = Badb.Compat, Badb.Auras

local OWN_MODES = {
    { value = "curated", text = L["Curati per la mia classe"] },
    { value = "all", text = L["Tutti i miei debuff"] },
    { value = "off", text = L["Nessuno"] },
}
local FRIEND_MODES = {
    { value = "cc", text = L["Solo controllo (CC)"] },
    { value = "all", text = L["CC e difensivi"] },
    { value = "off", text = L["Niente"] },
}

-- Dove finisce ogni categoria sulla nameplate.
local SLOT_OF = {
    cc = "cc", silence = "cc", root = "cc",
    immunity = "buff", defensive = "buff", offensive = "buff", utility = "buff", drink = "buff",
    snare = "row", own = "row",
}

local M = Badb.Modules:New("NameplateAuras", {
    title = L["Aure sulle nameplate"],
    category = L["Combattimento"],
    description = L["CC grande a destra, difensivi e offensivi nemici a sinistra, i tuoi debuff sopra."],
    dependencies = { "Auras" },
    defaults = {
        enabled = false,
        ownDebuffs = "curated",
        friendly = "cc",
        categories = {
            immunity = true, cc = true, silence = true, root = true,
            defensive = true, offensive = true, utility = false, drink = true,
            snare = false, -- rallentamenti messi da altri (i tuoi sono gia' nei tuoi debuff)
        },
        ccSize = 30,
        buffSize = 24,
        ownSize = 20,
        maxBuffs = 3,
        maxOwn = 6,
        ownOffsetY = 16,
        spacing = 2,
        numbers = true,       -- numeri del countdown (disegnati dal client)
        hideBlizzard = true,  -- nasconde la fila di aure Blizzard mentre il modulo e' attivo
    },
})

M.options = {
    { type = "header", label = L["Cosa mostrare"] },
    { type = "select", path = "ownDebuffs", label = L["I miei debuff (sopra la barra)"], values = OWN_MODES },
    { type = "select", path = "friendly", label = L["Nameplate alleate"], values = FRIEND_MODES },
    { type = "toggle", path = "categories.cc", label = L["Controllo: stun, fear, polymorph, sleep"] },
    { type = "toggle", path = "categories.silence", label = L["Silence e disarm"] },
    { type = "toggle", path = "categories.root", label = "Root" },
    { type = "toggle", path = "categories.immunity", label = L["Immunita' (bolle, Ice Block)"] },
    { type = "toggle", path = "categories.defensive", label = L["Difensivi nemici"] },
    { type = "toggle", path = "categories.offensive", label = L["Offensivi nemici"] },
    { type = "toggle", path = "categories.drink", label = L["Sta bevendo"] },
    { type = "toggle", path = "categories.utility", label = L["Utilita' (Freedom, Fear Ward, Innervate)"] },
    { type = "toggle", path = "categories.snare", label = L["Rallentamenti messi da altri"] },
    { type = "header", label = L["Dimensioni"] },
    { type = "range", path = "ccSize", label = L["Icona CC"], min = 16, max = 48, step = 1 },
    { type = "range", path = "buffSize", label = L["Icone difensivi/offensivi"], min = 12, max = 40, step = 1 },
    { type = "range", path = "ownSize", label = L["Icone dei miei debuff"], min = 12, max = 36, step = 1 },
    { type = "range", path = "maxBuffs", label = L["Max difensivi/offensivi"], min = 0, max = 6, step = 1 },
    { type = "range", path = "maxOwn", label = L["Max miei debuff"], min = 0, max = 10, step = 1 },
    { type = "range", path = "ownOffsetY", label = L["Distanza dei miei debuff dalla barra"], min = 0, max = 40, step = 1 },
    { type = "range", path = "spacing", label = L["Spaziatura"], min = 0, max = 8, step = 1 },
    { type = "toggle", path = "numbers", label = L["Numeri del countdown"] },
    { type = "toggle", path = "hideBlizzard", label = L["Nascondi le aure Blizzard sulle nameplate"] },
}

------------------------------------------------------------------------------
-- Stato per nameplate
------------------------------------------------------------------------------
local plates = {}   -- [UnitFrame] = { unit, holder, cc, buffs = {}, row = {}, blizz = { [frame] = alpha } }
local unitToUF = {} -- [unit] = UnitFrame
M._plates, M._unitToUF = plates, unitToUF

local function healthBarOf(uf)
    return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
end

local function blizzardAuraFrames(uf)
    local list = {}
    for _, key in ipairs({ "BuffFrame", "AurasFrame", "DebuffFrame" }) do
        local f = uf[key]
        if type(f) == "table" and f.SetAlpha then list[#list + 1] = f end
    end
    return list
end

local function getPlate(unit)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit, issecure and issecure() or false)
    local uf = ok and plate and plate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return nil end
    return uf
end

local function ensureState(uf)
    local st = plates[uf]
    if st then return st end
    local anchor = healthBarOf(uf) or uf
    local holder = CreateFrame("Frame", nil, uf)
    holder:SetAllPoints(anchor)
    if holder.SetFrameLevel and anchor.GetFrameLevel then holder:SetFrameLevel((anchor:GetFrameLevel() or 1) + 5) end
    st = { holder = holder, anchor = anchor, buffs = {}, row = {}, blizz = {} }
    plates[uf] = st
    return st
end

local function icon(st, list, i)
    local f = list[i]
    if not f then
        f = Auras:CreateIcon(st.holder)
        list[i] = f
    end
    return f
end

------------------------------------------------------------------------------
-- Decisione: quali aure e dove
------------------------------------------------------------------------------
local function isEnemy(unit)
    local can = Compat.SafeValue(UnitCanAttack and UnitCanAttack("player", unit), nil)
    if can == nil then return true end -- sconosciuto: trattato da nemico (piu' informazioni, nessun rischio)
    return can == true
end

local function isPlayer(unit)
    return Compat.SafeValue(UnitIsUnit and UnitIsUnit(unit, "player"), false) == true
end

-- Ritorna { cc = voce|nil, buffs = {voci}, row = {voci} } senza toccare widget (testabile).
function M:Select(unit)
    local res = { buffs = {}, row = {} }
    local enemy = isEnemy(unit)
    local friendly = self:Get("friendly")
    if not enemy and friendly == "off" then return res, enemy end
    local cats = self:Get("categories") or {}
    local own = enemy and self:Get("ownDebuffs") or "off"
    local entries = Auras:Collect(unit, { own = own })
    local maxBuffs, maxOwn = self:Get("maxBuffs") or 3, self:Get("maxOwn") or 6
    for _, e in ipairs(entries) do
        local slot = SLOT_OF[e.category]
        local catOn = e.category == "own" or cats[e.category] == true
        if slot == "cc" and catOn then
            if not res.cc then
                res.cc = e
            elseif e.own and enemy and own ~= "off" and #res.row < maxOwn then
                res.row[#res.row + 1] = e -- un secondo CC tuo resta visibile sopra
            end
        elseif slot == "buff" and catOn and e.filter == "HELPFUL" then
            if (enemy or friendly == "all") and #res.buffs < maxBuffs then res.buffs[#res.buffs + 1] = e end
        elseif enemy and own ~= "off" and e.own and #res.row < maxOwn then
            res.row[#res.row + 1] = e -- i tuoi debuff (anche rallentamenti curati)
        elseif enemy and slot == "row" and e.category == "snare" and catOn and #res.row < maxOwn then
            res.row[#res.row + 1] = e
        end
    end
    -- La fila dei propri debuff in ordine stabile di applicazione (non per priorita'): niente salti.
    table.sort(res.row, function(a, b) return a.index < b.index end)
    return res, enemy
end

------------------------------------------------------------------------------
-- Disegno
------------------------------------------------------------------------------
local function hideFrom(list, first)
    for i = first, #list do Auras:ClearIcon(list[i]) end
end

local function hideBlizzard(self, uf, st)
    if not self:Get("hideBlizzard") then return end
    for _, f in ipairs(blizzardAuraFrames(uf)) do
        if st.blizz[f] == nil then st.blizz[f] = f.GetAlpha and f:GetAlpha() or 1 end
        f:SetAlpha(0)
    end
end

local function restoreBlizzard(st)
    for f, alpha in pairs(st.blizz) do
        if f.SetAlpha then f:SetAlpha(alpha) end
        st.blizz[f] = nil
    end
end

function M:UpdateUnit(unit)
    -- `running` e non `enabled`: Modules imposta enabled solo dopo OnEnable.
    if not self.running or type(unit) ~= "string" then return end
    local uf = getPlate(unit)
    if not uf then
        -- nameplate sparita o diventata forbidden: niente da disegnare
        local old = unitToUF[unit]
        if old then self:ReleasePlate(old) end
        return
    end
    local st = ensureState(uf)
    if st.unit and st.unit ~= unit and unitToUF[st.unit] == uf then unitToUF[st.unit] = nil end
    st.unit = unit
    unitToUF[unit] = uf

    if isPlayer(unit) then -- barra personale: niente aure nostre
        self:ClearPlate(uf)
        return
    end

    hideBlizzard(self, uf, st)
    local res = self:Select(unit)
    local numbers = self:Get("numbers") ~= false
    local spacing = self:Get("spacing") or 2
    local anchor = st.anchor

    -- Slot CC a destra
    if res.cc then
        st.cc = st.cc or Auras:CreateIcon(st.holder)
        local size = self:Get("ccSize")
        Auras:SetIcon(st.cc, res.cc, unit, { size = size, numbers = numbers })
        st.cc:ClearAllPoints()
        st.cc:SetPoint("LEFT", anchor, "RIGHT", spacing + 1, 0)
    elseif st.cc then
        Auras:ClearIcon(st.cc)
    end

    -- Difensivi/offensivi a sinistra, crescono verso sinistra
    local bsize = self:Get("buffSize")
    for i, e in ipairs(res.buffs) do
        local f = icon(st, st.buffs, i)
        Auras:SetIcon(f, e, unit, { size = bsize, numbers = numbers })
        f:ClearAllPoints()
        if i == 1 then f:SetPoint("RIGHT", anchor, "LEFT", -(spacing + 1), 0)
        else f:SetPoint("RIGHT", st.buffs[i - 1], "LEFT", -spacing, 0) end
    end
    hideFrom(st.buffs, #res.buffs + 1)

    -- I miei debuff sopra, centrati sulla barra
    local osize, n = self:Get("ownSize"), #res.row
    local width = n * osize + math.max(n - 1, 0) * spacing
    for i, e in ipairs(res.row) do
        local f = icon(st, st.row, i)
        Auras:SetIcon(f, e, unit, { size = osize, numbers = numbers, border = e.category ~= "own" })
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", anchor, "TOP", -width / 2 + (i - 1) * (osize + spacing), self:Get("ownOffsetY"))
    end
    hideFrom(st.row, n + 1)
    st.last = res
end

function M:ClearPlate(uf)
    local st = plates[uf]
    if not st then return end
    if st.cc then Auras:ClearIcon(st.cc) end
    hideFrom(st.buffs, 1)
    hideFrom(st.row, 1)
    restoreBlizzard(st)
    st.last = nil
end

function M:ReleasePlate(uf)
    local st = plates[uf]
    if not st then return end
    self:ClearPlate(uf)
    if st.unit and unitToUF[st.unit] == uf then unitToUF[st.unit] = nil end
    st.unit = nil
end

function M:UpdateAll()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local ok, list = pcall(C_NamePlate.GetNamePlates, issecure and issecure() or false)
    if not ok or type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then self:UpdateUnit(unit) end
    end
end

------------------------------------------------------------------------------
-- Aggiornamenti coalescati: UNIT_AURA arriva a raffica in BG, si ridisegna una volta per frame.
------------------------------------------------------------------------------
local pending, flushQueued = {}, false

local function flush()
    flushQueued = false
    local units = {}
    for unit in pairs(pending) do units[#units + 1] = unit end
    wipe(pending)
    for _, unit in ipairs(units) do M:UpdateUnit(unit) end
end
M._flush = flush

function M:Queue(unit)
    pending[unit] = true
    if not flushQueued then
        flushQueued = true
        Compat.After(0, flush)
    end
end

local function isPlateUnit(unit)
    return type(unit) == "string" and unit:sub(1, 9) == "nameplate"
end

------------------------------------------------------------------------------
-- Ciclo di vita
------------------------------------------------------------------------------
function M:OnEnable()
    self.running = true
    if not Auras:HasAuraAPI() then
        Badb.Logger:Warn(L["Aure sulle nameplate: il client non espone le API aure, modulo inattivo."])
    end
    self:On("NAME_PLATE_UNIT_ADDED", function(_, unit) self:UpdateUnit(unit) end)
    self:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        pending[unit] = nil
        local uf = unitToUF[unit]
        if uf then self:ReleasePlate(uf) end
    end)
    self:On("UNIT_AURA", function(_, unit) if isPlateUnit(unit) then self:Queue(unit) end end)
    self:On("UNIT_FACTION", function(_, unit) if isPlateUnit(unit) then self:Queue(unit) end end)
    self:On("BADB_AURAS_CHANGED", function() self:UpdateAll() end)
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module == self.name then
            if path == "hideBlizzard" and not self:Get("hideBlizzard") then
                for _, st in pairs(plates) do restoreBlizzard(st) end
            end
            self:UpdateAll()
        end
    end)
    self:UpdateAll()
end

function M:OnProfileChanged()
    if not self.running then return end
    for _, st in pairs(plates) do restoreBlizzard(st) end
    self:UpdateAll()
end

function M:OnDisable()
    self.running = false
    wipe(pending)
    for uf in pairs(plates) do self:ReleasePlate(uf) end
end
