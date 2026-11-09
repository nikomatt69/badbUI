-- BadbUI - Data/Auras
-- Database curato delle aure importanti per WoW: Forever (classi e incantesimi "vanilla").
-- Solo dati: la logica sta in Modules/Auras.lua.
--
-- Formato: ogni categoria e' una lista di "famiglie". Una famiglia raccoglie tutti i rank
-- di uno stesso incantesimo: { 118, 12824, 12825, 12826, n = "Polymorph" }.
--   * Gli ID sono quelli di Classic Era: Forever potrebbe usarne di nuovi (FOREVER_FACTS, conf. C).
--   * Per questo il motore risolve anche il NOME LOCALIZZATO del PRIMO ID di ogni famiglia e
--     riconosce l'aura per nome: un rank nuovo con lo stesso nome viene comunque classificato.
--   * `n` e' solo un promemoria leggibile (inglese) e non viene mai mostrato ne' confrontato.
--   * `noName = true` esclude la famiglia dal riconoscimento per nome (nomi troppo generici).
-- Nessun dato proviene da Skill Capped o da altri addon: e' una selezione nostra.
local _, ns = ...
local Badb = ns.Badb

local D = {}
Badb.AuraData = D

-- Ordine = priorita' di default (piu' alta = mostrata prima). `harmful` indica dove cercarla.
D.CATEGORIES = {
    { key = "immunity", title = "Immunita'", priority = 100, harmful = false, color = { 1.00, 0.85, 0.10 },
      desc = "Bolle e immunita': inutile attaccare, cambia bersaglio." },
    { key = "cc", title = "Controllo (stun, fear, poly, sleep)", priority = 90, harmful = true, color = { 0.95, 0.20, 0.20 },
      desc = "Perdita totale di controllo." },
    { key = "silence", title = "Silence e disarm", priority = 80, harmful = true, color = { 0.70, 0.35, 0.95 },
      desc = "Non puo' lanciare o attaccare in mischia." },
    { key = "defensive", title = "Difensivi", priority = 70, harmful = false, color = { 0.25, 0.75, 1.00 },
      desc = "Riduzioni del danno e fughe." },
    { key = "offensive", title = "Offensivi", priority = 60, harmful = false, color = { 1.00, 0.45, 0.10 },
      desc = "Cooldown di danno o cura attivi: pericolo." },
    { key = "root", title = "Root", priority = 50, harmful = true, color = { 0.30, 0.85, 0.35 },
      desc = "Immobilizzato ma puo' lanciare." },
    { key = "utility", title = "Utilita'", priority = 40, harmful = false, color = { 0.85, 0.85, 0.85 },
      desc = "Libero movimento, mana, protezioni dalla paura." },
    { key = "snare", title = "Rallentamenti", priority = 30, harmful = true, color = { 0.55, 0.75, 0.55 },
      desc = "Movimento ridotto." },
    { key = "drink", title = "Sta bevendo", priority = 20, harmful = false, color = { 0.40, 0.70, 1.00 },
      desc = "Healer o caster che recupera mana: momento per attaccarlo." },
}

D.SPELLS = {
    immunity = {
        { 642, 1020, n = "Divine Shield" },
        { 498, 5573, n = "Divine Protection" },
        { 1022, 5599, 10278, n = "Blessing of Protection" },
        { 11958, n = "Ice Block" },
        { 710, 18647, n = "Banish" },
        { 8178, n = "Grounding Totem Effect" },
    },
    cc = {
        -- stun
        { 853, 5588, 5589, 10308, n = "Hammer of Justice" },
        { 408, 8643, n = "Kidney Shot" },
        { 1833, n = "Cheap Shot" },
        { 5211, 6798, 8983, n = "Bash" },
        { 9005, 9823, 9827, n = "Pounce" },
        { 7922, n = "Charge Stun" },
        { 20253, 20614, 20615, n = "Intercept Stun" },
        { 12809, n = "Concussion Blow" },
        { 12798, n = "Revenge Stun" },
        { 5530, n = "Mace Stun Effect" },
        { 20549, n = "War Stomp" },
        { 12355, n = "Impact" },
        { 20170, n = "Seal of Justice stun" },
        { 15269, n = "Blackout" },
        { 18093, n = "Pyroclasm" },
        { 16922, n = "Starfire Stun" },
        { 24394, n = "Intimidation" },
        -- incapacitate / sleep / polymorph
        { 1776, 1777, 8629, 11285, 11286, n = "Gouge" },
        { 6770, 2070, 11297, n = "Sap" },
        { 118, 12824, 12825, 12826, 28270, 28271, 28272, n = "Polymorph" },
        { 20066, n = "Repentance" },
        { 3355, 14308, 14309, n = "Freezing Trap Effect" },
        { 19503, n = "Scatter Shot" },
        { 19386, 24132, 24133, n = "Wyvern Sting" },
        { 2637, 18657, 18658, n = "Hibernate" },
        { 6358, n = "Seduction" },
        { 9484, 9485, 10955, n = "Shackle Undead" },
        { 605, 10911, 10912, n = "Mind Control" },
        -- fear / horror
        { 5782, 6213, 6215, n = "Fear" },
        { 5484, 17928, n = "Howl of Terror" },
        { 6789, 17925, 17926, n = "Death Coil" },
        { 8122, 8124, 10888, 10890, n = "Psychic Scream" },
        { 5246, 20511, n = "Intimidating Shout" },
        { 1513, 14326, 14327, n = "Scare Beast" },
        { 2878, 5627, 10326, n = "Turn Undead" },
    },
    silence = {
        { 15487, n = "Silence" },
        { 18469, n = "Counterspell - Silenced" },
        { 18425, n = "Kick - Silenced" },
        { 24259, n = "Spell Lock" },
        { 18498, n = "Shield Bash - Silenced" },
        { 676, n = "Disarm" },
        { 14251, n = "Riposte" },
    },
    defensive = {
        { 5277, n = "Evasion" },
        { 871, n = "Shield Wall" },
        { 12975, 12976, n = "Last Stand" },
        { 20230, n = "Retaliation" },
        { 22812, n = "Barkskin" },
        { 22842, 22895, 22896, n = "Frenzied Regeneration" },
        { 11426, 13031, 13032, 13033, n = "Ice Barrier" },
        { 5384, n = "Feign Death" },
        { 20594, n = "Stoneform" },
        { 7744, n = "Will of the Forsaken" },
        { 18499, n = "Berserker Rage" },
        { 11327, 11329, n = "Vanish" },
    },
    offensive = {
        { 1719, n = "Recklessness" },
        { 12292, n = "Death Wish" },
        { 12328, n = "Sweeping Strikes" },
        { 12042, n = "Arcane Power" },
        { 11129, n = "Combustion" },
        { 12043, n = "Presence of Mind" },
        { 13750, n = "Adrenaline Rush" },
        { 13877, n = "Blade Flurry" },
        { 14177, n = "Cold Blood" },
        { 10060, n = "Power Infusion" },
        { 14751, n = "Inner Focus" },
        { 16166, n = "Elemental Mastery" },
        { 16188, n = "Nature's Swiftness (Shaman)" },
        { 17116, n = "Nature's Swiftness (Druid)" },
        { 3045, n = "Rapid Fire" },
        { 19574, n = "Bestial Wrath" },
        { 20216, n = "Divine Favor" },
        { 18288, n = "Amplify Curse" },
        { 20572, n = "Blood Fury" },
        { 26297, 26296, 20554, n = "Berserking" },
    },
    root = {
        { 122, 865, 6131, 10230, n = "Frost Nova" },
        { 12494, n = "Frostbite" },
        { 339, 1062, 5195, 5196, 9852, 9853, n = "Entangling Roots" },
        { 23694, n = "Improved Hamstring" },
        { 19229, n = "Improved Wing Clip" },
        { 19306, 20909, 20910, n = "Counterattack" },
        { 19185, n = "Entrapment" },
        { 19675, n = "Feral Charge Effect" },
    },
    utility = {
        { 1044, n = "Blessing of Freedom" },
        { 6346, n = "Fear Ward" },
        { 29166, n = "Innervate" },
        { 6940, 20729, n = "Blessing of Sacrifice" },
    },
    snare = {
        { 1715, 7372, 7373, n = "Hamstring" },
        { 2974, 14267, 14268, n = "Wing Clip" },
        { 5116, n = "Concussive Shot" },
        { 3409, 11201, n = "Crippling Poison" },
        { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304, n = "Frostbolt" },
        { 120, 8492, 10159, 10160, 10161, n = "Cone of Cold" },
        { 8056, 8058, 10472, 10473, n = "Frost Shock" },
        { 15407, 17311, 17312, 17313, 17314, 18807, n = "Mind Flay" },
        { 18223, n = "Curse of Exhaustion" },
        { 12323, n = "Piercing Howl" },
        { 3600, n = "Earthbind" },
        { 11113, 13018, 13019, 13020, 13021, n = "Blast Wave" },
        { 6136, 7321, n = "Chilled" },
    },
    drink = {
        { 430, 431, 432, 1133, 1135, 1137, 22734, 24355, n = "Drink" },
    },
}

-- Debuff "propri" curati per classe: quelli che conviene tenere d'occhio sulla nameplate
-- del nemico (DoT, rallentamenti, maledizioni, marchi). I CC propri passano comunque dallo slot CC.
D.CLASS_DEBUFFS = {
    WARRIOR = {
        { 772, 6546, 6547, 6548, 11572, 11573, 11574, n = "Rend" },
        { 1715, 7372, 7373, n = "Hamstring" },
        { 12294, 21551, 21552, 21553, n = "Mortal Strike" },
        { 7386, 7405, 8380, 11596, 11597, n = "Sunder Armor" },
        { 6343, 8198, 8204, 8205, 11580, 11581, n = "Thunder Clap" },
        { 1160, 6190, 11554, 11555, 11556, n = "Demoralizing Shout" },
        { 12162, 12850, 12868, n = "Deep Wounds" },
        { 12323, n = "Piercing Howl" },
    },
    PALADIN = {
        { 20184, n = "Judgement of Justice" },
        { 20185, 20344, 20345, 20346, n = "Judgement of Light" },
        { 20186, 20354, 20355, n = "Judgement of Wisdom" },
        { 21183, 20188, 20300, 20301, 20302, 20303, n = "Judgement of the Crusader" },
    },
    HUNTER = {
        { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, n = "Serpent Sting" },
        { 3034, 14279, 14280, n = "Viper Sting" },
        { 3043, 14275, 14276, 14277, n = "Scorpid Sting" },
        { 1130, 14323, 14324, 14325, n = "Hunter's Mark" },
        { 2974, 14267, 14268, n = "Wing Clip" },
        { 5116, n = "Concussive Shot" },
        { 13812, 14314, 14315, n = "Explosive Trap Effect" },
        { 13797, 14298, 14299, 14300, 14301, n = "Immolation Trap Effect" },
    },
    ROGUE = {
        { 1943, 8639, 8640, 11273, 11274, 11275, n = "Rupture" },
        { 703, 8631, 8632, 8633, 11289, 11290, n = "Garrote" },
        { 8647, 8649, 8650, 11197, 11198, n = "Expose Armor" },
        { 2818, 2819, 11353, 11354, 25349, n = "Deadly Poison" },
        { 13218, 13222, 13223, 13224, n = "Wound Poison" },
        { 3409, 11201, n = "Crippling Poison" },
        { 5760, 8692, 11398, n = "Mind-numbing Poison" },
        { 16511, 17347, 17348, n = "Hemorrhage" },
    },
    PRIEST = {
        { 589, 594, 970, 992, 2767, 10892, 10893, 10894, n = "Shadow Word: Pain" },
        { 2944, 19276, 19277, 19278, 19279, 19280, n = "Devouring Plague" },
        { 15407, 17311, 17312, 17313, 17314, 18807, n = "Mind Flay" },
        { 15286, n = "Vampiric Embrace" },
        { 15258, n = "Shadow Vulnerability" },
        { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261, n = "Holy Fire" },
    },
    SHAMAN = {
        { 8050, 8052, 8053, 10447, 10448, 29228, n = "Flame Shock" },
        { 8056, 8058, 10472, 10473, n = "Frost Shock" },
        { 3600, n = "Earthbind" },
        { 17364, n = "Stormstrike" },
    },
    MAGE = {
        { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304, n = "Frostbolt" },
        { 120, 8492, 10159, 10160, 10161, n = "Cone of Cold" },
        { 12654, n = "Ignite" },
        { 22959, n = "Fire Vulnerability" },
        { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809, n = "Pyroblast" },
        { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306, n = "Fireball" },
        { 11113, 13018, 13019, 13020, 13021, n = "Blast Wave" },
        { 12579, n = "Winter's Chill" },
    },
    WARLOCK = {
        { 172, 6222, 6223, 7648, 11671, 11672, 25311, n = "Corruption" },
        { 980, 1014, 6217, 11711, 11712, 11713, n = "Curse of Agony" },
        { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309, n = "Immolate" },
        { 18265, 18879, 18880, 18881, n = "Siphon Life" },
        { 18223, n = "Curse of Exhaustion" },
        { 1714, 11719, n = "Curse of Tongues" },
        { 702, 1108, 6205, 7646, 11707, 11708, n = "Curse of Weakness" },
        { 1490, 11721, 11722, n = "Curse of the Elements" },
        { 17862, 17937, n = "Curse of Shadow" },
        { 603, n = "Curse of Doom" },
        { 17877, 18867, 18868, 18869, 18870, 18871, n = "Shadowburn" },
    },
    DRUID = {
        { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835, n = "Moonfire" },
        { 5570, 24974, 24975, 24976, 24977, n = "Insect Swarm" },
        { 1822, 1823, 1824, 9904, n = "Rake" },
        { 1079, 9492, 9493, 9752, 9894, 9896, n = "Rip" },
        { 770, 778, 9749, 9907, n = "Faerie Fire" },
        { 16857, 17390, 17391, 17392, n = "Faerie Fire (Feral)" },
        { 9007, 9824, 9826, n = "Pounce Bleed" },
        { 99, 1735, 9490, 9747, 9898, n = "Demoralizing Roar" },
    },
}

return D
