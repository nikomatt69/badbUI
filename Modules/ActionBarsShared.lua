-- BadbUI - Libreria condivisa per i moduli ActionBars e Cooldowns.
-- Elenco barre/pulsanti Blizzard (risolti in modo lazy, i nomi cambiano tra le patch)
-- e accesso al tema visivo. Se il design system (Badb.Theme) e' caricato lo usa,
-- altrimenti ricade su una palette locale equivalente.
local _, ns = ...
local Badb = ns.Badb
local Compat = Badb.Compat

local Lib = {}
Badb.ActionBarsLib = Lib

-- key: chiave nelle opzioni; frames: candidati per la barra (il primo esistente vince);
-- prefix/count: pulsanti "<prefix><n>".
Lib.BARS = {
    { key = "main",        title = "Barra principale", frames = { "MainActionBar", "MainMenuBar" }, prefix = "ActionButton",              count = 12 },
    { key = "bottomLeft",  title = "Barra 2",          frames = { "MultiBarBottomLeft" },           prefix = "MultiBarBottomLeftButton",  count = 12 },
    { key = "bottomRight", title = "Barra 3",          frames = { "MultiBarBottomRight" },          prefix = "MultiBarBottomRightButton", count = 12 },
    { key = "right",       title = "Barra 4",          frames = { "MultiBarRight" },                prefix = "MultiBarRightButton",       count = 12 },
    { key = "left",        title = "Barra 5",          frames = { "MultiBarLeft" },                 prefix = "MultiBarLeftButton",        count = 12 },
    { key = "bar6",        title = "Barra 6",          frames = { "MultiBar5" },                    prefix = "MultiBar5Button",           count = 12 },
    { key = "bar7",        title = "Barra 7",          frames = { "MultiBar6" },                    prefix = "MultiBar6Button",           count = 12 },
    { key = "bar8",        title = "Barra 8",          frames = { "MultiBar7" },                    prefix = "MultiBar7Button",           count = 12 },
    { key = "pet",         title = "Barra famiglio",   frames = { "PetActionBar", "PetActionBarFrame" }, prefix = "PetActionButton",  count = 10 },
    { key = "stance",      title = "Barra forme",      frames = { "StanceBar", "StanceBarFrame" },  prefix = "StanceButton",              count = 10 },
}

function Lib.GetBarFrame(bar)
    for _, name in ipairs(bar.frames) do
        local f = _G[name]
        if f then return f end
    end
end

-- fn(button, bar, index) per ogni pulsante esistente.
function Lib.ForEachButton(fn)
    for _, bar in ipairs(Lib.BARS) do
        for i = 1, bar.count do
            local b = _G[bar.prefix .. i]
            if b then fn(b, bar, i) end
        end
    end
end

-- Regioni standard di un pulsante d'azione (Mainline, con fallback sui nomi globali).
function Lib.Regions(b)
    local name = b:GetName() or ""
    return {
        icon = b.icon or b.Icon or _G[name .. "Icon"],
        hotkey = b.HotKey or _G[name .. "HotKey"],
        macro = b.Name or _G[name .. "Name"],
        count = b.Count or _G[name .. "Count"],
        cooldown = b.cooldown or b.Cooldown or _G[name .. "Cooldown"],
        normal = b.GetNormalTexture and b:GetNormalTexture(),
        mask = b.IconMask,
        slotBg = b.SlotBackground,
        slotArt = b.SlotArt,
        border = b.Border or _G[name .. "Border"],
    }
end

---------------------------------------------------------------------------
-- Tema
---------------------------------------------------------------------------
local FALLBACK = {
    colors = {
        bg       = { 0.05, 0.06, 0.08, 0.85 },
        border   = { 0.16, 0.18, 0.22, 1 },
        accent   = { 0.25, 0.65, 1.00, 1 },
        text     = { 0.95, 0.96, 0.98, 1 },
        textDim  = { 0.60, 0.64, 0.70, 1 },
        danger   = { 1.00, 0.32, 0.32, 1 },
        warning  = { 1.00, 0.80, 0.25, 1 },
        mana     = { 0.35, 0.55, 1.00, 1 },
        disabled = { 0.40, 0.40, 0.40, 1 },
    },
    fonts = {
        normal = "Fonts\\FRIZQT__.TTF",
        bold   = "Fonts\\FRIZQT__.TTF",
        mono   = "Fonts\\ARIALN.TTF",
        number = "Fonts\\ARIALN.TTF",
    },
}
Lib.FALLBACK_THEME = FALLBACK

local function fromTheme(group, name)
    local T = Badb.Theme
    if not T then return nil end
    -- Badb.Theme.colors/fonts sono tabelle aggiornate in place al cambio tema:
    -- leggerle ad ogni applicazione basta per seguire lo schema attivo.
    return type(T[group]) == "table" and T[group][name] or nil
end

-- Restituisce r, g, b, a. Accetta colori {r,g,b,a} o {r=,g=,b=,a=}.
function Lib.Color(name)
    local c = fromTheme("colors", name) or FALLBACK.colors[name] or FALLBACK.colors.text
    if type(c) ~= "table" then c = FALLBACK.colors[name] or FALLBACK.colors.text end
    return c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1
end

function Lib.Font(name)
    local f = fromTheme("fonts", name)
    if type(f) == "table" then f = f.path or f[1] end
    return f or FALLBACK.fonts[name] or FALLBACK.fonts.normal
end

-- Bordo piatto 1px + sfondo, stile "card" del design system.
function Lib.CreateBorder(parent, size)
    local f = Compat.CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 1)
    Lib.StyleBorder(f, size)
    return f
end

function Lib.StyleBorder(f, size)
    size = size or 1
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", -size, size)
    f:SetPoint("BOTTOMRIGHT", size, -size)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = size })
        f:SetBackdropBorderColor(Lib.Color("border"))
    end
end

-- Abbreviazione dei tasti: "SHIFT-BUTTON4" -> "SM4", "CTRL-NUMPAD5" -> "CN5".
local KEY_REPLACEMENTS = {
    { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "M" },
    { "MOUSEWHEELUP", "WU" }, { "MOUSEWHEELDOWN", "WD" },
    { "MIDDLEMOUSE", "M3" }, { "BUTTON(%d+)", "M%1" },
    { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" }, { "NUMPADMULTIPLY", "N*" },
    { "NUMPADDIVIDE", "N/" }, { "NUMPADDECIMAL", "N." }, { "NUMPAD", "N" },
    { "CAPSLOCK", "Caps" }, { "SPACEBAR", "Sp" }, { "SPACE", "Sp" },
    { "PAGEUP", "PgU" }, { "PAGEDOWN", "PgD" }, { "INSERT", "Ins" },
    { "DELETE", "Del" }, { "HOME", "Hm" }, { "BACKSPACE", "Bs" }, { "ESCAPE", "Esc" },
    { "TAB", "Tab" }, { "ENTER", "Ent" },
}

function Lib.ShortKey(key)
    if not key or key == "" then return nil end
    key = key:upper()
    for _, r in ipairs(KEY_REPLACEMENTS) do key = key:gsub(r[1], r[2]) end
    return key
end
