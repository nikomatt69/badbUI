-- BadbUI - Frame Manager
-- Registro centrale dei frame gestibili (Blizzard o di BadbUI).
-- Per ogni frame salva nel profilo: posizione, scala, alpha, visibilita' e condizioni.
-- Ripristina sempre lo stato originale quando un frame viene "rilasciato".
local _, ns = ...
local Badb = ns.Badb
local Events, Logger, DB, Compat = Badb.Events, Badb.Logger, Badb.DB, Badb.Compat

local FM = { registry = {}, movers = {}, unlocked = false }
Badb.FrameManager = FM

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

-- Riporta il frame allo stato Blizzard originale. Non tocca la configurazione del profilo.
-- I frame Edit Mode non hanno mai punti/scala riscritti da noi: restano all'Edit Mode.
local function restoreNow(desc, f)
    local o = desc.original
    if not o then return end
    if not Compat.IsEditModeFrame(f) then
        f:ClearAllPoints()
        for _, p in ipairs(o.points) do f:SetPoint(unpack(p)) end
        f:SetScale(o.scale)
    end
    f:SetAlpha(o.alpha)
    if o.shown then f:Show() end
end

-- Rilascio esplicito (azione dell'utente): azzera la configurazione e ripristina lo stato originale.
-- La configurazione va azzerata PRIMA di Show(): l'hook "hidden" altrimenti rileggerebbe hidden=true e richiuderebbe il frame.
function FM:Restore(key)
    local desc = self.registry[key]
    if not desc then return end
    DB.profile.frames[key] = {}
    local f = resolve(desc)
    if f and desc.original then
        Events:RunOutOfCombat("restore:" .. key, function() restoreNow(desc, f) end)
    end
    Events:Fire("BADB_FRAME_CHANGED", key, "restore")
end

-- Cambio profilo: ripristina lo stato originale e applica la configurazione del NUOVO profilo, senza modificarla.
-- Ripristino e applicazione stanno nella stessa azione differita, cosi' in combattimento l'ordine e' sempre corretto.
function FM:Reapply(key)
    local desc = self.registry[key]
    local f = desc and resolve(desc)
    if not f then return end
    if not desc.original then return self:Apply(key) end
    Events:RunOutOfCombat("frame:" .. key, function()
        restoreNow(desc, f)
        applyNow(desc, f, conf(key))
    end)
end

function FM:SetOption(key, field, value)
    conf(key)[field] = value
    self:Apply(key)
    Events:Fire("BADB_FRAME_CHANGED", key, field, value)
end

-- Modalita' sblocco: overlay trascinabili sopra ogni frame registrato, con snap a griglia.
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local SCALE_STEP, SCALE_MIN, SCALE_MAX = 0.05, 0.5, 2

-- Salva la posizione (relativa al centro dello schermo) e la riapplica; il mover segue il frame.
local function place(m, desc, f, x, y)
    local c = conf(desc.key)
    c.point, c.relPoint, c.x, c.y = "CENTER", "CENTER", x, y
    FM:Apply(desc.key)
    m:ClearAllPoints(); m:SetAllPoints(f)
    Events:Fire("BADB_FRAME_CHANGED", desc.key, "position", c)
end

-- Sposta di (dx, dy) pixel dalla posizione attuale del frame. Falso se la posizione non e' leggibile.
local function nudge(m, desc, f, dx, dy)
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if type(x) ~= "number" or type(ux) ~= "number" then return false end
    place(m, desc, f, math.floor(x - ux + 0.5) + dx, math.floor(y - uy + 0.5) + dy)
    return true
end

local function createMover(desc, f)
    local m = Compat.CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetAllPoints(f)
    m:EnableMouse(true); m:SetMovable(true); m:RegisterForDrag("LeftButton")
    if m.SetBackdrop then
        m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        m:SetBackdropColor(0.09, 0.52, 0.82, 0.3); m:SetBackdropBorderColor(0.09, 0.52, 0.82, 0.95)
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
        place(self, desc, f, x, y)
    end)
    m:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then FM:Restore(desc.key) end
    end)
    -- Come i mover di ElvUI: con il mouse sopra, le frecce spostano di 1 px (Maiusc: 10 px) e
    -- Maiusc + rotella cambia la scala. Gli altri tasti restano al gioco.
    m:EnableKeyboard(false)
    if m.SetPropagateKeyboardInput then m:SetPropagateKeyboardInput(true) end
    m:SetScript("OnEnter", function(self)
        if self.EnableKeyboard then self:EnableKeyboard(true) end
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(desc.title)
            GameTooltip:AddLine("Trascina: sposta (griglia)", 1, 1, 1)
            GameTooltip:AddLine("Frecce: 1 px (Maiusc 10 px)", 1, 1, 1)
            if desc.scalable ~= false then GameTooltip:AddLine("Maiusc + rotella: scala", 1, 1, 1) end
            GameTooltip:AddLine("Tasto destro: ripristina", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    m:SetScript("OnLeave", function(self)
        if self.EnableKeyboard then self:EnableKeyboard(false) end
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    m:SetScript("OnKeyDown", function(self, key)
        local dir = ARROWS[key]
        local handled = false
        if dir and not InCombatLockdown() then
            local step = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
            handled = nudge(self, desc, f, dir[1] * step, dir[2] * step)
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not handled) end
    end)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseWheel", function(_, delta)
        if not (IsShiftKeyDown and IsShiftKeyDown()) or desc.scalable == false then return end
        if Compat.IsEditModeFrame(f) or InCombatLockdown() then return end
        local cur = conf(desc.key).scale or f:GetScale() or 1
        local nxt = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor((cur + (delta > 0 and SCALE_STEP or -SCALE_STEP)) * 100 + 0.5) / 100))
        FM:SetOption(desc.key, "scale", nxt)
    end)
    return m
end

FM._nudge = nudge -- usato dai test

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
    Events:Fire("BADB_UNLOCK_CHANGED", state)
end

Events:On(FM, "PLAYER_REGEN_DISABLED", function()
    if FM.unlocked then FM:SetUnlocked(false) end
end)

Events:On(FM, "PLAYER_ENTERING_WORLD", function()
    FM.ready = true
    FM:ApplyAll()
end)

Events:On(FM, "BADB_PROFILE_CHANGED", function()
    for key in pairs(FM.registry) do FM:Reapply(key) end
end)
