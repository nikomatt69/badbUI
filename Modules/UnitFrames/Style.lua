-- BadbUI - Unit Frames: adattatore di stile
-- Legge colori, font e texture da Badb.Theme (design system condiviso, vedi docs/UI.md).
-- Se il tema non e' caricato (o manca una chiave) usa una palette di riserva con la stessa
-- direzione visiva: fondi notturni, hairline da 1px, testo bianco a scala, accento oro.
-- Tutte le letture passano da qui: i file degli elementi non conoscono il tema.
local _, ns = ...
local Badb = ns.Badb

local UF = ns.UF or {}
ns.UF = UF

local Style = {}
UF.Style = Style

local WHITE = "Interface\\Buttons\\WHITE8X8"

local FALLBACK = {
    bg        = { 0.07, 0.085, 0.13, 0.92 },
    panel     = { 0.11, 0.13, 0.2, 0.96 },
    panelAlt  = { 0.14, 0.165, 0.25, 1 },
    border    = { 1, 1, 1, 0.14 },
    divider   = { 1, 1, 1, 0.1 },
    accent    = { 0.9, 0.73, 0.4, 1 },
    accentDim = { 0.55, 0.45, 0.26, 1 },
    text      = { 0.97, 0.975, 0.99, 1 },
    textDim   = { 0.76, 0.79, 0.87, 1 },
    textMuted = { 0.6, 0.64, 0.73, 1 },
    success   = { 0.42, 0.85, 0.6, 1 },
    warning   = { 0.98, 0.75, 0.3, 1 },
    danger    = { 0.96, 0.45, 0.45, 1 },
    shadow    = { 0, 0, 0.02, 0.6 },
}

-- Colori specifici dei frame (non fanno parte del tema condiviso).
Style.unit = {
    health     = { 0.36, 0.78, 0.55 },  -- vita senza colore classe/reazione
    track      = { 0.04, 0.05, 0.08, 0.85 },
    dead       = { 0.42, 0.42, 0.46 },
    offline    = { 0.32, 0.33, 0.38 },
    tapped     = { 0.55, 0.55, 0.58 },
    hostile    = { 0.92, 0.36, 0.36 },
    neutral    = { 0.95, 0.8, 0.35 },
    friendly   = { 0.36, 0.78, 0.55 },
    castLocked = { 0.55, 0.57, 0.62 },  -- cast non interrompibile
}

local function theme() return Badb.Theme end

-- Restituisce r, g, b, a per una chiave del tema.
function Style.Color(key)
    local T = theme()
    if T and T.Get then
        local ok, r, g, b, a = pcall(T.Get, T, key)
        if ok and type(r) == "number" then return r, g, b, a or 1 end
    end
    local c = FALLBACK[key] or FALLBACK.text
    return c[1], c[2], c[3], c[4] or 1
end

function Style.Texture(key)
    local T = theme()
    local t = T and T.textures and T.textures[key or "statusbar"]
    return t or WHITE
end

function Style.Font(key)
    local T = theme()
    local f = T and T.fonts and T.fonts[key or "normal"]
    return f or STANDARD_TEXT_FONT
end

-- Sfondo piatto + bordo hairline da 1px (bordo esterno, non copre il contenuto).
function Style.Skin(f)
    if not f.badbBg then
        f.badbBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.badbBg:SetAllPoints()
        f.badbBorder = {}
        for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = f:CreateTexture(nil, "BORDER", nil, 7)
            t:SetTexture(WHITE)
            if side == "TOP" or side == "BOTTOM" then
                t:SetHeight(1)
                t:SetPoint(side .. "LEFT", -1, side == "TOP" and 1 or -1)
                t:SetPoint(side .. "RIGHT", 1, side == "TOP" and 1 or -1)
            else
                t:SetWidth(1)
                t:SetPoint("TOP" .. side, side == "LEFT" and -1 or 1, 1)
                t:SetPoint("BOTTOM" .. side, side == "LEFT" and -1 or 1, -1)
            end
            f.badbBorder[i] = t
        end
        -- Ombra morbida sotto il frame: profondita' senza bordi pesanti.
        f.badbShadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.badbShadow:SetTexture(WHITE)
        f.badbShadow:SetPoint("TOPLEFT", -3, 3)
        f.badbShadow:SetPoint("BOTTOMRIGHT", 3, -3)
    end
    f.badbBg:SetTexture(WHITE)
    f.badbBg:SetVertexColor(Style.Color("bg"))
    local r, g, b, a = Style.Color("border")
    for _, t in ipairs(f.badbBorder) do t:SetVertexColor(r, g, b, a) end
    local sr, sg, sb, sa = Style.Color("shadow")
    f.badbShadow:SetVertexColor(sr, sg, sb, (sa or 0.6) * 0.5)
end

-- Bordo evidenziato (es. bersaglio corrente nel party, aggro).
function Style.SetHighlight(f, colorKey)
    if not f.badbBorder then return end
    local r, g, b, a
    if colorKey then r, g, b, a = Style.Color(colorKey) else r, g, b, a = Style.Color("border") end
    for _, t in ipairs(f.badbBorder) do t:SetVertexColor(r, g, b, a) end
end

function Style.StatusBar(parent, layer)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(Style.Texture("statusbar"))
    bar.bg = bar:CreateTexture(nil, layer or "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(WHITE)
    local t = Style.unit.track
    bar.bg:SetVertexColor(t[1], t[2], t[3], t[4])
    return bar
end

function Style.Text(parent, size, justify, colorKey)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Style.Font("normal"), size or 11, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    fs.badbColor = colorKey or "text"
    fs:SetTextColor(Style.Color(fs.badbColor))
    return fs
end

function Style.RefreshText(fs, size)
    fs:SetFont(Style.Font("normal"), size, "")
    fs:SetTextColor(Style.Color(fs.badbColor or "text"))
end

-- Il design system notifica i cambi di tema con il messaggio BADB_THEME_CHANGED.
-- Usiamo il bus eventi (e non Theme:OnChange) cosi' Events:OffAll libera tutto al disable.
function Style.OnChange(owner, fn)
    Badb.Events:On(owner, "BADB_THEME_CHANGED", fn)
end
