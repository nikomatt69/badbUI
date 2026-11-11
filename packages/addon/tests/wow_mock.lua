-- BadbUI - API WoW simulate per i test fuori dal client (Lua 5.1).
-- Copre solo cio' che serve all'addon: frame generici, Cooldown, hook, CVar, binding.
-- Ogni metodo non definito che inizia con Set/Get/Clear/... diventa un no-op, cosi'
-- i test restano focalizzati sul comportamento e non sulla grafica.
local Mock = { events = {}, cvars = {}, bindings = {}, combat = false, time = 100 }
unpack = unpack or table.unpack

local NOOP_PREFIXES = { "Set", "Get", "Clear", "Enable", "Disable", "Register", "Unregister", "Remove",
    "Add", "Start", "Stop", "Play", "Highlight", "Is", "Raise", "Lower" }

local function noop(k)
    if type(k) ~= "string" then return nil end
    for _, p in ipairs(NOOP_PREFIXES) do
        if k:sub(1, #p) == p then return function() end end
    end
end

local Methods = {}
Mock.Methods = Methods

local function newObject(kind, extra)
    local o = { __kind = kind, __alpha = 1, __shown = true, __scripts = {}, __font = { "Fonts\\FRIZQT__.TTF", 12, "" } }
    return setmetatable(o, { __index = function(_, k)
        if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
        return (extra and extra[k]) or Methods[k] or noop(k)
    end })
end
Mock.NewObject = newObject

function Methods:GetAlpha() return self.__alpha end
function Methods:SetAlpha(a) self.__alpha = a end
function Methods:HasFocus() return false end
function Methods:IsShown() return self.__shown end
function Methods:Show() self.__shown = true end
function Methods:Hide() self.__shown = false end
function Methods:SetShown(v) self.__shown = v and true or false end
function Methods:GetFont() return unpack(self.__font) end
function Methods:SetFont(a, b, c) self.__font = { a, b, c } end
function Methods:SetText(t) self.__text = t end
function Methods:GetText() return self.__text end
function Methods:SetTextColor(r, g, b) self.__color = { r, g, b } end
function Methods:SetVertexColor(r, g, b) self.__vc = { r, g, b } end
function Methods:SetTexCoord(...) self.__texcoord = { ... } end
function Methods:SetTexture(t) self.__texture = t end
function Methods:GetTexture() return self.__texture end
function Methods:GetName() return self.__name end
function Methods:GetWidth() return self.__width or 40 end
function Methods:GetFrameLevel() return 1 end
function Methods:GetNumPoints() return 0 end
function Methods:GetScale() return 1 end
function Methods:IsMouseOver() return self.__mouseover or false end
function Methods:IsForbidden() return self.__forbidden or false end
function Methods:IsProtected() return false end
function Methods:SetScript(k, f) self.__scripts[k] = f end
function Methods:GetScript(k) return self.__scripts[k] end
function Methods:HookScript(k, f)
    local prev = self.__scripts[k]
    self.__scripts[k] = prev and function(...) prev(...); f(...) end or f
end
function Methods:RegisterEvent(e) Mock.events[e] = true end
function Methods:CreateTexture() return newObject("Texture") end
function Methods:CreateFontString() return newObject("FontString") end
function Methods:CreateAnimationGroup()
    return newObject("AnimationGroup", { CreateAnimation = function() return newObject("Animation") end })
end
function Methods:GetNormalTexture()
    local t = rawget(self, "__normal") or newObject("Texture")
    rawset(self, "__normal", t)
    return t
end
function Methods:GetCountdownFontString()
    local t = rawget(self, "__countdown") or newObject("FontString")
    rawset(self, "__countdown", t)
    return t
end
function Methods:SetHideCountdownNumbers(v) self.__hideNumbers = v end
function Methods:SetSwipeColor(r, g, b, a) self.__swipe = { r, g, b, a } end
function Methods:RemoveMaskTexture(m) self.__maskRemoved = m end
function Methods:AddMaskTexture() self.__maskRemoved = nil end

-- Metodi condivisi da tutti i Cooldown (come la metatable reale del widget).
local CooldownIndex = {}
Mock.CooldownIndex = CooldownIndex
function CooldownIndex:SetCooldown(start, duration) self.__start, self.__duration = start, duration end
setmetatable(CooldownIndex, { __index = function(_, k)
    if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
    return Methods[k] or noop(k)
end })
-- Come nel client: la metatable dei Cooldown ha __index = tabella condivisa (hookabile).
local CooldownMeta = { __index = CooldownIndex }

function CreateFrame(kind, name, parent, template)
    local o
    if kind == "Cooldown" then
        o = setmetatable({ __kind = kind, __alpha = 1, __shown = true, __scripts = {} }, CooldownMeta)
    else
        o = newObject(kind)
    end
    o.__name, o.__parent = name, parent
    if name then _G[name] = o end
    return o
end

-- hooksecurefunc reale: esegue l'originale e poi l'hook.
function hooksecurefunc(a, b, c)
    if type(a) == "string" then a, b, c = _G, a, b end
    local orig = a[b] or function() end
    a[b] = function(...)
        local r = { orig(...) }
        c(...)
        return unpack(r)
    end
end

function GetBuildInfo() return "1.60.0", "00000", "Nov 1 2026", 16001 end
C_AddOns = { GetAddOnMetadata = function() return "test" end }
C_Timer = { After = function(_, f) f() end, NewTicker = function() end }
C_CVar = {
    GetCVar = function(k) return Mock.cvars[k] end,
    SetCVar = function(k, v) Mock.cvars[k] = v end,
}
function InCombatLockdown() return Mock.combat end
function UnitName() return "Tester" end
function GetRealmName() return "Forever" end
function GetLocale() return "itIT" end
function GetTime() return Mock.time end
function GetBindingKey(cmd) return Mock.bindings[cmd] end
function HasAction() return true end
function IsUsableAction(action) local s = Mock.usable[action]; if s then return s[1], s[2] end return true, false end
Mock.usable = {}
function UnitExists() return false end
function GetCursorInfo() return nil end
function GetSpellTexture() return 135274 end
function GetPhysicalScreenSize() return 1920, 1080 end
function GetCVar(k) return Mock.cvars[k] end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function date() return "00:00:00" end
function tinsert(t, v) table.insert(t, v) end
function ActionButton_UpdateRangeIndicator() end
UISpecialFrames, SlashCmdList = {}, {}
Mock.chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(Mock.chat, m) end }
UIParent = newObject("Frame")

-- Un valore opaco come quelli restituiti dal client in combattimento.
function Mock.Secret() return { __secret = true } end

-- Pulsanti e barre d'azione come nel client Mainline.
function Mock.CreateActionButtons(prefix, count, commandPrefix)
    for i = 1, count do
        local b = CreateFrame("CheckButton", prefix .. i)
        b.icon = newObject("Texture")
        b.HotKey = newObject("FontString")
        b.Name = newObject("FontString")
        b.Count = newObject("FontString")
        b.IconMask = newObject("MaskTexture")
        b.cooldown = CreateFrame("Cooldown", prefix .. i .. "Cooldown", b)
        b.action = i
        b.commandName = commandPrefix and (commandPrefix .. i) or nil
        b.UpdateHotkeys = function() end
        b.UpdateUsable = function() end
    end
end

function Mock.Fire(event, ...)
    local listeners = BadbUI.Events.listeners[event]
    if not listeners then return end
    for _, fn in pairs(listeners) do fn(event, ...) end
end

-- Carica i file della TOC nell'ordine dichiarato, con il vararg (nome, namespace).
function Mock.LoadAddon(root, tocName, addonName)
    local ns = {}
    local toc = assert(io.open(root .. "/" .. tocName))
    for line in toc:lines() do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            local path = root .. "/" .. line:gsub("\\", "/")
            local f = assert(io.open(path))
            local src = f:read("*a")
            f:close()
            local chunk = assert((loadstring or load)(src, "@" .. line))
            chunk(addonName or "BadbUI", ns)
        end
    end
    toc:close()
    return ns
end

return Mock
