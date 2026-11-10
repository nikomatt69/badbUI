-- BadbUI - Nameplates
-- Due livelli, entrambi reversibili:
--   1. Comportamento: CVar Blizzard (visibilita', distanza, impilamento, scala, trasparenza),
--      gestiti da Badb.CVars che salva e ripristina i valori originali.
--   2. Stile: texture della barra vita, dimensione nome, bordo sul bersaglio, gestito
--      decorando le nameplate Blizzard quando compaiono (NAME_PLATE_UNIT_ADDED).
-- Regole Forever: niente lettura di vita/minaccia (secret values in combattimento), niente
-- nameplate "forbidden" (amiche in istanza): C_NamePlate.GetNamePlateForUnit(unit, issecure())
-- le esclude da solo.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local CVars, Compat = Badb.CVars, Badb.Compat

local STACK_MODES = { { value = "stack", text = L["Impilate (consigliato)"] }, { value = "overlap", text = L["Sovrapposte"] } }
local TEXTURES = {
    { value = "blizzard", text = "Blizzard" },
    { value = "flat", text = L["Piatta (Badb)"] },
    { value = "smooth", text = L["Morbida"] },
}
local TEXTURE_PATHS = {
    flat = "Interface\\Buttons\\WHITE8X8",
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
}

local M = Badb.Modules:New("Nameplates", {
    title = "Nameplate",
    category = L["Combattimento"],
    description = L["Visibilita', impilamento e stile delle barre sopra le unita'."],
    defaults = {
        enabled = false,
        showEnemies = true,
        showFriends = false,
        showAlways = true,        -- mostra anche fuori combattimento
        showMinions = false,      -- totem, guardiani, pet nemici
        maxDistance = 41,
        stacking = "stack",
        overlapV = 1.1,
        globalScale = 1.0,
        selectedScale = 1.2,
        minAlpha = 0.6,           -- unita' non bersagliate
        occludedAlpha = 0.4,      -- unita' dietro ostacoli
        classColorEnemies = true,
        classColorFriends = true,
        personalBar = false,
        -- stile
        texture = "flat",
        nameSize = 10,
        targetBorder = true,
    },
})

M.options = {
    { type = "header", label = L["Visibilita'"] },
    { type = "toggle", path = "showEnemies", label = L["Nemici"] },
    { type = "toggle", path = "showFriends", label = L["Alleati"] },
    { type = "toggle", path = "showAlways", label = L["Sempre visibili (anche fuori combattimento)"] },
    { type = "toggle", path = "showMinions", label = L["Pet, totem e guardiani nemici"] },
    { type = "toggle", path = "personalBar", label = L["Barra personale (risorse sotto il personaggio)"] },
    { type = "range", path = "maxDistance", label = L["Distanza massima (yard)"], min = 20, max = 60, step = 1 },
    { type = "header", label = L["Disposizione"] },
    { type = "select", path = "stacking", label = L["Impilamento"], values = STACK_MODES },
    { type = "range", path = "overlapV", label = L["Spaziatura verticale"], min = 0.5, max = 2, step = 0.05 },
    { type = "range", path = "globalScale", label = L["Scala"], min = 0.6, max = 1.6, step = 0.05 },
    { type = "range", path = "selectedScale", label = L["Scala bersaglio"], min = 1, max = 1.6, step = 0.05 },
    { type = "range", path = "minAlpha", label = L["Trasparenza non bersagliati"], min = 0.2, max = 1, step = 0.05 },
    { type = "range", path = "occludedAlpha", label = L["Trasparenza dietro ostacoli"], min = 0.1, max = 1, step = 0.05 },
    { type = "header", label = L["Stile"] },
    { type = "toggle", path = "classColorEnemies", label = L["Colore di classe (nemici)"] },
    { type = "toggle", path = "classColorFriends", label = L["Colore di classe (alleati)"] },
    { type = "select", path = "texture", label = L["Texture barra"], values = TEXTURES },
    { type = "range", path = "nameSize", label = L["Dimensione nome"], min = 7, max = 16, step = 1 },
    { type = "toggle", path = "targetBorder", label = L["Bordo evidenziato sul bersaglio"] },
}

-- Tabella di traduzione opzione -> CVar
function M:BuildCVars()
    local g = function(k) return self:Get(k) end
    return {
        nameplateShowEnemies = g("showEnemies"),
        nameplateShowFriends = g("showFriends"),
        nameplateShowAll = g("showAlways"),
        nameplateShowEnemyMinions = g("showMinions"),
        nameplateShowEnemyPets = g("showMinions"),
        nameplateShowEnemyGuardians = g("showMinions"),
        nameplateShowEnemyTotems = g("showMinions"),
        nameplateShowSelf = g("personalBar"),
        nameplateMaxDistance = g("maxDistance"),
        nameplateMotion = g("stacking") == "stack" and 1 or 0,
        nameplateOverlapV = g("overlapV"),
        nameplateGlobalScale = g("globalScale"),
        nameplateSelectedScale = g("selectedScale"),
        nameplateMinAlpha = g("minAlpha"),
        nameplateMaxAlpha = 1,
        nameplateOccludedAlphaMult = g("occludedAlpha"),
        ShowClassColorInNameplate = g("classColorEnemies"),
        ShowClassColorInFriendlyNameplate = g("classColorFriends"),
    }
end

function M:ApplyCVars()
    CVars:SetMany(self.name, self:BuildCVars())
end

------------------------------------------------------------------------------
-- Stile
------------------------------------------------------------------------------
local styled = {} -- [UnitFrame] = { origTexture, origFont = {path,size,flags}, border }

local function healthBarOf(uf)
    return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
end

local function accentColor()
    local T = Badb.Theme
    if T and T.Get then
        local r, g, b = T:Get("accent")
        if r then return r, g, b end
    end
    return 0.90, 0.73, 0.40 -- oro Badb
end

local function ensureBorder(uf, hb, st)
    if st.border then return st.border end
    local b = CreateFrame("Frame", nil, hb, "BackdropTemplate")
    b:SetPoint("TOPLEFT", hb, -2, 2)
    b:SetPoint("BOTTOMRIGHT", hb, 2, -2)
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetFrameLevel(hb:GetFrameLevel() + 2)
    b:Hide()
    st.border = b
    uf.BadbTargetBorder = b
    return b
end

function M:StylePlate(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit, issecure())
    local uf = plate and plate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    local hb = healthBarOf(uf)
    local st = styled[uf]
    if not st then
        st = {}
        if hb and hb.GetStatusBarTexture then
            local tex = hb:GetStatusBarTexture()
            st.origTexture = tex and tex:GetTexture()
        end
        if uf.name and uf.name.GetFont then st.origFont = { uf.name:GetFont() } end
        styled[uf] = st
    end
    st.unit = unit

    local texPath = TEXTURE_PATHS[self:Get("texture")]
    if hb and texPath then hb:SetStatusBarTexture(texPath)
    elseif hb and st.origTexture then hb:SetStatusBarTexture(st.origTexture) end

    if uf.name and st.origFont and st.origFont[1] then
        uf.name:SetFont(st.origFont[1], self:Get("nameSize"), st.origFont[3] or "OUTLINE")
    end

    if hb then
        local border = ensureBorder(uf, hb, st)
        border:SetBackdropBorderColor(accentColor())
        local isTarget = Compat.SafeValue(UnitIsUnit(unit, "target"), false)
        border:SetShown(self:Get("targetBorder") and isTarget == true)
    end
end

function M:UnstylePlate(uf)
    local st = styled[uf]
    if not st then return end
    local hb = healthBarOf(uf)
    if hb and st.origTexture then hb:SetStatusBarTexture(st.origTexture) end
    if uf.name and st.origFont and st.origFont[1] then uf.name:SetFont(unpack(st.origFont)) end
    if st.border then st.border:Hide() end
    styled[uf] = nil
end

function M:RestyleAll()
    for _, plate in ipairs(C_NamePlate.GetNamePlates(issecure())) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then self:StylePlate(unit) end
    end
end

function M:UpdateTargetBorders()
    for uf, st in pairs(styled) do
        if st.border and st.unit then
            local isTarget = Compat.SafeValue(UnitIsUnit(st.unit, "target"), false)
            st.border:SetShown(self:Get("targetBorder") and isTarget == true)
        end
    end
end

------------------------------------------------------------------------------
-- Ciclo di vita
------------------------------------------------------------------------------
function M:OnEnable()
    self:On("NAME_PLATE_UNIT_ADDED", function(_, unit) self:StylePlate(unit) end)
    self:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        for _, st in pairs(styled) do if st.unit == unit then st.unit = nil end end
    end)
    self:On("PLAYER_TARGET_CHANGED", function() self:UpdateTargetBorders() end)
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module ~= self.name then return end
        self:ApplyCVars()
        self:RestyleAll()
    end)
    self:On("BADB_THEME_CHANGED", function() self:RestyleAll() end)
    self:ApplyCVars()
    self:RestyleAll()
end

function M:OnProfileChanged()
    self:ApplyCVars()
    self:RestyleAll()
end

function M:OnDisable()
    CVars:Restore(self.name)
    for uf in pairs(styled) do self:UnstylePlate(uf) end
end
