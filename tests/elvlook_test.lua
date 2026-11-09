-- Test del modulo ElvLook (datatext, minimappa quadrata, chat, fondo barre, stile con un click)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}

local function newFrame(Mock, name)
    local f = Mock.NewObject("Frame")
    f.__name = name
    _G[name] = f
    return f
end

-- API di sistema usate dai datatext.
local function stubSystem(Mock, over)
    over = over or {}
    -- il mock generico non registra le dimensioni: qui si'
    local M = Mock.Methods
    function M:SetSize(w, h) self.__width, self.__height = w, h end
    function M:SetWidth(w) self.__width = w end
    function M:SetHeight(h) self.__height = h end
    function M:GetSize() return self.__width, self.__height end
    function M:GetHeight() return self.__height end
    local pts = {}
    function M:SetPoint(...) self.__points = self.__points or {}; table.insert(self.__points, { ... }) end
    function M:ClearAllPoints() self.__points = {} end
    function GetFramerate() return over.fps or 59.6 end
    function GetNetStats() return 0, 0, over.home or 20, over.world or 35 end
    function GetMoney() return over.money or 12345678 end
    function GetInventoryItemDurability(slot)
        if over.durability then return over.durability(slot) end
        if slot == 1 then return 90, 100 elseif slot == 5 then return 40, 100 end
        return nil
    end
    function date() return "21:07" end
end

local function elv() return BadbUI.Modules:Get("ElvLook") end

local function runUpdate(panel)
    panel.__scripts.OnUpdate(panel, 1.1)
end
local function left(M) return M.panels.left end
local function right(M) return M.panels.right end

T["e' registrato, attivo di default e ha i due pannelli datatext"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    truthy(M, "modulo non registrato")
    truthy(M.enabled, "non attivo di default")
    truthy(left(M) and right(M), "pannelli non creati")
    eq(_G.BadbElvDatatextLeft, left(M)); eq(_G.BadbElvDatatextRight, right(M))
    truthy(BadbUI.FrameManager.registry.ElvDatatext_left, "pannello sinistro non registrato nel FrameManager")
    truthy(BadbUI.FrameManager.registry.ElvDatatext_right, "pannello destro non registrato nel FrameManager")
    truthy(left(M):IsShown() and right(M):IsShown())
end

T["misure di default come ElvUI: 412x22, tre caselle, angoli in basso"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    M.panels = nil; M:Apply() -- ricrea con il mock che registra misure e punti
    local w, h = left(M):GetSize()
    eq(w, 412); eq(h, 22)
    eq(#left(M).slots, 3); eq(#right(M).slots, 3)
    local pl, pr = left(M).__points[1], right(M).__points[1]
    eq(pl[1], "BOTTOMLEFT"); eq(pr[1], "BOTTOMRIGHT")
    eq(left(M).slots[1].__font[1], "Fonts\\ARIALN.TTF", "font stretto come PT Sans Narrow")
end

T["datatext: destra = fps/latenza, ora, oro; sinistra = zona, durabilita' (peggiore), borse"] = function(Mock)
    stubSystem(Mock)
    function GetMinimapZoneText() return "Elwynn" end
    local M = elv()
    M:Apply()
    runUpdate(right(M)); runUpdate(left(M))
    local r, l = right(M).slots, left(M).slots
    truthy(r[1].__text:find("60", 1, true), "fps arrotondati")
    truthy(r[1].__text:find("35", 1, true), "latenza world")
    truthy(r[2].__text:find("21:07", 1, true), "orologio")
    truthy(r[3].__text:find("1,234", 1, true), "oro con separatore migliaia")
    truthy(r[3].__text:find("56", 1, true), "argento")
    truthy(l[1].__text:find("Elwynn", 1, true), "zona")
    truthy(l[2].__text:find("40%%"), "durabilita' peggiore (40%)")
end

T["datatext: durabilita' senza oggetti, danger sotto il 25%"] = function(Mock)
    stubSystem(Mock, { durability = function() return nil end })
    local M = elv()
    M:Apply(); runUpdate(left(M))
    truthy(left(M).slots[2].__text:find("-", 1, true), "senza oggetti mostra trattino")
    stubSystem(Mock, { durability = function(slot) if slot == 3 then return 10, 100 end end })
    runUpdate(left(M))
    truthy(left(M).slots[2].__text:find("10%%"), "10%")
    truthy(left(M).slots[2].__text:find(BadbUI.Theme:Hex("danger"), 1, true), "colore pericolo")
end

T["un datatext che lancia errori non ferma gli altri"] = function(Mock)
    stubSystem(Mock)
    function GetFramerate() error("boom") end
    local M = elv()
    M:Apply()
    local ok = pcall(runUpdate, right(M))
    truthy(ok, "l'errore e' uscito dall'OnUpdate")
    eq(right(M).slots[1].__text, "", "casella rotta vuota")
    truthy(right(M).slots[2].__text:find("21:07", 1, true), "le altre caselle funzionano")
end

T["casella scelta dall'utente e valore sconosciuto"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    M:Set("right1", "time"); M:Set("right2", "inesistente")
    M:Apply(); runUpdate(right(M))
    truthy(right(M).slots[1].__text:find("21:07", 1, true))
    eq(right(M).slots[2].__text, "", "valore sconosciuto = vuoto")
end

T["opzioni numeriche corrotte: si usano i limiti"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    M:Set("panelWidth", 0 / 0); M:Set("panelHeight", "x"); M:Set("fontSize", 9999)
    M:Apply()
    eq(left(M):GetWidth(), 412, "NaN: default")
    truthy(left(M).slots[1].__font[2] <= 18, "font oltre il limite")
end

T["larghezza e altezza regolabili"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    M:Set("panelWidth", 600); M:Set("panelHeight", 30); M:Apply()
    local w, h = right(M):GetSize()
    eq(w, 600); eq(h, 30)
end

T["pannelli nascosti se disattivati, nessun frame doppio"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    local first = left(M)
    M:Set("datatexts", false); M:Apply()
    eq(left(M):IsShown(), false); eq(right(M):IsShown(), false)
    M:Set("datatexts", true); M:Apply()
    eq(left(M), first, "pannello ricreato")
    truthy(left(M):IsShown())
end

T["minimappa: quadrata, pezzi Blizzard nascosti e ripristinati"] = function(Mock)
    stubSystem(Mock)
    local mm = newFrame(Mock, "Minimap")
    mm.SetMaskTexture = function(self, t) self.mask = t end
    local border = newFrame(Mock, "MinimapBorder")
    border:SetAlpha(0.8)
    MinimapCluster = Mock.NewObject("Frame")
    MinimapCluster.BorderTop = Mock.NewObject("Texture")
    local M = elv()
    M:Apply()
    eq(mm.mask, "Interface\\Buttons\\WHITE8X8", "maschera quadrata (client classico, senza ZoomIn)")
    eq(GetMinimapShape(), "SQUARE")
    eq(border:GetAlpha(), 0, "bordo nascosto")
    eq(MinimapCluster.BorderTop:GetAlpha(), 0)
    truthy(M.mmFrame and M.mmFrame:IsShown(), "cornice")
    M:Set("minimap", false); M:Apply()
    eq(border:GetAlpha(), 0.8, "alpha originale non ripristinato")
    eq(M.mmFrame:IsShown(), false)
    eq(GetMinimapShape, nil, "GetMinimapShape non ripristinato")
end

T["minimappa su client moderno/Forever: maschere a fileID come ElvUI e pezzi Forever nascosti"] = function(Mock)
    stubSystem(Mock)
    local mm = newFrame(Mock, "Minimap")
    mm.SetMaskTexture = function(self, t) self.mask = t end
    mm.ZoomIn = Mock.NewObject("Button")
    local underlay = newFrame(Mock, "MinimapCompassTextureUnderlay")
    MinimapCluster = Mock.NewObject("Frame")
    MinimapCluster.DielFrame = Mock.NewObject("Frame")
    local M = elv()
    M:Apply()
    eq(mm.mask, 130937, "maschera quadrata moderna")
    eq(underlay:GetAlpha(), 0); eq(MinimapCluster.DielFrame:GetAlpha(), 0); eq(mm.ZoomIn:GetAlpha(), 0)
    M:Set("minimap", false); M:Apply()
    eq(mm.mask, 186178, "maschera tonda moderna ripristinata")
    eq(underlay:GetAlpha(), 1)
    eq(MinimapCluster.DielFrame:GetAlpha(), 1, "pezzo del cluster non ripristinato")
    eq(mm.ZoomIn:GetAlpha(), 1, "ZoomIn non ripristinato")
end

T["minimappa assente: nessun errore"] = function(Mock)
    stubSystem(Mock)
    _G.Minimap = nil
    local M = elv()
    M:Apply()
    truthy(M.enabled)
end

T["chat: sfondo che segue il frame, pulsanti nascosti e ripristinati"] = function(Mock)
    stubSystem(Mock)
    NUM_CHAT_WINDOWS = 2
    local cf = newFrame(Mock, "ChatFrame1")
    local btn = newFrame(Mock, "ChatFrame1ButtonFrame")
    local menu = newFrame(Mock, "ChatFrameMenuButton")
    newFrame(Mock, "ChatFrame1EditBox")
    local M = elv()
    M:Apply()
    local rec = M.chatFrames[1]
    truthy(rec and rec.bd, "sfondo chat non creato")
    eq(btn:GetAlpha(), 0); eq(menu:GetAlpha(), 0)
    truthy(rec.bd:IsShown())
    cf.__scripts.OnHide(cf)
    eq(rec.bd:IsShown(), false, "lo sfondo deve seguire la chat")
    cf.__scripts.OnShow(cf)
    truthy(rec.bd:IsShown())
    M:Set("chat", false); M:Apply()
    eq(btn:GetAlpha(), 1); eq(menu:GetAlpha(), 1)
    eq(rec.bd:IsShown(), false)
end

T["barre azioni: fondo piatto e decorazioni nascoste, ripristino al disable"] = function(Mock)
    stubSystem(Mock)
    local main = MainActionBar
    main.BorderArt = Mock.NewObject("Texture")
    main.EndCaps = Mock.NewObject("Frame")
    main.EndCaps.LeftEndCap = Mock.NewObject("Texture")
    main.EndCaps.RightEndCap = Mock.NewObject("Texture")
    local M = elv()
    M:Apply()
    truthy(M.barFrames.MainActionBar, "fondo barra principale")
    truthy(M.barFrames.MultiBarBottomLeft, "fondo seconda barra")
    eq(main.BorderArt:GetAlpha(), 0)
    eq(main.EndCaps.LeftEndCap:GetAlpha(), 0)
    BadbUI.Modules:SetEnabled("ElvLook", false)
    eq(main.BorderArt:GetAlpha(), 1, "decorazione non ripristinata")
    eq(main.EndCaps.RightEndCap:GetAlpha(), 1)
    eq(M.barFrames.MainActionBar:IsShown(), false)
    eq(left(M):IsShown(), false); eq(right(M):IsShown(), false)
end

T["barre azioni: in combattimento il fondo e' rimandato"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    M.barFrames = nil
    Mock.combat = true
    M:Apply()
    eq(M.barFrames, nil, "creato in combattimento")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    truthy(M.barFrames and M.barFrames.MainActionBar, "non creato a fine combattimento")
end

T["riattivare non duplica i frame"] = function(Mock)
    stubSystem(Mock)
    local M = elv()
    local bar, bd = left(M), M.barFrames.MainActionBar
    BadbUI.Modules:SetEnabled("ElvLook", false)
    BadbUI.Modules:SetEnabled("ElvLook", true)
    eq(left(M), bar); eq(M.barFrames.MainActionBar, bd)
    truthy(left(M):IsShown())
end

T["/badb elv: tema ElvUI e moduli visibili attivi, backup creato"] = function(Mock)
    stubSystem(Mock)
    local Modules = BadbUI.Modules
    Modules:SetEnabled("UnitFrames", false)
    BadbUI.Theme:SetScheme("night"); BadbUI.Theme:SetAccent("gold")
    local made
    BadbUI.Backups.Create = function(_, label) made = label end
    elv():ApplyElvStyle(true)
    eq(BadbUI.Theme.state.scheme, "elvui"); eq(BadbUI.Theme.state.accent, "elvui")
    truthy(BadbUI.DB:Get("UnitFrames", "enabled"), "unit frame spenti nel profilo")
    truthy(Modules:Get("ActionBars").enabled)
    eq(made, "pre-elvui", "backup mancante")
end

T["primo avvio: non applica nulla da solo (decide il wizard), suggerisce /badb elv una volta"] = function(Mock)
    stubSystem(Mock)
    BadbUI.Modules:SetEnabled("UnitFrames", false)
    BadbUI.Theme:SetScheme("night")
    local made = 0
    BadbUI.Backups.Create = function() made = made + 1 end
    BadbUI.DB.sv.global.elvStyleHinted = nil
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    truthy(BadbUI.DB.sv.global.elvStyleHinted, "suggerimento non segnato")
    eq(BadbUI.DB:Get("UnitFrames", "enabled"), false, "ha acceso i unit frame da solo")
    eq(BadbUI.Theme.state.scheme, "night", "ha cambiato il tema da solo")
    eq(made, 0, "ha creato un backup da solo")
    local hints = 0
    for _, l in ipairs(Mock.chat) do if l:find("/badb elv", 1, true) then hints = hints + 1 end end
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    local after = 0
    for _, l in ipairs(Mock.chat) do if l:find("/badb elv", 1, true) then after = after + 1 end end
    eq(after, hints, "suggerimento ripetuto")
end

T["OtherUI rileva un'altra UI caricata (es. Skill Capped)"] = function(Mock)
    stubSystem(Mock)
    C_AddOns.IsAddOnLoaded = function(name) return name == "SkillCapped" end
    eq(elv():OtherUI(), "SkillCapped")
    C_AddOns.IsAddOnLoaded = function() return false end
    eq(elv():OtherUI(), nil)
    -- il comando manuale funziona comunque
    BadbUI.Theme:SetScheme("night")
    elv():ApplyElvStyle(true)
    eq(BadbUI.Theme.state.scheme, "elvui")
end

T["il comando elv esiste nel router"] = function()
    truthy(elv().commands.elv, "comando mancante")
end

return T
