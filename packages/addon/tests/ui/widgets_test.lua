-- Controlli: comportamento, stati disabilitati, valori limite.
local S = {}

S["Button: click, varianti, disabilitato non esegue"] = function(boot)
    local T = boot()
    local n = 0
    local b = T.UI:Button(UIParent, "Ok", 100, 24, function() n = n + 1 end, "primary")
    T.Mock.click(b)
    T.eq(n, 1)
    T.sameColor(b.bg, "accent", "primary usa l'accento")
    T.sameColor(b.text, "onAccent")
    b:SetVariant("ghost")
    T.ok(not b.bg:IsShown(), "ghost senza fondo")
    b:SetVariant("danger")
    T.ok(b.bg:IsShown()); T.sameColor(b.text, "danger")
    b:SetEnabled(false)
    T.Mock.click(b)
    T.eq(n, 1, "click su bottone disabilitato")
    T.eq(b:GetAlpha(), 0.4)
    b:SetEnabled(true); T.Mock.click(b); T.eq(n, 2)
    -- variante sconosciuta: ripiega su secondary senza errori
    local b2 = T.UI:Button(UIParent, "x", nil, nil, nil, "boh")
    T.Mock.click(b2) -- onClick nil: nessun errore
    T.eq(b2:GetHeight(), T.Theme.sizes.button)
end

S["ConfirmButton: serve il secondo click entro 3 secondi"] = function(boot)
    local T = boot()
    local n = 0
    local b = T.UI:ConfirmButton(UIParent, "Reset", "Sicuro?", 100, 24, function() n = n + 1 end)
    T.Mock.click(b)
    T.eq(n, 0); T.eq(b.text:GetText(), "Sicuro?")
    T.Mock.advance(3.1)
    T.eq(b.text:GetText(), "Reset", "armamento non scaduto")
    T.Mock.click(b); T.Mock.click(b)
    T.eq(n, 1); T.eq(b.text:GetText(), "Reset")
end

S["Toggle: legge get, scrive set, ridisegna, rispetta disabilitato"] = function(boot)
    local T = boot()
    local v, changes = false, 0
    local t = T.UI:Toggle(UIParent, "Attivo", function() return v end, function(x) v = x end, { onChange = function() changes = changes + 1 end })
    T.eq(t.value, false); T.sameColor(t.switch.track, "track")
    T.Mock.click(t.switch)
    T.eq(v, true); T.eq(changes, 1); T.sameColor(t.switch.track, "accent")
    t:SetEnabled(false)
    T.Mock.click(t.switch)
    T.eq(v, true, "toggle disabilitato ha cambiato valore")
    -- cambio esterno + Refresh
    v = false; t:Refresh(); T.eq(t.value, false)
    -- get che ritorna nil o valori non booleani
    local t2 = T.UI:Toggle(UIParent, "x", function() return nil end, function() end)
    T.eq(t2.value, false)
    local t3 = T.UI:Toggle(UIParent, "x", function() return 1 end, function() end)
    T.eq(t3.value, true)
end

S["Checkbox: spunta e bordo d'accento"] = function(boot)
    local T = boot()
    local v = false
    local c = T.UI:Checkbox(UIParent, "Spunta", function() return v end, function(x) v = x end)
    T.ok(not c.box.fill:IsShown())
    T.Mock.click(c)
    T.eq(v, true); T.ok(c.box.fill:IsShown()); T.sameColor(c.box.badbSkin.top, "accent")
    c:SetEnabled(false); T.Mock.click(c); T.eq(v, true)
end

S["Slider: input utente, formato, rotella, limiti e valori non numerici"] = function(boot)
    local T = boot()
    local v = 0.5
    local s = T.UI:Slider(UIParent, "Alpha", 0, 1, 0.1, function() return v end, function(x) v = x end, { percent = true })
    T.eq(s.valueText:GetText(), "50%")
    s.slider:SetValue(0.8, true)
    T.near(v, 0.8); T.eq(s.valueText:GetText(), "80%")
    s.slider:SetValue(0.3) -- programmatico: nessun set
    T.near(v, 0.8)
    T.Mock.script(s.slider, "OnMouseWheel", 1)
    T.near(v, 0.4)
    s.slider:SetValue(1, true)
    T.Mock.script(s.slider, "OnMouseWheel", 1)
    T.near(v, 1, 1e-9, "rotella oltre il massimo")
    s:SetEnabled(false)
    s.slider:SetValue(0.2, true)
    T.near(v, 1, 1e-9, "slider disabilitato ha scritto")
    -- valore salvato corrotto: si parte dal minimo
    local s2 = T.UI:Slider(UIParent, "x", 5, 10, 1, function() return "abc" end, function() end)
    T.eq(s2.slider:GetValue(), 5); T.eq(s2.valueText:GetText(), "5")
    -- formato personalizzato e live = false (scrive solo al rilascio)
    local w
    local s3 = T.UI:Slider(UIParent, "x", 0, 2, 0.5, function() return 1 end, function(x) w = x end,
        { format = function(x) return x .. "x" end, live = false })
    s3.slider:SetValue(1.5, true)
    T.eq(w, nil, "live=false non deve scrivere durante il drag")
    T.Mock.script(s3.slider, "OnMouseUp")
    T.eq(w, 1.5); T.eq(s3.valueText:GetText(), "1.5x")
end

S["Dropdown: apre, sceglie, item da funzione, disabilitati, valore ignoto"] = function(boot)
    local T = boot()
    local v = "b"
    local items = { { value = "a", text = "A" }, { value = "b", text = "B" }, { value = "c", text = "C", disabled = true } }
    local d = T.UI:Dropdown(UIParent, "Scelta", items, function() return v end, function(x) v = x end)
    T.eq(d.button.text:GetText(), "B")
    T.Mock.click(d.button)
    local menu = _G.BadbUIDropdownMenu
    T.ok(menu:IsShown(), "menu non aperto"); T.eq(menu.owner, d); T.ok(d.open)
    local rows = menu.list.rows
    T.eq(rows[1].text:GetText(), "A")
    T.Mock.click(rows[3]) -- disabilitato
    T.eq(v, "b"); T.ok(menu:IsShown(), "click su item disabilitato ha chiuso il menu")
    T.Mock.click(rows[1])
    T.eq(v, "a"); T.ok(not menu:IsShown()); T.eq(d.button.text:GetText(), "A"); T.ok(not d.open)
    -- secondo click sullo stesso bottone chiude
    T.Mock.click(d.button); T.Mock.click(d.button); T.ok(not menu:IsShown())
    -- un solo menu: aprire un altro dropdown sposta il proprietario
    local d2 = T.UI:Dropdown(UIParent, nil, function() return { "x", "y" } end, function() return "zzz" end, function() end)
    T.Mock.click(d.button); T.Mock.click(d2.button)
    T.eq(menu.owner, d2); T.ok(not d.open, "il primo dropdown resta aperto")
    T.eq(d2.button.text:GetText(), "zzz", "valore fuori lista mostrato com'e'")
    T.UI:CloseDropdowns(); T.ok(not menu:IsShown())
    -- lista vuota e valore nil
    local d3 = T.UI:Dropdown(UIParent, "Vuoto", {}, function() return nil end, function() end, { placeholder = "Nessuno" })
    T.eq(d3.button.text:GetText(), "Nessuno")
    T.Mock.click(d3.button) -- non deve esplodere
    d3:SetEnabled(false); T.UI:CloseDropdowns(); T.Mock.click(d3.button); T.ok(not menu:IsShown())
end

S["Dropdown: lista lunga limitata a maxRows e scorre al valore scelto"] = function(boot)
    local T = boot()
    local items = {}
    for i = 1, 50 do items[i] = { value = i, text = "N" .. i } end
    local d = T.UI:Dropdown(UIParent, "Molti", items, function() return 40 end, function() end, { maxRows = 8 })
    T.Mock.click(d.button)
    local menu = _G.BadbUIDropdownMenu
    T.eq(menu:GetHeight(), 8 * 22 + 4)
    T.ok(menu.list.offset > 0, "non scorre fino al valore selezionato")
end

S["EditBox: invio, escape, placeholder, errore, multiline"] = function(boot)
    local T = boot()
    local entered, changed
    local e = T.UI:EditBox(UIParent, 200, 24, { placeholder = "Cerca", onEnter = function(t) entered = t end, onChange = function(t) changed = t end })
    T.ok(e.placeholder:IsShown())
    e.edit:SetFocus()
    T.ok(not e.placeholder:IsShown(), "placeholder visibile con focus")
    T.sameColor(e.badbSkin.top, "focus")
    e.edit._text = "ciao"; T.Mock.script(e.edit, "OnTextChanged", true)
    T.eq(changed, "ciao")
    T.Mock.script(e.edit, "OnEnterPressed")
    T.eq(entered, "ciao"); T.ok(not e.edit:HasFocus())
    T.sameColor(e.badbSkin.top, "border")
    e:SetError(true); T.sameColor(e.badbSkin.top, "danger")
    e:SetText(""); T.ok(e.placeholder:IsShown())
    e:SetEnabled(false); T.ok(not e.edit:HasFocus())
    local m = T.UI:EditBox(UIParent, 300, 120, { multiline = true })
    T.ok(m.scroll, "multiline senza scroll")
    m.edit:SetFocus()
    T.Mock.script(m.edit, "OnEnterPressed")
    T.eq(m:GetText(), "\n", "invio in multiline deve andare a capo")
end

S["ScrollList: virtualizza, ricicla righe, limita l'offset"] = function(boot)
    local T = boot()
    local created = 0
    local list = T.UI:ScrollList(UIParent, 20, function(parent)
        created = created + 1
        local r = CreateFrame("Frame", nil, parent)
        r.fs = r:CreateFontString()
        return r
    end, function(r, item) r.fs:SetText(item) end)
    list:SetSize(200, 100) -- 5 righe visibili
    local data = {}
    for i = 1, 1000 do data[i] = "riga " .. i end
    list:SetData(data)
    T.eq(created, 5, "righe create oltre le visibili")
    T.eq(list.rows[1].fs:GetText(), "riga 1")
    list.bar:SetValue(500)
    T.eq(list.rows[1].fs:GetText(), "riga 501")
    T.eq(created, 5, "lo scroll non deve creare righe")
    list:SetData({ "a", "b" })
    T.eq(list.offset, 0, "offset non riportato a 0 con meno dati")
    T.ok(list.rows[1]:IsShown() and list.rows[2]:IsShown() and not list.rows[3]:IsShown())
    list:SetData(nil) -- nessun errore, nessuna riga
    T.ok(not list.rows[1]:IsShown())
end

S["Chip, ProgressBar, Separator, Tooltip"] = function(boot)
    local T = boot()
    local c = T.UI:Chip(UIParent, "ok", "success")
    T.sameColor(c.text, "success")
    c:SetChip("n", "neutral"); T.sameColor(c.text, "textDim")
    T.ok(c:GetWidth() >= 24, "chip troppo stretto")
    local p = T.UI:ProgressBar(UIParent, 100, 4)
    p:SetProgress(2); T.eq(p:GetValue(), 1)
    p:SetProgress(-1); T.eq(p:GetValue(), 0)
    p:SetProgress(nil); T.eq(p:GetValue(), 0)
    local sep = T.UI:Separator(UIParent, true)
    T.eq(sep._w, 1)
    local owner = CreateFrame("Frame", nil, UIParent)
    T.UI:Tooltip(owner, "Titolo", { "riga", { left = "a", right = "b" }, { "rosso", "danger" } })
    T.eq(#GameTooltip._lines, 4)
    T.UI:HideTooltip(); T.ok(not GameTooltip:IsShown())
end

S["i widget seguono il cambio tema dopo la creazione"] = function(boot)
    local T = boot()
    local b = T.UI:Button(UIParent, "x", 80, 24, nil, "primary")
    local t = T.UI:Toggle(UIParent, "t", function() return true end, function() end)
    T.Theme:SetAccent(0.2, 0.9, 0.3)
    T.near(b.bg._color[1], 0.2); T.near(t.switch.track._color[2], 0.9)
end

S["le factory funzionano sia con : sia con ."] = function(boot)
    local T = boot()
    local n = 0
    local b = T.UI.Button(UIParent, "Punto", 80, 24, function() n = n + 1 end, "primary")
    T.Mock.click(b); T.eq(n, 1); T.eq(b._parent, UIParent)
    local t = T.UI.Toggle(UIParent, "x", function() return true end, function() end)
    T.eq(t.value, true)
end

return S
