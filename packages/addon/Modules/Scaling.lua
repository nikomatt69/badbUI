-- BadbUI - Scaling: UI scale globale "pixel perfect" e scala per singolo frame non-Edit Mode.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger = Badb.Events, Badb.Logger

local MIN_MANUAL, MAX_MANUAL = 0.20, 1.20

local function currentScale()
    if not UIParent or type(UIParent.GetScale) ~= "function" then return nil end
    local ok, value = pcall(UIParent.GetScale, UIParent)
    if ok and not Badb.Compat.IsSecret(value) and type(value) == "number" and value > 0 and value < math.huge then
        return value
    end
end

local function supported()
    return currentScale() ~= nil and type(UIParent.SetScale) == "function"
end

local M = Badb.Modules:New("Scaling", {
    title = L["Scala interfaccia"],
    category = L["Interfaccia"],
    defaults = { enabled = false, pixelPerfect = true, uiScale = 0.71 },
    replaces = {
        { addon = "UIScalaMinima", coverage = "full", available = supported,
          note = L["Per mantenere le stesse dimensioni, imposta la scala manuale usata in precedenza."] },
    },
    options = {
        { type = "toggle", path = "pixelPerfect", label = L["Scala pixel perfect (768 / altezza schermo)"] },
        { type = "range", path = "uiScale", label = L["Scala manuale"], min = MIN_MANUAL, max = MAX_MANUAL, step = 0.01,
          disabled = function() return Badb.DB:Get("Scaling", "pixelPerfect") == true end },
    },
})

local function targetScale(self)
    if self:Get("pixelPerfect") and type(GetPhysicalScreenSize) == "function" then
        local ok, _, height = pcall(GetPhysicalScreenSize)
        if ok and not Badb.Compat.IsSecret(height) and type(height) == "number" and height > 0 then
            return math.max(0.4, math.min(1.15, 768 / height))
        end
    end
    local manual = self:Get("uiScale")
    if type(manual) ~= "number" or manual ~= manual then return self.defaults.uiScale end
    return math.max(MIN_MANUAL, math.min(MAX_MANUAL, manual))
end

function M:Apply()
    Events:RunOutOfCombat("uiScale", function()
        local scale = currentScale()
        if not scale or type(UIParent.SetScale) ~= "function" then return end
        local target = targetScale(self)
        if math.abs(scale - target) <= 0.001 then return end
        self.originalScale = self.originalScale or scale
        local ok = pcall(UIParent.SetScale, UIParent, target)
        if ok then Logger:Debug("UI scale %.3f", target) end
    end)
end

function M:OnEnable()
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == self.name then self:Apply() end
    end)
    self:On("UI_SCALE_CHANGED", function() self:Apply() end)
    self:On("DISPLAY_SIZE_CHANGED", function() self:Apply() end)
    self:Apply()
end

function M:OnProfileChanged() self:Apply() end

function M:OnDisable()
    self:Off("UI_SCALE_CHANGED")
    Events:RunOutOfCombat("uiScale", function()
        if self.originalScale and supported() then pcall(UIParent.SetScale, UIParent, self.originalScale) end
        self.originalScale = nil
    end)
end

M.commands = {
    scale = { help = L["scale [valore] - mostra o imposta la scala manuale (0.20–1.20)"], fn = function(args)
        if not args or not args:find("%S") then
            local scale = currentScale()
            if scale then Logger:Info(L["Scala attuale: %.2f"], scale) end
            return
        end
        local scale = tonumber(args)
        if not scale or scale < MIN_MANUAL or scale > MAX_MANUAL or scale ~= scale then
            Logger:Warn(L["Inserisci una scala compresa tra 0.20 e 1.20."])
            return
        end
        if not supported() then
            Logger:Warn(L["Modulo non disponibile su questo client"])
            return
        end
        M:Set("uiScale", scale)
        M:Set("pixelPerfect", false)
        Badb.Modules:SetEnabled(M.name, true)
    end },
}
