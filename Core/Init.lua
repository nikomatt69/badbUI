-- AegisUI - Init
-- Namespace condiviso tra tutti i file dell'addon (passato come vararg dal client).
local ADDON_NAME, ns = ...

local Aegis = {}
ns.Aegis = Aegis
_G.AegisUI = Aegis -- API pubblica per altri addon/WeakAuras

Aegis.name = ADDON_NAME
Aegis.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- Localizzazione: L["chiave"] restituisce la chiave stessa se manca la traduzione.
Aegis.L = setmetatable({}, { __index = function(t, k) rawset(t, k, k); return k end })

-- Utilita' comuni
function Aegis.CopyTable(src, dst)
    dst = dst or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = Aegis.CopyTable(v, type(dst[k]) == "table" and dst[k] or {})
        else
            dst[k] = v
        end
    end
    return dst
end

-- Applica i default senza sovrascrivere i valori dell'utente.
function Aegis.MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            Aegis.MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Accesso a percorsi "a.b.c" dentro una tabella.
function Aegis.GetPath(tbl, path)
    for key in string.gmatch(path, "[^%.]+") do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[key]
    end
    return tbl
end

function Aegis.SetPath(tbl, path, value)
    local parent, last = tbl, nil
    for key in string.gmatch(path, "[^%.]+") do
        if last then
            if type(parent[last]) ~= "table" then parent[last] = {} end
            parent = parent[last]
        end
        last = key
    end
    parent[last] = value
end
