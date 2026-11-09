-- Test del modulo ActionBars
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

local T = {}

T["abilitato di default e stila i pulsanti"] = function()
    local AB = BadbUI.Modules:Get("ActionBars")
    assert(AB.enabled, "modulo non attivo")
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 0, "texture Blizzard nascosta")
    eq(ActionButton1.icon.__maskRemoved, ActionButton1.IconMask, "maschera icona rimossa")
    eq(ActionButton1.icon.__texcoord[1], 0.08, "zoom icona")
end

T["keybind abbreviati"] = function(Mock)
    local Lib = BadbUI.ActionBarsLib
    eq(Lib.ShortKey("SHIFT-BUTTON4"), "SM4")
    eq(Lib.ShortKey("CTRL-NUMPAD5"), "CN5")
    eq(Lib.ShortKey("ALT-MOUSEWHEELUP"), "AWU")
    eq(Lib.ShortKey("NUMPADPLUS"), "N+")
    eq(Lib.ShortKey("MIDDLEMOUSE"), "M3")
    eq(Lib.ShortKey(nil), nil)

    Mock.bindings.ACTIONBUTTON1 = "SHIFT-BUTTON4"
    Mock.Fire("UPDATE_BINDINGS")
    eq(ActionButton1.HotKey:GetText(), "SM4", "testo hotkey")
    -- Blizzard riscrive il testo: l'hook lo riabbrevia.
    ActionButton1.HotKey:SetText("s-M4")
    ActionButton1:UpdateHotkeys()
    eq(ActionButton1.HotKey:GetText(), "SM4", "dopo UpdateHotkeys")
end

T["keybind nascosti e nomi macro"] = function()
    local AB = BadbUI.Modules:Get("ActionBars")
    eq(ActionButton1.Name:GetAlpha(), 0, "nomi macro nascosti di default")
    AB:Set("showMacroNames", true)
    eq(ActionButton1.Name:GetAlpha(), 1, "nomi macro visibili")
    AB:Set("showKeybinds", false)
    eq(ActionButton1.HotKey:GetAlpha(), 0, "keybind nascosti")
    AB:Set("keybindSize", 15)
    eq(select(2, ActionButton1.HotKey:GetFont()), 15, "dimensione keybind")
end

T["colore per stato"] = function(Mock)
    local Lib = BadbUI.ActionBarsLib
    Mock.usable[2] = { false, true } -- manca la risorsa
    ActionButton2:UpdateUsable()
    eq(ActionButton2.icon.__vc[1], select(1, Lib.Color("mana")), "blu per risorsa")

    Mock.usable[3] = { true, false }
    ActionButton_UpdateRangeIndicator(ActionButton3, true, false)
    eq(ActionButton3.icon.__vc[1], select(1, Lib.Color("danger")), "rosso fuori portata")
    ActionButton_UpdateRangeIndicator(ActionButton3, true, true)
    eq(ActionButton3.icon.__vc[1], 1, "bianco in portata")
end

T["secret value non causano errori"] = function(Mock)
    Mock.usable[4] = { Mock.Secret(), Mock.Secret() }
    ActionButton4.icon.__vc = nil
    ActionButton4:UpdateUsable()
    eq(ActionButton4.icon.__vc, nil, "nessuna modifica con valori opachi")
    ActionButton_UpdateRangeIndicator(ActionButton4, Mock.Secret(), Mock.Secret())
end

T["dissolvenza al mouseover"] = function()
    local AB = BadbUI.Modules:Get("ActionBars")
    AB:Set("fade.main", true)
    AB:Set("fadeDuration", 0)
    local fader
    -- Il fader e' l'unico frame con OnUpdate creato dal modulo: lo eseguiamo a mano.
    for _, bar in ipairs(BadbUI.ActionBarsLib.BARS) do assert(bar.key) end
    fader = AB._fader
    assert(fader, "fader esposto per i test")
    fader.__scripts.OnUpdate(fader, 0.1)
    eq(MainActionBar:GetAlpha(), 0, "barra nascosta")
    MainActionBar.__mouseover = true
    fader.__scripts.OnUpdate(fader, 0.1)
    eq(MainActionBar:GetAlpha(), 1, "barra visibile al mouseover")
    eq(MultiBarBottomLeft:GetAlpha(), 1, "barre senza dissolvenza intatte")
end

T["disattivazione ripristina Blizzard"] = function()
    local AB = BadbUI.Modules:Get("ActionBars")
    AB:Set("fade.main", true)
    MainActionBar:SetAlpha(0.2)
    BadbUI.Modules:SetEnabled("ActionBars", false)
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 1, "texture ripristinata")
    eq(ActionButton1.icon.__maskRemoved, nil, "maschera ripristinata")
    eq(ActionButton1.icon.__texcoord[2], 1, "texcoord ripristinate")
    eq(MainActionBar:GetAlpha(), 1, "alpha barra ripristinata")
    BadbUI.Modules:SetEnabled("ActionBars", true)
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 0, "riattivazione")
end

T["segue il tema del design system"] = function(Mock)
    BadbUI.Theme = { colors = { danger = { 0.9, 0.1, 0.2, 1 } }, fonts = { number = "Fonts\\TEST.TTF" } }
    Mock.Fire("BADB_THEME_CHANGED")
    eq(select(1, BadbUI.ActionBarsLib.Color("danger")), 0.9, "colore dal tema")
    eq(ActionButton1.HotKey:GetFont(), "Fonts\\TEST.TTF", "font dal tema")
    eq(select(1, BadbUI.ActionBarsLib.Color("mana")), 0.35, "fallback per chiavi mancanti")
end

T["edge: barre e pulsanti mancanti (client senza MultiBar5-7)"] = function(Mock)
    -- Nessun MultiBar5Button/StanceButton nel mock: ApplyAll non deve fallire.
    MainActionBar = nil
    local AB = BadbUI.Modules:Get("ActionBars")
    AB:Set("fade.main", true)
    AB._fader.__scripts.OnUpdate(AB._fader, 0.1)
    AB:ApplyAll()
end

T["edge: login/reload ripetuti sono idempotenti"] = function(Mock)
    Mock.Fire("PLAYER_ENTERING_WORLD")
    Mock.Fire("PLAYER_ENTERING_WORLD")
    -- Il bordo e lo sfondo sono creati una volta sola e riutilizzati.
    local AB = BadbUI.Modules:Get("ActionBars")
    local count = 0
    local orig = BadbUI.ActionBarsLib.CreateBorder
    BadbUI.ActionBarsLib.CreateBorder = function(...) count = count + 1; return orig(...) end
    AB:ApplyAll(); AB:ApplyAll()
    BadbUI.ActionBarsLib.CreateBorder = orig
    eq(count, 0, "nessun bordo duplicato")
end

T["edge: pulsanti creati dopo il login (famiglio)"] = function(Mock)
    Mock.CreateActionButtons("PetActionButton", 10)
    Mock.Fire("UNIT_PET", "player")
    eq(PetActionButton1:GetNormalTexture():GetAlpha(), 0, "famiglio stilato")
end

T["edge: in combattimento le barre in dissolvenza restano visibili"] = function(Mock)
    local AB = BadbUI.Modules:Get("ActionBars")
    AB:Set("fade.main", true); AB:Set("fadeDuration", 0)
    Mock.combat = true
    AB._fader.__scripts.OnUpdate(AB._fader, 0.1)
    eq(MainActionBar:GetAlpha(), 1, "visibile in combattimento")
    AB:Set("fadeShowInCombat", false)
    AB._fader.__scripts.OnUpdate(AB._fader, 0.1)
    eq(MainActionBar:GetAlpha(), 0, "nascosta se l'opzione e' spenta")
    -- Le modifiche in combattimento sono solo alpha/texture: nessuna coda necessaria.
    AB:Set("skin", false)
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 1, "stile aggiornato anche in combattimento")
end

T["edge: cambio profilo applica le opzioni del nuovo profilo"] = function()
    local DB = BadbUI.DB
    DB:CopyProfile("Default", "PvP")
    DB.sv.profiles.PvP.modules.ActionBars.skin = false
    DB:SetProfile("PvP")
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 1, "profilo senza stile")
    DB:SetProfile("Default")
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 0, "ritorno al profilo con stile")
end

T["edge: profilo con modulo disattivato"] = function()
    local DB = BadbUI.DB
    DB:CopyProfile("Default", "Vanilla")
    DB.sv.profiles.Vanilla.modules.ActionBars.enabled = false
    DB:SetProfile("Vanilla")
    assert(not BadbUI.Modules:Get("ActionBars").enabled, "modulo spento")
    eq(ActionButton1:GetNormalTexture():GetAlpha(), 1, "Blizzard ripristinato")
end

T["edge: tema incompleto o malformato"] = function()
    local Lib = BadbUI.ActionBarsLib
    BadbUI.Theme = { colors = { danger = "rosso", accent = { r = 0.1, g = 0.2, b = 0.3 } }, fonts = { number = { path = "Fonts\\A.TTF" } } }
    eq(select(1, Lib.Color("danger")), 1, "stringa ignorata, fallback")
    eq(select(3, Lib.Color("accent")), 0.3, "formato {r,g,b}")
    eq(select(4, Lib.Color("accent")), 1, "alpha di default")
    eq(Lib.Font("number"), "Fonts\\A.TTF", "font come tabella {path}")
    eq(select(1, Lib.Color("inesistente")), Lib.FALLBACK_THEME.colors.text[1], "chiave sconosciuta")
end

T["edge: pulsante senza binding mantiene il testo Blizzard"] = function()
    ActionButton5.HotKey:SetText("\226\151\143") -- RANGE_INDICATOR
    ActionButton5:UpdateHotkeys()
    eq(ActionButton5.HotKey:GetText(), "\226\151\143", "indicatore di portata intatto")
end

T["edge: slot vuoto non viene colorato"] = function(Mock)
    local hasAction = HasAction
    HasAction = function() return false end
    ActionButton6.icon.__vc = nil
    ActionButton6:UpdateUsable()
    HasAction = hasAction
    eq(ActionButton6.icon.__vc, nil, "nessun colore su slot vuoto")
end

return T
