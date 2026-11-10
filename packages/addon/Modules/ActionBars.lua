-- BadbUI - ActionBars
-- Stile dei pulsanti d'azione Blizzard (icone piatte con bordo del tema), keybind abbreviati,
-- colore per fuori portata / mana insufficiente, dissolvenza delle barre al mouseover.
--
-- Regole Forever:
--  * Posizione, dimensione, righe e spaziatura delle barre appartengono all'Edit Mode:
--    questo modulo non chiama mai SetPoint/SetScale sulle barre (il layout viaggia nel
--    profilo tramite EditModeBridge).
--  * Si toccano solo texture, font string, alpha e frame figli non protetti: nulla che
--    il client blocchi in combattimento, quindi niente taint sui pulsanti secure.
--  * Valori restituiti da API di stato (IsUsableAction ecc.) passano da Compat.IsSecret.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat, Lib = Badb.Compat, Badb.ActionBarsLib

local fadeDefaults, fadeOptions = {}, {}
for _, bar in ipairs(Lib.BARS) do fadeDefaults[bar.key] = false end

local M = Badb.Modules:New("ActionBars", {
    title = L["Barre azioni"],
    category = L["Barre"],
    defaults = {
        enabled = true,
        -- Stile
        skin = true,
        iconZoom = 0.08,
        borderSize = 1,
        backgroundAlpha = 0.6,
        -- Testi
        showKeybinds = true,
        shortKeybinds = true,
        keybindSize = 11,
        showMacroNames = false,
        macroNameSize = 10,
        countSize = 13,
        -- Stato
        rangeColor = true,
        manaColor = true,
        unusableColor = true,
        -- Dissolvenza
        fade = fadeDefaults,
        fadeAlpha = 0,
        fadeShowInCombat = true,
        fadeShowWithTarget = false,
        fadeDuration = 0.2,
    },
})

M.options = {
    { type = "header", label = L["Stile pulsanti"] },
    { type = "toggle", path = "skin", label = L["Icone piatte con bordo del tema"] },
    { type = "range", path = "iconZoom", label = L["Zoom icona"], min = 0, max = 0.2, step = 0.01 },
    { type = "range", path = "borderSize", label = L["Spessore bordo"], min = 0, max = 4, step = 1 },
    { type = "range", path = "backgroundAlpha", label = L["Opacita' sfondo slot"], min = 0, max = 1, step = 0.05 },
    { type = "header", label = L["Testi"] },
    { type = "toggle", path = "showKeybinds", label = L["Mostra keybind"] },
    { type = "toggle", path = "shortKeybinds", label = L["Keybind abbreviati (S, C, A, M4, N5...)"] },
    { type = "range", path = "keybindSize", label = L["Dimensione keybind"], min = 6, max = 20, step = 1 },
    { type = "toggle", path = "showMacroNames", label = L["Mostra nomi delle macro"] },
    { type = "range", path = "macroNameSize", label = L["Dimensione nomi macro"], min = 6, max = 18, step = 1 },
    { type = "range", path = "countSize", label = L["Dimensione cariche/quantita'"], min = 6, max = 22, step = 1 },
    { type = "header", label = L["Colore dello stato"] },
    { type = "toggle", path = "rangeColor", label = L["Rosso se il bersaglio e' fuori portata"] },
    { type = "toggle", path = "manaColor", label = L["Blu se manca la risorsa"] },
    { type = "toggle", path = "unusableColor", label = L["Grigio se non utilizzabile"] },
    { type = "header", label = L["Dissolvenza (mouseover)"] },
    { type = "range", path = "fadeAlpha", label = L["Opacita' quando nascoste"], min = 0, max = 1, step = 0.05 },
    { type = "toggle", path = "fadeShowInCombat", label = L["Mostra sempre in combattimento"] },
    { type = "toggle", path = "fadeShowWithTarget", label = L["Mostra quando hai un bersaglio"] },
    { type = "range", path = "fadeDuration", label = L["Durata transizione (s)"], min = 0, max = 1, step = 0.05 },
}
for _, bar in ipairs(Lib.BARS) do
    M.options[#M.options + 1] = { type = "toggle", path = "fade." .. bar.key, label = "Mouseover: " .. bar.title }
end

-- Stato per pulsante: originali salvati alla prima modifica per il ripristino.
local state = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function S(b)
    local s = state[b]
    if not s then s = {}; state[b] = s end
    return s
end

---------------------------------------------------------------------------
-- Stile
---------------------------------------------------------------------------
local function setRegionAlpha(s, key, region, alpha)
    if not region then return end
    if s[key] == nil then s[key] = region:GetAlpha() end
    region:SetAlpha(alpha)
end

local function restoreRegionAlpha(s, key, region)
    if region and s[key] ~= nil then region:SetAlpha(s[key]) end
    s[key] = nil
end

local function skinButton(self, b)
    local r, s = Lib.Regions(b), S(b)
    if not r.icon then return end
    local z = self:Get("iconZoom") or 0.08
    r.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    if r.mask and not s.maskRemoved and r.icon.RemoveMaskTexture then
        r.icon:RemoveMaskTexture(r.mask)
        s.maskRemoved = true
    end
    setRegionAlpha(s, "normalAlpha", r.normal, 0)
    setRegionAlpha(s, "slotArtAlpha", r.slotArt, 0)
    setRegionAlpha(s, "slotBgAlpha", r.slotBg, 0)

    if not s.bg then
        s.bg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        s.bg:SetAllPoints(b)
    end
    local br, bgc, bb = Lib.Color("bg")
    s.bg:SetColorTexture(br, bgc, bb, self:Get("backgroundAlpha") or 0.6)
    s.bg:Show()

    local size = self:Get("borderSize") or 1
    if not s.border then s.border = Lib.CreateBorder(b, size) else Lib.StyleBorder(s.border, size) end
    s.border:SetShown(size > 0)
    s.skinned = true
end

local function unskinButton(b)
    local s = state[b]
    if not s or not s.skinned then return end
    local r = Lib.Regions(b)
    if r.icon then
        r.icon:SetTexCoord(0, 1, 0, 1)
        if s.maskRemoved and r.mask and r.icon.AddMaskTexture then r.icon:AddMaskTexture(r.mask) end
    end
    s.maskRemoved = nil
    restoreRegionAlpha(s, "normalAlpha", r.normal)
    restoreRegionAlpha(s, "slotArtAlpha", r.slotArt)
    restoreRegionAlpha(s, "slotBgAlpha", r.slotBg)
    if s.bg then s.bg:Hide() end
    if s.border then s.border:Hide() end
    s.skinned = nil
end

---------------------------------------------------------------------------
-- Testi
---------------------------------------------------------------------------
local function rememberFont(s, key, fs)
    if fs and not s[key] then s[key] = { fs:GetFont() } end
end

local function restoreFont(s, key, fs)
    local f = s[key]
    if fs and f and f[1] then fs:SetFont(f[1], f[2], f[3]) end
    s[key] = nil
end

local function bindingKey(b)
    if b.commandName then return GetBindingKey(b.commandName) end
    local name = b:GetName()
    return name and GetBindingKey("CLICK " .. name .. ":LeftButton")
end

local function updateHotkey(self, b)
    if not self.enabled then return end
    local r, s = Lib.Regions(b), S(b)
    local hk = r.hotkey
    if not hk then return end
    rememberFont(s, "hotkeyFont", hk)
    hk:SetFont(Lib.Font("number"), self:Get("keybindSize") or 11, "OUTLINE")
    hk:SetTextColor(Lib.Color("text"))
    if not self:Get("showKeybinds") then
        setRegionAlpha(s, "hotkeyAlpha", hk, 0)
        return
    end
    restoreRegionAlpha(s, "hotkeyAlpha", hk)
    if self:Get("shortKeybinds") then
        local short = Lib.ShortKey(bindingKey(b))
        if short then hk:SetText(short) end
    end
end

local function updateTexts(self, b)
    local r, s = Lib.Regions(b), S(b)
    updateHotkey(self, b)
    if r.macro then
        rememberFont(s, "macroFont", r.macro)
        r.macro:SetFont(Lib.Font("normal"), self:Get("macroNameSize") or 10, "OUTLINE")
        if self:Get("showMacroNames") then restoreRegionAlpha(s, "macroAlpha", r.macro)
        else setRegionAlpha(s, "macroAlpha", r.macro, 0) end
    end
    if r.count then
        rememberFont(s, "countFont", r.count)
        r.count:SetFont(Lib.Font("number"), self:Get("countSize") or 13, "OUTLINE")
    end
end

local function restoreTexts(b)
    local s = state[b]
    if not s then return end
    local r = Lib.Regions(b)
    restoreFont(s, "hotkeyFont", r.hotkey)
    restoreFont(s, "macroFont", r.macro)
    restoreFont(s, "countFont", r.count)
    restoreRegionAlpha(s, "hotkeyAlpha", r.hotkey)
    restoreRegionAlpha(s, "macroAlpha", r.macro)
    if b.UpdateHotkeys then pcall(b.UpdateHotkeys, b, b.buttonType) end
end

---------------------------------------------------------------------------
-- Colore per stato (portata / risorsa / utilizzabile)
---------------------------------------------------------------------------
local function colorIcon(self, b)
    if not self.enabled then return end
    local r = Lib.Regions(b)
    if not r.icon then return end
    local s = S(b)
    local action = b.action
    if not action or not HasAction or not HasAction(action) then return end
    local usable, noMana = IsUsableAction(action)
    if Compat.IsSecret(usable) or Compat.IsSecret(noMana) then return end
    if s.outOfRange and self:Get("rangeColor") then
        r.icon:SetVertexColor(Lib.Color("danger"))
    elseif noMana and self:Get("manaColor") then
        r.icon:SetVertexColor(Lib.Color("mana"))
    elseif not usable and self:Get("unusableColor") then
        r.icon:SetVertexColor(Lib.Color("disabled"))
    else
        r.icon:SetVertexColor(1, 1, 1)
    end
end

local function hookButton(self, b)
    if hooked[b] then return end
    hooked[b] = true
    if b.UpdateHotkeys then
        hooksecurefunc(b, "UpdateHotkeys", function(btn) updateHotkey(self, btn) end)
    end
    if b.UpdateUsable then
        hooksecurefunc(b, "UpdateUsable", function(btn) colorIcon(self, btn) end)
    end
end

local rangeHooked = false
local function hookRange(self)
    if rangeHooked then return end
    rangeHooked = true
    -- Mainline: ActionButton_UpdateRangeIndicator(self, checksRange, inRange)
    if type(ActionButton_UpdateRangeIndicator) == "function" then
        hooksecurefunc("ActionButton_UpdateRangeIndicator", function(b, checksRange, inRange)
            if Compat.IsSecret(checksRange) or Compat.IsSecret(inRange) then return end
            S(b).outOfRange = checksRange and inRange == false or false
            colorIcon(self, b)
        end)
    end
end

---------------------------------------------------------------------------
-- Dissolvenza
---------------------------------------------------------------------------
local fader = CreateFrame("Frame")
fader:Hide()
M._fader = fader -- esposto per i test
local fadeElapsed = 0

local function isHovered(bar, frame)
    if frame:IsMouseOver() then return true end
    -- Lo SpellFlyout aperto da un pulsante della barra conta come mouseover.
    local flyout = _G.SpellFlyout
    if flyout and flyout:IsShown() and flyout:IsMouseOver() then
        local parent = flyout:GetParent()
        return parent and parent.GetParent and parent:GetParent() == frame
    end
    return false
end

local function targetAlpha(self, bar, frame)
    if not self:Get("fade." .. bar.key) then return 1 end
    if self:Get("fadeShowInCombat") and InCombatLockdown() then return 1 end
    if self:Get("fadeShowWithTarget") and UnitExists("target") then return 1 end
    -- Con lo spellbook o il cursore carico (drag di un'abilita') la barra resta visibile.
    if GetCursorInfo() then return 1 end
    if isHovered(bar, frame) then return 1 end
    return self:Get("fadeAlpha") or 0
end

local function anyFade(self)
    for _, bar in ipairs(Lib.BARS) do
        if self:Get("fade." .. bar.key) then return true end
    end
    return false
end

fader:SetScript("OnUpdate", function(_, elapsed)
    fadeElapsed = fadeElapsed + elapsed
    if fadeElapsed < 0.05 then return end
    local dt = fadeElapsed
    fadeElapsed = 0
    local self = M
    local dur = math.max(self:Get("fadeDuration") or 0.2, 0.001)
    for _, bar in ipairs(Lib.BARS) do
        local frame = Lib.GetBarFrame(bar)
        if frame and frame:IsShown() then
            local want = targetAlpha(self, bar, frame)
            local cur = frame:GetAlpha()
            if math.abs(cur - want) > 0.001 then
                local step = dt / dur
                local nextA = cur < want and math.min(want, cur + step) or math.max(want, cur - step)
                frame:SetAlpha(nextA)
            end
        end
    end
end)

local function updateFader(self)
    if self.enabled and anyFade(self) then
        fader:Show()
    else
        fader:Hide()
    end
    -- Le barre senza dissolvenza tornano sempre opache.
    for _, bar in ipairs(Lib.BARS) do
        local frame = Lib.GetBarFrame(bar)
        if frame and (not self.enabled or not self:Get("fade." .. bar.key)) and frame:GetAlpha() < 1 then
            frame:SetAlpha(1)
        end
    end
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------
function M:ApplyButton(b)
    hookButton(self, b)
    if self:Get("skin") then skinButton(self, b) else unskinButton(b) end
    updateTexts(self, b)
    colorIcon(self, b)
end

function M:ApplyAll()
    if not self.enabled then return end
    Lib.ForEachButton(function(b) self:ApplyButton(b) end)
    updateFader(self)
end

function M:OnEnable()
    -- self.enabled viene impostato dal sistema moduli dopo OnEnable: lo anticipiamo
    -- perche' ApplyAll e gli hook lo controllano.
    self.enabled = true
    hookRange(self)
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == self.name then self:ApplyAll() end
    end)
    self:On("BADB_THEME_CHANGED", function() self:ApplyAll() end)
    self:On("UPDATE_BINDINGS", function()
        Lib.ForEachButton(function(b) updateHotkey(self, b) end)
    end)
    -- Le barre extra e il famiglio possono comparire dopo il login.
    self:On("PLAYER_ENTERING_WORLD", function() self:ApplyAll() end)
    self:On("UNIT_PET", function(_, unit) if unit == "player" then self:ApplyAll() end end)
    self:On("UPDATE_SHAPESHIFT_FORMS", function() self:ApplyAll() end)
    self:ApplyAll()
end

function M:OnProfileChanged() self:ApplyAll() end

function M:OnDisable()
    self.enabled = false
    fader:Hide()
    Lib.ForEachButton(function(b)
        unskinButton(b)
        restoreTexts(b)
        local r = Lib.Regions(b)
        if r.icon then r.icon:SetVertexColor(1, 1, 1) end
        if b.UpdateUsable then pcall(b.UpdateUsable, b) end
    end)
    updateFader(self)
end

-- API pubblica per altri moduli/addon: riapplica lo stile a un pulsante esterno
-- (es. barre create da un altro modulo BadbUI).
function M:StyleExternalButton(b)
    if self.enabled then self:ApplyButton(b) end
end

