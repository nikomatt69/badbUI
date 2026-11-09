-- Test delle barre esperienza e reputazione (Modules/DataBars.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}
local function D() return BadbUI.DataBars end

local function stub(o)
    o = o or {}
    -- il mock generico non registra valori: li registriamo qui
    local M = _G.__Mock.Methods
    function M:SetValue(v) self.__value = v end
    function M:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
    function M:SetStatusBarColor(r, g, b, a) self.__sbc = { r, g, b, a } end
    function M:SetSize(w, h) self.__width, self.__height = w, h end
    function M:GetHeight() return self.__height end
    function M:SetPoint(...) self.__points = self.__points or {}; table.insert(self.__points, { ... }) end
    function M:ClearAllPoints() self.__points = {} end
    UnitLevel = function() return o.level or 30 end
    GetMaxPlayerLevel = function() return o.cap or 60 end
    UnitXP = function() return o.xp or 1500 end
    UnitXPMax = function() return o.xpmax or 6000 end
    GetXPExhaustion = function() return o.rested end
    C_Reputation = o.noModernRep and nil or { GetWatchedFactionData = function() return o.rep end }
    GetWatchedFactionInfo = o.classicRep
    D().active = true
    D().bars = nil
end

T["registrato e attivo di default"] = function(Mock)
    _G.__Mock = Mock
    truthy(D() and D().enabled)
end

T["XPInfo: valori, riposo, livello massimo, API assente, valori assurdi"] = function(Mock)
    _G.__Mock = Mock
    stub({ rested = 800 })
    local x = D().XPInfo()
    eq(x.cur, 1500); eq(x.max, 6000); eq(x.rested, 800); eq(x.level, 30)
    stub({ level = 60 }); eq(D().XPInfo(), nil, "al livello massimo non c'e' barra")
    stub({ xpmax = 0 }); eq(D().XPInfo(), nil, "max 0")
    stub({ rested = -5 }); eq(D().XPInfo().rested, 0, "riposo negativo")
    UnitXP = nil; eq(D().XPInfo(), nil, "senza API")
end

T["RepInfo: API moderna (tabella)"] = function(Mock)
    _G.__Mock = Mock
    stub({ rep = { name = "Stormwind", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4200 } })
    local r = D().RepInfo()
    eq(r.name, "Stormwind"); eq(r.cur, 1200); eq(r.max, 6000); eq(r.reaction, 5)
end

T["RepInfo: API classica, esaltato, nessuna fazione, dati incompleti"] = function(Mock)
    _G.__Mock = Mock
    stub({ noModernRep = true, classicRep = function() return "Darnassus", 6, 0, 12000, 7000 end })
    local r = D().RepInfo(); eq(r.name, "Darnassus"); eq(r.cur, 7000); eq(r.max, 12000)
    stub({ rep = { name = "Alleanza", reaction = 8, currentReactionThreshold = 42000, nextReactionThreshold = 42000, currentStanding = 42000 } })
    r = D().RepInfo(); eq(r.cur, r.max, "esaltato: barra piena")
    stub({ rep = nil }); eq(D().RepInfo(), nil, "nessuna fazione")
    stub({ rep = { name = "", reaction = 4 } }); eq(D().RepInfo(), nil)
    stub({ rep = { name = "X", reaction = 4 } }); eq(D().RepInfo(), nil, "soglie mancanti")
end

T["Update: barra XP con valore, colore ElvUI, riposo e testo"] = function(Mock)
    _G.__Mock = Mock
    stub({ rested = 800 })
    D():Update()
    local xp = D().bars.xp
    eq(xp.__value, 1500); eq(xp.__max, 6000)
    eq(xp.__sbc[1], 0); eq(xp.__sbc[2], 0.4); eq(xp.__sbc[3], 1)
    eq(xp.rested.__value, 2300, "riposo sommato all'XP")
    truthy(xp:IsShown() and xp.rested:IsShown())
    truthy(xp.text:GetText():find("1,500 / 6,000", 1, true), "testo valore")
    truthy(xp.text:GetText():find("25%%"), "percentuale")
    truthy(xp.text:GetText():find("riposo 800", 1, true))
end

T["Update: al livello massimo l'XP e' nascosta e la reputazione scende"] = function(Mock)
    _G.__Mock = Mock
    stub({ level = 60, rep = { name = "F", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 100, currentStanding = 50 } })
    D():Update()
    eq(D().bars.xp:IsShown(), false)
    truthy(D().bars.rep:IsShown())
    eq(D().bars.rep.__points[#D().bars.rep.__points][5], 6, "reputazione in basso se manca l'XP")
end

T["Update: opzioni disattivate, modalita' testo, valori corrotti"] = function(Mock)
    _G.__Mock = Mock
    stub({ rep = { name = "F", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 100, currentStanding = 50 } })
    D():Set("xp", false); D():Set("rep", false); D():Update()
    eq(D().bars.xp:IsShown(), false); eq(D().bars.rep:IsShown(), false)
    D():Set("xp", true); D():Set("textMode", "none"); D():Update()
    eq(D().bars.xp.text:GetText(), "")
    D():Set("textMode", "percent"); D():Update()
    eq(D().bars.xp.text:GetText(), "25%")
    D():Set("width", 0 / 0); D():Set("height", "x"); D():Set("fontSize", 9999); D():Update()
    eq(D().bars.xp.__width, 360, "NaN: larghezza di default")
    truthy(D().bars.xp.text.__font[2] <= 16, "font oltre il limite")
end

T["FormatText"] = function()
    eq(D().FormatText("both", 50, 200), "50 / 200  (25%)")
    eq(D().FormatText("value", 1234567, 2000000), "1,234,567 / 2,000,000")
    eq(D().FormatText("percent", 0, 0), "0%", "max zero non divide")
end

T["barra Blizzard: nascosta con alpha e ripristinata al disable"] = function(Mock)
    _G.__Mock = Mock
    stub()
    StatusTrackingBarManager = Mock.NewObject("Frame"); StatusTrackingBarManager:SetAlpha(0.9)
    D():HideBlizzard(true); eq(StatusTrackingBarManager:GetAlpha(), 0)
    D():HideBlizzard(true); D():HideBlizzard(false)
    eq(StatusTrackingBarManager:GetAlpha(), 0.9, "alpha originale non ripristinato")
    D().bars = nil; D():Update()
    BadbUI.Modules:SetEnabled("DataBars", false)
    eq(D().bars.xp:IsShown(), false)
    eq(D().active, false)
end

T["posizione scelta dall'utente per la reputazione non viene sovrascritta"] = function(Mock)
    _G.__Mock = Mock
    stub({ rep = { name = "F", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 100, currentStanding = 50 } })
    D():Update()
    local last = D().bars.rep.__points[#D().bars.rep.__points]
    BadbUI.DB.profile.frames.ElvRepBar = { point = "CENTER", x = 10, y = 10 }
    D().bars.xp:Hide(); D():PlaceRep()
    eq(D().bars.rep.__points[#D().bars.rep.__points], last, "riposizionata nonostante la scelta dell'utente")
end

T["frame registrati nel FrameManager e nessun frame doppio alla riattivazione"] = function(Mock)
    _G.__Mock = Mock
    stub()
    D():Update()
    truthy(BadbUI.FrameManager.registry.ElvXPBar and BadbUI.FrameManager.registry.ElvRepBar)
    local xp = D().bars.xp
    BadbUI.Modules:SetEnabled("DataBars", false); BadbUI.Modules:SetEnabled("DataBars", true)
    eq(D().bars.xp, xp)
end

return T
