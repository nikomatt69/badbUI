local Badb = ...
local S, CVars = WOWSTUB, Badb.CVars

test("salva l'originale e lo ripristina", function()
    S.cvars.nameplateMotion = "0"
    CVars:Set("Nameplates", "nameplateMotion", 1)
    eq(S.cvars.nameplateMotion, "1")
    CVars:Set("Nameplates", "nameplateMotion", 0)
    CVars:Set("Nameplates", "nameplateMotion", 1)
    CVars:Restore("Nameplates")
    eq(S.cvars.nameplateMotion, "0", "dopo restore")
end)

test("ignora CVar inesistenti", function()
    CVars:Set("Nameplates", "cvarCheNonEsiste", 1)
    eq(S.cvars.cvarCheNonEsiste, nil)
end)

test("booleani convertiti in 0/1", function()
    S.cvars.nameplateShowAll = "0"
    CVars:SetMany("Nameplates", { nameplateShowAll = true })
    eq(S.cvars.nameplateShowAll, "1")
    CVars:Restore("Nameplates")
end)

test("in combattimento la modifica attende la fine", function()
    S.cvars.raidFramesDisplayPowerBars = "0"
    S.combat = true
    CVars:Set("GroupFrames", "raidFramesDisplayPowerBars", true)
    eq(S.cvars.raidFramesDisplayPowerBars, "0", "in combattimento")
    S.combat = false
    S.fire("PLAYER_REGEN_ENABLED")
    eq(S.cvars.raidFramesDisplayPowerBars, "1", "dopo il combattimento")
    CVars:Restore("GroupFrames")
end)

test("restore tocca solo i CVar del modulo", function()
    S.cvars.nameplateMotion, S.cvars.raidOptionDisplayPets = "0", "0"
    CVars:Set("Nameplates", "nameplateMotion", 1)
    CVars:Set("GroupFrames", "raidOptionDisplayPets", 1)
    CVars:Restore("Nameplates")
    eq(S.cvars.nameplateMotion, "0"); eq(S.cvars.raidOptionDisplayPets, "1")
    CVars:Restore("GroupFrames")
end)
