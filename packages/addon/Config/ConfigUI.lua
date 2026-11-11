-- BadbUI - ConfigUI v2: finestra principale con sidebar, pagine dei moduli, ricerca e servizi UI.
-- Struttura del file:
--   1. Logica pura (indice pagine, ordinamento, risoluzione, ricerca, coda toast)  -> testata senza disegno
--   2. Servizi: TextBox, Confirm, Toast
--   3. Pagine core (Panoramica, Profili, Moduli, Frame, Informazioni)
--   4. Finestra (sidebar, ricerca, contenuto) e pannello leggero in Settings
-- Le pagine dei moduli sono lette a runtime da Badb.Modules.list[*].page (vedi docs/configui.md).
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local DB, Modules, Compat, W, Events, Logger = Badb.DB, Badb.Modules, Badb.Compat, Badb.Widgets, Badb.Events, Badb.Logger

local UI = { custom = {}, customOrder = {}, actions = {}, pageFrames = {}, sbHeaders = {}, sbButtons = {}, searchRows = {} }
Badb.ConfigUI = UI

UI.CATEGORIES = { L["Gestione"], L["Interfaccia"], L["Gioco"], L["Strumenti"], L["Contenuti"] }
local DEFAULT_CATEGORY = L["Strumenti"]
local FRAME_W, FRAME_H = 880, 600
local MIN_W, MIN_H, MAX_W, MAX_H = 820, 460, 1300, 950
local SIDEBAR_W = 176
local MAX_RESULTS = 30

local function tstr(v, default)
    if type(v) == "string" and v ~= "" then return v end
    return default
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function addSpecial(name)
    for _, n in ipairs(UISpecialFrames) do if n == name then return end end
    tinsert(UISpecialFrames, name)
end

-- Se il primo argomento e' UI (chiamata con i due punti) lo scarta: permette sia UI.X(...) sia UI:X(...).
local function unwrap(a, ...)
    if a == UI then return ... end
    return a, ...
end

-- Stato persistente della finestra: Badb.DB.sv.global.ui (scala, posizione, dimensione, pagina, sezioni aperte).
function UI.State()
    local sv = DB.sv
    if not sv then UI._tmp = UI._tmp or {}; return UI._tmp end
    sv.global = sv.global or {}
    if type(sv.global.ui) ~= "table" then sv.global.ui = {} end
    return sv.global.ui
end

---------------------------------------------------------------------------
-- 1. LOGICA PURA
---------------------------------------------------------------------------
-- Pagine core. `build` e' risolto in UI.corePages (definite piu' sotto).
local CORE = {
    { key = "overview", title = L["Panoramica"], category = L["Gestione"], order = 0,
      keywords = L["stato avvisi azioni recenti scorciatoie home"] },
    { key = "profiles", title = L["Profili"], category = L["Gestione"], order = 10,
      keywords = L["profilo copia rinomina elimina reset importa esporta specializzazione spec"] },
    { key = "modules", title = L["Moduli"], category = L["Gestione"], order = 900,
      keywords = L["moduli attiva disattiva abilita opzioni"] },
    { key = "about", title = L["Informazioni"], category = L["Gestione"], order = 999,
      keywords = L["versione comandi slash scala finestra crediti log"] },
    { key = "frames", title = "Frame", category = L["Interfaccia"], order = 0,
      keywords = L["frame sblocca sposta posizione alpha trasparenza scala visibile ripristina"] },
}
UI.corePages = {}

local function categoryRank(cat)
    for i, c in ipairs(UI.CATEGORIES) do if c == cat then return i end end
    return 100
end

local function pageLess(a, b)
    local ra, rb = categoryRank(a.category), categoryRank(b.category)
    if ra ~= rb then return ra < rb end
    if a.category ~= b.category then return a.category < b.category end
    if a.order ~= b.order then return a.order < b.order end
    local ta, tb = a.title:lower(), b.title:lower()
    if ta ~= tb then return ta < tb end
    return a.key < b.key
end
UI.PageLess = pageLess

local function genericOptionsBuild(name)
    return function(parent, ctx)
        local m = Modules:Get(name)
        local h, _, group = W:Build(parent, m, 8)
        if group then ctx.AddRefresh(function() group:Refresh() end) end
        return h + 16
    end
end

-- Indice di tutte le pagine (core + moduli con `page` + RegisterPage), ordinato per categoria/order/titolo.
-- Rilegge Badb.Modules.list a ogni chiamata: nessuna cache da invalidare.
function UI:CollectPages()
    local list = {}
    for _, c in ipairs(CORE) do
        list[#list + 1] = {
            key = c.key, title = c.title, category = c.category, order = c.order, kind = "core",
            enabled = true, keywords = c.keywords,
            build = function(parent, ctx) return UI.corePages[c.key](parent, ctx) end,
        }
    end
    local order, mlist = Modules.order or {}, Modules.list or {}
    for _, name in ipairs(order) do
        local m = mlist[name]
        local p = type(m) == "table" and m.page
        if type(p) == "table" then
            list[#list + 1] = {
                key = "mod:" .. name, module = name, kind = "module",
                title = tstr(p.title, tstr(m.title, name)),
                category = tstr(p.category, DEFAULT_CATEGORY),
                order = tonumber(p.order) or 100,
                enabled = m.enabled and true or false,
                keywords = type(p.keywords) == "table" and table.concat(p.keywords, " ") or tstr(p.keywords),
                build = type(p.build) == "function" and p.build or genericOptionsBuild(name),
                refresh = type(p.refresh) == "function" and p.refresh or nil,
            }
        end
    end
    for _, key in ipairs(self.customOrder) do
        local p = self.custom[key]
        if p then
            list[#list + 1] = {
                key = key, kind = "custom", enabled = true,
                title = tstr(p.title, key), category = tstr(p.category, DEFAULT_CATEGORY),
                order = tonumber(p.order) or 100,
                keywords = type(p.keywords) == "table" and table.concat(p.keywords, " ") or tstr(p.keywords),
                build = p.build, refresh = type(p.refresh) == "function" and p.refresh or nil,
            }
        end
    end
    table.sort(list, pageLess)
    return list
end

-- Raggruppa le pagine per categoria nell'ordine della sidebar: { {category=, pages={rec,...}}, ... }
function UI:GetSidebarModel()
    local groups, byCat = {}, {}
    for _, rec in ipairs(self:CollectPages()) do
        local g = byCat[rec.category]
        if not g then
            g = { category = rec.category, pages = {} }
            byCat[rec.category] = g
            groups[#groups + 1] = g
        end
        g.pages[#g.pages + 1] = rec
    end
    return groups
end

function UI:FindPage(key)
    if type(key) ~= "string" then return nil end
    for _, rec in ipairs(self:CollectPages()) do
        if rec.key == key then return rec end
    end
end

-- Accetta chiave di pagina, nome modulo o titolo (case-insensitive). Ritorna chiave pagina o nil.
function UI:ResolveKey(arg)
    if type(arg) ~= "string" then return nil end
    arg = strtrim(arg)
    if arg == "" then return nil end
    local pages = self:CollectPages()
    for _, rec in ipairs(pages) do if rec.key == arg then return rec.key end end
    local low = arg:lower()
    for _, rec in ipairs(pages) do
        if rec.key:lower() == low or (rec.module and rec.module:lower() == low) then return rec.key end
    end
    for _, rec in ipairs(pages) do if rec.title:lower() == low then return rec.key end end
    return nil
end

-- Registra una pagina non legata a un modulo. page = { title, order, category, build, refresh }.
function UI:RegisterPage(key, page)
    if type(key) ~= "string" or key == "" then return false, L["chiave non valida"] end
    if type(page) ~= "table" or type(page.build) ~= "function" then return false, L["page.build mancante"] end
    for _, c in ipairs(CORE) do if c.key == key then return false, L["chiave riservata"] end end
    if key:sub(1, 4) == "mod:" then return false, L["prefisso 'mod:' riservato"] end
    if not self.custom[key] then self.customOrder[#self.customOrder + 1] = key end
    self.custom[key] = page
    if self.built then self:RebuildSidebar() end
    return true
end

function UI:UnregisterPage(key)
    if not self.custom[key] then return false end
    self.custom[key] = nil
    for i, k in ipairs(self.customOrder) do if k == key then table.remove(self.customOrder, i); break end end
    self.pageFrames[key] = nil
    if self.built then self:RebuildSidebar() end
    return true
end

-- Ricerca globale: sottostringa case-insensitive su titoli pagina, titoli modulo e label delle `options`.
-- Ritorna { {kind="page"|"module"|"option", key=paginaDaAprire, title=, detail=, module=}, ... } (max 30).
function UI:Search(query)
    local q = strtrim(tostring(query or "")):lower()
    local out = {}
    if q == "" then return out end
    local function has(s) return type(s) == "string" and s:lower():find(q, 1, true) ~= nil end
    local pages = self:CollectPages()
    local pageOfModule = {}
    for _, rec in ipairs(pages) do
        if rec.module then pageOfModule[rec.module] = rec end
        if has(rec.title) or has(rec.keywords) then
            out[#out + 1] = { kind = "page", key = rec.key, title = rec.title, detail = rec.category, module = rec.module }
        end
    end
    local order, mlist = Modules.order or {}, Modules.list or {}
    for _, name in ipairs(order) do
        local m = mlist[name]
        if type(m) == "table" then
            local own = pageOfModule[name]
            if not (own and has(own.title)) and (has(m.title) or has(name)) then
                out[#out + 1] = { kind = "module", key = own and own.key or "modules", title = tstr(m.title, name),
                    detail = L["Modulo"], module = name }
            end
            if type(m.options) == "table" then
                for _, opt in ipairs(m.options) do
                    local label = W.OptionLabel(opt)
                    if label and has(label) then
                        out[#out + 1] = { kind = "option", key = "modules", title = label,
                            detail = L["Moduli > "] .. tstr(m.title, name), module = name }
                    end
                end
            end
        end
    end
    while #out > MAX_RESULTS do out[#out] = nil end
    return out
end

-- Coda dei toast: max `max` visibili, gli altri in attesa; ogni toast scade dopo `duration` secondi.
local TOAST_LEVELS = { info = true, ok = true, warn = true, error = true }
function UI.NewToastQueue(max, duration)
    local q = { max = max or 3, duration = duration or 4, items = {}, pending = {} }
    function q:Push(text, level)
        text = tostring(text or "")
        if text == "" then return nil end
        if #text > 200 then text = text:sub(1, 197) .. "..." end
        if not TOAST_LEVELS[level] then level = "info" end
        for _, it in ipairs(self.items) do
            if it.text == text and it.level == level then it.age = 0; return it end
        end
        local it = { text = text, level = level, age = 0 }
        if #self.items < self.max then
            self.items[#self.items + 1] = it
        else
            self.pending[#self.pending + 1] = it
            if #self.pending > 20 then table.remove(self.pending, 1) end
        end
        return it
    end
    -- Ritorna true se l'insieme dei toast visibili e' cambiato.
    function q:Tick(dt)
        local changed = false
        for i = #self.items, 1, -1 do
            local it = self.items[i]
            it.age = it.age + (tonumber(dt) or 0)
            if it.age >= self.duration then table.remove(self.items, i); changed = true end
        end
        while #self.items < self.max and #self.pending > 0 do
            self.items[#self.items + 1] = table.remove(self.pending, 1)
            changed = true
        end
        return changed
    end
    function q:Count() return #self.items end
    return q
end

-- Ultime azioni (mostrate in Panoramica)
function UI:RecordAction(text)
    if not self.recording then return end -- niente rumore dell'avvio (attivazione moduli al login)
    local a = self.actions
    table.insert(a, 1, { time = date("%H:%M:%S"), text = tostring(text) })
    while #a > 20 do a[#a] = nil end
end

local function moduleTitle(name)
    local m = Modules.list and Modules.list[name]
    return m and m.title or tostring(name)
end

-- Avvisi per la Panoramica: { {level=, text=, actionLabel=, action=fn}, ... }
local diagCache = { at = -100 }
function UI:GetWarnings()
    local out = {}
    if InCombatLockdown and InCombatLockdown() then
        out[#out + 1] = { level = "warn", text = L["In combattimento: alcune modifiche saranno applicate a fine combattimento."] }
    end
    local FM = Badb.FrameManager
    if FM and FM.unlocked then
        out[#out + 1] = { level = "warn", text = L["Frame sbloccati: trascinali e poi bloccali."],
            actionLabel = L["Blocca"], action = function() FM:SetUnlocked(false) end }
    end
    local Wiz = Badb.Wizard
    if Wiz then
        local done
        if type(Wiz.IsCompleted) == "function" then
            local ok, r = pcall(Wiz.IsCompleted, Wiz)
            if ok then done = r end
        elseif DB.sv and DB.sv.global then
            done = DB.sv.global.wizardDone
        end
        if not done then
            out[#out + 1] = { level = "info", text = L["Configurazione guidata non completata."], actionLabel = L["Avvia"],
                action = function()
                    if Wiz.Open then Wiz:Open() elseif Wiz.Start then Wiz:Start(true) end
                end }
        end
    end
    local D = Badb.Diagnostics
    if D and type(D.RunChecks) == "function" then
        local now = type(GetTime) == "function" and GetTime() or 0
        if now - diagCache.at > 10 or now < diagCache.at then
            local ok, res = pcall(D.RunChecks, D)
            diagCache.at, diagCache.res = now, ok and res or nil
        end
        local errors, warns = 0, 0
        for _, c in ipairs(type(diagCache.res) == "table" and diagCache.res or {}) do
            if c.level == "error" then errors = errors + 1 elseif c.level == "warn" then warns = warns + 1 end
        end
        if errors + warns > 0 then
            out[#out + 1] = { level = errors > 0 and "error" or "warn",
                text = string.format(L["Diagnostica: %d errori, %d avvisi."], errors, warns),
                actionLabel = L["Dettagli"], action = function() UI:OpenPage("Diagnostics") end }
        end
    end
    local nerr = 0
    for _, line in ipairs(Logger.buffer or {}) do
        if line:find("ERROR:", 1, true) then nerr = nerr + 1 end
    end
    if nerr > 0 then
        out[#out + 1] = { level = "warn", text = string.format(L["%d errori nel log."], nerr), actionLabel = "Log",
            action = function() UI.TextBox(L["Log BadbUI"], table.concat(Logger.buffer, "\n")) end }
    end
    return out
end

---------------------------------------------------------------------------
-- 2. SERVIZI: TextBox, Confirm, Toast
---------------------------------------------------------------------------
local box
local function ensureTextBox()
    if box then return box end
    local f = W.CreateFrame("Frame", "BadbUITextBox", UIParent, "BasicFrameTemplateWithInset,BackdropTemplate", "BasicFrameTemplateWithInset", "BackdropTemplate")
    f:SetSize(520, 300); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if not f.TitleText then W.Backdrop(f) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    local sf = W.CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -32); sf:SetPoint("BOTTOMRIGHT", -14, 40)
    local edit = sf.EditBox
    if edit then
        edit:SetWidth(470); W.Call(edit, "SetFontObject", ChatFontNormal)
        if sf.CharCount then sf.CharCount:Hide() end
    else
        -- Template assente: ScrollFrame base + EditBox multilinea.
        local sf2 = W.CreateScrollFrame(f)
        sf2:SetPoint("TOPLEFT", 14, -32); sf2:SetPoint("BOTTOMRIGHT", -30, 40)
        edit = CreateFrame("EditBox", nil, sf2)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetWidth(460)
        W.Call(edit, "SetFontObject", ChatFontNormal)
        sf2:SetScrollChild(edit)
    end
    f.edit = edit
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f.ok = W.MakeButton(f, L["Chiudi"], 120, 22)
    f.ok:SetPoint("BOTTOM", 0, 12)
    addSpecial("BadbUITextBox")
    box = f
    UI.textBoxFrame = f
    return f
end

-- Finestra di testo per import/export. Firma storica: TextBox(title, text, onAccept?) (con . o :).
function UI.TextBox(...)
    local title, text, onAccept, label = unwrap(...)
    local ok, err = pcall(function()
        local f = ensureTextBox()
        text = tostring(text or "")
        if #text > 500000 then text = text:sub(1, 500000) end
        f.title:SetText(tostring(title or ""))
        f.edit:SetText(text)
        W.Call(f.edit, "HighlightText")
        W.Call(f.edit, "SetFocus")
        f.ok:SetText(label or (onAccept and L["Importa"] or L["Chiudi"]))
        f.ok:SetScript("OnClick", function()
            if type(onAccept) == "function" then W.Safe(onAccept, "TextBox", f.edit:GetText()) end
            f:Hide()
        end)
        f:Show()
    end)
    if not ok then Logger:Error("TextBox: %s", tostring(err)) end
end

-- Conferma modale con coda (mai StaticPopup: nessun rischio di taint).
local confirmFrame, confirmCur
local confirmQueue = {}
UI.confirmQueue = confirmQueue

local function confirmFinish(result)
    local it = confirmCur
    if not it then return end
    confirmCur = nil
    confirmFrame:Hide()
    local cb = result and it.onYes or it.onNo
    if type(cb) == "function" then W.Safe(cb, "Confirm") end
    local nxt = table.remove(confirmQueue, 1)
    if nxt then UI.ShowConfirm(nxt) end
end

function UI.ShowConfirm(it)
    if not confirmFrame then
        local f = W.CreateFrame("Frame", "BadbUIConfirm", UIParent, "BackdropTemplate")
        f:SetSize(380, 140); f:SetPoint("CENTER", 0, 60); f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        W.Backdrop(f)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 20, -20); f.text:SetPoint("TOPRIGHT", -20, -20)
        f.text:SetJustifyH("CENTER"); W.Call(f.text, "SetWordWrap", true)
        f.yes = W.MakeButton(f, L["Conferma"], 120, 24, function() confirmFinish(true) end)
        f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
        f.no = W.MakeButton(f, L["Annulla"], 120, 24, function() confirmFinish(false) end)
        f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
        -- ESC: UISpecialFrames nasconde il frame -> equivale ad Annulla.
        f:SetScript("OnHide", function() if confirmCur then confirmFinish(false) end end)
        addSpecial("BadbUIConfirm")
        confirmFrame = f
        UI.confirmFrame = f
    end
    confirmCur = it
    confirmFrame.text:SetText(it.text)
    confirmFrame:Show()
end

function UI.Confirm(...)
    local text, onYes, onNo = unwrap(...)
    local ok, err = pcall(function()
        local it = { text = tostring(text or ""), onYes = onYes, onNo = onNo }
        if confirmCur then
            if #confirmQueue < 10 then confirmQueue[#confirmQueue + 1] = it end
        else
            UI.ShowConfirm(it)
        end
    end)
    if not ok then Logger:Error("Confirm: %s", tostring(err)); return false end
    return true
end

-- Toast non invasivi
UI.toasts = UI.NewToastQueue(3, 4)
local TOAST_COLORS = {
    info = { 0.25, 0.65, 1 }, ok = { 0.37, 0.82, 0.41 }, warn = { 1, 0.8, 0 }, error = { 1, 0.31, 0.31 },
}
UI.toastFrames = {}

function UI:RenderToasts()
    local items = self.toasts.items
    for i, it in ipairs(items) do
        local f = self.toastFrames[i]
        if not f then
            f = W.CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            f:SetSize(340, 30); f:SetFrameStrata("FULLSCREEN_DIALOG")
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            f.text:SetPoint("LEFT", 10, 0); f.text:SetPoint("RIGHT", -10, 0)
            f.text:SetJustifyH("LEFT")
            self.toastFrames[i] = f
        end
        local c = TOAST_COLORS[it.level] or TOAST_COLORS.info
        W.Backdrop(f, { 0.05, 0.06, 0.08, 0.92 }, { c[1], c[2], c[3], 0.9 })
        f.text:SetText(it.text)
        f.badbLevel = it.level
        f:ClearAllPoints(); f:SetPoint("TOP", UIParent, "TOP", 0, -90 - (i - 1) * 36)
        f:SetAlpha(clamp((self.toasts.duration - it.age) / 0.5, 0, 1))
        f:Show()
    end
    for i = #items + 1, #self.toastFrames do self.toastFrames[i]:Hide() end
end

function UI.Toast(...)
    local text, level = unwrap(...)
    local ok, err = pcall(function()
        if not UI.toasts:Push(text, level) then return end
        UI:RenderToasts()
        if not UI.toastDriver then UI.toastDriver = CreateFrame("Frame") end
        UI.toastDriver:SetScript("OnUpdate", function(_, dt)
            if UI.toasts:Tick(dt) then UI:RenderToasts() end
            if UI.toasts:Count() == 0 then UI.toastDriver:SetScript("OnUpdate", nil) end
        end)
    end)
    if not ok then Logger:Error("Toast: %s", tostring(err)) end
end

---------------------------------------------------------------------------
-- Helper di disegno
---------------------------------------------------------------------------
local Stack = {}
Stack.__index = Stack
local function newStack(parent, ctx) return setmetatable({ parent = parent, y = 8, ctx = ctx }, Stack) end
function Stack:Add(frame, h, x, yoff)
    frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x or 16, -(self.y + (yoff or 0)))
    self.y = self.y + (h or 0)
    return frame
end
function Stack:Gap(n) self.y = self.y + (n or 8) end
function Stack:Text(text, template, h, x, width)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetWidth(width or W.width); fs:SetJustifyH("LEFT")
    W.Call(fs, "SetWordWrap", true)
    fs:SetText(text or "")
    return self:Add(fs, h or 18, x)
end
function Stack:Header(text) return self:Text(text, "GameFontNormalLarge", 30) end
function Stack:Buttons(specs, width, perRow)
    width, perRow = width or 130, perRow or 4
    local out = {}
    for i, s in ipairs(specs) do
        local col = (i - 1) % perRow
        local b = W.MakeButton(self.parent, s[1], s.width or width, 22, s[2])
        b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 16 + col * ((s.width or width) + 8), -self.y)
        out[#out + 1] = b
        if col == perRow - 1 or i == #specs then self.y = self.y + 30 end
    end
    return out
end
function Stack:Widgets(options, module)
    local h, _, group = W:Build(self.parent, module, self.y, options)
    self.y = h
    if self.ctx and group then self.ctx.AddRefresh(function() group:Refresh() end) end
    return group
end

local function errorBox(parent, title, msg)
    local f = W.CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(W.width, 90)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -12)
    W.Backdrop(f, { 0.25, 0.05, 0.05, 0.9 }, { 1, 0.3, 0.3, 0.9 })
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -8); t:SetText("|cffff5050" .. tostring(title) .. "|r")
    local m = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m:SetPoint("TOPLEFT", 10, -28); m:SetWidth(W.width - 20); m:SetJustifyH("LEFT")
    msg = tostring(msg or "")
    if #msg > 600 then msg = msg:sub(1, 600) .. "..." end
    m:SetText(msg)
    local h = 40 + W.EstimateTextHeight(msg, W.width - 20, 12)
    f:SetHeight(h)
    f.title, f.message = t, m
    return f, h + 24
end
UI.ErrorBox = errorBox

local function setModuleEnabled(name, value)
    local ok, err = pcall(Modules.SetEnabled, Modules, name, value)
    if not ok then Logger:Error(L["Modulo %s: %s"], tostring(name), tostring(err)) end
end

---------------------------------------------------------------------------
-- 3. PAGINE CORE
---------------------------------------------------------------------------
local P = UI.corePages

-- Panoramica -------------------------------------------------------------
local function moduleRows()
    local rows = {}
    for _, name in ipairs(Modules.order or {}) do
        local m = Modules.list[name]
        if m then
            local on = m.enabled and true or false
            local acts = { { label = on and L["Disattiva"] or L["Attiva"], width = 70, func = function() setModuleEnabled(name, not on) end } }
            if type(m.page) == "table" then
                acts[#acts + 1] = { label = L["Apri"], width = 50, func = function() UI:OpenPage(name) end, noRefresh = true }
            end
            rows[#rows + 1] = { text = tstr(m.title, name), actions = acts,
                detail = on and L["|cff5fd068attivo|r"] or L["|cff888888disattivo|r"] }
        end
    end
    return rows
end

P.overview = function(parent, ctx)
    local S = newStack(parent, ctx)
    S:Text("BadbUI  |cff888888v" .. tostring(Badb.version) .. "|r", "GameFontHighlightHuge", 36)
    S:Text(L["Gestione completa dell'interfaccia di WoW: Forever."], "GameFontDisable", 24)
    S:Widgets({ { type = "label", text = function()
        local total, on = 0, 0
        for _, name in ipairs(Modules.order or {}) do
            total = total + 1
            if Modules.list[name] and Modules.list[name].enabled then on = on + 1 end
        end
        return string.format(L["Profilo attivo: |cff3fa7ff%s|r\nModuli attivi: %d di %d"], tostring(DB:GetProfileName()), on, total)
    end } })
    S:Gap(6)
    S:Header(L["Scorciatoie"])
    local shortcuts = {}
    for _, rec in ipairs(UI:CollectPages()) do
        if rec.kind == "module" and #shortcuts < 9 then
            shortcuts[#shortcuts + 1] = { rec.title, function() UI:Open(rec.key) end }
        end
    end
    shortcuts[#shortcuts + 1] = { L["Profili"], function() UI:Open("profiles") end }
    shortcuts[#shortcuts + 1] = { "Frame", function() UI:Open("frames") end }
    S:Buttons(shortcuts, 170, 3)
    S:Gap(6)
    S:Header(L["Avvisi"])
    S:Widgets({ { type = "list", height = 96, empty = L["Nessun avviso"], items = function()
        local rows = {}
        for _, w in ipairs(UI:GetWarnings()) do
            local c = ({ error = "ff5050", warn = "ffcc00", info = "3fa7ff" })[w.level] or "ffffff"
            local acts = w.action and { { label = w.actionLabel or L["Apri"], width = 70, func = w.action } } or nil
            rows[#rows + 1] = { text = "|cff" .. c .. w.text .. "|r", actions = acts }
        end
        return rows
    end } })
    S:Header(L["Moduli"])
    S:Widgets({ { type = "list", height = 170, items = moduleRows } })
    S:Header(L["Ultime azioni"])
    S:Widgets({ { type = "list", height = 110, empty = L["Nessuna azione recente"], items = function()
        local rows = {}
        for _, a in ipairs(UI.actions) do rows[#rows + 1] = { text = "|cff888888" .. a.time .. "|r  " .. a.text } end
        return rows
    end } })
    return S.y + 16
end

-- Profili ----------------------------------------------------------------
local function uniqueProfileName(base)
    local name, n = base, 1
    while DB.sv.profiles[name] do n = n + 1; name = base .. " (" .. n .. ")" end
    return name
end

local function notify(ok, err, okText)
    if ok then
        UI:Toast(okText, "ok")
    else
        UI:Toast(tostring(err or L["operazione non riuscita"]), "error")
    end
    UI:Refresh()
end

-- Wrapper storici: la logica (validazione nomi, riallineamento personaggi/spec) vive in DB.
function UI:RenameProfile(old, new) return DB:RenameProfile(old, new) end

function UI:CopyProfile(src, name) return DB:CopyProfile(src, name) end

function UI:ImportProfileString(str)
    local name = uniqueProfileName(L["Importato "] .. date("%Y-%m-%d %H:%M"))
    local ok, err = DB:ImportProfile(str, name)
    if ok then DB:SetProfile(name) end
    return ok, err, name
end

local function profileRows()
    local rows, active = {}, DB:GetProfileName()
    for _, name in ipairs(DB:ListProfiles()) do
        local isActive = name == active
        rows[#rows + 1] = {
            text = name, detail = isActive and L["|cff3fa7ffattivo|r"] or "",
            actions = {
                { label = L["Attiva"], width = 54, disabled = isActive, func = function() DB:SetProfile(name) end },
                { label = L["Copia"], width = 48, func = function()
                    UI.TextBox(L["Nome della copia di '"] .. name .. "'", "", function(txt)
                        local ok, res = UI:CopyProfile(name, txt)
                        notify(ok, res, L["Profilo copiato"])
                    end)
                end },
                { label = L["Rinomina"], width = 62, func = function()
                    UI.TextBox(L["Nuovo nome per '"] .. name .. "'", name, function(txt)
                        local ok, err = UI:RenameProfile(name, txt)
                        notify(ok, err, L["Profilo rinominato"])
                    end)
                end },
                { label = L["Esporta"], width = 54, noRefresh = true, func = function()
                    UI.TextBox(L["Esporta profilo '"] .. name .. "'", DB:ExportProfile(name))
                end },
                { label = L["Elimina"], width = 54, disabled = isActive,
                  confirm = L["Eliminare il profilo '"] .. name .. L["'? L'operazione non e' reversibile."],
                  func = function()
                      local ok, err = DB:DeleteProfile(name)
                      notify(ok, err, L["Profilo eliminato"])
                  end },
            },
        }
    end
    return rows
end

local function specCount()
    if type(GetNumSpecializations) == "function" then
        local ok, n = pcall(GetNumSpecializations)
        if ok and tonumber(n) and n > 0 then return n end
    end
    return 2
end

local function specName(i)
    if type(GetSpecializationInfo) == "function" then
        local ok, _, name = pcall(GetSpecializationInfo, i)
        if ok and type(name) == "string" then return name end
    end
    return L["Specializzazione "] .. i
end

P.profiles = function(parent, ctx)
    local S = newStack(parent, ctx)
    S:Header(L["Profili"])
    S:Widgets({ { type = "label", text = function()
        return L["Profilo attivo: |cff3fa7ff"] .. tostring(DB:GetProfileName()) .. "|r"
    end } })
    S:Widgets({ { type = "list", height = 190, empty = L["Nessun profilo"], items = profileRows } })
    S:Buttons({
        { L["Nuovo / Copia"], function()
            UI.TextBox(L["Nome del nuovo profilo (copia dell'attivo)"], "", function(name)
                local ok, res = UI:CopyProfile(DB:GetProfileName(), name)
                if ok then DB:SetProfile(res) end
                local err = not ok and res or nil
                notify(ok, err, L["Profilo creato"])
            end)
        end },
        { L["Esporta attivo"], function() UI.TextBox(L["Esporta profilo"], DB:ExportProfile()) end },
        { L["Importa"], function()
            -- Pagina Import / Export con anteprima; fallback alla finestra di testo se assente.
            local IO = Badb.ImportExport
            if IO and IO:OpenImport() then return end
            UI.TextBox(L["Incolla la stringa BadbUI"], "", function(str)
                local ok, err = UI:ImportProfileString(str)
                if not ok then Logger:Error(L["Import fallito: %s"], tostring(err)) end
                notify(ok, err, L["Profilo importato"])
            end)
        end },
        { "Reset", function()
            UI:Confirm(L["Reimpostare il profilo '"] .. tostring(DB:GetProfileName()) .. L["' ai valori predefiniti?"], function()
                DB:ResetProfile()
                notify(true, nil, L["Profilo reimpostato"])
            end)
        end },
    }, 128, 4)
    S:Gap(8)
    S:Header(L["Profilo per specializzazione"])
    S:Text(L["Il profilo scelto viene attivato automaticamente al cambio di specializzazione."], "GameFontDisableSmall", 18)
    local specs = {}
    for i = 1, specCount() do
        specs[#specs + 1] = {
            type = "dropdown", label = specName(i),
            values = function()
                local v = { { value = "", label = "(nessuno)" } }
                for _, n in ipairs(DB:ListProfiles()) do v[#v + 1] = { value = n, label = n } end
                return v
            end,
            get = function()
                local map = DB.sv.specProfiles and DB.sv.specProfiles[DB.char]
                return map and map[i] or ""
            end,
            set = function(v) DB:SetSpecProfile(i, v ~= "" and v or nil) end,
        }
    end
    S:Widgets(specs)
    return S.y + 16
end

-- Moduli -----------------------------------------------------------------
P.modules = function(parent, ctx)
    local sections, order = {}, {}
    local state = UI.State()
    state.expanded = type(state.expanded) == "table" and state.expanded or {}
    UI.moduleSections = sections

    local function layout()
        local y = 8
        for _, name in ipairs(order) do
            local s = sections[name]
            s.header:ClearAllPoints(); s.header:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
            y = y + 30
            if s.expanded then
                if not s.body then
                    s.body = CreateFrame("Frame", nil, parent)
                    s.body:SetSize(W.width, 1)
                    local m = Modules:Get(name)
                    local h, _, group = W:Build(s.body, m, 4)
                    s.group, s.bodyH = group, h + 8
                    s.body:SetHeight(s.bodyH)
                end
                s.body:ClearAllPoints(); s.body:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
                s.body:Show()
                y = y + s.bodyH + 6
            elseif s.body then
                s.body:Hide()
            end
            s.arrow:SetText(s.expanded and "-" or "+")
        end
        ctx.Resize(y + 16)
    end

    for _, name in ipairs(Modules.order or {}) do
        local m = Modules.list[name]
        if m then
            order[#order + 1] = name
            local s = { expanded = state.expanded[name] and true or false }
            sections[name] = s
            local h = W.CreateFrame("Button", nil, parent, "BackdropTemplate")
            h:SetSize(W.width, 26)
            W.Backdrop(h, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.10 })
            s.header = h
            s.arrow = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            s.arrow:SetPoint("LEFT", 8, 0)
            local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            title:SetPoint("LEFT", 26, 0)
            title:SetText(tstr(m.title, name) .. "  |cff888888" .. tostring(m.category or "") .. "|r")
            function s.SetExpanded(_, v)
                s.expanded = v and true or false
                state.expanded[name] = s.expanded or nil
                layout()
            end
            h:SetScript("OnClick", function() s:SetExpanded(not s.expanded) end)
            local right = -6
            if type(m.page) == "table" then
                local open = W.MakeButton(h, L["Pagina"], 56, 20, function() UI:OpenPage(name) end)
                open:SetPoint("RIGHT", h, "RIGHT", right, 0)
                right = right - 62
            end
            local cb = W.CreateFrame("CheckButton", nil, h, "UICheckButtonTemplate")
            cb:SetSize(24, 24); cb:SetPoint("RIGHT", h, "RIGHT", right, 0)
            local cbText = cb.text or cb.Text
            if cbText then cbText:SetText(L["Attivo"]); cbText:ClearAllPoints(); cbText:SetPoint("RIGHT", cb, "LEFT", -2, 0) end
            cb:SetScript("OnClick", function(self) setModuleEnabled(name, self:GetChecked() and true or false) end)
            s.check = cb
        end
    end

    ctx.AddRefresh(function()
        for _, name in ipairs(order) do
            local s, m = sections[name], Modules.list[name]
            s.check:SetChecked(m.enabled and true or false)
            if s.group then s.group:Refresh() end
        end
        -- Apertura mirata (ricerca / UI:OpenPage su modulo senza pagina).
        local focus = UI.pendingFocus
        if focus and sections[focus] then
            UI.pendingFocus = nil
            if not sections[focus].expanded then sections[focus]:SetExpanded(true) end
        end
    end)
    layout()
    return nil -- l'altezza e' gestita da ctx.Resize
end

-- Frame ------------------------------------------------------------------
local function resolveFrame(desc)
    if type(desc.frame) == "table" then return desc.frame end
    return type(desc.frame) == "string" and _G[desc.frame] or nil
end

local function frameConf(key)
    local f = DB.profile and DB.profile.frames
    return f and f[key] or {}
end

local function miniSlider(row, x, width, min, max, step, get, set, fmt)
    local s = W.CreateFrame("Slider", nil, row, "MinimalSliderTemplate")
    s:SetSize(width, 14); s:SetPoint("LEFT", row, "LEFT", x, -4)
    s:SetMinMaxValues(min, max); s:SetValueStep(step); W.Call(s, "SetObeyStepOnDrag", true)
    local val = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    val:SetPoint("BOTTOM", s, "TOP", 0, 1)
    s.Refresh = function(self)
        local v = tonumber(get()) or max
        self:SetValue(v); val:SetFormattedText(fmt, v)
    end
    s:SetScript("OnValueChanged", function(_, v, user)
        val:SetFormattedText(fmt, v)
        if user then W.Safe(set, "frame slider", v) end
    end)
    s:Refresh()
    return s
end

P.frames = function(parent, ctx)
    local FM = Badb.FrameManager
    local S = newStack(parent, ctx)
    S:Header("Frame")
    if not FM then
        S:Text(L["FrameManager non disponibile."], "GameFontDisable", 20)
        return S.y + 16
    end
    local status = S:Text("", "GameFontHighlight", 22)
    local btn = S:Buttons({ { L["Sblocca frame"], function()
        local ok, err = pcall(FM.SetUnlocked, FM, not FM.unlocked)
        if not ok then Logger:Error(L["Sblocco frame: %s"], tostring(err)) end
        UI:Refresh()
    end, width = 150 } })[1]
    ctx.AddRefresh(function()
        status:SetText(FM.unlocked and L["|cffffcc00Frame sbloccati: trascina per spostare, tasto destro per ripristinare.|r"]
            or L["Frame bloccati."])
        btn:SetText(FM.unlocked and L["Blocca frame"] or L["Sblocca frame"])
    end)
    S:Gap(4)

    local byCat, cats = {}, {}
    for key, desc in pairs(FM.registry or {}) do
        local c = tstr(desc.category, L["Altro"])
        if not byCat[c] then byCat[c] = {}; cats[#cats + 1] = c end
        byCat[c][#byCat[c] + 1] = { key = key, desc = desc }
    end
    table.sort(cats)
    if #cats == 0 then S:Text(L["Nessun frame registrato."], "GameFontDisable", 20) end
    for _, c in ipairs(cats) do
        table.sort(byCat[c], function(a, b)
            local ta, tb = tostring(a.desc.title or a.key):lower(), tostring(b.desc.title or b.key):lower()
            if ta ~= tb then return ta < tb end
            return a.key < b.key
        end)
        S:Text(c, "GameFontNormal", 24)
        for _, item in ipairs(byCat[c]) do
            local key, desc = item.key, item.desc
            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(W.width, 34)
            S:Add(row, 36)
            local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            name:SetPoint("LEFT", 4, 0); name:SetWidth(140); name:SetJustifyH("LEFT")
            name:SetText(tostring(desc.title or key))
            local f = resolveFrame(desc)
            local editMode = f and Compat.IsEditModeFrame(f)
            local refreshers = {}
            if desc.hideable then
                local cb = W.CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                cb:SetSize(24, 24); cb:SetPoint("LEFT", row, "LEFT", 146, 0)
                local t = cb.text or cb.Text
                if t then t:SetText(L["Visibile"]) end
                cb:SetScript("OnClick", function(self)
                    local vis = self:GetChecked() and true or false
                    W.Safe(function()
                        if vis then
                            FM:SetOption(key, "hidden", nil)
                            local fr = resolveFrame(desc)
                            if fr and desc.original and desc.original.shown then
                                Events:RunOutOfCombat("show:" .. key, function() fr:Show() end)
                            end
                        else
                            FM:SetOption(key, "hidden", true)
                        end
                    end, L["Frame visibile"])
                end)
                refreshers[#refreshers + 1] = function() cb:SetChecked(not frameConf(key).hidden) end
                row.visible = cb
            end
            if desc.alphable ~= false then
                row.alpha = miniSlider(row, 270, 100, 0.1, 1, 0.05,
                    function() return frameConf(key).alpha or 1 end,
                    function(v) FM:SetOption(key, "alpha", v) end, "Alpha %.2f")
                refreshers[#refreshers + 1] = function() row.alpha:Refresh() end
            end
            if desc.scalable and not editMode then
                row.scale = miniSlider(row, 385, 80, 0.5, 2, 0.05,
                    function() return frameConf(key).scale or 1 end,
                    function(v) FM:SetOption(key, "scale", v) end, L["Scala %.2f"])
                refreshers[#refreshers + 1] = function() row.scale:Refresh() end
            end
            local rb = W.MakeButton(row, L["Ripristina"], 66, 20, function()
                FM:Restore(key)
                UI:Refresh()
            end)
            rb:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.restore = rb
            ctx.AddRefresh(function() for _, fn in ipairs(refreshers) do fn() end end)
        end
    end
    return S.y + 16
end

-- Informazioni -----------------------------------------------------------
function UI:SetScale(s)
    s = clamp(math.floor((tonumber(s) or 1) * 20 + 0.5) / 20, 0.6, 1.5)
    UI.State().scale = s
    if self.frame then self.frame:SetScale(s) end
    return s
end

function UI:ResetWindow()
    local st = UI.State()
    st.point, st.relPoint, st.x, st.y, st.width, st.height, st.scale = nil, nil, nil, nil, nil, nil, nil
    if self.frame then
        local f = self.frame
        f:SetScale(1); f:SetSize(FRAME_W, FRAME_H)
        f:ClearAllPoints(); f:SetPoint("CENTER")
    end
end

P.about = function(parent, ctx)
    local S = newStack(parent, ctx)
    S:Header("BadbUI")
    local build = ""
    if type(GetBuildInfo) == "function" then
        local ok, v, b = pcall(GetBuildInfo)
        if ok then build = string.format("Client %s (build %s, interface %s)", tostring(v), tostring(b), tostring(Compat.interface)) end
    end
    S:Text(L["Versione "] .. tostring(Badb.version) .. "\n" .. build .. L["\nAutore: Nikoemme"], "GameFontHighlight", 52)
    S:Gap(4)
    S:Header(L["Finestra"])
    local scaleLabel = S:Text("", "GameFontHighlight", 22)
    ctx.AddRefresh(function() scaleLabel:SetText(string.format(L["Scala: %.2f"], UI.State().scale or 1)) end)
    S:Buttons({
        { L["Riduci scala"], function() UI:SetScale((UI.State().scale or 1) - 0.05); UI:Refresh() end },
        { L["Aumenta scala"], function() UI:SetScale((UI.State().scale or 1) + 0.05); UI:Refresh() end },
        { L["Reimposta finestra"], function() UI:ResetWindow(); UI:Refresh() end, width = 150 },
        { L["Mostra log"], function() UI.TextBox(L["Log BadbUI"], table.concat(Logger.buffer, "\n")) end },
    }, 130, 4)
    S:Gap(6)
    S:Header(L["Comandi  /badb  /bui"])
    S:Widgets({ { type = "label", small = true, text = function()
        local lines = {}
        local Slash = Badb.Slash
        for _, c in ipairs(Slash and Slash:List() or {}) do
            lines[#lines + 1] = "|cff3fa7ff" .. (c.name == "" and "(vuoto)" or c.name) .. "|r  " .. tostring(c.help or "")
        end
        return table.concat(lines, "\n")
    end } })
    return S.y + 16
end

---------------------------------------------------------------------------
-- 4. FINESTRA
---------------------------------------------------------------------------
local function buildDisabledNotice(container, rec)
    local fs = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, -16); fs:SetWidth(W.width); fs:SetJustifyH("LEFT")
    fs:SetText(L["Il modulo |cffffd100"] .. moduleTitle(rec.module) .. L["|r e' disattivato.\nAttivalo per usare questa pagina."])
    local b = W.MakeButton(container, L["Attiva modulo"], 140, 24, function() setModuleEnabled(rec.module, true) end)
    b:SetPoint("TOPLEFT", 16, -64)
    return 110
end

local function newContainer(self)
    local c = CreateFrame("Frame", nil, self.content)
    c:SetSize(W.width + 40, 100)
    c:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
    c:Hide()
    return c
end

-- Costruisce una pagina in modo isolato: un errore in build produce un box errore, mai un crash della shell.
local function buildPage(self, rec)
    local entry = { rec = rec, refreshers = {}, height = 100, enabledAtBuild = rec.enabled }
    entry.container = newContainer(self)
    local function resize(h)
        h = clamp(tonumber(h) or 100, 40, 20000)
        entry.height = h
        entry.container:SetHeight(h)
        if self.current == rec.key then self:ApplyContentHeight(h) end
    end
    local ctx = {
        UI = UI, W = W, theme = Badb.Theme, key = rec.key, module = rec.module and Modules:Get(rec.module) or nil,
        AddRefresh = function(fn) if type(fn) == "function" then entry.refreshers[#entry.refreshers + 1] = fn end end,
        Resize = resize,
    }
    if rec.enabled == false then
        resize(buildDisabledNotice(entry.container, rec))
    elseif type(rec.build) ~= "function" then
        local f, h = errorBox(entry.container, L["Pagina non valida"], L["build mancante"])
        entry.failed, entry.errorFrame = true, f
        resize(h)
    else
        local ok, h = pcall(rec.build, entry.container, ctx)
        if not ok then
            Logger:Error(L["Pagina '%s': %s"], rec.title, tostring(h))
            entry.container:Hide()
            entry.container = newContainer(self) -- scarta i widget a meta' costruiti
            entry.refreshers = {}
            local f, eh = errorBox(entry.container, L["Errore nella pagina '"] .. rec.title .. "'", h)
            entry.failed, entry.errorFrame, entry.buildError = true, f, tostring(h)
            resize(eh)
        else
            if h ~= nil then resize(h) end
            if rec.refresh then
                entry.refreshers[#entry.refreshers + 1] = function() rec.refresh(ctx) end
            end
        end
    end
    return entry
end

function UI:ApplyContentHeight(h)
    if not self.content then return end
    self.content:SetHeight(math.max(1, h + 20))
    W.Call(self.scroll, "UpdateScrollChildRect")
end

function UI:RefreshPage(key)
    local entry = self.pageFrames[key]
    if not entry then return end
    local err
    for _, fn in ipairs(entry.refreshers) do
        local ok, e = pcall(fn)
        if not ok then err = tostring(e) end
    end
    if err then
        if entry.lastErr ~= err then Logger:Error(L["Pagina '%s' refresh: %s"], entry.rec.title, err) end
    end
    entry.lastErr = err
    if self.current == key and self.refreshError then
        self.refreshError:SetText(err and (L["|cffff5050Errore nel refresh: "] .. err:sub(1, 120) .. "|r") or "")
    end
end

function UI:SelectPage(key)
    if not self.built then return false end
    local rec = self:FindPage(key) or self:FindPage("overview")
    local prev = self.current and self.pageFrames[self.current]
    if prev then prev.container:Hide() end
    local entry = self.pageFrames[rec.key]
    if entry and entry.enabledAtBuild ~= rec.enabled then
        entry.container:Hide()
        entry = nil
    end
    if not entry then
        entry = buildPage(self, rec)
        self.pageFrames[rec.key] = entry
    end
    entry.rec = rec
    entry.container:Show()
    self.current = rec.key
    UI.State().page = rec.key
    self:ApplyContentHeight(entry.height)
    W.Call(self.scroll, "SetVerticalScroll", 0)
    self.pageTitle:SetText("|cff888888" .. rec.category .. "  >|r  " .. rec.title)
    self:RefreshPage(rec.key)
    self:UpdateSidebarSelection()
    return true
end

-- Sidebar ----------------------------------------------------------------
function UI:UpdateSidebarSelection()
    for _, b in ipairs(self.sbButtons) do
        if b:IsShown() then b.sel:SetShown(b.key == self.current) end
    end
end

function UI:RebuildSidebar()
    if not self.built then return end
    local child = self.sidebarChild
    local y, hi, bi = 4, 0, 0
    for _, g in ipairs(self:GetSidebarModel()) do
        hi = hi + 1
        local h = self.sbHeaders[hi]
        if not h then
            h = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            self.sbHeaders[hi] = h
        end
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -y)
        h:SetText(g.category:upper()); h:Show()
        y = y + 18
        for _, rec in ipairs(g.pages) do
            bi = bi + 1
            local b = self.sbButtons[bi]
            if not b then
                b = CreateFrame("Button", nil, child)
                b:SetSize(SIDEBAR_W - 8, 22)
                b.sel = b:CreateTexture(nil, "BACKGROUND")
                b.sel:SetAllPoints(); W.Call(b.sel, "SetColorTexture", 0.25, 0.65, 1, 0.25)
                b.hl = b:CreateTexture(nil, "HIGHLIGHT")
                b.hl:SetAllPoints(); W.Call(b.hl, "SetColorTexture", 1, 1, 1, 0.08)
                b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                b.label:SetPoint("LEFT", 12, 0); b.label:SetJustifyH("LEFT")
                b:SetScript("OnClick", function(btn) UI:SelectPage(btn.key) end)
                self.sbButtons[bi] = b
            end
            b.key, b.disabledModule = rec.key, rec.enabled == false
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
            b.label:SetText(rec.enabled == false and ("|cff777777" .. rec.title .. "|r") or rec.title)
            b:Show()
            y = y + 23
        end
        y = y + 8
    end
    for i = hi + 1, #self.sbHeaders do self.sbHeaders[i]:Hide() end
    for i = bi + 1, #self.sbButtons do self.sbButtons[i]:Hide() end
    child:SetHeight(y + 4)
    W.Call(self.sidebarScroll, "UpdateScrollChildRect")
    self:UpdateSidebarSelection()
end

-- Ricerca ----------------------------------------------------------------
function UI:UpdateSearch(text)
    if not self.built then return end
    local results = self:Search(text)
    self.searchResults = results
    local shown = math.min(#results, 8)
    for i = 1, shown do
        local r = results[i]
        local row = self.searchRows[i]
        if not row then
            row = CreateFrame("Button", nil, self.searchPanel)
            row:SetSize(300, 22)
            row:SetPoint("TOPLEFT", self.searchPanel, "TOPLEFT", 4, -4 - (i - 1) * 22)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints(); W.Call(row.hl, "SetColorTexture", 1, 1, 1, 0.10)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 6, 0); row.text:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(self2)
                local res = self2.result
                if res then UI:OpenResult(res) end
            end)
            self.searchRows[i] = row
        end
        row.result = r
        row.text:SetText(r.title .. "  |cff888888" .. tostring(r.detail or "") .. "|r")
        row:Show()
    end
    for i = shown + 1, #self.searchRows do self.searchRows[i]:Hide(); self.searchRows[i].result = nil end
    self.searchPanel:SetHeight(shown * 22 + 8)
    self.searchPanel:SetShown(shown > 0)
end

function UI:OpenResult(r)
    if r.kind == "option" or (r.kind == "module" and r.key == "modules") then UI.pendingFocus = r.module end
    self:ClearSearch()
    self:Open(r.key)
end

function UI:ClearSearch()
    if not self.built then return end
    self.searchBox:SetText("")
    W.Call(self.searchBox, "ClearFocus")
    self.searchResults = {}
    for _, row in ipairs(self.searchRows) do row:Hide(); row.result = nil end
    self.searchPanel:Hide()
end

-- Finestra principale ----------------------------------------------------
local function saveGeometry(f)
    local st = UI.State()
    local ok, point, _, relPoint, x, y = pcall(f.GetPoint, f, 1)
    if ok and point then st.point, st.relPoint, st.x, st.y = point, relPoint, x, y end
    local w, h = tonumber(f:GetWidth()), tonumber(f:GetHeight())
    if w and h and w >= MIN_W and h >= MIN_H then st.width, st.height = w, h end
end

function UI:Create()
    if self.built then return self.frame end
    local st = UI.State()
    local f = W.CreateFrame("Frame", "BadbUIConfigFrame", UIParent, "BasicFrameTemplateWithInset,BackdropTemplate", "BasicFrameTemplateWithInset", "BackdropTemplate")
    self.frame = f
    f:SetFrameStrata("HIGH")
    f:SetSize(clamp(tonumber(st.width) or FRAME_W, MIN_W, MAX_W), clamp(tonumber(st.height) or FRAME_H, MIN_H, MAX_H))
    f:SetScale(clamp(tonumber(st.scale) or 1, 0.6, 1.5))
    if st.point then
        f:SetPoint(st.point, UIParent, st.relPoint or st.point, tonumber(st.x) or 0, tonumber(st.y) or 0)
    else
        f:SetPoint("CENTER")
    end
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    W.Call(f, "SetClampedToScreen", true)
    W.Call(f, "SetResizable", true)
    if not W.Call(f, "SetResizeBounds", MIN_W, MIN_H, MAX_W, MAX_H) then W.Call(f, "SetMinResize", MIN_W, MIN_H) end
    f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
    f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing(); saveGeometry(self2) end)
    f:SetScript("OnHide", function(self2) saveGeometry(self2) end)
    if not f.TitleText then
        W.Backdrop(f)
        local close = W.MakeButton(f, "X", 24, 22, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -8) end
    title:SetText("BadbUI  |cff888888v" .. tostring(Badb.version) .. "|r")
    addSpecial("BadbUIConfigFrame")

    -- Ricerca (in alto)
    local sb, tpl = W.CreateFrame("EditBox", "BadbUIConfigSearch", f, "SearchBoxTemplate", "InputBoxTemplate")
    sb:SetSize(240, 22); sb:SetPoint("TOPLEFT", 16, -34)
    W.Call(sb, "SetAutoFocus", false)
    if not tpl or tpl == "InputBoxTemplate" then W.Call(sb, "SetTextInsets", 6, 6, 0, 0) end
    self.searchBox = sb
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", sb, "RIGHT", 10, 0)
    hint:SetText(L["Cerca pagine e opzioni"])
    local panel = W.CreateFrame("Frame", nil, f, "BackdropTemplate")
    panel:SetSize(308, 8); panel:SetPoint("TOPLEFT", sb, "BOTTOMLEFT", 0, -2)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    W.Backdrop(panel, { 0.05, 0.06, 0.08, 0.98 }, { 0.25, 0.65, 1, 0.8 })
    panel:Hide()
    self.searchPanel = panel
    sb:SetScript("OnTextChanged", function(self2) UI:UpdateSearch(self2:GetText() or "") end)
    sb:SetScript("OnEscapePressed", function() UI:ClearSearch() end)
    sb:SetScript("OnEnterPressed", function()
        local r = UI.searchResults and UI.searchResults[1]
        if r then UI:OpenResult(r) end
    end)

    -- Sidebar
    local side = W.CreateFrame("Frame", nil, f, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 12, -64); side:SetPoint("BOTTOMLEFT", 12, 12); side:SetWidth(SIDEBAR_W)
    W.Backdrop(side, { 0, 0, 0, 0.30 }, { 1, 1, 1, 0.08 })
    local ssf, schild = W.CreateScrollFrame(side)
    ssf:SetPoint("TOPLEFT", 2, -2); ssf:SetPoint("BOTTOMRIGHT", -2, 2)
    schild:SetWidth(SIDEBAR_W - 8)
    self.sidebar, self.sidebarScroll, self.sidebarChild = side, ssf, schild

    -- Contenuto
    self.pageTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.pageTitle:SetPoint("TOPLEFT", side, "TOPRIGHT", 14, -4)
    self.refreshError = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.refreshError:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -70)
    self.refreshError:SetWidth(360); self.refreshError:SetJustifyH("RIGHT")
    local sf, content = W.CreateScrollFrame(f)
    sf:SetPoint("TOPLEFT", side, "TOPRIGHT", 8, -30); sf:SetPoint("BOTTOMRIGHT", -30, 12)
    content:SetSize(W.width + 40, 1)
    self.scroll, self.content = sf, content

    -- Maniglia di ridimensionamento
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel((tonumber(f:GetFrameLevel()) or 1) + 10)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    W.Call(gt, "SetTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); saveGeometry(f) end)
    self.grip = grip

    self.built = true
    return f
end

-- Apre la finestra. pageKey = chiave pagina, nome modulo o titolo; senza argomento riapre l'ultima pagina.
function UI:Open(pageKey)
    if self ~= UI then pageKey, self = self, UI end -- supporta anche UI.Open(pageKey)
    local ok, err = pcall(function()
        self:Create()
        self:RebuildSidebar()
        self.frame:Show()
        local key = self:ResolveKey(pageKey)
        if not key and pageKey ~= nil and type(pageKey) == "string" and pageKey ~= "" then
            -- nome modulo senza pagina: apre Moduli con la sezione espansa
            if Modules.list and Modules.list[pageKey] then UI.pendingFocus = pageKey; key = "modules" end
        end
        key = key or self:ResolveKey(UI.State().page) or (self:FindPage("home") and "home") or "overview"
        self:SelectPage(key)
    end)
    if not ok then Logger:Error("ConfigUI: %s", tostring(err)); return false end
    return true
end

function UI.Close()
    if UI.built then UI.frame:Hide() end
end

function UI.Toggle()
    if UI.built and UI.frame:IsShown() then UI:Close() else UI:Open() end
end

-- Apre la pagina di un modulo (o, se non ne ha, la sua sezione in Moduli). Ritorna true se aperto.
function UI:OpenPage(moduleName)
    if self ~= UI then moduleName, self = self, UI end
    if type(moduleName) ~= "string" then return false end
    if not (Modules.list and Modules.list[moduleName]) then return false end
    if type(Modules.list[moduleName].page) ~= "table" then UI.pendingFocus = moduleName end
    return self:Open(moduleName)
end

function UI.Refresh()
    if not UI.built then return end
    if UI.frame:IsShown() then UI:RebuildSidebar() end
    if UI.current then UI:RefreshPage(UI.current) end
end

-- Refresh coalescato (per eventi frequenti come BADB_OPTION_CHANGED).
function UI.QueueRefresh()
    if not UI.built or not UI.frame:IsShown() then return end
    if not UI.refreshDriver then UI.refreshDriver = CreateFrame("Frame") end
    UI.refreshDriver:SetScript("OnUpdate", function(drv)
        drv:SetScript("OnUpdate", nil)
        UI:Refresh()
    end)
end

---------------------------------------------------------------------------
-- Eventi e pannello leggero in Settings
---------------------------------------------------------------------------
Events:On(UI, "BADB_PROFILE_CHANGED", function(_, name)
    UI:RecordAction(L["Profilo attivo: "] .. tostring(name))
    UI:Refresh()
end)
Events:On(UI, "BADB_MODULE_ENABLED", function(_, name)
    UI:RecordAction(L["Modulo attivato: "] .. moduleTitle(name))
    UI:Refresh()
end)
Events:On(UI, "BADB_MODULE_DISABLED", function(_, name)
    UI:RecordAction(L["Modulo disattivato: "] .. moduleTitle(name))
    UI:Refresh()
end)
Events:On(UI, "PLAYER_ENTERING_WORLD", function() UI.recording = true end)
Events:On(UI, "BADB_OPTION_CHANGED", function() UI:QueueRefresh() end)
Events:On(UI, "BADB_UNLOCK_CHANGED", function(_, state)
    UI:RecordAction(state and L["Frame sbloccati"] or L["Frame bloccati"])
    UI:Refresh()
end)
Events:On(UI, "BADB_PRESET_APPLIED", function(_, key) UI:RecordAction(L["Preset applicato: "] .. tostring(key)); UI:Refresh() end)
Events:On(UI, "BADB_PRESET_UNDONE", function(_, key) UI:RecordAction(L["Preset annullato: "] .. tostring(key)); UI:Refresh() end)
Events:On(UI, "BADB_BACKUP_CREATED", function(_, id) UI:RecordAction(L["Backup creato: "] .. tostring(id)); UI:Refresh() end)
Events:On(UI, "BADB_BACKUP_RESTORED", function(_, id) UI:RecordAction(L["Backup ripristinato: "] .. tostring(id)); UI:Refresh() end)
Events:On(UI, "BADB_INTEGRATION_APPLIED", function(_, id) UI:RecordAction(L["Integrazione applicata: "] .. tostring(id)) end)
Events:On(UI, "PLAYER_REGEN_DISABLED", function() UI:QueueRefresh() end)
Events:On(UI, "PLAYER_REGEN_ENABLED", function() UI:QueueRefresh() end)

-- Pannello leggero registrato in Opzioni > AddOns: solo un pulsante per aprire la finestra.
local panel = CreateFrame("Frame")
panel:Hide()
UI.panel = panel
do
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("BadbUI")
    local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    d:SetPoint("TOPLEFT", 16, -52); d:SetWidth(520); d:SetJustifyH("LEFT")
    d:SetText(L["Tutta la configurazione e' nella finestra BadbUI (comando /badb)."])
    local b = W.MakeButton(panel, L["Apri BadbUI"], 160, 26, function() UI:Open() end)
    b:SetPoint("TOPLEFT", 16, -90)
    panel.openButton = b
end
Compat.RegisterOptionsPanel(panel, "BadbUI")

-- Native child categories make Blizzard display the expandable + beside BadbUI.
UI.settingsPanels = {}
function UI:RegisterSettingsShortcuts()
    if not panel.settingsCategory or #self.settingsPanels > 0 then return end
    if not (Settings and type(Settings.RegisterCanvasLayoutSubcategory) == "function") then return end
    local shortcuts = {
        { title = "Control panel", page = "home", button = "Open BadbUI" },
        { title = "Macro catalog", page = "Macros" },
        { title = "Profiles", page = "profiles" },
        { title = "Help", page = "help" },
    }
    for _, shortcut in ipairs(shortcuts) do
        local child = CreateFrame("Frame")
        child:Hide()
        local heading = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        heading:SetPoint("TOPLEFT", 16, -16); heading:SetText(shortcut.title)
        local description = child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        description:SetPoint("TOPLEFT", 16, -52); description:SetWidth(520); description:SetJustifyH("LEFT")
        description:SetText("Open this section in BadbUI. You can also use /badb at any time.")
        local button = W.MakeButton(child, shortcut.button or ("Open " .. shortcut.title), 200, 26, function()
            if SettingsPanel and SettingsPanel.Hide then SettingsPanel:Hide() end
            if shortcut.page == "help" and Badb.Help then Badb.Help:Open("start")
            else UI:OpenPage(shortcut.page) end
        end)
        button:SetPoint("TOPLEFT", 16, -90)
        child.openButton, child.pageKey = button, shortcut.page
        Compat.RegisterOptionsPanel(child, shortcut.title, panel.settingsCategory)
        self.settingsPanels[#self.settingsPanels + 1] = child
    end
end
UI:RegisterSettingsShortcuts()
