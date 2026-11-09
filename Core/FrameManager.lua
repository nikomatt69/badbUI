-- AegisUI - Frame Manager
-- Registro centrale dei frame gestibili (Blizzard o di AegisUI).
-- Per ogni frame salva nel profilo: posizione, scala, alpha, visibilita' e condizioni.
-- Ripristina sempre lo stato originale quando un frame viene "rilasciato".
local _, ns = ...
local Aegis = ns.Aegis
local Events, Logger, DB, Compat = Aegis.Events, Aegis.Logger, Aegis.DB, Aegis.Compat

local FM = { registry = {}, movers = {}, unlocked = false }
Aegis.FrameManager = FM

--[[ Descrittore:
FM:Register("PlayerFrame", {
    frame = "PlayerFrame",       -- nome globale o riferimento (risolto in modo lazy)
    title = "Giocatore",
    category = "Unit Frames",
    movable = true, scalable = true, hideable = true,
})
]]
function FM:Register(key, desc)
    desc.key = key
    desc.title = desc.title or key
    desc.category = desc.category or "Altro"
    self.registry[key] = desc
    if self.ready then self:Apply(key) end
end

local function resolve(desc)
    if type(desc.frame) == "table" then return desc.frame end
    return _G[desc.frame]
end

local function conf(key)
    local frames = DB.profile.frames
    frames[key] = frames[key] or {}
    return frames[key]
end

-- Salva lo stato originale una sola volta, per poterlo ripristinare.
local function snapshot(desc, f)
    if desc.original then return end
    local points = {}
    for i = 1, f:GetNumPoints() do points[i] = { f:GetPoint(i) } end
    desc.original = { points = points, scale = f:GetScale(), alpha = f:GetAlpha(), shown = f:IsShown() }
end

local function applyNow(desc, f, c)
    snapshot(desc, f)
    -- Frame Edit Mode: posizione e scala appartengono al layout Edit Mode (vedi EditModeBridge).
    local editMode = Compat.IsEditModeFrame(f)
    if c.point and not editMode then
        f:ClearAllPoints()
        f:SetPoint(c.point, UIParent, c.relPoint or c.point, c.x or 0, c.y or 0)
        if f.SetUserPlaced and f:IsMovable() then f:SetUserPlaced(true) end
    end
    if c.scale and not editMode then f:SetScale(c.scale) end
    if c.alpha then f:SetAlpha(c.alpha) end
    if c.hidden then
        f:Hide()
        if not desc.hookedShow then
            desc.hookedShow = true
            hooksecurefunc(f, "Show", function(self)
                local cur = DB.profile.frames[desc.key]
                if cur and cur.hidden and not InCombatLockdown() then self:Hide() end
            end)
        end
    end
end

function FM:Apply(key)
    local desc = self.registry[key]
    local f = desc and resolve(desc)
    if not f then return end
    local c = conf(key)
    if f:IsProtected() then
        Events:RunOutOfCombat("frame:" .. key, function() applyNow(desc, f, c) end)
    else
        applyNow(desc, f, c)
    end
end

function FM:ApplyAll()
    for key in pairs(self.registry) do self:Apply(key) end
end

function FM:Restore(key)
    local desc = self.registry[key]
    local f = desc and resolve(desc)
    if not f or not desc.original then return end
    Events:RunOutOfCombat("restore:" .. key, function()
        local o = desc.original
        f:ClearAllPoints()
        for _, p in ipairs(o.points) do f:SetPoint(unpack(p)) end
        f:SetScale(o.scale); f:SetAlpha(o.alpha)
        if o.shown then f:Show() end
    end)
    DB.profile.frames[key] = {}
end

function FM:SetOption(key, field, value)
    conf(key)[field] = value
    self:Apply(key)
    Events:Fire("AEGIS_FRAME_CHANGED", key, field, value)
end

-- Modalita' sblocco: overlay trascinabili sopra ogni frame registrato, con snap a griglia.
local function createMover(desc, f)
    local m = Compat.CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetAllPoints(f)
    m:EnableMouse(true); m:SetMovable(true); m:RegisterForDrag("LeftButton")
    if m.SetBackdrop then
        m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        m:SetBackdropColor(0.25, 0.65, 1, 0.25); m:SetBackdropBorderColor(0.25, 0.65, 1, 0.9)
    end
    local label = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER"); label:SetText(desc.title)
    m:SetScript("OnDragStart", function(self) self:StartMoving() end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local grid = DB.sv.global.gridSize or 8
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        x = math.floor((x - ux) / grid + 0.5) * grid
        y = math.floor((y - uy) / grid + 0.5) * grid
        local c = conf(desc.key)
        c.point, c.relPoint, c.x, c.y = "CENTER", "CENTER", x, y
        FM:Apply(desc.key)
        self:ClearAllPoints(); self:SetAllPoints(f)
    end)
    m:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then FM:Restore(desc.key) end
    end)
    return m
end

function FM:SetUnlocked(state)
    if state and InCombatLockdown() then
        Logger:Warn("Impossibile sbloccare in combattimento")
        return
    end
    self.unlocked = state
    for key, desc in pairs(self.registry) do
        local f = resolve(desc)
        if f and desc.movable ~= false and not Compat.IsEditModeFrame(f) then
            self.movers[key] = self.movers[key] or createMover(desc, f)
            self.movers[key]:SetShown(state)
        end
    end
    Events:Fire("AEGIS_UNLOCK_CHANGED", state)
end

Events:On(FM, "PLAYER_REGEN_DISABLED", function()
    if FM.unlocked then FM:SetUnlocked(false) end
end)

Events:On(FM, "PLAYER_ENTERING_WORLD", function()
    FM.ready = true
    FM:ApplyAll()
end)

Events:On(FM, "AEGIS_PROFILE_CHANGED", function()
    for key, desc in pairs(FM.registry) do
        if desc.original then FM:Restore(key) end
    end
    FM:ApplyAll()
end)
