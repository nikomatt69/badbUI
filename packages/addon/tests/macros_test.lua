-- Macro catalog tests (engine, hand-written catalog and fixed-unit variants).
local function eq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected a truthy value", 2) end end

local T = {}
local function X() return BadbUI.Macros end

-- Simulated /macro panel: general and character slots, as in the client.
local function install(Mock, class)
    local G = { list = {}, created = 0, deleted = 0 }
    MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
    local function find(name) for i, m in ipairs(G.list) do if m.name == name then return i end end end
    function GetMacroIndexByName(name) return find(name) or 0 end
    function GetMacroInfo(i)
        local m = G.list[type(i) == "number" and i or find(i) or 0]
        if m then return m.name, m.icon, m.body end
    end
    function GetNumMacros()
        local a, c = 0, 0
        for _, m in ipairs(G.list) do if m.perChar then c = c + 1 else a = a + 1 end end
        return a, c
    end
    function CreateMacro(name, icon, body, perChar)
        if Mock.combat then error("in combat") end
        G.list[#G.list + 1] = { name = name, icon = icon, body = body, perChar = perChar and true or false }
        G.created = G.created + 1
        return #G.list
    end
    function DeleteMacro(i)
        if Mock.combat then error("in combat") end
        table.remove(G.list, type(i) == "number" and i or find(i))
        G.deleted = G.deleted + 1
    end
    function PickupMacro(i) G.picked = G.list[i] and G.list[i].name end
    if class then
        function UnitClass() return class, class end
        BadbUI.Player:Invalidate()
    end
    Mock.macros = G
    return G
end

T["catalog: no registration errors and lots of macros"] = function(Mock)
    for _, m in ipairs(Mock.chat) do truthy(not m:find("Macros", 1, true), "registration error: " .. m) end
    truthy(#X().order >= 6000, "catalog too small: " .. #X().order)
    truthy(#X().order < X().LIMITS.entries, "catalog has no room for extensions")
end

T["every class: shared + 3 specs, each with PvE and PvP"] = function()
    for _, c in ipairs(BadbUI.Player.CLASSES) do
        truthy(#X():List({ class = c.token, spec = "all" }) >= 15, c.token .. ": too few shared macros")
        truthy(#X():List({ class = c.token }) >= 400, c.token .. ": too few macros overall")
        for _, t in ipairs(c.trees) do
            for _, mode in ipairs({ "pve", "pvp" }) do
                local n = 0
                for _, e in ipairs(X():List({ class = c.token, spec = t.key })) do if e.mode == mode then n = n + 1 end end
                truthy(n >= 5, c.token .. "/" .. t.key .. "/" .. mode .. ": only " .. n)
                truthy(#X():List({ class = c.token, spec = t.key, mode = mode, includeShared = true }) >= 100,
                    c.token .. "/" .. t.key .. "/" .. mode .. ": insufficient variants including shared utilities")
            end
        end
    end
    truthy(#X():List({ class = "ALL" }) >= 20, "too few general macros")
end

T["every entry respects client limits and has a unique name within its class"] = function()
    local seen = {}
    for _, id in ipairs(X().order) do
        local e = X():Get(id)
        truthy(#e.name >= 1 and #e.name <= 16, "name: " .. e.name)
        local body = X():Render(id)
        truthy(body and #body <= 255, "body too long: " .. e.name)
        truthy(not body:find("[{}]"), "leftover braces: " .. e.name)
        truthy(body:sub(1, 1) == "/" or body:sub(1, 1) == "#", "first line: " .. e.name)
        for line in (body .. "\n"):gmatch("(.-)\n") do
            truthy(line:match("^[/#]%a"), e.name .. ": invalid line '" .. line .. "'")
            local open, close = select(2, line:gsub("%[", "")), select(2, line:gsub("%]", ""))
            eq(open, close, e.name .. ": square brackets")
        end
        if e.targets.arena then
            eq(e.mode, "pvp", "arena templates must stay out of PvE")
            truthy(e.note and e.note:find("arena-enabled client", 1, true), "missing compatibility note: " .. e.name)
        end
        local lname = e.name:lower()
        truthy(not seen[e.class .. "|" .. lname], "duplicate name: " .. e.name)
        seen[e.class .. "|" .. lname] = true
        if e.class ~= "ALL" then truthy(not seen["ALL|" .. lname], "name also used by the general macros: " .. e.name) end
    end
end

T["names updated for Forever: no removed spells"] = function()
    for _, id in ipairs(X().order) do
        local body = X():Get(id).body
        for _, gone in ipairs({ "Curse of Agony", "Curse of Doom", "Curse of Shadows", "Fire Nova Totem", "Tiger's Fury",
                                "Wyvern Sting", "Lightwell", "Tranquil Air Totem", "Blessing of Sanctuary", "Dark Pact" }) do
            truthy(not body:find(gone, 1, true), id .. " uses " .. gone)
        end
    end
end

T["filters: class, spec, content, search"] = function()
    for _, e in ipairs(X():List({ class = "MAGE", spec = "frost", mode = "pvp" })) do
        eq(e.class, "MAGE"); eq(e.spec, "frost"); truthy(e.mode == "pvp" or e.mode == "any")
    end
    for _, e in ipairs(X():List({ class = "MAGE", mode = "pve" })) do truthy(e.mode ~= "pvp", e.name) end
    local found = X():List({ class = "WARLOCK", search = "bane of agony" })
    truthy(#found >= 2, "search")
    eq(#X():List({ class = "MAGE", search = "zzzz" }), 0)
    eq(#X():List("not a table"), #X().order)
end

T["fixed enemy units: every class has focus, arena, boss and assist variants"] = function()
    local examples = {
        { "WARRIOR", "Pummel" }, { "PALADIN", "HoJ" }, { "HUNTER", "Concussive" },
        { "ROGUE", "Kick" }, { "PRIEST", "SW Pain" }, { "SHAMAN", "Earth Shock" },
        { "MAGE", "Counter" }, { "WARLOCK", "Fear" }, { "DRUID", "Roots" },
    }
    for _, sample in ipairs(examples) do
        local function check(suffix, unit, mode)
            local e = X():Find(sample[2] .. " " .. suffix, sample[1])
            truthy(e, sample[1] .. ": missing " .. suffix)
            eq(e.mode, mode)
            local body = X():Render(e.id)
            truthy(body:find("[@" .. unit .. ",harm,nodead]", 1, true), e.name .. ": incorrect unit")
            truthy(not body:find("[]", 1, true), e.name .. ": unexpected fallback")
            truthy(not body:find("/target", 1, true), e.name .. ": changes target")
        end
        check("Foc", "focus", "any"); check("MO", "mouseover", "any")
        check("TT", "targettarget", "any"); check("FT", "focustarget", "any")
        for i = 1, 4 do check("P" .. i .. "T", "party" .. i .. "target", "any") end
        for i = 1, 5 do
            check("A" .. i, "arena" .. i, "pvp")
            check("B" .. i, "boss" .. i, "pve")
        end
    end
end

T["fixed friendly units: heals, dispels, buffs and resurrection cover the full raid"] = function()
    local examples = {
        { "PALADIN", "Cleanse" }, { "PALADIN", "Holy Light" }, { "PALADIN", "Kings" },
        { "PALADIN", "Shock Heal" }, { "PRIEST", "PW Shield" }, { "PRIEST", "Penance" },
        { "PRIEST", "PoM" }, { "SHAMAN", "Chain Heal" }, { "SHAMAN", "Riptide" },
        { "MAGE", "Decurse" }, { "WARLOCK", "Devour" }, { "DRUID", "Innervate" },
        { "DRUID", "Wild Growth" }, { "DRUID", "Rebirth", true },
        { "PRIEST", "Resurrect", true }, { "PALADIN", "Redeem", true }, { "SHAMAN", "Ancestral", true },
    }
    for _, sample in ipairs(examples) do
        local condition = sample[3] and "help,dead" or "help,nodead"
        for i = 1, 40 do
            local e = X():Find(sample[2] .. " R" .. i, sample[1])
            truthy(e, sample[1] .. ": missing raid variant " .. sample[2] .. " R" .. i)
            eq(e.mode, "pve")
            truthy(e.note:find("roster", 1, true), e.name .. ": missing roster note")
            local body = X():Render(e.id)
            truthy(body:find("[@raid" .. i .. "," .. condition .. "]", 1, true), e.name .. ": incorrect unit")
            truthy(not body:find("[]", 1, true), e.name .. ": unexpected fallback")
        end
        for i = 1, 4 do truthy(X():Find(sample[2] .. " P" .. i, sample[1]), sample[2] .. ": missing party variant") end
        if sample[3] then eq(X():Find(sample[2] .. " Me", sample[1]), nil, "no self resurrection macro") end
    end
    eq(X():Render("paladin:holy-light-b5t"), "#showtooltip Holy Light\n/cast [@boss5target,help,nodead] Holy Light")
end

T["general raid and arena helpers use guarded fixed units"] = function()
    for i = 1, 40 do
        for _, action in ipairs({ "Target", "Focus", "Assist" }) do
            local e = X():Find(action .. " R" .. i, "ALL")
            truthy(e, "missing general raid helper"); eq(e.mode, "pve")
            truthy(X():Render(e.id):find("[@raid" .. i .. ",", 1, true), "unguarded raid unit")
        end
    end
    for i = 1, 5 do
        eq(X():Render("all:attack-a" .. i), "/target [@arena" .. i .. ",harm,nodead]\n/startattack [@arena" .. i .. ",harm,nodead]")
    end
end

T["target filters, search and shared utilities compose"] = function()
    for _, choice in ipairs(X().TARGET_CHOICES) do
        local list = X():List({ target = choice.value })
        truthy(#list > 0, "empty target filter " .. choice.value)
        if choice.value ~= "*" then
            for _, e in ipairs(list) do truthy(e.targets[choice.value], "incorrect target classification: " .. e.name) end
        end
    end
    local f = { class = "PALADIN", spec = "holy", mode = "pve", target = "raid", search = "Cleanse" }
    eq(#X():List(f), 0, "shared entries are opt-in for API consumers")
    f.includeShared = true
    eq(#X():List(f), 40, "all Cleanse raid variants available to Holy")
    eq(#X():List({ mode = "pve", target = "arena" }), 0)
    eq(#X():List({ mode = "pvp", target = "boss" }), 0)
end

T["Register: bad input never throws and is rejected"] = function()
    local bad = { 5, {}, { class = "MONK", name = "A", title = "t", body = "/x" },
        { class = "MAGE", spec = "arms", name = "A", title = "t", body = "/x" },
        { class = "MAGE", name = string.rep("a", 17), title = "t", body = "/x" },
        { class = "MAGE", name = "Ok", title = "t", body = string.rep("a", 256) },
        { class = "MAGE", name = "Ok", title = "t", body = "/cast |cffff0000" },
        { class = "MAGE", name = "Ok", title = "t", body = "/x", mode = "arena" },
        { class = "MAGE", name = "Blink", title = "t", body = "/x" },   -- name already in the catalog
        { class = "MAGE", name = "Focus", title = "t", body = "/x" } }   -- name used by the general macros
    for i, def in ipairs(bad) do
        local ok, res = pcall(X().Register, X(), def)
        truthy(ok, "Register threw (" .. i .. ")")
        eq(res, false, "case " .. i)
    end
    local n, errs = X():RegisterPack("MAGE", { frost = { pve = { "broken", { "Test Pack", "title", "/cast {Frostbolt}" } } } })
    eq(n, 1); eq(#errs, 1)
    eq(X():Get("mage:test-pack").spec, "frost")
end

T["turn on and off: creates and deletes the game macro"] = function(Mock)
    local G = install(Mock, "MAGE")
    eq(X():IsActive("mage:blink"), false)
    truthy(X():Enable("mage:blink"))
    eq(#G.list, 1)
    eq(G.list[1].name, "Blink"); eq(G.list[1].perChar, true)
    eq(G.list[1].body, "#showtooltip\n/stopcasting\n/cast Blink")
    eq(X():IsActive("mage:blink"), true)
    truthy(X():Enable("mage:blink"), "second turn on")
    eq(#G.list, 1, "no duplicates")
    eq(X():ActiveCount(), 1)
    truthy(X():Pickup("mage:blink")); eq(G.picked, "Blink")
    truthy(X():Toggle("mage:blink"))
    eq(#G.list, 0)
    eq(X():IsActive("mage:blink"), false)
    eq(select(1, X():Disable("mage:blink")), false, "already off")
end

T["never touches the user's own macros"] = function(Mock)
    local G = install(Mock, "MAGE")
    CreateMacro("Blink", "x", "/say mine", true)
    local ok, err = X():Enable("mage:blink")
    eq(ok, false); truthy(err:find("already have", 1, true))
    eq(G.list[1].body, "/say mine")
    -- same macro already present and identical: adopted without duplicates
    CreateMacro("Fireball", "x", X():Render("mage:fireball"), true)
    truthy(X():Enable("mage:fireball")); eq(#G.list, 2)
    -- edited by hand after being turned on: stays in the game when turned off
    truthy(X():Enable("mage:frostbolt"))
    G.list[3].body = "/cast Frostbolt\n/say edited"
    local ok2, how = X():Disable("mage:frostbolt")
    eq(ok2, true); eq(how, "kept"); eq(#G.list, 3)
    eq(X():IsActive("mage:frostbolt"), false)
    -- deleted by hand from /macro: the state realigns
    truthy(X():Enable("mage:evocation"))
    table.remove(G.list, 4)
    eq(X():IsActive("mage:evocation"), false)
end

T["other class, combat, full slots, missing API"] = function(Mock)
    local G = install(Mock, "MAGE")
    eq(select(1, X():Enable("warrior:charge")), false, "macro of another class")
    truthy(X():Enable("all:focus"), "general macros work for everyone")
    eq(select(1, X():Enable("none")), false)
    Mock.combat = true
    eq(select(1, X():Enable("mage:blink")), false, "no creation in combat")
    eq(select(1, X():Disable("all:focus")), false, "no deletion in combat")
    eq(#G.list, 1)
    Mock.combat = false
    -- character slots full: uses the general ones; everything full: clear error
    for i = 1, 18 do CreateMacro("c" .. i, "x", "/x", true) end
    truthy(X():Enable("mage:blink"))
    eq(G.list[#G.list].perChar, false)
    for i = 1, 119 do CreateMacro("a" .. i, "x", "/x", false) end
    local ok, err = X():Enable("mage:fireball")
    eq(ok, false); truthy(err:find("full", 1, true))
    CreateMacro = nil
    eq(select(1, X():Enable("mage:frostbolt")), false, "client without the API")
    eq(X().IsSupported(), false)
end

T["turn on all / turn off all by filter"] = function(Mock)
    local G = install(Mock, "ROGUE")
    local f = { class = "ROGUE", spec = "subtlety", mode = "pvp" }
    local want = #X():List(f)
    local r = X():EnableAll(f)
    eq(r.on, want); eq(r.failed, 0); eq(#G.list, want)
    truthy(X():Enable("rogue:kick"))
    local d = X():DisableAll(f)
    eq(d.off, want); eq(#G.list, 1, "the macro outside the filter stays")
    eq(X():DisableAll().off, 1); eq(#G.list, 0)
end

T["spell name translation and custom text"] = function(Mock)
    local G = install(Mock, "WARRIOR")
    truthy(X():SetSpellName("Charge", "Carica"))
    eq(X():Render("warrior:charge"), "#showtooltip Carica\n/dismount\n/startattack\n/cast Carica")
    truthy(X():Render("warrior:charge-intercept"):find("Carica; [combat,stance:3] Intercept", 1, true), "exact replacement")
    truthy(X():Enable("warrior:charge")); eq(G.list[1].body:find("Charge", 1, true), nil)
    eq(select(1, X():SetSpellName("a{b", "x")), false)
    eq(select(1, X():SetSpellName("Charge", "x|cff")), false)
    truthy(X():SetSpellName("Charge", ""))
    truthy(X():Render("warrior:charge"):find("/cast Charge", 1, true))
    truthy(X():SetBody("warrior:rend", "/cast {Rend}\n/say hello"))
    eq(X():IsCustomized("warrior:rend"), true)
    eq(X():Render("warrior:rend"), "/cast Rend\n/say hello")
    eq(select(1, X():SetBody("warrior:rend", string.rep("x", 300))), false)
    eq(select(1, X():SetBody("warrior:rend", 12)), false)
    truthy(X():SetBody("warrior:rend", nil)); eq(X():IsCustomized("warrior:rend"), false)
    -- state lives in sv.global (game macros do not depend on the BadbUI profile)
    truthy(BadbUIDB.global.macros.chars[BadbUI.DB.char]["warrior:charge"])
    BadbUIDB.global.macros = "corrupted"
    eq(X():IsActive("warrior:charge"), false, "corrupted state: no error")
end

T["spells not found in the spellbook"] = function(Mock)
    install(Mock, "MAGE")
    eq(X():MissingSpells("mage:pom-pyro"), nil, "cannot know without the API")
    function GetSpellInfo(name) if name == "Pyroblast" then return name end end
    local missing = X():MissingSpells("mage:pom-pyro")
    eq(#missing, 1); eq(missing[1], "Presence of Mind")
    truthy(X().describe("mage:pom-pyro"):find("Presence of Mind", 1, true))
end

T["page and rows: character class, actions, filters"] = function(Mock)
    local G = install(Mock, "PRIEST")
    local rows = X().rows()
    eq(#rows, math.min(X().PAGE_SIZE, #X():List({ class = "PRIEST" })), "opens on the character class")
    local function row(id) for _, r in ipairs(X().rows()) do if r.id == id then return r end end end
    local function act(r, label) for _, a in ipairs(r.actions) do if a.label == label then return a end end end
    truthy(act(row("priest:renew"), "Turn on"), "Turn on action")
    eq(act(row("priest:renew"), "Pick up"), nil)
    act(row("priest:renew"), "Turn on").func()
    eq(#G.list, 1)
    truthy(row("priest:renew").detail:find("cff5fd068on", 1, true))
    truthy(act(row("priest:renew"), "Pick up"), "Pick up only when on")
    act(row("priest:renew"), "Turn off").func()
    eq(#G.list, 0)
    X().view.spec, X().view.mode = "shadow", "pvp"
    eq(#X().rows(), math.min(X().PAGE_SIZE, #X():List({ class = "PRIEST", spec = "shadow", mode = "pvp", includeShared = true })))
    X().view.class, X().view.spec = "MAGE", "*"
    truthy(act(X().rows()[1], "Turn on").disabled, "other class: cannot be turned on")
    truthy(X().summary():find("another class", 1, true))
    truthy(#X().specChoices() == 5 and #X().classChoices() == 10)
    truthy(BadbUI.ConfigUI:OpenPage("Macros"), "page opens")
end

T["pagination reaches every macro and filters reset the page"] = function(Mock)
    install(Mock, "PRIEST")
    local view = X().view
    view.class, view.spec, view.mode = "PRIEST", "*", "*"
    local expected = X():List(X().viewFilter())
    local seen, pages = {}, #X().pageChoices()
    truthy(pages > 3, "large catalog must span multiple pages")
    for page = 1, pages do
        view.page = page
        local rows = X().rows()
        truthy(#rows <= X().PAGE_SIZE)
        for _, row in ipairs(rows) do
            truthy(not seen[row.id], "duplicate row across pages: " .. row.id)
            seen[row.id] = true
        end
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    eq(count, #expected, "no entries lost to the widget row limit")
    view.page = 999
    X().rows(); eq(view.page, pages, "stale page is clamped")
    local options = X().pageOptions()
    local search, target
    for _, opt in ipairs(options) do
        if opt.type == "text" then search = opt end
        if opt.label == "Target / variant" then target = opt end
    end
    truthy(search and target)
    target.set("raid"); eq(view.page, 1)
    search.set("Power Word: Shield"); eq(view.page, 1)
    eq(#X():List(X().viewFilter()), 40)
    search.set("no-such-spell")
    eq(#X().rows(), 0); eq(view.page, 1); eq(#X().pageChoices(), 1)
end

T["/badb macro command"] = function(Mock)
    local G = install(Mock, "DRUID")
    local S = BadbUI.Slash
    truthy(S:Dispatch("macro on Cat")); eq(#G.list, 1)
    truthy(S:Dispatch("macro off druid:cat")); eq(#G.list, 0)
    truthy(S:Dispatch("macro on Focus")); truthy(S:Dispatch("macro on Shred"))
    truthy(S:Dispatch("macro alloff")); eq(#G.list, 0)
    truthy(S:Dispatch("macro name Cat Form = Katzengestalt"))
    eq(X():GetSpellName("Cat Form"), "Katzengestalt")
    for _, c in ipairs({ "macro list feral pvp", "macro show Cat", "macro on missing", "macro whatever", "macro name", "macro" }) do
        truthy(S:Dispatch(c), c)
    end
end

-- The tests define global client APIs: remove them after each test so later suites stay clean.
local GLOBALS = { "GetMacroIndexByName", "GetMacroInfo", "GetNumMacros", "CreateMacro", "DeleteMacro", "PickupMacro",
    "MAX_ACCOUNT_MACROS", "MAX_CHARACTER_MACROS", "UnitClass", "GetSpellInfo" }
for name, fn in pairs(T) do
    T[name] = function(Mock)
        local saved = {}
        for _, g in ipairs(GLOBALS) do saved[g] = _G[g] end
        local ok, err = pcall(fn, Mock)
        for _, g in ipairs(GLOBALS) do _G[g] = saved[g] end
        if not ok then error(err, 0) end
    end
end

return T
