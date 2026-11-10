-- BadbUI - Unit Frames: elementi (vita, risorsa, nome, cast, aure, indicatori)
-- Regole Forever / secret values:
--   * I valori come UnitHealth possono essere opachi in combattimento: non si confrontano e
--     non si fa aritmetica su di loro. Si passano direttamente ai widget (SetValue, SetText,
--     SetTexture) che li accettano, sempre dentro pcall per i client che non li accettano.
--   * Quando serve una decisione (colore, testo) si usa Compat.SafeValue con un fallback neutro.
--   * Gli elementi qui sono figli NON protetti del bottone secure: si possono aggiornare,
--     mostrare e nascondere anche in combattimento. Solo dimensioni e ancoraggi del bottone
--     stesso passano da Events:RunOutOfCombat (vedi UnitFrames.lua).
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat = Badb.Compat

local UF = ns.UF
local Style = UF.Style
local E = {}
UF.Elements = E

local Safe, IsSecret = Compat.SafeValue, Compat.IsSecret

local function try(fn, ...)
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local function short(v)
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e4 then return string.format("%.1fk", v / 1e3) end
    return tostring(math.floor(v + 0.5))
end

-- Abbreviazione che funziona anche con valori secret (AbbreviateNumbers e' secret-aware).
local function abbreviate(v)
    if not IsSecret(v) then return short(v) end
    if AbbreviateNumbers then return try(AbbreviateNumbers, v) end
end

---------------------------------------------------------------------------
-- Stato dell'unita'
---------------------------------------------------------------------------
local function unitState(u)
    if not Safe(UnitIsConnected(u), true) then return "offline" end
    if Safe(UnitIsGhost(u), false) then return "ghost" end
    if Safe(UnitIsDead(u), false) then return "dead" end
end

local STATE_TEXT = { offline = "Offline", ghost = L["Spirito"], dead = L["Morto"] }

---------------------------------------------------------------------------
-- Costruzione
---------------------------------------------------------------------------
function E.Build(f)
    Style.Skin(f)

    local health = Style.StatusBar(f)
    f.Health = health

    local power = Style.StatusBar(f)
    f.Power = power

    -- Testi sopra le barre in un frame dedicato (sempre sopra la vita).
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints(health)
    over:SetFrameLevel(health:GetFrameLevel() + 3)
    f.Overlay = over
    f.Level = Style.Text(over, 11, "LEFT", "textDim")
    f.Name = Style.Text(over, 11, "LEFT", "text")
    f.HealthText = Style.Text(over, 11, "RIGHT", "text")
    f.PowerText = Style.Text(power, 9, "RIGHT", "textDim")

    -- Indicatori
    f.RaidIcon = over:CreateTexture(nil, "OVERLAY")
    f.RaidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.RaidIcon:SetSize(16, 16)
    f.RaidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
    f.RaidIcon:Hide()

    f.Leader = over:CreateTexture(nil, "OVERLAY")
    f.Leader:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon")
    f.Leader:SetSize(12, 12)
    f.Leader:SetPoint("CENTER", f, "TOPLEFT", 6, 0)
    f.Leader:Hide()

    f.Combat = over:CreateTexture(nil, "OVERLAY")
    f.Combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.Combat:SetTexCoord(0.5, 1, 0, 0.49)
    f.Combat:SetSize(18, 18)
    f.Combat:SetPoint("CENTER", f, "TOPRIGHT", -4, 0)
    f.Combat:Hide()

    -- Icona di classe (al posto del ritratto): fuori dal frame, a sinistra.
    f.ClassIcon = f:CreateTexture(nil, "ARTWORK")
    f.ClassIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    f.ClassIcon:Hide()

    -- Barra di lancio: sotto il frame, con icona a sinistra.
    local cast = Style.StatusBar(f)
    cast:Hide()
    Style.Skin(cast)
    cast.Icon = cast:CreateTexture(nil, "ARTWORK")
    cast.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cast.IconFrame = CreateFrame("Frame", nil, cast)
    cast.IconFrame:SetAllPoints(cast.Icon)
    Style.Skin(cast.IconFrame)
    cast.IconFrame:SetFrameLevel(cast:GetFrameLevel())
    cast.Text = Style.Text(cast, 10, "LEFT", "text")
    cast.Time = Style.Text(cast, 10, "RIGHT", "textDim")
    cast.Spark = cast:CreateTexture(nil, "OVERLAY")
    cast.Spark:SetTexture("Interface\\Buttons\\WHITE8X8")
    cast.Spark:SetWidth(1)
    cast.Spark:SetPoint("TOP", cast:GetStatusBarTexture(), "TOPRIGHT")
    cast.Spark:SetPoint("BOTTOM", cast:GetStatusBarTexture(), "BOTTOMRIGHT")
    cast.owner = f
    f.Castbar = cast

    f.Auras = { buttons = {} }
end

---------------------------------------------------------------------------
-- Layout (dimensioni elementi interni: non protetti, ma calcolati dalla config)
---------------------------------------------------------------------------
function E.Layout(f, c)
    local showPower = c.showPower and (c.powerHeight or 0) > 0
    local ph = showPower and c.powerHeight or 0
    local font = c.fontSize or 11

    f.Health:ClearAllPoints()
    f.Health:SetPoint("TOPLEFT", 1, -1)
    f.Health:SetPoint("TOPRIGHT", -1, -1)
    f.Health:SetPoint("BOTTOM", f, "BOTTOM", 0, showPower and (ph + 2) or 1)
    f.Health:SetStatusBarTexture(Style.Texture("statusbar"))

    f.Power:ClearAllPoints()
    f.Power:SetPoint("BOTTOMLEFT", 1, 1)
    f.Power:SetPoint("BOTTOMRIGHT", -1, 1)
    f.Power:SetHeight(math.max(ph, 1))
    f.Power:SetStatusBarTexture(Style.Texture("statusbar"))
    f.Power:SetShown(showPower)

    Style.RefreshText(f.Level, font)
    Style.RefreshText(f.Name, font)
    Style.RefreshText(f.HealthText, font)
    Style.RefreshText(f.PowerText, math.max(font - 2, 8))

    f.Level:ClearAllPoints()
    f.Level:SetPoint("LEFT", f.Overlay, "LEFT", 5, 0)
    f.Level:SetShown(c.showLevel and true or false)
    f.Name:ClearAllPoints()
    if c.showLevel then
        f.Name:SetPoint("LEFT", f.Level, "RIGHT", 4, 0)
    else
        f.Name:SetPoint("LEFT", f.Overlay, "LEFT", 5, 0)
    end
    f.Name:SetPoint("RIGHT", f.HealthText, "LEFT", -4, 0)
    f.Name:SetShown(c.showName and true or false)
    f.HealthText:ClearAllPoints()
    f.HealthText:SetPoint("RIGHT", f.Overlay, "RIGHT", -5, 0)
    f.HealthText:SetShown((c.showHealthValue or c.showHealthPercent) and true or false)
    f.PowerText:ClearAllPoints()
    f.PowerText:SetPoint("RIGHT", f.Power, "RIGHT", -4, 0)
    f.PowerText:SetShown(showPower and c.showPowerText and ph >= 8 and true or false)

    -- Icona di classe: quadrata, alta quanto il frame, a sinistra
    local h = f:GetHeight() > 0 and f:GetHeight() or (c.height or 40)
    f.ClassIcon:ClearAllPoints()
    f.ClassIcon:SetSize(h, h)
    f.ClassIcon:SetPoint("RIGHT", f, "LEFT", -4, 0)
    if not c.showClassIcon then f.ClassIcon:Hide() end

    -- Castbar
    local cast = f.Castbar
    cast.enabled = c.showCastbar and true or false
    local ch = c.castbarHeight or 16
    cast:ClearAllPoints()
    cast:SetHeight(ch)
    cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", ch + 3, -(c.castbarGap or 6))
    cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -(c.castbarGap or 6))
    cast:SetStatusBarTexture(Style.Texture("statusbar"))
    cast.Icon:ClearAllPoints()
    cast.Icon:SetSize(ch, ch)
    cast.Icon:SetPoint("RIGHT", cast, "LEFT", -3, 0)
    Style.RefreshText(cast.Text, math.max(font - 1, 8))
    Style.RefreshText(cast.Time, math.max(font - 1, 8))
    cast.Text:ClearAllPoints()
    cast.Text:SetPoint("LEFT", 4, 0)
    cast.Text:SetPoint("RIGHT", cast.Time, "LEFT", -4, 0)
    cast.Time:ClearAllPoints()
    cast.Time:SetPoint("RIGHT", -4, 0)
    local sr, sg, sb = Style.Color("text")
    cast.Spark:SetColorTexture(sr, sg, sb, 0.8)
    Style.Skin(cast); Style.Skin(cast.IconFrame)
    if not cast.enabled then cast:Hide() end

    -- Aure
    local a = f.Auras
    a.enabled = c.showAuras and true or false
    a.size = c.auraSize or 20
    a.max = c.auraMax or 8
    a.onlyMine = c.auraOnlyMine and true or false
    a.anchorBelow = c.showCastbar -- con castbar sotto, le aure vanno sopra
    for _, b in ipairs(a.buttons) do b:Hide() end

    -- Aura grande (CC, immunita', difensivi) al centro del frame, dal database curato Badb.Auras
    f.bigAuraEnabled = c.showBigAura and true or false
    f.bigAuraSize = math.max(12, math.min(48, (c.height or 40) - 4))
    if f.BigAura and not f.bigAuraEnabled then Badb.Auras:ClearIcon(f.BigAura) end

    Style.Skin(f)
end

---------------------------------------------------------------------------
-- Vita
---------------------------------------------------------------------------
local function healthColor(f)
    local u, c = f.unit, f.conf
    local col = Style.unit
    local state = unitState(u)
    if state == "offline" then return col.offline end
    if state then return col.dead end
    if c.classColor and Safe(UnitIsPlayer(u), false) then
        local _, class = UnitClass(u)
        class = Safe(class, nil)
        local cc = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
        if cc then return { cc.r, cc.g, cc.b } end
    end
    if c.reactionColor and not Safe(UnitIsPlayer(u), true) then
        if Safe(UnitIsTapDenied(u), false) then return col.tapped end
        local reaction = Safe(UnitReaction(u, "player"), nil)
        if reaction then
            if reaction >= 5 then return col.friendly end
            if reaction == 4 then return col.neutral end
            return col.hostile
        end
    end
    return col.health
end

local function healthText(f, cur, max)
    local u, c = f.unit, f.conf
    local state = unitState(u)
    if state then return STATE_TEXT[state] end
    local value, pct
    if c.showHealthValue then value = abbreviate(cur) end
    if c.showHealthPercent then
        if not IsSecret(cur) and not IsSecret(max) then
            pct = string.format("%d%%", max > 0 and math.floor(cur / max * 100 + 0.5) or 0)
        elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            local p = try(UnitHealthPercent, u, true, CurveConstants.ScaleTo100)
            if p ~= nil then pct = try(string.format, "%.0f%%", p) end
        end
    end
    if value and pct then return try(string.format, "%s  |cffb4bdcf%s|r", value, pct) or pct end
    return value or pct or ""
end

function E.UpdateHealth(f)
    local u, h = f.unit, f.Health
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    try(h.SetMinMaxValues, h, 0, max)
    try(h.SetValue, h, cur)
    local col = healthColor(f)
    h:SetStatusBarColor(col[1], col[2], col[3])
    if f.HealthText:IsShown() then try(f.HealthText.SetText, f.HealthText, healthText(f, cur, max)) end
end

---------------------------------------------------------------------------
-- Risorsa (mana, ira, energia...)
---------------------------------------------------------------------------
function E.UpdatePower(f)
    if not f.Power:IsShown() then return end
    local u, p = f.unit, f.Power
    local cur, max = UnitPower(u), UnitPowerMax(u)
    try(p.SetMinMaxValues, p, 0, max)
    try(p.SetValue, p, cur)
    local _, token = UnitPowerType(u)
    token = Safe(token, nil)
    local pc = token and PowerBarColor and PowerBarColor[token]
    if pc then p:SetStatusBarColor(pc.r, pc.g, pc.b) else p:SetStatusBarColor(Style.Color("accent")) end
    if f.PowerText:IsShown() then try(f.PowerText.SetText, f.PowerText, abbreviate(cur) or "") end
end

---------------------------------------------------------------------------
-- Nome e livello
---------------------------------------------------------------------------
function E.UpdateName(f)
    local u = f.unit
    if f.Name:IsShown() then try(f.Name.SetText, f.Name, UnitName(u) or "") end
    if f.Level:IsShown() then
        local lvl = UnitLevel(u)
        if IsSecret(lvl) then
            try(f.Level.SetText, f.Level, lvl)
        elseif lvl and lvl > 0 then
            f.Level:SetText(lvl)
            local dc = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl)
            if dc then f.Level:SetTextColor(dc.r, dc.g, dc.b) end
        else
            f.Level:SetText("??")
            f.Level:SetTextColor(Style.Color("danger"))
        end
    end
end

---------------------------------------------------------------------------
-- Indicatori
---------------------------------------------------------------------------
function E.UpdateIndicators(f)
    local u = f.unit
    local idx = GetRaidTargetIndex(u)
    if idx ~= nil and (IsSecret(idx) or idx > 0) and SetRaidTargetIconTexture then
        try(SetRaidTargetIconTexture, f.RaidIcon, idx)
        f.RaidIcon:Show()
    else
        f.RaidIcon:Hide()
    end
    f.Leader:SetShown(f.conf.showLeader and Safe(UnitIsGroupLeader(u), false) or false)

    -- In combattimento? Utile su bersaglio/focus (si puo' Sap-pare? il healer puo' bere?).
    -- Il valore puo' essere secret: lo si delega al client con SetAlphaFromBoolean se c'e'.
    if not f.conf.showCombat then
        f.Combat:Hide()
    elseif u ~= "player" then
        local inCombat = UnitAffectingCombat(u)
        if IsSecret(inCombat) then
            if f.Combat.SetAlphaFromBoolean then
                f.Combat:Show()
                f.Combat:SetAlphaFromBoolean(inCombat, 1, 0)
            else
                f.Combat:Hide()
            end
        else
            f.Combat:SetAlpha(1)
            f.Combat:SetShown(inCombat and true or false)
        end
    else
        f.Combat:SetShown(UnitAffectingCombat("player") and true or false)
    end

    -- Icona di classe solo per i giocatori, con classe leggibile.
    local icon = f.ClassIcon
    local class = f.conf.showClassIcon and Safe(UnitIsPlayer(u), false) and Safe(select(2, UnitClass(u)), nil)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        icon:Show()
    else
        icon:Hide()
    end
end

---------------------------------------------------------------------------
-- Castbar
---------------------------------------------------------------------------
local function castOnUpdate(cast, elapsed)
    local now = GetTime()
    if now >= cast.endTime then
        cast:SetScript("OnUpdate", nil)
        cast:Hide()
        return
    end
    local progress = cast.channel and (cast.endTime - now) or (now - cast.startTime)
    cast:SetValue(progress)
    cast.Time:SetFormattedText("%.1f", cast.endTime - now)
end

local function castColor(cast, locked)
    if locked then
        local l = Style.unit.castLocked
        cast:SetStatusBarColor(l[1], l[2], l[3])
    else
        cast:SetStatusBarColor(Style.Color("accent"))
    end
end

function E.StartCast(f, channel)
    local cast = f.Castbar
    if not cast.enabled then return end
    local u = f.unit
    local name, text, texture, startMS, endMS, _, _, notInterruptible
    if channel then
        name, text, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(u)
    else
        name, text, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(u)
    end
    if name == nil then cast:Hide(); return end

    try(cast.Text.SetText, cast.Text, text or name)
    try(cast.Icon.SetTexture, cast.Icon, texture)
    castColor(cast, Safe(notInterruptible, false))
    cast.channel = channel

    if not IsSecret(startMS) and not IsSecret(endMS) and startMS and endMS then
        cast.startTime, cast.endTime = startMS / 1000, endMS / 1000
        cast:SetMinMaxValues(0, cast.endTime - cast.startTime)
        cast:SetScript("OnUpdate", castOnUpdate)
        castOnUpdate(cast, 0)
    else
        -- Tempi opachi: si delega l'animazione al client se offre l'API a durata.
        cast:SetScript("OnUpdate", nil)
        cast.Time:SetText("")
        local getDur = channel and UnitChannelDuration or UnitCastingDuration
        local dur = getDur and try(getDur, u)
        if not (dur and cast.SetTimerDuration and try(cast.SetTimerDuration, cast, dur) ~= false) then
            cast:SetMinMaxValues(0, 1); cast:SetValue(1)
        end
    end
    cast:Show()
end

function E.StopCast(f)
    local cast = f.Castbar
    cast:SetScript("OnUpdate", nil)
    cast:Hide()
end

function E.SetCastInterruptible(f, interruptible)
    if f.Castbar:IsShown() then castColor(f.Castbar, not interruptible) end
end

function E.UpdateCast(f)
    if not f.Castbar.enabled then return f.Castbar:Hide() end
    if UnitChannelInfo(f.unit) ~= nil then return E.StartCast(f, true) end
    if UnitCastingInfo(f.unit) ~= nil then return E.StartCast(f, false) end
    E.StopCast(f)
end

---------------------------------------------------------------------------
-- Aure (bersaglio / focus): debuff prima, poi buff
---------------------------------------------------------------------------
local function auraButton(f, i)
    local a = f.Auras
    local b = a.buttons[i]
    if b then return b end
    b = CreateFrame("Frame", nil, f)
    Style.Skin(b)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("TOPLEFT", 1, -1); b.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.Cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.Cooldown:SetAllPoints(b.Icon)
    b.Cooldown:SetDrawEdge(false)
    b.Cooldown:SetReverse(true)
    b.Count = Style.Text(b, 10, "RIGHT", "text")
    b.Count:SetPoint("BOTTOMRIGHT", -1, 1)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if self.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(f.unit, self.auraInstanceID)
        elseif self.index then
            GameTooltip:SetUnitAura(f.unit, self.index, self.filter)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    a.buttons[i] = b
    return b
end

local function setAura(f, b, data, index, filter, isDebuff)
    b.index, b.filter, b.auraInstanceID = index, filter, data.auraInstanceID
    try(b.Icon.SetTexture, b.Icon, data.icon)
    local n = data.applications
    if IsSecret(n) then try(b.Count.SetText, b.Count, n)
    else b.Count:SetText(n and n > 1 and n or "") end

    local exp, dur = data.expirationTime, data.duration
    if not IsSecret(exp) and not IsSecret(dur) and dur and dur > 0 then
        b.Cooldown:SetCooldown(exp - dur, dur)
        b.Cooldown:Show()
    elseif C_UnitAuras.GetAuraDuration and b.Cooldown.SetCooldownFromDurationObject then
        local d = try(C_UnitAuras.GetAuraDuration, f.unit, data.auraInstanceID)
        if d then try(b.Cooldown.SetCooldownFromDurationObject, b.Cooldown, d) else b.Cooldown:Hide() end
    else
        b.Cooldown:Hide()
    end

    -- Bordo colorato per i debuff in base al tipo di dispel (se leggibile).
    if isDebuff then
        local kind = Safe(data.dispelName, nil)
        local dc = kind and DebuffTypeColor and DebuffTypeColor[kind]
        if dc then
            for _, t in ipairs(b.badbBorder) do t:SetVertexColor(dc.r, dc.g, dc.b, 1) end
        else
            Style.SetHighlight(b, "danger")
        end
    else
        Style.SetHighlight(b)
    end
    b:Show()
end

function E.UpdateAuras(f)
    local a = f.Auras
    if not a.enabled then return end
    local u, shown = f.unit, 0
    local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if getAura then
        local passes = {
            { filter = a.onlyMine and "HARMFUL|PLAYER" or "HARMFUL", debuff = true },
            { filter = "HELPFUL", debuff = false },
        }
        for _, pass in ipairs(passes) do
            for i = 1, 40 do
                if shown >= a.max then break end
                local data = getAura(u, i, pass.filter)
                if not data then break end
                shown = shown + 1
                setAura(f, auraButton(f, shown), data, i, pass.filter, pass.debuff)
            end
        end
    end
    local size, gap = a.size, 3
    local perRow = math.max(1, math.floor((f:GetWidth() + gap) / (size + gap)))
    for i = 1, #a.buttons do
        local b = a.buttons[i]
        if i <= shown then
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", col * (size + gap), 4 + row * (size + gap))
        else
            b:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Aura grande: la piu' importante tra immunita' > CC > silence > difensivi > offensivi
-- (priorita' e categorie da Badb.Auras, la stessa lista delle nameplate e degli avvisi).
---------------------------------------------------------------------------
local BIG_AURA_CATEGORIES = { "immunity", "cc", "silence", "defensive", "offensive" }

function E.UpdateBigAura(f)
    local A = Badb.Auras
    if not A then return end
    local entry = f.bigAuraEnabled and A.enabled and A:GetHighest(f.unit, BIG_AURA_CATEGORIES) or nil
    if not entry then
        if f.BigAura then A:ClearIcon(f.BigAura) end
        return
    end
    if not f.BigAura then
        f.BigAura = A:CreateIcon(f, f.bigAuraSize)
        if f.BigAura.SetFrameLevel and f.Health and f.Health.GetFrameLevel then
            f.BigAura:SetFrameLevel((f.Health:GetFrameLevel() or 1) + 6)
        end
    end
    f.BigAura:ClearAllPoints()
    f.BigAura:SetPoint("CENTER", f, "CENTER", 0, 0)
    A:SetIcon(f.BigAura, entry, f.unit, { size = f.bigAuraSize })
end

function E.UpdateAllAuras(f)
    E.UpdateAuras(f)
    E.UpdateBigAura(f)
end

---------------------------------------------------------------------------
-- Aggiornamento completo
---------------------------------------------------------------------------
function E.UpdateAll(f)
    if f.preview then return E.Preview(f) end
    if not UnitExists(f.unit) then return end
    E.UpdateHealth(f)
    E.UpdatePower(f)
    E.UpdateName(f)
    E.UpdateIndicators(f)
    E.UpdateCast(f)
    E.UpdateAuras(f)
    E.UpdateBigAura(f)
end

-- Dati finti per configurare i frame senza gruppo/bersaglio.
local PREVIEW_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "PALADIN", "SHAMAN", "WARLOCK" }
function E.Preview(f)
    local seed = f.previewSeed or 1
    local class = PREVIEW_CLASSES[(seed - 1) % #PREVIEW_CLASSES + 1]
    local cc = RAID_CLASS_COLORS[class]
    local pct = 35 + (seed * 17) % 60
    f.Health:SetMinMaxValues(0, 100); f.Health:SetValue(pct)
    if f.conf.classColor and cc then f.Health:SetStatusBarColor(cc.r, cc.g, cc.b)
    else local h = Style.unit.health; f.Health:SetStatusBarColor(h[1], h[2], h[3]) end
    f.Power:SetMinMaxValues(0, 100); f.Power:SetValue(100 - pct / 2)
    local pc = PowerBarColor and PowerBarColor.MANA
    if pc then f.Power:SetStatusBarColor(pc.r, pc.g, pc.b) end
    f.Name:SetText(f.previewName or f.unit)
    f.Level:SetText("60"); f.Level:SetTextColor(Style.Color("textDim"))
    local parts = {}
    if f.conf.showHealthValue then parts[#parts + 1] = short(pct * 52) end
    if f.conf.showHealthPercent then parts[#parts + 1] = "|cffb4bdcf" .. pct .. "%|r" end
    f.HealthText:SetText(table.concat(parts, "  "))
    f.PowerText:SetText(short(4200))
    if f.Castbar.enabled then
        local cast = f.Castbar
        cast:SetScript("OnUpdate", nil)
        cast:SetMinMaxValues(0, 1); cast:SetValue(0.6)
        castColor(cast, false)
        cast.Text:SetText(L["Incantesimo di prova"]); cast.Time:SetText("1.2")
        cast.Icon:SetTexture(136243)
        cast:Show()
    end
    if f.Auras.enabled then
        local a = f.Auras
        for i = 1, math.min(a.max, 4) do
            local b = auraButton(f, i)
            b.index, b.auraInstanceID = nil, nil
            b.Icon:SetTexture(i % 2 == 0 and 136085 or 135940)
            b.Count:SetText(i == 1 and 3 or "")
            b.Cooldown:Hide()
            b:SetSize(a.size, a.size)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (a.size + 3), 4)
            if i <= 2 then Style.SetHighlight(b, "danger") else Style.SetHighlight(b) end
            b:Show()
        end
    end
end
