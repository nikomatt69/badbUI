-- BadbUI - Hub di integrazione con gli addon terzi.
-- Rileva gli addon (ElvUI, Details!, Plater, Bartender4, BigWigs, DBM, WeakAuras...), cattura il loro
-- stato/profilo dentro il profilo BadbUI (quindi nell'export BadbUI) e lo riapplica.
-- Gli adapter specifici stanno in Modules/IntegrationAdapters.lua (Badb.IntegrationAdapterDefs);
-- adapter di terze parti: Badb.Integrations:RegisterAdapter(def).
--
-- Dati salvati (profilo, modulo "Integrations"):
--   data = { [id] = { version = 1, capturedAt = time, payload = <tabella> } }
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger, Modules = Badb.Events, Badb.Logger, Badb.Modules

local DATA_VERSION = 1
local MAX_PAYLOAD_BYTES = 64 * 1024  -- dimensione dell'export serializzato del payload
local MAX_DEPTH, MAX_NODES = 12, 20000
local ID_PATTERN = "^[%w_%-]+$"      -- niente punti: l'id finisce in un percorso "data.<id>"

local M = Modules:New("Integrations", {
    title = L["Integrazioni addon"],
    category = L["Strumenti"],
    defaults = { enabled = true, autoApplyOnProfileChange = false, data = {} },
    options = {
        { type = "toggle", path = "autoApplyOnProfileChange", label = L["Riapplica le integrazioni al cambio profilo"] },
    },
})
Badb.Integrations = M
M.adapters, M.order, M.state = {}, {}, {}
M.MAX_PAYLOAD_BYTES = MAX_PAYLOAD_BYTES

-- ---------------------------------------------------------------------------------------
-- Utilita'
-- ---------------------------------------------------------------------------------------
local function now()
    if type(time) == "function" then return time() end
    if type(GetTime) == "function" then return GetTime() end
    return 0
end

local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() and true or false end

local function isSecret(v) return Badb.Compat ~= nil and Badb.Compat.IsSecret(v) or false end

local function pack(...) return { n = select("#", ...), ... } end

-- Rende pubblico un metodo che non lancia mai: un errore interno diventa `false, messaggio`.
local function guarded(fn, onFail)
    return function(...)
        local r = pack(pcall(fn, ...))
        if r[1] then return unpack(r, 2, r.n) end
        Logger:Error("Integrations: %s", tostring(r[2]))
        if onFail then return onFail(tostring(r[2])) end
        return false, tostring(r[2])
    end
end

-- Copia pulita di un payload: solo string/number/boolean/table, chiavi string/number, niente
-- funzioni/userdata/secret, niente cicli, profondita' e numero di nodi limitati.
local function sanitize(value, depth, path, budget)
    if isSecret(value) then return nil end
    local tv = type(value)
    if tv == "string" or tv == "boolean" then return value end
    if tv == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if tv ~= "table" then return nil end
    if depth > MAX_DEPTH then error(L["struttura troppo profonda"], 0) end
    if path[value] then error(L["riferimento ciclico nei dati"], 0) end
    budget.n = budget.n + 1
    if budget.n > MAX_NODES then error(L["troppi elementi nei dati"], 0) end
    path[value] = true
    local out = {}
    for k, v in pairs(value) do
        local tk = type(k)
        if (tk == "string" and not isSecret(k)) or (tk == "number" and k == k and k ~= math.huge and k ~= -math.huge) then
            local clean = sanitize(v, depth + 1, path, budget)
            if clean ~= nil then out[k] = clean end
        end
    end
    path[value] = nil
    return out
end

-- ---------------------------------------------------------------------------------------
-- Registro adapter
-- ---------------------------------------------------------------------------------------
function M:RegisterAdapter(def)
    if type(def) ~= "table" then return false, L["definizione non valida"] end
    local id = def.id
    if type(id) ~= "string" or #id > 64 or not id:match(ID_PATTERN) then
        return false, L["id non valido (solo lettere, numeri, '_' e '-')"]
    end
    local supported = def.supported ~= false
    if supported and (type(def.capture) ~= "function" or type(def.apply) ~= "function") then
        return false, "adapter '" .. id .. L["': capture e apply sono obbligatori"]
    end
    if def.detect ~= nil and type(def.detect) ~= "function" then return false, L["detect deve essere una funzione"] end
    if def.reset ~= nil and type(def.reset) ~= "function" then return false, L["reset deve essere una funzione"] end
    local a = {
        id = id,
        title = type(def.title) == "string" and def.title or id,
        addon = type(def.addon) == "string" and def.addon or nil,
        detect = def.detect, capture = def.capture, apply = def.apply, reset = def.reset,
        supported = supported,
        unsupportedReason = type(def.unsupportedReason) == "string" and def.unsupportedReason or nil,
        note = type(def.note) == "string" and def.note or "",
        noteFn = type(def.noteFn) == "function" and def.noteFn or nil,
        confidence = (def.confidence == "A" or def.confidence == "B") and def.confidence or "C",
    }
    if not supported and not a.unsupportedReason then a.unsupportedReason = L["non supportato"] end
    if not self.adapters[id] then self.order[#self.order + 1] = id end
    self.adapters[id] = a
    self.state[id] = self.state[id] or {}
    return true
end

local function adapterFor(self, id)
    if type(id) ~= "string" then return nil, L["id integrazione non valido"] end
    local a = self.adapters[id]
    if not a then return nil, L["integrazione sconosciuta: "] .. id end
    return a
end

-- Esegue una funzione dell'adapter in pcall. Ritorna ok, r1, r2 (ok=false => r1 = messaggio).
local function callAdapter(self, a, method, ...)
    local fn = a[method]
    if type(fn) ~= "function" then return false, method .. L[" non disponibile per "] .. a.title end
    local ok, r1, r2 = pcall(fn, ...)
    if not ok then
        local msg = tostring(r1)
        self.state[a.id].lastError = msg
        Logger:Error(L["Integrazione %s (%s): %s"], a.id, method, msg)
        return false, msg
    end
    return true, r1, r2
end

-- Nota informativa (statica o calcolata da noteFn, in pcall).
local function noteOf(a)
    if a.noteFn then
        local ok, n = pcall(a.noteFn)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return a.note or ""
end

local function isLoaded(self, a)
    if not a.detect then return false end
    local ok, r = pcall(a.detect)
    if not ok then
        self.state[a.id].lastError = tostring(r)
        Logger:Error(L["Integrazione %s (detect): %s"], a.id, tostring(r))
        return false
    end
    return r and true or false
end

-- ---------------------------------------------------------------------------------------
-- Dati catturati
-- ---------------------------------------------------------------------------------------
local function getData(self, create)
    local ok, data = pcall(self.Get, self, "data")
    if ok and type(data) == "table" then return data end
    if create then
        pcall(self.Set, self, "data", {})
        ok, data = pcall(self.Get, self, "data")
        if ok and type(data) == "table" then return data end
    end
    return nil
end

-- Ritorna record | nil, motivo ("missing" | "corrupt" | "newer")
local function recordOf(self, id)
    local data = getData(self, false)
    if not data then
        local ok, raw = pcall(self.Get, self, "data")
        if ok and raw ~= nil then return nil, "corrupt" end
        return nil, "missing"
    end
    local rec = data[id]
    if rec == nil then return nil, "missing" end
    if type(rec) ~= "table" or type(rec.version) ~= "number" or type(rec.payload) ~= "table" then
        return nil, "corrupt"
    end
    if rec.version < 1 or rec.version % 1 ~= 0 then return nil, "corrupt" end
    if rec.version > DATA_VERSION then return nil, "newer" end
    return rec
end

local RECORD_ERRORS = {
    missing = L["nessun dato catturato: esegui prima Cattura"],
    corrupt = L["dati catturati corrotti: ripeti la Cattura"],
    newer = L["dati creati da una versione piu' recente di BadbUI"],
}

-- ---------------------------------------------------------------------------------------
-- API pubblica
-- ---------------------------------------------------------------------------------------
function M:Status(id)
    local a, err = adapterFor(self, id)
    if not a then return nil, err end
    local st = self.state[id] or {}
    local rec, why = recordOf(self, id)
    local loaded = isLoaded(self, a)
    local info = {
        id = id, title = a.title, addon = a.addon,
        loaded = loaded, supported = a.supported, unsupportedReason = a.unsupportedReason,
        note = noteOf(a), confidence = a.confidence,
        hasProfile = rec ~= nil, capturedAt = rec and rec.capturedAt or nil,
        corrupt = (why == "corrupt"), canReset = a.reset ~= nil,
        lastError = st.lastError, lastWarning = st.lastWarning, lastApplied = st.lastApplied,
    }
    if not a.supported then info.state = "unsupported"
    elseif not loaded then info.state = "missing"
    elseif rec then info.state = "captured"
    else info.state = "installed" end
    return info
end
M.Status = guarded(M.Status, function(msg) return nil, msg end)

function M:List()
    local out = {}
    for _, id in ipairs(self.order) do
        local s = self:Status(id)
        if s then
            out[#out + 1] = {
                id = s.id, title = s.title, loaded = s.loaded, supported = s.supported,
                hasProfile = s.hasProfile, reason = s.unsupportedReason, state = s.state,
                capturedAt = s.capturedAt, canReset = s.canReset, note = s.note, confidence = s.confidence,
            }
        end
    end
    return out
end
M.List = guarded(M.List, function() return {} end)

-- Salva nel profilo BadbUI lo stato dell'addon terzo.
function M:Capture(id)
    local a, err = adapterFor(self, id)
    if not a then return false, err end
    if not a.supported then return false, a.unsupportedReason end
    if not isLoaded(self, a) then return false, a.title .. L[" non e' caricato"] end
    local st = self.state[id]
    local ok, payload, msg = callAdapter(self, a, "capture")
    if not ok then return false, payload end
    if type(payload) ~= "table" then
        err = (type(msg) == "string" and msg) or L["capture non ha restituito dati validi"]
        st.lastError = err
        return false, err
    end
    local okS, clean = pcall(sanitize, payload, 1, {}, { n = 0 })
    if not okS then
        st.lastError = tostring(clean)
        return false, L["payload non valido: "] .. tostring(clean)
    end
    local okE, str = pcall(Badb.Serializer.Export, Badb.Serializer, "integration:" .. id, clean)
    if not okE or type(str) ~= "string" then
        st.lastError = L["serializzazione fallita"]
        return false, L["serializzazione del payload fallita"]
    end
    if #str > MAX_PAYLOAD_BYTES then
        err = string.format(L["payload troppo grande (%d byte, massimo %d)"], #str, MAX_PAYLOAD_BYTES)
        st.lastError = err
        return false, err
    end
    if not getData(self, true) then return false, L["profilo BadbUI non disponibile"] end
    self:Set("data." .. id, { version = DATA_VERSION, capturedAt = now(), payload = clean })
    st.lastError = nil
    return true
end
M.Capture = guarded(M.Capture)

-- Backup pre-azione (se Badb.Backups esiste). Un backup fallito avvisa ma non blocca.
local function backup(label)
    local B = Badb.Backups
    if B and type(B.Create) == "function" then
        local ok, id = pcall(B.Create, B, label, "pre-import")
        if not ok or not id then Logger:Warn(L["Backup pre-azione non riuscito (%s)"], label) end
    end
end

-- Controlli comuni ad Apply/Reset (immediati, validi anche in combattimento).
local function usable(self, a)
    if not a.supported then return false, a.unsupportedReason end
    if not isLoaded(self, a) then return false, a.title .. L[" non e' caricato"] end
    return true
end

-- Esecuzione sincrona di Apply (si assume fuori combattimento).
local function doApply(self, id, opts)
    local a, err = adapterFor(self, id)
    if not a then return false, err end
    local okU, errU = usable(self, a)
    if not okU then return false, errU end
    local rec, why = recordOf(self, id)
    if not rec then return false, RECORD_ERRORS[why] or L["dati non validi"] end
    if self._busy then return false, L["operazione gia' in corso"] end

    self._busy = true
    local st = self.state[id]
    local okRun, rOk, rErr, rWarn = pcall(function()
        if not (opts and opts.noBackup) then backup(L["Integrazione "] .. a.title) end
        local okC, res, msg = callAdapter(self, a, "apply", Badb.CopyTable(rec.payload))
        if not okC then return false, res end
        if res == "skipped" then
            st.lastWarning = msg
            Logger:Warn("%s: %s", a.title, tostring(msg))
            return true, nil, msg
        end
        if res == false or (res == nil and type(msg) == "string") then
            local e = tostring(msg or L["apply fallito"])
            st.lastError = e
            Logger:Error(L["Integrazione %s (apply): %s"], id, e)
            return false, e
        end
        st.lastError, st.lastWarning, st.lastApplied = nil, nil, now()
        Events:Fire("BADB_INTEGRATION_APPLIED", id)
        return true
    end)
    self._busy = false
    if not okRun then
        st.lastError = tostring(rOk)
        Logger:Error(L["Integrazione %s: %s"], id, tostring(rOk))
        return false, tostring(rOk)
    end
    return rOk, rErr, rWarn
end

-- Riapplica quanto catturato. In combattimento l'azione e' differita a fine combattimento.
-- Ritorna true, nil[, avviso]  oppure  false, errore.
function M:Apply(id, opts)
    local a, err = adapterFor(self, id)
    if not a then return false, err end
    local okU, errU = usable(self, a)
    if not okU then return false, errU end
    local rec, why = recordOf(self, id)
    if not rec then return false, RECORD_ERRORS[why] or L["dati non validi"] end
    if inCombat() then
        Events:RunOutOfCombat("integration:apply:" .. id, function()
            local ok, e = doApply(self, id, opts)
            if not ok then Logger:Warn(L["Applicazione differita di %s fallita: %s"], id, tostring(e)) end
        end)
        return true, nil, L["differito a fine combattimento"]
    end
    return doApply(self, id, opts)
end
M.Apply = guarded(M.Apply)

-- Applica tutte le integrazioni catturate, supportate e caricate. Un adapter che fallisce non
-- blocca gli altri. Ritorna ok(=nessun fallimento), err, applicate, fallite.
local function applyAllNow(self, opts)
    if self._autoRunning then return false, L["operazione gia' in corso"], 0, 0 end
    self._autoRunning = true
    local applied, failed, lastErr = 0, 0, nil
    for _, id in ipairs(self.order) do
        local a = self.adapters[id]
        if a and a.supported and isLoaded(self, a) and recordOf(self, id) then
            local ok, e = doApply(self, id, opts)
            if ok then applied = applied + 1 else failed = failed + 1; lastErr = e end
        end
    end
    self._autoRunning = false
    return failed == 0, lastErr, applied, failed
end

function M:ApplyAll(opts)
    if inCombat() then
        Events:RunOutOfCombat("integration:applyAll", function()
            local ok = pcall(applyAllNow, self, opts)
            if not ok then self._autoRunning = false end
        end)
        return true, nil, 0, 0
    end
    return applyAllNow(self, opts)
end
M.ApplyAll = guarded(M.ApplyAll)

-- Ripristina i default dell'addon terzo (se l'adapter lo supporta). Distruttivo: backup prima.
function M:Reset(id)
    local a, err = adapterFor(self, id)
    if not a then return false, err end
    if type(a.reset) ~= "function" then return false, L["reset non supportato per "] .. a.title end
    local okU, errU = usable(self, a)
    if not okU then return false, errU end
    local function run()
        if self._busy then return false, L["operazione gia' in corso"] end
        self._busy = true
        local okRun, ok, e = pcall(function()
            backup("Reset " .. a.title)
            local okC, res, msg = callAdapter(self, a, "reset")
            if not okC then return false, res end
            if res == false or (res == nil and type(msg) == "string") then
                self.state[id].lastError = tostring(msg)
                return false, tostring(msg)
            end
            self.state[id].lastError = nil
            return true
        end)
        self._busy = false
        if not okRun then return false, tostring(ok) end
        return ok, e
    end
    if inCombat() then
        Events:RunOutOfCombat("integration:reset:" .. id, function()
            local ok, e = run()
            if not ok then Logger:Warn(L["Reset differito di %s fallito: %s"], id, tostring(e)) end
        end)
        return true, nil, L["differito a fine combattimento"]
    end
    return run()
end
M.Reset = guarded(M.Reset)

-- Elimina i dati catturati (non tocca l'addon terzo).
function M:Forget(id)
    local a, err = adapterFor(self, id)
    if not a then return false, err end
    local data = getData(self, false)
    if data and data[id] ~= nil then self:Set("data." .. id, nil) end
    return true
end
M.Forget = guarded(M.Forget)

-- ---------------------------------------------------------------------------------------
-- Ciclo di vita
-- ---------------------------------------------------------------------------------------
function M:OnInitialize()
    for _, def in ipairs(Badb.IntegrationAdapterDefs or {}) do
        -- Un adapter di terze parti gia' registrato con lo stesso id ha la precedenza.
        if not self.adapters[def.id] then
            local ok, err = self:RegisterAdapter(def)
            if not ok then Logger:Warn(L["Adapter %s scartato: %s"], tostring(def.id), tostring(err)) end
        end
    end
end

function M:OnEnable()
    self:On("BADB_PROFILE_CHANGED", function()
        if self._busy or self._autoRunning then return end -- anti-ricorsione
        if not self:Get("autoApplyOnProfileChange") then return end
        Events:RunOutOfCombat("integration:autoApply", function()
            if self._busy or self._autoRunning then return end
            if not self:Get("autoApplyOnProfileChange") then return end
            applyAllNow(self, { noBackup = true })
        end)
    end)
end

function M:OnDisable()
    self._busy, self._autoRunning = false, false
end

-- ---------------------------------------------------------------------------------------
-- Comandi /badb integration ...
-- ---------------------------------------------------------------------------------------
local function parseArgs(args)
    if type(args) == "table" then return args[1], args[2] end
    if type(args) ~= "string" then return nil end
    local a, b = args:match("^%s*(%S+)%s*(%S*)")
    if b == "" then b = nil end
    return a, b
end

local STATE_LABEL = { missing = L["non installato"], installed = L["installato"], captured = L["catturato"], unsupported = L["non supportato"] }

local function report(ok, err, warn, okText)
    if ok then
        Logger:Info("%s%s", okText, warn and (" (" .. tostring(warn) .. ")") or "")
    else
        Logger:Warn("%s", tostring(err))
    end
end

M.commands = {
    integration = {
        help = "integration list | capture <id> | apply <id> | reset <id> | forget <id>",
        fn = function(args)
            local sub, id = parseArgs(args)
            sub = sub and sub:lower() or "list"
            if sub == "list" then
                for _, r in ipairs(M:List()) do
                    Logger:Info("%s [%s]: %s%s", r.id, r.title, STATE_LABEL[r.state] or r.state,
                        r.reason and (" - " .. r.reason) or "")
                end
            elseif sub == "capture" or sub == "apply" or sub == "reset" or sub == "forget" then
                if not id then Logger:Warn(L["uso: integration %s <id>"], sub); return end
                local method = sub:sub(1, 1):upper() .. sub:sub(2)
                local ok, err, warn = M[method](M, id)
                report(ok, err, warn, id .. ": " .. sub .. L[" eseguito"])
            else
                Logger:Info(L["uso: /badb integration list | capture <id> | apply <id> | reset <id> | forget <id>"])
            end
        end,
    },
}

-- ---------------------------------------------------------------------------------------
-- Pagina ConfigUI: una riga per integrazione.
-- ---------------------------------------------------------------------------------------
local ICONS = {
    missing = "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
    installed = "Interface\\RAIDFRAME\\ReadyCheck-Waiting",
    captured = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    unsupported = "Interface\\RAIDFRAME\\ReadyCheck-Waiting",
}
local ROW_H = 46

local function notify(text, level)
    local UI = Badb.ConfigUI
    if UI and UI.Toast then
        local ok = pcall(UI.Toast, UI, text, level)
        if ok then return end
    end
    if level == "error" then Logger:Warn("%s", text) else Logger:Info("%s", text) end
end

local function makeButton(parent, label, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(70, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function buildPage(parent, ctx)
    local rows = {}
    local y = 0

    local auto = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    auto:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    local autoText = auto.text or auto.Text
    if autoText then autoText:SetText(L["Riapplica le integrazioni al cambio profilo"]) end
    auto:SetScript("OnClick", function(self)
        M:Set("autoApplyOnProfileChange", self:GetChecked() and true or false)
    end)
    y = y + 34

    local function refresh()
        pcall(function() auto:SetChecked(M:Get("autoApplyOnProfileChange") and true or false) end)
        for _, row in ipairs(rows) do
            local s = M:Status(row.id)
            if s then
                row.icon:SetTexture(ICONS[s.state] or ICONS.missing)
                row.title:SetText(s.title)
                local line = STATE_LABEL[s.state] or s.state
                if s.state == "captured" and s.capturedAt and date then
                    local okD, d = pcall(date, "%Y-%m-%d %H:%M", s.capturedAt)
                    if okD and type(d) == "string" then line = line .. " (" .. d .. ")" end
                end
                row.status:SetText(line)
                local detail = s.unsupportedReason or s.lastError or s.lastWarning or s.note or ""
                row.reason:SetText(detail)
                local canCapture = s.loaded and s.supported
                row.capture:SetEnabled(canCapture and true or false)
                row.apply:SetEnabled((canCapture and s.hasProfile) and true or false)
                row.reset:SetEnabled((canCapture and s.canReset) and true or false)
                if s.supported then row.reset:Show() else row.reset:Hide() end
            end
        end
    end

    local function act(id, method, okText)
        local ok, err, warn = M[method](M, id)
        if ok then notify(okText .. (warn and (" - " .. tostring(warn)) or ""), "info")
        else notify(tostring(err), "error") end
        refresh()
    end

    for _, item in ipairs(M:List()) do
        local id = item.id
        local row = { id = id }
        row.icon = parent:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -y - 2)
        row.title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.title:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, -y)
        row.status = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.status:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, -y - 16)
        row.reason = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.reason:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, -y - 30)
        row.capture = makeButton(parent, L["Cattura"], 330, -y, function() act(id, "Capture", L["Catturato"]) end)
        row.apply = makeButton(parent, L["Applica"], 404, -y, function() act(id, "Apply", L["Applicato"]) end)
        row.reset = makeButton(parent, "Reset", 478, -y, function()
            local UI = Badb.ConfigUI
            local run = function() act(id, "Reset", L["Reset eseguito"]) end
            if UI and UI.Confirm then UI:Confirm(L["Ripristinare i default di "] .. item.title .. "?", run) else run() end
        end)
        rows[#rows + 1] = row
        y = y + ROW_H
    end

    M._pageRefresh = refresh
    refresh()
    return y
end

M.page = {
    title = L["Integrazioni"],
    order = 50,
    category = L["Strumenti"],
    build = buildPage,
    refresh = function() if M._pageRefresh then M._pageRefresh() end end,
}
