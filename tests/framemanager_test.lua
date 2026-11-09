-- Test del FrameManager (regressioni segnalate durante l'integrazione di LayoutStudio)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

local T = {}

local function newFrame(name)
    local f = CreateFrame("Frame", name)
    BadbUI.FrameManager:Register(name, { frame = name, title = name, category = "Test" })
    return f
end

T["Restore rimostra un frame nascosto (l'hook non lo richiude)"] = function()
    local FM = BadbUI.FrameManager
    local f = newFrame("BadbTestFrame")
    FM:SetOption("BadbTestFrame", "hidden", true)
    eq(f:IsShown(), false, "nascosto")
    FM:Restore("BadbTestFrame")
    eq(f:IsShown(), true, "dopo Restore")
    eq(next(BadbUI.DB.profile.frames.BadbTestFrame), nil, "configurazione azzerata")
end

T["Restore azzera la configurazione anche se il frame non esiste ancora"] = function()
    local FM = BadbUI.FrameManager
    FM:Register("BadbMissing", { frame = "BadbMissingGlobal", title = "x" })
    BadbUI.DB.profile.frames.BadbMissing = { hidden = true, alpha = 0.2 }
    FM:Restore("BadbMissing")
    eq(next(BadbUI.DB.profile.frames.BadbMissing), nil)
end

T["il cambio profilo non cancella la configurazione del nuovo profilo"] = function()
    local FM, DB = BadbUI.FrameManager, BadbUI.DB
    local f = newFrame("BadbTestFrame2")
    FM:SetOption("BadbTestFrame2", "alpha", 0.5)
    DB.sv.profiles.B = { frames = { BadbTestFrame2 = { alpha = 0.3 } }, modules = {} }
    DB:SetProfile("B")
    eq(DB.profile.frames.BadbTestFrame2.alpha, 0.3, "configurazione del profilo B intatta")
    eq(f:GetAlpha(), 0.3, "alpha applicato dal profilo B")
    DB:SetProfile("Default")
    eq(DB.profile.frames.BadbTestFrame2.alpha, 0.5, "configurazione del profilo Default intatta")
    eq(f:GetAlpha(), 0.5)
end

T["cambio profilo: il frame torna all'originale se il nuovo profilo non lo gestisce"] = function()
    local FM, DB = BadbUI.FrameManager, BadbUI.DB
    local f = newFrame("BadbTestFrame3")
    FM:SetOption("BadbTestFrame3", "alpha", 0.4)
    eq(f:GetAlpha(), 0.4)
    DB.sv.profiles.Vuoto = { frames = {}, modules = {} }
    DB:SetProfile("Vuoto")
    eq(f:GetAlpha(), 1, "alpha originale ripristinato")
end

T["cambio profilo in combattimento: ripristino e applicazione differiti nell'ordine giusto"] = function(Mock)
    local FM, DB = BadbUI.FrameManager, BadbUI.DB
    local f = newFrame("BadbTestFrame4")
    FM:SetOption("BadbTestFrame4", "alpha", 0.4)
    DB.sv.profiles.C = { frames = { BadbTestFrame4 = { alpha = 0.7 } }, modules = {} }
    Mock.combat = true
    DB:SetProfile("C")
    eq(f:GetAlpha(), 0.4, "nulla cambia in combattimento")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(f:GetAlpha(), 0.7, "applicato a fine combattimento")
end

T["Restore emette BADB_FRAME_CHANGED"] = function()
    local FM = BadbUI.FrameManager
    newFrame("BadbTestFrame5")
    local got
    BadbUI.Events:On({ name = "t" }, "BADB_FRAME_CHANGED", function(_, key, field) got = { key, field } end)
    FM:SetOption("BadbTestFrame5", "alpha", 0.5)
    got = nil
    FM:Restore("BadbTestFrame5")
    assert(got, "evento non emesso")
    eq(got[1], "BadbTestFrame5"); eq(got[2], "restore")
end

T["il drag di un mover emette BADB_FRAME_CHANGED (position)"] = function()
    local FM = BadbUI.FrameManager
    newFrame("BadbTestFrame6")
    local oldCenter = UIParent.GetCenter
    UIParent.GetCenter = function() return 480, 270 end
    local ok, err = pcall(function()
        FM:SetUnlocked(true)
        local m = FM.movers.BadbTestFrame6
        assert(m, "mover non creato")
        m.GetCenter = function() return 500, 400 end
        local got
        BadbUI.Events:On({ name = "t2" }, "BADB_FRAME_CHANGED", function(_, key, field) got = { key, field } end)
        m.__scripts.OnDragStop(m)
        assert(got, "evento non emesso")
        eq(got[1], "BadbTestFrame6"); eq(got[2], "position")
        eq(BadbUI.DB.profile.frames.BadbTestFrame6.x, 24, "snap alla griglia da 8: 20 -> 24")
        eq(BadbUI.DB.profile.frames.BadbTestFrame6.y, 128)
    end)
    UIParent.GetCenter = oldCenter
    if not ok then error(err, 0) end
end

-- Mover: frecce, Maiusc e rotella (come i mover di ElvUI)
local function withMover(name, fn)
    local FM = BadbUI.FrameManager
    local f = newFrame(name)
    local oldCenter = UIParent.GetCenter
    UIParent.GetCenter = function() return 480, 270 end
    f.GetCenter = function() return 500, 400 end
    local shift = false
    IsShiftKeyDown = function() return shift end
    local ok, err = pcall(function()
        FM:SetUnlocked(true)
        local m = FM.movers[name]
        assert(m, "mover non creato")
        m.SetPropagateKeyboardInput = function(self, v) self.__propagate = v end
        fn(FM, m, f, function(v) shift = v end)
    end)
    UIParent.GetCenter = oldCenter
    if not ok then error(err, 0) end
end

T["mover: le frecce spostano di 1 px, con Maiusc di 10, e consumano il tasto"] = function()
    withMover("BadbTestFrame7", function(FM, m, f, setShift)
        local conf = function() return BadbUI.DB.profile.frames.BadbTestFrame7 end
        m.__scripts.OnKeyDown(m, "RIGHT")
        eq(conf().x, 21); eq(conf().y, 130, "20 + 1, 130")
        eq(m.__propagate, false, "tasto freccia gestito: non va al gioco")
        f.GetCenter = function() return 501, 400 end
        setShift(true)
        m.__scripts.OnKeyDown(m, "UP")
        eq(conf().y, 140, "con Maiusc: +10")
        m.__scripts.OnKeyDown(m, "W")
        eq(m.__propagate, true, "altri tasti restano al gioco")
    end)
end

T["mover: in combattimento le frecce non spostano"] = function(Mock)
    withMover("BadbTestFrame8", function(FM, m)
        Mock.combat = true
        m.__scripts.OnKeyDown(m, "LEFT")
        eq(BadbUI.DB.profile.frames.BadbTestFrame8 and BadbUI.DB.profile.frames.BadbTestFrame8.x, nil)
        eq(m.__propagate, true)
    end)
end

T["mover: Maiusc + rotella cambia la scala entro i limiti"] = function()
    withMover("BadbTestFrame9", function(FM, m, f, setShift)
        local conf = function() return BadbUI.DB.profile.frames.BadbTestFrame9 end
        m.__scripts.OnMouseWheel(m, 1)
        eq(conf() and conf().scale, nil, "senza Maiusc la rotella non scala")
        setShift(true)
        m.__scripts.OnMouseWheel(m, 1)
        eq(conf().scale, 1.05)
        for _ = 1, 40 do m.__scripts.OnMouseWheel(m, 1) end
        eq(conf().scale, 2, "massimo 2")
        for _ = 1, 80 do m.__scripts.OnMouseWheel(m, -1) end
        eq(conf().scale, 0.5, "minimo 0.5")
    end)
end

T["mover: posizione illeggibile non lancia errori"] = function()
    withMover("BadbTestFrame10", function(FM, m, f)
        f.GetCenter = function() return nil end
        m.__scripts.OnKeyDown(m, "LEFT")
        eq(m.__propagate, true)
    end)
end

return T
