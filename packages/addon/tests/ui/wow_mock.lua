-- BadbUI test harness: mock minimale ma fedele dell'API WoW necessaria a caricare
-- Core/ e UI/ fuori dal gioco (Lua 5.1). Non simula il rendering: registra stato
-- (punti, dimensioni, colori, script) cosi' i test possono verificarlo.
--
-- Uso: local Mock = dofile("tests/mock/wow.lua"); Mock.install()
-- Poi: Mock.fire("ADDON_LOADED", "BadbUI"), Mock.setCombat(true), Mock.click(button)...
local Mock = {}

local unpack = unpack or table.unpack

---------------------------------------------------------------------------
-- Oggetti UI
---------------------------------------------------------------------------

local registry = {}      -- tutti gli oggetti creati
local eventFrames = {}   -- frame con RegisterEvent
local named = {}

local Object = {}
Object.__index = Object

local function new(kind, parent, name)
    local o = setmetatable({
        _type = kind, _parent = parent, _name = name, _shown = kind ~= "Frame_hidden",
        _w = 0, _h = 0, _points = {}, _scripts = {}, _hooks = {}, _events = {}, _children = {},
        _alpha = 1, _level = parent and (parent._level or 0) + 1 or 0, _strata = "MEDIUM",
        _text = "", _value = 0, _min = 0, _max = 0, _enabled = true, _mouse = false,
    }, Object)
    if parent then table.insert(parent._children, o) end
    registry[#registry + 1] = o
    if name then _G[name] = o; named[name] = o end
    return o
end
Mock.new = new

-- Qualsiasi metodo non implementato esplicitamente e' un no-op che registra la chiamata.
-- Solo nomi con iniziale maiuscola (metodi API): i campi minuscoli restano nil.
setmetatable(Object, { __index = function(_, k)
    if type(k) ~= "string" or not k:find("^%u") then return nil end
    return function(self, ...)
        self._calls = self._calls or {}
        self._calls[k] = { ... }
    end
end })

function Object:GetObjectType() return self._type end
function Object:IsObjectType(t) return self._type == t end
function Object:GetName() return self._name end
function Object:GetParent() return self._parent end
function Object:SetParent(p) self._parent = p end
function Object:GetChildren() return unpack(self._children) end

function Object:SetSize(w, h) self._w, self._h = w or 0, h or 0; self:_sizeChanged() end
function Object:SetWidth(w) self._w = w or 0; self:_sizeChanged() end
function Object:SetHeight(h) self._h = h or 0; self:_sizeChanged() end
function Object:GetWidth()
    if self._w == 0 and #self._points >= 2 and self._parent then return self._parent:GetWidth() end
    return self._w
end
function Object:GetHeight()
    if self._h == 0 and #self._points >= 2 and self._parent then return self._parent:GetHeight() end
    return self._h
end
function Object:GetSize() return self:GetWidth(), self:GetHeight() end
function Object:_sizeChanged()
    local fn = self._scripts.OnSizeChanged
    if fn then fn(self, self._w, self._h) end
end

function Object:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    table.insert(self._points, { point, rel, relPoint or point, x or 0, y or 0 })
end
function Object:ClearAllPoints() self._points = {} end
function Object:SetAllPoints(rel) self._points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } } end
function Object:GetPoint(i)
    local p = self._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Object:GetNumPoints() return #self._points end

function Object:Show()
    if self._shown then return end
    self._shown = true
    if self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Object:Hide()
    if not self._shown then return end
    self._shown = false
    if self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Object:SetShown(v) if v then self:Show() else self:Hide() end end
function Object:IsShown() return self._shown end
function Object:IsVisible()
    local o = self
    while o do if not o._shown then return false end; o = o._parent end
    return true
end

function Object:SetAlpha(a) self._alpha = a end
function Object:SetScale(s) self._scale = s end
function Object:GetScale() return self._scale or 1 end
function Object:GetEffectiveScale()
    local s, o = 1, self
    while o do s = s * (o._scale or 1); o = o._parent end
    return s
end
function Object:GetAlpha() return self._alpha end
function Object:SetFrameLevel(l) self._level = l end
function Object:GetFrameLevel() return self._level end
function Object:SetFrameStrata(s) self._strata = s end
function Object:GetFrameStrata() return self._strata end
function Object:EnableMouse(v) self._mouse = v and true or false end
function Object:IsMouseEnabled() return self._mouse end
function Object:IsMouseOver() return self._mouseOver or false end

function Object:SetScript(name, fn) self._scripts[name] = fn end
function Object:GetScript(name) return self._scripts[name] end
function Object:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...) if old then old(...) end; return fn(...) end
end
function Object:HasScript() return true end

function Object:RegisterEvent(e) self._events[e] = true; eventFrames[self] = true end
function Object:UnregisterEvent(e) self._events[e] = nil end
function Object:UnregisterAllEvents() self._events = {} end
function Object:IsEventRegistered(e) return self._events[e] or false end

-- Region factory
function Object:CreateTexture(name, layer)
    local t = new("Texture", self, name); t._layer = layer; return t
end
function Object:CreateFontString(name, layer)
    local t = new("FontString", self, name); t._layer = layer; return t
end
function Object:CreateAnimationGroup() return new("AnimationGroup", self) end

-- Texture
function Object:SetTexture(tex) self._texture = tex end
function Object:GetTexture() return self._texture end
function Object:SetColorTexture(r, g, b, a) self._color = { r, g, b, a or 1 } end
function Object:SetVertexColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function Object:GetVertexColor() local c = self._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Object:SetGradient(orient, c1, c2) self._gradient = { orient, c1, c2 } end
function Object:SetRotation(r) self._rotation = r end

-- FontString / EditBox
function Object:SetText(t)
    self._text = t == nil and "" or tostring(t)
    if self._type == "EditBox" and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function Object:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Object:GetText() return self._text end
function Object:GetStringWidth() return #(self._text or "") * 6 end
function Object:GetStringHeight() return 12 end
function Object:SetTextColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function Object:GetTextColor() local c = self._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Object:SetFontObject(o) self._font = o end
function Object:GetFontObject() return self._font end
function Object:SetFont(path, size, flags) self._fontPath, self._fontSize, self._fontFlags = path, size, flags; return true end
function Object:GetFont() return self._fontPath, self._fontSize, self._fontFlags end
function Object:SetFocus() self._focus = true; if self._scripts.OnEditFocusGained then self._scripts.OnEditFocusGained(self) end end
function Object:ClearFocus() if not self._focus then return end; self._focus = false; if self._scripts.OnEditFocusLost then self._scripts.OnEditFocusLost(self) end end
function Object:HasFocus() return self._focus or false end
function Object:Insert(s) self:SetText((self._text or "") .. s) end

-- Button
function Object:SetFontString(fs) self._fontString = fs end
function Object:GetFontString() return self._fontString end
function Object:Enable() self._enabled = true end
function Object:Disable() self._enabled = false end
function Object:IsEnabled() return self._enabled end
function Object:Click(btn)
    if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton", false) end
end
function Object:RegisterForDrag() end
function Object:RegisterForClicks() end

-- Slider / StatusBar
function Object:SetMinMaxValues(a, b) self._min, self._max = a, b; if self._value < a then self._value = a end; if self._value > b then self._value = b end end
function Object:GetMinMaxValues() return self._min, self._max end
function Object:SetValue(v, user)
    v = math.max(self._min, math.min(self._max, v))
    local changed = v ~= self._value
    self._value = v
    if self._scripts.OnValueChanged and (changed or user) then self._scripts.OnValueChanged(self, v, user) end
end
function Object:GetValue() return self._value end
function Object:SetStatusBarColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function Object:GetStatusBarColor() local c = self._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Object:SetThumbTexture(t) self._thumb = t end
function Object:GetThumbTexture() return self._thumb end

-- ScrollFrame
function Object:SetScrollChild(c) self._scrollChild = c end
function Object:GetScrollChild() return self._scrollChild end
function Object:SetVerticalScroll(v) self._vscroll = v end
function Object:GetVerticalScroll() return self._vscroll or 0 end

-- Movimento
function Object:StartMoving() self._moving = true end
function Object:StopMovingOrSizing() self._moving = false end
function Object:StartSizing() self._sizing = true end

-- Font object (CreateFont)
function Object:SetShadowColor() end
function Object:SetShadowOffset() end

---------------------------------------------------------------------------
-- Globali WoW
---------------------------------------------------------------------------

local state = { combat = false, time = 0, timers = {}, build = 16001 }
Mock.state = state

function Mock.install(opts)
    opts = opts or {}
    state.build = opts.interface or 16001

    _G.UIParent = new("Frame", nil, "UIParent")
    UIParent._w, UIParent._h = 1920, 1080
    _G.WorldFrame = new("Frame", nil, "WorldFrame")
    _G.GameTooltip = new("GameTooltip", UIParent, "GameTooltip")
    GameTooltip._lines = {}
    function GameTooltip:SetOwner(o) self._owner = o; self._lines = {} end
    function GameTooltip:ClearLines() self._lines = {} end
    function GameTooltip:AddLine(t) table.insert(self._lines, t) end
    function GameTooltip:AddDoubleLine(l, r) table.insert(self._lines, l .. " | " .. r) end
    _G.DEFAULT_CHAT_FRAME = new("Frame", UIParent, "DEFAULT_CHAT_FRAME")
    Mock.chat = {}
    function DEFAULT_CHAT_FRAME:AddMessage(m) table.insert(Mock.chat, m) end

    _G.CreateFrame = function(kind, name, parent, template)
        local f = new(kind or "Frame", parent, name)
        f._template = template
        return f
    end
    _G.CreateFont = function(name)
        local f = new("Font", nil, name)
        return f
    end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end } end

    _G.GetBuildInfo = function() return "1.60.0", "99999", "Nov 1 2026", state.build end
    _G.InCombatLockdown = function() return state.combat end
    _G.GetTime = function() return state.time end
    _G.GetScreenWidth = function() return 1920 end
    _G.GetScreenHeight = function() return 1080 end
    _G.GetPhysicalScreenSize = function() return state.physW or 1920, state.physH or 1080 end
    _G.GetLocale = function() return opts.locale or "itIT" end
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "Realm" end
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    _G.GetSpecialization = function() return 1 end
    _G.IsControlKeyDown = function() return false end
    _G.IsShiftKeyDown = function() return false end
    _G.IsAltKeyDown = function() return false end
    _G.IsMouseButtonDown = function() return false end
    _G.PlaySound = function() end
    _G.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2 }
    _G.UISpecialFrames = {}
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.date = os.date
    _G.time = os.time
    _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    _G.strsplit = function(sep, s)
        local out = {}
        for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
        return unpack(out)
    end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end; return false end
    _G.format = string.format
    _G.Mixin = function(o, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end; return o end
    _G.CopyTable = function(t) local o = {}; for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end; return o end
    _G.securecall = function(fn, ...) return fn(...) end
    _G.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = a, b, c
        if type(a) == "string" then tbl, name, fn = _G, a, b end
        local old = tbl[name]
        tbl[name] = function(...) local r = { old(...) }; fn(...); return unpack(r) end
    end
    _G.issecretvalue = opts.secrets and function(v) return type(v) == "table" and v.__secret == true end or nil

    _G.C_Timer = {
        After = function(sec, fn) table.insert(state.timers, { at = state.time + sec, fn = fn }) end,
        NewTicker = function(sec, fn) local t = { Cancel = function(self) self.cancelled = true end }; return t end,
        NewTimer = function(sec, fn) local t = { Cancel = function(self) self.cancelled = true end }; table.insert(state.timers, { at = state.time + sec, fn = fn, handle = t }); return t end,
    }
    _G.C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "test" or nil end, IsAddOnLoaded = function() return false end }
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(panel, title) return { GetID = function() return title end } end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
    }
    _G.SlashCmdList = {}
    _G.C_EditMode = nil
    _G.EditModeManagerFrame = nil
end

---------------------------------------------------------------------------
-- Pilotaggio
---------------------------------------------------------------------------

function Mock.fire(event, ...)
    for f in pairs(eventFrames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

function Mock.setCombat(on)
    state.combat = on
    Mock.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

function Mock.advance(sec)
    state.time = state.time + sec
    local due = {}
    for i = #state.timers, 1, -1 do
        local t = state.timers[i]
        if t.at <= state.time then table.remove(state.timers, i); due[#due + 1] = t end
    end
    for _, t in ipairs(due) do if not (t.handle and t.handle.cancelled) then t.fn() end end
end

function Mock.click(o, btn)
    if o._scripts.OnMouseDown then o._scripts.OnMouseDown(o, btn or "LeftButton") end
    if o._scripts.OnMouseUp then o._scripts.OnMouseUp(o, btn or "LeftButton") end
    o:Click(btn)
end

function Mock.script(o, name, ...)
    local fn = o._scripts[name]
    if fn then return fn(o, ...) end
end

function Mock.objects() return registry end

-- Carica i file elencati nella TOC con (addonName, ns) come vararg, come fa il client.
-- filter(path) -> bool sceglie quali file caricare.
function Mock.loadAddon(tocPath, addonName, filter)
    local base = tocPath:match("^(.*)/[^/]+$") or "."
    local ns = {}
    local files = {}
    for line in io.lines(tocPath) do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            local path = line:gsub("\\", "/")
            if not filter or filter(path) then files[#files + 1] = path end
        end
    end
    for _, path in ipairs(files) do
        local chunk, err = loadfile(base .. "/" .. path)
        if not chunk then error("Errore di sintassi in " .. path .. ": " .. tostring(err), 0) end
        local ok, runErr = pcall(chunk, addonName, ns)
        if not ok then error("Errore caricando " .. path .. ": " .. tostring(runErr), 0) end
    end
    return ns, files
end

return Mock
