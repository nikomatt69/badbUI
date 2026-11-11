-- BadbUI - Suite: registro di cio' che BadbUI copre al posto di altri addon.
-- Ogni modulo dichiara nel proprio descrittore:
--   replaces = { { addon = "CartellaAddon", title = "Nome", coverage = "full" | "partial", note = "..." }, ... }
-- Suite incrocia queste dichiarazioni con gli addon installati e dice quali sono ormai superflui:
--   * "full"    il modulo BadbUI copre l'addon: con il modulo attivo l'addon si puo' spegnere e rimuovere
--   * "partial" il modulo copre l'uso comune ma non tutto: la nota spiega cosa manca
-- Spegnere un addon richiede /reload; nulla viene cancellato dal disco (lo fa l'utente dalla cartella AddOns).
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Modules, Logger = Badb.Modules, Badb.Logger

local MAX_NOTE = 240

local M = Modules:New("Suite", {
    title = L["Suite"],
    category = L["Gestione"],
    description = L["Mostra quali addon installati sono coperti dai moduli di BadbUI e possono essere spenti."],
    defaults = { enabled = true },
    page = { title = L["Addon sostituiti"], order = 15, category = L["Gestione"],
             keywords = { "addon", L["sostituisce"], L["rimuovi"], L["copertura"], "suite" } },
})
Badb.Suite = M

local function addonApi() return C_AddOns or {} end

local function isLoaded(name)
    local f = addonApi().IsAddOnLoaded or IsAddOnLoaded
    if not f then return false end
    local ok, v = pcall(f, name)
    return ok and v and true or false
end

-- Stato di un addon per nome cartella: installed, enabled (attivo al prossimo caricamento), loaded.
local function addonState(name)
    local api = addonApi()
    local info = api.GetAddOnInfo or GetAddOnInfo
    local installed = false
    if info then
        local ok, a, _, _, _, reason = pcall(info, name)
        if ok then
            if type(a) == "table" then installed = a.name ~= nil and a.reason ~= "MISSING"
            else installed = a ~= nil and reason ~= "MISSING" end
        end
    end
    local loaded = isLoaded(name)
    local enabled = loaded
    local state = api.GetAddOnEnableState or GetAddOnEnableState
    if state then
        local ok, v = pcall(state, name)
        if not (ok and type(v) == "number") then ok, v = pcall(state, UnitName and UnitName("player"), name) end
        if ok and type(v) == "number" then enabled = v > 0 end
    end
    return installed or loaded, enabled, loaded
end

local function validEntry(e)
    return type(e) == "table" and type(e.addon) == "string" and e.addon ~= "" and e.addon ~= Badb.name
end

-- Tutte le dichiarazioni, anche per addon non installati.
-- { {addon, title, module, moduleTitle, moduleEnabled, coverage, note, installed, enabled, loaded, removable}, ... }
function M:ListCoverage()
    local out = {}
    for _, name in ipairs(Modules.order) do
        local m = Modules.list[name]
        if type(m.replaces) == "table" then
            for _, e in ipairs(m.replaces) do
                if validEntry(e) then
                    local installed, enabled, loaded = addonState(e.addon)
                    local coverage = e.coverage == "partial" and "partial" or "full"
                    out[#out + 1] = {
                        addon = e.addon,
                        title = type(e.title) == "string" and e.title ~= "" and e.title or e.addon,
                        module = name, moduleTitle = m.title, moduleEnabled = m.enabled and true or false,
                        coverage = coverage,
                        note = type(e.note) == "string" and e.note:sub(1, MAX_NOTE) or nil,
                        installed = installed, enabled = enabled, loaded = loaded,
                        removable = coverage == "full" and (m.enabled and true or false),
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.title:lower() ~= b.title:lower() then return a.title:lower() < b.title:lower() end
        return a.module < b.module
    end)
    return out
end

-- Addon installati e ancora attivi che un modulo acceso copre per intero (senza doppioni).
function M:ListRemovable()
    local out, seen = {}, {}
    for _, row in ipairs(self:ListCoverage()) do
        if row.removable and row.installed and row.enabled and not seen[row.addon] then
            seen[row.addon] = true
            out[#out + 1] = row
        end
    end
    return out
end

local function setAddonEnabled(name, value)
    local mp = Badb.MainPages
    if mp and mp.setAddonEnabled then return mp.setAddonEnabled(name, value) end
    local api = addonApi()
    local f = value and (api.EnableAddOn or EnableAddOn) or (api.DisableAddOn or DisableAddOn)
    if not f then return false end
    return (pcall(f, name))
end

-- Spegne (non cancella) gli addon coperti per intero. Ritorna la lista dei nomi spenti; serve /reload.
function M:DisableCovered()
    local done = {}
    for _, row in ipairs(self:ListRemovable()) do
        if setAddonEnabled(row.addon, false) then done[#done + 1] = row.addon end
    end
    self.pendingReload = self.pendingReload or #done > 0
    return done
end

local function esc(s) return (tostring(s or ""):gsub("|", "||")) end

function M.rows()
    local rows = {}
    for _, row in ipairs(M:ListCoverage()) do
        if row.installed then
            local state
            if not row.enabled then state = L["|cff888888gia' spento|r"]
            elseif not row.moduleEnabled then state = L["|cffffcc00modulo BadbUI spento|r"]
            elseif row.coverage == "partial" then state = L["|cffffcc00coperto in parte|r"]
            else state = L["|cff5fd068coperto: puoi rimuoverlo|r"] end
            local detail = state .. " - " .. esc(row.moduleTitle)
            if row.note then detail = detail .. " - " .. esc(row.note) end
            local acts = {}
            if not row.moduleEnabled then
                acts[#acts + 1] = { label = L["Accendi"], width = 64, func = function() Modules:SetEnabled(row.module, true) end }
            elseif row.enabled then
                acts[#acts + 1] = { label = L["Spegni"], width = 64, func = function()
                    if setAddonEnabled(row.addon, false) then M.pendingReload = true end
                end }
            end
            rows[#rows + 1] = { text = esc(row.title), detail = detail, actions = acts }
        end
    end
    return rows
end

M.options = {
    { type = "label", text = function()
        local n = #M:ListRemovable()
        local head = n > 0 and string.format(L["%d addon installati sono coperti per intero da BadbUI: puoi spegnerli e poi rimuoverli dalla cartella AddOns."], n)
            or L["Nessun addon installato e' ancora da spegnere: BadbUI sta gia' facendo il lavoro."]
        if M.pendingReload then head = head .. "\n" .. L["|cff3fa7ffRicarica l'interfaccia per applicare le modifiche.|r"] end
        return head
    end },
    { type = "list", height = 360, empty = L["Nessun addon coperto risulta installato"], items = M.rows },
    { type = "execute", label = L["Spegni tutti gli addon coperti per intero"],
      confirm = L["Spegnere tutti gli addon coperti per intero? Servira' un /reload."],
      func = function()
          local done = M:DisableCovered()
          Logger:Info(L["Addon spenti: %s"], #done > 0 and table.concat(done, ", ") or L["nessuno"])
      end },
    { type = "execute", label = L["Ricarica l'interfaccia (/reload)"], func = function() ReloadUI() end },
}

M.commands = {
    suite = { help = L["suite [disable] - elenca gli addon coperti da BadbUI o li spegne"], fn = function(args)
        if strtrim(args or ""):lower() == "disable" then
            local done = M:DisableCovered()
            Logger:Info(L["Addon spenti: %s"], #done > 0 and table.concat(done, ", ") or L["nessuno"])
            if #done > 0 then Logger:Info(L["Usa /reload per applicare."]) end
            return
        end
        local n = 0
        for _, row in ipairs(M:ListCoverage()) do
            if row.installed then
                n = n + 1
                Logger:Info("%s -> %s (%s)", row.title, row.moduleTitle,
                    row.removable and L["coperto"] or (row.coverage == "partial" and L["in parte"] or L["modulo spento"]))
            end
        end
        if n == 0 then Logger:Info(L["Nessun addon coperto risulta installato"]) end
    end },
}
