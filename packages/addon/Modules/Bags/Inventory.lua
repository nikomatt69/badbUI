-- Lettura dei contenitori e archivio locale.
local _, ns = ...
local Badb = ns.Badb
local Compat, L = Badb.Compat, Badb.L

local Inventory = {}
ns.BagsInventory = Inventory

local SCHEMA_VERSION = 1
local MAX_CHARACTERS = 24
local MAX_AGE = 90 * 24 * 60 * 60
local MAX_CONTAINER = 256
local MAX_SOURCE = 1024
local MAX_STACK = 1000000
local MAX_ID = 2147483647
local MAX_TIMESTAMP = 4102444800
local SOURCES = { "bags", "bank" }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return Compat.SafeValue(value) end
end

local function integer(value, min, max)
    value = Compat.SafeValue(value)
    if type(value) == "number" and value >= min and value <= max and value == math.floor(value) then
        return value
    end
end

local function plainText(value, limit)
    value = Compat.SafeValue(value)
    if type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%c|]") then
        return value
    end
end

local function itemLink(value, id)
    value = Compat.SafeValue(value)
    if type(value) ~= "string" or #value > 512 then return nil end
    local reference, name = value:match("^|c%x%x%x%x%x%x%x%x|H(item:[%d:%-]+)|h%[([^%c|]+)%]|h|r$")
    if reference and tonumber(reference:match("^item:(%d+)")) == id then
        return value, reference, plainText(name, 160)
    end
end

local function now()
    return integer(call(GetServerTime), 1, MAX_TIMESTAMP) or integer(call(time), 1, MAX_TIMESTAMP)
end

function Inventory.Available()
    local container = C_Container
    return type(container) == "table"
        and type(container.GetContainerNumSlots) == "function"
        and type(container.GetContainerItemInfo) == "function"
end

function Inventory.Character()
    local name = plainText(call(UnitName, "player"), 80)
    local realm = plainText(call(GetRealmName), 120)
    if not (name and realm) then return nil end
    return name .. "-" .. realm, name, realm
end

local function containers(source)
    local enum = Enum and Enum.BagIndex or {}
    local ids, seen = {}, {}
    local function add(id)
        id = integer(id, -100, 255)
        if id and not seen[id] then
            ids[#ids + 1] = id
            seen[id] = true
        end
    end
    local regular = integer(NUM_BAG_SLOTS, 1, 8) or 4
    if source == "bags" then
        add(Compat.SafeValue(enum.Backpack, 0) or 0)
        for i = 1, regular do add(Compat.SafeValue(enum["Bag_" .. i], i) or i) end
        add(enum.ReagentBag)
        add(enum.Keyring)
    else
        for i = 1, 9 do add(enum["CharacterBankTab_" .. i]) end
        if #ids == 0 then
            add(enum.Bank)
            for i = 1, integer(NUM_BANKBAGSLOTS, 0, 9) or 0 do add(regular + i) end
        end
    end
    return ids
end

local function safeItem(info)
    local id = integer(info.itemID, 1, MAX_ID)
    local count = integer(info.stackCount, 1, MAX_STACK)
    if not id or not count then return nil end
    local link, reference, name = itemLink(info.hyperlink, id)
    if not name then
        local getName = C_Item and C_Item.GetItemNameByID
        local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        name = plainText(call(getName, id), 160) or plainText(call(getInfo, id), 160)
    end
    return {
        id = id, count = count, name = name, link = link,
        icon = integer(info.iconFileID, 1, MAX_ID),
    }, reference or ("item:" .. id)
end

function Inventory.Scan(source)
    if not Inventory.Available() then return nil end
    local snapshot = { capacity = 0, occupied = 0, items = {}, time = now() }
    local byReference, missingNames = {}, {}
    local keyring = Enum and Enum.BagIndex and Compat.SafeValue(Enum.BagIndex.Keyring)
    for _, bag in ipairs(containers(source)) do
        local size
        if bag == keyring and type(GetKeyRingSize) == "function" then size = call(GetKeyRingSize)
        else size = call(C_Container.GetContainerNumSlots, bag) end
        size = integer(size, 0, MAX_CONTAINER)
        if not size or snapshot.capacity + size > MAX_SOURCE then return nil end
        snapshot.capacity = snapshot.capacity + size
        for slot = 1, size do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if not ok or Compat.IsSecret(info) then return nil end
            if info ~= nil then
                if type(info) ~= "table" then return nil end
                local item, reference = safeItem(info)
                if not item then return nil end
                snapshot.occupied = snapshot.occupied + 1
                if not item.name then missingNames[item.id] = true end
                local existing = byReference[reference]
                if existing then
                    existing.count = existing.count + item.count
                    existing.name = existing.name or item.name
                    existing.icon = existing.icon or item.icon
                else
                    byReference[reference] = item
                    snapshot.items[#snapshot.items + 1] = item
                end
            end
        end
    end
    if snapshot.capacity == 0 then return nil end
    return snapshot, missingNames
end

local function cleanSnapshot(value, oldest, latest)
    if type(value) ~= "table" then return nil end
    local capacity = integer(value.capacity, 1, MAX_SOURCE)
    local timestamp = integer(value.time, oldest, latest)
    local occupied = capacity and integer(value.occupied, 0, capacity)
    if not (capacity and timestamp and occupied and type(value.items) == "table") then return nil end
    local items = {}
    for i = 1, occupied do
        local entry = value.items[i]
        if type(entry) == "table" then
            local id = integer(entry.id, 1, MAX_ID)
            local count = integer(entry.count, 1, MAX_STACK * MAX_SOURCE)
            if id and count then
                local link, _, linkName = itemLink(entry.link, id)
                items[#items + 1] = {
                    id = id, count = count, link = link, name = plainText(entry.name, 160) or linkName,
                    icon = integer(entry.icon, 1, MAX_ID),
                }
            end
        end
    end
    return { capacity = capacity, occupied = occupied, time = timestamp, items = items }
end

local function latestCapture(character)
    return math.max(character.bags and character.bags.time or 0, character.bank and character.bank.time or 0)
end

local function prune(characters, keep)
    local keys = {}
    for key in pairs(characters) do
        if key ~= keep then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local left, right = latestCapture(characters[a]), latestCapture(characters[b])
        if left ~= right then return left > right end
        return a < b
    end)
    local limit = keep and characters[keep] and MAX_CHARACTERS - 1 or MAX_CHARACTERS
    for i = limit + 1, #keys do characters[keys[i]] = nil end
end

function Inventory.OpenStore(store)
    local characters = {}
    if type(store.version) == "number" and store.version > SCHEMA_VERSION then return characters end
    if store.version == SCHEMA_VERSION and type(store.characters) == "table" then
        local latest = now()
        local oldest = latest and math.max(1, latest - MAX_AGE) or 1
        for key, value in pairs(store.characters) do
            if plainText(key, 201) and type(value) == "table" then
                local name, realm = plainText(value.name, 80), plainText(value.realm, 120)
                if name and realm then
                    local character = { name = name, realm = realm }
                    for _, source in ipairs(SOURCES) do
                        character[source] = cleanSnapshot(value[source], oldest, latest and latest + 300 or MAX_TIMESTAMP)
                    end
                    if character.bags or character.bank then characters[key] = character end
                end
            end
        end
        prune(characters, Inventory.Character())
    end
    store.version, store.characters = SCHEMA_VERSION, characters
    return characters
end

function Inventory.Save(characters, key, name, realm, source, snapshot)
    if not (key and snapshot.time) then return end
    local isNew = characters[key] == nil
    local character = characters[key] or {}
    character.name, character.realm = name, realm
    character[source] = snapshot
    characters[key] = character
    if isNew then prune(characters, key) end
end

local function fold(value)
    if Badb.Guides and Badb.Guides.Fold then return Badb.Guides.Fold(value) end
    return value:lower()
end

function Inventory.Rows(characters, live, scope, characterKey, current, currentName, currentRealm)
    local rows, snapshots = {}, {}
    local function add(key, name, realm, character)
        for _, source in ipairs(SOURCES) do
            if scope == "all" or scope == source then
                local isLive = key == current and live[source] ~= nil
                local snapshot = isLive and live[source] or character[source]
                if snapshot then
                    snapshots[#snapshots + 1] = { snapshot = snapshot, live = isLive }
                    for _, item in ipairs(snapshot.items) do
                        local label = item.name or L["Oggetto %d"]:format(item.id)
                        rows[#rows + 1] = {
                            item = item, label = label, source = source, live = isLive, key = key,
                            owner = name .. " - " .. realm,
                            search = fold(label .. " " .. name .. " " .. realm .. " " .. item.id),
                        }
                    end
                end
            end
        end
    end
    for key, character in pairs(characters) do
        if characterKey == "all" or characterKey == key then
            add(key, character.name, character.realm, character)
        end
    end
    if current and not characters[current] and (characterKey == "all" or characterKey == current) then
        add(current, currentName, currentRealm, {})
    end
    table.sort(rows, function(a, b)
        if a.search ~= b.search then return a.search < b.search end
        if a.source ~= b.source then return a.source < b.source end
        if a.key ~= b.key then return a.key < b.key end
        return (a.item.link or "") < (b.item.link or "")
    end)
    return rows, snapshots
end

function Inventory.Filter(rows, query)
    local terms = {}
    if type(query) == "string" then
        for term in fold(query:sub(1, 120)):gmatch("%S+") do
            terms[#terms + 1] = term
            if #terms == 8 then break end
        end
    end
    if #terms == 0 then return rows end
    local found = {}
    for _, row in ipairs(rows) do
        local match = true
        for _, term in ipairs(terms) do
            if not row.search:find(term, 1, true) then
                match = false
                break
            end
        end
        if match then found[#found + 1] = row end
    end
    return found
end
