-- Stub minimale dell'API WoW per eseguire i file dell'addon fuori dal gioco.
-- Copre solo quello che serve ai test: aggiungere funzioni qui quando servono.
local S = { cvars = {}, combat = false, events = {}, printed = {} }
WOWSTUB = S

local function noop() end
local frameMT = {}
frameMT.__index = function(_, k) return noop end
function CreateFrame()
    local f = setmetatable({}, frameMT)
    f.RegisterEvent = function(_, e) S.events[e] = true end
    f.UnregisterEvent = function(_, e) S.events[e] = nil end
    f.SetScript = function(self, _, fn) self.onEvent = fn end
    S.eventFrame = S.eventFrame or f
    return f
end

function GetBuildInfo() return "1.60.0", "0", "Nov 1 2026", 16001 end
C_AddOns = { GetAddOnMetadata = function() return "test" end }
C_Timer = { After = function(_, fn) fn() end, NewTicker = noop }
C_CVar = {
    GetCVar = function(n) return S.cvars[n] end,
    SetCVar = function(n, v) S.cvars[n] = tostring(v) end,
    GetCVarInfo = function(n) if S.cvars[n] ~= nil then return S.cvars[n] end end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) S.printed[#S.printed + 1] = m end }
function InCombatLockdown() return S.combat end
function UnitName() return "Tester" end
function GetRealmName() return "Forever" end
function UnitLevel() return S.level or 60 end
function IsInRaid() return S.inRaid or false end
function UnitGroupRolesAssigned() return S.role or "NONE" end
function GetMaxLevelForPlayerExpansion() return 60 end
function date() return "00:00:00" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc() end
function issecure() return true end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
Enum = {}
unpack = unpack or table.unpack

-- Simula un evento di gioco sul bus dell'addon.
function S.fire(event, ...)
    if S.eventFrame and S.eventFrame.onEvent then S.eventFrame.onEvent(S.eventFrame, event, ...) end
end

-- Oggetti finti (statusbar, fontstring, frame) che registrano le chiamate utili ai test.
function S.region(extra)
    local r = { calls = {} }
    r.SetStatusBarTexture = function(self, t) self.texture = t end
    r.GetStatusBarTexture = function(self) return { GetTexture = function() return self.texture end } end
    r.GetFont = function(self) return self.font or "Fonts\\FRIZQT__.TTF", self.fontSize or 10, self.fontFlags or "OUTLINE" end
    r.SetFont = function(self, f, size, flags) self.font, self.fontSize, self.fontFlags = f, size, flags end
    r.GetFrameLevel = function() return 1 end
    r.IsForbidden = function(self) return self.forbidden or false end
    r.SetColorTexture = function(self, ...) self.color = { ... } end
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- Frame con backdrop per i bordi delle nameplate
local baseCreate = CreateFrame
function CreateFrame(kind, name, parent, template)
    local f = baseCreate(kind, name, parent, template)
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.Hide = function(self) self.shown = false end
    f.SetBackdropBorderColor = function(self, ...) self.borderColor = { ... } end
    return f
end

-- Nameplate
S.plates = {}
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return S.plates[unit] end,
    GetNamePlates = function()
        local list = {}
        for _, p in pairs(S.plates) do list[#list + 1] = p end
        return list
    end,
}
function S.addPlate(unit, opts)
    opts = opts or {}
    local uf = S.region({ unit = unit, forbidden = opts.forbidden })
    if not opts.noHealth then uf.healthBar = S.region({ texture = "Blizzard\\Bar" }) end
    uf.name = S.region()
    S.plates[unit] = { namePlateUnitToken = unit, UnitFrame = uf }
    return uf
end
S.target = nil
S.secretTarget = false
function UnitIsUnit(a, b)
    if S.secretTarget then return S.SECRET end
    return b == "target" and a == S.target
end
S.SECRET = setmetatable({}, { __eq = function() error("confronto su secret value") end })
function issecretvalue(v) return rawequal(v, S.SECRET) end

-- Edit Mode: un layout personale (indice 1) dopo i 2 preset Blizzard.
Enum.EditModeSystem = { UnitFrame = 3 }
Enum.EditModeUnitFrameSystemIndices = { Party = 5, Raid = 6 }
Enum.EditModeUnitFrameSetting = { FrameWidth = 3, FrameHeight = 4 }
Enum.EditModePresetLayoutsMeta = { NumValues = 2 }
Enum.EditModeLayoutType = { Account = 1 }
EditModeManagerFrame = {}
function S.resetLayouts(active)
    local function sys(index, w, h)
        return { system = 3, systemIndex = index, settings = { { setting = 3, value = w }, { setting = 4, value = h } } }
    end
    S.layouts = {
        activeLayout = active or 3,
        layouts = { { layoutName = "Mio", layoutType = 1, systems = { sys(5, 24, 12), sys(6, 9, 4) } } },
    }
    S.savedLayouts = 0
end
S.resetLayouts()
local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end
C_EditMode = {
    GetLayouts = function() return copy(S.layouts) end,
    SaveLayouts = function(l) S.layouts = copy(l); S.savedLayouts = S.savedLayouts + 1 end,
    ConvertLayoutInfoToString = function() return "layoutstring" end,
}
-- Regole slider Blizzard: valore salvato = (pixel - min) / step
local function slider(setting, min, step)
    return { setting = setting, minValue = min, stepSize = step,
        ConvertValue = function(self, v, forDisplay)
            if forDisplay then return v * self.stepSize + self.minValue end
            return (v - self.minValue) / self.stepSize
        end }
end
EditModeSettingDisplayInfoManager = { systemSettingDisplayInfo = { [3] = { slider(3, 72, 2), slider(4, 36, 2) } } }
return S
