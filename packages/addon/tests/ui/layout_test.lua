-- Finestre, tab, navigazione, stack, galleria.
local S = {}

S["Window: struttura, ESC, chiusura"] = function(boot)
    local T = boot()
    local closed = 0
    local w = T.UI:Window("BadbUITestWin", 600, 400, "Titolo", { subtitle = "sotto", sidebar = true, footer = true, onClose = function() closed = closed + 1 end })
    T.ok(w.header and w.title and w.body and w.footer and w.sidebar and w.close and w.subtitle, "parti mancanti")
    T.eq(w.title:GetText(), "Titolo")
    T.ok(tContains(UISpecialFrames, "BadbUITestWin"), "ESC non registrato")
    T.ok(not w:IsShown(), "deve nascere nascosta")
    w:Show(); T.ok(w:IsShown())
    T.Mock.click(w.close)
    T.ok(not w:IsShown()); T.eq(closed, 1)
    w:Toggle(); T.ok(w:IsShown()); w:Toggle(); T.ok(not w:IsShown())
    w:SetTitle("Nuovo", "sub2"); T.eq(w.title:GetText(), "Nuovo"); T.eq(w.subtitle:GetText(), "sub2")
    -- senza nome globale: niente ESC ma funziona
    local anon = T.UI:Window(nil, 300, 200, "Anonima", { noClose = true })
    T.ok(anon.close == nil); anon:Show(); T.ok(anon:IsShown())
end

S["Window: posizione ricordata, dati corrotti ignorati, reset"] = function(boot)
    local T = boot()
    local w = T.UI:Window("BadbUIPosWin", 500, 300, "P", { resizable = true })
    w:Show()
    w:ClearAllPoints(); w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -50); w:SetSize(640, 480)
    T.Mock.script(w.header, "OnDragStop")
    local saved = BadbUIDB.global.windows.BadbUIPosWin
    T.eq(saved.point, "TOPLEFT"); T.eq(saved.x, 100); T.eq(saved.w, 640)

    local T2 = boot({ db = BadbUIDB })
    local w2 = T2.UI:Window("BadbUIPosWin", 500, 300, "P", { resizable = true })
    w2:Show()
    local p, _, _, x, y = w2:GetPoint(1)
    T2.eq(p, "TOPLEFT"); T2.eq(x, 100); T2.eq(y, -50); T2.eq(w2:GetWidth(), 640)

    local T3 = boot({ db = { global = { windows = { BadbUIPosWin = { point = nil, x = "a" } } } } })
    local w3 = T3.UI:Window("BadbUIPosWin", 500, 300, "P")
    w3:Show()
    T3.eq((w3:GetPoint(1)), "CENTER", "posizione corrotta non ignorata")
    w3:ResetPosition(); T3.eq((w3:GetPoint(1)), "CENTER")
    T3.eq(BadbUIDB.global.windows.BadbUIPosWin, nil)
end

S["Window: chiudere la finestra chiude i dropdown aperti"] = function(boot)
    local T = boot()
    local w = T.UI:Window("BadbUIDDWin", 500, 300, "D")
    local d = T.UI:Dropdown(w.body, "x", { "a", "b" }, function() return "a" end, function() end)
    w:Show(); T.Mock.click(d.button)
    T.ok(BadbUIDropdownMenu:IsShown())
    w:Hide()
    T.ok(not BadbUIDropdownMenu:IsShown(), "menu rimasto aperto")
end

S["Tabs: selezione, callback, cambio elenco"] = function(boot)
    local T = boot()
    local got = {}
    local tabs = T.UI:Tabs(UIParent, { { id = "a", text = "A" }, { id = "b", text = "B", badge = "3" } }, function(id, user) got[#got + 1] = { id, user } end)
    T.eq(tabs:GetSelected(), "a"); T.eq(got[1][1], "a"); T.ok(not got[1][2], "selezione iniziale marcata come utente")
    T.Mock.click(tabs.buttons[2])
    T.eq(tabs:GetSelected(), "b"); T.eq(got[2][2], true)
    T.ok(tabs.buttons[2].under:IsShown() and not tabs.buttons[1].under:IsShown())
    tabs:SetTabs({ { id = "z", text = "Z" } })
    T.ok(not tabs.buttons[2]:IsShown(), "tab vecchio ancora visibile")
    local empty = T.UI:Tabs(UIParent, {}, nil)
    T.eq(empty:GetSelected(), nil)
end

S["NavList: intestazioni non cliccabili, id ignoti ignorati, badge"] = function(boot)
    local T = boot()
    local sel
    local nav = T.UI:NavList(UIParent, {
        { id = "h", text = "Sezione", header = true },
        { id = "one", text = "Uno" },
        { id = "two", text = "Due", badge = "!" },
    }, function(id) sel = id end)
    T.ok(not nav.buttons[1]:IsMouseEnabled(), "intestazione cliccabile")
    T.eq(nav.buttons[1].text:GetText(), "SEZIONE")
    T.Mock.click(nav.buttons[2]); T.eq(sel, "one")
    nav:Select("h"); T.eq(sel, "one", "intestazione selezionabile")
    nav:Select("nonEsiste"); T.eq(nav:GetSelected(), "one")
    nav:SetBadge("two", "5"); T.eq(nav.buttons[3].badge:GetText(), "5")
    nav:SetBadge("nonEsiste", "x") -- nessun errore
    T.ok(nav.buttons[2].mark:IsShown())
end

S["Stack: impila e aggiorna l'altezza del contenitore"] = function(boot)
    local T = boot()
    local page = CreateFrame("Frame", nil, UIParent)
    local st = T.UI:Stack(page, { gap = 10, padding = 16 })
    local a = CreateFrame("Frame", nil, page); a:SetHeight(30)
    local b = CreateFrame("Frame", nil, page); b:SetHeight(20)
    st:Add(a); st:Add(b)
    local _, _, _, _, y = b:GetPoint(1)
    T.eq(y, -(16 + 30 + 10))
    T.eq(page:GetHeight(), 16 + 30 + 10 + 20 + 10 + 16)
    local refreshed = 0
    a.Refresh = function() refreshed = refreshed + 1 end
    b.Refresh = function() error("rotto") end
    st:Refresh(); T.eq(refreshed, 1, "Refresh di un widget rotto blocca gli altri")
end

S["Galleria: si costruisce, cambia pagina, comando slash"] = function(boot)
    local T = boot()
    SlashCmdList.BADBUI("gallery")
    local w = _G.BadbUIGallery
    T.ok(w and w:IsShown(), "galleria non aperta")
    w.tabs:Select("theme")
    w.tabs:Select("list")
    w.nav:Select("controls", true)
    T.eq(w.tabs:GetSelected(), "controls")
    T.Theme:SetScheme("graphite") -- ridipinge tutto senza errori
    SlashCmdList.BADBUI("gallery")
    T.ok(not w:IsShown())
end

S["Window segue il tema (sfondo, header, bordo)"] = function(boot)
    local T = boot()
    local w = T.UI:Window("BadbUIThemeWin", 400, 300, "T")
    T.sameColor(w.badbSkin.bg, "bg")
    T.Theme:SetScheme("dusk")
    T.sameColor(w.badbSkin.bg, "bg")
    T.ok(w.header.sky._gradient, "header senza gradiente")
end

return S
