-- Test del modulo Tooltip (Modules/Tooltip.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}
local function TT() return BadbUI.Tooltip end

local function tooltip(Mock, name, over)
    Mock.Methods.GetObjectType = function(self) return self.__kind end -- serve a Theme:Paint
    local t = Mock.NewObject("Frame")
    t.__name = name
    t.NineSlice = Mock.NewObject("Frame")
    t.NineSlice:SetAlpha(0.9)
    over = over or {}
    t.GetUnit = function() return "Nome", over.unit end
    t.GetItem = function() return "Spada", over.link end
    _G[name] = t
    return t
end

local function borderColor(tt)
    local e = TT().skinned[tt].bd.badbSkin.top
    return e.__vc
end

T["registrato e attivo di default"] = function()
    truthy(TT() and TT().enabled)
end

T["Skin: sfondo creato una volta, cornice Blizzard nascosta e poi ripristinata"] = function(Mock)
    local tt = tooltip(Mock, "GameTooltip")
    TT():StyleAll()
    local rec = TT().skinned[tt]
    truthy(rec and rec.bd, "sfondo non creato")
    eq(tt.NineSlice:GetAlpha(), 0)
    TT():StyleAll()
    eq(TT().skinned[tt], rec, "sfondo ricreato")
    BadbUI.Modules:SetEnabled("Tooltip", false)
    eq(tt.NineSlice:GetAlpha(), 0.9, "alpha originale non ripristinato")
    eq(rec.bd:IsShown(), false)
end

T["giocatore: bordo del colore della classe"] = function(Mock)
    local tt = tooltip(Mock, "GameTooltip", { unit = "mouseover" })
    RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
    UnitIsPlayer = function() return true end
    UnitClass = function() return "Mago", "MAGE" end
    TT():StyleAll(); TT():Style(tt)
    eq(borderColor(tt)[1], 0.41); eq(borderColor(tt)[3], 0.94)
end

T["giocatore: dati secret, nessun colore e nessun errore"] = function(Mock)
    local tt = tooltip(Mock, "GameTooltip", { unit = "mouseover" })
    UnitIsPlayer = function() return Mock.Secret() end
    TT():StyleAll()
    truthy(pcall(TT().Style, TT(), tt), "errore con valori secret")
    eq(borderColor(tt)[1], 0, "bordo colorato con dati opachi")
    UnitIsPlayer = function() return true end
    UnitClass = function() return Mock.Secret(), Mock.Secret() end
    truthy(pcall(TT().Style, TT(), tt))
    eq(borderColor(tt)[1], 0)
end

T["PNG non giocatore: bordo predefinito (nero)"] = function(Mock)
    local tt = tooltip(Mock, "GameTooltip", { unit = "target" })
    UnitIsPlayer = function() return false end
    TT():StyleAll(); TT():Style(tt)
    eq(borderColor(tt)[1], 0)
end

T["oggetto: bordo per qualita' da 'non comune' in su, grigio e bianco restano neri"] = function(Mock)
    local tt = tooltip(Mock, "ItemRefTooltip", { link = "|cffa335ee|Hitem:1|h[Spada]|h|r" })
    ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [4] = { r = 0.64, g = 0.21, b = 0.93 } }
    local quality = 4
    GetItemInfo = function() return "Spada", "link", quality end
    TT():StyleAll(); TT():Style(tt)
    eq(borderColor(tt)[1], 0.64)
    quality = 1; TT():Style(tt)
    eq(borderColor(tt)[1], 0, "bianco colorato")
    quality = "x"; truthy(pcall(TT().Style, TT(), tt))
end

T["opzioni: bordi disattivabili, opacita' ripulita"] = function(Mock)
    local tt = tooltip(Mock, "GameTooltip", { unit = "mouseover" })
    RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
    UnitIsPlayer = function() return true end
    UnitClass = function() return "Mago", "MAGE" end
    TT():Set("classBorder", false); TT():StyleAll(); TT():Style(tt)
    eq(borderColor(tt)[1], 0, "bordo di classe con opzione spenta")
    TT():Set("bgAlpha", 0 / 0)
    truthy(pcall(TT().StyleAll, TT()), "NaN sull'opacita'")
end

T["OnTooltipCleared riporta il bordo predefinito"] = function(Mock)
    local tt = tooltip(Mock, "GameTooltip", { unit = "mouseover" })
    RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
    UnitIsPlayer = function() return true end
    UnitClass = function() return "Mago", "MAGE" end
    TT():StyleAll(); TT():Style(tt)
    eq(borderColor(tt)[1], 0.41)
    tt.__scripts.OnTooltipCleared(tt)
    eq(borderColor(tt)[1], 0)
end

T["tooltip assenti o senza NineSlice: nessun errore"] = function(Mock)
    _G.GameTooltip = nil
    local bare = Mock.NewObject("Frame"); _G.ItemRefTooltip = bare
    truthy(pcall(TT().StyleAll, TT()))
    truthy(TT().skinned[bare])
end

return T
