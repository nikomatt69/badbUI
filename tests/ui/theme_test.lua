-- Theme: token, persistenza, validazione delle SavedVariables, contrasto, pixel perfect.
local S = {}

-- Luminanza relativa e contrasto WCAG.
local function lum(r, g, b)
    local function ch(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end
local function contrast(c1, c2)
    local l1, l2 = lum(c1[1], c1[2], c1[3]), lum(c2[1], c2[2], c2[3])
    if l1 < l2 then l1, l2 = l2, l1 end
    return (l1 + 0.05) / (l2 + 0.05)
end

S["espone tutte le chiavi del contratto pubblico"] = function(boot)
    local T = boot()
    for _, k in ipairs({ "bg", "surface", "panel", "panelAlt", "sidebar", "header", "border", "divider", "hover", "selected",
        "accent", "accentDim", "onAccent", "text", "textDim", "textMuted", "success", "warning", "danger", "shadow" }) do
        local c = T.Theme.colors[k]
        T.ok(type(c) == "table" and #c == 4, "colore mancante: " .. k)
        T.ok(c.r == c[1] and c.a == c[4], "alias r/g/b/a mancanti: " .. k)
    end
    for _, k in ipairs({ "normal", "body", "bold", "header", "title", "mono", "number" }) do
        T.ok(type(T.Theme.fonts[k]) == "string", "font mancante: " .. k)
    end
    for _, k in ipairs({ "title", "heading", "body", "small", "mono" }) do
        T.ok(_G[T.Theme.fontObjects[k]] ~= nil, "FontObject mancante: " .. k)
    end
    T.ok(T.Theme.textures.statusbar and T.Theme.textures.white, "texture mancanti")
    T.eq(_G.BadbUI.Theme, T.Theme, "Theme non esposto su _G.BadbUI")
end

S["Get accetta chiave nuda, prefisso colors. e fallback su chiave ignota"] = function(boot)
    local T = boot()
    local r1, g1, b1 = T.Theme:Get("accent")
    local r2, g2, b2 = T.Theme:Get("colors.accent")
    T.eq(r1, r2); T.eq(g1, g2); T.eq(b1, b2)
    local r3 = T.Theme:Get("nonEsiste")
    T.eq(r3, T.Theme.colors.text[1], "fallback su text")
    T.eq(select(4, T.Theme:Get(nil)), T.Theme.colors.text[4])
    T.ok(T.Theme:Hex("accent"):match("^|cff%x%x%x%x%x%x$"), "Hex non valido")
end

S["le tabelle colore restano le stesse (aggiornate in place)"] = function(boot)
    local T = boot()
    local accent, bg = T.Theme.colors.accent, T.Theme.colors.bg
    local before = bg[1]
    T.ok(T.Theme:SetScheme("graphite"))
    T.ok(T.Theme.colors.bg == bg, "tabella bg sostituita")
    T.ok(bg[1] ~= before, "bg non aggiornato")
    T.ok(T.Theme:SetAccent("jade"))
    T.ok(T.Theme.colors.accent == accent, "tabella accent sostituita")
    T.near(accent[1], T.Theme.ACCENTS.jade[1])
end

S["Paint ricolora le region al cambio tema"] = function(boot)
    local T = boot()
    local f = CreateFrame("Frame", nil, UIParent)
    local tex = f:CreateTexture()
    local fs = f:CreateFontString()
    T.Theme:Paint(tex, "accent")
    T.Theme:Paint(fs, "text", 0.5)
    T.sameColor(tex, "accent")
    T.Theme:SetAccent(0.1, 0.2, 0.3)
    T.near(tex._color[1], 0.1); T.near(tex._color[3], 0.3)
    T.near(fs._color[4], T.Theme.colors.text[4] * 0.5, 1e-6, "moltiplicatore alpha")
    T.Theme:Paint(tex, nil)
    T.Theme:SetAccent("gold")
    T.near(tex._color[1], 0.1, 1e-6, "region rimossa ancora dipinta")
end

S["OnChange e messaggio BADB_THEME_CHANGED"] = function(boot)
    local T = boot()
    local calls, msgs = 0, 0
    T.Theme:OnChange("x", function() calls = calls + 1 end)
    T.eq(calls, 1, "OnChange deve chiamare subito")
    T.Badb.Events:On({}, "BADB_THEME_CHANGED", function() msgs = msgs + 1 end)
    T.Theme:SetScheme("dusk")
    T.eq(calls, 2); T.eq(msgs, 1)
    T.Theme:OffChange("x")
    T.Theme:SetScheme("night")
    T.eq(calls, 2, "listener rimosso chiamato")
end

S["un listener che lancia errori non blocca gli altri"] = function(boot)
    local T = boot()
    local reached = false
    T.Theme:OnChange("a", function() error("boom") end, true)
    T.Theme:OnChange("b", function() reached = true end, true)
    T.Theme:SetScheme("dusk")
    T.ok(reached, "listener successivo non eseguito")
end

S["valori non validi rifiutati"] = function(boot)
    local T = boot()
    T.eq(T.Theme:SetScheme("inesistente"), false)
    T.eq(T.Theme.state.scheme, "elvui")
    T.eq(T.Theme:SetAccent("inesistente"), false)
    T.eq(T.Theme.state.accent, "elvui")
    T.Theme:SetOpacity(5); T.eq(T.Theme.state.opacity, 1)
    T.Theme:SetOpacity(-1); T.eq(T.Theme.state.opacity, 0.3)
end

S["preferenze salvate e ricaricate al login"] = function(boot)
    local T = boot()
    T.Theme:SetScheme("graphite"); T.Theme:SetAccent("violet"); T.Theme:SetOpacity(0.8)
    local saved = BadbUIDB
    local T2 = boot({ db = saved })
    T2.eq(T2.Theme.state.scheme, "graphite")
    T2.eq(T2.Theme.state.accent, "violet")
    T2.near(T2.Theme.state.opacity, 0.8)
    T2.near(T2.Theme.colors.bg[4], T2.Theme.SCHEMES.graphite.bg[4] * 0.8)
end

S["SavedVariables corrotte: si torna ai default senza errori"] = function(boot)
    local bad = { global = { theme = { scheme = 42, accent = {}, customAccent = { "x", 2, -1 }, opacity = 0 / 0 } } }
    local T = boot({ db = bad })
    T.eq(T.Theme.state.scheme, "elvui")
    T.eq(T.Theme.state.accent, "elvui")
    T.eq(T.Theme.state.customAccent, nil)
    T.eq(T.Theme.state.opacity, 1)
    T.eq(bad.global.theme.customAccent, nil, "accento corrotto non ripulito")
    -- theme non tabella / global non tabella
    local T2 = boot({ db = { global = { theme = nil } } })
    T2.eq(T2.Theme.state.scheme, "elvui")
end

S["Reset riporta ai valori di fabbrica"] = function(boot)
    local T = boot()
    T.Theme:SetScheme("dusk"); T.Theme:SetAccent(1, 0, 0); T.Theme:SetOpacity(0.5)
    T.Theme:Reset()
    T.eq(T.Theme.state.scheme, "elvui"); T.eq(T.Theme.state.customAccent, nil); T.eq(T.Theme.state.opacity, 1)
    T.eq(BadbUIDB.global.theme.scheme, "elvui")
end

S["tema usabile prima del login (valori di default gia' risolti)"] = function(boot)
    local T = boot({ noLogin = true })
    T.ok(T.Theme.colors.accent[1] > 0, "accent non risolto prima del login")
    local f = T.UI:Panel(UIParent)
    T.ok(f.badbSkin, "Skin fallito prima del login")
end

S["contrasto del testo leggibile su ogni schema (7:1 primario, 4.5:1 secondario)"] = function(boot)
    local T = boot()
    for name, s in pairs(T.Theme.SCHEMES) do
        for _, ground in ipairs({ "bg", "panel", "panelAlt", "sidebar" }) do
            T.ok(contrast(s.text, s[ground]) >= 7, name .. ": text su " .. ground)
            T.ok(contrast(s.textDim, s[ground]) >= 4.5, name .. ": textDim su " .. ground)
            T.ok(contrast(s.textMuted, s[ground]) >= 3, name .. ": textMuted su " .. ground)
        end
    end
    for name, acc in pairs(T.Theme.ACCENTS) do
        T.ok(contrast({ 0.04, 0.05, 0.08 }, acc) >= 4.5, "onAccent su accento " .. name)
        T.ok(contrast(acc, T.Theme.SCHEMES.night.bg) >= 4.5, "accento " .. name .. " su night")
    end
end

S["schema ElvUI: predefinito, bordo nero pieno, accento azzurro"] = function(boot)
    local T = boot()
    T.eq(T.Theme.state.scheme, "elvui"); T.eq(T.Theme.state.accent, "elvui")
    local b = T.Theme.colors.border
    T.near(b[1], 0); T.near(b[2], 0); T.near(b[3], 0); T.near(b[4], 1, 1e-6, "bordo non pieno")
    local a = T.Theme.colors.accent
    T.ok(a[3] > a[1] and a[3] > 0.8, "accento non azzurro")
    -- lo schema notte mantiene la hairline chiara
    T.Theme:SetScheme("night")
    T.near(T.Theme.colors.border[1], 1); T.near(T.Theme.colors.border[4], 0.12, 1e-6)
    T.Theme:SetScheme("elvui")
    T.near(T.Theme.colors.border[1], 0, 1e-6, "override non riapplicato")
end

S["hairline pixel perfect su ogni scala e risoluzione"] = function(boot)
    local T = boot({ physH = 1440 })
    local f = T.UI:Panel(UIParent)
    T.near(f.badbSkin.top._h, 768 / 1440, 1e-6, "1px a 1440p")
    UIParent:SetScale(0.64)
    T.Mock.fire("UI_SCALE_CHANGED")
    T.near(f.badbSkin.left._w, 768 / 1440 / 0.64, 1e-6, "1px dopo cambio scala")
    T.Mock.state.physH = 2160
    T.Mock.fire("DISPLAY_SIZE_CHANGED")
    T.near(f.badbSkin.bottom._h, 768 / 2160 / 0.64, 1e-6, "1px dopo cambio risoluzione")
    T.Mock.state.physH = 0
    T.eq(T.Theme:Pixel(), 1, "fallback con risoluzione ignota")
end

S["Skin riapplicato non duplica le texture"] = function(boot)
    local T = boot()
    local f = CreateFrame("Frame", nil, UIParent)
    T.Theme:Skin(f)
    local n = #f._children
    local s = f.badbSkin
    T.Theme:Skin(f, { bg = "panelAlt", border = "accent" })
    T.eq(#f._children, n, "texture duplicate")
    T.eq(f.badbSkin, s)
    T.sameColor(s.bg, "panelAlt"); T.sameColor(s.top, "accent")
    T.Theme:Skin(f, { bg = false, border = false })
    T.ok(not s.bg:IsShown() and not s.top:IsShown(), "bg/bordo non nascosti")
end

S["/badb theme da riga di comando"] = function(boot)
    local T = boot()
    SlashCmdList.BADBUI("theme dusk jade")
    T.eq(T.Theme.state.scheme, "dusk"); T.eq(T.Theme.state.accent, "jade")
    SlashCmdList.BADBUI("theme ember")
    T.eq(T.Theme.state.accent, "ember")
    SlashCmdList.BADBUI("theme boh")
    T.eq(T.Theme.state.scheme, "dusk", "schema ignoto non deve cambiare nulla")
end

S["gli stili di gioco puntano a token esistenti"] = function(boot)
    local T = boot()
    for name, st in pairs(T.Theme.styles) do
        for _, field in ipairs({ "borderColor", "glow", "color", "bg", "border" }) do
            if st[field] then T.ok(T.Theme.colors[st[field]], name .. "." .. field .. " -> " .. st[field]) end
        end
        if st.font then T.ok(T.Theme.fontObjects[st.font], name .. ".font") end
        if st.texture then T.ok(T.Theme.textures[st.texture], name .. ".texture") end
    end
    for _, k in ipairs({ "cc", "combat", "alert", "info" }) do T.ok(T.Theme.colors[k], "colore " .. k) end
end

return S
