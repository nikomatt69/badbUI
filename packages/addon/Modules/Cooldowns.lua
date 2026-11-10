-- BadbUI - Cooldowns
-- Numeri dei cooldown con il font del tema, colore per tempo rimanente, swipe/edge/bling
-- configurabili e "pulse" al centro dello schermo quando un'abilita' torna pronta.
--
-- Scelte per Forever:
--  * Il testo del countdown e' quello nativo del client (CVar countdownForCooldowns):
--    funziona anche quando la durata e' un secret value, perche' lo disegna il client.
--    BadbUI si limita a stilizzarlo.
--  * Colore per tempo rimanente, soglia GCD e pulse richiedono la durata: se e' secret
--    (combattimento) quelle funzioni si disattivano per quel cooldown, senza errori.
--  * Nessun combat log: lo stato arriva solo dagli hook sui frame Cooldown.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat, DB, FM, Lib = Badb.Compat, Badb.DB, Badb.FrameManager, Badb.ActionBarsLib

local M = Badb.Modules:New("Cooldowns", {
    title = "Cooldown",
    category = L["Barre"],
    defaults = {
        enabled = true,
        numbers = true,
        fontScale = 0.42,       -- dimensione testo come frazione della larghezza del pulsante
        minFontSize = 8,
        minDuration = 1.6,      -- sotto questa durata (GCD) niente numeri
        colorByTime = true,
        expiringThreshold = 5,  -- secondi: sotto diventa colore "danger"
        swipeAlpha = 0.75,
        drawEdge = false,
        drawBling = true,
        allCooldowns = false,   -- anche buff, oggetti, borse...
        pulse = true,
        pulseMinDuration = 6,
        pulseSize = 56,
    },
})

M.options = {
    { type = "header", label = L["Numeri"] },
    { type = "toggle", path = "numbers", label = L["Mostra i secondi rimanenti"] },
    { type = "range", path = "fontScale", label = L["Dimensione testo (rispetto al pulsante)"], min = 0.2, max = 0.8, step = 0.02 },
    { type = "range", path = "minDuration", label = L["Nascondi sotto (s, esclude il GCD)"], min = 0, max = 5, step = 0.1 },
    { type = "toggle", path = "colorByTime", label = L["Colore per tempo rimanente"] },
    { type = "range", path = "expiringThreshold", label = L["Soglia 'in scadenza' (s)"], min = 0, max = 15, step = 1 },
    { type = "header", label = L["Animazione"] },
    { type = "range", path = "swipeAlpha", label = L["Opacita' dello swipe"], min = 0, max = 1, step = 0.05 },
    { type = "toggle", path = "drawEdge", label = L["Bordo luminoso sullo swipe"] },
    { type = "toggle", path = "drawBling", label = L["Lampo a fine cooldown"] },
    { type = "toggle", path = "allCooldowns", label = L["Applica a tutti i cooldown (buff, oggetti, borse)"] },
    { type = "header", label = "Pulse" },
    { type = "toggle", path = "pulse", label = L["Icona al centro quando un'abilita' torna pronta"] },
    { type = "range", path = "pulseMinDuration", label = L["Solo cooldown piu' lunghi di (s)"], min = 0, max = 60, step = 1 },
    { type = "range", path = "pulseSize", label = L["Dimensione pulse"], min = 32, max = 128, step = 4 },
    { type = "execute", label = L["Prova pulse"], func = function() M:Pulse(GetSpellTexture and GetSpellTexture(6603) or 136243) end },
}

local tracked = setmetatable({}, { __mode = "k" }) -- cooldown dei pulsanti d'azione -> pulsante
local active = {}                                    -- cooldown -> { start, duration }
local styled = setmetatable({}, { __mode = "k" })    -- cooldown -> font originale

---------------------------------------------------------------------------
-- Stile
---------------------------------------------------------------------------
local function countdownFS(cd)
    return cd.GetCountdownFontString and cd:GetCountdownFontString()
end

local function styleCooldown(self, cd)
    local fs = countdownFS(cd)
    if fs then
        if not styled[cd] then styled[cd] = { fs:GetFont() } end
        local w = cd:GetWidth() or 36
        if w <= 0 then w = 36 end
        local size = math.max(self:Get("minFontSize") or 8, math.floor(w * (self:Get("fontScale") or 0.42) + 0.5))
        fs:SetFont(Lib.Font("number"), size, "OUTLINE")
        fs:SetTextColor(Lib.Color("text"))
    end
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, self:Get("swipeAlpha") or 0.75) end
    if cd.SetDrawEdge then cd:SetDrawEdge(self:Get("drawEdge") and true or false) end
    if cd.SetDrawBling then cd:SetDrawBling(self:Get("drawBling") and true or false) end
end

local function unstyleCooldown(cd)
    local f = styled[cd]
    local fs = countdownFS(cd)
    if f and fs and f[1] then fs:SetFont(f[1], f[2], f[3]); fs:SetTextColor(1, 1, 1) end
    styled[cd] = nil
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.8) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(true) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
end

local function wants(self, cd)
    if not self.enabled then return false end
    if tracked[cd] then return true end
    -- Cooldown di nameplate e frame protetti sono "forbidden": mai toccarli.
    return self:Get("allCooldowns") and not cd:IsForbidden() or false
end

local driver = CreateFrame("Frame")
driver:Hide()
M._driver = driver -- esposto per i test

local function onSetCooldown(cd, start, duration)
    local self = M
    if not wants(self, cd) then return end
    styleCooldown(self, cd)
    if Compat.IsSecret(start) or Compat.IsSecret(duration) or not duration then
        -- Durata opaca: il client disegna comunque il countdown, niente colore/soglia.
        active[cd] = nil
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not self:Get("numbers")) end
        return
    end
    local short = duration < (self:Get("minDuration") or 0)
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(short or not self:Get("numbers"))
    end
    if duration > 0 and start and start > 0 then
        active[cd] = { start = start, duration = duration }
        driver:Show()
    else
        active[cd] = nil
    end
end

local function onDurationObject(cd)
    -- API Midnight-style: la durata arriva come oggetto opaco. Solo stile.
    local self = M
    if not wants(self, cd) then return end
    active[cd] = nil
    styleCooldown(self, cd)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not self:Get("numbers")) end
end

local elapsedAcc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedAcc = elapsedAcc + elapsed
    if elapsedAcc < 0.1 then return end
    elapsedAcc = 0
    local self = M
    local now = GetTime()
    local threshold = self:Get("expiringThreshold") or 5
    local byTime = self:Get("colorByTime")
    for cd, info in pairs(active) do
        local remaining = info.start + info.duration - now
        if remaining <= 0 or not cd:IsShown() then
            active[cd] = nil
        elseif byTime then
            local fs = countdownFS(cd)
            if fs then
                if remaining <= threshold then fs:SetTextColor(Lib.Color("danger"))
                elseif remaining <= 60 then fs:SetTextColor(Lib.Color("text"))
                else fs:SetTextColor(Lib.Color("textDim")) end
            end
        end
    end
    if next(active) == nil then driver:Hide() end
end)

---------------------------------------------------------------------------
-- Pulse
---------------------------------------------------------------------------
local pulse

local function createPulse()
    local f = CreateFrame("Frame", "BadbUICooldownPulse", UIParent)
    f:SetSize(56, 56)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.border = Lib.CreateBorder(f, 1)
    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetPoint("TOPLEFT", -1, 1)
    f.glow:SetPoint("BOTTOMRIGHT", 1, -1)
    f.glow:SetBlendMode("ADD")

    local ag = f:CreateAnimationGroup()
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.12); fadeIn:SetOrder(1)
    local grow = ag:CreateAnimation("Scale")
    grow:SetScaleFrom(0.7, 0.7); grow:SetScaleTo(1.15, 1.15); grow:SetDuration(0.25); grow:SetOrder(1)
    local hold = ag:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(0.35); hold:SetOrder(2)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.3); fadeOut:SetOrder(3)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
    return f
end

function M:StylePulse()
    if not pulse then return end
    local size = self:Get("pulseSize") or 56
    pulse:SetSize(size, size)
    pulse.bg:SetColorTexture(Lib.Color("bg"))
    Lib.StyleBorder(pulse.border, 1)
    local r, g, b = Lib.Color("accent")
    pulse.glow:SetColorTexture(r, g, b, 0.18)
end

function M:Pulse(texture)
    if not pulse or not texture then return end
    pulse.icon:SetTexture(texture)
    pulse.anim:Stop()
    pulse:SetAlpha(0)
    pulse:Show()
    pulse.anim:Play()
end

local function onCooldownDone(cd)
    local self = M
    if not self.enabled or not self:Get("pulse") then return end
    local b = tracked[cd]
    local info = cd.badbLast
    if not b or not info then return end
    if info < (self:Get("pulseMinDuration") or 6) then return end
    local r = Lib.Regions(b)
    local tex = r.icon and r.icon:GetTexture()
    if tex and not Compat.IsSecret(tex) then self:Pulse(tex) end
end

---------------------------------------------------------------------------
-- Hook
---------------------------------------------------------------------------
local metaHooked = false
local function hookMeta()
    if metaHooked then return end
    local sample = _G.ActionButton1Cooldown or CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    local mt = getmetatable(sample)
    local index = mt and mt.__index
    if type(index) ~= "table" then return end
    metaHooked = true
    hooksecurefunc(index, "SetCooldown", function(cd, start, duration)
        -- Durata dell'ultimo cooldown "lungo" per decidere il pulse a fine timer.
        if tracked[cd] and not Compat.IsSecret(duration) and duration and duration > 0 then
            cd.badbLast = duration
        end
        onSetCooldown(cd, start, duration)
    end)
    if index.SetCooldownFromDurationObject then
        hooksecurefunc(index, "SetCooldownFromDurationObject", onDurationObject)
    end
    if index.SetCooldownDuration then
        hooksecurefunc(index, "SetCooldownDuration", function(cd, duration)
            onSetCooldown(cd, GetTime(), duration)
        end)
    end
end

local function trackButtons()
    Lib.ForEachButton(function(b)
        local cd = Lib.Regions(b).cooldown
        if cd and not tracked[cd] then
            tracked[cd] = b
            cd:HookScript("OnCooldownDone", onCooldownDone)
        end
    end)
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------
local cvarKey = "cooldownsOriginalCountdownCVar"

local function applyCVar(self)
    if not C_CVar then return end
    local g = DB.sv.global
    if g[cvarKey] == nil then g[cvarKey] = C_CVar.GetCVar("countdownForCooldowns") or "0" end
    if self:Get("numbers") then C_CVar.SetCVar("countdownForCooldowns", "1") end
end

local function restoreCVar()
    if not C_CVar then return end
    local g = DB.sv.global
    if g[cvarKey] ~= nil then
        C_CVar.SetCVar("countdownForCooldowns", g[cvarKey])
        g[cvarKey] = nil
    end
end

function M:ApplyAll()
    if not self.enabled then return end
    trackButtons()
    applyCVar(self)
    for cd in pairs(tracked) do styleCooldown(self, cd) end
    if self:Get("allCooldowns") then
        for cd in pairs(styled) do styleCooldown(self, cd) end
    else
        for cd in pairs(styled) do if not tracked[cd] then unstyleCooldown(cd) end end
    end
    self:StylePulse()
end

function M:OnInitialize()
    pulse = createPulse()
    FM:Register("CooldownPulse", { frame = pulse, title = L["Pulse cooldown"], category = L["Barre"], hideable = false })
end

function M:OnEnable()
    self.enabled = true
    hookMeta()
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == self.name then self:ApplyAll() end
    end)
    self:On("BADB_THEME_CHANGED", function() self:ApplyAll() end)
    self:On("PLAYER_ENTERING_WORLD", function() self:ApplyAll() end)
    self:On("UNIT_PET", function(_, unit) if unit == "player" then self:ApplyAll() end end)
    self:ApplyAll()
end

function M:OnProfileChanged() self:ApplyAll() end

function M:OnDisable()
    self.enabled = false
    wipe(active)
    driver:Hide()
    for cd in pairs(styled) do unstyleCooldown(cd) end
    for cd in pairs(tracked) do unstyleCooldown(cd) end
    restoreCVar()
    if pulse then pulse.anim:Stop(); pulse:Hide() end
end
