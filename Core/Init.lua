-- BadbUI - Init
-- Namespace condiviso tra tutti i file dell'addon (passato come vararg dal client).
local ADDON_NAME, ns = ...

local Badb = {}
ns.Badb = Badb
_G.BadbUI = Badb -- API pubblica per altri addon/WeakAuras

Badb.name = ADDON_NAME
Badb.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- Localizzazione: L["chiave"] restituisce la chiave stessa se manca la traduzione.
Badb.L = setmetatable({}, { __index = function(t, k) rawset(t, k, k); return k end })

-- Utilita' comuni
function Badb.CopyTable(src, dst)
    dst = dst or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = Badb.CopyTable(v, type(dst[k]) == "table" and dst[k] or {})
        else
            dst[k] = v
        end
    end
    return dst
end

-- Applica i default senza sovrascrivere i valori dell'utente.
function Badb.MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            Badb.MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Accesso a percorsi "a.b.c" dentro una tabella.
function Badb.GetPath(tbl, path)
    for key in string.gmatch(path, "[^%.]+") do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[key]
    end
    return tbl
end

function Badb.SetPath(tbl, path, value)
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
