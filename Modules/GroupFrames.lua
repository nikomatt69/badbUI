-- BadbUI - Raid e party frame
-- Personalizza i Compact Unit Frame Blizzard (party e raid) senza sostituirli:
--   * Opzioni Blizzard (colore classe, barre risorse, pet, aggro, testo vita...) via CVar.
--   * Dimensioni (larghezza/altezza) scritte nel layout Edit Mode attivo, perche' su Forever
--     posizione e dimensione di questi frame appartengono all'Edit Mode: niente SetPoint/SetSize.
--   * Stile (texture barra vita, dimensione nome, sfondo) applicato con hooksecurefunc sulle
--     funzioni di setup Blizzard: nessun taint, nessuna lettura di valori secret.
local _, ns = ...
local Badb = ns.Badb
local CVars, Compat, Logger, Events = Badb.CVars, Badb.Compat, Badb.Logger, Badb.Events

local HEALTH_TEXT = {
    { value = "none", text = "Nessuno" },
    { value = "health", text = "Vita attuale" },
    { value = "losthealth", text = "Vita mancante" },
    { value = "perc", text = "Percentuale" },
}
local TEXTURES = {
    { value = "blizzard", text = "Blizzard" },
    { value = "flat", text = "Piatta (Badb)" },
    { value = "smooth", text = "Morbida" },
}
local TEXTURE_PATHS = {
    flat = "Interface\\Buttons\\WHITE8X8",
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
}

local M = Badb.Modules:New("GroupFrames", {
    title = "Raid e party",
    category = "Gruppo",
    description = "Opzioni, dimensioni e stile dei frame di gruppo Blizzard.",
    defaults = {
        enabled = false,
        raidStyleParty = true,     -- party con lo stesso stile dei raid frame
        classColors = true,
        powerBars = false,
        showPets = false,
        aggroHighlight = true,
        mainTankAssist = true,
        onlyDispellable = false,
        incomingHeals = true,
        healthText = "none",
        resizeFrames = false,      -- scrive larghezza/altezza nel layout Edit Mode
        partyWidth = 120,
        partyHeight = 60,
        raidWidth = 90,
        raidHeight = 45,
        -- stile
        texture = "flat",
        nameSize = 11,
        darkBackground = true,
    },
})

M.options = {
    { type = "header", label = "Opzioni Blizzard" },
    { type = "toggle", path = "raidStyleParty", label = "Party in stile raid" },
    { type = "toggle", path = "classColors", label = "Colore di classe" },
    { type = "toggle", path = "powerBars", label = "Barre risorse" },
    { type = "toggle", path = "showPets", label = "Mostra pet" },
    { type = "toggle", path = "aggroHighlight", label = "Evidenzia aggro" },
    { type = "toggle", path = "mainTankAssist", label = "Mostra main tank e assist" },
    { type = "toggle", path = "onlyDispellable", label = "Solo debuff dissipabili" },
    { type = "toggle", path = "incomingHeals", label = "Cure in arrivo" },
    { type = "select", path = "healthText", label = "Testo vita", values = HEALTH_TEXT },
    { type = "header", label = "Dimensioni (layout Edit Mode)" },
    { type = "toggle", path = "resizeFrames", label = "Gestisci dimensioni da BadbUI" },
    { type = "range", path = "partyWidth", label = "Larghezza party", min = 72, max = 144, step = 2 },
    { type = "range", path = "partyHeight", label = "Altezza party", min = 36, max = 72, step = 2 },
    { type = "range", path = "raidWidth", label = "Larghezza raid", min = 72, max = 144, step = 2 },
    { type = "range", path = "raidHeight", label = "Altezza raid", min = 36, max = 72, step = 2 },
    { type = "header", label = "Stile" },
    { type = "select", path = "texture", label = "Texture barra vita", values = TEXTURES },
    { type = "range", path = "nameSize", label = "Dimensione nome", min = 8, max = 16, step = 1 },
    { type = "toggle", path = "darkBackground", label = "Sfondo scuro" },
}

------------------------------------------------------------------------------
-- CVar
------------------------------------------------------------------------------
function M:BuildCVars()
    local g = function(k) return self:Get(k) end
    return {
        useCompactPartyFrames = g("raidStyleParty"),
        raidFramesDisplayClassColor = g("classColors"),
        raidFramesDisplayPowerBars = g("powerBars"),
        raidOptionDisplayPets = g("showPets"),
        raidFramesDisplayAggroHighlight = g("aggroHighlight"),
        raidOptionDisplayMainTankAndAssist = g("mainTankAssist"),
        raidFramesDisplayOnlyDispellableDebuffs = g("onlyDispellable"),
        raidFramesDisplayIncomingHeals = g("incomingHeals"),
        raidFramesHealthText = g("healthText"),
    }
end

------------------------------------------------------------------------------
-- Dimensioni tramite layout Edit Mode
------------------------------------------------------------------------------
-- Converte il valore "umano" (pixel) nel valore salvato nel layout, usando le stesse regole
-- dello slider Edit Mode di Blizzard quando disponibili.
local function toLayoutValue(system, setting, value)
    local mgr = EditModeSettingDisplayInfoManager
    local infos = mgr and mgr.systemSettingDisplayInfo and mgr.systemSettingDisplayInfo[system]
    if infos then
        for _, info in ipairs(infos) do
            if info.setting == setting then
                if info.ConvertValue then
                    local ok, v = pcall(info.ConvertValue, info, value, false)
                    if ok and v then return v end
                end
                if info.minValue and info.stepSize then
                    return math.floor((value - info.minValue) / info.stepSize + 0.5)
                end
            end
        end
    end
    return value
end

local function setSystemSetting(layoutInfo, system, index, setting, value)
    for _, sys in ipairs(layoutInfo.systems or {}) do
        if sys.system == system and (index == nil or sys.systemIndex == index) then
            for _, s in ipairs(sys.settings or {}) do
                if s.setting == setting then
                    local v = toLayoutValue(system, setting, value)
                    if s.value ~= v then s.value = v; return true end
                    return false
                end
            end
        end
    end
    return false
end

function M:ApplySizes()
    if not self:Get("resizeFrames") or not Compat.hasEditMode then return end
    local E = Enum
    if not (E.EditModeSystem and E.EditModeUnitFrameSystemIndices and E.EditModeUnitFrameSetting) then return end
    Events:RunOutOfCombat("groupFrameSizes", function()
        local layouts = C_EditMode.GetLayouts()
        local presets = (E.EditModePresetLayoutsMeta and E.EditModePresetLayoutsMeta.NumValues) or 2
        local idx = layouts.activeLayout - presets
        local info = layouts.layouts[idx]
        if not info then
            Logger:Warn("Raid e party: il layout Edit Mode attivo e' un preset Blizzard. Crea un layout personale per gestire le dimensioni.")
            return
        end
        local sys, ix, set = E.EditModeSystem.UnitFrame, E.EditModeUnitFrameSystemIndices, E.EditModeUnitFrameSetting
        local changed = false
        changed = setSystemSetting(info, sys, ix.Party, set.FrameWidth, self:Get("partyWidth")) or changed
        changed = setSystemSetting(info, sys, ix.Party, set.FrameHeight, self:Get("partyHeight")) or changed
        changed = setSystemSetting(info, sys, ix.Raid, set.FrameWidth, self:Get("raidWidth")) or changed
        changed = setSystemSetting(info, sys, ix.Raid, set.FrameHeight, self:Get("raidHeight")) or changed
        if changed then
            C_EditMode.SaveLayouts(layouts)
            Logger:Debug("Dimensioni raid/party salvate nel layout '%s'", info.layoutName or "?")
            -- Mantiene allineata la copia del layout salvata nel profilo BadbUI.
            local bridge = Badb.Modules:Get("EditModeBridge")
            if bridge and bridge.enabled and bridge:Get("layoutName") == info.layoutName then bridge:Capture() end
        end
    end)
end

------------------------------------------------------------------------------
-- Stile dei Compact Unit Frame
------------------------------------------------------------------------------
local originals = setmetatable({}, { __mode = "k" }) -- [frame] = { tex, font }

local function isGroupFrame(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end
    local unit = frame.unit or frame.displayedUnit
    if type(unit) ~= "string" then return false end
    return unit:find("^party") or unit:find("^raid") or unit == "player"
end

function M:StyleFrame(frame)
    if not self.active or not isGroupFrame(frame) then return end
    local hb, name = frame.healthBar, frame.name
    local o = originals[frame]
    if not o then
        o = {}
        if hb and hb.GetStatusBarTexture then
            local t = hb:GetStatusBarTexture()
            o.tex = t and t:GetTexture()
        end
        if name and name.GetFont then o.font = { name:GetFont() } end
        originals[frame] = o
    end
    local path = TEXTURE_PATHS[self:Get("texture")]
    if hb then
        if path then hb:SetStatusBarTexture(path) elseif o.tex then hb:SetStatusBarTexture(o.tex) end
    end
    if name and o.font and o.font[1] then name:SetFont(o.font[1], self:Get("nameSize"), o.font[3]) end
    if frame.background and frame.background.SetColorTexture then
        -- Senza sfondo scuro lasciamo quello Blizzard, reimpostato dal prossimo setup.
        if self:Get("darkBackground") then frame.background:SetColorTexture(0.06, 0.07, 0.10, 0.9) end
    end
end

function M:UnstyleFrame(frame)
    local o = originals[frame]
    if not o then return end
    if frame.healthBar and o.tex then frame.healthBar:SetStatusBarTexture(o.tex) end
    if frame.name and o.font and o.font[1] then frame.name:SetFont(unpack(o.font)) end
    originals[frame] = nil
end

local function eachGroupFrame(fn)
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if f then fn(f) end
    end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if f then fn(f) end
    end
    for g = 1, 8 do
        for i = 1, 5 do
            local f = _G["CompactRaidGroup" .. g .. "Member" .. i]
            if f then fn(f) end
        end
    end
end

function M:RestyleAll()
    eachGroupFrame(function(f) self:StyleFrame(f) end)
end

local hooked = false
local function installHooks()
    if hooked then return end
    hooked = true
    -- hooksecurefunc non si puo' rimuovere: le hook controllano M.active.
    local function restyle(frame) M:StyleFrame(frame) end
    if DefaultCompactUnitFrameSetup then hooksecurefunc("DefaultCompactUnitFrameSetup", restyle) end
    if DefaultCompactMiniFrameSetup then hooksecurefunc("DefaultCompactMiniFrameSetup", restyle) end
    if CompactUnitFrame_UpdateName then hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if not M.active or not isGroupFrame(frame) then return end
        local o = originals[frame]
        if frame.name and o and o.font and o.font[1] then frame.name:SetFont(o.font[1], M:Get("nameSize"), o.font[3]) end
    end) end
end

------------------------------------------------------------------------------
-- Ciclo di vita
------------------------------------------------------------------------------
function M:ApplyAll()
    CVars:SetMany(self.name, self:BuildCVars())
    self:ApplySizes()
    self:RestyleAll()
end

function M:OnEnable()
    self.active = true -- M.enabled diventa true solo dopo OnEnable: le hook usano questo flag
    installHooks()
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module ~= self.name then return end
        if path and path:find("Width$") or path and path:find("Height$") or path == "resizeFrames" then
            self:ApplySizes()
        else
            self:ApplyAll()
        end
    end)
    self:On("GROUP_ROSTER_UPDATE", function() self:RestyleAll() end)
    self:ApplyAll()
end

function M:OnProfileChanged() self:ApplyAll() end

function M:OnDisable()
    self.active = false
    CVars:Restore(self.name)
    eachGroupFrame(function(f) self:UnstyleFrame(f) end)
end
