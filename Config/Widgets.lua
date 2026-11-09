-- BadbUI - Widget dichiarativi per la ConfigUI.
-- Ogni modulo descrive le opzioni come dati: { type, path | get/set, label, ... }
-- Tipi: header, toggle, range, execute, select (storici) + dropdown, text, color, label, separator, list.
-- Campi comuni: hidden = bool|fn, disabled = bool|fn, tooltip = stringa|fn.
-- Nuovi tipi = nuova funzione in W.Builders (firma: builder(parent, module, opt) -> frame, altezza[, xoff, yoff]).
-- Tutti i builder ufficiali sono "a prova di errore": un descrittore errato produce una riga rossa, mai un errore Lua.
local _, ns = ...
local Badb = ns.Badb

local W = { Builders = {} }
Badb.Widgets = W

W.hex = { accent = "3fa7ff", muted = "888888", ok = "5fd068", warn = "ffcc00", err = "ff5050", title = "ffd100" }
W.colors = {
    panel = { 0.07, 0.08, 0.10, 0.96 },
    panelBorder = { 0.25, 0.65, 1, 0.55 },
    row = { 1, 1, 1, 0.04 },
    accent = { 0.25, 0.65, 1, 1 },
}

local WIDTH = 540 -- larghezza utile di una pagina (il contratto dice ~560)
W.width = WIDTH

---------------------------------------------------------------------------
-- Utilita' di base
---------------------------------------------------------------------------
local function logError(fmt, ...)
    if Badb.Logger then Badb.Logger:Error(fmt, ...) end
end

-- Chiama un metodo solo se esiste (i template Blizzard cambiano tra le patch), senza mai lanciare.
function W.Call(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

-- Valuta un valore o una funzione (con pcall). In errore o nil ritorna default.
function W.Eval(v, default)
    if type(v) == "function" then
        local ok, r = pcall(v)
        if ok and r ~= nil then return r end
        return default
    end
    if v == nil then return default end
    return v
end

-- Esegue fn(...) isolando gli errori (log). Ritorna ok, risultati.
function W.Safe(fn, what, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        logError("%s: %s", what or "widget", tostring(a))
        return false
    end
    return true, a, b
end

-- CreateFrame che prova i template in ordine e ricade su un frame base se nessuno esiste.
-- Ritorna frame, templateUsato (nil se base).
function W.CreateFrame(kind, name, parent, ...)
    for i = 1, select("#", ...) do
        local tpl = select(i, ...)
        if tpl then
            local ok, f = pcall(CreateFrame, kind, name, parent, tpl)
            if ok and f then return f, tpl end
        end
    end
    local ok, f = pcall(CreateFrame, kind, name, parent)
    if ok and f then return f, nil end
    error("CreateFrame(" .. tostring(kind) .. ") non riuscito: " .. tostring(f), 2)
end

function W.Backdrop(f, bg, border)
    if type(f.SetBackdrop) ~= "function" then return end
    pcall(function()
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        bg, border = bg or W.colors.panel, border or W.colors.panelBorder
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end)
end

function W.MakeButton(parent, text, width, height, onClick)
    local b, tpl = W.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, height or 22)
    if not tpl then
        W.Call(b, "SetNormalFontObject", "GameFontNormal")
        W.Call(b, "SetHighlightFontObject", "GameFontHighlight")
    end
    b:SetText(text or "")
    if onClick then
        b:SetScript("OnClick", function(self, mouse) W.Safe(onClick, "pulsante", self, mouse) end)
    end
    return b
end

-- ScrollFrame con figlio; ritorna sf, child.
function W.CreateScrollFrame(parent)
    local sf, tpl = W.CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(WIDTH, 1)
    sf:SetScrollChild(child)
    if not tpl then
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local cur = tonumber(self:GetVerticalScroll()) or 0
            local range = tonumber(self:GetVerticalScrollRange()) or 0
            self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 30)))
        end)
    end
    return sf, child
end

function W.SetChildHeight(sf, child, h)
    child:SetHeight(math.max(1, h or 1))
    W.Call(sf, "UpdateScrollChildRect")
end

-- Stima l'altezza di un testo a capo automatico (usata quando il client non da' GetStringHeight).
function W.EstimateTextHeight(text, width, lineHeight, charWidth)
    text = tostring(text or "")
    lineHeight, charWidth = lineHeight or 14, charWidth or 6.2
    local perLine = math.max(1, math.floor((width or WIDTH) / charWidth))
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(#line / perLine))
    end
    return lines * lineHeight
end

local function stringHeight(fs, text, width, lineHeight)
    local ok, h = pcall(fs.GetStringHeight, fs)
    if ok and type(h) == "number" and h > 0 then return h end
    return W.EstimateTextHeight(text, width, lineHeight)
end

---------------------------------------------------------------------------
-- Logica pura: scelte dropdown, colori, validazione descrittori
---------------------------------------------------------------------------
-- Normalizza i valori di un dropdown in { {value=, label=}, ... }.
-- Accetta: array di scalari, array di {value=,label=} / {v, l}, mappa valore -> etichetta (ordinata per etichetta), o funzione che ritorna uno di questi.
function W.NormalizeChoices(values)
    if type(values) == "function" then
        local ok, r = pcall(values)
        values = ok and r or nil
    end
    local out = {}
    if type(values) ~= "table" then return out end
    if #values > 0 then
        for _, v in ipairs(values) do
            if type(v) == "table" then
                local value = v.value
                if value == nil then value = v[1] end
                local label = v.label
                if label == nil then label = v.text end -- formato del builder storico "select"
                if label == nil then label = v[2] end
                if value ~= nil then out[#out + 1] = { value = value, label = tostring(label ~= nil and label or value) } end
            elseif v ~= nil then
                out[#out + 1] = { value = v, label = tostring(v) }
            end
        end
    else
        for value, label in pairs(values) do
            out[#out + 1] = { value = value, label = tostring(label) }
        end
        table.sort(out, function(a, b)
            if a.label ~= b.label then return a.label < b.label end
            return tostring(a.value) < tostring(b.value)
        end)
    end
    return out
end

local function clamp01(n)
    n = tonumber(n)
    if not n or n ~= n then return nil end
    return math.max(0, math.min(1, n))
end

-- Accetta tabella {r,g,b,a} / {r=,g=,b=,a=} oppure stringa esadecimale "RRGGBB" / "AARRGGBB". Ritorna r,g,b,a (default bianco opaco).
function W.ParseColor(v)
    if type(v) == "table" then
        local r, g, b, a = clamp01(v.r or v[1]), clamp01(v.g or v[2]), clamp01(v.b or v[3]), clamp01(v.a or v[4])
        if r and g and b then return r, g, b, a or 1 end
    elseif type(v) == "string" then
        local hex = v:gsub("^#", "")
        if hex:match("^%x%x%x%x%x%x$") then
            return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1
        elseif hex:match("^%x%x%x%x%x%x%x%x$") then
            return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255, tonumber(hex:sub(1, 2), 16) / 255
        end
    end
    return 1, 1, 1, 1
end

local function hasAccess(opt)
    return type(opt.path) == "string" or (type(opt.get) == "function" and type(opt.set) == "function")
end

-- Valida un descrittore. Ritorna true oppure false, messaggio.
function W.Validate(opt, module)
    if type(opt) ~= "table" then return false, "descrittore non valido (" .. type(opt) .. ")" end
    local t = opt.type
    if type(t) ~= "string" then return false, "campo 'type' mancante" end
    if t == "header" or t == "separator" or t == "label" then return true end
    if t == "execute" then
        if type(opt.func) ~= "function" then return false, "'" .. tostring(opt.label) .. "': func mancante" end
        return true
    end
    if t == "list" then
        if type(opt.items) ~= "function" and type(opt.items) ~= "table" then return false, "list: 'items' mancante" end
        return true
    end
    if t == "toggle" or t == "range" or t == "text" or t == "color" or t == "dropdown" or t == "select" then
        local name = tostring(opt.label or opt.path or t)
        if not hasAccess(opt) and not (type(opt.get) == "function" and not module) then
            if not (module and type(opt.path) == "string") then return false, "'" .. name .. "': servono path oppure get+set" end
        end
        if t == "range" and not (tonumber(opt.min) and tonumber(opt.max) and tonumber(opt.min) < tonumber(opt.max)) then
            return false, "'" .. name .. "': min/max non validi"
        end
        if (t == "dropdown" or t == "select") and type(opt.values) ~= "table" and type(opt.values) ~= "function" then
            return false, "'" .. name .. "': values mancante"
        end
        return true
    end
    return true -- tipi custom: li valida il loro builder
end

-- Etichetta ricercabile di un descrittore (nil se non ne ha).
function W.OptionLabel(opt)
    if type(opt) ~= "table" then return nil end
    if type(opt.label) == "string" and opt.label ~= "" then return opt.label end
    return nil
end

---------------------------------------------------------------------------
-- Accesso ai dati
---------------------------------------------------------------------------
local function getter(module, opt)
    if type(opt.get) == "function" then return opt.get end
    if module and type(opt.path) == "string" then return function() return module:Get(opt.path) end end
    return function() end
end

local function setter(module, opt)
    if type(opt.set) == "function" then return opt.set end
    if module and type(opt.path) == "string" then return function(v) module:Set(opt.path, v) end end
    return function() end
end

local function label(opt) return tostring(opt.label or "") end

---------------------------------------------------------------------------
-- Tooltip / stato disabilitato (comuni a tutti i widget)
---------------------------------------------------------------------------
function W.SetTooltip(w, tip)
    w.badbTooltip = tip
    if tip == nil then return end
    local target = w.badbMain or w
    W.Call(target, "EnableMouse", true)
    local function onEnter(self)
        if not GameTooltip then return end
        local text = W.Eval(tip, nil)
        if type(text) ~= "string" or text == "" then return end
        W.Call(GameTooltip, "SetOwner", self, "ANCHOR_RIGHT")
        W.Call(GameTooltip, "SetText", text, 1, 1, 1, 1, true)
        W.Call(GameTooltip, "Show")
    end
    local function onLeave() if GameTooltip then W.Call(GameTooltip, "Hide") end end
    if target.HookScript then
        target:HookScript("OnEnter", onEnter); target:HookScript("OnLeave", onLeave)
    else
        target:SetScript("OnEnter", onEnter); target:SetScript("OnLeave", onLeave)
    end
end

function W.ApplyDisabled(w, disabled)
    disabled = disabled and true or false
    w.badbDisabled = disabled
    local target = w.badbMain or w
    W.Call(target, disabled and "Disable" or "Enable")
    W.Call(w, "SetAlpha", disabled and 0.5 or 1)
    if type(w.OnDisabledChanged) == "function" then pcall(w.OnDisabledChanged, w, disabled) end
end

---------------------------------------------------------------------------
-- Builder
---------------------------------------------------------------------------
local raw = {}

-- Riga rossa per descrittori errati.
function W.ErrorLabel(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetWidth(WIDTH)
    W.Call(fs, "SetJustifyH", "LEFT")
    fs:SetText("|cff" .. W.hex.err .. tostring(text or "Opzione non valida") .. "|r")
    return fs, 22
end

raw.header = function(parent, _, opt)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(label(opt))
    fs:SetHeight(24)
    return fs, 28
end

raw.toggle = function(parent, module, opt)
    local cb = W.CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local get, set = getter(module, opt), setter(module, opt)
    cb.text = cb.text or cb.Text
    if cb.text then cb.text:SetText(label(opt)) end
    cb.Refresh = function(self) self:SetChecked(get() and true or false) end
    cb:SetScript("OnClick", function(self) W.Safe(set, "toggle " .. label(opt), self:GetChecked() and true or false) end)
    cb:Refresh()
    return cb, 28
end

raw.range = function(parent, module, opt)
    local s = W.CreateFrame("Slider", nil, parent, "MinimalSliderTemplate")
    local get, set = getter(module, opt), setter(module, opt)
    local min, max = tonumber(opt.min), tonumber(opt.max)
    local step = tonumber(opt.step) or 0.01
    local fmt = step >= 1 and "%s: %.0f" or "%s: %.2f"
    s:SetSize(220, 16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    W.Call(s, "SetObeyStepOnDrag", true)
    local lbl = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lbl:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
    local function show(v) lbl:SetFormattedText(fmt, label(opt), v) end
    s.Refresh = function(self)
        local v = tonumber(get()) or min
        self:SetValue(v)
        show(v)
    end
    s:SetScript("OnValueChanged", function(self, v, userInput)
        show(v)
        if userInput then W.Safe(set, "range " .. label(opt), v) end
    end)
    s:Refresh()
    return s, 40, 20, 14
end

raw.execute = function(parent, _, opt)
    local b = W.MakeButton(parent, label(opt), tonumber(opt.width) or 200, 22, function() opt.func() end)
    return b, 30
end

raw.dropdown = function(parent, module, opt)
    local get, set = getter(module, opt), setter(module, opt)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(300, 46)
    local lbl = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label(opt))

    local function choices() return W.NormalizeChoices(opt.values) end
    local function labelOf(value)
        for _, c in ipairs(choices()) do if c.value == value then return c.label end end
        return value ~= nil and tostring(value) or "-"
    end
    function box.SetValue(_, value)
        W.Safe(set, "dropdown " .. label(opt), value)
        box:Refresh()
    end
    box.GetChoices = function() return choices() end

    local dd, tpl = nil, nil
    local ok, f, t = pcall(W.CreateFrame, "DropdownButton", nil, box, "WowStyle1DropdownTemplate")
    if ok and f and t and type(f.SetupMenu) == "function" then dd, tpl = f, t end
    if dd then
        dd:SetPoint("TOPLEFT", 0, -18); dd:SetWidth(220)
        dd:SetupMenu(function(_, root)
            for _, c in ipairs(choices()) do
                root:CreateRadio(c.label, function() return get() == c.value end, function() box:SetValue(c.value) end)
            end
        end)
        box.badbMode = "menu"
        box.Refresh = function() W.Call(dd, "GenerateMenu") end
    else
        -- Fallback senza template dropdown: pulsante che cicla tra i valori.
        dd = W.MakeButton(box, "", 220, 22, function()
            local list = choices()
            if #list == 0 then return end
            local cur = get()
            local idx = 0
            for i, c in ipairs(list) do if c.value == cur then idx = i end end
            box:SetValue(list[idx % #list + 1].value)
        end)
        dd:SetPoint("TOPLEFT", 0, -18)
        box.badbMode = "cycle"
        box.Refresh = function() dd:SetText(labelOf(get())) end
    end
    box.badbMain, box.button = dd, dd
    box:Refresh()
    return box, 46
end

-- "select" (da main, usato da Wizard/Presets): { type="select", path|get/set, label, values = { {value=, text=}, ... } | fn }.
-- Alias compatibile di dropdown.
raw.select = raw.dropdown

raw.text = function(parent, module, opt)
    local get, set = getter(module, opt), setter(module, opt)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(WIDTH - 20, 46)
    local lbl = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label(opt))
    local eb = W.CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    eb:SetSize(tonumber(opt.width) or 240, 22)
    eb:SetPoint("TOPLEFT", 6, -18)
    W.Call(eb, "SetAutoFocus", false)
    W.Call(eb, "SetFontObject", "ChatFontNormal")
    if tonumber(opt.maxLetters) then W.Call(eb, "SetMaxLetters", tonumber(opt.maxLetters)) end
    local err = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    err:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    box.err, box.edit, box.badbMain = err, eb, eb

    local function current()
        local v = get()
        return v ~= nil and tostring(v) or ""
    end
    box.Refresh = function()
        eb:SetText(current())
        err:SetText("")
    end
    -- Conferma il testo: applica validazione/conversione, poi set(). Ritorna true se accettato.
    function box.Commit()
        local txt = eb:GetText() or ""
        if txt == current() then err:SetText(""); return true end
        local value = txt
        local message
        if opt.numeric then
            value = tonumber(txt)
            if value == nil then message = "numero non valido" end
        end
        if not message and type(opt.validate) == "function" then
            local ok, valid, conv = pcall(opt.validate, txt)
            if not ok then
                message = "validazione fallita"
                logError("text %s: %s", label(opt), tostring(valid))
            elseif valid == false or valid == nil then
                message = type(conv) == "string" and conv or "valore non valido"
            elseif conv ~= nil then
                value = conv
            end
        end
        if message then
            err:SetText("|cff" .. W.hex.err .. message .. "|r")
            eb:SetText(current())
            return false
        end
        W.Safe(set, "text " .. label(opt), value)
        err:SetText("")
        return true
    end
    eb:SetScript("OnEnterPressed", function(self) box.Commit(); W.Call(self, "ClearFocus") end)
    eb:SetScript("OnEditFocusLost", function() box.Commit() end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(current()); W.Call(self, "ClearFocus") end)
    box:Refresh()
    return box, 46
end

raw.color = function(parent, module, opt)
    local get, set = getter(module, opt), setter(module, opt)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(300, 30)
    local btn = W.CreateFrame("Button", nil, box, "BackdropTemplate")
    btn:SetSize(26, 22); btn:SetPoint("TOPLEFT", 0, -4)
    W.Backdrop(btn, { 0, 0, 0, 1 }, { 0.8, 0.8, 0.8, 1 })
    local sw = btn:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", 2, -2); sw:SetPoint("BOTTOMRIGHT", -2, 2)
    local lbl = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    lbl:SetText(label(opt))
    box.swatch, box.button, box.badbMain = sw, btn, btn

    local function store(r, g, b, a)
        if type(opt.set) == "function" then
            W.Safe(opt.set, "color " .. label(opt), r, g, b, a)
        elseif module and type(opt.path) == "string" then
            module:Set(opt.path, { r = r, g = g, b = b, a = a })
        end
        box:Refresh()
    end
    box.SetColor = function(_, r, g, b, a) store(r, g, b, a or 1) end
    box.Refresh = function()
        local r, g, b, a = W.ParseColor(get())
        W.Call(sw, "SetColorTexture", r, g, b, a)
    end
    btn:SetScript("OnClick", function()
        local r, g, b, a = W.ParseColor(get())
        local ok, e = pcall(function()
            local P = ColorPickerFrame
            if not P then error("ColorPickerFrame non disponibile") end
            local function fromPicker()
                local nr, ng, nb = P:GetColorRGB()
                local na = a
                if opt.hasAlpha and type(P.GetColorAlpha) == "function" then na = P:GetColorAlpha() or a end
                store(nr or r, ng or g, nb or b, na)
            end
            if type(P.SetupColorPickerAndShow) == "function" then
                P:SetupColorPickerAndShow({
                    r = r, g = g, b = b, opacity = a, hasOpacity = opt.hasAlpha and true or false,
                    swatchFunc = fromPicker, opacityFunc = fromPicker,
                    cancelFunc = function() store(r, g, b, a) end,
                })
            else
                P.func, P.opacityFunc, P.cancelFunc = fromPicker, fromPicker, function() store(r, g, b, a) end
                P.hasOpacity, P.opacity = opt.hasAlpha and true or false, a
                P:SetColorRGB(r, g, b)
                P:Show()
            end
        end)
        if not ok then logError("Selettore colore: %s", tostring(e)) end
    end)
    box:Refresh()
    return box, 30
end

raw.label = function(parent, _, opt)
    local width = tonumber(opt.width) or WIDTH
    local fs = parent:CreateFontString(nil, "ARTWORK", opt.small and "GameFontHighlightSmall" or "GameFontHighlight")
    fs:SetWidth(width)
    W.Call(fs, "SetJustifyH", "LEFT")
    W.Call(fs, "SetWordWrap", true)
    local lineH = opt.small and 12 or 14
    local function apply()
        local text = W.Eval(opt.text, nil)
        if text == nil then text = W.Eval(opt.label, "") end
        text = tostring(text)
        fs:SetText(text)
        fs.badbHeight = stringHeight(fs, text, width, lineH) + 6
    end
    fs.Refresh = apply
    apply()
    return fs, fs.badbHeight
end

raw.separator = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(WIDTH, 1)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetAllPoints()
    W.Call(line, "SetColorTexture", 1, 1, 1, 0.12)
    return f, 14, 16, 6
end

-- Lista scorrevole di righe con azioni.
-- opt.items = fn|tabella -> { { text=, detail=, onClick=fn(item), actions={ {label=, func=fn(item), confirm=txt|fn(item), disabled=bool|fn(item), width=n}, ... } }, ... }
raw.list = function(parent, _, opt)
    local ROW = 24
    local viewH = math.max(60, math.min(400, tonumber(opt.height) or 150))
    local box = CreateFrame("Frame", nil, parent)
    local top = 0
    if opt.label then
        local lbl = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 0, 0); lbl:SetText(label(opt))
        top = 20
    end
    box:SetSize(WIDTH, top + viewH + 4)
    local holder = W.CreateFrame("Frame", nil, box, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", 0, -top); holder:SetSize(WIDTH, viewH)
    W.Backdrop(holder, { 0, 0, 0, 0.25 }, { 1, 1, 1, 0.10 })
    local sf, child = W.CreateScrollFrame(holder)
    sf:SetPoint("TOPLEFT", 2, -2); sf:SetPoint("BOTTOMRIGHT", -22, 2)
    child:SetWidth(WIDTH - 28)
    local empty = holder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("CENTER")
    empty:SetText(tostring(opt.empty or "Nessun elemento"))
    box.rows, box.scroll, box.child = {}, sf, child

    local function makeRow(i)
        local row = CreateFrame("Button", nil, child)
        row:SetSize(WIDTH - 28, ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        W.Call(row.bg, "SetColorTexture", 1, 1, 1, i % 2 == 0 and 0.04 or 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", 6, 0); row.text:SetJustifyH("LEFT")
        row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.actionButtons = {}
        return row
    end

    local function runAction(act, item)
        local function go()
            W.Safe(act.func, "azione '" .. tostring(act.label) .. "'", item)
            if not act.noRefresh then box:Refresh() end
        end
        local confirm = W.Eval(type(act.confirm) == "function" and function() return act.confirm(item) end or act.confirm, nil)
        local UI = Badb.ConfigUI
        if type(confirm) == "string" and UI and UI.Confirm then
            UI:Confirm(confirm, go)
        else
            go()
        end
    end

    box.Refresh = function()
        local items = opt.items
        if type(items) == "function" then
            local ok, r = pcall(items)
            if not ok then logError("list %s: %s", label(opt), tostring(r)) end
            items = ok and r or nil
        end
        if type(items) ~= "table" then items = {} end
        local n = math.min(#items, 300)
        for i = 1, n do
            local item = items[i]
            if type(item) ~= "table" then item = { text = tostring(item) } end
            local row = box.rows[i] or makeRow(i)
            box.rows[i] = row
            row.badbItem = item
            row:Show()
            row.text:SetText(tostring(item.text or ""))
            row.detail:SetText(tostring(item.detail or ""))
            row:SetScript("OnClick", function() if type(item.onClick) == "function" then W.Safe(item.onClick, "riga lista", item) end end)
            -- Azioni, ancorate a destra (max 5).
            local acts = type(item.actions) == "table" and item.actions or {}
            local x = -4
            for j = #acts, 1, -1 do
                if j <= 5 and type(acts[j]) == "table" then
                    local act = acts[j]
                    local b = row.actionButtons[j]
                    if not b then
                        b = W.MakeButton(row, "", 60, 18)
                        row.actionButtons[j] = b
                    end
                    local w = tonumber(act.width) or 62
                    b:SetSize(w, 18)
                    b:ClearAllPoints(); b:SetPoint("RIGHT", row, "RIGHT", x, 0)
                    b:SetText(tostring(act.label or "?"))
                    b:Show()
                    b.badbDisabled = W.Eval(type(act.disabled) == "function" and function() return act.disabled(item) end or act.disabled, false) and true or false
                    W.Call(b, b.badbDisabled and "Disable" or "Enable")
                    b:SetScript("OnClick", function()
                        if b.badbDisabled then return end
                        runAction(act, item)
                    end)
                    x = x - w - 2
                end
            end
            for j = #acts + 1, #row.actionButtons do row.actionButtons[j]:Hide() end
            row.detail:ClearAllPoints()
            row.detail:SetPoint("RIGHT", row, "RIGHT", x - 6, 0)
            row.text:SetWidth(math.max(40, WIDTH - 28 + x - 92))
        end
        for i = n + 1, #box.rows do box.rows[i]:Hide() end
        empty:SetShown(n == 0)
        W.SetChildHeight(sf, child, n * ROW)
        box.badbCount = n
    end
    box:Refresh()
    return box, top + viewH + 8
end

-- Wrapper "a prova di errore" di ogni builder ufficiale: mai un errore Lua verso il chiamante.
-- Il wrapper e' pubblico in W.Builders; i grezzi restano in W.Raw (per i test).
W.Raw = raw
for name, fn in pairs(raw) do
    W.Builders[name] = function(parent, module, opt)
        local ok, msg = W.Validate(opt, module)
        if not ok then
            logError("Opzione non valida: %s", tostring(msg))
            return W.ErrorLabel(parent, "Opzione non valida: " .. tostring(msg))
        end
        local okb, w, h, xoff, yoff = pcall(fn, parent, module, opt)
        if not okb then
            logError("Builder %s: %s", name, tostring(w))
            return W.ErrorLabel(parent, "Errore nel widget '" .. name .. "'")
        end
        return w, h, xoff, yoff
    end
end

---------------------------------------------------------------------------
-- Layout verticale
---------------------------------------------------------------------------
-- Costruisce un singolo descrittore. Non lancia mai. Ritorna entry = { w, h, x, y, opt }.
function W:BuildOne(parent, module, opt)
    local t = type(opt) == "table" and opt.type or nil
    local build = t and self.Builders[t]
    local w, h, xoff, yoff
    if build then
        local ok, a, b, c, d = pcall(build, parent, module, opt)
        if ok and a then
            w, h, xoff, yoff = a, b, c, d
        else
            logError("Builder %s: %s", tostring(t), tostring(a))
            w, h = self.ErrorLabel(parent, "Errore nel widget '" .. tostring(t) .. "'")
        end
    else
        local msg = type(opt) ~= "table" and ("descrittore non valido (" .. type(opt) .. ")") or ("tipo sconosciuto '" .. tostring(t) .. "'")
        logError("Opzione non valida: %s", msg)
        w, h = self.ErrorLabel(parent, "Opzione non valida: " .. msg)
    end
    local entry = { w = w, h = tonumber(h) or 28, x = xoff or 16, y = yoff or 0, opt = type(opt) == "table" and opt or {} }
    if type(opt) == "table" then
        if opt.tooltip ~= nil then W.SetTooltip(w, opt.tooltip) end
    end
    return entry
end

-- Costruisce in colonna le opzioni di un modulo (module.options) o di una lista esplicita.
-- Ritorna: altezza totale (da startY), array di widget, gruppo { Refresh(), Layout(), entries }.
function W:Build(parent, module, startY, options)
    if options == nil then options = module and module.options end
    if type(options) ~= "table" then options = {} end
    local group = { entries = {}, startY = startY or 0 }
    local widgets = {}
    for _, opt in ipairs(options) do
        local entry = self:BuildOne(parent, module, opt)
        group.entries[#group.entries + 1] = entry
        widgets[#widgets + 1] = entry.w
    end

    local function state(entry)
        local opt = entry.opt
        entry.hidden = W.Eval(opt.hidden, false) and true or false
        W.ApplyDisabled(entry.w, W.Eval(opt.disabled, false))
    end

    function group:Layout()
        local y = self.startY
        for _, e in ipairs(self.entries) do
            if e.hidden then
                e.w:Hide()
            else
                e.w:Show()
                e.w:ClearAllPoints()
                e.w:SetPoint("TOPLEFT", parent, "TOPLEFT", e.x, -(y + e.y))
                y = y + (tonumber(e.w.badbHeight) or e.h)
            end
        end
        self.height = y
        return y
    end

    function group:Refresh()
        for _, e in ipairs(self.entries) do
            if type(e.w.Refresh) == "function" then W.Safe(e.w.Refresh, "refresh widget", e.w) end
            state(e)
        end
        return self:Layout()
    end

    for _, e in ipairs(group.entries) do state(e) end
    local height = group:Layout()
    return height, widgets, group
end
