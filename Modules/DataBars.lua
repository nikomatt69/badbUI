-- BadbUI - DataBars: barre esperienza e reputazione in stile ElvUI (barra piatta con bordo nero e testo).
-- Colori di ElvUI (Defaults/Profile.lua): esperienza (0, 0.4, 1), riposo viola trasparente; reputazione dai colori fazione.
-- Solo API non protette e non secret (UnitXP, reputazione): nessun taint, funziona in combattimento.
-- Nasconde la barra Blizzard (StatusTrackingBarManager) con alpha, e ripristina il valore originale al disable.
local _, ns = ...
local Badb = ns.Badb
local Events, Logger, FM, Modules = Badb.Events, Badb.Logger, Badb.FrameManager, Badb.Modules

local floor, max, min = math.floor, math.max, math.min
local FONT = "Fonts\\ARIALN.TTF"

local XP_COLOR = { 0, 0.4, 1 }
local RESTED_COLOR = { 1, 0, 1, 0.35 }
local REACTION = { -- se FACTION_BAR_COLORS manca: odiato ... esaltato
    [1] = { 0.8, 0.13, 0.13 }, [2] = { 0.8, 0.13, 0.13 }, [3] = { 0.75, 0.27, 0 }, [4] = { 0.9, 0.7, 0 },
    [5] = { 0, 0.6, 0.1 }, [6] = { 0, 0.6, 0.1 }, [7] = { 0, 0.6, 0.1 }, [8] = { 0, 0.6, 0.1 },
}

local function theme() return Badb.Theme end

local function skin(frame, opts)
    local T = theme()
    if T and T.Skin then T:Skin(frame, opts) end
end

local function grouped(n)
    local s, k = tostring(floor(n or 0)), nil
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local M = Modules:New("DataBars", {
    title = "Barre esperienza e reputazione",
    category = "Interfaccia",
    description = "Barre piatte sotto le barre azioni, come in ElvUI: esperienza (con riposo) e reputazione seguita.",
    defaults = { enabled = true, xp = true, rep = true, width = 360, height = 14, textMode = "both",
                 fontSize = 11, hideBlizzard = true },
    options = {
        { type = "toggle", path = "xp", label = "Barra esperienza (nascosta al livello massimo)" },
        { type = "toggle", path = "rep", label = "Barra reputazione (fazione seguita)" },
        { type = "range", path = "width", label = "Larghezza", min = 150, max = 800, step = 2 },
        { type = "range", path = "height", label = "Altezza", min = 6, max = 30, step = 1 },
        { type = "range", path = "fontSize", label = "Dimensione testo", min = 8, max = 16, step = 1 },
        { type = "select", path = "textMode", label = "Testo", values = {
            { value = "both", label = "Valore e percentuale" }, { value = "value", label = "Solo valore" },
            { value = "percent", label = "Solo percentuale" }, { value = "none", label = "Nessuno" } } },
        { type = "toggle", path = "hideBlizzard", label = "Nascondi la barra Blizzard" },
    },
    page = { title = "Barre XP e reputazione", order = 6, category = "Interfaccia",
             keywords = { "esperienza", "xp", "reputazione", "fazione", "barra", "databar" } },
})
Badb.DataBars = M

local function num(path, def, lo, hi)
    local v = M:Get(path)
    if type(v) ~= "number" or v ~= v then v = def end
    return max(lo, min(hi, v))
end

---------------------------------------------------------------------------
-- Dati
---------------------------------------------------------------------------

function M.XPInfo()
    if not UnitXP then return nil end
    local level = UnitLevel and UnitLevel("player") or 1
    local cap = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if type(level) ~= "number" or type(cap) ~= "number" or level >= cap then return nil end
    local cur, mx = UnitXP("player"), UnitXPMax and UnitXPMax("player")
    if type(cur) ~= "number" or type(mx) ~= "number" or mx <= 0 then return nil end
    local rested = GetXPExhaustion and GetXPExhaustion()
    if type(rested) ~= "number" or rested < 0 then rested = 0 end
    return { cur = cur, max = mx, rested = rested, level = level }
end

-- Supporta la API moderna (tabella) e quella classica (valori multipli).
function M.RepInfo()
    local name, reaction, lo, hi, value
    local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if type(data) == "table" then
        name, reaction = data.name, data.reaction
        lo, hi, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    elseif GetWatchedFactionInfo then
        name, reaction, lo, hi, value = GetWatchedFactionInfo()
    end
    if type(name) ~= "string" or name == "" then return nil end
    if type(lo) ~= "number" or type(hi) ~= "number" or type(value) ~= "number" then return nil end
    local span = hi - lo
    if span <= 0 then return { name = name, reaction = reaction or 4, cur = 1, max = 1 } end -- esaltato
    return { name = name, reaction = reaction or 4, cur = max(0, value - lo), max = span }
end

local function reactionColor(r)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[r]
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    c = REACTION[r] or REACTION[4]
    return c[1], c[2], c[3]
end

local function formatText(mode, cur, mx, extra)
    if mode == "none" then return "" end
    local pct = mx > 0 and floor(cur / mx * 100 + 0.5) or 0
    local value = grouped(cur) .. " / " .. grouped(mx)
    local t = mode == "value" and value or (mode == "percent" and (pct .. "%") or (value .. "  (" .. pct .. "%)"))
    return extra and extra ~= "" and (t .. "  " .. extra) or t
end
M.FormatText = formatText

---------------------------------------------------------------------------
-- Barre
---------------------------------------------------------------------------

local faded = setmetatable({}, { __mode = "k" })

local function build(key, name, point)
    local bar = CreateFrame("StatusBar", name, UIParent)
    bar:SetFrameStrata("BACKGROUND")
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    bar:SetSize(360, 14)
    bar:SetPoint(point[1], UIParent, point[1], point[2], point[3])
    skin(bar, { bg = "panel", border = "border" })
    bar.rested = CreateFrame("StatusBar", nil, bar)
    bar.rested:SetAllPoints(bar)
    bar.rested:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.rested:SetMinMaxValues(0, 1); bar.rested:SetValue(0)
    bar.rested:SetFrameLevel(bar:GetFrameLevel())
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetFont(FONT, 11, "")
    bar.text:SetShadowOffset(1, -1); bar.text:SetShadowColor(0, 0, 0, 1)
    bar.text:SetPoint("CENTER")
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if self.tip and GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip[1])
            for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1) end
            GameTooltip:Show()
        end
    end)
    bar:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    FM:Register(key, { frame = bar, title = name == "BadbElvXPBar" and "Barra esperienza" or "Barra reputazione",
                       category = "Interfaccia", hideable = false })
    return bar
end

function M:Bars()
    if not self.bars then
        self.bars = {
            xp = build("ElvXPBar", "BadbElvXPBar", { "BOTTOM", 0, 6 }),
            rep = build("ElvRepBar", "BadbElvRepBar", { "BOTTOM", 0, 22 }),
        }
    end
    return self.bars
end

local function setup(bar, w, h, size)
    bar:SetSize(w, h)
    bar.text:SetFont(FONT, size, "")
end

function M:Update()
    if not self.active then return end
    local bars = self:Bars()
    local w, h, size = num("width", 360, 150, 800), num("height", 14, 6, 30), num("fontSize", 11, 8, 16)
    local mode = self:Get("textMode")
    local xpBar, repBar = bars.xp, bars.rep
    setup(xpBar, w, h, size); setup(repBar, w, h, size)

    local xp = self:Get("xp") and M.XPInfo()
    if xp then
        xpBar:SetMinMaxValues(0, xp.max); xpBar:SetValue(xp.cur)
        xpBar:SetStatusBarColor(XP_COLOR[1], XP_COLOR[2], XP_COLOR[3], 1)
        xpBar.rested:SetMinMaxValues(0, xp.max); xpBar.rested:SetValue(min(xp.max, xp.cur + xp.rested))
        xpBar.rested:SetStatusBarColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], RESTED_COLOR[4])
        xpBar.rested:SetShown(xp.rested > 0)
        xpBar.text:SetText(formatText(mode, xp.cur, xp.max, xp.rested > 0 and ("riposo " .. grouped(xp.rested)) or nil))
        xpBar.tip = { "Esperienza", string.format("Livello %d", xp.level), string.format("Mancano %s XP", grouped(xp.max - xp.cur)),
                      xp.rested > 0 and string.format("Riposo: %s", grouped(xp.rested)) or "Nessun riposo" }
        xpBar:Show()
    else
        xpBar:Hide()
    end

    local rep = self:Get("rep") and M.RepInfo()
    if rep then
        repBar:SetMinMaxValues(0, rep.max); repBar:SetValue(rep.cur)
        repBar:SetStatusBarColor(reactionColor(rep.reaction))
        repBar.rested:Hide()
        repBar.text:SetText(rep.name .. (mode == "none" and "" or ("  " .. formatText(mode, rep.cur, rep.max))))
        repBar.tip = { rep.name, string.format("%s / %s", grouped(rep.cur), grouped(rep.max)) }
        repBar:Show()
    else
        repBar:Hide()
    end
    self:PlaceRep()
end

-- Se l'esperienza e' nascosta (livello massimo) la reputazione scende in basso.
function M:PlaceRep()
    local bars = self.bars
    if not bars then return end
    local y = bars.xp:IsShown() and (6 + num("height", 14, 6, 30) + 2) or 6
    local conf = Badb.DB.profile.frames.ElvRepBar
    if conf and conf.point then return end -- posizione scelta dall'utente: non toccarla
    bars.rep:ClearAllPoints()
    bars.rep:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, y)
end

function M:HideBlizzard(on)
    local mgr = _G.StatusTrackingBarManager
    if not mgr or not mgr.SetAlpha then return end
    if on then
        if faded[mgr] == nil then faded[mgr] = mgr:GetAlpha() end
        mgr:SetAlpha(0)
    elseif faded[mgr] ~= nil then
        mgr:SetAlpha(faded[mgr]); faded[mgr] = nil
    end
end

local EVENTS = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }

function M:OnEnable()
    self.active = true
    self:Update()
    self:HideBlizzard(self:Get("hideBlizzard"))
    for _, ev in ipairs(EVENTS) do self:On(ev, function() M:Update() end) end
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == "DataBars" then M:Update(); M:HideBlizzard(M:Get("hideBlizzard")) end
    end)
end

function M:OnProfileChanged() self:Update(); self:HideBlizzard(self:Get("hideBlizzard")) end

function M:OnDisable()
    self.active = false
    for _, bar in pairs(self.bars or {}) do bar:Hide() end
    self:HideBlizzard(false)
end
