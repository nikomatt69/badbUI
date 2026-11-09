-- BadbUI - Theme: design token del design system (colori, font, texture, spaziature).
-- Stile: "notte strumentale". Fondi blu notte profondi, hairline da 1px, scala di testo
-- bianca a tre livelli, un solo accento caldo. Ispirato al look dell'addon Polestar,
-- codice e valori originali BadbUI.
--
-- Contratto pubblico (vedi docs/UI.md):
--   Theme.colors.<key> = { r, g, b, a }   aggiornata IN PLACE al cambio tema
--   Theme.fonts.<key>  = path del font
--   Theme.fontObjects.<key> = nome del FontObject globale
--   Theme.textures, Theme.spacing, Theme.sizes
--   Theme:Get(key) -> r, g, b, a      Theme:Hex(key) -> "|cffrrggbb"
--   Theme:Paint(region, key, alphaMul) Theme:OnChange(owner, fn)
--   Theme:Skin(frame, opts)            Theme:SetScheme(name)  Theme:SetAccent(r, g, b)
-- Ogni cambio di tema spara il messaggio "BADB_THEME_CHANGED" sul bus eventi.
local _, ns = ...
local Badb = ns.Badb
local Events = Badb.Events

local Theme = {}
Badb.Theme = Theme

local pairs, type, unpack, format, floor = pairs, type, unpack, string.format, math.floor

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------

-- Accento predefinito: oro caldo. Le alternative sono offerte dal selettore in config.
Theme.ACCENTS = {
    elvui  = { 0.09, 0.52, 0.82 }, -- valuecolor di ElvUI (Defaults/Profile.lua)
    gold   = { 0.93, 0.75, 0.42 },
    badb   = { 0.25, 0.65, 1.00 },
    jade   = { 0.36, 0.84, 0.62 },
    violet = { 0.68, 0.56, 1.00 },
    ember  = { 1.00, 0.52, 0.34 },
    frost  = { 0.55, 0.86, 0.96 },
}
Theme.ACCENT_ORDER = { "elvui", "gold", "badb", "jade", "violet", "ember", "frost" }

-- Colori di stato: uguali in ogni schema, cosi' "pericolo" e' sempre lo stesso rosso.
local STATUS = {
    success = { 0.40, 0.84, 0.58, 1 },
    warning = { 0.98, 0.74, 0.32, 1 },
    danger  = { 0.95, 0.43, 0.43, 1 },
    info    = { 0.56, 0.78, 1.00, 1 },
    -- segnali di gioco: controllo di folla, combattimento, allerta a centro schermo
    cc      = { 0.70, 0.52, 1.00, 1 },
    combat  = { 1.00, 0.36, 0.30, 1 },
    alert   = { 1.00, 0.82, 0.30, 1 },
}

-- Schemi: fondi + scala di testo. "ink" e' il colore di hairline e velature.
Theme.SCHEMES = {
    -- Stile ElvUI: grigio carbone piatto, bordo nero da 1px (non una velatura chiara), niente ombra morbida.
    elvui = {
        label = "ElvUI",
        flat     = true,
        bg       = { 0.060, 0.060, 0.060, 0.96 },  -- backdropfadecolor di ElvUI (0.06)
        panel    = { 0.100, 0.100, 0.100, 0.98 },  -- backdropcolor di ElvUI (0.1)
        panelAlt = { 0.135, 0.135, 0.135, 1 },
        sidebar  = { 0.072, 0.072, 0.072, 1 },
        header   = { 0.120, 0.120, 0.120, 1 },
        footer   = { 0.072, 0.072, 0.072, 1 },
        text      = { 1.00, 1.00, 1.00, 1 },
        textDim   = { 0.82, 0.82, 0.82, 1 },
        textMuted = { 0.64, 0.64, 0.64, 1 },
        ink    = { 1, 1, 1 },
        border  = { 0, 0, 0, 1 },    -- override dei velature: bordo e divisori neri pieni
        divider = { 0, 0, 0, 0.85 },
        shadow = { 0, 0, 0, 0.35 },
    },
    night = {
        label = "Notte",
        bg       = { 0.035, 0.047, 0.082, 0.96 },
        panel    = { 0.050, 0.064, 0.108, 0.98 },
        panelAlt = { 0.078, 0.096, 0.152, 1 },
        sidebar  = { 0.024, 0.032, 0.060, 1 },
        header   = { 0.070, 0.100, 0.190, 1 },
        footer   = { 0.030, 0.040, 0.072, 1 },
        text      = { 0.96, 0.97, 0.99, 1 },
        textDim   = { 0.70, 0.73, 0.81, 1 },
        textMuted = { 0.50, 0.54, 0.64, 1 },
        ink    = { 1, 1, 1 },
        shadow = { 0, 0, 0.02, 0.6 },
    },
    dusk = {
        label = "Crepuscolo",
        bg       = { 0.092, 0.112, 0.176, 0.96 },
        panel    = { 0.108, 0.130, 0.200, 0.98 },
        panelAlt = { 0.136, 0.162, 0.246, 1 },
        sidebar  = { 0.070, 0.086, 0.138, 1 },
        header   = { 0.150, 0.190, 0.320, 1 },
        footer   = { 0.078, 0.095, 0.150, 1 },
        text      = { 0.97, 0.97, 0.99, 1 },
        textDim   = { 0.77, 0.79, 0.87, 1 },
        textMuted = { 0.60, 0.63, 0.72, 1 },
        ink    = { 1, 1, 1 },
        shadow = { 0, 0, 0.02, 0.6 },
    },
    graphite = {
        label = "Grafite",
        bg       = { 0.128, 0.134, 0.144, 0.96 },
        panel    = { 0.148, 0.154, 0.164, 0.98 },
        panelAlt = { 0.180, 0.188, 0.200, 1 },
        sidebar  = { 0.100, 0.106, 0.114, 1 },
        header   = { 0.196, 0.210, 0.236, 1 },
        footer   = { 0.110, 0.116, 0.124, 1 },
        text      = { 0.97, 0.97, 0.97, 1 },
        textDim   = { 0.79, 0.80, 0.81, 1 },
        textMuted = { 0.63, 0.64, 0.66, 1 },
        ink    = { 1, 1, 1 },
        shadow = { 0, 0, 0, 0.6 },
    },
}
Theme.SCHEME_ORDER = { "elvui", "night", "dusk", "graphite" }

-- Velature di "ink" (hairline, hover, selezione) come frazioni di alpha.
local WASH = { border = 0.12, divider = 0.08, hover = 0.06, selected = 0.10, track = 0.14, control = 0.05 }

---------------------------------------------------------------------------
-- Token statici
---------------------------------------------------------------------------

local STANDARD = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local NARROW = "Fonts\\ARIALN.TTF"

Theme.fonts = {
    normal = STANDARD, body = STANDARD, bold = STANDARD,
    header = STANDARD, title = STANDARD,
    mono = NARROW, number = NARROW,
}

Theme.textures = {
    white = "Interface\\Buttons\\WHITE8X8",
    statusbar = "Interface\\Buttons\\WHITE8X8", -- piatta, coerente con lo stile
    glow = "Interface\\Buttons\\WHITE8X8",      -- usata con gradiente verticale
}

Theme.spacing = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
Theme.sizes = { row = 32, button = 26, header = 48, sidebar = 180, footer = 30, border = 1, tab = 28 }

-- Stili per elementi di gioco (non di configurazione): i moduli leggono questi token
-- invece di inventare dimensioni proprie, cosi' alert, aure e indicatori sono coerenti.
Theme.styles = {
    -- aura prioritaria (CC/difensivi) grande al centro dei frame
    priorityAura = { size = 36, borderSize = 2, borderColor = "cc", glow = "cc", countFont = "number", countSize = 14 },
    -- allerta a centro schermo ("guaritore in CC", "interrompi")
    alert = { font = "title", size = 24, color = "alert", bg = "bg", bgAlpha = 0.55, duration = 2.5, fadeOut = 0.4, offsetY = 180 },
    -- indicatore di combattimento sui frame
    combatIndicator = { size = 14, color = "combat", pulse = true },
    -- barre (vita, risorse, cast) piatte con hairline
    statusbar = { texture = "statusbar", border = "border", bg = "track", height = 18, spark = false },
}

-- FontObject condivisi: { chiave = { nome, size, flags, colore } }
local FONT_DEFS = {
    title   = { "BadbFontTitle",   18, "",        "text" },
    heading = { "BadbFontHeading", 14, "",        "text" },
    body    = { "BadbFontBody",    12, "",        "text" },
    small   = { "BadbFontSmall",   10, "",        "textDim" },
    mono    = { "BadbFontMono",    12, "",        "text" },
    number  = { "BadbFontNumber",  12, "OUTLINE", "text" },
}
Theme.fontObjects = {}
for k, def in pairs(FONT_DEFS) do Theme.fontObjects[k] = def[1] end

---------------------------------------------------------------------------
-- Stato e risoluzione
---------------------------------------------------------------------------

Theme.colors = {}
Theme.state = { scheme = "elvui", accent = "elvui", customAccent = nil, opacity = 1 }

local function set4(dst, r, g, b, a)
    dst[1], dst[2], dst[3], dst[4] = r, g, b, a or 1
    dst.r, dst.g, dst.b, dst.a = dst[1], dst[2], dst[3], dst[4]
    return dst
end

local function slot(key)
    local t = Theme.colors[key]
    if not t then t = {}; Theme.colors[key] = t end
    return t
end

-- Ricalcola Theme.colors senza sostituire le tabelle (chi le ha in mano le vede aggiornate).
function Theme:Resolve()
    local s = self.SCHEMES[self.state.scheme] or self.SCHEMES.elvui
    local op = self.state.opacity or 1
    for _, k in pairs({ "bg", "panel", "panelAlt", "sidebar", "header", "footer", "text", "textDim", "textMuted", "shadow" }) do
        local c = s[k]
        local a = c[4] or 1
        if k == "bg" or k == "panel" then a = a * op end
        set4(slot(k), c[1], c[2], c[3], a)
    end
    set4(slot("surface"), unpack(self.colors.panel, 1, 4))
    local ink = s.ink
    for k, a in pairs(WASH) do set4(slot(k), ink[1], ink[2], ink[3], a) end
    for _, k in ipairs({ "border", "divider" }) do -- override per schema (es. bordo nero ElvUI)
        local o = s[k]
        if o then set4(slot(k), o[1], o[2], o[3], o[4] or 1) end
    end
    for k, c in pairs(STATUS) do set4(slot(k), unpack(c)) end

    local acc = self.state.customAccent or self.ACCENTS[self.state.accent] or self.ACCENTS.elvui
    set4(slot("accent"), acc[1], acc[2], acc[3], 1)
    set4(slot("accentDim"), acc[1], acc[2], acc[3], 0.35)
    set4(slot("accentSoft"), acc[1], acc[2], acc[3], 0.14)
    set4(slot("onAccent"), 0.04, 0.05, 0.08, 1)
    set4(slot("focus"), acc[1], acc[2], acc[3], 0.8)
end

-- "accent" o "colors.accent" -> r, g, b, a
function Theme:Get(key)
    if type(key) == "table" then return key[1], key[2], key[3], key[4] or 1 end
    key = key and key:gsub("^colors%.", "") or "text"
    local c = self.colors[key] or self.colors.text
    return c[1], c[2], c[3], c[4] or 1
end

function Theme:GetColor(key) return self.colors[(key or ""):gsub("^colors%.", "")] end

function Theme:Hex(key)
    local r, g, b = self:Get(key)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- Testo colorato inline: Theme:Wrap("ciao", "accent")
function Theme:Wrap(text, key) return self:Hex(key) .. tostring(text) .. "|r" end

---------------------------------------------------------------------------
-- Pittura che segue il tema
---------------------------------------------------------------------------

local painted = setmetatable({}, { __mode = "k" })
local listeners = {}

local function apply(region, key, mul)
    local r, g, b, a = Theme:Get(key)
    a = a * (mul or 1)
    local ot = region.GetObjectType and region:GetObjectType()
    if ot == "FontString" or ot == "EditBox" then
        region:SetTextColor(r, g, b, a)
    elseif ot == "Texture" then
        if region.badbVertex then region:SetVertexColor(r, g, b, a) else region:SetColorTexture(r, g, b, a) end
    elseif ot == "StatusBar" then
        region:SetStatusBarColor(r, g, b, a)
    elseif region.SetBackdropColor then
        region:SetBackdropColor(r, g, b, a)
    end
end

-- Colora una region con un token e la ricolora a ogni cambio tema.
-- key = nil smette di seguirlo.
function Theme:Paint(region, key, mul)
    if not region then return end
    if key == nil then painted[region] = nil; return end
    local p = painted[region] or {}
    p.key, p.mul = key, mul
    painted[region] = p
    apply(region, key, mul)
    return region
end

function Theme:Unpaint(region) painted[region] = nil end

-- fn(Theme) ora e a ogni cambio tema. owner per poterlo rimuovere.
function Theme:OnChange(owner, fn, skipNow)
    listeners[owner] = fn
    if not skipNow then pcall(fn, self) end
end

function Theme:OffChange(owner) listeners[owner] = nil end

local function updateFonts()
    if not CreateFont then return end -- ambienti ridotti (test headless)
    for key, def in pairs(FONT_DEFS) do
        local obj = _G[def[1]] or CreateFont(def[1])
        local path = (key == "mono" or key == "number") and Theme.fonts.mono or Theme.fonts.body
        obj:SetFont(path, def[2], def[3])
        obj:SetTextColor(Theme:Get(def[4]))
        obj:SetShadowColor(0, 0, 0.02, 0.8)
        obj:SetShadowOffset(1, -1)
        Theme.fontObjects[key] = def[1]
    end
end

function Theme:Refresh()
    self:Resolve()
    updateFonts()
    for region, p in pairs(painted) do pcall(apply, region, p.key, p.mul) end
    for owner, fn in pairs(listeners) do
        local ok, err = pcall(fn, self)
        if not ok and Badb.Logger then Badb.Logger:Error("Theme listener %s: %s", tostring(owner.name or owner), err) end
    end
    if Events then Events:Fire("BADB_THEME_CHANGED", self.state.scheme) end
end

---------------------------------------------------------------------------
-- Preferenze (salvate in BadbUIDB.global.theme, valide per tutti i profili)
---------------------------------------------------------------------------

local function store()
    if type(BadbUIDB) ~= "table" then return nil end
    BadbUIDB.global = BadbUIDB.global or {}
    BadbUIDB.global.theme = BadbUIDB.global.theme or {}
    return BadbUIDB.global.theme
end

local function save()
    local db = store()
    if not db then return end
    db.scheme, db.accent, db.opacity = Theme.state.scheme, Theme.state.accent, Theme.state.opacity
    db.customAccent = Theme.state.customAccent and { unpack(Theme.state.customAccent) } or nil
end

function Theme:SetScheme(name)
    if not self.SCHEMES[name] then return false end
    self.state.scheme = name
    save(); self:Refresh()
    return true
end

-- SetAccent("jade") oppure SetAccent(r, g, b)
function Theme:SetAccent(r, g, b)
    if type(r) == "string" then
        if not self.ACCENTS[r] then return false end
        self.state.accent, self.state.customAccent = r, nil
    else
        self.state.customAccent = { r, g, b }
    end
    save(); self:Refresh()
    return true
end

function Theme:SetOpacity(v)
    self.state.opacity = math.max(0.3, math.min(1, v or 1))
    save(); self:Refresh()
end

function Theme:ListSchemes()
    local out = {}
    for _, k in ipairs(self.SCHEME_ORDER) do out[#out + 1] = { value = k, text = self.SCHEMES[k].label } end
    return out
end

-- Le SavedVariables possono essere corrotte o scritte da versioni vecchie: si valida tutto.
local function validColor(c)
    if type(c) ~= "table" then return false end
    for i = 1, 3 do
        if type(c[i]) ~= "number" or c[i] ~= c[i] or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end
Theme.ValidColor = validColor

function Theme:Load()
    local db = store()
    if db then
        if self.SCHEMES[db.scheme] then self.state.scheme = db.scheme end
        if self.ACCENTS[db.accent] then self.state.accent = db.accent end
        if validColor(db.customAccent) then
            self.state.customAccent = { db.customAccent[1], db.customAccent[2], db.customAccent[3] }
        else
            db.customAccent = nil
        end
        if type(db.opacity) == "number" and db.opacity == db.opacity then
            self.state.opacity = math.max(0.3, math.min(1, db.opacity))
        end
    end
    self:Refresh()
end

-- Torna ai valori di fabbrica (schema ElvUI, accento azzurro, opacita' piena).
function Theme:Reset()
    self.state.scheme, self.state.accent, self.state.customAccent, self.state.opacity = "elvui", "elvui", nil, 1
    save(); self:Refresh()
end

---------------------------------------------------------------------------
-- Pixel perfect: 1 "pixel" del tema = 1 pixel fisico dello schermo, a qualsiasi
-- scala UI e risoluzione. Ricalcolato su UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED.
---------------------------------------------------------------------------

function Theme:Pixel(frame)
    local _, physH = 0, 0
    if GetPhysicalScreenSize then _, physH = GetPhysicalScreenSize() end
    if not physH or physH <= 0 then return 1 end
    local scale = (frame or UIParent) and (frame or UIParent):GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    return 768 / physH / scale
end

local skinned = setmetatable({}, { __mode = "k" })

local function layoutEdges(frame)
    local s = frame.badbSkin
    if not s then return end
    local px = Theme:Pixel(frame)
    s.top:SetHeight(px); s.bottom:SetHeight(px)
    s.left:SetWidth(px); s.right:SetWidth(px)
end

---------------------------------------------------------------------------
-- Skin: fondo + hairline 1px su un frame qualunque (anche di altri moduli)
---------------------------------------------------------------------------

local function edge(frame, layer)
    local t = frame:CreateTexture(nil, layer or "BORDER")
    t:SetTexture(Theme.textures.white)
    t.badbVertex = true
    return t
end

-- opts: { bg = "panel", border = "border", alpha = 1, inset = 0, shadow = false }
function Theme:Skin(frame, opts)
    opts = opts or {}
    local s = frame.badbSkin
    if not s then
        s = {}
        s.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        s.bg:SetTexture(self.textures.white); s.bg.badbVertex = true
        s.top, s.bottom, s.left, s.right = edge(frame), edge(frame), edge(frame), edge(frame)
        s.top:SetPoint("TOPLEFT"); s.top:SetPoint("TOPRIGHT")
        s.bottom:SetPoint("BOTTOMLEFT"); s.bottom:SetPoint("BOTTOMRIGHT")
        s.left:SetPoint("TOPLEFT"); s.left:SetPoint("BOTTOMLEFT")
        s.right:SetPoint("TOPRIGHT"); s.right:SetPoint("BOTTOMRIGHT")
        frame.badbSkin = s
        skinned[frame] = true
        layoutEdges(frame)
    end
    local inset = opts.inset or 0
    s.bg:ClearAllPoints()
    s.bg:SetPoint("TOPLEFT", inset, -inset); s.bg:SetPoint("BOTTOMRIGHT", -inset, inset)
    if opts.bg == false then s.bg:Hide() else s.bg:Show(); self:Paint(s.bg, opts.bg or "panel", opts.alpha) end
    for _, e in ipairs({ s.top, s.bottom, s.left, s.right }) do
        if opts.border == false then e:Hide() else e:Show(); self:Paint(e, opts.border or "border") end
    end
    if opts.shadow and not s.shadow then
        s.shadow = CreateFrame("Frame", nil, frame)
        s.shadow:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
        s.shadow:SetPoint("TOPLEFT", -4, 4); s.shadow:SetPoint("BOTTOMRIGHT", 4, -4)
        local t = s.shadow:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetAllPoints(); t:SetTexture(self.textures.white); t.badbVertex = true
        self:Paint(t, "shadow", 0.5)
    end
    return frame
end

-- Cambia il colore della hairline di uno skin esistente (focus, hover, errore).
function Theme:SetBorder(frame, key, mul)
    local s = frame.badbSkin
    if not s then return end
    for _, e in ipairs({ s.top, s.bottom, s.left, s.right }) do self:Paint(e, key or "border", mul) end
end

-- Compatibilita' con chi chiede un bottone al tema.
function Theme:CreateButton(parent, text, w, h, onClick, variant)
    return Badb.UI:Button(parent, text, w, h, onClick, variant)
end

-- Gradiente verticale tra due token (header "cielo notturno").
function Theme:Gradient(texture, topKey, bottomKey, topMul, bottomMul)
    texture:SetTexture(self.textures.white)
    local function paint()
        local r1, g1, b1, a1 = self:Get(topKey)
        local r2, g2, b2, a2 = self:Get(bottomKey)
        a1, a2 = a1 * (topMul or 1), a2 * (bottomMul or 1)
        if CreateColor and pcall(texture.SetGradient, texture, "VERTICAL", CreateColor(r2, g2, b2, a2), CreateColor(r1, g1, b1, a1)) then
            return
        end
        texture:SetVertexColor(r1, g1, b1, a1) -- client senza SetGradient a colori
    end
    paint()
    self:OnChange(texture, paint, true)
    return texture
end

-- Valori validi gia' al caricamento del file; le preferenze salvate arrivano a PLAYER_LOGIN.
Theme:Resolve()
updateFonts()
Events:On(Theme, "PLAYER_LOGIN", function() Theme:Load() end)

local function rescale()
    for frame in pairs(skinned) do pcall(layoutEdges, frame) end
end
Theme.RelayoutPixels = rescale
Events:On(Theme, "UI_SCALE_CHANGED", rescale)
Events:On(Theme, "DISPLAY_SIZE_CHANGED", rescale)
