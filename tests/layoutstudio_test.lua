-- Test del modulo LayoutStudio
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso vero", 2) end end

local UX, UY = 960, 540

-- Frame finto con geometria: i punti vivono in f.pts, GetCenter li legge (solo CENTER).
local function newFrame(Mock, key, x, y, w, h, opts)
    opts = opts or {}
    local f = Mock.NewObject("Frame")
    f.pts = opts.noGeometry and {} or { { "CENTER", UIParent, "CENTER", x, y } }
    f.setCalls = 0
    f.GetNumPoints = function(s) return #s.pts end
    f.GetPoint = function(s, i) local p = s.pts[i]; if p then return unpack(p) end end
    f.ClearAllPoints = function(s) s.pts = {} end
    f.SetPoint = function(s, ...) s.setCalls = s.setCalls + 1; s.pts[#s.pts + 1] = { ... } end
    f.GetCenter = function(s)
        local p = s.pts[1]
        if p and p[1] == "CENTER" then return UX + p[4], UY + p[5] end
    end
    f.GetWidth = function() return w end
    f.GetHeight = function() return h end
    f.IsProtected = function() return opts.protected or false end
    if opts.editMode then f.system = 1 end
    BadbUI.FrameManager:Register(key, { frame = f, title = opts.title or key, category = opts.category or "Test" })
    return f
end

local function center(f)
    local cx, cy = f:GetCenter()
    return cx - UX, cy - UY
end

-- Ogni test: UIParent con centro noto, hook tastiera di prova, pulizia globali.
local function test(fn)
    return function(Mock)
        UIParent.GetCenter = function() return UX, UY end
        IsShiftKeyDown = function() return Mock.shift or false end
        IsControlKeyDown = function() return Mock.ctrl or false end
        local ok, err = pcall(fn, Mock)
        IsShiftKeyDown, IsControlKeyDown = nil, nil
        if not ok then error(err, 0) end
    end
end

local function LS() return BadbUI.LayoutStudio end
local function FM() return BadbUI.FrameManager end
local function tick(Mock) Mock.time = Mock.time + 10 end

local T = {}

-- Calcoli puri ---------------------------------------------------------------

T["calc: allineamento su tutti i modi"] = test(function()
    local C = LS().Calc
    local rects = {
        { key = "A", x = -200, y = 0, w = 100, h = 50 },
        { key = "B", x = 0, y = 100, w = 60, h = 20 },
        { key = "C", x = 150, y = -100, w = 40, h = 40 },
    }
    local p = C.Align(rects, "left")
    eq(p.A.x, -200); eq(p.B.x, -220); eq(p.C.x, -230); eq(p.B.y, 100, "y invariata")
    p = C.Align(rects, "right") -- bordo destro massimo = 170
    eq(p.A.x, 120); eq(p.B.x, 140); eq(p.C.x, 150)
    p = C.Align(rects, "top") -- bordo alto massimo = 110
    eq(p.A.y, 85); eq(p.B.y, 100); eq(p.C.y, 90)
    p = C.Align(rects, "bottom") -- bordo basso minimo = -120
    eq(p.A.y, -95); eq(p.B.y, -110); eq(p.C.y, -100)
    p = C.Align(rects, "hcenter") -- (-250 + 170) / 2 = -40
    eq(p.A.x, -40); eq(p.B.x, -40); eq(p.C.x, -40)
    p = C.Align(rects, "vcenter") -- (-120 + 110) / 2 = -5
    eq(p.A.y, -5); eq(p.B.y, -5); eq(p.C.y, -5)
end)

T["calc: distribuzione orizzontale e verticale"] = test(function()
    local C = LS().Calc
    -- Ordine volutamente mescolato: si ordina per centro.
    local rects = {
        { key = "C", x = 250, y = 0, w = 50, h = 10 },
        { key = "A", x = -300, y = 5, w = 100, h = 10 },
        { key = "B", x = -100, y = 9, w = 100, h = 10 },
    }
    local p = C.Distribute(rects, "h")
    eq(p.A.x, -300); eq(p.C.x, 250); eq(p.B.x, -12, "spazio uguale (187.5) arrotondato")
    eq(p.B.y, 9, "y invariata")
    local v = {
        { key = "A", x = 0, y = 0, w = 10, h = 20 },
        { key = "B", x = 0, y = 10, w = 10, h = 20 },
        { key = "C", x = 0, y = 100, w = 10, h = 20 },
    }
    p = C.Distribute(v, "v") -- bordi: -10 .. 110, totale 60, spazio 30 -> B centro 50 (spazio 30)
    eq(p.B.y, 50); eq(p.A.y, 0); eq(p.C.y, 100)
end)

T["calc: input degenere (uno, due, duplicati, rect invalidi)"] = test(function()
    local C = LS().Calc
    local one = { { key = "A", x = 0, y = 0, w = 10, h = 10 } }
    local r, err = C.Align(one, "left")
    eq(r, nil); truthy(err:find("almeno 2"))
    r, err = C.Distribute({ one[1], { key = "B", x = 5, y = 5, w = 1, h = 1 } }, "h")
    eq(r, nil); truthy(err:find("almeno 3"))
    -- duplicati contati una volta, rect senza coordinate scartati
    local dup = { one[1], one[1], { key = "B", x = nil, y = 0 }, { key = "C", x = 0 / 0, y = 0 }, { key = "D", x = 40, y = 0, w = 10, h = 10 } }
    local p = C.Align(dup, "left")
    truthy(p and p.A and p.D and not p.B and not p.C, "solo A e D")
    eq(C.Align({ {}, "x", 5 }, "left"), nil)
    eq(C.Align(nil, "left"), nil)
    eq((C.Align(one, "diagonale")), nil)
    eq((C.Distribute({}, "z")), nil)
    local u = C.Unique({ "A", "A", 5, "B", false, "A" })
    eq(#u, 2)
    eq(C.Step(false, false, 8), 1); eq(C.Step(true, false, 8), 8); eq(C.Step(false, true, 8), 10)
    eq(C.Step(true, false, nil), 8, "griglia di default")
end)

T["calc: snap delta e descrizione differenze"] = test(function()
    local C = LS().Calc
    local me = { x = 40, y = 24, w = 100, h = 50 }
    local dx, dy = C.SnapDelta(me, { { x = 146, y = 500, w = 100, h = 10 } }, 6)
    eq(dx, 6); eq(dy, 0)
    dx, dy = C.SnapDelta(me, { { x = 300, y = 500, w = 10, h = 10 } }, 6)
    eq(dx, 0); eq(dy, 0)
    dx, dy = C.SnapDelta(nil, {}, 6); eq(dx, 0); eq(dy, 0)
    eq(C.Diff({ x = 120, y = 0 }, { x = 128, y = 0 }), "x 120 -> 128")
    eq(C.Diff({}, { hidden = true }), "nascosto")
    eq(C.Diff({ x = 1 }, { x = 1 }), "")
end)

-- Storia, transazioni, undo/redo ---------------------------------------------

T["storia: eventi del FrameManager = un passo, undo/redo ripristinano"] = test(function(Mock)
    local A = newFrame(Mock, "A", 10, 20, 100, 50)
    FM():SetOption("A", "point", "CENTER")
    FM():SetOption("A", "relPoint", "CENTER")
    FM():SetOption("A", "x", 100)
    FM():SetOption("A", "y", 50)
    eq(#LS()._undo, 1, "eventi ravvicinati coalescono")
    eq(LS():CanUndo(), true); eq(LS():CanRedo(), false)
    local x, y = center(A); eq(x, 100); eq(y, 50)
    local ok = LS():Undo()
    eq(ok, true)
    x, y = center(A); eq(x, 10, "posizione originale"); eq(y, 20)
    eq(next(BadbUI.DB.profile.frames.A), nil, "stato DB svuotato")
    eq(LS():CanUndo(), false); eq(LS():CanRedo(), true)
    eq(LS():Redo(), true)
    x, y = center(A); eq(x, 100); eq(y, 50)
    eq(BadbUI.DB.profile.frames.A.x, 100)
end)

T["storia: transazione esplicita su piu' frame"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10); newFrame(Mock, "B", 0, 0, 10, 10)
    eq(LS():Begin("Due frame"), true)
    FM():SetOption("A", "x", 5); tick(Mock)
    FM():SetOption("B", "x", 7); tick(Mock)
    FM():SetOption("A", "x", 9)
    eq(#LS()._undo, 0, "niente storia prima di End")
    LS():End()
    eq(#LS()._undo, 1)
    local e = LS()._undo[1]
    eq(#e.keys, 2); eq(e.after.A.x, 9, "ultimo valore (coalescenza nella transazione)"); eq(e.before.A.x, nil)
    LS():Undo()
    eq(BadbUI.DB.profile.frames.A.x, nil); eq(BadbUI.DB.profile.frames.B.x, nil)
    eq(LS():End(), true, "End senza Begin e' innocuo")
end)

T["storia: coalescenza per finestra temporale, non oltre"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    FM():SetOption("A", "scale", 1.1)
    FM():SetOption("A", "scale", 1.2)
    FM():SetOption("A", "scale", 1.3)
    eq(#LS()._undo, 1)
    eq(LS()._undo[1].after.A.scale, 1.3)
    tick(Mock)
    FM():SetOption("A", "scale", 1.5)
    eq(#LS()._undo, 2, "fuori finestra: nuovo passo")
    tick(Mock)
    FM():SetOption("A", "scale", 1.5)
    eq(#LS()._undo, 2, "nessun cambiamento: nessun passo")
    -- dopo un undo non si fonde con il passo precedente
    LS():Undo()
    FM():SetOption("A", "scale", 1.4)
    eq(#LS()._undo, 2)
    eq(LS()._undo[2].before.A.scale, 1.3)
end)

T["storia: coalescenza che torna allo stato iniziale elimina il passo"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    FM():SetOption("A", "alpha", 0.5)
    FM():SetOption("A", "alpha", nil)
    eq(#LS()._undo, 0)
    eq(LS():CanUndo(), false)
end)

T["storia: limite di 100 passi (e configurabile)"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    for i = 1, 120 do tick(Mock); FM():SetOption("A", "x", i) end
    eq(#LS()._undo, 100)
    local n = 0
    while LS():Undo() do n = n + 1 end
    eq(n, 100)
    eq(BadbUI.DB.profile.frames.A.x, 20, "i primi 20 passi sono stati scartati")
    LS():Set("maxHistory", 5)
    for i = 1, 10 do tick(Mock); FM():SetOption("A", "x", 200 + i) end
    eq(#LS()._undo, 5)
    LS():Set("maxHistory", -3)
    tick(Mock); FM():SetOption("A", "x", 999)
    eq(#LS()._undo, 1, "minimo 1")
end)

T["storia: undo/redo non generano nuova storia (replay)"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    for i = 1, 3 do tick(Mock); FM():SetOption("A", "x", i * 10) end
    local changed = 0
    BadbUI.Events:On({}, "BADB_FRAME_CHANGED", function() changed = changed + 1 end)
    LS():Undo(); LS():Undo()
    eq(#LS()._undo, 1); eq(#LS()._redo, 2, "nessun passo nuovo")
    LS():Redo()
    eq(#LS()._undo, 2); eq(#LS()._redo, 1)
    truthy(changed > 0, "gli altri moduli vedono comunque gli eventi")
    eq(BadbUI.DB.profile.frames.A.x, 20)
end)

T["storia: una nuova azione invalida il redo"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    tick(Mock); FM():SetOption("A", "x", 10)
    tick(Mock); FM():SetOption("A", "x", 20)
    LS():Undo()
    eq(LS():CanRedo(), true)
    tick(Mock); FM():SetOption("A", "x", 30)
    eq(LS():CanRedo(), false)
    local ok, err = LS():Redo()
    eq(ok, false); truthy(err)
    eq(BadbUI.DB.profile.frames.A.x, 30)
end)

T["storia: evento BADB_LAYOUT_HISTORY e GetHistory leggibile"] = test(function(Mock)
    newFrame(Mock, "A", 120, 0, 10, 10, { title = "Giocatore" })
    local last
    BadbUI.Events:On({}, "BADB_LAYOUT_HISTORY", function(_, u, r) last = { u, r } end)
    eq(LS():Nudge("A", 8, 0), true)
    eq(last[1], true); eq(last[2], false)
    eq(LS():Nudge("A", 8, 0), true)
    local h = LS():GetHistory()
    eq(#h, 2)
    eq(h[1].text, "Giocatore: x 128 -> 136")
    truthy(h[2].text:find("^Giocatore: x orig%. %-> 128"))
    LS():Undo()
    eq(last[1], true); eq(last[2], true)
    h = LS():GetHistory()
    eq(h[1].undone, true); eq(h[2].undone, false)
    eq(#LS():GetHistory(1), 1)
    LS():Undo()
    eq(last[1], false)
end)

T["storia: FM:Restore (Hider, clic destro) e' annullabile"] = test(function(Mock)
    local A = newFrame(Mock, "A", 0, 0, 10, 10)
    FM():SetOption("A", "hidden", true)
    eq(A:IsShown(), false)
    tick(Mock)
    FM():Restore("A") -- (il Show() interno del core viene richiuso dall'hook: limite noto del FM)
    eq(next(BadbUI.DB.profile.frames.A), nil)
    eq(#LS()._undo, 2)
    eq(LS():Undo(), true)
    eq(BadbUI.DB.profile.frames.A.hidden, true)
    eq(LS():Undo(), true)
    eq(A:IsShown(), true, "undo di hidden: mostrato")
    eq(next(BadbUI.DB.profile.frames.A), nil)
end)

T["storia: Undo/Redo senza storia ritornano false con messaggio"] = test(function()
    local ok, err = LS():Undo(); eq(ok, false); truthy(err)
    ok, err = LS():Redo(); eq(ok, false); truthy(err)
    eq(LS():ClearHistory(), true)
end)

-- Nudge, align, distribute via FrameManager ----------------------------------

T["nudge: sposta via FrameManager e annulla"] = test(function(Mock)
    local A = newFrame(Mock, "A", 120, 40, 10, 10)
    eq(LS():Nudge("A", 8, -4), true)
    local x, y = center(A); eq(x, 128); eq(y, 36)
    local c = BadbUI.DB.profile.frames.A
    eq(c.point, "CENTER"); eq(c.x, 128)
    LS():Nudge("A", 1, 1)
    eq(BadbUI.DB.profile.frames.A.x, 129, "base = valore salvato")
    LS():Undo(); LS():Undo()
    x, y = center(A); eq(x, 120); eq(y, 40)
end)

T["nudge: input errati e frame inesistenti"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    local ok, err = LS():Nudge("nope", 1, 1); eq(ok, false); truthy(err:find("nope"))
    ok = LS():Nudge("A", "x", 1); eq(ok, false)
    ok = LS():Nudge("A", 0 / 0, 1); eq(ok, false)
    ok = LS():Nudge("A", math.huge, 1); eq(ok, false)
    ok = LS():Nudge(nil, 1, 1); eq(ok, false, "nessuna selezione")
    ok = LS():Nudge({}, 1, 1); eq(ok, false)
    ok = LS():Nudge("A", nil, nil); eq(ok, false)
    eq(#LS()._undo, 0)
    -- coordinate enormi vengono limitate
    eq(LS():Nudge("A", 5e8, 0), true)
    eq(BadbUI.DB.profile.frames.A.x, 16384)
end)

T["nudge: frame senza geometria"] = test(function(Mock)
    newFrame(Mock, "G", 0, 0, 10, 10, { noGeometry = true })
    local ok, err = LS():Nudge("G", 1, 0)
    eq(ok, false); truthy(err:find("geometria"))
    -- con posizione salvata si puo' spostare comunque
    FM():SetOption("G", "point", "CENTER"); FM():SetOption("G", "relPoint", "CENTER")
    FM():SetOption("G", "x", 10); FM():SetOption("G", "y", 10)
    eq(LS():Nudge("G", 5, 0), true)
    eq(BadbUI.DB.profile.frames.G.x, 15)
end)

T["align: 5 frame = un solo passo di undo"] = test(function(Mock)
    local f = {
        newFrame(Mock, "A", -200, 0, 100, 50), newFrame(Mock, "B", 0, 100, 60, 20),
        newFrame(Mock, "C", 150, -100, 40, 40), newFrame(Mock, "D", 300, 30, 20, 20),
        newFrame(Mock, "E", -50, -200, 80, 10),
    }
    local ok, err, info = LS():Align({ "A", "B", "C", "D", "E" }, "left")
    eq(ok, true, tostring(err)); truthy(info)
    eq(#LS()._undo, 1)
    -- bordo sinistro minimo = -250
    local expect = { -200, -220, -230, -240, -210 }
    for i, fr in ipairs(f) do eq((center(fr)), expect[i], "frame " .. i) end
    local h = LS():GetHistory()
    truthy(h[1].text:find("Allinea a sinistra"), h[1].text)
    truthy(h[1].text:find("5 frame"))
    LS():Undo()
    local orig = { -200, 0, 150, 300, -50 }
    for i, fr in ipairs(f) do eq((center(fr)), orig[i], "ripristino " .. i) end
    LS():Redo()
    for i, fr in ipairs(f) do eq((center(fr)), expect[i], "redo " .. i) end
end)

T["align: tutti i modi applicati via FM"] = test(function(Mock)
    local A = newFrame(Mock, "A", -200, 0, 100, 50)
    local B = newFrame(Mock, "B", 0, 100, 60, 20)
    local C = newFrame(Mock, "C", 150, -100, 40, 40)
    local keys = { "A", "B", "C" }
    LS():Align(keys, "top")
    eq(select(2, center(A)), 85); eq(select(2, center(B)), 100); eq(select(2, center(C)), 90)
    LS():Align(keys, "hcenter")
    eq((center(A)), -40); eq((center(B)), -40); eq((center(C)), -40)
    LS():Align(keys, "vcenter")
    eq(select(2, center(A)), select(2, center(B)))
    local ok, err = LS():Align(keys, "boh"); eq(ok, false); truthy(err)
end)

T["distribute: via FM, un passo di undo"] = test(function(Mock)
    local A = newFrame(Mock, "A", -300, 0, 100, 10)
    local B = newFrame(Mock, "B", -100, 0, 100, 10)
    local C = newFrame(Mock, "C", 250, 0, 50, 10)
    eq(LS():Distribute({ "C", "A", "B" }, "h"), true)
    eq((center(A)), -300); eq((center(B)), -12); eq((center(C)), 250)
    eq(#LS()._undo, 1)
    LS():Undo()
    eq((center(B)), -100)
    local ok, err = LS():Distribute({ "A", "B" }, "h"); eq(ok, false); truthy(err:find("almeno 3"))
    ok = LS():Distribute({ "A", "B", "C" }, "x"); eq(ok, false)
end)

T["align: un frame, duplicati, chiavi inesistenti, nessuna geometria"] = test(function(Mock)
    local A = newFrame(Mock, "A", -100, 0, 20, 20)
    local B = newFrame(Mock, "B", 100, 30, 20, 20)
    newFrame(Mock, "G", 0, 0, 20, 20, { noGeometry = true })
    local ok, err = LS():Align({ "A" }, "left"); eq(ok, false); truthy(err:find("almeno 2"))
    ok = LS():Align({ "A", "A", "A" }, "left"); eq(ok, false, "duplicati = un frame")
    ok = LS():Align({}, "left"); eq(ok, false)
    ok = LS():Align("A", "left"); eq(ok, false)
    ok = LS():Align(nil, "left"); eq(ok, false)
    ok = LS():Align({ "nope", "nada" }, "left"); eq(ok, false)
    ok = LS():Align({ "A", "nope" }, "left"); eq(ok, false, "uno solo valido")
    local info
    ok, err, info = LS():Align({ "A", "B", "nope", "G", "A" }, "top")
    eq(ok, true, tostring(err))
    eq(info.unknown[1], "nope"); eq(info.noGeometry[1], "G")
    eq(select(2, center(A)), select(2, center(B)))
    eq(#LS()._undo, 1)
    -- gia' allineati: nessun nuovo passo
    ok = LS():Align({ "A", "B" }, "top"); eq(ok, true)
    eq(#LS()._undo, 1)
end)

-- Edit Mode, combattimento, gruppi --------------------------------------------

T["edit mode: nessuna modifica, messaggio chiaro, mai SetPoint"] = test(function(Mock)
    BadbUI.Compat.hasEditMode = true
    local E = newFrame(Mock, "E", 0, 0, 50, 50, { editMode = true })
    local A = newFrame(Mock, "A", 100, 0, 50, 50)
    local B = newFrame(Mock, "B", 200, 40, 50, 50)
    local ok, err = LS():Nudge("E", 5, 5)
    eq(ok, false); eq(err, "gestito dall'Edit Mode")
    ok, err = LS():Align({ "E" }, "left")
    eq(ok, false); eq(err, "gestito dall'Edit Mode")
    ok, err = LS():Align({ "E", "A" }, "left")
    eq(ok, false, "resta un solo frame valido")
    ok = LS():Align({ "E", "A", "B" }, "top")
    eq(ok, true, "A e B si allineano, E viene saltato")
    eq(E.setCalls, 0, "SetPoint mai chiamato sul frame Edit Mode")
    eq(BadbUI.DB.profile.frames.E == nil or next(BadbUI.DB.profile.frames.E) == nil, true)
    eq(select(2, center(A)), select(2, center(B)))
    ok, err = LS():Distribute({ "E", "E", "E" }, "h")
    eq(ok, false); eq(err, "gestito dall'Edit Mode")
    eq(#LS()._undo, 1)
end)

T["edit mode: con layout preset Blizzard il messaggio suggerisce di duplicarlo"] = test(function(Mock)
    BadbUI.Compat.hasEditMode = true
    newFrame(Mock, "E", 0, 0, 50, 50, { editMode = true })
    local active = 1 -- indice presente nella lista utente = layout utente
    C_EditMode = { GetLayouts = function() return { layouts = { { layoutName = "Mio" } }, activeLayout = active } end }
    local ok, err = LS():Nudge("E", 1, 1)
    C_EditMode = nil
    eq(ok, false)
    eq(err:sub(1, #"gestito dall'Edit Mode"), "gestito dall'Edit Mode")
    truthy(err:find("EditModeBridge") == nil, "layout utente: nessun suggerimento")
    active = 2
    C_EditMode = { GetLayouts = function() return { layouts = { { layoutName = "Mio" } }, activeLayout = 2 } end }
    ok, err = LS():Nudge("E", 1, 1)
    C_EditMode = nil
    eq(ok, false)
    truthy(err:find("duplicalo") and err:find("EditModeBridge"), err)
    eq(err:sub(1, #"gestito dall'Edit Mode"), "gestito dall'Edit Mode")
    -- API del client che fallisce: messaggio base
    C_EditMode = { GetLayouts = function() error("boom") end }
    ok, err = LS():Nudge("E", 1, 1)
    C_EditMode = nil
    eq(err, "gestito dall'Edit Mode")
end)

T["combattimento: frame protetti rifiutati, gli altri no"] = test(function(Mock)
    local P = newFrame(Mock, "P", 0, 0, 50, 50, { protected = true })
    local A = newFrame(Mock, "A", 100, 0, 50, 50)
    local B = newFrame(Mock, "B", 200, 40, 50, 50)
    eq(LS():Nudge("P", 5, 0), true)
    Mock.combat = true
    local ok, err = LS():Nudge("P", 5, 0)
    eq(ok, false); eq(err, "in combattimento")
    eq(BadbUI.DB.profile.frames.P.x, 5, "nulla e' cambiato")
    ok, err = LS():Align({ "P", "A", "B" }, "top")
    eq(ok, false); eq(err, "in combattimento")
    eq(select(2, center(A)), 0, "nessun frame mosso")
    -- non protetti: funziona anche in combattimento
    eq(LS():Nudge("A", 3, 0), true)
    eq((center(A)), 103)
    -- l'undo di un passo con frame protetto e' rifiutato, quello dei non protetti no
    eq(LS():Undo(), true)
    ok, err = LS():Undo()
    eq(ok, false); eq(err, "in combattimento")
    eq(LS():CanUndo(), true, "il passo resta in storia")
    Mock.combat = false
    eq(LS():Undo(), true)
    eq(BadbUI.DB.profile.frames.P.x, nil)
end)

T["gruppi: blocco impedisce nudge, align e undo"] = test(function(Mock)
    local A = newFrame(Mock, "A", 0, 0, 10, 10)
    local B = newFrame(Mock, "B", 50, 20, 10, 10)
    local C = newFrame(Mock, "C", 90, 60, 10, 10)
    eq(LS():Nudge("A", 5, 0), true)
    eq(LS():Group("g", { "A", "B", "A", "nope" }), true)
    eq(#LS():GetGroups().g.keys, 2, "duplicati e inesistenti scartati")
    eq(LS():SetGroupLock("g", true), true)
    eq(LS():GetGroups().g.locked, true)
    eq(LS():Get("groups").g.locked, true, "salvato nel profilo")
    local ok, err = LS():Nudge("A", 5, 0)
    eq(ok, false); truthy(err:find("bloccato"))
    ok = LS():Align({ "A", "B", "C" }, "top"); eq(ok, false)
    eq(select(2, center(C)), 60)
    ok, err = LS():Undo(); eq(ok, false); truthy(err:find("bloccato"))
    eq(LS():Nudge("C", 1, 0), true, "frame fuori dal gruppo")
    eq(LS():SetGroupLock("g", false), true)
    eq(LS():Nudge("A", 5, 0), true)
    eq(LS():Align({ "A", "B", "C" }, "left"), true)
    -- gestione del gruppo
    ok = LS():Group("", { "A" }); eq(ok, false)
    ok = LS():Group(5, { "A" }); eq(ok, false)
    ok = LS():Group("x", { "nope" }); eq(ok, false)
    ok = LS():Group("x", "A"); eq(ok, false)
    ok = LS():SetGroupLock("inesistente", true); eq(ok, false)
    ok = LS():Ungroup("inesistente"); eq(ok, false)
    eq(LS():Ungroup("g"), true)
    eq(LS():Get("groups").g, nil)
    eq(LS():Group("h", { "B", "C" }), true)
    eq(LS():SelectGroup("h"), true)
    eq(#LS():GetSelection(), 2)
end)

-- Profilo e attivazione ---------------------------------------------------------

T["cambio profilo svuota la storia"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    LS():Nudge("A", 5, 5)
    LS():Group("g", { "A" })
    eq(LS():CanUndo(), true)
    local last
    BadbUI.Events:On({}, "BADB_LAYOUT_HISTORY", function(_, u, r) last = { u, r } end)
    BadbUI.DB:SetProfile("Altro")
    eq(LS():CanUndo(), false); eq(LS():CanRedo(), false)
    eq(last[1], false); eq(last[2], false)
    eq(LS():Get("groups").g, nil, "i gruppi sono del profilo")
    -- nel nuovo profilo si ricomincia a registrare correttamente
    tick(Mock)
    eq(LS():Nudge("A", 1, 0), true)
    eq(#LS()._undo, 1)
    BadbUI.DB:ResetProfile()
    eq(LS():CanUndo(), false)
end)

T["disattivazione: overlay spento, storia vuota, API inerti"] = test(function(Mock)
    local A = newFrame(Mock, "A", 0, 0, 10, 10)
    FM():SetUnlocked(true)
    LS():Select("A")
    truthy(LS():IsCapturing())
    LS():Nudge("A", 5, 5)
    BadbUI.Modules:SetEnabled("LayoutStudio", false)
    eq(LS():IsCapturing(), false)
    eq(LS():CanUndo(), false)
    eq(BadbUI.Events.listeners.BADB_FRAME_CHANGED == nil or BadbUI.Events.listeners.BADB_FRAME_CHANGED[LS()] == nil, true)
    eq(BadbUI.Events.listeners.BADB_UNLOCK_CHANGED == nil or BadbUI.Events.listeners.BADB_UNLOCK_CHANGED[LS()] == nil, true)
    eq(LS()._kb:IsShown(), false)
    local ok, err = LS():Nudge("A", 1, 1); eq(ok, false); eq(err, "modulo disattivato")
    ok = LS():Undo(); eq(ok, false)
    ok = LS():Align({ "A", "B" }, "left"); eq(ok, false)
    ok = LS():Select("A"); eq(ok, false)
    -- gli hook sui mover/Restore restano ma sono inerti
    FM().movers.A.__scripts.OnMouseDown(FM().movers.A, "LeftButton")
    FM():SetOption("A", "x", 3)
    FM():Restore("A")
    eq(LS():CanUndo(), false)
    -- riattivazione: storia pulita e registrazione di nuovo attiva
    BadbUI.Modules:SetEnabled("LayoutStudio", true)
    eq(LS():CanUndo(), false)
    tick(Mock)
    FM():SetOption("A", "x", 8)
    eq(LS():CanUndo(), true)
end)

T["preset applicato o backup ripristinato invalida la storia"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    LS():Nudge("A", 5, 0)
    BadbUI.Events:Fire("BADB_PRESET_APPLIED", "x", "merge")
    eq(LS():CanUndo(), false)
    LS():Nudge("A", 5, 0)
    BadbUI.Events:Fire("BADB_BACKUP_RESTORED", "id")
    eq(LS():CanUndo(), false)
end)

-- Tastiera, selezione, mover ----------------------------------------------------

local function keyboard(Mock)
    local kb = LS()._kb
    kb.EnableKeyboard = function(s, v) s.kbOn = v end
    kb.SetPropagateKeyboardInput = function(s, v) s.prop = v end
    return kb
end

T["tastiera: cattura solo con sblocco e selezione"] = test(function(Mock)
    local A = newFrame(Mock, "A", 0, 0, 10, 10)
    local kb = keyboard(Mock)
    LS():_updateCapture()
    eq(kb.kbOn, false)
    LS():Select("A")
    eq(LS():IsCapturing(), false, "bloccato: nessuna cattura")
    eq(kb.kbOn, false)
    FM():SetUnlocked(true)
    eq(LS():IsCapturing(), true); eq(kb.kbOn, true)
    LS():Select(nil)
    eq(LS():IsCapturing(), false); eq(kb.kbOn, false, "nessuna selezione")
    LS():Select("A")
    eq(kb.kbOn, true)
    FM():SetUnlocked(false)
    eq(kb.kbOn, false); eq(kb:IsShown(), false)
    FM():SetUnlocked(true)
    -- entrata in combattimento: FM sblocca, la cattura si spegne
    Mock.combat = true
    Mock.Fire("PLAYER_REGEN_DISABLED")
    eq(FM().unlocked, false)
    eq(kb.kbOn, false)
    Mock.combat = false
end)

T["tastiera: frecce, shift = griglia, ctrl = 10, tutto il resto propaga"] = test(function(Mock)
    local A = newFrame(Mock, "A", 100, 100, 10, 10)
    local kb = keyboard(Mock)
    FM():SetUnlocked(true)
    LS():Select("A")
    local down = kb.__scripts.OnKeyDown
    down(kb, "LEFT"); eq(kb.prop, false, "freccia consumata")
    eq((center(A)), 99)
    down(kb, "UP"); eq(select(2, center(A)), 101)
    down(kb, "DOWN"); down(kb, "DOWN"); eq(select(2, center(A)), 99)
    Mock.shift = true
    down(kb, "RIGHT"); eq((center(A)), 107, "griglia di default 8")
    LS():SetGridSize(16)
    down(kb, "RIGHT"); eq((center(A)), 123)
    Mock.shift = false; Mock.ctrl = true
    down(kb, "RIGHT"); eq((center(A)), 133)
    -- Ctrl+Z / Ctrl+Y
    down(kb, "Z"); eq(kb.prop, false); eq((center(A)), 123)
    down(kb, "Y"); eq((center(A)), 133)
    Mock.ctrl = false
    for _, k in ipairs({ "ESCAPE", "W", "A", "SPACE", "Z", "Y", "F1", "ENTER", "LSHIFT" }) do
        down(kb, k)
        eq(kb.prop, true, "il tasto " .. k .. " deve propagare")
    end
    -- Nessuna selezione/cattura: si propaga anche una freccia
    LS():Select(nil)
    down(kb, "LEFT"); eq(kb.prop, true)
    eq((center(A)), 133, "non mosso")
end)

T["tastiera: selezione multipla muove tutto in un passo"] = test(function(Mock)
    local A = newFrame(Mock, "A", 0, 0, 10, 10)
    local B = newFrame(Mock, "B", 50, 50, 10, 10)
    local kb = keyboard(Mock)
    FM():SetUnlocked(true)
    LS():Select("A"); LS():Select("B", true)
    eq(#LS():GetSelection(), 2)
    kb.__scripts.OnKeyDown(kb, "LEFT")
    eq((center(A)), -1); eq((center(B)), 49)
    eq(#LS()._undo, 1)
    LS():Select("A", true) -- alterna: A esce dalla selezione
    eq(#LS():GetSelection(), 1)
    local ok, err = LS():Select("nope"); eq(ok, false); truthy(err)
    ok = LS():Select(42); eq(ok, false)
    eq(LS():SelectAll("Test"), true)
    eq(#LS():GetSelection(), 2)
    eq(LS():SelectAll("Inesistente"), true)
    eq(#LS():GetSelection(), 0)
end)

T["tastiera: un errore nel nudge non mangia il tasto"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10)
    local kb = keyboard(Mock)
    FM():SetUnlocked(true)
    LS():Select("A")
    local orig = LS().NudgeSelection
    LS().NudgeSelection = function() error("boom") end
    kb.__scripts.OnKeyDown(kb, "LEFT")
    eq(kb.prop, true, "errore: il tasto propaga")
    LS().NudgeSelection = orig
end)

T["mover: clic seleziona, shift-clic aggiunge, sondaggio difensivo"] = test(function(Mock)
    newFrame(Mock, "A", 0, 0, 10, 10); newFrame(Mock, "B", 50, 0, 10, 10)
    FM():SetUnlocked(true)
    local mA, mB = FM().movers.A, FM().movers.B
    truthy(mA and mB)
    mA.__scripts.OnMouseDown(mA, "LeftButton")
    eq(LS():GetSelection()[1], "A"); eq(#LS():GetSelection(), 1)
    Mock.shift = true
    mB.__scripts.OnMouseDown(mB, "LeftButton")
    eq(#LS():GetSelection(), 2)
    Mock.shift = false
    mB.__scripts.OnMouseDown(mB, "RightButton")
    eq(#LS():GetSelection(), 2, "il clic destro non cambia la selezione")
    mB.__scripts.OnMouseDown(mB, "LeftButton")
    eq(#LS():GetSelection(), 1)
    -- mover mancanti o strani: nessun errore
    FM().movers.Strano = "non un frame"
    FM().movers.Vuoto = {}
    FM():SetUnlocked(true)
    LS():_hookMovers()
    eq(LS():Select("A"), true)
end)

T["mover: drag registrato come passo, snap intelligente"] = test(function(Mock)
    local A = newFrame(Mock, "A", 0, 0, 100, 50)
    newFrame(Mock, "B", 146, 400, 100, 10)
    FM():SetUnlocked(true)
    local m = FM().movers.A
    local function drag(cx, cy)
        m.__scripts.OnDragStart(m)
        m.GetCenter = function() return UX + cx, UY + cy end
        m.__scripts.OnDragStop(m)
    end
    LS():Set("snap", false)
    drag(37, 21) -- griglia 8 -> (40, 24)
    local x, y = center(A); eq(x, 40); eq(y, 24)
    eq(#LS()._undo, 1)
    LS():Undo()
    x, y = center(A); eq(x, 0); eq(y, 0)
    eq(next(BadbUI.DB.profile.frames.A), nil)
    -- con lo snap: il bordo destro di A (90) si aggancia al bordo sinistro di B (96)
    tick(Mock)
    LS():Set("snap", true)
    drag(37, 21)
    x, y = center(A); eq(x, 46); eq(y, 24)
    eq(#LS()._undo, 1, "drag + snap = un solo passo")
    LS():Undo()
    eq((center(A)), 0)
    eq(LS():ToggleSnap(), false)
    eq(LS():ToggleSnap(), true)
end)

T["griglia: SetGridSize valida e limita"] = test(function()
    local ok, n = LS():SetGridSize(12.7); eq(ok, true); eq(n, 12)
    eq(BadbUI.DB.sv.global.gridSize, 12)
    ok, n = LS():SetGridSize(0); eq(n, 1)
    ok, n = LS():SetGridSize(9999); eq(n, 128)
    ok = LS():SetGridSize("abc"); eq(ok, false)
    ok = LS():SetGridSize(nil); eq(ok, false)
    ok = LS():SetGridSize(0 / 0); eq(ok, false)
    eq(LS():GetGridSize(), 128)
end)

-- Pagina e comandi ---------------------------------------------------------------

T["page: costruzione, stato dei pulsanti, cronologia"] = test(function(Mock)
    local page = LS().page
    eq(page.category, "Strumenti"); eq(type(page.build), "function")
    local parent = Mock.NewObject("Frame")
    local h = page.build(parent, { UI = BadbUI.ConfigUI, W = BadbUI.Widgets })
    eq(type(h), "number"); truthy(h > 100)
    local ui = LS()._ui
    eq(ui.undo.__enabledState, false); eq(ui.redo.__enabledState, false)
    newFrame(Mock, "A", 0, 0, 10, 10, { title = "Giocatore" })
    LS():Nudge("A", 8, 0)
    eq(ui.undo.__enabledState, true)
    truthy(ui.lines[1].__text:find("Giocatore"), ui.lines[1].__text)
    eq(ui.lines[2].__text, "")
    LS():Undo()
    eq(ui.redo.__enabledState, true); eq(ui.undo.__enabledState, false)
    truthy(ui.lines[1].__text:find("annullato"))
    LS():Select("A")
    truthy(ui.selection.__text:find("Giocatore"))
    for i = 1, 14 do tick(Mock); FM():SetOption("A", "x", i) end
    LS():Redo()
    page.refresh()
    truthy(ui.lines[10].__text ~= "" and ui.lines[11] == nil, "massimo 10 righe")
    -- build senza widget condivisi: nessun errore
    local saved = BadbUI.Widgets
    BadbUI.Widgets = nil
    eq(type(page.build(Mock.NewObject("Frame"), {})), "number")
    BadbUI.Widgets = saved
    -- pulsanti Sblocca/Blocca tramite il FrameManager
    local clicks = {}
    local prev = CreateFrame
    CreateFrame = function(kind, name, p, tpl)
        local f = prev(kind, name, p, tpl)
        if kind == "Button" then clicks[#clicks + 1] = f end
        return f
    end
    page.build(Mock.NewObject("Frame"), { W = saved })
    CreateFrame = prev
    local unlockBtn = clicks[1]
    unlockBtn.__scripts.OnClick(unlockBtn)
    eq(FM().unlocked, true)
    clicks[2].__scripts.OnClick(clicks[2])
    eq(FM().unlocked, false)
end)

T["page: allinea/distribuisci agiscono sulla selezione"] = test(function(Mock)
    local A = newFrame(Mock, "A", -100, 0, 20, 20)
    local B = newFrame(Mock, "B", 100, 50, 20, 20)
    local clicks = {}
    local prev = CreateFrame
    CreateFrame = function(kind, name, p, tpl)
        local f = prev(kind, name, p, tpl)
        if kind == "Button" then clicks[#clicks + 1] = f end
        return f
    end
    LS().page.build(Mock.NewObject("Frame"), { W = BadbUI.Widgets })
    CreateFrame = prev
    -- ordine pulsanti: Sblocca, Blocca, Annulla, Ripeti, Tutti, Deseleziona, 6 allinea, 2 distribuisci
    local function click(i) clicks[i].__scripts.OnClick(clicks[i]) end
    click(5)
    truthy(#LS():GetSelection() >= 2, "seleziona tutti")
    LS():Select("A"); LS():Select("B", true)
    click(9) -- Alto
    eq(select(2, center(A)), select(2, center(B)))
    click(3) -- Annulla
    eq(select(2, center(A)), 0)
    click(6) -- Deseleziona
    eq(#LS():GetSelection(), 0)
    click(9) -- allinea senza selezione: avviso, nessun errore
    eq(#LS()._undo, 0)
end)

T["comandi: layout undo | redo | grid | nudge | snap"] = test(function(Mock)
    local cmd = LS().commands.layout
    truthy(cmd and cmd.help and cmd.fn)
    local A = newFrame(Mock, "A", 10, 10, 10, 10)
    cmd.fn("nudge A 5 -5")
    eq((center(A)), 15); eq(select(2, center(A)), 5)
    cmd.fn("undo")
    eq((center(A)), 10)
    cmd.fn("redo")
    eq((center(A)), 15)
    cmd.fn("grid 20")
    eq(BadbUI.DB.sv.global.gridSize, 20)
    cmd.fn("grid abc")
    eq(BadbUI.DB.sv.global.gridSize, 20)
    local before = LS():Get("snap")
    cmd.fn("snap")
    eq(LS():Get("snap"), not before)
    -- input malformati: nessun errore Lua
    cmd.fn(""); cmd.fn("boh"); cmd.fn("nudge"); cmd.fn("nudge A x y"); cmd.fn("nudge nope 1 1")
    cmd.fn(nil); cmd.fn("grid"); cmd.fn("undo undo undo")
    cmd.fn(string.rep("x", 100000))
end)

return T
