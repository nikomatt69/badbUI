-- Aggiornamenti BadbUI: il gioco salva una richiesta, il companion la esegue a client chiuso.
local _, ns = ...
local Badb = ns.Badb
local L = Badb.L
local U = {}
Badb.Updates = U

local MAX_STATUS_AGE = 600

local function store()
    return Badb.DB:GetStore("updates")
end

local function now()
    return time()
end

local function version(value)
    if type(value) ~= "string" or #value > 20 then return nil end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
    if major > 999999 or minor > 999999 or patch > 999999 then return nil end
    if value ~= string.format("%d.%d.%d", major, minor, patch) then return nil end
    return string.format("%06d%06d%06d", major, minor, patch)
end

local function available(status)
    local installed, latest = version(status.installed), version(status.latest)
    if status.installed ~= Badb.version or not installed or not latest then return false end
    if type(status.checkedAt) ~= "number" then return false end
    local age = now() - status.checkedAt
    return age >= -300 and age <= MAX_STATUS_AGE and latest > installed
end

function U:Status()
    local status = type(Badb.UpdateStatus) == "table" and Badb.UpdateStatus or {}
    local s = store()
    local request = s and type(s.request) == "table" and s.request or nil
    local receipt = type(status.receipt) == "table" and status.receipt or nil
    if request and receipt and type(request.id) == "string" and receipt.id == request.id then
        if receipt.result == "installed" and request.version == Badb.version and not available(status) then
            return "installed", Badb.version
        elseif receipt.result == "failed" and available(status) then
            return "failed", status.latest
        elseif receipt.result == "release_changed" and available(status) then
            return "release_changed", status.latest
        end
    elseif request and request.from == Badb.version and version(request.version)
        and type(request.at) == "number" and now() - request.at <= 86400 and request.at <= now() + 300 then
        return "pending", request.version
    end
    if available(status) then return "available", status.latest end
    if status.installed == Badb.version and version(status.latest) and type(status.checkedAt) == "number" then
        local age = now() - status.checkedAt
        if age >= -300 and age <= MAX_STATUS_AGE then return "current", Badb.version end
    end
    return "unknown", Badb.version
end

function U:CanRequest()
    local state = self:Status()
    return state == "available" or state == "failed" or state == "release_changed"
end

function U:Request(expected)
    if InCombatLockdown and InCombatLockdown() then return false, L["Riprova fuori dal combattimento."] end
    if not self:CanRequest() then return false, L["Nessun aggiornamento disponibile da installare."] end
    local s = store()
    if not s then return false, L["Le impostazioni di BadbUI non sono ancora disponibili."] end
    local _, target = self:Status()
    if expected and target ~= expected then return false, L["Nessun aggiornamento disponibile da installare."] end
    local timestamp = now()
    local seq = type(s.sequence) == "number" and s.sequence or 0
    seq = math.floor(seq % 1000000000) + 1
    if seq ~= seq then seq = 1 end
    s.version = 1
    s.sequence = seq
    s.request = { id = string.format("%d-%d", timestamp, seq), from = Badb.version, version = target, at = timestamp }
    return true
end

function U:Cancel()
    if self:Status() ~= "pending" then return false end
    local s = store()
    if not s then return false end
    s.request = nil
    return true
end

function U:StatusText()
    local state, target = self:Status()
    local messages = {
        unknown = L["BadbUI %s. Avvia il companion e usa /reload per leggere il catalogo degli aggiornamenti."],
        current = L["BadbUI %s è aggiornato."],
        available = L["BadbUI %s è disponibile."],
        pending = L["Aggiornamento a BadbUI %s richiesto. Esci da WoW e attendi la conferma nel companion prima di riaprirlo."],
        installed = L["BadbUI %s è stato installato."],
        failed = L["Aggiornamento a BadbUI %s non riuscito. Controlla il messaggio nel companion e riprova."],
        release_changed = L["La release è cambiata. Puoi confermare l'installazione di BadbUI %s."],
    }
    return string.format(messages[state], target)
end

function U:Options()
    return {
        { type = "header", label = L["Aggiornamenti BadbUI"] },
        { type = "label", text = function() return U:StatusText() end },
        { type = "execute", label = L["Installa aggiornamento"], disabled = function() return not U:CanRequest() end,
          func = function()
              if not U:CanRequest() then return end
              local _, target = U:Status()
              local ui = Badb.ConfigUI
              ui:Confirm(string.format(L["Installare BadbUI %s? Dopo la conferma, esci da WoW lasciando aperto il companion."], target), function()
                  local ok, err = U:Request(target)
                  ui:Toast(ok and U:StatusText() or err, ok and "info" or "warn")
                  ui:RefreshPage("addons")
              end)
          end },
        { type = "execute", label = L["Annulla aggiornamento"], disabled = function() return U:Status() ~= "pending" end,
          func = function()
              U:Cancel()
              Badb.ConfigUI:RefreshPage("addons")
          end },
    }
end
