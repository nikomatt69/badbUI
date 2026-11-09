-- BadbUI - Pagina "Import / Export" della ConfigUI.
-- Tutta l'interfaccia (opzioni dei moduli, frame, layout Edit Mode) in UNA stringa BADB1,
-- oppure le sole opzioni di un modulo. Ogni import passa da un'anteprima: niente viene
-- applicato finche' l'utente non sceglie un'azione (e la sostituzione chiede conferma).
--
-- Logica pura in Badb.ImportExport (testabile senza UI):
--   IO:Export(kind, target)       -> stringa | nil, errore      kind = "profile" | "module"
--   IO:Analyze(str)               -> analisi { ok, error, info, actions = { new, replace, module } }
--   IO:Apply(action, str, name)   -> ok, risultato | errore     action = "new" | "replace" | "module"
--   IO:DefaultName()              -> nome libero "Importato AAAA-MM-GG HH.MM[ (n)]"
local _, ns = ...
local Badb = ns.Badb
local DB, Modules, W, Logger = Badb.DB, Badb.Modules, Badb.Widgets, Badb.Logger
local UI = Badb.ConfigUI

local IO = { state = { kind = "profile", target = nil, text = "", analysis = nil, name = nil } }
Badb.ImportExport = IO

local MAX_INPUT = 500000 -- oltre questa lunghezza la stringa non e' un export BadbUI plausibile

---------------------------------------------------------------------------
-- Logica pura
---------------------------------------------------------------------------
function IO:DefaultName()
    local base = "Importato " .. date("%Y-%m-%d %H.%M")
    local name, n = base, 1
    while DB:ProfileExists(name) do n = n + 1; name = base .. " (" .. n .. ")" end
    return name
end

function IO:Export(kind, target)
    if kind == "module" then
        if type(target) ~= "string" or not Modules:Get(target) then return nil, "scegli un modulo" end
        return DB:ExportModule(target)
    end
    target = target or DB:GetProfileName()
    if not DB:ProfileExists(target) then return nil, "profilo inesistente: " .. tostring(target) end
    return DB:ExportProfile(target)
end

local function moduleTitle(name)
    local m = Modules:Get(name)
    return m and m.title or name
end

function IO:Analyze(str)
    local a = { ok = false, actions = {} }
    if type(str) ~= "string" or str:gsub("%s", "") == "" then
        a.error = "Incolla una stringa di export BadbUI."
        a.empty = true
        return a
    end
    if #str > MAX_INPUT then
        a.error = "Testo troppo lungo per essere un export BadbUI."
        return a
    end
    local info, err = DB:PreviewImport(str)
    if not info then
        a.error = tostring(err)
        return a
    end
    a.ok, a.info = true, info
    if info.kind == "profile" then
        a.actions.new, a.actions.replace = true, true
    elseif #info.modules == 1 then
        a.actions.module = true
    else
        a.ok = false
        a.error = "Il modulo '" .. tostring(info.unknown[1]) .. "' non e' installato."
    end
    return a
end

-- Testo leggibile dell'analisi (usato dalla pagina e dai test).
function IO:Describe(a)
    if not a then return "Incolla una stringa e premi Analizza. Niente viene applicato prima della tua scelta." end
    if not a.ok then return "|cffff5555" .. tostring(a.error) .. "|r" end
    local info = a.info
    local lines = {}
    if info.kind == "profile" then
        lines[#lines + 1] = "|cff55dd77Profilo completo valido|r  (creato con BadbUI " .. tostring(info.addon or "?") .. ")"
        local titles = {}
        for _, n in ipairs(info.modules) do titles[#titles + 1] = moduleTitle(n) end
        lines[#lines + 1] = "Moduli: " .. (#titles > 0 and table.concat(titles, ", ") or "nessuno")
        lines[#lines + 1] = "Frame configurati: " .. info.frames .. "   Layout Edit Mode: " .. (info.hasLayout and "incluso" or "non incluso")
        if #info.unknown > 0 then
            lines[#lines + 1] = "|cffffcc00Ignorati (moduli non installati): " .. table.concat(info.unknown, ", ") .. "|r"
        end
    else
        lines[#lines + 1] = "|cff55dd77Opzioni del modulo '" .. moduleTitle(info.modules[1]) .. "'|r  (BadbUI " .. tostring(info.addon or "?") .. ")"
        lines[#lines + 1] = "Sovrascrive solo le opzioni di questo modulo nel profilo attivo."
    end
    return table.concat(lines, "\n")
end

function IO:Apply(action, str, name)
    local a = self:Analyze(str)
    if not a.ok then return false, a.error end
    if not a.actions[action] then return false, "azione non disponibile per questa stringa" end
    if action == "new" then
        local ok, res = DB:ImportProfile(str, name or self:DefaultName())
        if ok then DB:SetProfile(res) end
        return ok, res
    elseif action == "replace" then
        local ok, err = DB:ImportIntoActive(str)
        return ok, ok and DB:GetProfileName() or err
    elseif action == "module" then
        return DB:ImportModule(str)
    end
    return false, "azione sconosciuta"
end

---------------------------------------------------------------------------
-- Pagina
---------------------------------------------------------------------------
local function toast(text, level)
    if UI and UI.Toast then UI:Toast(text, level) end
end

local function sourceChoices()
    local v = {}
    if IO.state.kind == "module" then
        for _, n in ipairs(Modules.order) do v[#v + 1] = { value = n, label = moduleTitle(n) } end
    else
        for _, n in ipairs(DB:ListProfiles()) do v[#v + 1] = { value = n, label = n } end
    end
    return v
end

local function currentSource()
    local s = IO.state
    if s.kind == "module" then
        if not (s.target and Modules:Get(s.target)) then s.target = Modules.order[1] end
    elseif not DB:ProfileExists(s.target) then
        s.target = DB:GetProfileName()
    end
    return s.target
end

-- Area di testo multilinea con scroll (template se presente, altrimenti frame base).
local function textArea(parent, width, height)
    local holder = W.CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width, height)
    W.Backdrop(holder)
    local sf = W.CreateScrollFrame(holder)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, sf)
    W.Call(edit, "SetMultiLine", true)
    W.Call(edit, "SetAutoFocus", false)
    W.Call(edit, "SetMaxLetters", MAX_INPUT)
    W.Call(edit, "SetFontObject", ChatFontNormal)
    edit:SetWidth(width - 40)
    W.Call(sf, "SetScrollChild", edit)
    edit:SetScript("OnEscapePressed", function(self) W.Call(self, "ClearFocus") end)
    holder:SetScript("OnMouseDown", function() W.Call(edit, "SetFocus") end)
    holder.edit = edit
    return holder
end

function IO:BuildPage(parent, ctx)
    local s = self.state
    local x, y, width = 16, 8, W.width - 16

    local function text(str, template, h)
        local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        W.Call(fs, "SetWidth", width)
        W.Call(fs, "SetJustifyH", "LEFT")
        fs:SetText(str)
        y = y + (h or 20)
        return fs
    end

    text("Import / Export", "GameFontNormalLarge", 28)
    text("Tutta la tua interfaccia in una stringa: opzioni dei moduli, frame e layout Edit Mode. "
        .. "Incollala su un altro personaggio o condividila.", "GameFontDisableSmall", 30)

    -- Esporta
    text("Esporta", "GameFontNormal", 22)
    local h, _, group = W:Build(parent, nil, y, {
        { type = "dropdown", label = "Contenuto", values = {
            { value = "profile", label = "Profilo completo" },
            { value = "module", label = "Opzioni di un modulo" } },
          get = function() return s.kind end,
          set = function(v) s.kind = v; s.target = nil; if self.group then self.group:Refresh() end end },
        { type = "dropdown", label = "Da", values = sourceChoices, get = currentSource,
          set = function(v) s.target = v end },
    })
    self.group = group
    y = y + h + 4

    local exportBtn = W.MakeButton(parent, "Genera stringa", 140, 24, function() self:DoExport() end)
    exportBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    hint:SetText("La stringa viene selezionata: copiala con Ctrl+C.")
    y = y + 34

    -- Area di testo condivisa
    local area = textArea(parent, width, 150)
    area:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    self.area = area
    area.edit:SetScript("OnTextChanged", function(e, userInput)
        if userInput then
            s.text = e:GetText() or ""
            s.analysis = nil
            self:RefreshPreview()
        end
    end)
    y = y + 158

    -- Importa
    text("Importa", "GameFontNormal", 22)
    local analyze = W.MakeButton(parent, "Analizza", 110, 24, function() self:DoAnalyze() end)
    analyze:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local clear = W.MakeButton(parent, "Svuota", 90, 24, function()
        s.text, s.analysis = "", nil
        area.edit:SetText("")
        W.Call(area.edit, "SetFocus")
        self:RefreshPreview()
    end)
    clear:SetPoint("LEFT", analyze, "RIGHT", 8, 0)
    y = y + 32

    self.preview = text("", "GameFontHighlightSmall", 64)
    W.Call(self.preview, "SetJustifyV", "TOP")
    W.Call(self.preview, "SetHeight", 60)

    local nh, _, ngroup = W:Build(parent, nil, y, {
        { type = "text", label = "Nome del nuovo profilo", width = 260, maxLetters = DB.MAX_NAME,
          get = function() return s.name or "" end,
          set = function(v) s.name = v end,
          validate = function(v)
              local n, err = DB.NormalizeName(v)
              if not n then return false, err end
              if DB:ProfileExists(n) then return false, "esiste gia' un profilo con questo nome" end
              return true, n
          end,
          hidden = function() return not (s.analysis and s.analysis.actions.new) end },
    })
    self.nameGroup = ngroup
    y = y + math.max(nh, 44) + 4

    self.btnNew = W.MakeButton(parent, "Importa come nuovo profilo", 210, 24, function() self:DoApply("new") end)
    self.btnNew:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    self.btnReplace = W.MakeButton(parent, "Sostituisci profilo attivo", 190, 24, function() self:DoApply("replace") end)
    self.btnReplace:SetPoint("LEFT", self.btnNew, "RIGHT", 8, 0)
    self.btnModule = W.MakeButton(parent, "Importa nel profilo attivo", 200, 24, function() self:DoApply("module") end)
    self.btnModule:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    y = y + 36

    if ctx and ctx.AddRefresh then ctx.AddRefresh(function() self:Refresh() end) end
    self.built = true
    self:RefreshPreview()
    return y
end

function IO:DoExport()
    local s = self.state
    local str, err = self:Export(s.kind, currentSource())
    if not str then toast("Export non riuscito: " .. tostring(err), "error"); return end
    s.text, s.analysis = str, nil
    if self.area then
        self.area.edit:SetText(str)
        W.Call(self.area.edit, "SetFocus")
        W.Call(self.area.edit, "HighlightText")
    end
    self:RefreshPreview(string.format("Stringa generata (%d caratteri). Il checksum fa rifiutare copie incomplete.", #str))
    toast("Stringa di export pronta", "ok")
end

function IO:DoAnalyze()
    local s = self.state
    if self.area then s.text = self.area.edit:GetText() or "" end
    s.analysis = self:Analyze(s.text)
    if s.analysis.actions.new then
        local valid = DB.NormalizeName(s.name or "")
        if not valid or DB:ProfileExists(valid) then s.name = self:DefaultName() end
    end
    self:RefreshPreview()
end

local function finish(ok, res, okText)
    if ok then
        toast(okText, "ok")
        IO.state.text, IO.state.analysis, IO.state.name = "", nil, nil
        if IO.area then IO.area.edit:SetText("") end
    else
        toast("Import non riuscito: " .. tostring(res), "error")
        Logger:Warn("Import non riuscito: %s", tostring(res))
    end
    IO:RefreshPreview()
    if UI and UI.Refresh then UI:Refresh() end
end

function IO:DoApply(action)
    local s = self.state
    if self.area then s.text = self.area.edit:GetText() or "" end
    if action == "replace" then
        UI:Confirm("Sostituire TUTTO il profilo attivo '" .. tostring(DB:GetProfileName())
            .. "' con la stringa importata? Non si puo' annullare: esporta prima il profilo se vuoi una copia.", function()
            local ok, res = self:Apply("replace", s.text)
            finish(ok, res, "Profilo attivo sostituito")
        end)
        return
    end
    local ok, res = self:Apply(action, s.text, s.name)
    if action == "new" then
        finish(ok, res, "Profilo '" .. tostring(res) .. "' importato e attivato")
    else
        finish(ok, res, "Opzioni di '" .. moduleTitle(tostring(res)) .. "' importate")
    end
end

function IO:RefreshPreview(message)
    if not self.built then return end
    local a = self.state.analysis
    self.preview:SetText(message or self:Describe(a))
    local acts = a and a.ok and a.actions or {}
    self.btnNew:SetShown(not acts.module)
    self.btnReplace:SetShown(not acts.module)
    self.btnModule:SetShown(acts.module and true or false)
    W.ApplyDisabled(self.btnNew, not acts.new)
    W.ApplyDisabled(self.btnReplace, not acts.replace)
    W.ApplyDisabled(self.btnModule, not acts.module)
    if self.nameGroup then self.nameGroup:Refresh() end
end

function IO:Refresh()
    if not self.built then return end
    if self.group then self.group:Refresh() end
    self:RefreshPreview()
end

-- Apre la pagina gia' pronta per un import (usato da Profili e da /badb import).
function IO:OpenImport()
    if not UI:Open("io") then return false end
    if self.area then W.Call(self.area.edit, "SetFocus") end
    return true
end

function IO:OpenExport(kind, target)
    self.state.kind, self.state.target = kind or "profile", target
    if not UI:Open("io") then return false end
    if self.group then self.group:Refresh() end
    self:DoExport()
    return true
end

UI:RegisterPage("io", {
    title = "Import / Export", category = "Gestione", order = 20,
    keywords = { "import", "export", "condividi", "stringa", "backup", "copia" },
    build = function(parent, ctx) return IO:BuildPage(parent, ctx) end,
})

-- /badb import apre la pagina pronta per incollare (export resta il comando base).
if Badb.Slash and type(Badb.Slash.Register) == "function" then
    Badb.Slash:Register("import", function() IO:OpenImport() end, "apre Import / Export per incollare una stringa")
    Badb.Slash:Register("io", function() UI:Open("io") end, "apre la pagina Import / Export")
end
