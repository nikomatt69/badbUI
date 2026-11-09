-- BadbUI - ElvLook: il "vestito" visibile in stile ElvUI.
-- Valori e disposizione ricavati dai default di ElvUI (tukui-org/ElvUI, Defaults/Profile.lua e Layout.lua).
-- Aggiunge cio' che si vede a colpo d'occhio, senza spostare ne' sostituire frame Blizzard protetti:
--   * due pannelli datatext 412x22 agli angoli in basso (zona, durabilita', borse / fps+ms, ora, oro), spostabili con /badb unlock;
--   * minimappa quadrata con cornice piatta;
--   * sfondo scuro dietro la chat e la casella di testo, senza i pulsanti Blizzard;
--   * fondo piatto dietro ogni barra azioni, senza le decorazioni Blizzard.
-- Tutto e' fatto con frame nostri ancorati a quelli Blizzard e con alpha: nessun SetPoint/SetSize
-- sui frame Edit Mode, quindi nessun taint e tutto funziona anche in combattimento.
-- Disattivando il modulo ogni alpha viene riportato al valore originale.
local _, ns = ...
local Badb = ns.Badb
local Events, Logger, FM, Modules = Badb.Events, Badb.Logger, Badb.FrameManager, Badb.Modules

local floor, max, min = math.floor, math.max, math.min
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Maschere della minimappa (da ElvUI, Maps/Minimap.lua SetMinimapMask): client moderno usa fileID, classico percorsi.
local MASK_SQUARE_MODERN, MASK_ROUND_MODERN = 130937, 186178
local MASK_ROUND_CLASSIC = "Textures\\MinimapMask"

---------------------------------------------------------------------------
-- Utilita'
---------------------------------------------------------------------------

local function theme() return Badb.Theme end

local function skin(frame, opts)
    local T = theme()
    if T and T.Skin then T:Skin(frame, opts) end
end

local function wrap(text, key)
    local T = theme()
    if T and T.Wrap then return T:Wrap(text, key) end
    return tostring(text)
end

local function groupDigits(n)
    local s, k = tostring(floor(n or 0)), nil
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

-- Alpha originali dei pezzi Blizzard nascosti (oggetto -> alpha), per il ripristino.
local faded = setmetatable({}, { __mode = "k" })

local function fade(obj)
    if type(obj) ~= "table" or not obj.SetAlpha or not obj.GetAlpha then return end
    if faded[obj] == nil then faded[obj] = obj:GetAlpha() end
    obj:SetAlpha(0)
end

local function restoreFaded()
    for obj, alpha in pairs(faded) do
        pcall(obj.SetAlpha, obj, alpha)
        faded[obj] = nil
    end
end

local function field(obj, name) return type(obj) == "table" and obj[name] or nil end

---------------------------------------------------------------------------
-- Datatext: ognuno restituisce il testo gia' colorato. Mai valori secret: solo API di sistema.
---------------------------------------------------------------------------

local function latencyKey(ms)
    if ms < 100 then return "success" elseif ms < 250 then return "warning" end
    return "danger"
end

local DATATEXTS = {
    fpsms = { label = "FPS e latenza", text = function()
        local fps = GetFramerate and GetFramerate() or 0
        local _, _, home, world = GetNetStats()
        local ms = world or home or 0
        return wrap(floor(fps + 0.5), "accent") .. wrap(" fps  ", "textDim")
            .. wrap(floor(ms), latencyKey(ms)) .. wrap(" ms", "textDim")
    end },
    fps = { label = "FPS", text = function()
        return wrap(floor((GetFramerate and GetFramerate() or 0) + 0.5), "accent") .. wrap(" fps", "textDim")
    end },
    latency = { label = "Latenza", text = function()
        local _, _, home, world = GetNetStats()
        local ms = world or home or 0
        return wrap(floor(ms), latencyKey(ms)) .. wrap(" ms", "textDim")
    end },
    gold = { label = "Oro", text = function()
        local c = GetMoney and GetMoney() or 0
        local g, s, cu = floor(c / 10000), floor(c / 100) % 100, c % 100
        return groupDigits(g) .. "|cffffd700g|r " .. s .. "|cffc0c0c0s|r " .. cu .. "|cffb87333c|r"
    end },
    durability = { label = "Durabilita'", text = function()
        local lowest, any = 100, false
        if GetInventoryItemDurability then
            for slot = 1, 19 do
                local cur, mx = GetInventoryItemDurability(slot)
                if type(cur) == "number" and type(mx) == "number" and mx > 0 then
                    any = true
                    lowest = min(lowest, cur / mx * 100)
                end
            end
        end
        if not any then return wrap("Durabilita' -", "textDim") end
        local key = lowest < 25 and "danger" or (lowest < 50 and "warning" or "success")
        return wrap("Durabilita' ", "textDim") .. wrap(floor(lowest + 0.5) .. "%", key)
    end },
    bags = { label = "Borse", text = function()
        local C = C_Container
        local getSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
        local getFree = (C and C.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
        if not (getSlots and getFree) then return wrap("Borse -", "textDim") end
        local free, total = 0, 0
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local n = getSlots(bag) or 0
            if n > 0 then
                total = total + n
                free = free + (getFree(bag) or 0)
            end
        end
        local ratio = total > 0 and free / total or 1
        local key = ratio < 0.1 and "danger" or (ratio < 0.25 and "warning" or "accent")
        return wrap("Borse ", "textDim") .. wrap((total - free) .. "/" .. total, key)
    end },
    time = { label = "Orologio", text = function()
        return wrap(date("%H:%M"), "accent")
    end },
    zone = { label = "Zona", text = function()
        local z = GetMinimapZoneText and GetMinimapZoneText() or ""
        return wrap(z, "textDim")
    end },
    none = { label = "Vuoto", text = function() return "" end },
}
local DATATEXT_ORDER = { "fpsms", "durability", "bags", "gold", "time", "zone", "fps", "latency", "none" }
local DATATEXT_CHOICES = {}
for _, k in ipairs(DATATEXT_ORDER) do DATATEXT_CHOICES[#DATATEXT_CHOICES + 1] = { value = k, label = DATATEXTS[k].label } end

-- Come ElvUI (Defaults/Profile.lua, datatexts.panels): due pannelli da 3 caselle, 412x22, agli angoli in basso.
-- Sinistra: (versione) / Durabilita' / ...  Destra: Sistema (fps+ms) / Ora / Oro.
local SLOTS = 3
local SIDES = { "left", "right" }
local SIDE_TITLE = { left = "Pannello sinistro", right = "Pannello destro" }
local SIDE_POINT = { left = { "BOTTOMLEFT", 4, 4 }, right = { "BOTTOMRIGHT", -4, 4 } }
local BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
               "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar" }

---------------------------------------------------------------------------
-- Modulo
---------------------------------------------------------------------------

local function slotOpt(side, i)
    return { type = "select", path = side .. i, label = SIDE_TITLE[side] .. ": casella " .. i, values = DATATEXT_CHOICES }
end

local M = Modules:New("ElvLook", {
    title = "Stile ElvUI",
    category = "Interfaccia",
    description = "Barra datatext, minimappa quadrata, sfondi per chat e barre azioni: il look piatto e visibile di ElvUI.",
    defaults = {
        enabled = true,
        datatexts = true, panelWidth = 412, panelHeight = 22, fontSize = 12,
        left1 = "zone", left2 = "durability", left3 = "bags",
        right1 = "fpsms", right2 = "time", right3 = "gold",
        minimap = true,
        chat = true, chatAlpha = 0.8,           -- backdropfadecolor di ElvUI: 0.06 con alpha 0.8
        barBackdrops = true, barAlpha = 1, hideBarArt = true,
    },
    options = {
        { type = "execute", label = "Applica lo stile ElvUI a tutta l'interfaccia", func = function() M:ApplyElvStyle() end,
          tooltip = "Tema ElvUI, unit frame, barre azioni e cooldown. Crea prima un backup (annullabile da Backup)." },
        { type = "header", label = "Pannelli datatext (si spostano con /badb unlock)" },
        { type = "toggle", path = "datatexts", label = "Mostra i due pannelli in basso" },
        { type = "range", path = "panelWidth", label = "Larghezza di ogni pannello", min = 150, max = 800, step = 2 },
        { type = "range", path = "panelHeight", label = "Altezza", min = 16, max = 40, step = 1 },
        { type = "range", path = "fontSize", label = "Dimensione testo", min = 8, max = 18, step = 1 },
        slotOpt("left", 1), slotOpt("left", 2), slotOpt("left", 3),
        slotOpt("right", 1), slotOpt("right", 2), slotOpt("right", 3),
        { type = "header", label = "Minimappa" },
        { type = "toggle", path = "minimap", label = "Minimappa quadrata con cornice piatta",
          tooltip = "Disattivando serve /reload per riavere la forma Blizzard originale." },
        { type = "header", label = "Chat" },
        { type = "toggle", path = "chat", label = "Sfondo scuro dietro la chat" },
        { type = "range", path = "chatAlpha", label = "Opacita' sfondo", min = 0.2, max = 1, step = 0.05 },
        { type = "header", label = "Barre azioni" },
        { type = "toggle", path = "barBackdrops", label = "Fondo piatto dietro le barre" },
        { type = "range", path = "barAlpha", label = "Opacita' fondo", min = 0.2, max = 1, step = 0.05 },
        { type = "toggle", path = "hideBarArt", label = "Nascondi le decorazioni Blizzard della barra principale" },
    },
    page = { title = "Stile ElvUI", order = 5, category = "Interfaccia",
             keywords = { "elvui", "datatext", "minimappa", "chat", "pannelli", "stile", "look" } },
    commands = {
        elv = { help = "elv - applica lo stile ElvUI (tema, unit frame, barre, datatext)", fn = function() M:ApplyElvStyle() end },
    },
})
Badb.ElvLook = M
M.DATATEXTS = DATATEXTS

local function num(path, def, lo, hi)
    local v = M:Get(path)
    if type(v) ~= "number" or v ~= v then v = def end
    return max(lo, min(hi, v))
end

---------------------------------------------------------------------------
-- Pannelli datatext (sinistro e destro)
---------------------------------------------------------------------------

local DT_FONT = "Fonts\\ARIALN.TTF" -- Arial Narrow del client: il piu' vicino al PT Sans Narrow di ElvUI

function M:BuildPanel(side)
    self.panels = self.panels or {}
    if self.panels[side] then return self.panels[side] end
    local name = "BadbElvDatatext" .. (side == "left" and "Left" or "Right")
    local panel = CreateFrame("Frame", name, UIParent)
    panel:SetFrameStrata("BACKGROUND")
    panel:SetSize(412, 22)
    local pt = SIDE_POINT[side]
    panel:SetPoint(pt[1], UIParent, pt[1], pt[2], pt[3])
    skin(panel, { bg = "panel", border = "border" }) -- ElvUI: backdropcolor 0.1, bordo nero, non trasparente
    panel.slots = {}
    for i = 1, SLOTS do
        local fs = panel:CreateFontString(nil, "OVERLAY")
        fs:SetFont(DT_FONT, 12, "")
        fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) -- fontOutline 'SHADOW' in ElvUI
        fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
        panel.slots[i] = fs
    end
    local since = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 1 then since = 0; M:UpdateTexts() end
    end)
    self.panels[side] = panel
    FM:Register("ElvDatatext_" .. side, { frame = panel, title = "Datatext: " .. SIDE_TITLE[side]:lower(),
                                           category = "Interfaccia", hideable = false })
    return panel
end

function M:UpdateTexts()
    for _, side in ipairs(SIDES) do
        local panel = self.panels and self.panels[side]
        if panel and panel:IsShown() then
            for i = 1, SLOTS do
                local def = DATATEXTS[self:Get(side .. i)] or DATATEXTS.none
                local ok, text = pcall(def.text)
                panel.slots[i]:SetText(ok and text or "")
            end
        end
    end
end

function M:ApplyBar()
    if not self:Get("datatexts") then
        for _, panel in pairs(self.panels or {}) do panel:Hide() end
        return
    end
    local w, h = num("panelWidth", 412, 150, 800), num("panelHeight", 22, 16, 40)
    local size = num("fontSize", 12, 8, 18)
    for _, side in ipairs(SIDES) do
        local panel = self:BuildPanel(side)
        panel:SetSize(w, h)
        local slotW = w / SLOTS
        for i, fs in ipairs(panel.slots) do
            fs:SetFont(DT_FONT, size, "")
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", panel, "LEFT", (i - 1) * slotW, 0)
            fs:SetWidth(slotW)
            fs:SetHeight(h)
        end
        panel:Show()
    end
    self:UpdateTexts()
end

---------------------------------------------------------------------------
-- Minimappa quadrata
---------------------------------------------------------------------------

-- Nomi presenti anche nel codice di ElvUI (Minimap.lua: killFrames, ramo Forever: DielFrame e
-- MinimapCompassTextureUnderlay). Quelli assenti sul client vengono ignorati.
local MINIMAP_GLOBALS = { "MinimapBorder", "MinimapBorderTop", "MinimapBackdrop", "MiniMapWorldMapButton",
                          "MinimapZoomIn", "MinimapZoomOut", "MinimapCompassTexture", "MinimapCompassTextureUnderlay",
                          "MiniMapMailBorder", "MinimapNorthTag" }
local CLUSTER_FIELDS = { "BorderTop", "ZoomIn", "ZoomOut", "DielFrame" }

local function isModern(mm) return field(mm, "ZoomIn") ~= nil end

function M:ApplyMinimap()
    local mm = _G.Minimap
    if not (mm and mm.SetMaskTexture) then return end
    if not self:Get("minimap") then
        self:RestoreMinimap()
        return
    end
    mm:SetMaskTexture(isModern(mm) and MASK_SQUARE_MODERN or WHITE)
    if self.origShape == nil then self.origShape = _G.GetMinimapShape or false end
    _G.GetMinimapShape = function() return "SQUARE" end
    for _, name in ipairs(MINIMAP_GLOBALS) do fade(_G[name]) end
    for _, name in ipairs(CLUSTER_FIELDS) do fade(field(_G.MinimapCluster, name)) end
    for _, name in ipairs({ "ZoomIn", "ZoomOut" }) do fade(field(mm, name)) end
    if not self.mmFrame then
        local f = CreateFrame("Frame", nil, mm)
        f:SetFrameLevel(max(0, mm:GetFrameLevel() - 1))
        f:SetPoint("TOPLEFT", mm, "TOPLEFT", -2, 2)
        f:SetPoint("BOTTOMRIGHT", mm, "BOTTOMRIGHT", 2, -2)
        self.mmFrame = f
    end
    skin(self.mmFrame, { bg = "bg", border = "border" })
    self.mmFrame:Show()
    self.mmSquare = true
end

function M:RestoreMinimap()
    if self.mmFrame then self.mmFrame:Hide() end
    if not self.mmSquare then return end
    self.mmSquare = false
    local mm = _G.Minimap
    if mm and mm.SetMaskTexture then mm:SetMaskTexture(isModern(mm) and MASK_ROUND_MODERN or MASK_ROUND_CLASSIC) end
    if self.origShape ~= nil then _G.GetMinimapShape = self.origShape or nil; self.origShape = nil end
    local pieces = {}
    for _, name in ipairs(MINIMAP_GLOBALS) do pieces[#pieces + 1] = _G[name] end
    for _, name in ipairs(CLUSTER_FIELDS) do pieces[#pieces + 1] = field(_G.MinimapCluster, name) end
    for _, name in ipairs({ "ZoomIn", "ZoomOut" }) do pieces[#pieces + 1] = field(mm, name) end
    for _, o in ipairs(pieces) do
        if faded[o] ~= nil then o:SetAlpha(faded[o]); faded[o] = nil end
    end
    Logger:Info("Minimappa: /reload per ripristinare del tutto la forma Blizzard")
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

local function chatCount() return NUM_CHAT_WINDOWS or 10 end

function M:ApplyChat()
    self.chatFrames = self.chatFrames or {}
    local on = self:Get("chat")
    local alpha = num("chatAlpha", 0.75, 0.2, 1)
    for i = 1, chatCount() do
        local cf = _G["ChatFrame" .. i]
        if cf then
            local rec = self.chatFrames[i]
            if on and not rec then
                local bd = CreateFrame("Frame", nil, UIParent)
                bd:SetFrameStrata("BACKGROUND")
                local tab = _G["ChatFrame" .. i .. "Tab"]
                local top = (tab and tab:GetHeight() or 24) + 4
                bd:SetPoint("TOPLEFT", cf, "TOPLEFT", -6, top)
                bd:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 6, -8)
                rec = { bd = bd }
                self.chatFrames[i] = rec
                if cf.HookScript then
                    cf:HookScript("OnShow", function() if M.active and M:Get("chat") then bd:Show() end end)
                    cf:HookScript("OnHide", function() bd:Hide() end)
                end
                local eb = _G["ChatFrame" .. i .. "EditBox"]
                if eb then
                    local ebd = CreateFrame("Frame", nil, eb)
                    ebd:SetFrameLevel(max(0, eb:GetFrameLevel() - 1))
                    ebd:SetPoint("TOPLEFT", eb, "TOPLEFT", 2, -2)
                    ebd:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -2, 2)
                    rec.ebd = ebd
                end
            end
            if rec then
                skin(rec.bd, { bg = "bg", border = "border", alpha = alpha })
                rec.bd:SetShown(on and cf:IsShown())
                if rec.ebd then skin(rec.ebd, { bg = "bg", border = "border", alpha = 0.95 }); rec.ebd:SetShown(on) end
                if on then
                    for _, n in ipairs({ "ButtonFrame", "EditBoxLeft", "EditBoxMid", "EditBoxRight",
                                         "EditBoxFocusLeft", "EditBoxFocusMid", "EditBoxFocusRight" }) do
                        fade(_G["ChatFrame" .. i .. n])
                    end
                end
            end
        end
    end
    if on then
        fade(_G.ChatFrameMenuButton); fade(_G.ChatFrameChannelButton)
    else
        self:RestoreChat()
    end
end

function M:RestoreChat()
    for _, rec in pairs(self.chatFrames or {}) do
        rec.bd:Hide()
        if rec.ebd then rec.ebd:Hide() end
    end
    for i = 1, chatCount() do
        for _, n in ipairs({ "ButtonFrame", "EditBoxLeft", "EditBoxMid", "EditBoxRight",
                             "EditBoxFocusLeft", "EditBoxFocusMid", "EditBoxFocusRight" }) do
            local o = _G["ChatFrame" .. i .. n]
            if o and faded[o] ~= nil then o:SetAlpha(faded[o]); faded[o] = nil end
        end
    end
    for _, o in ipairs({ _G.ChatFrameMenuButton, _G.ChatFrameChannelButton }) do
        if o and faded[o] ~= nil then o:SetAlpha(faded[o]); faded[o] = nil end
    end
end

---------------------------------------------------------------------------
-- Fondo delle barre azioni
---------------------------------------------------------------------------

function M:ApplyBarBackdrops()
    self.barFrames = self.barFrames or {}
    local on = self:Get("barBackdrops")
    local alpha = num("barAlpha", 0.6, 0.2, 1)
    for _, name in ipairs(BARS) do
        local bar = _G[name]
        if bar then
            local bd = self.barFrames[name]
            if on and not bd and bar.CreateTexture then
                bd = CreateFrame("Frame", nil, bar)
                bd:SetFrameLevel(max(0, bar:GetFrameLevel() - 1))
                bd:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 3)
                bd:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 3, -3)
                self.barFrames[name] = bd
            end
            if bd then
                skin(bd, { bg = "bg", border = "border", alpha = alpha })
                bd:SetShown(on)
            end
        end
    end
    local main = _G.MainActionBar
    if main and on and self:Get("hideBarArt") then
        fade(field(main, "BorderArt"))
        local caps = field(main, "EndCaps")
        fade(field(caps, "LeftEndCap")); fade(field(caps, "RightEndCap"))
        fade(field(main, "ActionBarPageNumber"))
    elseif main then
        for _, o in ipairs({ field(main, "BorderArt"), field(field(main, "EndCaps"), "LeftEndCap"),
                             field(field(main, "EndCaps"), "RightEndCap"), field(main, "ActionBarPageNumber") }) do
            if faded[o] ~= nil then o:SetAlpha(faded[o]); faded[o] = nil end
        end
    end
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------

local function isolated(name, fn)
    local ok, err = pcall(fn)
    if not ok then Logger:Error("ElvLook:%s - %s", name, tostring(err)) end
end

function M:Apply()
    if not self.active then return end
    isolated("bar", function() M:ApplyBar() end)
    isolated("minimap", function() M:ApplyMinimap() end)
    isolated("chat", function() M:ApplyChat() end)
    -- creare frame figli di barre protette: solo fuori dal combattimento
    Events:RunOutOfCombat("elvlook:bars", function() isolated("barBackdrops", function() M:ApplyBarBackdrops() end) end)
end

function M:OnEnable()
    self.active = true -- `enabled` viene impostato dal gestore solo dopo OnEnable
    self:Apply()
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == "ElvLook" then M:Apply() end
    end)
    self:On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
        M:Apply()
        local sv = Badb.DB.sv
        if sv and sv.global and not sv.global.elvStyleApplied and (isLogin or isReload) then
            sv.global.elvStyleApplied = true
            local other = M:OtherUI()
            if other then
                -- Un'altra UI e' gia' caricata (es. Skill Capped, BetterBlizzFrames, ElvUI): non la scavalchiamo da soli.
                Logger:Info("Stile ElvUI non applicato in automatico: rilevato %s. Usa /badb elv per applicarlo.", other)
            else
                M:ApplyElvStyle(true)
            end
        end
    end)
end

function M:OnProfileChanged() self:Apply() end

function M:OnDisable()
    self.active = false
    for _, panel in pairs(self.panels or {}) do panel:Hide() end
    self:RestoreMinimap()
    self:RestoreChat()
    for _, bd in pairs(self.barFrames or {}) do bd:Hide() end
    restoreFaded()
end

---------------------------------------------------------------------------
-- Un click: tema + moduli visibili
---------------------------------------------------------------------------

-- UI di terzi che sostituiscono frame unita'/nameplate/barre: se ce n'e' una, il primo avvio non tocca nulla.
local OTHER_UIS = { "ElvUI", "SkillCapped", "BetterBlizzFrames", "BetterBlizzPlates", "ShadowedUnitFrames", "XPerl",
                   "ZPerl", "MetaPerl", "EllesmereUI", "ClassicUI_Forever", "ForeverUnitFrames" }

function M:OtherUI()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return nil end
    for _, name in ipairs(OTHER_UIS) do
        local ok, loaded = pcall(isLoaded, name)
        if ok and loaded then return name end
    end
    return nil
end

local ELV_MODULES = { "ElvLook", "DataBars", "Tooltip", "UnitFrames", "ActionBars", "Cooldowns" }

function M:ApplyElvStyle(silent)
    local Backups = Badb.Backups
    if Backups and Backups.Create then pcall(Backups.Create, Backups, "pre-elvui") end
    local T = theme()
    if T then T:SetScheme("elvui"); T:SetAccent("elvui") end
    for _, name in ipairs(ELV_MODULES) do
        if Modules.list[name] then Modules:SetEnabled(name, true) end
    end
    if not silent then Logger:Info("Stile ElvUI applicato. /badb unlock per spostare i frame, /badb elv per riapplicarlo.") end
end
