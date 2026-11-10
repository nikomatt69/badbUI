-- BadbUI - Macros: catalog of ready-made macros per class, specialization and content (PvE / PvP).
--
-- Every catalog entry (Data/Macros.lua) can be turned on and off: turning it on creates the macro in the
-- game's /macro panel (character slots first, then general slots), turning it off deletes it.
-- BadbUI only touches the macros it created: a user macro with the same name is never overwritten,
-- and a catalog macro edited by hand is never deleted.
--
-- Badb.Macros is an API table separate from the module descriptor (ModuleProto already has Get(path)).
-- It exists as soon as this file loads, so Data/Macros.lua can register its packs right away.
--
-- Facts and limits (see docs/macros.md): 255 characters per macro, 16 for the name, no creating or
-- editing in combat. Spell names in the body are wrapped in braces ({Charge}); the braces are removed
-- on creation and the name is replaced by a user-saved translation, if any (non-English clients).
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger, Modules = Badb.Events, Badb.Logger, Badb.Modules

local X = Badb.Macros or {}
Badb.Macros = X

X.entries, X.order, X.names = {}, {}, {}
X.LIMITS = { name = 16, body = 255, title = 120, note = 300, entries = 12000, translations = 1000 }
X.ICON = "INV_Misc_QuestionMark" -- with #showtooltip the client shows the spell icon
X.MODES = { pve = true, pvp = true, any = true }
local LIM = X.LIMITS

X.CLASS_LABELS = { ALL = "General (all classes)", WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
X.SPEC_LABELS = { arms = "Arms", fury = "Fury", protection = "Protection", holy = "Holy", retribution = "Retribution",
    beastmastery = "Beast Mastery", marksmanship = "Marksmanship", survival = "Survival",
    assassination = "Assassination", combat = "Combat", subtlety = "Subtlety", discipline = "Discipline",
    shadow = "Shadow", elemental = "Elemental", enhancement = "Enhancement", restoration = "Restoration",
    arcane = "Arcane", fire = "Fire", frost = "Frost", affliction = "Affliction", demonology = "Demonology",
    destruction = "Destruction", balance = "Balance", feral = "Feral" }
local MODE_LABELS = { pve = "PvE", pvp = "PvP", any = "PvE and PvP" }
X.TARGET_CHOICES = {
    { value = "*", label = "All targets" }, { value = "focus", label = "Focus" },
    { value = "mouseover", label = "Mouseover" }, { value = "self", label = "Self" },
    { value = "party", label = "Party / arena teammates" }, { value = "raid", label = "Raid members (1-40)" },
    { value = "boss", label = "Bosses (1-5)" }, { value = "assist", label = "Assist / target of target" },
    { value = "arena", label = "Arena enemies (compatibility)" },
}

---------------------------------------------------------------------------
-- 1. Catalog: validation and registration (pure logic)
---------------------------------------------------------------------------

local function classInfo(token) return Badb.Player and Badb.Player:GetClassInfo(token) end

local function hasSpec(class, spec)
    local info = classInfo(class)
    if not info then return false end
    for _, t in ipairs(info.trees) do if t.key == spec then return true end end
    return false
end

local function slug(s) return (s:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")) end

local function plain(body) return (body:gsub("{([^{}\n]+)}", "%1")) end

local function spellsOf(body)
    local list, seen = {}, {}
    for s in body:gmatch("{([^{}\n]+)}") do
        if not seen[s] then seen[s] = true; list[#list + 1] = s end
    end
    return list
end

local function targetsOf(body)
    local targets = {}
    for unit in body:gmatch("@([%w]+)") do
        if unit == "focus" or unit == "mouseover" then targets[unit] = true end
        if unit == "player" then targets.self = true end
        for _, group in ipairs({ "party", "raid", "boss", "arena" }) do
            if unit:match("^" .. group .. "%d+$") or unit:match("^" .. group .. "pet%d+$") then targets[group] = true end
        end
        if unit:match("target$") and unit ~= "target" then targets.assist = true end
    end
    if body:match("/assist%s") then targets.assist = true end
    return targets
end

-- def = { class = "WARRIOR"|...|"ALL", spec = tree key | nil (whole class), mode = "pve"|"pvp"|"any",
--         name = in-game name (max 16), title = short description, body = text with {Spell}, note = optional }
function X:Register(def)
    if type(def) ~= "table" then return false, "invalid definition" end
    local class, spec, mode = def.class, def.spec, def.mode or "any"
    if class ~= "ALL" and not classInfo(class) then return false, "unknown class: " .. tostring(class) end
    if spec ~= nil and not hasSpec(class, spec) then return false, "unknown specialization: " .. tostring(spec) end
    if not self.MODES[mode] then return false, "invalid content: " .. tostring(mode) end
    local name, body, title = def.name, def.body, def.title
    if type(name) ~= "string" or #name < 1 or #name > LIM.name or name:find("[%c|]") then
        return false, "invalid name (1-" .. LIM.name .. " characters): " .. tostring(name)
    end
    if type(body) ~= "string" or body:match("^%s*$") or body:find("|", 1, true) then return false, "invalid body: " .. name end
    if #plain(body) > LIM.body then return false, "body over " .. LIM.body .. " characters: " .. name end
    if type(title) ~= "string" or #title < 1 or #title > LIM.title then return false, "invalid title: " .. name end
    if def.note ~= nil and (type(def.note) ~= "string" or #def.note > LIM.note) then return false, "invalid note: " .. name end
    if #self.order >= LIM.entries then return false, "catalog full" end
    local id = type(def.id) == "string" and def.id or (class:lower() .. ":" .. slug(name))
    if self.entries[id] then return false, "duplicate macro: " .. id end
    -- The in-game name identifies the macro: unique across the class and the general ones.
    local lname = name:lower()
    for otherClass in pairs(self.names[lname] or {}) do
        if otherClass == class or otherClass == "ALL" or class == "ALL" then return false, "name already used: " .. name end
    end
    self.names[lname] = self.names[lname] or {}
    self.names[lname][class] = id
    local e = { id = id, class = class, spec = spec, mode = mode, name = name, title = title, body = body,
                note = def.note, spells = spellsOf(body), targets = targetsOf(body), index = #self.order + 1 }
    self.entries[id] = e
    self.order[#self.order + 1] = id
    return true, id
end

-- pack = { [tree key | "all"] = { pve = {...}, pvp = {...}, any = {...} } }, entry = { name, title, body, note? }
-- Returns how many entries were registered and the list of errors (never a Lua error).
function X:RegisterPack(class, pack)
    local added, errors = 0, {}
    if type(pack) ~= "table" then return 0, { "invalid pack" } end
    local scopes = { "all" }
    local info = classInfo(class)
    for _, t in ipairs(info and info.trees or {}) do scopes[#scopes + 1] = t.key end
    for _, scope in ipairs(scopes) do
        local byMode = pack[scope]
        if type(byMode) == "table" then
            for _, mode in ipairs({ "any", "pve", "pvp" }) do
                for _, row in ipairs(type(byMode[mode]) == "table" and byMode[mode] or {}) do
                    local ok, err = self:Register({ class = class, spec = scope ~= "all" and scope or nil, mode = mode,
                        name = type(row) == "table" and row[1] or nil, title = type(row) == "table" and row[2] or nil,
                        body = type(row) == "table" and row[3] or nil, note = type(row) == "table" and row[4] or nil })
                    if ok then added = added + 1 else errors[#errors + 1] = tostring(err) end
                end
            end
        end
    end
    for _, err in ipairs(errors) do Logger:Error("Macros %s: %s", tostring(class), err) end
    return added, errors
end

function X:Get(id) return type(id) == "string" and self.entries[id] or nil end

-- filter = { class, spec, mode, search, target, includeShared? }
-- A spec normally selects only that tree; includeShared also includes class-wide entries.
-- With `mode`, "any" entries stay included. Order: catalog order.
function X:List(filter)
    filter = type(filter) == "table" and filter or {}
    local q = type(filter.search) == "string" and filter.search:lower() or nil
    if q == "" then q = nil end
    local out = {}
    for _, id in ipairs(self.order) do
        local e = self.entries[id]
        local ok = (filter.class == nil or e.class == filter.class)
        if ok and filter.spec ~= nil then
            if filter.spec == "all" then ok = e.spec == nil
            else ok = e.spec == filter.spec or (filter.includeShared == true and e.spec == nil) end
        end
        if ok and (filter.mode == "pve" or filter.mode == "pvp") then ok = e.mode == filter.mode or e.mode == "any" end
        if ok and filter.target and filter.target ~= "*" then ok = e.targets[filter.target] == true end
        if ok and q then
            ok = e.name:lower():find(q, 1, true) ~= nil or e.title:lower():find(q, 1, true) ~= nil
                or e.body:lower():find(q, 1, true) ~= nil
        end
        if ok then out[#out + 1] = e end
    end
    return out
end

-- Finds by exact id or by in-game name (case-insensitive), preferring the given class, then the general ones.
function X:Find(text, class)
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    if self.entries[text] then return self.entries[text] end
    local byClass = self.names[text:lower()]
    if not byClass then return nil end
    local id = (class and byClass[class]) or byClass.ALL
    if not id then
        local n = 0
        for _, v in pairs(byClass) do n = n + 1; id = v end
        if n ~= 1 then return nil end
    end
    return self.entries[id]
end

---------------------------------------------------------------------------
-- 2. Saved state (Badb.DB.sv.global.macros: game macros do not depend on the BadbUI profile)
---------------------------------------------------------------------------

local function state()
    local sv = Badb.DB and Badb.DB.sv
    if not sv then return nil end
    local st = sv.global.macros
    if type(st) ~= "table" then st = {}; sv.global.macros = st end
    st.version = 1
    if type(st.chars) ~= "table" then st.chars = {} end
    if type(st.spellNames) ~= "table" then st.spellNames = {} end
    if type(st.bodies) ~= "table" then st.bodies = {} end
    return st
end

local function charState()
    local st = state()
    local key = st and Badb.DB.char
    if type(key) ~= "string" then return nil end
    if type(st.chars[key]) ~= "table" then st.chars[key] = {} end
    return st.chars[key]
end

-- Final body: customized version (if saved) with translated spell names.
function X:Render(id)
    local e = self:Get(id)
    if not e then return nil, "unknown macro" end
    local st = state()
    local src = st and type(st.bodies[id]) == "string" and st.bodies[id] or e.body
    local map = st and st.spellNames or {}
    local out = src:gsub("{([^{}\n]+)}", function(s)
        local t = map[s]
        return (type(t) == "string" and t ~= "") and t or s
    end)
    if #out > LIM.body then return nil, "text is over " .. LIM.body .. " characters (" .. #out .. ")" end
    return out
end

-- Spell translation (non-English clients): Macros:SetSpellName("Charge", "Carica"). Empty string or nil removes it.
function X:SetSpellName(english, localName)
    local st = state()
    if not st then return false, "database not ready" end
    if type(english) ~= "string" or english == "" or #english > 80 or english:find("[{}|%c]") then return false, "invalid name" end
    if localName == nil or localName == "" then st.spellNames[english] = nil; return true end
    if type(localName) ~= "string" or #localName > 80 or localName:find("[{}|%c]") then return false, "invalid translation" end
    if st.spellNames[english] == nil then
        local n = 0
        for _ in pairs(st.spellNames) do n = n + 1 end
        if n >= LIM.translations then return false, "too many translations" end
    end
    st.spellNames[english] = localName
    return true
end

function X:GetSpellName(english)
    local st = state()
    return st and st.spellNames[english] or nil
end

-- Custom text for an entry (nil or same as the original = back to the catalog). Applies from the next time it is turned on.
function X:SetBody(id, body)
    local e, st = self:Get(id), state()
    if not e then return false, "unknown macro" end
    if not st then return false, "database not ready" end
    if body == nil or body == e.body then st.bodies[id] = nil; return true end
    if type(body) ~= "string" or body:match("^%s*$") or body:find("|", 1, true) then return false, "invalid text" end
    if #plain(body) > LIM.body then return false, "text is over " .. LIM.body .. " characters" end
    st.bodies[id] = body
    return true
end

function X:IsCustomized(id)
    local st = state()
    return st ~= nil and type(st.bodies[id]) == "string"
end

---------------------------------------------------------------------------
-- 3. Client macro API (probed: none is verified on Forever)
---------------------------------------------------------------------------

local function apiReady()
    return type(CreateMacro) == "function" and type(DeleteMacro) == "function" and type(GetMacroIndexByName) == "function"
end
X.IsSupported = function() return apiReady() end

local function macroIndex(name)
    if type(GetMacroIndexByName) ~= "function" then return nil end
    local ok, i = pcall(GetMacroIndexByName, name)
    i = ok and tonumber(i) or 0
    return i > 0 and i or nil
end

local function macroBody(idx)
    if type(GetMacroInfo) ~= "function" then return nil end
    local ok, _, _, body = pcall(GetMacroInfo, idx)
    return ok and type(body) == "string" and body or nil
end

local function norm(s) return (tostring(s or ""):gsub("\r", ""):gsub("%s+$", "")) end

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- { account = used, accountMax, char = used, charMax }
function X:Slots()
    local acc, chr = 0, 0
    if type(GetNumMacros) == "function" then
        local ok, a, c = pcall(GetNumMacros)
        if ok then acc, chr = tonumber(a) or 0, tonumber(c) or 0 end
    end
    return { account = acc, accountMax = tonumber(MAX_ACCOUNT_MACROS) or 120,
             char = chr, charMax = tonumber(MAX_CHARACTER_MACROS) or 18 }
end

-- true / false when the client can tell whether the spell is in the spellbook, nil when it cannot.
local function spellKnown(name)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok then return info ~= nil end
    end
    if type(GetSpellInfo) == "function" then
        local ok, n = pcall(GetSpellInfo, name)
        if ok then return n ~= nil end
    end
    return nil
end

-- Spells of the macro the client cannot find (not learned yet, or name needs translating). nil = cannot be checked.
function X:MissingSpells(id)
    local e = self:Get(id)
    if not e then return nil end
    local st, missing, checked = state(), {}, false
    for _, s in ipairs(e.spells) do
        local name = st and st.spellNames[s] or s
        local known = spellKnown(name)
        if known ~= nil then checked = true end
        if known == false then missing[#missing + 1] = name end
    end
    if not checked and #e.spells > 0 then return nil end
    return missing
end

---------------------------------------------------------------------------
-- 4. Turn on / off
---------------------------------------------------------------------------

function X:IsActive(id)
    local cs = charState()
    local rec = cs and cs[id]
    if type(rec) ~= "table" or type(rec.name) ~= "string" then return false end
    if not apiReady() then return false end
    if macroIndex(rec.name) then return true end
    cs[id] = nil -- deleted by hand from the /macro panel: no longer ours
    return false
end

local function changed() Events:Fire("BADB_MACROS_CHANGED") end

function X:Enable(id)
    local e = self:Get(id)
    if not e then return false, "unknown macro" end
    if not apiReady() then return false, "this client does not let addons create macros" end
    local cs = charState()
    if not cs then return false, "database not ready" end
    local class = Badb.Player and Badb.Player:GetClass()
    if e.class ~= "ALL" and class and class ~= e.class then
        return false, (self.CLASS_LABELS[e.class] or e.class) .. " macro: not for this character"
    end
    if self:IsActive(id) then return true end
    if inCombat() then return false, "macros cannot be created in combat" end
    local body, err = self:Render(id)
    if not body then return false, err end
    local idx = macroIndex(e.name)
    if idx then
        -- Same name already present: adopt it only if identical, otherwise it belongs to the user.
        if norm(macroBody(idx)) ~= norm(body) then
            return false, "you already have a macro named '" .. e.name .. "': rename or delete it"
        end
        cs[id] = { name = e.name, body = body, adopted = true }
        changed()
        return true
    end
    local slots = self:Slots()
    local perChar
    if slots.char < slots.charMax then perChar = true
    elseif slots.account < slots.accountMax then perChar = false
    else return false, "macro slots are full (" .. slots.charMax .. " character and " .. slots.accountMax .. " general)" end
    local ok, res = pcall(CreateMacro, e.name, self.ICON, body, perChar)
    if not ok or not macroIndex(e.name) then
        return false, "the client rejected the macro" .. ((not ok and res) and (": " .. tostring(res)) or "")
    end
    cs[id] = { name = e.name, body = body, perChar = perChar }
    changed()
    return true
end

-- Returns true, "kept" when the macro was edited by hand: it stays in the game and BadbUI stops managing it.
function X:Disable(id)
    local cs = charState()
    local rec = cs and cs[id]
    if type(rec) ~= "table" then return false, "macro is not on" end
    if not apiReady() then return false, "this client does not let addons delete macros" end
    local idx = macroIndex(rec.name)
    if not idx then cs[id] = nil; changed(); return true end
    if inCombat() then return false, "macros cannot be deleted in combat" end
    local current = macroBody(idx)
    if current ~= nil and norm(current) ~= norm(rec.body) then
        cs[id] = nil
        changed()
        return true, "kept"
    end
    local ok, err = pcall(DeleteMacro, idx)
    if not ok then return false, "the client rejected the deletion: " .. tostring(err) end
    cs[id] = nil
    changed()
    return true
end

function X:SetActive(id, value)
    if value then return self:Enable(id) end
    return self:Disable(id)
end

function X:Toggle(id) return self:SetActive(id, not self:IsActive(id)) end

-- Turns on every entry matching the filter. Returns { on = n, failed = n, errors = { "name: reason", ... } }.
function X:EnableAll(filter)
    local res = { on = 0, failed = 0, errors = {} }
    for _, e in ipairs(self:List(filter)) do
        local ok, err = self:Enable(e.id)
        if ok then res.on = res.on + 1
        else
            res.failed = res.failed + 1
            if #res.errors < 5 then res.errors[#res.errors + 1] = e.name .. ": " .. tostring(err) end
        end
    end
    return res
end

-- Turns off this character's active macros (all of them, or only the ones matching the filter).
function X:DisableAll(filter)
    local res = { off = 0, kept = 0, failed = 0 }
    local cs = charState()
    if not cs then return res end
    local only
    if filter then
        only = {}
        for _, e in ipairs(self:List(filter)) do only[e.id] = true end
    end
    local ids = {}
    for id in pairs(cs) do if not only or only[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local ok, how = self:Disable(id)
        if not ok then res.failed = res.failed + 1
        elseif how == "kept" then res.kept = res.kept + 1
        else res.off = res.off + 1 end
    end
    return res
end

function X:ActiveCount()
    local n = 0
    for id in pairs(charState() or {}) do if self:IsActive(id) then n = n + 1 end end
    return n
end

-- Puts the macro on the cursor, ready to drop on an action bar.
function X:Pickup(id)
    local cs = charState()
    local rec = cs and cs[id]
    if type(rec) ~= "table" or not self:IsActive(id) then return false, "turn the macro on first" end
    if type(PickupMacro) ~= "function" then return false, "open /macro and drag it from there" end
    if inCombat() then return false, "not in combat" end
    local ok, err = pcall(PickupMacro, macroIndex(rec.name))
    if not ok then return false, tostring(err) end
    return true
end

---------------------------------------------------------------------------
-- 5. ConfigUI page
---------------------------------------------------------------------------

X.PAGE_SIZE = 100 -- The shared list widget displays at most 300 rows.
X.view = { class = nil, spec = "*", mode = "*", target = "*", search = "", includeShared = true, page = 1 }
local view = X.view

local function setView(key, value)
    view[key], view.page = value, 1
end

local function toast(text, level)
    local UI = Badb.ConfigUI
    if UI and UI.Toast then UI:Toast(text, level) else Logger:Info("%s", text) end
end

local function viewClass()
    if not view.class then
        local c = Badb.Player and Badb.Player:GetClass()
        view.class = classInfo(c) and c or "WARRIOR"
        local snap = Badb.Player and Badb.Player:GetSnapshot()
        if snap and snap.treeKey and hasSpec(view.class, snap.treeKey) then view.spec = snap.treeKey end
    end
    return view.class
end

function X.viewFilter()
    local f = { class = viewClass() }
    if view.spec ~= "*" then f.spec = view.spec end
    if view.mode ~= "*" then f.mode = view.mode end
    if view.target ~= "*" then f.target = view.target end
    f.search, f.includeShared = view.search, view.includeShared
    return f
end

function X.pageInfo(count)
    count = count or #X:List(X.viewFilter())
    local pages = math.max(1, math.ceil(count / X.PAGE_SIZE))
    view.page = math.max(1, math.min(pages, math.floor(tonumber(view.page) or 1)))
    return view.page, pages, count
end

function X.pageChoices()
    local _, pages = X.pageInfo()
    local out = {}
    for i = 1, pages do out[i] = { value = i, label = i .. " / " .. pages } end
    return out
end

function X.classChoices()
    local out = {}
    for _, c in ipairs(Badb.Player and Badb.Player.CLASSES or {}) do
        out[#out + 1] = { value = c.token, label = X.CLASS_LABELS[c.token] or c.token }
    end
    out[#out + 1] = { value = "ALL", label = X.CLASS_LABELS.ALL }
    return out
end

function X.specChoices()
    local out = { { value = "*", label = "All" } }
    local info = classInfo(viewClass())
    if info then
        out[#out + 1] = { value = "all", label = "Shared by the whole class" }
        for _, t in ipairs(info.trees) do out[#out + 1] = { value = t.key, label = X.SPEC_LABELS[t.key] or t.key } end
    end
    return out
end

local function esc(s) return (tostring(s or ""):gsub("|", "||")) end

local function scopeLabel(e)
    local where = e.spec and (X.SPEC_LABELS[e.spec] or e.spec) or (e.class == "ALL" and "general" or "class")
    return where .. (e.mode ~= "any" and (" " .. MODE_LABELS[e.mode]) or "")
end

function X.describe(id)
    local e = X:Get(id)
    if not e then return "" end
    local body = X:Render(id) or plain(e.body)
    local lines = { e.name .. " - " .. e.title, "(" .. scopeLabel(e) .. ")", "", body }
    if e.note then lines[#lines + 1] = ""; lines[#lines + 1] = "Note: " .. e.note end
    local missing = X:MissingSpells(id)
    if missing and #missing > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Spells not found in your spellbook (not learned yet, or the client is not English): "
            .. table.concat(missing, ", ")
    end
    return table.concat(lines, "\n")
end

local function showCode(e)
    local UI = Badb.ConfigUI
    if not (UI and UI.TextBox) then return end
    UI.TextBox("Macro: " .. e.name .. " - edit the text and save (applies the next time you turn it on)",
        X:Render(e.id) or plain(e.body), function(text)
            text = norm(text)
            if text == norm(X:Render(e.id) or "") then return end
            local ok, err = X:SetBody(e.id, text)
            toast(ok and ("Text of '" .. e.name .. "' saved: turn the macro off and on to use it")
                or ("Not saved: " .. tostring(err)), ok and "ok" or "error")
        end, "Save")
end

function X.rows()
    local rows = {}
    local class = Badb.Player and Badb.Player:GetClass()
    local entries = X:List(X.viewFilter())
    local page = X.pageInfo(#entries)
    for i = (page - 1) * X.PAGE_SIZE + 1, math.min(page * X.PAGE_SIZE, #entries) do
        local e = entries[i]
        local on = X:IsActive(e.id)
        local usable = e.class == "ALL" or not class or class == e.class
        local detail = on and "|cff5fd068on|r" or "|cff888888off|r"
        if view.spec == "*" or view.mode == "*" or (view.includeShared and not e.spec) then detail = detail .. "  " .. scopeLabel(e) end
        if X:IsCustomized(e.id) then detail = detail .. "  |cff3fa7ffcustomized|r" end
        if e.targets.arena then detail = detail .. "  |cffffcc00arena compatibility template|r" end
        local acts = {
            { label = "Code", width = 54, noRefresh = true, func = function() showCode(e) end },
        }
        if on then
            acts[#acts + 1] = { label = "Pick up", width = 54, noRefresh = true, func = function()
                local ok, err = X:Pickup(e.id)
                if ok then toast("'" .. e.name .. "' is on your cursor: drop it on an action bar", "info")
                else toast(tostring(err), "warn") end
            end }
        end
        acts[#acts + 1] = { label = on and "Turn off" or "Turn on", width = 62, disabled = not usable, func = function()
            local ok, err = X:SetActive(e.id, not on)
            if not ok then toast(e.name .. ": " .. tostring(err), "error")
            elseif err == "kept" then toast("'" .. e.name .. "' was edited by hand: it stays in /macro", "warn") end
        end }
        rows[#rows + 1] = { text = esc(e.name) .. "  |cffaaaaaa" .. esc(e.title) .. "|r", detail = detail, actions = acts,
                            id = e.id, onClick = function() showCode(e) end }
    end
    return rows
end

function X.summary()
    local s = X:Slots()
    local page, pages, shown = X.pageInfo()
    local text = string.format("Catalog: |cff3fa7ff%d|r macros, %d listed, %d on for this character.  "
        .. "Slots: character %d/%d, general %d/%d. Page %d/%d.",
        #X.order, shown, X:ActiveCount(), s.char, s.charMax, s.account, s.accountMax, page, pages)
    if not apiReady() then text = text .. "\n|cffff6060This client does not expose the macro creation API: the catalog is read-only.|r" end
    local class = Badb.Player and Badb.Player:GetClass()
    if class and view.class ~= "ALL" and view.class ~= class then
        text = text .. "\n|cffffcc00You are viewing another class: you can read the code but not turn the macros on.|r"
    end
    return text
end

function X.pageOptions(refresh)
    refresh = refresh or function() end
    return {
        { type = "label", text = X.summary },
        { type = "select", label = "Class", values = X.classChoices, get = function() return viewClass() end,
          set = function(v) setView("class", v); view.spec = "*"; refresh() end },
        { type = "select", label = "Specialization", values = X.specChoices, get = function() return view.spec end,
          set = function(v) setView("spec", v); refresh() end, hidden = function() return viewClass() == "ALL" end },
        { type = "toggle", label = "Include shared class macros", get = function() return view.includeShared end,
          set = function(v) setView("includeShared", v); refresh() end,
          hidden = function() return viewClass() == "ALL" or view.spec == "*" or view.spec == "all" end },
        { type = "select", label = "Content", get = function() return view.mode end,
          values = { { value = "*", label = "PvE and PvP" }, { value = "pve", label = "PvE only" }, { value = "pvp", label = "PvP only" } },
          set = function(v) setView("mode", v); refresh() end },
        { type = "select", label = "Target / variant", values = X.TARGET_CHOICES,
          get = function() return view.target end, set = function(v) setView("target", v); refresh() end },
        { type = "text", label = "Search name, spell or unit (press Enter)", width = 360, maxLetters = 100,
          get = function() return view.search end, set = function(v) setView("search", v); refresh() end },
        { type = "select", label = "Page (100 macros per page)", values = X.pageChoices,
          get = function() return X.pageInfo() end, set = function(v) view.page = v; refresh() end },
        { type = "list", height = 330, empty = "No macros for this selection", items = X.rows },
        { type = "execute", label = "Turn on all filtered", func = function()
            local r = X:EnableAll(X.viewFilter())
            toast(string.format("%d turned on, %d failed%s", r.on, r.failed, r.errors[1] and (" (" .. r.errors[1] .. ")") or ""),
                r.failed > 0 and "warn" or "ok")
            refresh()
        end },
        { type = "execute", label = "Turn off all filtered", func = function()
            local r = X:DisableAll(X.viewFilter())
            toast(string.format("%d turned off, %d kept (edited by hand), %d failed", r.off, r.kept, r.failed),
                r.failed > 0 and "warn" or "ok")
            refresh()
        end },
        { type = "label", small = true, text = "Turn on = the macro appears in /macro (character slots first). "
            .. "'Pick up' puts it on your cursor to drop on an action bar; click the row or 'Code' to read and edit it. "
            .. "Spell names are English: on a client in another language use "
            .. "/badb macro name Charge = <local name> or edit the text. No changes in combat. "
            .. "Raid numbers follow the roster. Arena entries require an arena-enabled client; Forever currently has no arenas. "
            .. "The catalog can exceed your available macro slots: filter it and turn on the entries you need." },
    }
end

local function buildPage(parent, ctx)
    local group
    local function refresh() if group then group:Refresh() end end
    local h, _, g = Badb.Widgets:Build(parent, nil, 8, X.pageOptions(refresh))
    group = g
    if ctx and ctx.AddRefresh then ctx.AddRefresh(refresh) end
    return h + 16
end

---------------------------------------------------------------------------
-- 6. Module and /badb macro command
---------------------------------------------------------------------------

local M
local function command(args)
    args = strtrim(tostring(args or ""))
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local class = Badb.Player and Badb.Player:GetClass()
    local function out(fmt, ...) Logger:Info(fmt, ...) end
    if cmd == "" or cmd == "open" then
        local UI = Badb.ConfigUI
        if UI and UI.OpenPage then UI:OpenPage("Macros") end
    elseif cmd == "list" then
        local f = { class = class or "ALL" }
        local targets = {}
        for _, choice in ipairs(X.TARGET_CHOICES) do targets[choice.value] = true end
        for word in rest:lower():gmatch("%S+") do
            if word == "pve" or word == "pvp" then f.mode = word
            elseif word == "shared" then f.spec = "all"
            elseif word == "withshared" then f.includeShared = true
            elseif targets[word] then f.target = word
            elseif hasSpec(f.class, word) then f.spec = word end
        end
        local list = X:List(f)
        out("%d macros (%s)", #list, X.CLASS_LABELS[f.class] or f.class)
        for i, e in ipairs(list) do
            if i > 60 then out("... %d more: open /badb macro", #list - 60); break end
            out("%s %s - %s [%s]", X:IsActive(e.id) and "[x]" or "[ ]", e.name, e.title, scopeLabel(e))
        end
    elseif cmd == "on" or cmd == "off" then
        local e = X:Find(rest, class)
        if not e then Logger:Warn("Macro not found: %s", rest); return end
        local ok, err = X:SetActive(e.id, cmd == "on")
        if ok then out("%s: %s", e.name, cmd == "on" and "on" or (err == "kept" and "kept in /macro (edited by hand)" or "off"))
        else Logger:Warn("%s: %s", e.name, tostring(err)) end
    elseif cmd == "show" then
        local e = X:Find(rest, class)
        if not e then Logger:Warn("Macro not found: %s", rest); return end
        for line in (X.describe(e.id) .. "\n"):gmatch("(.-)\n") do out("%s", line) end
    elseif cmd == "alloff" then
        local r = X:DisableAll()
        out("%d turned off, %d kept, %d failed", r.off, r.kept, r.failed)
    elseif cmd == "name" then
        local en, loc = rest:match("^(.-)%s*=%s*(.-)$")
        if not en or en == "" then Logger:Warn("Usage: /badb macro name Charge = <local name> (empty after = to remove)"); return end
        local ok, err = X:SetSpellName(en, loc)
        if ok then out("%s -> %s (applies to macros turned on from now)", en, loc ~= "" and loc or "(original)")
        else Logger:Warn("%s", tostring(err)) end
    else
        Logger:Warn("Usage: /badb macro [list [spec] [pve|pvp] [focus|party|raid|boss|arena|assist] [withshared] | on <name> | off <name> | show <name> | alloff | name <english> = <local>]")
    end
end

M = Modules:New("Macros", {
    title = "Macro catalog",
    category = L["Contenuti"],
    description = "Ready-made macros for every class and specialization, PvE and PvP: turn them on and off from the catalog.",
    defaults = { enabled = true },
    page = { title = "Macros", order = 30, category = L["Contenuti"], build = buildPage,
             keywords = { "macro", "macros", "class", "spec", "pvp", "pve", "mouseover", "focus", "interrupt", "party", "raid", "boss", "arena" } },
    commands = {
        macro = { help = "macro [list|on|off|show|alloff|name] - macro catalog per class and spec", fn = command },
    },
})
X.module = M
-- Disabling the module does NOT delete macros already created: they sit on the user's bars (see docs/macros.md).
