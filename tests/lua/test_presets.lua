local Badb = ...
local S, P, DB = WOWSTUB, Badb.Presets, Badb.DB

test("ruolo sovrascrive il contenuto", function()
    local spec = P:Build({ content = "raid", role = "healer" })
    eq(spec.modules.GroupFrames.raidWidth, 100)
    eq(spec.modules.GroupFrames.onlyDispellable, true)
    eq(spec.modules.Nameplates.globalScale, 0.9)
end)

test("build non modifica i preset registrati", function()
    P:Build({ content = "raid", role = "healer" })
    eq(P.content.raid.modules.GroupFrames.raidWidth, 88)
end)

test("scelte del wizard", function()
    local spec = P:Build({ content = "dungeon", role = "dps", friendlyPlates = true, pixelPerfect = false })
    eq(spec.modules.Nameplates.showFriends, true)
    eq(spec.modules.Scaling.pixelPerfect, false)
end)

test("ogni combinazione produce un riepilogo", function()
    for _, c in ipairs(P.contentOrder) do
        for _, r in ipairs(P.roleOrder) do
            local lines = P:Describe(P:Build({ content = c, role = r, hideClutter = true }))
            assert(#lines >= 3, c .. "/" .. r)
        end
    end
end)

test("i preset usano solo opzioni esistenti nei moduli", function()
    local function check(mods, where)
        for module, opts in pairs(mods) do
            local m = Badb.Modules:Get(module)
            assert(m, where .. ": modulo sconosciuto " .. module)
            for k in pairs(opts) do
                assert(m.defaults[k] ~= nil, where .. ": " .. module .. "." .. k .. " non e' un'opzione")
            end
        end
    end
    for id, c in pairs(P.content) do check(c.modules, id) end
    for id, r in pairs(P.roles) do check(r.modules, id) end
end)

test("raccomandazione da ruolo e livello", function()
    S.role, S.level = "HEALER", 30
    local r = P:Recommend()
    eq(r.role, "healer"); eq(r.content, "leveling")
    S.role, S.level, S.inRaid = "TANK", 60, true
    r = P:Recommend()
    eq(r.role, "tank"); eq(r.content, "raid")
    S.role, S.inRaid = nil, false
end)

test("apply crea un nuovo profilo e undo torna indietro", function()
    local before = DB:GetProfileName()
    local name = P:Apply(P:Build({ content = "pvp", role = "dps", hideClutter = true }))
    eq(DB:GetProfileName(), name)
    eq(DB:Get("Nameplates", "showMinions"), true)
    eq(DB.profile.frames.BagsBar.hidden, true)
    eq(DB.sv.profiles[before].frames.BagsBar, nil, "profilo originale intatto")
    P:Undo()
    eq(DB:GetProfileName(), before)
    assert(not P:CanUndo())
end)

test("nomi profilo unici", function()
    local a = P:Apply(P:Build({ content = "raid", role = "tank" }))
    local b = P:Apply(P:Build({ content = "raid", role = "tank" }))
    assert(a ~= b, a .. " == " .. b)
end)

test("niente apply in combattimento", function()
    S.combat = true
    eq(P:Apply(P:Build({})), nil)
    S.combat = false
end)

test("apply attiva i moduli, undo li spegne e ripristina i CVar", function()
    DB:SetProfile("Default") -- profilo base con Nameplates/GroupFrames spenti
    assert(not Badb.Modules:Get("Nameplates").enabled)
    S.cvars.nameplateShowAll, S.cvars.raidFramesDisplayPowerBars = "0", "0"
    P:Apply(P:Build({ content = "dungeon", role = "healer" }))
    assert(Badb.Modules:Get("Nameplates").enabled, "Nameplates attivo")
    assert(Badb.Modules:Get("GroupFrames").enabled, "GroupFrames attivo")
    eq(S.cvars.nameplateShowAll, "1")
    eq(S.cvars.raidFramesDisplayPowerBars, "1")
    P:Undo()
    assert(not Badb.Modules:Get("Nameplates").enabled)
    eq(S.cvars.nameplateShowAll, "0")
    eq(S.cvars.raidFramesDisplayPowerBars, "0")
end)

test("undo impossibile se il profilo precedente e' stato eliminato", function()
    local before = DB:GetProfileName()
    DB:CopyProfile(before, "Temp")
    DB:SetProfile("Temp")
    P:Apply(P:Build({ content = "raid", role = "dps" }))
    DB:DeleteProfile("Temp")
    assert(not P:CanUndo())
    P:Undo() -- non deve generare errori
    DB:SetProfile(before)
end)

test("al login i CVar orfani vengono ripristinati", function()
    S.cvars.nameplateMotion = "0"
    DB.sv.global.cvarOriginals.nameplateMotion = { value = "0", owner = "Nameplates" }
    S.cvars.nameplateMotion = "1" -- modificato in una sessione precedente
    assert(not Badb.Modules:Get("Nameplates").enabled)
    S.fire("PLAYER_LOGIN")
    eq(S.cvars.nameplateMotion, "0")
    eq(DB.sv.global.cvarOriginals.nameplateMotion, nil)
end)

test("layout Edit Mode: ruolo > contenuto, voce ruolo > default", function()
    P:RegisterContent("ztest", { title = "Z", modules = {}, editMode = { default = "C-def", tank = "C-tank" } })
    P:RegisterRole("ztestrole", { title = "R", modules = {}, editMode = "R-all" })
    eq(P:Build({ content = "ztest", role = "tank" }).editMode, "C-tank")
    eq(P:Build({ content = "ztest", role = "dps" }).editMode, "C-def")
    eq(P:Build({ content = "ztest", role = "ztestrole" }).editMode, "R-all")
    eq(P:Build({ content = "raid", role = "dps" }).editMode, nil)
    local name = P:Apply(P:Build({ content = "ztest", role = "healer" }))
    eq(DB:Get("EditModeBridge", "layoutString"), "C-def")
    eq(DB:Get("EditModeBridge", "layoutName"), name)
    P:Undo()
    P.content.ztest, P.roles.ztestrole = nil, nil
    for _, list in ipairs({ P.contentOrder, P.roleOrder }) do
        for i = #list, 1, -1 do if list[i]:find("^ztest") then table.remove(list, i) end end
    end
end)
