-- BadbUI - Fixed-unit variants of the hand-written catalog (Data/Macros.lua).
-- Harm: focus, mouseover, target of target, focus target, party targets, boss1-5 and arena1-5.
-- Help: focus, mouseover, self, target of target, focus target, party1-4 and raid1-40.
-- Names are "<label> <unit>" (16 characters max). No fallback to a different unit.
-- All spell availability, stance requirements and client unit support need in-game verification.
--
-- Spec format:  "Spell"  |  { "Spell", "Label", k = "kick"|"cc", pre = "extra line", dead = true }
--               |  { label = "Label", title = "What it does on", body = "text with @U as the unit" }
local _, ns = ...
local Macros = ns.Badb.Macros
if not Macros then return end

local ARENA = "Compatibility template: arena units require an arena-enabled client. Forever does not currently offer arenas."
local BOSS = "Boss units require encounter frames exposed by the client. Verify support and spell immunity in game."
local RAID = "Raid numbers follow the current roster, not a fixed player or role. Check the roster after group changes."
local VERIFY = "Spell and talent availability, form requirements and multi-press behaviour must be verified in game."

local HARM = {
    { "focus", "Foc", "your focus", "any" },
    { "mouseover", "MO", "your mouseover", "any" },
    { "targettarget", "TT", "your target's target", "any" },
    { "focustarget", "FT", "your focus's target", "any" },
    { "arena1", "A1", "arena enemy 1", "pvp" },
    { "arena2", "A2", "arena enemy 2", "pvp" },
    { "arena3", "A3", "arena enemy 3", "pvp" },
    { "arena4", "A4", "arena enemy 4", "pvp" },
    { "arena5", "A5", "arena enemy 5", "pvp" },
}
local HELP = {
    { "focus", "Foc", "your focus", "any" },
    { "mouseover", "MO", "your mouseover", "any" },
    { "player", "Me", "yourself", "any" },
    { "targettarget", "TT", "your target's target", "any" },
    { "focustarget", "FT", "your focus's target", "any" },
    { "party1", "P1", "party member 1 (group or arena teammate)", "any" },
    { "party2", "P2", "party member 2 (group or arena teammate)", "any" },
    { "party3", "P3", "party member 3 (group or arena teammate)", "any" },
    { "party4", "P4", "party member 4 (group or arena teammate)", "any" },
}
for i = 1, 4 do
    HARM[#HARM + 1] = { "party" .. i .. "target", "P" .. i .. "T", "party member " .. i .. "'s target", "any" }
end
for i = 1, 5 do
    HARM[#HARM + 1] = { "boss" .. i, "B" .. i, "boss " .. i, "pve" }
    HELP[#HELP + 1] = { "boss" .. i .. "target", "B" .. i .. "T", "boss " .. i .. "'s target", "pve" }
end
for i = 1, 40 do
    HELP[#HELP + 1] = { "raid" .. i, "R" .. i, "raid member " .. i, "pve" }
end

local function expand(out, list, units, kind)
    for _, sp in ipairs(list or {}) do
        if type(sp) == "string" then sp = { sp } end
        local spell, label = sp[1], sp.label or sp[2] or sp[1]
        for _, u in ipairs(units) do
            if not (sp.dead and u[1] == "player") then
                local body, title
                if sp.body then
                    body = sp.body:gsub("@U", "@" .. u[1])
                    title = sp.title .. " " .. u[3]
                else
                    local cond = kind == "harm" and "harm,nodead" or (sp.dead and "help,dead" or "help,nodead")
                    body = "#showtooltip {" .. spell .. "}\n" .. (sp.k == "kick" and "/stopcasting\n" or "")
                        .. (sp.pre and (sp.pre .. "\n") or "") .. "/cast [@" .. u[1] .. "," .. cond .. "] {" .. spell .. "}"
                    title = spell .. " on " .. u[3] .. " without changing target"
                end
                local bucket = out[u[4]]
                local note = u[1]:match("^arena") and ARENA or (u[1]:match("^boss") and BOSS)
                    or (u[1]:match("^raid") and RAID)
                bucket[#bucket + 1] = { label .. " " .. u[2], title, body, note and (note .. " " .. VERIFY) or VERIFY }
            end
        end
    end
end

local function variants(class, spec)
    local pack = {}
    for scope, lists in pairs(spec) do
        local out = { any = {}, pve = {}, pvp = {} }
        expand(out, lists.harm, HARM, "harm")
        expand(out, lists.help, HELP, "help")
        pack[scope] = out
    end
    return Macros:RegisterPack(class, pack)
end

---------------------------------------------------------------------------
-- General (all classes)
---------------------------------------------------------------------------
do
    local any, pve, pvp = {}, {}, {}
    for i = 1, 4 do
        local u, who = "party" .. i, "party member " .. i .. " (group or arena teammate)"
        any[#any + 1] = { "Target P" .. i, "Target " .. who, "/target [@" .. u .. ",exists]" }
        any[#any + 1] = { "Focus P" .. i, "Focus " .. who, "/focus [@" .. u .. ",exists]" }
        any[#any + 1] = { "Assist P" .. i, "Target whatever " .. who .. " is hitting", "/assist [@" .. u .. ",help,nodead]" }
        any[#any + 1] = { "Target P" .. i .. " Pet", "Target the pet of " .. who, "/target [@partypet" .. i .. ",exists]" }
    end
    for i = 1, 40 do
        local u, who = "raid" .. i, "raid member " .. i
        pve[#pve + 1] = { "Target R" .. i, "Target " .. who, "/target [@" .. u .. ",exists]", RAID }
        pve[#pve + 1] = { "Focus R" .. i, "Focus " .. who, "/focus [@" .. u .. ",exists]", RAID }
        pve[#pve + 1] = { "Assist R" .. i, "Target whatever " .. who .. " is hitting", "/assist [@" .. u .. ",help,nodead]", RAID }
        pve[#pve + 1] = { "Target R" .. i .. " Pet", "Target the pet of " .. who, "/target [@raidpet" .. i .. ",exists]", RAID }
    end
    for i = 1, 5 do
        local u, who = "boss" .. i, "boss " .. i
        pve[#pve + 1] = { "Target B" .. i, "Target " .. who, "/target [@" .. u .. ",harm,nodead]", BOSS }
        pve[#pve + 1] = { "Focus B" .. i, "Focus " .. who, "/focus [@" .. u .. ",harm,nodead]", BOSS }
        pve[#pve + 1] = { "Assist B" .. i, "Target whoever " .. who .. " is attacking", "/assist [@" .. u .. ",harm,nodead]", BOSS }
    end
    for i = 1, 5 do
        local u, who = "arena" .. i, "arena enemy " .. i
        pvp[#pvp + 1] = { "Target A" .. i, "Target " .. who, "/target [@" .. u .. ",harm,nodead]", ARENA }
        pvp[#pvp + 1] = { "Focus A" .. i, "Focus " .. who, "/focus [@" .. u .. ",harm,nodead]", ARENA }
        pvp[#pvp + 1] = { "Attack A" .. i, "Target " .. who .. " and start attacking",
            "/target [@" .. u .. ",harm,nodead]\n/startattack [@" .. u .. ",harm,nodead]", ARENA }
        pvp[#pvp + 1] = { "Target A" .. i .. " Pet", "Target the pet of " .. who, "/target [@arenapet" .. i .. ",exists]", ARENA }
    end
    for _, mark in ipairs({ { "Star", 1 }, { "Circle", 2 }, { "Diamond", 3 }, { "Triangle", 4 } }) do
        pve[#pve + 1] = { mark[1], "Mark your mouseover or target with " .. mark[1],
            "/tm [@mouseover,exists,nodead][] " .. mark[2] }
    end
    for _, seconds in ipairs({ 10, 15, 20 }) do
        pve[#pve + 1] = { "Pull " .. seconds, seconds .. " second pull countdown", "/countdown " .. seconds }
    end
    Macros:RegisterPack("ALL", { all = { any = any, pve = pve, pvp = pvp } })
end

local PET_ATTACK = { label = "Pet Attack", title = "Send your pet at", body = "/petattack [@U,harm,nodead]" }

---------------------------------------------------------------------------
-- Warrior
---------------------------------------------------------------------------
local BATTLE, DEFENSIVE, BERSERKER = "/cast [nostance:1] {Battle Stance}", "/cast [nostance:2] {Defensive Stance}",
    "/cast [nostance:3] {Berserker Stance}"
variants("WARRIOR", {
    all = { harm = {
        { "Pummel", k = "kick", pre = BERSERKER }, { "Shield Bash", k = "kick" }, { "Intercept", k = "cc", pre = BERSERKER },
        { "Charge", k = "cc", pre = BATTLE }, { "Hamstring", k = "cc" }, "Execute",
    } },
    arms = { harm = {
        { "Mortal Strike", "Mortal" }, { "Spearing Strike", "Spearing" }, "Rend", { "Overpower", pre = BATTLE },
        { "Mocking Blow", pre = BATTLE }, { "Victory Rush", "Victory" },
    } },
    fury = { harm = {
        "Bloodthirst", "Slam", { "Intimidating Shout", "Intim Shout", k = "cc" },
        { label = "Zerk Charge", title = "Berserker Rage, then Intercept", k = "cc",
          body = "#showtooltip {Intercept}\n/cast {Berserker Rage}\n/cast [nostance:3] {Berserker Stance}\n/cast [@U,harm,nodead] {Intercept}" },
        { label = "Throw", title = "Use your ranged weapon on",
          body = "#showtooltip\n/cast [worn:Bows,@U,harm,nodead] {Shoot Bow}; [worn:Crossbows,@U,harm,nodead] {Shoot Crossbow}; [worn:Guns,@U,harm,nodead] {Shoot Gun}; [@U,harm,nodead] {Throw}" },
    } },
    protection = { harm = {
        "Shield Slam", "Revenge", { "Concussion Blow", "Concussion", k = "cc" }, { "Sunder Armor", "Sunder" },
        { "Disarm", k = "cc", pre = DEFENSIVE }, { "Taunt", pre = DEFENSIVE },
    } },
})

---------------------------------------------------------------------------
-- Paladin
---------------------------------------------------------------------------
variants("PALADIN", {
    all = {
        harm = { { "Hammer of Justice", "HoJ", k = "cc" }, "Judgement" },
        help = {
            "Cleanse", { "Blessing of Protection", "BoP" }, { "Blessing of Freedom", "Freedom" },
            { "Blessing of Sacrifice", "BoSac" }, { "Lay on Hands", "LoH" }, { "Flash of Light", "FoL" },
            "Holy Light", "Purify", { "Blessing of Wisdom", "Wisdom" }, { "Blessing of Kings", "Kings" },
            { "Blessing of Might", "Might" }, "Salvation",
            { "Redemption", "Redeem", dead = true },
        },
    },
    holy = {
        harm = { { "Holy Shock", "Shock Dmg" } },
        help = { { "Holy Shock", "Shock Heal" }, { "Light's Vigil", "Vigil" },
                 { label = "Favor Light", title = "Divine Favor, then Holy Light on",
                   body = "#showtooltip {Holy Light}\n/cast {Divine Favor}\n/cast [@U,help,nodead] {Holy Light}" } },
    },
    protection = {
        harm = { "Holy Strike", "Exorcism" },
    },
    retribution = {
        harm = { { "Hammer of Wrath", "Wrath Hammer" }, { "Turn Evil", k = "cc" },
                 { label = "Stun Judge", title = "Hammer of Justice, then Judgement (one per press) on", k = "cc",
                   body = "#showtooltip\n/castsequence [@U,harm,nodead] reset=10 {Hammer of Justice}, {Judgement}" } },
    },
})

---------------------------------------------------------------------------
-- Hunter
---------------------------------------------------------------------------
variants("HUNTER", {
    all = { harm = {
        { "Hunter's Mark", "Mark" }, { "Concussive Shot", "Concussive", k = "cc" }, { "Wing Clip", k = "cc" },
        { "Tranquilizing Shot", "Tranq Shot" }, { "Viper Sting", "Viper" },
    } },
    beastmastery = { harm = {
        PET_ATTACK,
        { label = "Mark Pet", title = "Hunter's Mark and pet attack on",
          body = "#showtooltip {Hunter's Mark}\n/petattack [@U,harm,nodead]\n/cast [@U,harm,nodead] {Hunter's Mark}" },
        { label = "Wrath Pet", title = "Bestial Wrath and pet attack on",
          body = "#showtooltip {Bestial Wrath}\n/petattack [@U,harm,nodead]\n/cast {Bestial Wrath}" },
        { label = "Intimidate", title = "Pet attack and Intimidation (pet stun) on", k = "cc",
          body = "#showtooltip {Intimidation}\n/petattack [@U,harm,nodead]\n/cast {Intimidation}" },
        { "Scare Beast", k = "cc" },
    } },
    marksmanship = { harm = {
        "Aimed Shot", "Arcane Shot", "Sniper Shot", { "Serpent Sting", "Serpent" }, { "Scorpid Sting", "Scorpid" },
        { "Distracting Shot", "Distract Sht" },
    } },
    survival = { harm = {
        { "Raptor Strike", "Raptor" }, { "Mongoose Bite", "Mongoose" }, { "Counterattack", "Counteratk", k = "cc" }, "Strider Kick",
    } },
})

---------------------------------------------------------------------------
-- Rogue
---------------------------------------------------------------------------
variants("ROGUE", {
    all = { harm = {
        { "Kick", k = "kick" }, { "Blind", k = "cc" }, { "Gouge", k = "cc" }, { "Kidney Shot", k = "cc" },
        { "Cheap Shot", k = "cc" },
    } },
    assassination = { harm = {
        "Mutilate", "Eviscerate", "Rupture", "Garrote", "Ambush", { "Expose Armor", "Expose" },
        { label = "Cold Evis", title = "Cold Blood, then Eviscerate on",
          body = "#showtooltip {Eviscerate}\n/cast {Cold Blood}\n/cast [@U,harm,nodead] {Eviscerate}" },
    } },
    combat = { harm = {
        { "Sinister Strike", "Sinister" }, "Backstab", "Riposte",
        { label = "Throw", title = "Use your ranged weapon on",
          body = "#showtooltip\n/cast [worn:Bows,@U,harm,nodead] {Shoot Bow}; [worn:Crossbows,@U,harm,nodead] {Shoot Crossbow}; [worn:Guns,@U,harm,nodead] {Shoot Gun}; [@U,harm,nodead] {Throw}" },
        { label = "Sprint Kick", title = "Sprint, then Kick on", k = "kick",
          body = "#showtooltip {Kick}\n/cast {Sprint}\n/cast [@U,harm,nodead] {Kick}" },
    } },
    subtlety = { harm = {
        { "Sap", k = "cc" }, "Hemorrhage", { "Ghostly Strike", "Ghostly" }, { "Premeditation", "Premed" },
        { label = "Prem Cheap", title = "Premeditation, then Cheap Shot (one per press) on", k = "cc",
          body = "#showtooltip\n/castsequence [@U,harm,nodead] reset=6 {Premeditation}, {Cheap Shot}" },
    } },
})

---------------------------------------------------------------------------
-- Priest
---------------------------------------------------------------------------
variants("PRIEST", {
    all = {
        harm = { { "Dispel Magic", "Dispel Off" }, { "Mind Control", k = "cc" }, { "Shackle Undead", "Shackle", k = "cc" },
                 { "Shadow Word: Pain", "SW Pain" } },
        help = { { "Dispel Magic", "Dispel" }, { "Power Word: Shield", "PW Shield" }, { "Abolish Disease", "Abolish Dis" },
                 "Fear Ward", "Flash Heal", "Renew", { "Greater Heal", "Great Heal" }, "Heal", "Lesser Heal",
                 { "Power Word: Fortitude", "Fortitude" }, { "Divine Spirit", "Spirit" },
                 { "Resurrection", "Resurrect", dead = true } },
    },
    discipline = {
        harm = { { "Penance", "Penance Dmg" }, "Smite", "Mana Burn" },
        help = { "Penance",
                 { label = "Focus Heal", title = "Inner Focus, then Greater Heal on",
                   body = "#showtooltip {Greater Heal}\n/cast {Inner Focus}\n/cast [@U,help,nodead] {Greater Heal}" } },
    },
    holy = {
        harm = { "Holy Fire" },
        help = { { "Prayer of Mending", "PoM" }, { "Binding Heal", "Binding" } },
    },
    shadow = { harm = {
        { "Silence", k = "kick" }, "Mind Blast", "Mind Flay", { "Devouring Plague", "Dev Plague" },
        { "Vampiric Embrace", "Vamp Embr" }, { "Shadow Word: Death", "SW Death" },
    } },
})

---------------------------------------------------------------------------
-- Shaman
---------------------------------------------------------------------------
variants("SHAMAN", {
    all = {
        harm = { { "Earth Shock", k = "kick" }, "Purge", { "Frost Shock", k = "cc" } },
        help = { "Cure Poison", "Cure Disease", { "Healing Wave", "Heal Wave" },
                 { "Lesser Healing Wave", "Lesser Wave" }, "Chain Heal",
                 { "Ancestral Spirit", "Ancestral", dead = true } },
    },
    elemental = { harm = {
        { "Lightning Bolt", "Lightning" }, { "Chain Lightning", "Chain Light" }, "Lava Burst", "Flame Shock",
    } },
    enhancement = { harm = {
        "Stormstrike",
        { label = "Wolf Shock", title = "Leave Ghost Wolf and Frost Shock", k = "cc",
          body = "#showtooltip {Frost Shock}\n/cancelaura {Ghost Wolf}\n/cast [@U,harm,nodead] {Frost Shock}" },
        { label = "Shock R1", title = "Rank 1 Earth Shock (cheap interrupt) on", k = "kick",
          body = "#showtooltip {Earth Shock}\n/stopcasting\n/cast [@U,harm,nodead] {Earth Shock}(Rank 1)" },
        { label = "Storm Purge", title = "Purge, Shift for Stormstrike, on",
          body = "#showtooltip\n/cast [mod:shift,@U,harm,nodead] {Stormstrike}; [@U,harm,nodead] {Purge}" },
    } },
    restoration = { help = {
        "Riptide",
    } },
})

---------------------------------------------------------------------------
-- Mage
---------------------------------------------------------------------------
variants("MAGE", {
    all = {
        harm = { { "Polymorph", "Poly", k = "cc" }, { "Counterspell", "Counter", k = "kick" }, "Fire Blast" },
        help = { { "Remove Lesser Curse", "Decurse" }, { "Arcane Intellect", "Intellect" } },
    },
    arcane = { harm = {
        "Arcane Blast", { "Arcane Missiles", "Missiles" },
        { label = "Instant Pyro", title = "Presence of Mind, then Pyroblast on",
          body = "#showtooltip {Pyroblast}\n/cast {Presence of Mind}\n/cast [@U,harm,nodead] {Pyroblast}" },
        { label = "Instant Poly", title = "Presence of Mind, then Polymorph on", k = "cc",
          body = "#showtooltip {Polymorph}\n/cast {Presence of Mind}\n/cast [@U,harm,nodead] {Polymorph}" },
    } },
    fire = { harm = { "Fireball", "Scorch", "Pyroblast", { "Frostfire Bolt", "Frostfire" } } },
    frost = { harm = {
        "Frostbolt", "Ice Lance",
        { label = "Slow Bolt", title = "Rank 1 Frostbolt (fast slow) on", k = "cc",
          body = "#showtooltip {Frostbolt}\n/cast [@U,harm,nodead] {Frostbolt}(Rank 1)" },
        { label = "Stop Poly", title = "Stop casting and Polymorph", k = "cc",
          body = "#showtooltip {Polymorph}\n/stopcasting\n/cast [@U,harm,nodead] {Polymorph}" },
    } },
})

---------------------------------------------------------------------------
-- Warlock
---------------------------------------------------------------------------
variants("WARLOCK", {
    all = {
        harm = { { "Fear", k = "cc" }, { "Death Coil", k = "cc" }, { "Spell Lock", k = "kick" }, { "Seduction", "Seduce", k = "cc" },
                 { "Curse of Tongues", "Tongues" }, { "Curse of Exhaustion", "Exhaustion" }, { "Devour Magic", "Devour Off" } },
        help = { { "Devour Magic", "Devour" } },
    },
    affliction = { harm = {
        "Corruption", { "Bane of Agony", "Agony" }, "Wrack", "Siphon Life", "Drain Life", "Drain Mana",
        { "Curse of Weakness", "Weakness" }, { "Curse of the Elements", "Elements" },
    } },
    demonology = { harm = {
        PET_ATTACK, { "Banish", k = "cc" }, "Soul Fire", { "Bane of Doom", "Doom" }, "Drain Soul",
    } },
    destruction = { harm = {
        "Shadow Bolt", "Immolate", "Incinerate", "Conflagrate", "Shadowburn", { "Searing Pain", "Sear Pain" }, { "Bane of Havoc", "Havoc" },
    } },
})

---------------------------------------------------------------------------
-- Druid
---------------------------------------------------------------------------
variants("DRUID", {
    all = {
        harm = { { "Entangling Roots", "Roots", k = "cc" }, { "Hibernate", k = "cc" }, "Faerie Fire" },
        help = { { "Remove Curse", "Decurse" }, { "Abolish Poison", "Abolish Psn" }, "Innervate",
                 { "Rejuvenation", "Rejuv" }, "Regrowth", { "Healing Touch", "Heal Touch" },
                 "Thorns", { "Mark of the Wild", "MotW" },
                 { "Rebirth", dead = true } },
    },
    balance = {
        harm = { "Wrath", "Starfire", "Moonfire", { "Insect Swarm", "Swarm" } },
    },
    feral = { harm = {
        { "Feral Charge", "Feral Chg", k = "kick", pre = "/cast [noform:1] !{Dire Bear Form}" }, { "Bash", k = "cc" },
        { "Pounce", k = "cc" }, "Rake", "Rip", "Shred", "Ravage", { "Ferocious Bite", "Bite" }, "Claw",
        "Growl", "Maul",
    } },
    restoration = { help = {
        "Swiftmend", "Wild Growth",
        { label = "Swift Touch", title = "Nature's Swiftness, then Healing Touch on",
          body = "#showtooltip {Healing Touch}\n/cast {Nature's Swiftness}\n/cast [@U,help,nodead] {Healing Touch}" },
    } },
})
