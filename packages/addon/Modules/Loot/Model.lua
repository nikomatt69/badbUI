-- BadbUI - Statistiche native degli oggetti e archivio locale.
local _, ns = ...
local Badb, L = ns.Badb, ns.Badb.L
local Model = {}
Badb.LootModel = Model

local MAX_ID, MAX_WEIGHT = 10000000, 100
local MAX_FAVORITES, MAX_OBSERVED, MAX_AGE = 100, 240, 90 * 86400

Model.stats = {
    { path = "strength", token = "ITEM_MOD_STRENGTH_SHORT", label = L["Forza"] },
    { path = "agility", token = "ITEM_MOD_AGILITY_SHORT", label = L["Agilità"] },
    { path = "stamina", token = "ITEM_MOD_STAMINA_SHORT", label = L["Tempra"] },
    { path = "intellect", token = "ITEM_MOD_INTELLECT_SHORT", label = L["Intelletto"] },
    { path = "spirit", token = "ITEM_MOD_SPIRIT_SHORT", label = L["Spirito"] },
    { path = "armor", token = "RESISTANCE0_NAME", label = L["Armatura"] },
    { path = "attackPower", token = "ITEM_MOD_ATTACK_POWER_SHORT", label = L["Potenza d'attacco"] },
    { path = "spellPower", token = "ITEM_MOD_SPELL_POWER_SHORT", label = L["Potenza magica"] },
    { path = "spellDamage", token = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", label = L["Danni magici"] },
    { path = "healing", token = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", label = L["Cure magiche"] },
    { path = "crit", token = "ITEM_MOD_CRIT_RATING_SHORT", label = L["Critico"] },
    { path = "hit", token = "ITEM_MOD_HIT_RATING_SHORT", label = L["Indice di impatto"] },
}

function Model.Call(fn, ...)
    if type(fn) ~= "function" then return end
    return pcall(fn, ...)
end

function Model.Number(value, min, max)
    if Badb.Compat.IsSecret(value) or type(value) ~= "number" or value ~= value or value < min or value > max then return nil end
    return value
end

function Model.Text(value, limit)
    if Badb.Compat.IsSecret(value) or type(value) ~= "string" then return nil end
    value = value:gsub("[%c|]", ""):sub(1, limit)
    return value ~= "" and value or nil
end

function Model.Item(value)
    if Badb.Compat.IsSecret(value) then return nil end
    if type(value) == "number" then
        if Model.Number(value, 1, MAX_ID) and value % 1 == 0 then return value, "item:" .. value end
        return nil
    end
    if type(value) ~= "string" or #value > 1024 then return nil end
    local data = value:match("|H(item:[%d:%-]+)|h") or value:match("^%s*(item:[%d:%-]+)%s*$")
    local raw = data and (data:match("^item:(%d+)$") or data:match("^item:(%d+):[%d:%-]*$"))
        or value:match("^%s*(%d+)%s*$")
    local id = raw and tonumber(raw)
    if Model.Number(id, 1, MAX_ID) then return id, data or ("item:" .. id) end
end

function Model.GetInfo(value)
    local id, item = Model.Item(value)
    if not id then return nil end
    local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, name, _, _, _, _, _, _, _, equip = Model.Call(fn, item)
    return id, item, ok and Model.Text(name, 120) or nil, ok and Model.Text(equip, 80) or nil
end

function Model.HasStats()
    return type(C_Item and C_Item.GetItemStats or GetItemStats) == "function"
end

function Model.Score(value, getWeight)
    local id, item, name, equip = Model.GetInfo(value)
    if not id then return nil, "invalid" end
    if not Model.HasStats() then return nil, "unavailable" end
    if not name then return nil, "loading", id end
    if not equip or equip == "INVTYPE_NON_EQUIP_IGNORE" then return nil, "equipment" end
    local ok, stats = Model.Call(C_Item and C_Item.GetItemStats or GetItemStats, item)
    if not ok or Badb.Compat.IsSecret(stats) or type(stats) ~= "table" then return nil, "unavailable" end
    local score, active = 0, false
    for _, def in ipairs(Model.stats) do
        local weight = Model.Number(getWeight(def.path), 0, MAX_WEIGHT) or 0
        if weight > 0 then
            active = true
            local amount = stats[def.token]
            if Badb.Compat.IsSecret(amount) then return nil, "unavailable" end
            score = score + weight * (Model.Number(amount, -100000, 100000) or 0)
        end
    end
    if not active then return nil, "weights" end
    return { id = id, name = name, equip = equip, score = score }
end

function Model.Open(store, at)
    if type(store) ~= "table" then return nil end
    local favorites, observed = {}, {}
    if store.version == 1 then
        local seen = {}
        for i = 1, MAX_FAVORITES do
            local id = type(store.favorites) == "table" and Model.Item(store.favorites[i]) or nil
            if id and not seen[id] then
                seen[id] = true
                favorites[#favorites + 1] = id
            end
        end
        seen = {}
        for i = 1, MAX_OBSERVED do
            local row = type(store.observed) == "table" and store.observed[i]
            if type(row) == "table" then
                local id, area = Model.Item(row.id), Model.Text(row.area, 120)
                local seenAt = Model.Number(row.at, math.max(0, at - MAX_AGE), at + 300)
                local key = id and area and (id .. ":" .. area)
                if key and seenAt and not seen[key] then
                    seen[key] = true
                    observed[#observed + 1] = { id = id, area = area, at = seenAt }
                end
            end
        end
    end
    store.version, store.favorites, store.observed = 1, favorites, observed
    return store
end

function Model.Favorite(store, value)
    local id = Model.Item(value)
    if not store or not id then return nil end
    for i, candidate in ipairs(store.favorites) do
        if id == candidate then
            table.remove(store.favorites, i)
            return false
        end
    end
    if #store.favorites >= MAX_FAVORITES then return nil, "limit" end
    table.insert(store.favorites, 1, id)
    return true
end

function Model.Observe(store, value, location, at)
    local id, area = Model.Item(value), Model.Text(location, 120)
    if not store or not id or not area then return false end
    for i = #store.observed, 1, -1 do
        local row = store.observed[i]
        if row.at < at - MAX_AGE or (row.id == id and row.area == area) then
            table.remove(store.observed, i)
        end
    end
    table.insert(store.observed, 1, { id = id, area = area, at = at })
    store.observed[MAX_OBSERVED + 1] = nil
    return true
end
