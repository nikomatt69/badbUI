-- BadbUI - Macro catalog: general + 9 classes x (shared, 3 trees) x (PvE, PvP).
--
-- Format: Macros:RegisterPack(CLASS, { [tree | "all"] = { any = {...}, pve = {...}, pvp = {...} } })
--   entry = { "In-game name (max 16)", "What it does", "macro text", "optional note" }
-- Spell names are wrapped in braces: {Charge}. The braces are removed when the macro is created (and the name
-- is replaced by the translation saved by the user, if any). Item names have no braces.
--
-- Sources (research of 2026-11-10, see docs/macros.md): modern-client syntax and conditionals (255 characters,
-- @mouseover, @focus, /castsequence), spell names from the Forever class-change summaries (e.g. Bane of Agony
-- instead of Curse of Agony, Victory Rush, Fire Nova, Penance, Ice Lance, Wild Growth).
-- NO macro has been tested in the client: the ones using new talents carry the "to be verified" note.
local _, ns = ...
local Macros = ns.Badb.Macros
if not Macros then return end

local S = "#showtooltip\n"
local V = "New Forever talent: name and behaviour to be verified in game."
local R = "Rank syntax is the Classic one: to be verified on Forever."

local function cast(sp) return S .. "/cast {" .. sp .. "}" end
local function atk(sp) return S .. "/startattack\n/cast {" .. sp .. "}" end
local function mo(sp) return S .. "/cast [@mouseover,harm,nodead][] {" .. sp .. "}" end
local function foc(sp) return S .. "/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {" .. sp .. "}" end
local function kick(sp) return S .. "/stopcasting\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {" .. sp .. "}" end
local function heal(sp) return S .. "/cast [@mouseover,help,nodead][help,nodead][@player] {" .. sp .. "}" end
local function me(sp) return S .. "/cast [@player] {" .. sp .. "}" end
local function now(sp) return S .. "/stopcasting\n/cast {" .. sp .. "}" end
local function shift(a, b) return S .. "/cast [mod:shift] {" .. b .. "}; {" .. a .. "}" end
local function burst(sp) return "#showtooltip {" .. sp .. "}\n/use 13\n/use 14\n/cast {" .. sp .. "}" end
local function pet(sp) return S .. "/petattack\n/cast {" .. sp .. "}" end
local function ground(sp) return S .. "/cast [@cursor] {" .. sp .. "}" end
local function stance(st, name, sp) return "#showtooltip {" .. sp .. "}\n/cast [nostance:" .. st .. "] {" .. name .. "}\n/cast {" .. sp .. "}" end
local function tot(sp) return S .. "/cast [@targettarget,help,nodead][] {" .. sp .. "}" end
local function pvp(sp) return S .. "/targetenemyplayer [noharm][dead]\n/cast {" .. sp .. "}" end
local function onfocus(sp) return S .. "/cast [@focus,harm,nodead] {" .. sp .. "}" end
local function tank(sp) return S .. "/cast [@focus,help,nodead][] {" .. sp .. "}" end
local function melee(sp) return "#showtooltip {" .. sp .. "}\n/targetenemyplayer [noharm][dead]\n/startattack\n/cast {" .. sp .. "}" end

---------------------------------------------------------------------------
-- General (all classes)
---------------------------------------------------------------------------
Macros:RegisterPack("ALL", { all = {
    any = {
        { "Focus", "Focus your mouseover or target; Shift clears it", "/clearfocus [mod:shift]\n/focus [nomod,@mouseover,exists,nodead][nomod,@target,exists]" },
        { "Target Focus", "Target your focus; Shift goes back to the last target", "/target [@focus,exists]\n/targetlasttarget [mod:shift]" },
        { "Assist Focus", "Target whatever your focus (e.g. the tank) is hitting", "/assist [@focus,help,nodead]" },
        { "Nearest Enemy", "Target the nearest enemy only if you have no valid target", "/targetenemy [noharm][dead]" },
        { "Last Target", "Go back to your previous target", "/targetlasttarget" },
        { "Clear Target", "Clear your target and stop attacking", "/stopattack\n/cleartarget" },
        { "Trinkets", "Use both trinkets", "#showtooltip\n/use 13\n/use 14" },
        { "Healing Potion", "Drink the best healing potion you carry",
          "#showtooltip\n/use Major Healing Potion\n/use Superior Healing Potion\n/use Greater Healing Potion\n/use Healing Potion\n/use Lesser Healing Potion\n/use Minor Healing Potion" },
        { "Healthstone", "Use the best healthstone you carry",
          "#showtooltip\n/use Major Healthstone\n/use Greater Healthstone\n/use Healthstone\n/use Lesser Healthstone\n/use Minor Healthstone" },
        { "Dismount", "Dismount and cancel your cast", "/stopcasting\n/dismount" },
        { "Max Zoom", "Zoom the camera all the way out", "/console cameraDistanceMaxZoomFactor 2.6" },
        { "Stop All", "Stop casting, attacking and call the pet back", "/stopcasting\n/stopattack\n/petfollow" },
    },
    pve = {
        { "Skull", "Skull on your mouseover or target", "/tm [@mouseover,exists,nodead][] 8" },
        { "Cross", "Cross on your mouseover or target", "/tm [@mouseover,exists,nodead][] 7" },
        { "Moon", "Moon (crowd control) on your mouseover or target", "/tm [@mouseover,exists,nodead][] 5" },
        { "Square", "Square (trap) on your mouseover or target", "/tm [@mouseover,exists,nodead][] 6" },
        { "Clear Marker", "Remove the marker from your mouseover or target", "/tm [@mouseover,exists][] 0" },
        { "Pull 5", "5 second pull countdown", "/countdown 5" },
        { "Ready Check", "Ready check (group leader)", "/readycheck" },
        { "Assist Tank", "Target whatever your friendly target is hitting", "/assist [help,nodead]" },
    },
    pvp = {
        { "Nearest Player", "Target the nearest enemy player (skips pets and totems)", "/targetenemyplayer [noharm][dead]" },
        { "Focus Enemy", "Focus the enemy player under your mouse", "/focus [@mouseover,harm,nodead][harm,nodead]" },
        { "Call Incoming", "Tell the battleground: enemies incoming", "/bg Enemies incoming at my position!" },
        { "Call Help", "Tell the battleground: help needed", "/bg Need help at my position!" },
        { "Call Clear", "Tell the battleground: all clear", "/bg All clear here." },
        { "Call Target", "Tell the battleground who you are attacking", "/bg Focus %t!" },
    },
} })

---------------------------------------------------------------------------
-- Warrior  (stances: 1 Battle, 2 Defensive, 3 Berserker)
---------------------------------------------------------------------------
Macros:RegisterPack("WARRIOR", {
    all = {
        any = {
            { "Charge", "Dismount, start attacking and Charge", "#showtooltip {Charge}\n/dismount\n/startattack\n/cast {Charge}" },
            { "Charge Intercept", "Charge out of combat, Intercept in combat (swaps stance for you)",
              "#showtooltip\n/startattack\n/cast [nocombat,stance:1] {Charge}; [combat,stance:3] {Intercept}; [nocombat] {Battle Stance}; [combat] {Berserker Stance}" },
            { "Victory Rush", "Victory Rush with auto attack", atk("Victory Rush") },
            { "Execute", "Execute (Shift: on mouseover), leaves Defensive Stance",
              "#showtooltip {Execute}\n/startattack\n/cast [stance:2] {Battle Stance}\n/cast [mod:shift,@mouseover,harm,nodead][] {Execute}" },
            { "Heroic Strike", "Heroic Strike, Shift for Cleave", "#showtooltip\n/startattack\n/cast [mod:shift] {Cleave}; {Heroic Strike}" },
            { "Shouts", "Battle Shout, Shift for Demoralizing Shout", shift("Battle Shout", "Demoralizing Shout") },
            { "Bloodrage", "Bloodrage", cast("Bloodrage") },
            { "Berserker Rage", "Berserker Rage with a stance swap", stance(3, "Berserker Stance", "Berserker Rage") },
            { "Overpower", "Overpower from any stance", stance(1, "Battle Stance", "Overpower") },
            { "Interrupt", "Pummel in Berserker Stance, Shield Bash otherwise; focus first",
              "#showtooltip\n/cast [stance:3,@focus,harm,nodead][stance:3] {Pummel}; [@focus,harm,nodead][] {Shield Bash}" },
            { "Hamstring", "Hamstring with auto attack", atk("Hamstring") },
            { "Rend", "Rend with auto attack", atk("Rend") },
            { "Sunder", "Sunder Armor; picks a target if you have none", "#showtooltip\n/targetenemy [noharm][dead]\n/startattack\n/cast {Sunder Armor}" },
            { "Thunder Clap", "Thunder Clap, Shift for Demoralizing Shout", shift("Thunder Clap", "Demoralizing Shout") },
            { "Stance Swap", "Battle <-> Defensive; Shift for Berserker",
              "#showtooltip\n/cast [mod:shift] {Berserker Stance}; [stance:1] {Defensive Stance}; {Battle Stance}" },
            { "Ranged", "One button for bow, crossbow, gun or thrown weapon",
              "#showtooltip\n/cast [worn:Bows] {Shoot Bow}; [worn:Crossbows] {Shoot Crossbow}; [worn:Guns] {Shoot Gun}; [worn:Thrown] {Throw}" },
        },
        pve = {
            { "Taunt", "Taunt your mouseover or target; Shift for Mocking Blow",
              "#showtooltip\n/cast [mod:shift] {Mocking Blow}; [nostance:2] {Defensive Stance}; [@mouseover,harm,nodead][] {Taunt}" },
            { "Challenging", "Challenging Shout (area taunt)", cast("Challenging Shout") },
            { "Sunder Mouseover", "Sunder Armor on your mouseover without changing target", mo("Sunder Armor") },
        },
        pvp = {
            { "Intercept", "Intercept with a stance swap, on mouseover or target",
              "#showtooltip {Intercept}\n/cast [nostance:3] {Berserker Stance}\n/cast [@mouseover,harm,nodead][] {Intercept}" },
            { "Disarm", "Disarm with a stance swap", stance(2, "Defensive Stance", "Disarm") },
            { "Fear Shout", "Intimidating Shout", cast("Intimidating Shout") },
            { "Hamstring PvP", "Target an enemy player and Hamstring", melee("Hamstring") },
            { "Pummel Focus", "Pummel your focus with a stance swap",
              "#showtooltip {Pummel}\n/cast [nostance:3] {Berserker Stance}\n/cast [@focus,harm,nodead][] {Pummel}" },
            { "Retaliation", "Retaliation with a stance swap", stance(1, "Battle Stance", "Retaliation") },
        },
    },
    arms = {
        pve = {
            { "Mortal Strike", "Mortal Strike with auto attack", atk("Mortal Strike") },
            { "Spearing Strike", "Spearing Strike with auto attack", atk("Spearing Strike"), V },
            { "Sweeping Strikes", "Sweeping Strikes with a stance swap", stance(1, "Battle Stance", "Sweeping Strikes") },
            { "Slam", "Slam with auto attack", atk("Slam") },
            { "Arms Burst", "Trinkets and Death Wish", burst("Death Wish") },
            { "Arms Whirlwind", "Whirlwind with a stance swap", stance(3, "Berserker Stance", "Whirlwind") },
            { "Rend Mouseover", "Rend on your mouseover without changing target", mo("Rend") },
        },
        pvp = {
            { "MS Player", "Target an enemy player and Mortal Strike", melee("Mortal Strike") },
            { "Spear Mouseover", "Spearing Strike on your mouseover or target", mo("Spearing Strike"), V },
            { "Quick Overpower", "Cancel what you are doing and Overpower",
              "#showtooltip {Overpower}\n/stopcasting\n/cast [nostance:1] {Battle Stance}\n/cast {Overpower}" },
            { "Arms PvP Burst", "Trinkets, Bloodrage and Death Wish", "#showtooltip {Death Wish}\n/use 13\n/use 14\n/cast {Bloodrage}\n/cast {Death Wish}" },
            { "Sweeping PvP", "Sweeping Strikes, Berserker Stance, Whirlwind (one per press)", "#showtooltip\n/castsequence reset=20 {Sweeping Strikes}, {Berserker Stance}, {Whirlwind}" },
            { "Arms Shield Wall", "Shield Wall with a stance swap (needs a shield)", stance(2, "Defensive Stance", "Shield Wall") },
        },
    },
    fury = {
        pve = {
            { "Bloodthirst", "Bloodthirst with auto attack", atk("Bloodthirst") },
            { "Whirlwind", "Whirlwind with auto attack", atk("Whirlwind") },
            { "Fury Burst", "Trinkets, Death Wish and Recklessness", "#showtooltip {Recklessness}\n/use 13\n/use 14\n/cast {Death Wish}\n/cast {Recklessness}" },
            { "Death Wish", "Death Wish", cast("Death Wish") },
            { "Recklessness", "Recklessness with a stance swap", stance(3, "Berserker Stance", "Recklessness") },
            { "BT Mouseover", "Bloodthirst on your mouseover without changing target", mo("Bloodthirst") },
            { "Cleave", "Cleave with auto attack", atk("Cleave") },
        },
        pvp = {
            { "Piercing Howl", "Piercing Howl (area slow)", cast("Piercing Howl") },
            { "BT Player", "Target an enemy player and Bloodthirst", melee("Bloodthirst") },
            { "Fury PvP Burst", "Trinkets, Bloodrage and Death Wish", "#showtooltip {Death Wish}\n/use 13\n/use 14\n/cast {Bloodrage}\n/cast {Death Wish}" },
            { "Pummel Mouseover", "Pummel your mouseover or target", "#showtooltip {Pummel}\n/cast [nostance:3] {Berserker Stance}\n/cast [@mouseover,harm,nodead][] {Pummel}" },
            { "Intercept Focus", "Intercept your focus", "#showtooltip {Intercept}\n/cast [nostance:3] {Berserker Stance}\n/cast [@focus,harm,nodead][] {Intercept}" },
            { "Break Fear", "Berserker Rage even mid-action", "#showtooltip {Berserker Rage}\n/stopcasting\n/cast [nostance:3] {Berserker Stance}\n/cast {Berserker Rage}" },
        },
    },
    protection = {
        pve = {
            { "Shield Slam", "Shield Slam with auto attack", atk("Shield Slam") },
            { "Revenge", "Revenge with auto attack", atk("Revenge") },
            { "Shield Block", "Shield Block", cast("Shield Block") },
            { "Tank Charge", "Charge in Defensive Stance (Vanguard talent)", "#showtooltip {Charge}\n/startattack\n/cast {Charge}", V },
            { "Shield Wall", "Shield Wall with a stance swap", stance(2, "Defensive Stance", "Shield Wall") },
            { "Last Stand", "Last Stand", cast("Last Stand") },
            { "Concussion Blow", "Concussion Blow on your mouseover or target", mo("Concussion Blow") },
            { "Taunt Focus", "Taunt your focus (for tank swaps)", "#showtooltip\n/cast [@focus,harm,nodead][] {Taunt}" },
            { "Demo Shout", "Demoralizing Shout", cast("Demoralizing Shout") },
        },
        pvp = {
            { "Bash Focus", "Shield Bash your focus or mouseover", foc("Shield Bash") },
            { "Stun Focus", "Concussion Blow your focus or mouseover", foc("Concussion Blow") },
            { "Disarm Focus", "Disarm your focus or target", "#showtooltip {Disarm}\n/cast [nostance:2] {Defensive Stance}\n/cast [@focus,harm,nodead][] {Disarm}" },
            { "Defensives", "Shield Block, Shift Shield Wall, Ctrl Last Stand", "#showtooltip\n/cast [mod:shift] {Shield Wall}; [mod:ctrl] {Last Stand}; {Shield Block}" },
            { "Slam Player", "Target an enemy player and Shield Slam", melee("Shield Slam") },
            { "Revenge PvP", "Revenge, Shift for Hamstring", "#showtooltip\n/startattack\n/cast [mod:shift] {Hamstring}; {Revenge}" },
        },
    },
})

---------------------------------------------------------------------------
-- Paladin
---------------------------------------------------------------------------
Macros:RegisterPack("PALADIN", {
    all = {
        any = {
            { "Flash of Light", "Flash of Light on mouseover, friendly target or yourself", heal("Flash of Light") },
            { "Holy Light", "Holy Light on mouseover, friendly target or yourself", heal("Holy Light") },
            { "Heals", "Holy Light, Shift for Flash of Light, on mouseover", "#showtooltip\n/cast [mod:shift,@mouseover,help,nodead][mod:shift] {Flash of Light}; [@mouseover,help,nodead][] {Holy Light}" },
            { "Cleanse", "Cleanse on mouseover, friendly target or yourself", heal("Cleanse") },
            { "Purify", "Purify on mouseover, friendly target or yourself", heal("Purify") },
            { "Judgement", "Judgement with auto attack", atk("Judgement") },
            { "Holy Strike", "Holy Strike with auto attack", atk("Holy Strike") },
            { "HoJ", "Hammer of Justice on focus, mouseover or target", foc("Hammer of Justice") },
            { "Lay on Hands", "Lay on Hands on mouseover, friendly target or yourself", heal("Lay on Hands") },
            { "BoP", "Blessing of Protection on mouseover; Alt on yourself", "#showtooltip\n/cast [mod:alt,@player][@mouseover,help,nodead][help,nodead][@player] {Blessing of Protection}" },
            { "Bubble", "Divine Shield even mid-cast", now("Divine Shield") },
            { "Cancel Bubble", "Remove Divine Shield and Blessing of Protection", "/cancelaura {Divine Shield}\n/cancelaura {Blessing of Protection}" },
            { "Blessings", "Might; Shift Wisdom; Ctrl Kings, on mouseover",
              "#showtooltip\n/cast [mod:shift,@mouseover,help][mod:shift] {Blessing of Wisdom}; [mod:ctrl,@mouseover,help][mod:ctrl] {Blessing of Kings}; [@mouseover,help][] {Blessing of Might}" },
            { "Seals", "Seal of Righteousness; Shift for Seal of Fury", shift("Seal of Righteousness", "Seal of Fury") },
            { "Hammer of Wrath", "Hammer of Wrath on your mouseover or target", mo("Hammer of Wrath") },
            { "Consecration", "Consecration", cast("Consecration") },
            { "Resurrect", "Redemption on your mouseover or target", "#showtooltip\n/cast [@mouseover,help,dead][] {Redemption}" },
        },
        pve = {
            { "Salvation", "Salvation on mouseover or friendly target", heal("Salvation") },
            { "Exorcism", "Exorcism on your mouseover or target", mo("Exorcism") },
            { "Auras", "Devotion Aura; Shift Retribution; Ctrl Concentration", "#showtooltip\n/cast [mod:shift] {Retribution Aura}; [mod:ctrl] {Concentration Aura}; {Devotion Aura}" },
        },
        pvp = {
            { "Freedom", "Blessing of Freedom on mouseover; Alt on yourself", "#showtooltip\n/cast [mod:alt,@player][@mouseover,help,nodead][help,nodead][@player] {Blessing of Freedom}" },
            { "Sacrifice", "Blessing of Sacrifice on mouseover or friendly target", "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead] {Blessing of Sacrifice}" },
            { "HoJ Player", "Target an enemy player and stun", pvp("Hammer of Justice") },
            { "Protection", "Divine Protection; Shift for Divine Shield", shift("Divine Protection", "Divine Shield") },
            { "Cleanse Self", "Cleanse on yourself", me("Cleanse") },
        },
    },
    holy = {
        pve = {
            { "Holy Shock", "Holy Shock: heals the friend under your mouse, otherwise damages your target",
              "#showtooltip\n/cast [@mouseover,help,nodead][@mouseover,harm,nodead][] {Holy Shock}" },
            { "Divine Favor HL", "Divine Favor and Holy Light on mouseover", "#showtooltip {Holy Light}\n/cast {Divine Favor}\n/cast [@mouseover,help,nodead][help,nodead][@player] {Holy Light}" },
            { "Light's Vigil", "Light's Vigil on focus, mouseover or friendly target", "#showtooltip\n/cast [@focus,help,nodead][@mouseover,help,nodead][] {Light's Vigil}", V },
            { "Heal Tank", "Holy Light on your focus (set the tank as focus)", tank("Holy Light") },
            { "Flash Tank", "Flash of Light on your focus", tank("Flash of Light") },
            { "Heal ToT", "Flash of Light on your enemy target's target", tot("Flash of Light") },
            { "Wisdom Seal", "Seal of Wisdom; Shift for Seal of Light", shift("Seal of Wisdom", "Seal of Light") },
            { "Voice of Truth", "Voice of Truth", cast("Voice of Truth"), V },
        },
        pvp = {
            { "Shock Heal", "Instant healing Holy Shock on mouseover or yourself", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead][@player] {Holy Shock}" },
            { "Favor Shock", "Divine Favor and Holy Shock on mouseover or yourself", "#showtooltip {Holy Shock}\n/cast {Divine Favor}\n/cast [@mouseover,help,nodead][help,nodead][@player] {Holy Shock}" },
            { "Quick Cleanse", "Cancel your cast and Cleanse the mouseover", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead][@player] {Cleanse}" },
            { "Flash Self", "Flash of Light on yourself", me("Flash of Light") },
            { "Concentration", "Concentration Aura", cast("Concentration Aura") },
            { "Vigil Self", "Light's Vigil on yourself", me("Light's Vigil"), V },
        },
    },
    protection = {
        pve = {
            { "Righteous Fury", "Righteous Fury", cast("Righteous Fury") },
            { "Holy Shield", "Holy Shield", cast("Holy Shield") },
            { "Seal of Fury", "Seal of Fury", cast("Seal of Fury") },
            { "Tank Pull", "Judgement on your mouseover or target with auto attack", "#showtooltip\n/startattack\n/cast [@mouseover,harm,nodead][] {Judgement}" },
            { "Tank Consecrate", "Consecration with auto attack", atk("Consecration") },
            { "Holy Wrath", "Holy Wrath", cast("Holy Wrath") },
            { "Save Ally", "Blessing of Protection on the ally under your mouse (drops physical threat)", "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead] {Blessing of Protection}" },
            { "Tank Strike", "Holy Strike, Shift for Judgement", "#showtooltip\n/startattack\n/cast [mod:shift] {Judgement}; {Holy Strike}" },
        },
        pvp = {
            { "Holy Shield PvP", "Holy Shield and attack the nearest enemy player", melee("Holy Shield") },
            { "Stun Mouseover", "Hammer of Justice on your mouseover", mo("Hammer of Justice") },
            { "Justice", "Seal of Justice then Judgement (two presses)", "#showtooltip\n/castsequence reset=8 {Seal of Justice}, {Judgement}" },
            { "Sacrifice Focus", "Blessing of Sacrifice on your focus", tank("Blessing of Sacrifice") },
            { "Tank Defensive", "Divine Protection even mid-cast", now("Divine Protection") },
        },
    },
    retribution = {
        pve = {
            { "Seal of Command", "Seal of Command", cast("Seal of Command") },
            { "Judge Strike", "Judgement, Shift for Holy Strike, with auto attack", "#showtooltip\n/startattack\n/cast [mod:shift] {Holy Strike}; {Judgement}" },
            { "Ret Burst", "Trinkets and Judgement", burst("Judgement") },
            { "Crusader", "Seal of the Crusader, Judgement, then Seal of Command (one per press)", "#showtooltip\n/castsequence reset=10 {Seal of the Crusader}, {Judgement}, {Seal of Command}" },
            { "Ret Aura", "Retribution Aura", cast("Retribution Aura") },
            { "Might Self", "Blessing of Might on yourself", me("Blessing of Might") },
            { "Quick Exorcism", "Exorcism with auto attack", atk("Exorcism") },
        },
        pvp = {
            { "Turn Evil", "Turn Evil on focus, mouseover or target", foc("Turn Evil"), V },
            { "Stun Burst", "Hammer of Justice and trinkets", "#showtooltip {Hammer of Justice}\n/use 13\n/use 14\n/cast {Hammer of Justice}" },
            { "Judge Player", "Target an enemy player and judge", melee("Judgement") },
            { "Freedom Self", "Blessing of Freedom on yourself", me("Blessing of Freedom") },
            { "Ret Justice", "Seal of Justice; Shift for Seal of Command", shift("Seal of Justice", "Seal of Command") },
            { "Quick Hammer", "Hammer of Wrath on the enemy under your mouse, even mid-cast", "#showtooltip\n/stopcasting\n/cast [@mouseover,harm,nodead][] {Hammer of Wrath}" },
        },
    },
})

---------------------------------------------------------------------------
-- Hunter
---------------------------------------------------------------------------
Macros:RegisterPack("HUNTER", {
    all = {
        any = {
            { "Hunter's Mark", "Hunter's Mark and send the pet in", pet("Hunter's Mark") },
            { "Auto Shot", "Auto Shot (never toggles off) and send the pet in", "#showtooltip {Auto Shot}\n/petattack\n/cast !{Auto Shot}" },
            { "Arcane Shot", "Arcane Shot and send the pet in", pet("Arcane Shot") },
            { "Aimed Shot", "Aimed Shot and send the pet in", pet("Aimed Shot") },
            { "Multi-Shot", "Multi-Shot", cast("Multi-Shot") },
            { "Serpent Sting", "Serpent Sting on your mouseover or target", mo("Serpent Sting") },
            { "Concussive Shot", "Concussive Shot on your mouseover or target", mo("Concussive Shot") },
            { "Feign Death", "Feign Death: stops everything; Ctrl calls the pet back", "#showtooltip {Feign Death}\n/stopattack\n/stopcasting\n/petfollow [mod:ctrl]\n/cast {Feign Death}" },
            { "Pet Control", "Attack; Shift follow; Ctrl stay", "/petattack [nomod]\n/petfollow [mod:shift]\n/petstay [mod:ctrl]" },
            { "Pet Mouseover", "Send the pet to your mouseover", "/petattack [@mouseover,harm,nodead][]" },
            { "Mend Pet", "Mend Pet; Revive Pet if dead; Call Pet if missing", "#showtooltip\n/cast [nopet] {Call Pet}; [@pet,dead] {Revive Pet}; {Mend Pet}" },
            { "Aspects", "Hawk; Shift Monkey; Ctrl Cheetah", "#showtooltip\n/cast [mod:shift] {Aspect of the Monkey}; [mod:ctrl] {Aspect of the Cheetah}; {Aspect of the Hawk}" },
            { "Melee", "Raptor Strike, Shift for Mongoose Bite", "#showtooltip\n/startattack\n/cast [mod:shift] {Mongoose Bite}; {Raptor Strike}" },
            { "Wing Clip", "Wing Clip with auto attack", atk("Wing Clip") },
            { "Disengage", "Disengage", cast("Disengage") },
            { "Frost Traps", "Freezing Trap; Shift for Frost Trap", shift("Freezing Trap", "Frost Trap") },
            { "Fire Traps", "Explosive Trap; Shift for Immolation Trap", shift("Explosive Trap", "Immolation Trap") },
            { "Flare", "Flare at your cursor", ground("Flare") },
        },
        pve = {
            { "Tranq Shot", "Tranquilizing Shot on your mouseover or target", mo("Tranquilizing Shot") },
            { "Distracting Shot", "Distracting Shot on your mouseover (pulls a mob off the healer)", mo("Distracting Shot") },
            { "Volley", "Volley at your cursor", ground("Volley") },
            { "Scare Beast", "Scare Beast on focus, mouseover or target", foc("Scare Beast") },
            { "Trap Pull", "Call the pet back and drop Freezing Trap", "#showtooltip {Freezing Trap}\n/petfollow\n/cast {Freezing Trap}" },
        },
        pvp = {
            { "Viper Sting", "Viper Sting on focus, mouseover or target", foc("Viper Sting") },
            { "Scorpid Sting", "Scorpid Sting on your mouseover or target", mo("Scorpid Sting") },
            { "Conc Player", "Target an enemy player and slow them", pvp("Concussive Shot") },
            { "Deterrence", "Deterrence and Aspect of the Monkey", "#showtooltip {Deterrence}\n/cast {Deterrence}\n/cast !{Aspect of the Monkey}" },
            { "Escape", "Wing Clip then Disengage (two presses)", "#showtooltip\n/castsequence reset=6 {Wing Clip}, {Disengage}" },
            { "Feign Trap", "Feign Death then Freezing Trap (two presses)", "#showtooltip\n/stopattack\n/petfollow\n/castsequence reset=8 {Feign Death}, {Freezing Trap}" },
            { "Pack", "Aspect of the Pack; Shift for Aspect of the Cheetah", shift("Aspect of the Pack", "Aspect of the Cheetah") },
        },
    },
    beastmastery = {
        pve = {
            { "Bestial Wrath", "Trinkets and Bestial Wrath with the pet attacking", "#showtooltip {Bestial Wrath}\n/petattack\n/use 13\n/use 14\n/cast {Bestial Wrath}" },
            { "Intimidation", "Intimidation on your mouseover or target", "#showtooltip {Intimidation}\n/petattack [@mouseover,harm,nodead][]\n/cast {Intimidation}" },
            { "Summon Hawk", "Summon Hawk", cast("Summon Hawk"), V },
            { "Quick Mend", "Mend Pet even mid-cast", now("Mend Pet") },
            { "Swap Target", "Move the pet to the new target and shoot", "#showtooltip {Arcane Shot}\n/petattack\n/cast !{Auto Shot}\n/cast {Arcane Shot}" },
            { "Beast Aspects", "Aspect of the Beast; Shift for Aspect of the Wild", shift("Aspect of the Beast", "Aspect of the Wild") },
            { "Pet Passive", "Call the pet back and set it to passive", "/petfollow\n/petpassive" },
        },
        pvp = {
            { "Pet Stun", "Intimidation on your focus", "#showtooltip {Intimidation}\n/petattack [@focus,harm,nodead][]\n/cast {Intimidation}" },
            { "BM Burst", "Bestial Wrath, trinkets and pet on the nearest enemy player", "#showtooltip {Bestial Wrath}\n/targetenemyplayer [noharm][dead]\n/petattack\n/use 13\n/use 14\n/cast {Bestial Wrath}" },
            { "Pet Focus", "Send the pet to your focus (e.g. the enemy healer)", "/petattack [@focus,harm,nodead]" },
            { "Pet Retreat", "Call the pet back and heal it", "#showtooltip {Mend Pet}\n/petfollow\n/cast {Mend Pet}" },
            { "Pet Dash", "Pet Dash or Dive onto the target", "/petattack\n/cast {Dash}\n/cast {Dive}" },
        },
    },
    marksmanship = {
        pve = {
            { "Sniper Shot", "Sniper Shot", cast("Sniper Shot"), V },
            { "Rapid Fire", "Trinkets and Rapid Fire", burst("Rapid Fire") },
            { "Aimed No Pet", "Aimed Shot without the pet (Lone Wolf)", "#showtooltip {Aimed Shot}\n/cast !{Auto Shot}\n/cast {Aimed Shot}" },
            { "Trueshot Aura", "Trueshot Aura", cast("Trueshot Aura") },
            { "Multi Arcane", "Multi-Shot, Shift for Arcane Shot", shift("Multi-Shot", "Arcane Shot") },
            { "Sting Mouseover", "Serpent Sting on mouseover; Shift for Scorpid Sting", "#showtooltip\n/cast [mod:shift,@mouseover,harm,nodead][mod:shift] {Scorpid Sting}; [@mouseover,harm,nodead][] {Serpent Sting}" },
            { "Dismiss Pet", "Dismiss Pet (for Lone Wolf)", cast("Dismiss Pet") },
        },
        pvp = {
            { "Sniper Mouseover", "Sniper Shot on your mouseover or target", mo("Sniper Shot"), V },
            { "Aimed Player", "Target an enemy player and Aimed Shot", pvp("Aimed Shot") },
            { "MM Burst", "Trinkets, Rapid Fire then Aimed Shot (two presses)", "#showtooltip\n/use 13\n/use 14\n/castsequence reset=20 {Rapid Fire}, {Aimed Shot}" },
            { "Quick Arcane", "Cancel your cast and Arcane Shot (to finish an enemy)", now("Arcane Shot") },
            { "Viper Mouseover", "Viper Sting on your mouseover", mo("Viper Sting") },
            { "Conc Focus", "Concussive Shot on your focus", "#showtooltip\n/cast [@focus,harm,nodead][] {Concussive Shot}" },
        },
    },
    survival = {
        pve = {
            { "Lacerating", "Lacerating Strikes with auto attack", atk("Lacerating Strikes"), V },
            { "Raptor Strike", "Raptor Strike with auto attack and pet", "#showtooltip {Raptor Strike}\n/petattack\n/startattack\n/cast {Raptor Strike}" },
            { "Mongoose Bite", "Mongoose Bite with auto attack", atk("Mongoose Bite") },
            { "Counterattack", "Counterattack with auto attack", atk("Counterattack") },
            { "Strider Kick", "Strider Kick on your mouseover or target", mo("Strider Kick"), V },
            { "Melee Traps", "Explosive Trap, then Immolation Trap (in combat)", "#showtooltip\n/castsequence reset=15 {Explosive Trap}, {Immolation Trap}" },
            { "Monkey", "Aspect of the Monkey; Shift for Aspect of the Hawk", shift("Aspect of the Monkey", "Aspect of the Hawk") },
        },
        pvp = {
            { "Kick Focus", "Strider Kick on your focus or mouseover", kick("Strider Kick"), V },
            { "Clip Player", "Target an enemy player and Wing Clip", melee("Wing Clip") },
            { "Counter Clip", "Counterattack, Shift for Wing Clip", "#showtooltip\n/startattack\n/cast [mod:shift] {Wing Clip}; {Counterattack}" },
            { "Quick Trap", "Freezing Trap at your feet even mid-action", "#showtooltip {Freezing Trap}\n/stopcasting\n/stopattack\n/cast {Freezing Trap}" },
            { "Quick Deterrence", "Deterrence even mid-cast", now("Deterrence") },
            { "Frost Trap PvP", "Frost Trap at your feet", cast("Frost Trap") },
        },
    },
})

---------------------------------------------------------------------------
-- Rogue
---------------------------------------------------------------------------
Macros:RegisterPack("ROGUE", {
    all = {
        any = {
            { "Sinister Strike", "Sinister Strike with auto attack", atk("Sinister Strike") },
            { "Opener", "Cheap Shot from stealth, Sinister Strike otherwise", "#showtooltip\n/cast [stealth] {Cheap Shot}; {Sinister Strike}" },
            { "Ambush", "Ambush from stealth, Backstab otherwise", "#showtooltip\n/cast [stealth] {Ambush}; {Backstab}" },
            { "Garrote", "Garrote from stealth, Rupture otherwise", "#showtooltip\n/cast [stealth] {Garrote}; {Rupture}" },
            { "Pick Open", "Pick Pocket and immediately Cheap Shot", "#showtooltip {Cheap Shot}\n/cast {Pick Pocket}\n/cast {Cheap Shot}" },
            { "Eviscerate", "Eviscerate with auto attack", atk("Eviscerate") },
            { "Slice and Dice", "Slice and Dice", cast("Slice and Dice") },
            { "Kidney Shot", "Kidney Shot; Cheap Shot from stealth", "#showtooltip\n/cast [stealth] {Cheap Shot}; {Kidney Shot}" },
            { "Kick", "Kick on focus, mouseover or target", foc("Kick") },
            { "Gouge", "Gouge your mouseover or target and stop attacking", "#showtooltip {Gouge}\n/stopattack\n/cast [@mouseover,harm,nodead][] {Gouge}" },
            { "Sap", "Sap your mouseover or focus; enters stealth if needed", "#showtooltip {Sap}\n/cast [nostealth,nocombat] {Stealth}\n/cast [@mouseover,harm,nodead][@focus,harm,nodead][] {Sap}" },
            { "Vanish", "Vanish: stops attacking first", "#showtooltip {Vanish}\n/stopattack\n/cast {Vanish}" },
            { "Escapes", "Evasion; Shift Sprint; Ctrl Vanish", "#showtooltip\n/stopattack [mod:ctrl]\n/cast [mod:shift] {Sprint}; [mod:ctrl] {Vanish}; {Evasion}" },
            { "Stealth", "Stealth without breaking it by accident", "#showtooltip\n/cast [nostealth] {Stealth}" },
            { "Blind", "Blind on focus, mouseover or target", foc("Blind") },
            { "Finishers", "Eviscerate; Shift Rupture; Ctrl Slice and Dice; Alt Expose Armor",
              "#showtooltip\n/cast [mod:shift] {Rupture}; [mod:ctrl] {Slice and Dice}; [mod:alt] {Expose Armor}; {Eviscerate}" },
        },
        pve = {
            { "Feint", "Feint (lowers threat)", cast("Feint") },
            { "Distract", "Distract at your cursor", ground("Distract") },
            { "Expose Armor", "Expose Armor with auto attack", atk("Expose Armor") },
            { "Kick Mouseover", "Kick your mouseover without changing target", mo("Kick") },
        },
        pvp = {
            { "Kick Focus", "Kick your focus only", "#showtooltip\n/cast [@focus,harm,nodead][] {Kick}" },
            { "Blind Focus", "Blind your focus only", onfocus("Blind") },
            { "Gouge Run", "Gouge then Sprint to get away (two presses)", "#showtooltip\n/stopattack\n/castsequence reset=10 {Gouge}, {Sprint}" },
            { "Sap Player", "Sap the nearest enemy player", "#showtooltip {Sap}\n/targetenemyplayer [noharm][dead]\n/cast {Sap}" },
            { "Vanish Open", "Vanish then Cheap Shot (two presses)", "#showtooltip\n/stopattack\n/castsequence reset=10 {Vanish}, {Cheap Shot}" },
            { "Quick Sprint", "Sprint even mid-action", now("Sprint") },
            { "Stealth PvP", "Stealth as soon as you leave combat", "#showtooltip {Stealth}\n/stopattack\n/cast [nostealth,nocombat] {Stealth}" },
        },
    },
    assassination = {
        pve = {
            { "Mutilate", "Mutilate with auto attack", atk("Mutilate") },
            { "Cold Blood Evis", "Cold Blood and Eviscerate", "#showtooltip {Eviscerate}\n/cast {Cold Blood}\n/cast {Eviscerate}" },
            { "Rupture", "Rupture with auto attack", atk("Rupture") },
            { "Assa Burst", "Trinkets and Cold Blood", burst("Cold Blood") },
            { "Garrote Open", "Garrote from stealth, Mutilate otherwise", "#showtooltip\n/cast [stealth] {Garrote}; {Mutilate}" },
            { "Backstab", "Backstab with auto attack", atk("Backstab") },
        },
        pvp = {
            { "Cold Blood Amb", "Cold Blood and Ambush from stealth", "#showtooltip {Ambush}\n/cast {Cold Blood}\n/cast {Ambush}" },
            { "Kidney Focus", "Kidney Shot on your focus", "#showtooltip\n/cast [@focus,harm,nodead][] {Kidney Shot}" },
            { "Mutilate PvP", "Target an enemy player and Mutilate", melee("Mutilate") },
            { "Stun Chain", "Cheap Shot from stealth, then Kidney Shot", "#showtooltip\n/cast [stealth] {Cheap Shot}; {Kidney Shot}", "Same as 'Kidney Shot', meant to sit on your opener key." },
            { "Garrote Caster", "Garrote your focus from stealth (silences)", "#showtooltip\n/cast [@focus,harm,nodead][] {Garrote}" },
        },
    },
    combat = {
        pve = {
            { "Blade Flurry", "Blade Flurry", cast("Blade Flurry") },
            { "Adrenaline Rush", "Trinkets and Adrenaline Rush", burst("Adrenaline Rush") },
            { "Combat Burst", "Trinkets, Blade Flurry and Adrenaline Rush", "#showtooltip {Adrenaline Rush}\n/use 13\n/use 14\n/cast {Blade Flurry}\n/cast {Adrenaline Rush}" },
            { "Riposte", "Riposte with auto attack", atk("Riposte") },
            { "SS Riposte", "Sinister Strike, Shift for Riposte", "#showtooltip\n/startattack\n/cast [mod:shift] {Riposte}; {Sinister Strike}" },
            { "SnD Evis", "Slice and Dice, Shift for Eviscerate", shift("Slice and Dice", "Eviscerate") },
        },
        pvp = {
            { "Riposte PvP", "Riposte the nearest enemy player (disarms)", melee("Riposte") },
            { "Rush Sprint", "Adrenaline Rush and Sprint", "#showtooltip {Adrenaline Rush}\n/cast {Adrenaline Rush}\n/cast {Sprint}" },
            { "Quick Evasion", "Evasion even mid-action", now("Evasion") },
            { "Quick Kick", "Kick your target, cancelling what you are doing", now("Kick") },
            { "Gouge Focus", "Gouge your focus", "#showtooltip\n/cast [@focus,harm,nodead][] {Gouge}" },
        },
    },
    subtlety = {
        pve = {
            { "Hemorrhage", "Hemorrhage with auto attack", atk("Hemorrhage") },
            { "Ghostly Strike", "Ghostly Strike with auto attack", atk("Ghostly Strike") },
            { "Premeditation", "Premeditation and Ambush from stealth", "#showtooltip {Ambush}\n/cast {Premeditation}\n/cast {Ambush}" },
            { "Preparation", "Preparation", cast("Preparation") },
            { "Hemo Open", "Garrote from stealth, Hemorrhage otherwise", "#showtooltip\n/cast [stealth] {Garrote}; {Hemorrhage}" },
            { "Thousand Cuts", "Thousand Cuts with auto attack", atk("Thousand Cuts"), V },
        },
        pvp = {
            { "Premed Cheap", "Premeditation and Cheap Shot from stealth", "#showtooltip {Cheap Shot}\n/cast {Premeditation}\n/cast {Cheap Shot}" },
            { "Reset", "Preparation and immediately Vanish", "#showtooltip {Preparation}\n/stopattack\n/cast {Preparation}\n/cast {Vanish}" },
            { "Sap Focus", "Sap your focus from stealth", onfocus("Sap") },
            { "Blind Mouseover", "Blind your mouseover", "#showtooltip\n/cast [@mouseover,harm,nodead] {Blind}" },
            { "Hemo PvP", "Target an enemy player and Hemorrhage", melee("Hemorrhage") },
            { "Ghostly PvP", "Ghostly Strike, Shift for Evasion", shift("Ghostly Strike", "Evasion") },
        },
    },
})

---------------------------------------------------------------------------
-- Priest
---------------------------------------------------------------------------
Macros:RegisterPack("PRIEST", {
    all = {
        any = {
            { "Flash Heal", "Flash Heal on mouseover, friendly target or yourself", heal("Flash Heal") },
            { "Heal", "Heal; Shift for Flash Heal, on mouseover", "#showtooltip\n/cast [mod:shift,@mouseover,help,nodead][mod:shift] {Flash Heal}; [@mouseover,help,nodead][] {Heal}" },
            { "Greater Heal", "Greater Heal on mouseover, friendly target or yourself", heal("Greater Heal") },
            { "Renew", "Renew on mouseover, friendly target or yourself", heal("Renew") },
            { "Shield", "Power Word: Shield on mouseover, friendly target or yourself", heal("Power Word: Shield") },
            { "Shield Self", "Power Word: Shield on yourself", me("Power Word: Shield") },
            { "Dispel", "Dispel Magic: unit under your mouse, otherwise your target (friend or enemy)", "#showtooltip\n/cast [@mouseover,exists,nodead][] {Dispel Magic}" },
            { "Disease", "Abolish Disease on mouseover, friendly target or yourself", heal("Abolish Disease") },
            { "Psychic Scream", "Psychic Scream even mid-cast", now("Psychic Scream") },
            { "Fade", "Fade", cast("Fade") },
            { "SW Pain", "Shadow Word: Pain on your mouseover or target", mo("Shadow Word: Pain") },
            { "Fear Ward", "Fear Ward on mouseover, friendly target or yourself", heal("Fear Ward") },
            { "Wand", "Wand without toggling it off", "#showtooltip {Shoot}\n/cast !{Shoot}" },
            { "Fortitude", "Power Word: Fortitude on mouseover; Shift for Divine Spirit", "#showtooltip\n/cast [mod:shift,@mouseover,help][mod:shift] {Divine Spirit}; [@mouseover,help][] {Power Word: Fortitude}" },
            { "Inner Fire", "Inner Fire", cast("Inner Fire") },
            { "Resurrect", "Resurrection on your mouseover or target", "#showtooltip\n/cast [@mouseover,help,dead][] {Resurrection}" },
            { "SW Death", "Shadow Word: Death on your mouseover or target", mo("Shadow Word: Death") },
        },
        pve = {
            { "Prayer Healing", "Prayer of Healing", cast("Prayer of Healing") },
            { "Shackle", "Shackle Undead on focus, mouseover or target", foc("Shackle Undead") },
            { "Heal Tank", "Greater Heal on your focus (set the tank as focus)", tank("Greater Heal") },
            { "Shield Tank", "Power Word: Shield then Renew on your focus (two presses)", "#showtooltip\n/castsequence [@focus,help,nodead][] reset=6 {Power Word: Shield}, {Renew}" },
            { "Mind Soothe", "Mind Soothe on your mouseover or target", mo("Mind Soothe") },
        },
        pvp = {
            { "Dispel Enemy", "Dispel Magic on an enemy: focus, mouseover or target", foc("Dispel Magic") },
            { "Dispel Self", "Dispel Magic on yourself", me("Dispel Magic") },
            { "Mana Burn", "Mana Burn on focus, mouseover or target", foc("Mana Burn") },
            { "Quick Heal", "Cancel your cast and Flash Heal the mouseover", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead][@player] {Flash Heal}" },
            { "Mind Control", "Mind Control on focus, mouseover or target", foc("Mind Control") },
            { "Scream Shield", "Psychic Scream then Power Word: Shield on yourself (two presses)", "#showtooltip\n/stopcasting\n/castsequence [@player] reset=8 {Psychic Scream}, {Power Word: Shield}" },
            { "Quick SWD", "Cancel your cast and Shadow Word: Death (to finish an enemy)", now("Shadow Word: Death") },
        },
    },
    discipline = {
        pve = {
            { "Penance", "Penance: heals the friend under your mouse, otherwise damages your target", "#showtooltip\n/cast [@mouseover,help,nodead][@mouseover,harm,nodead][] {Penance}", V },
            { "Penance Tank", "Penance on your focus", tank("Penance"), V },
            { "Inner Focus GH", "Inner Focus and Greater Heal on mouseover", "#showtooltip {Greater Heal}\n/cast {Inner Focus}\n/cast [@mouseover,help,nodead][help,nodead][@player] {Greater Heal}" },
            { "Shield ToT", "Power Word: Shield on your enemy target's target", tot("Power Word: Shield") },
            { "Divine Spirit", "Divine Spirit on mouseover, friendly target or yourself", heal("Divine Spirit") },
            { "Smite", "Smite on your mouseover or target", mo("Smite") },
        },
        pvp = {
            { "Penance Self", "Penance on yourself", me("Penance"), V },
            { "Quick Shield", "Cancel your cast and Power Word: Shield the mouseover", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead][@player] {Power Word: Shield}" },
            { "Burn Focus", "Mana Burn on your focus only", onfocus("Mana Burn") },
            { "Focus Burn", "Inner Focus and Mana Burn on your focus", "#showtooltip {Mana Burn}\n/cast {Inner Focus}\n/cast [@focus,harm,nodead][] {Mana Burn}" },
            { "Dispel Focus", "Dispel Magic on your enemy focus only", onfocus("Dispel Magic") },
            { "Penance Damage", "Penance on the nearest enemy player", pvp("Penance"), V },
        },
    },
    holy = {
        pve = {
            { "Prayer Mending", "Prayer of Mending on focus, mouseover or friendly target", "#showtooltip\n/cast [@focus,help,nodead][@mouseover,help,nodead][] {Prayer of Mending}", V },
            { "Binding Heal", "Binding Heal on mouseover or friendly target", "#showtooltip\n/cast [@mouseover,help,nodead][] {Binding Heal}", V },
            { "Holy Nova", "Holy Nova", cast("Holy Nova") },
            { "Holy Fire", "Holy Fire on your mouseover or target", mo("Holy Fire") },
            { "Renew Focus", "Renew on your focus", tank("Renew") },
            { "Heal ToT", "Flash Heal on your enemy target's target", tot("Flash Heal") },
            { "Lesser Heal", "Lesser Heal on mouseover, friendly target or yourself (cheap heal)", heal("Lesser Heal") },
        },
        pvp = {
            { "Mending Self", "Prayer of Mending on yourself", me("Prayer of Mending"), V },
            { "Renew Self", "Renew on yourself", me("Renew") },
            { "Quick Nova", "Cancel your cast and Holy Nova", now("Holy Nova") },
            { "Quick Binding", "Cancel your cast and Binding Heal the mouseover", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][] {Binding Heal}", V },
            { "Flash Self", "Flash Heal on yourself", me("Flash Heal") },
            { "Disease Self", "Abolish Disease on yourself", me("Abolish Disease") },
        },
    },
    shadow = {
        pve = {
            { "Mind Blast", "Mind Blast", cast("Mind Blast") },
            { "Mind Flay", "Mind Flay without clipping the current channel", "#showtooltip\n/cast [nochanneling] {Mind Flay}" },
            { "Devouring Plague", "Devouring Plague on your mouseover or target", mo("Devouring Plague") },
            { "Vampiric Embrace", "Vampiric Embrace on your mouseover or target", mo("Vampiric Embrace") },
            { "Shadowform", "Shadowform without leaving it by accident", "#showtooltip\n/cast !{Shadowform}" },
            { "Shadow Burst", "Trinkets and Mind Blast", burst("Mind Blast") },
            { "Shadow Dots", "Shadow Word: Pain then Devouring Plague (two presses)", "#showtooltip\n/castsequence reset=target/8 {Shadow Word: Pain}, {Devouring Plague}" },
        },
        pvp = {
            { "Silence", "Silence on focus, mouseover or target, even mid-cast", kick("Silence") },
            { "Silence Focus", "Silence your focus only", "#showtooltip\n/stopcasting\n/cast [@focus,harm,nodead] {Silence}" },
            { "Pain Player", "Shadow Word: Pain on the nearest enemy player", pvp("Shadow Word: Pain") },
            { "Unform Heal", "Leave Shadowform and Flash Heal yourself", "#showtooltip {Flash Heal}\n/cancelaura {Shadowform}\n/cast [@player] {Flash Heal}" },
            { "Blast Player", "Mind Blast on the nearest enemy player", pvp("Mind Blast") },
            { "Plague Focus", "Devouring Plague on your focus", "#showtooltip\n/cast [@focus,harm,nodead][] {Devouring Plague}" },
            { "Flay Mouseover", "Mind Flay on your mouseover (slows runners)", mo("Mind Flay") },
        },
    },
})

---------------------------------------------------------------------------
-- Shaman
---------------------------------------------------------------------------
Macros:RegisterPack("SHAMAN", {
    all = {
        any = {
            { "Earth Shock", "Earth Shock on focus, mouseover or target, even mid-cast", kick("Earth Shock") },
            { "Shocks", "Earth Shock; Shift Flame Shock; Ctrl Frost Shock", "#showtooltip\n/cast [mod:shift] {Flame Shock}; [mod:ctrl] {Frost Shock}; {Earth Shock}" },
            { "Lightning Bolt", "Lightning Bolt; Shift for Chain Lightning", shift("Lightning Bolt", "Chain Lightning") },
            { "Healing Wave", "Healing Wave on mouseover, friendly target or yourself", heal("Healing Wave") },
            { "Lesser Wave", "Lesser Healing Wave on mouseover, friendly target or yourself", heal("Lesser Healing Wave") },
            { "Chain Heal", "Chain Heal on mouseover, friendly target or yourself", heal("Chain Heal") },
            { "Purge", "Purge on focus, mouseover or target", foc("Purge") },
            { "Cures", "Cure Poison; Shift for Cure Disease, on mouseover", "#showtooltip\n/cast [mod:shift,@mouseover,help][mod:shift] {Cure Disease}; [@mouseover,help,nodead][help,nodead][@player] {Cure Poison}" },
            { "Totems", "Call of the Elements; Shift for Totemic Recall", shift("Call of the Elements", "Totemic Recall") },
            { "Totems 2", "Call of the Spirits; Shift for Call of the Ancestors", shift("Call of the Spirits", "Call of the Ancestors") },
            { "Move Totems", "Totemic Projection at your cursor", ground("Totemic Projection") },
            { "Shields", "Lightning Shield; Shift for Water Shield", shift("Lightning Shield", "Water Shield") },
            { "Ghost Wolf", "Ghost Wolf without leaving it by accident", "#showtooltip\n/cast !{Ghost Wolf}" },
            { "Fire Nova", "Fire Nova", cast("Fire Nova") },
            { "Imbues", "Windfury Weapon; Shift Flametongue; Ctrl Rockbiter; Alt Frostbrand",
              "#showtooltip\n/cast [mod:shift] {Flametongue Weapon}; [mod:ctrl] {Rockbiter Weapon}; [mod:alt] {Frostbrand Weapon}; {Windfury Weapon}" },
            { "Resurrect", "Ancestral Spirit on your mouseover or target", "#showtooltip\n/cast [@mouseover,help,dead][] {Ancestral Spirit}" },
        },
        pve = {
            { "Earth Totems", "Strength of Earth Totem; Shift for Stoneskin Totem", shift("Strength of Earth Totem", "Stoneskin Totem") },
            { "Air Totems", "Windfury Totem; Shift for Grace of Air Totem", shift("Windfury Totem", "Grace of Air Totem") },
            { "Water Totems", "Mana Spring Totem; Shift for Healing Stream Totem", shift("Mana Spring Totem", "Healing Stream Totem") },
            { "Fire Totems", "Searing Totem; Shift for Magma Totem", shift("Searing Totem", "Magma Totem") },
            { "Tremor", "Tremor Totem; Shift for Poison Cleansing Totem", shift("Tremor Totem", "Poison Cleansing Totem") },
        },
        pvp = {
            { "Earthbind", "Earthbind Totem even mid-cast", now("Earthbind Totem") },
            { "Grounding", "Grounding Totem even mid-cast", now("Grounding Totem") },
            { "Tremor PvP", "Tremor Totem even mid-cast", now("Tremor Totem") },
            { "Frost Shock", "Frost Shock on the nearest enemy player", pvp("Frost Shock") },
            { "Purge Mouseover", "Purge your mouseover", mo("Purge") },
            { "Shock Focus", "Earth Shock your focus only", "#showtooltip\n/stopcasting\n/cast [@focus,harm,nodead] {Earth Shock}" },
            { "Shock Rank 1", "Rank 1 Earth Shock on your mouseover (cheap interrupt)", "#showtooltip {Earth Shock}\n/stopcasting\n/cast [@mouseover,harm,nodead][] {Earth Shock}(Rank 1)", R },
            { "Stoneclaw", "Stoneclaw Totem", cast("Stoneclaw Totem") },
        },
    },
    elemental = {
        pve = {
            { "Lava Burst", "Lava Burst on your mouseover or target", mo("Lava Burst"), V },
            { "Flame Lava", "Flame Shock then Lava Burst (two presses)", "#showtooltip\n/castsequence reset=target/10 {Flame Shock}, {Lava Burst}", V },
            { "Chain Lightning", "Chain Lightning on your mouseover or target", mo("Chain Lightning") },
            { "Elemental Burst", "Trinkets and Chain Lightning", burst("Chain Lightning") },
            { "Flame Shock", "Flame Shock on your mouseover or target", mo("Flame Shock") },
            { "Bolt Mouseover", "Lightning Bolt on your mouseover or target", mo("Lightning Bolt") },
            { "Earthbound", "Earthbound", cast("Earthbound"), V },
        },
        pvp = {
            { "Lava Player", "Lava Burst on the nearest enemy player", pvp("Lava Burst"), V },
            { "Quick Chain", "Cancel your cast and Chain Lightning", now("Chain Lightning") },
            { "Frost Mouseover", "Frost Shock your mouseover (slows runners)", mo("Frost Shock") },
            { "Ele PvP Burst", "Trinkets, Chain Lightning then Earth Shock (two presses)", "#showtooltip\n/use 13\n/use 14\n/castsequence reset=8 {Chain Lightning}, {Earth Shock}" },
            { "Ele Quick Heal", "Cancel your cast and Lesser Healing Wave yourself", "#showtooltip\n/stopcasting\n/cast [@player] {Lesser Healing Wave}" },
            { "Purge Focus", "Purge your focus only", onfocus("Purge") },
        },
    },
    enhancement = {
        pve = {
            { "Stormstrike", "Stormstrike with auto attack", atk("Stormstrike") },
            { "Storm Shock", "Stormstrike, Shift for Earth Shock", "#showtooltip\n/startattack\n/cast [mod:shift] {Earth Shock}; {Stormstrike}" },
            { "Rage of Farseer", "Trinkets and Rage of the Farseer", burst("Rage of the Farseer"), V },
            { "Melee Shock", "Flame Shock with auto attack", atk("Flame Shock") },
            { "Maelstrom Bolt", "Instant Lightning Bolt; Shift for Chain Lightning (with Maelstrom Weapon)", shift("Lightning Bolt", "Chain Lightning"), V },
            { "Windfury Weapon", "Windfury Weapon", cast("Windfury Weapon") },
            { "Melee Nova", "Fire Nova with auto attack", atk("Fire Nova") },
        },
        pvp = {
            { "Storm Player", "Target an enemy player and Stormstrike", melee("Stormstrike") },
            { "Melee Frost", "Frost Shock with auto attack", atk("Frost Shock") },
            { "Quick Wolf", "Ghost Wolf even mid-action", "#showtooltip {Ghost Wolf}\n/stopcasting\n/cast !{Ghost Wolf}" },
            { "Maelstrom Heal", "Lesser Healing Wave on yourself; Shift on mouseover", "#showtooltip\n/cast [mod:shift,@mouseover,help,nodead][@player] {Lesser Healing Wave}", V },
            { "Enh PvP Burst", "Trinkets, Rage of the Farseer and Stormstrike", "#showtooltip {Stormstrike}\n/use 13\n/use 14\n/cast {Rage of the Farseer}\n/cast {Stormstrike}", V },
            { "Melee Purge", "Purge with auto attack", atk("Purge") },
        },
    },
    restoration = {
        pve = {
            { "Riptide", "Riptide on mouseover, friendly target or yourself", heal("Riptide"), V },
            { "Riptide Tank", "Riptide on your focus", tank("Riptide"), V },
            { "Heal Tank", "Healing Wave on your focus (set the tank as focus)", tank("Healing Wave") },
            { "Chain Tank", "Chain Heal on your focus", tank("Chain Heal") },
            { "Mana Tide", "Mana Tide Totem", cast("Mana Tide Totem") },
            { "Water Shield", "Water Shield", cast("Water Shield"), V },
            { "Heal ToT", "Lesser Healing Wave on your enemy target's target", tot("Lesser Healing Wave") },
            { "Healing Stream", "Healing Stream Totem", cast("Healing Stream Totem") },
        },
        pvp = {
            { "Riptide Self", "Riptide on yourself", me("Riptide"), V },
            { "Quick Riptide", "Cancel your cast and Riptide the mouseover", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead][@player] {Riptide}", V },
            { "Lesser Self", "Lesser Healing Wave on yourself", me("Lesser Healing Wave") },
            { "Shock and Heal", "Earth Shock an enemy mouseover without losing your friendly target", "#showtooltip {Earth Shock}\n/stopcasting\n/cast [@mouseover,harm,nodead][@focus,harm,nodead] {Earth Shock}" },
            { "Poison Self", "Cure Poison on yourself", me("Cure Poison") },
            { "Grounding Heal", "Grounding Totem then Lesser Healing Wave on yourself (two presses)", "#showtooltip\n/stopcasting\n/castsequence [@player] reset=8 {Grounding Totem}, {Lesser Healing Wave}" },
        },
    },
})

---------------------------------------------------------------------------
-- Mage
---------------------------------------------------------------------------
Macros:RegisterPack("MAGE", {
    all = {
        any = {
            { "Polymorph", "Polymorph on focus, mouseover or target; Shift sets the focus first",
              "#showtooltip {Polymorph}\n/focus [mod:shift,@mouseover,harm][mod:shift]\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {Polymorph}" },
            { "Counterspell", "Counterspell on focus, mouseover or target, even mid-cast", kick("Counterspell") },
            { "Blink", "Blink even mid-cast", now("Blink") },
            { "Ice Block", "Ice Block even mid-cast; press again to break it", "#showtooltip {Ice Block}\n/stopcasting\n/cancelaura {Ice Block}\n/cast {Ice Block}" },
            { "Frost Nova", "Frost Nova even mid-cast", now("Frost Nova") },
            { "Fire Blast", "Fire Blast on your mouseover or target", mo("Fire Blast") },
            { "Cone of Cold", "Cone of Cold", cast("Cone of Cold") },
            { "Arcane Explosion", "Arcane Explosion", cast("Arcane Explosion") },
            { "Blizzard", "Blizzard at your cursor", ground("Blizzard") },
            { "Flamestrike", "Flamestrike at your cursor", ground("Flamestrike") },
            { "Intellect", "Arcane Intellect on mouseover, friendly target or yourself", heal("Arcane Intellect") },
            { "Decurse", "Remove Lesser Curse on mouseover, friendly target or yourself", heal("Remove Lesser Curse") },
            { "Armors", "Mage Armor; Shift for Ice Armor", shift("Mage Armor", "Ice Armor") },
            { "Mana Shield", "Mana Shield", cast("Mana Shield") },
            { "Evocation", "Evocation", cast("Evocation") },
            { "Wand", "Wand without toggling it off", "#showtooltip {Shoot}\n/cast !{Shoot}" },
            { "Water Food", "Conjure Water; Shift for Conjure Food", shift("Conjure Water", "Conjure Food") },
            { "Frostfire Bolt", "Frostfire Bolt on your mouseover or target", mo("Frostfire Bolt"), V },
        },
        pve = {
            { "Poly Focus", "Polymorph your focus only (re-sheep)", onfocus("Polymorph") },
            { "Scorch", "Scorch on your mouseover or target", mo("Scorch") },
            { "Decurse Focus", "Remove Lesser Curse on your focus", tank("Remove Lesser Curse") },
        },
        pvp = {
            { "CS Focus", "Counterspell your focus only", "#showtooltip\n/stopcasting\n/cast [@focus,harm,nodead] {Counterspell}" },
            { "Poly Mouseover", "Polymorph your mouseover", "#showtooltip\n/cast [@mouseover,harm,nodead] {Polymorph}" },
            { "Poly Player", "Polymorph the nearest enemy player", pvp("Polymorph") },
            { "Nova Blink", "Frost Nova then Blink (two presses)", "#showtooltip\n/stopcasting\n/castsequence reset=8 {Frost Nova}, {Blink}" },
            { "Quick Blast", "Cancel your cast and Fire Blast (to finish an enemy)", now("Fire Blast") },
            { "Decurse Self", "Remove Lesser Curse on yourself", me("Remove Lesser Curse") },
            { "Wards", "Mana Shield; Shift Fire Ward; Ctrl Frost Ward", "#showtooltip\n/cast [mod:shift] {Fire Ward}; [mod:ctrl] {Frost Ward}; {Mana Shield}" },
        },
    },
    arcane = {
        pve = {
            { "Arcane Blast", "Arcane Blast", cast("Arcane Blast"), V },
            { "Arcane Missiles", "Arcane Missiles without clipping the current channel", "#showtooltip\n/cast [nochanneling] {Arcane Missiles}" },
            { "Arcane Burst", "Trinkets and Arcane Power", burst("Arcane Power") },
            { "PoM Blast", "Presence of Mind and Arcane Blast", "#showtooltip {Presence of Mind}\n/cast {Presence of Mind}\n/cast {Arcane Blast}", V },
            { "Arcane Power", "Arcane Power", cast("Arcane Power") },
            { "Blast Missiles", "Arcane Blast, Shift for Arcane Missiles", shift("Arcane Blast", "Arcane Missiles"), V },
            { "Quick Evocation", "Cancel your cast and Evocation", now("Evocation") },
        },
        pvp = {
            { "PoM Pyro", "Presence of Mind and an instant Pyroblast", "#showtooltip {Presence of Mind}\n/stopcasting\n/cast {Presence of Mind}\n/cast {Pyroblast}" },
            { "PoM Poly", "Presence of Mind and an instant Polymorph on your focus", "#showtooltip {Polymorph}\n/stopcasting\n/cast {Presence of Mind}\n/cast [@focus,harm,nodead][] {Polymorph}" },
            { "Arcane PvP Burst", "Trinkets, Arcane Power and Presence of Mind", "#showtooltip {Arcane Power}\n/use 13\n/use 14\n/cast {Arcane Power}\n/cast {Presence of Mind}" },
            { "Missiles Mouse", "Arcane Missiles on your mouseover", mo("Arcane Missiles") },
            { "Quick Explosion", "Cancel your cast and Arcane Explosion (reveals rogues)", now("Arcane Explosion") },
        },
    },
    fire = {
        pve = {
            { "Fireball", "Fireball", cast("Fireball") },
            { "Pyroblast", "Pyroblast on your mouseover or target", mo("Pyroblast") },
            { "Fire Burst", "Trinkets and Combustion", burst("Combustion") },
            { "Blast Wave", "Blast Wave", cast("Blast Wave") },
            { "Scorch Fireball", "Fireball, Shift for Scorch", shift("Fireball", "Scorch") },
            { "Pyro Pull", "Pyroblast then Fireball (two presses)", "#showtooltip\n/castsequence reset=combat/target {Pyroblast}, {Fireball}" },
            { "Fire Ward", "Fire Ward", cast("Fire Ward") },
        },
        pvp = {
            { "Pyro Player", "Pyroblast the nearest enemy player", pvp("Pyroblast") },
            { "Quick Wave", "Cancel your cast and Blast Wave", now("Blast Wave") },
            { "Scorch Mouseover", "Scorch your mouseover", mo("Scorch") },
            { "Fire PvP Burst", "Trinkets, Combustion and Fire Blast", "#showtooltip {Combustion}\n/use 13\n/use 14\n/cast {Combustion}\n/cast {Fire Blast}" },
            { "Blast Mouseover", "Fire Blast your mouseover without changing target", "#showtooltip\n/stopcasting\n/cast [@mouseover,harm,nodead] {Fire Blast}" },
        },
    },
    frost = {
        pve = {
            { "Frostbolt", "Frostbolt", cast("Frostbolt") },
            { "Ice Lance", "Ice Lance on your mouseover or target", mo("Ice Lance"), V },
            { "Cold Snap", "Cold Snap", cast("Cold Snap") },
            { "Ice Barrier", "Ice Barrier", cast("Ice Barrier") },
            { "Frost Burst", "Trinkets and Frostbolt", burst("Frostbolt") },
            { "Bolt Lance", "Frostbolt, Shift for Ice Lance", shift("Frostbolt", "Ice Lance"), V },
            { "Quick Blizzard", "Cancel your cast and Blizzard at your cursor", "#showtooltip\n/stopcasting\n/cast [@cursor] {Blizzard}" },
        },
        pvp = {
            { "Quick Lance", "Cancel your cast and Ice Lance (on frozen enemies)", now("Ice Lance"), V },
            { "Nova Lance", "Frost Nova then Ice Lance (two presses)", "#showtooltip\n/stopcasting\n/castsequence reset=6 {Frost Nova}, {Ice Lance}", V },
            { "Bolt Player", "Frostbolt the nearest enemy player", pvp("Frostbolt") },
            { "Quick Barrier", "Ice Barrier even mid-cast", now("Ice Barrier") },
            { "Snap Block", "Cold Snap and immediately Ice Block", "#showtooltip {Ice Block}\n/stopcasting\n/cast {Cold Snap}\n/cast {Ice Block}" },
            { "Quick Cone", "Cancel your cast and Cone of Cold", now("Cone of Cold") },
            { "Bolt Rank 1", "Rank 1 Frostbolt (cheap slow)", "#showtooltip {Frostbolt}\n/cast {Frostbolt}(Rank 1)", R },
        },
    },
})

---------------------------------------------------------------------------
-- Warlock
---------------------------------------------------------------------------
Macros:RegisterPack("WARLOCK", {
    all = {
        any = {
            { "Shadow Bolt", "Shadow Bolt and send the demon in", pet("Shadow Bolt") },
            { "Corruption", "Corruption on your mouseover or target", mo("Corruption") },
            { "Bane of Agony", "Bane of Agony on your mouseover or target", mo("Bane of Agony") },
            { "Curses", "Bane of Agony; Shift Curse of the Elements; Ctrl Curse of Weakness",
              "#showtooltip\n/cast [mod:shift] {Curse of the Elements}; [mod:ctrl] {Curse of Weakness}; {Bane of Agony}" },
            { "Immolate", "Immolate on your mouseover or target", mo("Immolate") },
            { "Fear", "Fear on focus, mouseover or target", foc("Fear") },
            { "Life Tap", "Life Tap", cast("Life Tap") },
            { "Drain Life", "Drain Life without clipping the current channel", "#showtooltip\n/cast [nochanneling] {Drain Life}" },
            { "Drain Soul", "Drain Soul for soul shards", "#showtooltip\n/cast [nochanneling] {Drain Soul}" },
            { "Demon Control", "Attack; Shift calls it back and sets passive", "/petattack [nomod]\n/petfollow [mod:shift]\n/petpassive [mod:shift]" },
            { "Demon Mouseover", "Send the demon to your mouseover", "/petattack [@mouseover,harm,nodead][]" },
            { "Health Funnel", "Health Funnel", cast("Health Funnel") },
            { "Stones", "Create Healthstone; Shift for Create Soulstone", shift("Create Healthstone", "Create Soulstone") },
            { "Death Coil", "Death Coil on your mouseover or target, even mid-cast", "#showtooltip\n/stopcasting\n/cast [@mouseover,harm,nodead][] {Death Coil}" },
            { "Howl of Terror", "Howl of Terror", cast("Howl of Terror") },
            { "Demon Armor", "Demon Armor", cast("Demon Armor") },
            { "Summon", "Summon Imp; Shift Voidwalker; Ctrl Succubus; Alt Felhunter",
              "#showtooltip\n/cast [mod:shift] {Summon Voidwalker}; [mod:ctrl] {Summon Succubus}; [mod:alt] {Summon Felhunter}; {Summon Imp}" },
            { "Wand", "Wand without toggling it off", "#showtooltip {Shoot}\n/cast !{Shoot}" },
        },
        pve = {
            { "Banish", "Banish on focus, mouseover or target", foc("Banish") },
            { "Rain of Fire", "Rain of Fire at your cursor", ground("Rain of Fire") },
            { "Bane of Doom", "Bane of Doom on your mouseover or target", mo("Bane of Doom") },
            { "Elements", "Curse of the Elements on your mouseover or target", mo("Curse of the Elements") },
            { "Soulstone", "Use your soulstone on the mouseover or friendly target", "#showtooltip\n/use [@mouseover,help,nodead][help,nodead] Major Soulstone\n/use [@mouseover,help,nodead][help,nodead] Soulstone" },
            { "Hellfire", "Hellfire", cast("Hellfire") },
        },
        pvp = {
            { "Fear Focus", "Fear your focus only", onfocus("Fear") },
            { "Fear Mouseover", "Fear your mouseover", "#showtooltip\n/cast [@mouseover,harm,nodead] {Fear}" },
            { "Tongues", "Curse of Tongues on focus, mouseover or target", foc("Curse of Tongues") },
            { "Exhaustion", "Curse of Exhaustion on your mouseover or target", mo("Curse of Exhaustion") },
            { "Spell Lock", "Felhunter's Spell Lock on focus, mouseover or target", foc("Spell Lock") },
            { "Devour Magic", "Felhunter's Devour Magic on mouseover, target or yourself", "#showtooltip\n/cast [@mouseover,exists,nodead][exists,nodead][@player] {Devour Magic}" },
            { "Seduction", "Succubus' Seduction on focus, mouseover or target", foc("Seduction") },
            { "Coil Player", "Death Coil the nearest enemy player", pvp("Death Coil") },
            { "Drain Mana", "Drain Mana on focus, mouseover or target", foc("Drain Mana") },
        },
    },
    affliction = {
        pve = {
            { "Wrack", "Wrack on your mouseover or target", mo("Wrack"), V },
            { "Siphon Life", "Siphon Life on your mouseover or target", mo("Siphon Life") },
            { "Affliction Dots", "Corruption, Bane of Agony, Siphon Life (one per press)", "#showtooltip\n/castsequence reset=target/10 {Corruption}, {Bane of Agony}, {Siphon Life}" },
            { "Dot Mouseover", "Corruption on mouseover; Shift for Bane of Agony", "#showtooltip\n/cast [mod:shift,@mouseover,harm,nodead][mod:shift] {Bane of Agony}; [@mouseover,harm,nodead][] {Corruption}" },
            { "Affliction Burst", "Trinkets and Shadow Bolt", burst("Shadow Bolt") },
            { "Safe Tap", "Life Tap without clipping a channel", "#showtooltip\n/cast [nochanneling] {Life Tap}" },
            { "Drain Mouseover", "Drain Life on your mouseover", mo("Drain Life") },
        },
        pvp = {
            { "Exhaust Focus", "Curse of Exhaustion on your focus", "#showtooltip\n/cast [@focus,harm,nodead][] {Curse of Exhaustion}" },
            { "Dot Player", "Corruption on the nearest enemy player", pvp("Corruption") },
            { "Wrack Player", "Wrack on the nearest enemy player", pvp("Wrack"), V },
            { "Siphon Focus", "Siphon Life on your focus", "#showtooltip\n/cast [@focus,harm,nodead][] {Siphon Life}" },
            { "Quick Howl", "Cancel your cast and Howl of Terror", now("Howl of Terror") },
            { "Dots on the Run", "Corruption then Bane of Agony on mouseover (one per press)", "#showtooltip\n/castsequence [@mouseover,harm,nodead][] reset=target/6 {Corruption}, {Bane of Agony}" },
        },
    },
    demonology = {
        pve = {
            { "Fel Domination", "Fel Domination and Summon Voidwalker", "#showtooltip {Fel Domination}\n/cast {Fel Domination}\n/cast {Summon Voidwalker}" },
            { "Soul Link", "Soul Link", cast("Soul Link") },
            { "Demonic Sac", "Demonic Sacrifice", cast("Demonic Sacrifice") },
            { "Quick Funnel", "Cancel your cast and Health Funnel", now("Health Funnel") },
            { "Void Shield", "Voidwalker's Sacrifice (shield)", cast("Sacrifice") },
            { "Demo Burst", "Trinkets, demon attacking and Shadow Bolt", "#showtooltip {Shadow Bolt}\n/petattack\n/use 13\n/use 14\n/cast {Shadow Bolt}" },
            { "Soul Fire", "Soul Fire", cast("Soul Fire") },
        },
        pvp = {
            { "Quick Summon", "Fel Domination and Summon Felhunter", "#showtooltip {Fel Domination}\n/cast {Fel Domination}\n/cast {Summon Felhunter}" },
            { "Lock Focus", "Spell Lock your focus only", onfocus("Spell Lock") },
            { "Seduce Focus", "Seduction on your focus only, calling the Succubus back first", "#showtooltip {Seduction}\n/petfollow\n/cast [@focus,harm,nodead] {Seduction}" },
            { "Devour Self", "Devour Magic on yourself", me("Devour Magic") },
            { "Demon Focus", "Send the demon to your focus", "/petattack [@focus,harm,nodead]" },
            { "Quick Void Shld", "Voidwalker's Sacrifice even mid-cast", now("Sacrifice") },
        },
    },
    destruction = {
        pve = {
            { "Incinerate", "Incinerate", cast("Incinerate"), V },
            { "Conflagrate", "Conflagrate on your mouseover or target", mo("Conflagrate") },
            { "Immo Conflag", "Immolate then Conflagrate (two presses)", "#showtooltip\n/castsequence reset=target/12 {Immolate}, {Conflagrate}" },
            { "Bane of Havoc", "Bane of Havoc on your focus or mouseover", foc("Bane of Havoc"), V },
            { "Shadowburn", "Shadowburn on your mouseover or target", mo("Shadowburn") },
            { "Destro Burst", "Trinkets and Soul Fire", burst("Soul Fire") },
            { "Searing Pain", "Searing Pain", cast("Searing Pain") },
        },
        pvp = {
            { "Quick Burn", "Cancel your cast and Shadowburn (to finish an enemy)", now("Shadowburn") },
            { "Quick Conflag", "Cancel your cast and Conflagrate", now("Conflagrate") },
            { "Havoc Focus", "Bane of Havoc on your focus only", onfocus("Bane of Havoc"), V },
            { "Pain Player", "Searing Pain on the nearest enemy player", pvp("Searing Pain") },
            { "Immo Player", "Immolate on the nearest enemy player", pvp("Immolate") },
            { "Destro PvP Burst", "Trinkets, Immolate then Conflagrate (two presses)", "#showtooltip\n/use 13\n/use 14\n/castsequence reset=target/12 {Immolate}, {Conflagrate}" },
        },
    },
})

---------------------------------------------------------------------------
-- Druid  (forms are called by name with "!": no form numbers needed)
---------------------------------------------------------------------------
Macros:RegisterPack("DRUID", {
    all = {
        any = {
            { "Bear", "Dire Bear Form (or Bear Form) without leaving it by accident", "#showtooltip\n/cast !{Dire Bear Form}\n/cast !{Bear Form}" },
            { "Cat", "Cat Form without leaving it by accident", "#showtooltip\n/cast !{Cat Form}" },
            { "Travel", "Aquatic Form in water, Travel Form outdoors, Cat Form otherwise", "#showtooltip\n/cast [swimming] !{Aquatic Form}; [outdoors] !{Travel Form}; !{Cat Form}" },
            { "Cancel Form", "Leave any form", "/cancelform" },
            { "Rejuvenation", "Leave form and Rejuvenation on mouseover, friendly target or yourself", "#showtooltip {Rejuvenation}\n/cancelform\n/cast [@mouseover,help,nodead][help,nodead][@player] {Rejuvenation}" },
            { "Healing Touch", "Leave form and Healing Touch on mouseover", "#showtooltip {Healing Touch}\n/cancelform\n/cast [@mouseover,help,nodead][help,nodead][@player] {Healing Touch}" },
            { "Regrowth", "Leave form and Regrowth on mouseover", "#showtooltip {Regrowth}\n/cancelform\n/cast [@mouseover,help,nodead][help,nodead][@player] {Regrowth}" },
            { "Moonfire", "Moonfire on your mouseover or target", mo("Moonfire") },
            { "Roots", "Entangling Roots on focus, mouseover or target", foc("Entangling Roots") },
            { "Faerie Fire", "Faerie Fire on your mouseover or target (also in form)", mo("Faerie Fire") },
            { "Barkskin", "Barkskin even mid-cast", now("Barkskin") },
            { "Nature's Grasp", "Nature's Grasp", cast("Nature's Grasp") },
            { "Innervate", "Innervate on mouseover; Alt on yourself", "#showtooltip\n/cast [mod:alt,@player][@mouseover,help,nodead][help,nodead][@player] {Innervate}" },
            { "Decurse", "Remove Curse; Shift for Abolish Poison, on mouseover", "#showtooltip\n/cast [mod:shift,@mouseover,help][mod:shift] {Abolish Poison}; [@mouseover,help,nodead][help,nodead][@player] {Remove Curse}" },
            { "Buffs", "Mark of the Wild on mouseover; Shift for Thorns", "#showtooltip\n/cast [mod:shift,@mouseover,help][mod:shift] {Thorns}; [@mouseover,help][] {Mark of the Wild}" },
            { "Resurrect", "Rebirth in combat, Revive out of combat, on mouseover", "#showtooltip\n/cast [combat,@mouseover,help,dead][combat] {Rebirth}; [@mouseover,help,dead][] {Revive}" },
            { "Dash", "Enter Cat Form and Dash", "#showtooltip {Dash}\n/cast [nostealth] !{Cat Form}\n/cast {Dash}" },
            { "Prowl", "Cat Form and Prowl without breaking it by accident", "#showtooltip {Prowl}\n/cast !{Cat Form}\n/cast [nostealth] {Prowl}" },
        },
        pve = {
            { "Hibernate", "Hibernate on focus, mouseover or target", foc("Hibernate") },
            { "Tranquility", "Leave form and Tranquility", "#showtooltip {Tranquility}\n/cancelform\n/cast {Tranquility}" },
            { "Hurricane", "Hurricane at your cursor", ground("Hurricane") },
            { "Innervate Focus", "Innervate your focus (set the healer as focus)", tank("Innervate") },
        },
        pvp = {
            { "Break Free", "Shift to break roots and slows: Travel Form outdoors, Cat Form otherwise", "#showtooltip\n/cancelform\n/cast [outdoors] !{Travel Form}; !{Cat Form}" },
            { "Roots Focus", "Entangling Roots on your focus only", onfocus("Entangling Roots") },
            { "Bash", "Enter bear form and Bash your focus or target", "#showtooltip {Bash}\n/cast !{Dire Bear Form}\n/cast [@focus,harm,nodead][] {Bash}" },
            { "Feral Charge", "Feral Charge on focus, mouseover or target", foc("Feral Charge") },
            { "Poison Self", "Abolish Poison on yourself", me("Abolish Poison") },
            { "Grasp Roots", "Nature's Grasp, Shift for Entangling Roots", shift("Nature's Grasp", "Entangling Roots") },
            { "Rejuv Self", "Rejuvenation on yourself without dropping your target", me("Rejuvenation") },
        },
    },
    balance = {
        pve = {
            { "Wrath", "Wrath; Shift for Starfire", shift("Wrath", "Starfire") },
            { "Starfire", "Starfire on your mouseover or target", mo("Starfire") },
            { "Insect Swarm", "Insect Swarm on your mouseover or target", mo("Insect Swarm") },
            { "Moonkin", "Moonkin Form without leaving it by accident", "#showtooltip\n/cast !{Moonkin Form}" },
            { "Balance Dots", "Moonfire then Insect Swarm (one per press)", "#showtooltip\n/castsequence reset=target/8 {Moonfire}, {Insect Swarm}" },
            { "Balance Burst", "Trinkets and Starfire", burst("Starfire") },
            { "Quick Hurricane", "Cancel your cast and Hurricane at your cursor", "#showtooltip\n/stopcasting\n/cast [@cursor] {Hurricane}" },
        },
        pvp = {
            { "Quick Moonfire", "Cancel your cast and Moonfire the mouseover or target", "#showtooltip\n/stopcasting\n/cast [@mouseover,harm,nodead][] {Moonfire}" },
            { "Swarm Player", "Insect Swarm on the nearest enemy player", pvp("Insect Swarm") },
            { "Roots Mouseover", "Entangling Roots on your mouseover", "#showtooltip\n/cast [@mouseover,harm,nodead] {Entangling Roots}" },
            { "Moonfire Rank 1", "Rank 1 Moonfire (cheap way to reveal rogues)", "#showtooltip {Moonfire}\n/cast [@mouseover,harm,nodead][] {Moonfire}(Rank 1)", R },
            { "Moonkin Heal", "Leave Moonkin Form and Regrowth yourself", "#showtooltip {Regrowth}\n/cancelform\n/cast [@player] {Regrowth}" },
            { "Faerie Fire PvP", "Faerie Fire on the nearest enemy player (against stealth)", pvp("Faerie Fire") },
        },
    },
    feral = {
        pve = {
            { "Shred", "Shred with auto attack; Ravage from stealth", "#showtooltip\n/startattack [nostealth]\n/cast [stealth] {Ravage}; {Shred}" },
            { "Claw Rake", "Claw, Shift for Rake", "#showtooltip\n/startattack\n/cast [mod:shift] {Rake}; {Claw}" },
            { "Cat Finishers", "Ferocious Bite; Shift Rip; Ctrl Primal Bite", "#showtooltip\n/cast [mod:shift] {Rip}; [mod:ctrl] {Primal Bite}; {Ferocious Bite}", V },
            { "Berserk", "Trinkets and Berserk", burst("Berserk"), V },
            { "Shifting Power", "Shifting Power", cast("Shifting Power"), V },
            { "Maul", "Maul with auto attack; Shift for Swipe", "#showtooltip\n/startattack\n/cast [mod:shift] {Swipe}; {Maul}" },
            { "Lacerate", "Lacerate with auto attack", atk("Lacerate") },
            { "Growl", "Growl your mouseover or target; Shift for Challenging Roar", "#showtooltip\n/cast [mod:shift] {Challenging Roar}; [@mouseover,harm,nodead][] {Growl}" },
            { "Bear Defensives", "Frenzied Regeneration; Shift Barkskin; Ctrl Enrage", "#showtooltip\n/cast [mod:shift] {Barkskin}; [mod:ctrl] {Enrage}; {Frenzied Regeneration}" },
            { "Feral Faerie", "Faerie Fire (Feral) on your mouseover or target", "#showtooltip\n/cast [@mouseover,harm,nodead][] {Faerie Fire (Feral)}" },
            { "Demo Roar", "Demoralizing Roar", cast("Demoralizing Roar") },
            { "Cower", "Cower (lowers threat in Cat Form)", cast("Cower") },
        },
        pvp = {
            { "Pounce", "Pounce from stealth, Rake otherwise", "#showtooltip\n/cast [stealth] {Pounce}; {Rake}" },
            { "Ravage PvP", "Ravage from stealth, Shred otherwise", "#showtooltip\n/cast [stealth] {Ravage}; {Shred}" },
            { "Charge Bash", "Feral Charge then Bash (two presses, in bear form)", "#showtooltip\n/castsequence reset=8 {Feral Charge}, {Bash}" },
            { "Charge Focus", "Feral Charge your focus only (interrupts)", onfocus("Feral Charge") },
            { "Quick Bear", "Bear form and Frenzied Regeneration", "#showtooltip {Frenzied Regeneration}\n/cast !{Dire Bear Form}\n/cast {Frenzied Regeneration}" },
            { "Berserk PvP", "Trinkets, Berserk and target an enemy player", "#showtooltip {Berserk}\n/targetenemyplayer [noharm][dead]\n/use 13\n/use 14\n/cast {Berserk}", V },
            { "Heal then Cat", "Leave form, Rejuvenation on yourself, then Cat Form (two presses)", "#showtooltip\n/cancelform\n/castsequence [@player] reset=6 {Rejuvenation}, {Cat Form}" },
        },
    },
    restoration = {
        pve = {
            { "Swiftmend", "Swiftmend on mouseover, friendly target or yourself", heal("Swiftmend") },
            { "Wild Growth", "Wild Growth on mouseover, friendly target or yourself", heal("Wild Growth"), V },
            { "Heal Tank", "Healing Touch on your focus (set the tank as focus)", tank("Healing Touch") },
            { "Hot Tank", "Rejuvenation then Regrowth on your focus (one per press)", "#showtooltip\n/castsequence [@focus,help,nodead][] reset=6 {Rejuvenation}, {Regrowth}" },
            { "Rejuv Mouseover", "Rejuvenation on mouseover, friendly target or yourself (keeps your form)", heal("Rejuvenation") },
            { "Heal ToT", "Regrowth on your enemy target's target", tot("Regrowth") },
            { "Rebirth", "Rebirth on your mouseover", "#showtooltip\n/cast [@mouseover,help,dead][] {Rebirth}" },
        },
        pvp = {
            { "Swiftmend Self", "Swiftmend on yourself", me("Swiftmend") },
            { "Quick Swiftmend", "Cancel your cast and Swiftmend the mouseover", "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead][@player] {Swiftmend}" },
            { "Regrowth Self", "Regrowth on yourself", me("Regrowth") },
            { "Growth Self", "Wild Growth on yourself", me("Wild Growth"), V },
            { "Bark Heal", "Barkskin and Regrowth on yourself", "#showtooltip {Regrowth}\n/cast {Barkskin}\n/cast [@player] {Regrowth}" },
            { "Decurse Self", "Remove Curse on yourself", me("Remove Curse") },
        },
    },
})
