-- BadbUI - Editor degli script (finestra del design system): elenco a sinistra, codice a destra.
-- Tutta la logica e' in Badb.Scripts (testabile senza UI): qui solo lettura/scrittura dei campi.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local UI, Logger = Badb.UI, Badb.Logger

local Editor = { current = nil }
Badb.ScriptEditor = Editor

local TEMPLATE = L[ [[-- Script BadbUI. Hai a disposizione: Badb (tutta l'API), script.on, script.after, script.every,
-- script.data (si salva), script.log e print. Esempio:
script.on("PLAYER_LEVEL_UP", function(event, level)
    script.data.lastLevel = level
    print("Livello " .. level .. "!")
end)
]] ]

local function scripts() return Badb.Scripts end

local function triggerItems()
    local out = {}
    for _, t in ipairs(scripts().TRIGGER_CHOICES) do out[#out + 1] = { value = t.value, text = t.label } end
    return out
end

function Editor:Build()
    local w = UI:Window("BadbUIScriptEditor", 880, 580, L["Script"], { subtitle = L["Lua con l'API di BadbUI"], sidebar = 220, footer = true })
    self.win = w
    self.nav = UI:NavList(w.sidebar, {}, function(id, byUser) if byUser then Editor:Select(id) end end) -- solo il click: Refresh richiama nav:Select
    self.nav:SetPoint("TOPLEFT", 0, -8); self.nav:SetPoint("BOTTOMRIGHT", 0, 8)

    local body = w.body
    self.fields = { trigger = "manual", enabled = false }
    UI:Label(body, L["Nome"], "small", "textDim"):SetPoint("TOPLEFT", 8, -8)
    self.nameBox = UI:EditBox(body, 230, 26, { maxLetters = 40, placeholder = L["nome dello script"] })
    self.nameBox:SetPoint("TOPLEFT", 8, -26)
    UI:Label(body, L["Quando"], "small", "textDim"):SetPoint("TOPLEFT", 252, -8)
    self.trigger = UI:Dropdown(body, nil, triggerItems(), function() return Editor.fields.trigger end,
        function(v) Editor.fields.trigger = v end, { width = 220 })
    self.trigger:SetPoint("TOPLEFT", 252, -26)
    UI:Label(body, L["Evento / secondi"], "small", "textDim"):SetPoint("TOPLEFT", 484, -8)
    self.param = UI:EditBox(body, 190, 26, { maxLetters = 60, placeholder = L["PLAYER_LEVEL_UP o 5"] })
    self.param:SetPoint("TOPLEFT", 484, -26)
    self.enabled = UI:Toggle(body, L["Attivo"], function() return Editor.fields.enabled end,
        function(v) Editor.fields.enabled = v end, { width = 160 })
    self.enabled:SetPoint("TOPLEFT", 690, -26)

    self.code = UI:EditBox(body, 600, 380, { multiline = true, mono = true, maxLetters = 60000, placeholder = L["-- codice Lua"] })
    self.code:SetPoint("TOPLEFT", 8, -64); self.code:SetPoint("BOTTOMRIGHT", -8, 34)
    self.status = UI:Label(body, "", "small", "textDim")
    self.status:SetPoint("BOTTOMLEFT", 8, 10)

    local f = w.footer
    local function btn(text, width, fn, variant, x)
        local b = UI:Button(f, text, width, 22, fn, variant)
        b:SetPoint("LEFT", x, 0)
        return b
    end
    btn(L["Nuovo"], 70, function() Editor:New() end, "secondary", 8)
    btn(L["Salva"], 70, function() Editor:Save() end, "primary", 84)
    btn(L["Esegui"], 70, function() Editor:Run() end, "secondary", 160)
    btn(L["Ferma"], 70, function() if Editor.current then scripts():Stop(Editor.current); Editor:Refresh() end end, "secondary", 236)
    self.delete = UI:ConfirmButton(f, L["Elimina"], L["Sicuro?"], 80, 22, function() Editor:Delete() end)
    self.delete:SetPoint("LEFT", 312, 0)
    btn(L["Esporta"], 70, function() Editor:Export() end, "ghost", 400)
    btn(L["Importa"], 70, function() Editor:ImportDialog() end, "ghost", 476)
end

function Editor:Refresh()
    if not self.win then return end
    local items = {}
    for _, s in ipairs(scripts():List()) do
        local badge = s.lastError and "!" or ((s.running and "ON") or (s.enabled and "..." or nil))
        items[#items + 1] = { id = s.name, text = s.name, badge = badge }
    end
    self.nav:SetItems(items)
    if self.current then self.nav:Select(self.current) end
    local rec = self.current and scripts():Record(self.current)
    if rec then
        self.status:SetText(string.format(L["Esecuzioni: %d%s%s"], rec.runs or 0,
            rec.imported and L[" - importato: leggi il codice prima di attivarlo"] or "",
            rec.lastError and (L["\nUltimo errore: "] .. rec.lastError) or ""))
    else
        self.status:SetText("")
    end
end

function Editor:Load(name)
    local rec = scripts():Record(name)
    self.current = rec and name or nil
    self.nameBox:SetText(rec and name or "")
    self.code:SetText(rec and rec.code or TEMPLATE)
    self.fields.trigger = rec and rec.trigger or "manual"
    self.fields.enabled = rec and rec.enabled or false
    self.param:SetText(rec and (rec.trigger == "timer" and tostring(rec.interval) or rec.event) or "")
    self.trigger:Refresh(); self.enabled:Refresh()
end

function Editor:Select(name) self:Load(name); self:Refresh() end

function Editor:New()
    self.current = nil
    self:Load(nil)
    self.nameBox:SetFocus()
    self:Refresh()
end

function Editor:Open(name)
    if not self.win then self:Build() end
    self.win:Show()
    if name and scripts():Record(name) then self:Select(name)
    elseif not self.current then self:Select((scripts():List()[1] or {}).name) end
    self:Refresh()
end

-- Raccoglie i campi dal form. Il campo "evento / secondi" dipende dal trigger scelto.
function Editor:Collect()
    local f = { code = self.code:GetText(), trigger = self.fields.trigger, enabled = self.fields.enabled }
    local p = strtrim(self.param:GetText() or "")
    if f.trigger == "timer" then f.interval = tonumber(p) or 5 elseif f.trigger == "event" and p ~= "" then f.event = p:upper() end
    return strtrim(self.nameBox:GetText() or ""), f
end

function Editor:Save()
    local name, fields = self:Collect()
    local ok, err = scripts():Save(name, fields)
    if not ok then self.status:SetText("|cffff6060" .. tostring(err) .. "|r"); self.nameBox:SetError(true); return false end
    self.nameBox:SetError(false)
    if self.current and self.current ~= name then scripts():Delete(self.current) end -- rinomina
    self.current = name
    self:Refresh()
    return true
end

function Editor:Run()
    if not self:Save() then return end
    local ok, err = scripts():Run(self.current)
    if not ok then self.status:SetText("|cffff6060" .. tostring(err) .. "|r") else self:Refresh() end
end

function Editor:Delete()
    if not self.current then return end
    scripts():Delete(self.current)
    self.current = nil
    self:Load(nil)
    self:Refresh()
end

-- Piccola finestra con un campo di testo (export: da copiare; import: da incollare).
function Editor:TextDialog(title, text, onOk)
    if not self.dialog then
        local d = UI:Window("BadbUIScriptText", 620, 300, title, { footer = true, strata = "FULLSCREEN_DIALOG" })
        d.box = UI:EditBox(d.body, 590, 200, { multiline = true, mono = true })
        d.box:SetPoint("TOPLEFT", 8, -8); d.box:SetPoint("BOTTOMRIGHT", -8, 8)
        d.ok = UI:Button(d.footer, "OK", 90, 22, function() if d.onOk then d.onOk(d.box:GetText()) end; d:Hide() end, "primary")
        d.ok:SetPoint("RIGHT", -8, 0)
        self.dialog = d
    end
    local d = self.dialog
    d:SetTitle(title)
    d.onOk = onOk
    d.box:SetText(text or "")
    d.ok:SetShown(onOk ~= nil)
    d:Show()
    d.box:SetFocus(); if text then d.box:HighlightText() end
end

function Editor:Export()
    if not self.current then return end
    local s, err = scripts():Export(self.current)
    if s then self:TextDialog(L["Esporta '"] .. self.current .. "' (Ctrl+C)", s) else self.status:SetText(tostring(err)) end
end

function Editor:ImportDialog()
    self:TextDialog(L["Incolla una stringa BADB1 di uno script"], "", function(text)
        local name, err = scripts():Import(text)
        if name then self.current = name; self:Load(name); self:Refresh()
        else self.status:SetText(L["|cffff6060Import fallito: "] .. tostring(err) .. "|r") end
    end)
end
