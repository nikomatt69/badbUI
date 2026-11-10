-- BadbUI - Gestore CVar
-- Molte opzioni di nameplate e raid frame su Forever sono CVar Blizzard. Questo servizio:
--   * salva il valore originale di ogni CVar la prima volta che BadbUI lo modifica
--     (in BadbUIDB.global.cvarOriginals, condiviso tra profili);
--   * tiene traccia (anche dopo /reload) di quale modulo "possiede" ogni CVar, per ripristinarli quando il modulo
--     viene disattivato;
--   * rimanda le modifiche fuori dal combattimento (molti CVar di nameplate sono protetti).
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger = Badb.Events, Badb.Logger

local CVars = {}
Badb.CVars = CVars

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

local function originals()
    local g = Badb.DB.sv.global
    g.cvarOriginals = g.cvarOriginals or {}
    return g.cvarOriginals
end

-- Un CVar esiste sul client corrente? (Forever non ha tutti i CVar di Retail.)
function CVars:Exists(name)
    if C_CVar and C_CVar.GetCVarInfo then return C_CVar.GetCVarInfo(name) ~= nil end
    return GetCVar(name) ~= nil
end

function CVars:Get(name)
    return GetCVar(name)
end

local function normalize(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    return tostring(value)
end

local function setNow(owner, name, value)
    if not CVars:Exists(name) then
        Logger:Debug(L["CVar %s non presente su questo client"], name)
        return
    end
    -- { value = originale, owner = modulo }: persistente, sopravvive a /reload.
    local orig = originals()
    if orig[name] == nil then orig[name] = { value = GetCVar(name), owner = owner } end
    orig[name].owner = owner
    value = normalize(value)
    if GetCVar(name) ~= value then
        local ok, err = pcall(SetCVar, name, value)
        if not ok then Logger:Warn("CVar %s: %s", name, tostring(err)) end
    end
end

-- owner: nome del modulo. Le modifiche in combattimento vengono accodate per CVar.
function CVars:Set(owner, name, value)
    Events:RunOutOfCombat("cvar:" .. name, function() setNow(owner, name, value) end)
end

-- Applica una tabella { cvar = valore } in blocco.
function CVars:SetMany(owner, map)
    Events:RunOutOfCombat("cvars:" .. owner, function()
        for name, value in pairs(map) do setNow(owner, name, value) end
    end)
end

-- Ripristina i valori originali di tutti i CVar posseduti da owner.
function CVars:Restore(owner)
    Events:RunOutOfCombat("cvarsRestore:" .. owner, function()
        local orig = originals()
        for name, o in pairs(orig) do
            if o.owner == owner then
                if o.value ~= nil then pcall(SetCVar, name, o.value) end
                orig[name] = nil
            end
        end
    end)
end

-- Dopo il login: CVar ancora marcati da moduli che nel profilo attuale sono spenti
-- (es. profilo cambiato prima di un /reload) vengono riportati al valore originale.
Events:On(CVars, "PLAYER_LOGIN", function()
    C_Timer.After(1, function()
        local seen = {}
        for _, o in pairs(originals()) do
            local m = Badb.Modules and Badb.Modules:Get(o.owner)
            if o.owner and not seen[o.owner] and not (m and m.enabled) then
                seen[o.owner] = true
                CVars:Restore(o.owner)
            end
        end
    end)
end)
