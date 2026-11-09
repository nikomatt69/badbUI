local Badb = ...
local S, NP, DB, Modules = WOWSTUB, Badb.Modules:Get("Nameplates"), Badb.DB, Badb.Modules

test("disattivato di default: nessun CVar toccato", function()
    assert(not NP.enabled)
    eq(DB.sv.global.cvarOriginals.nameplateMotion, nil)
end)

test("attivazione applica i CVar e lo stile", function()
    S.cvars.nameplateMotion, S.cvars.nameplateShowAll = "0", "0"
    local uf = S.addPlate("nameplate1")
    Modules:SetEnabled("Nameplates", true)
    eq(NP.enabled, true)
    eq(S.cvars.nameplateMotion, "1")
    eq(S.cvars.nameplateShowAll, "1")
    eq(uf.healthBar.texture, "Interface\\Buttons\\WHITE8X8")
    eq(uf.name.fontSize, 10)
end)

test("nuova nameplate stilizzata all'evento", function()
    local uf = S.addPlate("nameplate2")
    S.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    eq(uf.healthBar.texture, "Interface\\Buttons\\WHITE8X8")
end)

test("nameplate forbidden ignorata", function()
    local uf = S.addPlate("nameplate3", { forbidden = true })
    S.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    eq(uf.healthBar.texture, "Blizzard\\Bar")
end)

test("nameplate senza barra vita non genera errori", function()
    S.addPlate("nameplate4", { noHealth = true })
    NP:StylePlate("nameplate4")
end)

test("unita' senza nameplate non genera errori", function()
    NP:StylePlate("nameplate99")
end)

test("bordo sul bersaglio", function()
    S.target = "nameplate1"
    S.fire("PLAYER_TARGET_CHANGED")
    local b1 = S.plates.nameplate1.UnitFrame.BadbTargetBorder
    local b2 = S.plates.nameplate2.UnitFrame.BadbTargetBorder
    eq(b1.shown, true); eq(b2.shown, false)
    S.target = "nameplate2"
    S.fire("PLAYER_TARGET_CHANGED")
    eq(b1.shown, false); eq(b2.shown, true)
    NP:Set("targetBorder", false)
    eq(b2.shown, false, "opzione disattivata")
    NP:Set("targetBorder", true)
end)

test("secret value sul bersaglio: nessun errore, bordo nascosto", function()
    S.secretTarget = true
    S.fire("PLAYER_TARGET_CHANGED")
    NP:StylePlate("nameplate1")
    eq(S.plates.nameplate1.UnitFrame.BadbTargetBorder.shown, false)
    eq(S.plates.nameplate2.UnitFrame.BadbTargetBorder.shown, false)
    S.secretTarget = false
end)

test("cambio opzione riapplica", function()
    NP:Set("texture", "blizzard")
    eq(S.plates.nameplate1.UnitFrame.healthBar.texture, "Blizzard\\Bar", "texture originale")
    NP:Set("nameSize", 14)
    eq(S.plates.nameplate1.UnitFrame.name.fontSize, 14)
    NP:Set("stacking", "overlap")
    eq(S.cvars.nameplateMotion, "0")
end)

test("disattivazione ripristina CVar e stile", function()
    NP:Set("texture", "flat")
    Modules:SetEnabled("Nameplates", false)
    eq(S.cvars.nameplateMotion, "0")
    eq(S.cvars.nameplateShowAll, "0")
    eq(S.plates.nameplate1.UnitFrame.healthBar.texture, "Blizzard\\Bar")
    eq(DB.sv.global.cvarOriginals.nameplateMotion, nil)
end)

test("dopo il disable gli eventi non stilizzano piu'", function()
    local uf = S.addPlate("nameplate5")
    S.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    eq(uf.healthBar.texture, "Blizzard\\Bar")
end)

test("attivazione in combattimento: CVar applicati a fine combattimento", function()
    S.cvars.nameplateMotion = "0"
    S.combat = true
    Modules:SetEnabled("Nameplates", true)
    eq(S.cvars.nameplateMotion, "0")
    S.combat = false
    S.fire("PLAYER_REGEN_ENABLED")
    eq(S.cvars.nameplateMotion, "0", "stacking=overlap salvato nel profilo")
    eq(S.cvars.nameplateShowAll, "1")
    Modules:SetEnabled("Nameplates", false)
end)
