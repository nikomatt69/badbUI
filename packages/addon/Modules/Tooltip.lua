-- BadbUI - Tooltip: aspetto piatto in stile ElvUI.
--   * sfondo scuro (backdropfadecolor di ElvUI: 0.06 con alpha 0.8) e bordo nero da 1 px, senza la cornice Blizzard
--   * bordo colorato per classe sui giocatori e per qualita' sugli oggetti
--   * barra della vita sottile e piatta
-- Solo frame nostri ancorati al tooltip e hook non protetti: nessun taint. I dati dell'unita' possono essere
-- secret in combattimento: in quel caso il bordo resta quello predefinito (mai confronti su valori opachi).
-- Al disable si ripristina l'alpha originale della cornice Blizzard.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Modules, Compat = Badb.Modules, Badb.Compat

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }
local QUALITY_MIN = 2 -- bordo colorato da "non comune" in su (grigio e bianco restano neri)

local function theme() return Badb.Theme end

local M = Modules:New("Tooltip", {
    title = "Tooltip",
    category = L["Interfaccia"],
    description = L["Tooltip piatti in stile ElvUI: sfondo scuro, bordo per classe o qualita', barra vita sottile."],
    defaults = { enabled = true, classBorder = true, qualityBorder = true, bgAlpha = 0.8, flatHealthBar = true },
    options = {
        { type = "toggle", path = "classBorder", label = L["Bordo del colore della classe sui giocatori"] },
        { type = "toggle", path = "qualityBorder", label = L["Bordo del colore della qualita' sugli oggetti"] },
        { type = "range", path = "bgAlpha", label = L["Opacita' dello sfondo"], min = 0.3, max = 1, step = 0.05 },
        { type = "toggle", path = "flatHealthBar", label = L["Barra della vita piatta"] },
    },
    page = { title = "Tooltip", order = 7, category = L["Interfaccia"], keywords = { "tooltip", L["suggerimento"], L["bordo"], L["classe"], L["qualita"] } },
})
Badb.Tooltip = M
M.skinned = {}

local faded = setmetatable({}, { __mode = "k" })

local function secret(v) return Compat and Compat.IsSecret and Compat.IsSecret(v) end

local function bgAlpha()
    local v = M:Get("bgAlpha")
    if type(v) ~= "number" or v ~= v then v = 0.8 end
    return math.max(0.3, math.min(1, v))
end

local function setBorder(rec, r, g, b)
    local T = theme()
    if not (T and T.SetBorder and rec and rec.bd) then return end
    T:SetBorder(rec.bd, r and { r, g, b, 1 } or "border")
end

-- Crea (una volta) e aggiorna lo sfondo del tooltip.
function M:Skin(tt)
    if type(tt) ~= "table" or not tt.CreateTexture then return end
    local rec = self.skinned[tt]
    if not rec then
        local bd = CreateFrame("Frame", nil, tt)
        bd:SetFrameLevel(math.max(0, tt:GetFrameLevel() - 1))
        bd:SetPoint("TOPLEFT", tt, "TOPLEFT", 0, 0)
        bd:SetPoint("BOTTOMRIGHT", tt, "BOTTOMRIGHT", 0, 0)
        rec = { bd = bd }
        self.skinned[tt] = rec
        if tt.HookScript then
            tt:HookScript("OnShow", function() if M.active then M:Style(tt) end end)
            tt:HookScript("OnTooltipCleared", function() if M.active then setBorder(rec) end end)
        end
    end
    local nine = tt.NineSlice
    if nine and nine.SetAlpha then
        if faded[nine] == nil then faded[nine] = nine:GetAlpha() end
        nine:SetAlpha(0)
    end
    local T = theme()
    if T and T.Skin then T:Skin(rec.bd, { bg = "bg", border = "border", alpha = bgAlpha() }) end
    rec.bd:Show()
    return rec
end

function M:UnitColor(tt)
    if not self:Get("classBorder") or not tt.GetUnit then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    if not ok or type(unit) ~= "string" or secret(unit) then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or secret(isPlayer) or not isPlayer then return end
    local okC, _, class = pcall(UnitClass, unit)
    if not okC or type(class) ~= "string" or secret(class) then return end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

function M:ItemColor(tt)
    if not self:Get("qualityBorder") or not tt.GetItem then return end
    local ok, _, link = pcall(tt.GetItem, tt)
    if not ok or type(link) ~= "string" then return end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return end
    local okI, _, _, quality = pcall(getInfo, link)
    if not okI or type(quality) ~= "number" or quality < QUALITY_MIN then return end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
end

-- Dopo che il contenuto e' impostato: colore del bordo e barra vita.
function M:Style(tt)
    local rec = self:Skin(tt)
    if not rec then return end
    local r, g, b = self:UnitColor(tt)
    if not r then r, g, b = self:ItemColor(tt) end
    setBorder(rec, r, g, b)
    if tt == _G.GameTooltip and self:Get("flatHealthBar") then
        local sb = _G.GameTooltipStatusBar
        if sb and sb.SetStatusBarTexture and not sb.badbFlat then
            sb:SetStatusBarTexture(WHITE); sb.badbFlat = true
        end
    end
end

function M:StyleAll()
    for _, name in ipairs(TOOLTIPS) do
        local tt = _G[name]
        if tt then self:Skin(tt) end
    end
end

function M:OnEnable()
    self.active = true
    self:StyleAll()
    -- Contenuto impostato dopo OnShow: la API moderna ha i post-call, altrimenti basta OnShow.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and not self.postCalls then
        self.postCalls = true
        local function post(tt) if M.active and M.skinned[tt] then M:Style(tt) end end
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, post)
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, post)
    end
    self:On("BADB_OPTION_CHANGED", function(_, module) if module == "Tooltip" then M:StyleAll() end end)
end

function M:OnProfileChanged() self:StyleAll() end

function M:OnDisable()
    self.active = false
    for _, rec in pairs(self.skinned) do rec.bd:Hide() end
    for nine, alpha in pairs(faded) do pcall(nine.SetAlpha, nine, alpha); faded[nine] = nil end
end
