-- BadbUI - Scaling: UI scale globale "pixel perfect" e scala per singolo frame non-Edit Mode.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger = Badb.Events, Badb.Logger

local M = Badb.Modules:New("Scaling", {
    title = L["Scala interfaccia"],
    category = L["Interfaccia"],
    defaults = { enabled = false, pixelPerfect = true, uiScale = 0.71 },
    options = {
        { type = "toggle", path = "pixelPerfect", label = L["Scala pixel perfect (768 / altezza schermo)"] },
        { type = "range", path = "uiScale", label = L["Scala manuale"], min = 0.4, max = 1.15, step = 0.01 },
    },
})

local function targetScale(self)
    if self:Get("pixelPerfect") then
        local _, h = GetPhysicalScreenSize()
        return math.max(0.4, math.min(1.15, 768 / h))
    end
    return self:Get("uiScale")
end

function M:Apply()
    Events:RunOutOfCombat("uiScale", function()
        local s = targetScale(self)
        UIParent:SetScale(s)
        Logger:Debug("UI scale %.3f", s)
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
    Events:RunOutOfCombat("uiScale", function()
        UIParent:SetScale(tonumber(GetCVar("uiScale")) or 1)
    end)
end
