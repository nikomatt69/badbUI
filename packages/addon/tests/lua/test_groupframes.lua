local Badb = ...
local S, GF, Modules = WOWSTUB, Badb.Modules:Get("GroupFrames"), Badb.Modules

local function setting(index, id)
    for _, sys in ipairs(S.layouts.layouts[1].systems) do
        if sys.systemIndex == index then
            for _, s in ipairs(sys.settings) do if s.setting == id then return s.value end end
        end
    end
end

-- Frame compatti Blizzard finti
CompactPartyFrameMember1 = S.region({ unit = "party1" })
CompactPartyFrameMember1.healthBar = S.region({ texture = "Blizzard\\Raid" })
CompactPartyFrameMember1.name = S.region()
CompactPartyFrameMember1.background = S.region()
CompactRaidFrame1 = S.region({ unit = "raid1", forbidden = true })
CompactRaidFrame1.healthBar = S.region({ texture = "Blizzard\\Raid" })
CompactRaidFrame2 = S.region({ unit = "nameplate1" }) -- non e' un frame di gruppo
CompactRaidFrame2.healthBar = S.region({ texture = "Blizzard\\Raid" })

test("attivazione: CVar di gruppo", function()
    S.cvars.raidFramesDisplayClassColor, S.cvars.raidFramesHealthText = "0", "perc"
    Modules:SetEnabled("GroupFrames", true)
    eq(S.cvars.raidFramesDisplayClassColor, "1")
    eq(S.cvars.raidFramesHealthText, "none")
end)

test("stile solo sui frame di gruppo non forbidden", function()
    eq(CompactPartyFrameMember1.healthBar.texture, "Interface\\Buttons\\WHITE8X8")
    eq(CompactPartyFrameMember1.name.fontSize, 11)
    eq(CompactRaidFrame1.healthBar.texture, "Blizzard\\Raid", "forbidden")
    eq(CompactRaidFrame2.healthBar.texture, "Blizzard\\Raid", "unita' non di gruppo")
end)

test("dimensioni non gestite di default", function()
    eq(S.savedLayouts, 0)
    eq(setting(5, 3), 24)
end)

test("dimensioni scritte nel layout con conversione slider", function()
    GF:Set("resizeFrames", true)
    eq(setting(5, 3), (120 - 72) / 2, "larghezza party")
    eq(setting(5, 4), (60 - 36) / 2, "altezza party")
    eq(setting(6, 3), (90 - 72) / 2, "larghezza raid")
    eq(setting(6, 4), (45 - 36) / 2, "altezza raid")
    eq(S.savedLayouts, 1)
end)

test("nessun salvataggio se i valori non cambiano", function()
    GF:ApplySizes()
    eq(S.savedLayouts, 1)
end)

test("layout preset Blizzard: avviso, nessuna scrittura", function()
    S.resetLayouts(1)
    GF:Set("partyWidth", 140)
    eq(S.savedLayouts, 0)
    S.resetLayouts()
end)

test("in combattimento le dimensioni attendono", function()
    S.combat = true
    GF:Set("raidWidth", 100)
    eq(S.savedLayouts, 0)
    S.combat = false
    S.fire("PLAYER_REGEN_ENABLED")
    eq(setting(6, 3), (100 - 72) / 2)
end)

test("senza info slider usa il valore grezzo", function()
    local saved = EditModeSettingDisplayInfoManager
    EditModeSettingDisplayInfoManager = nil
    GF:Set("raidHeight", 50)
    eq(setting(6, 4), 50)
    EditModeSettingDisplayInfoManager = saved
end)

test("Enum Edit Mode mancanti: nessun errore", function()
    local saved = Enum.EditModeUnitFrameSetting
    Enum.EditModeUnitFrameSetting = nil
    GF:Set("raidHeight", 40)
    Enum.EditModeUnitFrameSetting = saved
end)

test("disattivazione ripristina CVar e stile", function()
    Modules:SetEnabled("GroupFrames", false)
    eq(S.cvars.raidFramesDisplayClassColor, "0")
    eq(S.cvars.raidFramesHealthText, "perc")
    eq(CompactPartyFrameMember1.healthBar.texture, "Blizzard\\Raid")
end)

test("da disattivato RestyleAll non tocca nulla", function()
    GF:RestyleAll()
    eq(CompactPartyFrameMember1.healthBar.texture, "Blizzard\\Raid")
end)
