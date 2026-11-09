-- Test del modulo Guides: validazione, sanificazione, ricerca, persistenza, suggerimento per zona,
-- visualizzatore (con il mock), contenuto bundled, comandi, pagina e disattivazione.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso un valore vero", 2) end end
local function falsy(v, msg) if v then error((msg or "atteso un valore falso") .. ": " .. tostring(v), 2) end end

local T = {}

local function G() return BadbUI.Guides end

local function entry(id, title, extra)
    local e = { id = id, title = title, body = { { type = "p", text = "testo di " .. id } } }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

local function pack(id, entries, extra)
    local p = { id = id, title = "Pack " .. id, category = "Cat-" .. id, version = 1, entries = entries }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

local function warnCount()
    local n = 0
    for _, line in ipairs(BadbUI.Logger.buffer) do
        if line:find("WARN", 1, true) then n = n + 1 end
    end
    return n
end

local function bufferHas(text)
    for _, line in ipairs(BadbUI.Logger.buffer) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function ids(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s.id end
    return table.concat(out, ",")
end

---------------------------------------------------------------------------
-- Validazione
---------------------------------------------------------------------------

T["API del contratto presente e Badb.Guides esiste al caricamento"] = function()
    local g = G()
    for _, name in ipairs({ "Register", "Search", "Open", "Bookmark", "GetProgress", "SetProgress", "Get",
        "ListPacks", "ListCategories", "GetBookmarks" }) do
        eq(type(g[name]), "function", name)
    end
end

T["pack valido: id globali, copie indipendenti, riepiloghi"] = function()
    local id, info = G():Register(pack("p1", { entry("e1", "Prima"), entry("e2", "Seconda", { tags = { "x" }, zone = "Zona", level = 20 }) }))
    eq(id, "p1")
    eq(info.entries, 2)
    eq(info.skipped, 0)
    local e = assert(G():Get("p1:e2"))
    eq(e.id, "p1:e2")
    eq(e.entryId, "e2")
    eq(e.zone, "Zona")
    eq(e.level, 20)
    eq(e.confidence, "A", "confidence di default")
    e.body[1].text = "manomesso"
    eq(G():Get("p1:e2").body[1].text, "testo di e2", "Get restituisce una copia")
    local nilEntry, err = G():Get("p1:nope")
    eq(nilEntry, nil)
    truthy(err)
    eq(G():Get(123), nil)
    local found = false
    for _, p in ipairs(G():ListPacks()) do if p.id == "p1" and p.count == 2 then found = true end end
    truthy(found, "ListPacks")
end

T["pack e entry invalidi: nil, err e Logger:Warn, mai errori Lua"] = function()
    local g = G()
    local bad = {
        nil, "stringa", 42, {}, { id = "a:b", title = "t", entries = {} },
        { id = "ok", title = "t" },                               -- manca entries
        { id = "ok", title = "t", entries = "no" },
        { id = "ok", title = 5, entries = {} },
        { id = "ok", title = "t", entries = { entry("e", "E") }, version = {} },
        { id = "ok", title = "t", entries = { entry("e", "E") }, category = 7 },
        { id = "ok", title = "t", entries = {} },                 -- nessuna entry valida
        { id = "ok", title = "t", entries = { 1, "x", {} } },     -- tutte invalide
        { id = string.rep("x", 70), title = "t", entries = { entry("e", "E") } },
        { id = "bad id", title = "t", entries = { entry("e", "E") } },
    }
    local before = warnCount()
    local n = 0
    for i = 1, 14 do
        n = n + 1
        local ok, a, b = pcall(g.Register, g, bad[i])
        truthy(ok, "errore Lua alla registrazione #" .. i)
        eq(a, nil, "pack #" .. i .. " doveva essere rifiutato")
        eq(type(b), "string", "messaggio di errore #" .. i)
    end
    truthy(warnCount() >= before + n, "warning nel Logger")
    eq(#g:ListPacks() >= 0, true)
    -- tabella con metatable ostile
    local hostile = setmetatable({}, { __index = function() error("boom") end })
    local ok2, a2 = pcall(g.Register, g, hostile)
    truthy(ok2)
    eq(a2, nil)
end

T["entry invalide vengono saltate, le altre restano"] = function()
    local g = G()
    local before = warnCount()
    local id, info = g:Register(pack("p2", {
        entry("ok1", "Buona"),
        { id = "video", title = "Blocco ignoto", body = { { type = "video", text = "x" } } },
        { id = "ok1", title = "Duplicata", body = {} },
        { id = "nobody", title = "Senza corpo" },
        { id = "notitle", body = {} },
        { id = "badtag", title = "T", tags = "x", body = {} },
        { id = "badconf", title = "C", confidence = "Z", body = {} },
        { id = "badlevel", title = "L", level = "alto", body = {} },
        entry("ok2", "Anche questa"),
    }))
    eq(id, "p2")
    eq(info.entries, 2)
    eq(info.skipped, 7)
    truthy(g:Get("p2:ok1")); truthy(g:Get("p2:ok2"))
    eq(g:Get("p2:video"), nil)
    truthy(bufferHas("tipo sconosciuto 'video'"), "warning sul tipo di blocco")
    truthy(bufferHas("id duplicato"), "warning sul duplicato")
    truthy(warnCount() > before)
    eq(g:Get("p2:ok1").title, "Buona", "la prima entry con quell'id resta")
end

T["blocchi: tutti i tipi validi, step numerati, errori nei campi"] = function()
    local g = G()
    local id = g:Register(pack("blk", { {
        id = "tutti", title = "Tutti i blocchi",
        body = {
            { type = "h", text = "Titolo" }, { type = "p", text = "Testo" },
            { type = "list", items = { "uno", "due" } },
            { type = "step", text = "primo" }, { type = "tip", text = "consiglio" },
            { type = "step", text = "secondo" }, { type = "warn", text = "attenzione" },
        },
    } }))
    eq(id, "blk")
    local e = g:Get("blk:tutti")
    eq(#e.body, 7)
    eq(e.steps, 2)
    eq(e.body[4].index, 1)
    eq(e.body[6].index, 2)
    -- campi sbagliati
    local bads = {
        { type = "p" }, { type = "p", text = 5 }, { type = "p", text = "   " }, { type = "list" },
        { type = "list", items = {} }, { type = "list", items = { 1 } }, "stringa", { type = 3 },
    }
    for i, b in ipairs(bads) do
        local pid, info = g:Register(pack("blk" .. i, { entry("buona", "Buona"), { id = "x", title = "X", body = { b } } }))
        eq(pid, "blk" .. i)
        eq(info.skipped, 1, "blocco errato #" .. i)
    end
end

T["limiti: 500 entry per pack, 200 blocchi, 4000 caratteri"] = function()
    local g = G()
    local many = {}
    for i = 1, 500 do many[i] = entry("e" .. i, "Entry " .. i) end
    truthy(g:Register(pack("p500", many)), "500 entry sono ammesse")
    many[501] = entry("e501", "Una di troppo")
    local id, err = g:Register(pack("p501", many))
    eq(id, nil)
    truthy(err:find("troppe entry", 1, true), err)
    eq(g:Get("p501:e1"), nil, "nessuna registrazione parziale")

    local function withBlocks(n)
        local body = {}
        for i = 1, n do body[i] = { type = "p", text = "b" .. i } end
        return { id = "x", title = "Blocchi", body = body }
    end
    local _, info200 = g:Register(pack("b200", { withBlocks(200), entry("ok", "ok") }))
    eq(info200.skipped, 0, "200 blocchi ammessi")
    local _, info201 = g:Register(pack("b201", { withBlocks(201), entry("ok", "ok") }))
    eq(info201.skipped, 1, "201 blocchi: entry saltata")

    local function withText(n)
        return { id = "x", title = "Testo", body = { { type = "p", text = string.rep("a", n) } } }
    end
    local _, t4000 = g:Register(pack("t4000", { withText(4000), entry("ok", "ok") }))
    eq(t4000.skipped, 0)
    local _, t4001 = g:Register(pack("t4001", { withText(4001), entry("ok", "ok") }))
    eq(t4001.skipped, 1)
    local longItem = { id = "x", title = "Lista", body = { { type = "list", items = { string.rep("a", 4001) } } } }
    local _, tl = g:Register(pack("tl", { longItem, entry("ok", "ok") }))
    eq(tl.skipped, 1, "limite anche sulle voci di lista")
    local longTitle = { id = "x", title = string.rep("t", 201), body = {} }
    local _, tt = g:Register(pack("tt", { longTitle, entry("ok", "ok") }))
    eq(tt.skipped, 1, "titolo troppo lungo")
end

T["sanificazione: solo colori |c...|r e texture whitelisted"] = function()
    local S = G().Sanitize
    eq(S("|cff00ff00ciao|r"), "|cff00ff00ciao|r", "colore valido")
    eq(S("|Hitem:19019:0:0|h[Spada]|h"), "[Spada]", "hyperlink rimosso, testo mantenuto")
    eq(S("|Hurl:http://evil|hclick|h qui"), "click qui")
    eq(S("|TInterface\\Icons\\INV_Misc_QuestionMark:16|t x"), "|TInterface\\Icons\\INV_Misc_QuestionMark:16|t x", "icona whitelisted")
    eq(S("|T136243:16|t"), "|T136243:16|t", "file ID numerico")
    eq(S("|TInterface\\Malicious\\Foo:16|t x"), " x", "texture non whitelisted")
    eq(S("|TInterface\\Icons\\..\\..\\x:16|t"), "", "path traversal")
    eq(S("|TInterface\\Icons\\A:16:16:0:0|t"), "|TInterface\\Icons\\A:16:16:0:0|t")
    eq(S("|TInterface\\Icons\\A:16;evil|t"), "", "parametri non numerici")
    eq(S("|cxyz"), "xyz", "colore malformato")
    eq(S("|cff112233aperto"), "|cff112233aperto|r", "colore non chiuso viene chiuso")
    eq(S("a|b"), "a||b", "pipe isolata resa letterale")
    eq(S("a||b"), "a||b", "pipe doppia invariata")
    eq(S("fine|"), "fine||")
    eq(S("|r|r"), "", "|r orfani")
    eq(S("|Kfoo|k!"), "!")
    eq(S("|Aatlas:1|a!"), "!")
    eq(S("x|h|t|a|k"), "x", "chiusure orfane")
    eq(S("a\r\nb\0c"), "a\nbc", "caratteri di controllo")
    eq(S(42), "", "non-stringa")
    -- applicato dentro un pack
    G():Register(pack("san", { {
        id = "e", title = "|Hitem:1|hTitolo|h", tags = { "|cffff0000rosso|r" },
        body = { { type = "p", text = "Vedi |Hitem:1|h[Oggetto]|h e |TInterface\\Bad\\X:16|t fine" },
                 { type = "list", items = { "|Hx|hvoce|h" } } },
    } }))
    local e = G():Get("san:e")
    eq(e.title, "Titolo")
    eq(e.tags[1], "|cffff0000rosso|r")
    eq(e.body[1].text, "Vedi [Oggetto] e  fine")
    eq(e.body[2].items[1], "voce")
end

T["link: solo http/https, mai aperti, label sanificata"] = function()
    local g = G()
    local valid = { "https://www.youtube.com/watch?v=abc123", "http://example.com", "https://a.b-c.it:8080/x/y?z=1#top" }
    for _, u in ipairs(valid) do truthy(g.IsValidUrl(u), u) end
    local invalid = { "javascript:alert(1)", "ftp://x.com/a", "https://exa mple.com", "https://", "https://user@evil.com",
        "file:///etc/passwd", "www.example.com", "https://a.com/|cffff0000", "https://a.com/\n", "http://", 5, "",
        "https://" .. string.rep("a", 600) .. ".com" }
    for _, u in ipairs(invalid) do falsy(g.IsValidUrl(u), tostring(u)) end

    local id = g:Register(pack("lnk", { entry("ok", "Con link", {
        links = { { label = "|Hx|hVideo|h", url = "https://youtu.be/xyz" }, { "Posizionale", "http://example.com/a" }, { url = "https://solo.url/" } },
    }) }))
    eq(id, "lnk")
    local e = g:Get("lnk:ok")
    eq(#e.links, 3)
    eq(e.links[1].label, "Video")
    eq(e.links[2].url, "http://example.com/a")
    eq(e.links[3].label, "https://solo.url/", "senza label: l'URL")
    local _, info = g:Register(pack("lnk2", { entry("buona", "Buona"), entry("brutta", "Brutta", {
        links = { { label = "x", url = "javascript:alert(1)" } } }) }))
    eq(info.skipped, 1, "entry con link non consentito saltata")
end

T["confidence: default A, normalizzata, solo A/B/C"] = function()
    local g = G()
    local _, info = g:Register(pack("cf", {
        entry("a", "A"), entry("b", "B", { confidence = "b" }), entry("c", "C", { confidence = "C" }),
        entry("x", "X", { confidence = "Z" }), entry("y", "Y", { confidence = 3 }),
    }))
    eq(info.entries, 3)
    eq(info.skipped, 2)
    eq(g:Get("cf:a").confidence, "A")
    eq(g:Get("cf:b").confidence, "B")
    eq(g:Search("C", { pack = "cf" })[1].confidence, "C", "anche nei riepiloghi")
end

T["ri-registrare un pack lo sostituisce, Unregister lo toglie"] = function()
    local g = G()
    g:Register(pack("rr", { entry("a", "Vecchia") }))
    g:Register(pack("rr", { entry("b", "Nuova") }))
    eq(g:Get("rr:a"), nil)
    truthy(g:Get("rr:b"))
    local count = 0
    for _, p in ipairs(g:ListPacks()) do if p.id == "rr" then count = count + 1 end end
    eq(count, 1)
    truthy(g:Unregister("rr"))
    eq(g:Get("rr:b"), nil)
    eq(g:Unregister("rr"), false)
end

---------------------------------------------------------------------------
-- Ricerca
---------------------------------------------------------------------------

T["ricerca: ranking titolo > tag > corpo, a parita' ordine alfabetico"] = function()
    local g = G()
    g:Register(pack("rk", {
        entry("corpo", "Terzo", { body = { { type = "p", text = "qui si parla di profilo nel testo" } } }),
        entry("tag", "Secondo", { tags = { "profilo" } }),
        entry("titolo", "Configurare il profilo"),
        entry("zona", "Quarto", { zone = "Profilo Valley" }),
    }))
    local res = g:Search("profilo", { pack = "rk" })
    eq(ids(res), "rk:titolo,rk:tag,rk:zona,rk:corpo")
    truthy(res[1].score > res[2].score and res[2].score > res[3].score and res[3].score > res[4].score, "punteggi decrescenti")
    -- tag esatto batte tag parziale
    g:Register(pack("rk2", {
        entry("parziale", "A", { tags = { "profilo-base" } }),
        entry("esatto", "B", { tags = { "profilo" } }),
    }))
    eq(ids(g:Search("profilo", { pack = "rk2" })), "rk2:esatto,rk2:parziale")
    -- inizio parola nel titolo batte posizione interna
    g:Register(pack("rk3", {
        entry("interno", "Autoprofilo"), entry("inizio", "Il profilo"),
    }))
    eq(ids(g:Search("profilo", { pack = "rk3" })), "rk3:inizio,rk3:interno")
    -- parita': ordine alfabetico per titolo
    g:Register(pack("rk4", { entry("z", "Zeta cane"), entry("a", "Alfa cane") }))
    eq(ids(g:Search("cane", { pack = "rk4" })), "rk4:a,rk4:z")
end

T["ricerca: insensibile a maiuscole e accenti"] = function()
    local g = G()
    g.Fold = g.Fold
    eq(g.Fold("ÀÈÌÒÙ àèìòù é É ç ñ"), "aeiou aeiou e e c n")
    eq(g.Fold("Perché l’età"), "perche l'eta")
    g:Register(pack("ac", {
        entry("a", "Perché i cooldown contano"),
        entry("b", "È tutto qui"),
        entry("c", "Altro", { body = { { type = "p", text = "Una città piena di perché" } } }),
        entry("d", "Zona", { zone = "Cittá di Prova" }),
    }))
    eq(ids(g:Search("perche", { pack = "ac" })), "ac:a,ac:c")
    eq(ids(g:Search("PERCHÉ", { pack = "ac" })), "ac:a,ac:c")
    eq(#g:Search("e tutto", { pack = "ac" }), 1, "E maiuscola accentata")
    eq(#g:Search("citta", { pack = "ac" }), 2, "corpo e zona")
    eq(#g:Search("ÈTÀ", { pack = "ac" }), 0)
end

T["ricerca: multi-termine in AND, query degeneri"] = function()
    local g = G()
    g:Register(pack("an", {
        entry("a", "Cooldown dei tank", { tags = { "difensivi" } }),
        entry("b", "Cooldown dei healer"),
        entry("c", "Barre dei tank"),
    }))
    eq(ids(g:Search("cooldown tank", { pack = "an" })), "an:a")
    eq(#g:Search("tank cooldown difensivi", { pack = "an" }), 1)
    eq(#g:Search("cooldown inesistente", { pack = "an" }), 0)
    eq(#g:Search("   ", { pack = "an" }), 3, "query vuota: tutte")
    eq(#g:Search(nil, { pack = "an" }), 3)
    eq(#g:Search(42, { pack = "an" }), 3)
    eq(#g:Search("tank", 5), #g:Search("tank"), "filtro non valido ignorato")
    local ok = pcall(g.Search, g, string.rep("x ", 5000), { pack = "an", level = {} })
    truthy(ok, "query enorme")
    local terms = g.ParseQuery("a b c d e f g h i j k l")
    eq(#terms, g.LIMITS.maxTerms)
end

T["ricerca: filtri category, tag, zone, level, pack, bookmarked"] = function()
    local g = G()
    g:Register(pack("f1", {
        entry("a", "Alfa", { tags = { "Raid", "tank" }, zone = "Tempio", level = 10 }),
        entry("b", "Beta", { tags = { "raid" }, zone = { "Foresta", "Tempio Antico" }, level = { 20, 30 } }),
        entry("c", "Gamma"),
    }))
    g:Register(pack("f2", { entry("d", "Delta", { tags = { "pvp" } }) }))
    eq(ids(g:Search("", { category = "cat-f1" })), "f1:a,f1:b,f1:c", "category (insensibile a maiuscole)")
    eq(ids(g:Search("", { pack = "f2" })), "f2:d")
    eq(ids(g:Search("", { tag = "RAID", pack = "f1" })), "f1:a,f1:b")
    eq(ids(g:Search("", { tag = "#tank", pack = "f1" })), "f1:a")
    eq(ids(g:Search("", { zone = "tempio", pack = "f1" })), "f1:a,f1:b", "zona anche tra piu' zone, sottostringa")
    eq(ids(g:Search("", { zone = "foresta", pack = "f1" })), "f1:b")
    eq(ids(g:Search("", { level = 5, pack = "f1" })), "f1:c", "sotto il livello minimo")
    eq(ids(g:Search("", { level = 15, pack = "f1" })), "f1:a,f1:c", "livello scalare = da n in su")
    eq(ids(g:Search("", { level = 25, pack = "f1" })), "f1:a,f1:b,f1:c")
    eq(ids(g:Search("", { level = 40, pack = "f1" })), "f1:a,f1:c", "oltre l'intervallo")
    eq(ids(g:Search("alfa", { category = "cat-f2" })), "", "filtri combinati con la query")
    g:Bookmark("f1:b", true)
    eq(ids(g:Search("", { bookmarked = true, pack = "f1" })), "f1:b")
    eq(ids(g:Search("beta", { bookmarked = true })), "f1:b")
    eq(#g:Search("alfa", { bookmarked = true }), 0)
end

T["ricerca: limite di 50 risultati; ListEntries/ListCategories"] = function()
    local g = G()
    local many = {}
    for i = 1, 120 do many[i] = entry("e" .. i, "Guida numero " .. i) end
    g:Register(pack("big", many))
    eq(#g:Search("guida", { pack = "big" }), 50)
    eq(#g:Search("", { pack = "big" }), 50)
    eq(#g:ListEntries({ pack = "big" }), 120, "ListEntries non ha il limite di 50")
    local cat
    for _, c in ipairs(g:ListCategories()) do if c.name == "Cat-big" then cat = c end end
    eq(cat and cat.count, 120)
end

---------------------------------------------------------------------------
-- Segnalibri e progresso
---------------------------------------------------------------------------

T["segnalibri: toggle, persistenza nel DB globale, ordine"] = function()
    local g = G()
    g:Register(pack("bm", { entry("b", "Bravo"), entry("a", "Alfa") }))
    local ok, state = g:Bookmark("bm:b", true)
    eq(ok, true); eq(state, true)
    eq(BadbUIDB.global.guides.bookmarks["bm:b"], true, "salvato in BadbUIDB.global.guides")
    truthy(g:IsBookmarked("bm:b"))
    g:Bookmark("bm:a")
    eq(ids(g:GetBookmarks()), "bm:a,bm:b", "ordinati per titolo")
    eq(select(2, g:Bookmark("bm:a")), false, "toggle")
    eq(BadbUIDB.global.guides.bookmarks["bm:a"], nil)
    local r, err = g:Bookmark("bm:nope", true)
    eq(r, nil); truthy(err)
    eq(g:Bookmark(nil, true), nil)
    -- "ricaricamento" del pack: il segnalibro resta
    g:Register(pack("bm", { entry("b", "Bravo"), entry("a", "Alfa") }))
    truthy(g:IsBookmarked("bm:b"))
    -- non dipende dal profilo
    BadbUI.DB:SetProfile("Altro")
    truthy(g:IsBookmarked("bm:b"), "per account, non per profilo")
end

T["progresso: step, clamp, persistenza, pulizia"] = function()
    local g = G()
    g:Register(pack("pr", {
        { id = "s", title = "Con step", body = {
            { type = "step", text = "uno" }, { type = "step", text = "due" }, { type = "step", text = "tre" } } },
        entry("nostep", "Senza step"),
    }))
    local c, total = g:GetProgress("pr:s")
    eq(c, 0); eq(total, 3)
    eq(select(2, g:SetProgress("pr:s", 2)), 2)
    c, total = g:GetProgress("pr:s")
    eq(c, 2); eq(total, 3)
    local d = BadbUIDB.global.guides.progress["pr:s"].done
    eq(d[1], true); eq(d[2], true); eq(d[3], nil)
    eq(select(2, g:SetProgress("pr:s", 99)), 3, "clamp al totale")
    eq(select(2, g:SetProgress("pr:s", 1.9)), 1, "intero")
    eq(select(2, g:SetProgress("pr:s", -5)), 0, "clamp a zero")
    eq(BadbUIDB.global.guides.progress["pr:s"], nil, "zero step: nessuna voce salvata")
    eq(g:SetProgress("pr:s", "abc"), nil)
    eq(g:SetProgress("pr:nope", 1), nil)
    eq(g:SetProgress("pr:nostep", 5) and select(2, g:SetProgress("pr:nostep", 5)), 0)
    eq(g:GetProgress("pr:nope"), nil)
    -- singoli step
    eq(select(2, g:SetStep("pr:s", 2, true)), 1)
    eq(select(2, g:SetStep("pr:s", 3)), 2, "toggle")
    eq(g:GetStepsDone("pr:s")[2], true)
    eq(g:SetStep("pr:s", 4, true), nil, "step inesistente")
    eq(g:SetStep("pr:s", 0, true), nil)
    eq(g:SetStep("pr:s", 1.5, true), nil)
    g:SetStep("pr:s", 2, false); g:SetStep("pr:s", 3, false)
    eq(BadbUIDB.global.guides.progress["pr:s"], nil)
end

T["dati salvati corrotti: tollerati e riparati"] = function()
    local g = G()
    g:Register(pack("cr", {
        { id = "s", title = "Con step", body = { { type = "step", text = "uno" }, { type = "step", text = "due" } } },
    }))
    local garbage = { "testo", 5, true, { 1, 2 } }
    for _, bad in ipairs(garbage) do
        BadbUIDB.global.guides = bad
        local ok = pcall(function()
            g:GetBookmarks(); g:GetProgress("cr:s"); g:GetRecent(); g:GetLastOpened(); g:Cleanup()
        end)
        truthy(ok, "guides = " .. tostring(bad))
        truthy(g:Bookmark("cr:s", true))
        eq(type(BadbUIDB.global.guides), "table", "struttura ricostruita")
        eq(BadbUIDB.global.guides.bookmarks["cr:s"], true)
    end
    BadbUIDB.global.guides = { bookmarks = "x", progress = 5, lastOpened = 12, recent = "no" }
    eq(#g:GetBookmarks(), 0)
    eq(select(1, g:GetProgress("cr:s")), 0)
    eq(g:GetLastOpened(), nil)
    -- voci con valori sbagliati
    BadbUIDB.global.guides = {
        bookmarks = { ["cr:s"] = 1, [5] = true, ["nope:x"] = true, ["cr:s2"] = true },
        progress = { ["cr:s"] = { done = { [1] = true, [99] = true, [0] = true, x = true, [2] = "si" } },
            ["nope:x"] = { done = { [1] = true } }, ["cr:bad"] = "stringa" },
        lastOpened = "nope:x", recent = { "nope:x", 7, "cr:s" },
    }
    eq(#g:GetBookmarks(), 0, "valore non booleano ignorato")
    eq(g:GetProgress("cr:s"), 1, "solo gli indici validi contano")
    local removed = g:Cleanup()
    truthy(removed >= 6, "rimossi " .. removed)
    local s = BadbUIDB.global.guides
    eq(next(s.bookmarks), nil)
    eq(s.progress["nope:x"], nil)
    eq(s.progress["cr:bad"], nil)
    eq(s.progress["cr:s"].done[1], true)
    eq(s.progress["cr:s"].done[99], nil)
    eq(s.lastOpened, nil)
    eq(#s.recent, 1)
    eq(s.recent[1], "cr:s")
end

T["pulizia: riferimenti a guide non piu' esistenti"] = function()
    local g = G()
    g:Register(pack("cl", { entry("a", "A", { body = { { type = "step", text = "x" } } }), entry("b", "B") }))
    g:Bookmark("cl:a", true); g:Bookmark("cl:b", true); g:SetProgress("cl:a", 1)
    g:Register(pack("cl", { entry("b", "B") })) -- l'entry "a" non esiste piu'
    local before = BadbUIDB.global.guides
    truthy(before.bookmarks["cl:a"])
    truthy(g:Cleanup() >= 2)
    eq(before.bookmarks["cl:a"], nil)
    eq(before.progress["cl:a"], nil)
    eq(before.bookmarks["cl:b"], true, "le altre restano")
    eq(g:Cleanup(), 0, "idempotente")
    -- anche all'abilitazione del modulo
    g:Bookmark("cl:b", true)
    g:Unregister("cl")
    BadbUI.Modules:SetEnabled("Guides", false)
    BadbUI.Modules:SetEnabled("Guides", true)
    eq(BadbUIDB.global.guides.bookmarks["cl:b"], nil, "OnEnable ripulisce")
end

---------------------------------------------------------------------------
-- Suggerimento contestuale
---------------------------------------------------------------------------

local function setupZone(name)
    local toasts = {}
    BadbUI.ConfigUI = BadbUI.ConfigUI or {}
    BadbUI.ConfigUI.Toast = function(_, text, level) toasts[#toasts + 1] = { text = text, level = level } end
    _G.GetRealZoneText = function() return name.value end
    return toasts
end

T["auto-suggest: un solo avviso per zona, mai finestre"] = function(Mock)
    local g = G()
    g:Register(pack("zn", {
        entry("a", "Guida al Tempio", { zone = "Tempio d'Ombra" }),
        entry("b", "Seconda guida", { zone = { "Altrove", "TEMPIO D'OMBRA" } }),
        entry("c", "Nessuna zona"),
    }))
    local zone = { value = "Tempio d'Ombra" }
    local toasts = setupZone(zone)
    eq(g.Viewer.frame, nil)
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#toasts, 1, "avviso al primo ingresso")
    truthy(toasts[1].text:find("Guida al Tempio", 1, true), toasts[1].text)
    truthy(toasts[1].text:find("altre 1", 1, true), "indica le altre guide")
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#toasts, 1, "non si ripete per la stessa zona")
    zone.value = "Zona Senza Guide"
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#toasts, 1, "zona senza guide: niente")
    zone.value = "TEMPIO D'OMBRA"
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#toasts, 1, "stessa zona con maiuscole diverse: ancora niente")
    eq(g.Viewer.frame, nil, "non apre mai finestre da solo")
    g:ResetSuggestions()
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#toasts, 2, "nuova sessione: nuovo avviso")
end

T["auto-suggest: non in combattimento, poi all'uscita"] = function(Mock)
    local g = G()
    g:Register(pack("zc", { entry("a", "Guida", { zone = "Zona Combat" }) }))
    local toasts = setupZone({ value = "Zona Combat" })
    Mock.combat = true
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#toasts, 0, "in combattimento nessun avviso")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(#toasts, 1, "all'uscita dal combattimento")
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(#toasts, 1)
end

T["auto-suggest: opzione, instance info, API assenti o secret, fallback sul Logger"] = function(Mock)
    local g = G()
    g:Register(pack("zo", { entry("a", "Guida", { zone = "Zona Opt" }) }))
    local mod = BadbUI.Modules:Get("Guides")
    local toasts = setupZone({ value = "Zona Opt" })
    mod:Set("autoSuggest", false)
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#toasts, 0, "autoSuggest spento")
    mod:Set("autoSuggest", true)
    -- nome di zona dato solo da GetInstanceInfo
    _G.GetRealZoneText = nil
    _G.GetInstanceInfo = function() return "Zona Opt" end
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#toasts, 1, "GetInstanceInfo")
    -- API che lancia errori, valori nil/secret/numeri
    g:ResetSuggestions()
    _G.GetInstanceInfo = function() error("api rotta") end
    _G.GetRealZoneText = function() return Mock.Secret() end
    Mock.Fire("PLAYER_ENTERING_WORLD")
    _G.GetRealZoneText = function() return 12 end
    Mock.Fire("PLAYER_ENTERING_WORLD")
    _G.GetRealZoneText = function() return nil end
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#toasts, 1, "nessun errore e nessun avviso")
    -- senza Toast: Logger:Info
    BadbUI.ConfigUI.Toast = nil
    g:ResetSuggestions()
    _G.GetRealZoneText = function() return "Zona Opt" end
    local before = #Mock.chat
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#Mock.chat, before + 1, "fallback sul Logger")
    truthy(Mock.chat[#Mock.chat]:find("Guide disponibili per Zona Opt", 1, true))
    -- Toast che lancia errore: si ripiega sul Logger
    BadbUI.ConfigUI.Toast = function() error("toast rotto") end
    g:ResetSuggestions()
    before = #Mock.chat
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#Mock.chat, before + 1)
    _G.GetRealZoneText, _G.GetInstanceInfo = nil, nil
end

---------------------------------------------------------------------------
-- Contenuto bundled
---------------------------------------------------------------------------

T["pack bundled: validi, senza warning, almeno 8 entry vere"] = function()
    local g = G()
    local starter
    for _, p in ipairs(g:ListPacks()) do if p.id == "starter" then starter = p end end
    truthy(starter, "pack starter registrato")
    truthy(starter.count >= 8, "almeno 8 entry, trovate " .. starter.count)
    for _, line in ipairs(BadbUI.Logger.buffer) do
        falsy(line:find("Guide:", 1, true) and line:find("WARN", 1, true), "warning al caricamento: " .. line)
    end
    local seen = {}
    for _, s in ipairs(g:ListEntries({ pack = "starter" })) do
        falsy(seen[s.id], "id duplicato " .. s.id)
        seen[s.id] = true
        local e = assert(g:Get(s.id))
        truthy(#e.body >= 5, s.id .. ": corpo troppo corto")
        truthy(e.confidence == "A" or e.confidence == "B" or e.confidence == "C", s.id .. ": confidence")
        local chars = 0
        for _, b in ipairs(e.body) do
            local texts = b.type == "list" and b.items or { b.text }
            for _, t in ipairs(texts) do
                chars = chars + #t
                eq(g.Sanitize(t), t, s.id .. ": il testo contiene codici non ammessi")
                falsy(t:lower():find("lorem", 1, true), s.id .. ": segnaposto")
            end
        end
        truthy(chars > 600, s.id .. ": contenuto troppo scarso")
        for _, l in ipairs(e.links) do truthy(g.IsValidUrl(l.url)) end
        if e.confidence ~= "A" then
            local flagged = false
            for _, b in ipairs(e.body) do
                if b.type == "warn" and b.text:lower():find("da verificare in gioco", 1, true) then flagged = true end
            end
            truthy(flagged, s.id .. ": confidenza " .. e.confidence .. " senza avviso 'da verificare in gioco'")
        end
    end
    -- le guide richieste dal contratto
    for _, id in ipairs({ "primo-avvio", "profili-preset", "layout-edit-mode", "import-export", "ui-tank", "ui-healer",
        "ui-dps", "forever-pvp", "ui-raid", "problemi-comuni", "forever-ui-nativa", "forever-pve", "template-classe",
        "restrizioni-addon", "conflitti-addon" }) do
        truthy(seen["starter:" .. id], "manca la guida " .. id)
    end
    truthy(g:Get("starter:primo-avvio").steps >= 5, "primo avvio con step spuntabili")
end

T["contenuto bundled: coerente con i fatti di Forever (nessuna arena, 4 BG, raid 10/20/40)"] = function()
    local g = G()
    local function alltext(id)
        local e = g:Get("starter:" .. id)
        local out = { e.title }
        for _, b in ipairs(e.body) do
            if b.type == "list" then for _, t in ipairs(b.items) do out[#out + 1] = t end else out[#out + 1] = b.text end
        end
        return table.concat(out, "\n")
    end
    local pvp = alltext("forever-pvp")
    for _, needle in ipairs({ "Warsong Gulch", "Arathi Basin", "Alterac Valley", "Darkspear Islands", "10 contro 10", "15 contro 15", "40 contro 40" }) do
        truthy(pvp:find(needle, 1, true), "forever-pvp: manca " .. needle)
    end
    truthy(pvp:find("non ci sono arene", 1, true), "dichiara che non ci sono arene")
    local pve = alltext("forever-pve")
    for _, needle in ipairs({ "Barrow Deeps", "Hyjal Summit", "Onyxia's Lair", "9 dicembre 2026", "10 giocatori", "20 giocatori", "40 giocatori" }) do
        truthy(pve:find(needle, 1, true), "forever-pve: manca " .. needle)
    end
    local ui = alltext("forever-ui-nativa")
    for _, needle in ipairs({ "Classic", "Enhanced", "Edit Mode", "Classic (Preset)", "click casting", "damage meter", "cooldown manager" }) do
        truthy(ui:lower():find(needle:lower(), 1, true), "forever-ui-nativa: manca " .. needle)
    end
    local tpl = alltext("template-classe")
    truthy(tpl:find("/badb role", 1, true), "cita /badb role")
    truthy(tpl:find("Non esistono template per le arene", 1, true))
    local conf = alltext("conflitti-addon")
    for _, needle in ipairs({ "ClassicUI Forever", "Classic UI Forever Reframed", "Forevermore Classic UI", "Forever Unit Frames", "EllesmereUI", "ElvUI", "Clique" }) do
        truthy(conf:find(needle, 1, true), "conflitti-addon: manca " .. needle)
    end
    local res = alltext("restrizioni-addon")
    truthy(res:find("combat log", 1, true) and res:find("secret values", 1, true))
    -- nessuna arena come contesto giocabile nelle guide
    for _, s in ipairs(g:ListEntries({ pack = "starter" })) do
        local t = alltext(s.entryId):lower()
        for line in (t .. "\n"):gmatch("(.-)\n") do
            if line:find("arena", 1, true) and not line:find("arene", 1, true) and not line:find("arena e", 1, true) then
                error(s.id .. ": menziona le arene in modo non negativo: " .. line)
            end
        end
    end
    eq(g:Get("starter:forever-pvp").confidence, "B")
    eq(g:Get("starter:primo-avvio").confidence, "A")
end

T["ricerca sul contenuto bundled"] = function()
    local g = G()
    local res = g:Search("profili")
    truthy(#res > 0)
    truthy(res[1].id == "starter:profili-preset" or res[2].id == "starter:profili-preset", "titolo in cima: " .. ids(res))
    eq(g:Search("profili preset")[1].id, "starter:profili-preset", "multi-termine + frase nel titolo")
    eq(g:Search("risoluzione problemi")[1].id, "starter:problemi-comuni")
    truthy(#g:Search("perche") >= 0)
    eq(g:Search("ESPORTARE import")[1].id, "starter:import-export", "accenti/maiuscole/multi-termine")
    local conf = g:Search("conflitti", { category = "BadbUI" })
    eq(conf[1].id, "starter:conflitti-addon")
end

---------------------------------------------------------------------------
-- Visualizzatore (con il mock)
---------------------------------------------------------------------------

T["viewer: costruzione lazy, ESC, apertura e rendering"] = function(Mock)
    local g = G()
    eq(g.Viewer.frame, nil, "non costruito prima del primo Open")
    local fired = {}
    local owner = {}
    BadbUI.Events:On(owner, "BADB_GUIDE_OPENED", function(_, id) fired[#fired + 1] = id end)
    local ok, err = g:Open("starter:primo-avvio")
    eq(ok, true, tostring(err))
    local f = g.Viewer.frame
    truthy(f and f == _G.BadbUIGuideViewer, "frame globale BadbUIGuideViewer")
    truthy(f:IsShown())
    local inSpecial = false
    for _, n in ipairs(UISpecialFrames) do if n == "BadbUIGuideViewer" then inSpecial = true end end
    truthy(inSpecial, "chiusura con ESC")
    eq(#fired, 1); eq(fired[1], "starter:primo-avvio")
    truthy(f.__scripts.OnDragStart and f.__scripts.OnDragStop, "trascinabile")
    truthy(g.Viewer.stats.steps >= 5, "step resi")
    truthy(g.Viewer.stats.fs > 5)
    eq(g:GetLastOpened(), "starter:primo-avvio")
    eq(g:GetRecent()[1].id, "starter:primo-avvio")
    -- seconda apertura: stesso frame, nessun duplicato in UISpecialFrames
    g:Open("starter:ui-raid")
    eq(g.Viewer.frame, f)
    local n = 0
    for _, name in ipairs(UISpecialFrames) do if name == "BadbUIGuideViewer" then n = n + 1 end end
    eq(n, 1)
    eq(g:GetRecent()[1].id, "starter:ui-raid")
    eq(g:GetRecent()[2].id, "starter:primo-avvio")
    -- guida inesistente / argomenti strani
    local before = warnCount()
    local r, e2 = g:Open("nope:x")
    eq(r, nil); truthy(e2)
    truthy(warnCount() > before)
    for _, bad in ipairs({ 5, true, {}, "" }) do
        local ok2 = pcall(g.Open, g, bad)
        truthy(ok2)
    end
    -- Open() senza argomenti riprende dall'ultima guida; OpenLibrary mostra la ricerca
    eq(g:Open(), true)
    eq(g:OpenLibrary("profili"), true)
    eq(g.Viewer.query, "profili")
    truthy(#g.Viewer.rows > 1)
    g:Close()
    falsy(f:IsShown())
end

T["viewer: corpi enormi, blocchi misti, link copiabili, ricerca e filtri"] = function(Mock)
    local g = G()
    local body = {}
    for i = 1, 200 do
        local kinds = { "h", "p", "list", "step", "tip", "warn" }
        local k = kinds[(i % 6) + 1]
        if k == "list" then
            local items = {}
            for j = 1, 100 do items[j] = "voce " .. j .. " " .. string.rep("x", 30) end
            body[i] = { type = "list", items = items }
        else
            body[i] = { type = k, text = string.rep("parola ", 570) .. i }
        end
    end
    local url = "https://example.com/video?id=1"
    g:Register(pack("huge", { { id = "e", title = "Enorme", body = body,
        links = { { label = "Video 1", url = url }, { label = "Video 2", url = "https://example.com/2" } } },
        entry("piccola", "Piccola") }))
    eq(g:Open("huge:e"), true)
    local V = g.Viewer
    truthy(V.stats.fs >= 150, "blocchi resi: " .. V.stats.fs)
    truthy(V.stats.height > 1000, "altezza stimata: " .. V.stats.height)
    eq(V.stats.edits, 2, "un EditBox per link")
    local eb = V.pools.edit[1]
    eq(eb.url, url)
    eq(eb:GetText(), url)
    eb:SetText("manomesso")
    eb.__scripts.OnTextChanged(eb, true)
    eq(eb:GetText(), url, "sola lettura: il testo viene ripristinato")
    eb.__scripts.OnEditFocusGained(eb)
    eb.__scripts.OnEscapePressed(eb)
    -- ri-render con una entry piccola: i pool vengono riusati e gli extra nascosti
    eq(g:Open("huge:piccola"), true)
    eq(V.stats.edits, 0)
    eq(V.pools.edit[1]:IsShown(), false, "link non piu' presenti: nascosti")
    eq(V.pools.fs[1]:IsShown(), true)
    eq(V.pools.fs[V.used.fs + 1] and V.pools.fs[V.used.fs + 1]:IsShown() or false, false)
    -- ricerca con l'EditBox della lista
    V.searchBox:SetText("enorme")
    V.searchBox.__scripts.OnTextChanged(V.searchBox)
    eq(V.rows[1].kind, "label")
    eq(V.rows[2].id, "huge:e")
    V.searchBox:SetText("")
    V.searchBox.__scripts.OnTextChanged(V.searchBox)
    local cats = 0
    for _, r in ipairs(V.rows) do if r.kind == "cat" then cats = cats + 1 end end
    truthy(cats >= 2, "navigazione per categorie")
    -- click su una categoria: la comprime
    local catRow
    for i, r in ipairs(V.rows) do if r.kind == "cat" and r.name == "Cat-huge" then catRow = i end end
    local btn = V.rowPool[catRow]
    btn.__scripts.OnClick(btn)
    eq(V.collapsed["Cat-huge"], true)
    -- filtro "solo segnalibri"
    g:Bookmark("huge:piccola", true)
    V.collapsed = {}
    V.bookmarkFilter.GetChecked = function() return true end
    V.bookmarkFilter.__scripts.OnClick(V.bookmarkFilter)
    local entries = 0
    for _, r in ipairs(V.rows) do if r.kind == "entry" then entries = entries + 1; eq(r.id, "huge:piccola") end end
    eq(entries, 1)
    -- tetto di righe
    V.onlyBookmarks = false
    local many = {}
    for i = 1, 500 do many[i] = entry("m" .. i, "Molte " .. i) end
    g:Register(pack("molte", many))
    g:Register(pack("molte2", many))
    V:RefreshList()
    truthy(#V.rows <= g.LIMITS.listRows + 1)
end

T["viewer: step, progresso e segnalibro dal lettore"] = function()
    local g = G()
    g:Open("starter:primo-avvio")
    local V = g.Viewer
    local row = V.pools.step[1]
    row.check.GetChecked = function() return true end
    row.check.__scripts.OnClick(row.check)
    local c, total = g:GetProgress("starter:primo-avvio")
    eq(c, 1)
    truthy(total >= 5)
    eq(V.progressFS:GetText(), string.format("Progresso: 1/%d passi", total))
    row.check.GetChecked = function() return false end
    row.check.__scripts.OnClick(row.check)
    eq(g:GetProgress("starter:primo-avvio"), 0)
    -- il checkbox riflette il progresso salvato alla riapertura
    g:SetProgress("starter:primo-avvio", 2)
    g:Open("starter:primo-avvio")
    -- segnalibro
    falsy(g:IsBookmarked("starter:primo-avvio"))
    V.starBtn.__scripts.OnClick(V.starBtn)
    truthy(g:IsBookmarked("starter:primo-avvio"))
    eq(V.starBtn.on, true)
    V.starBtn.__scripts.OnClick(V.starBtn)
    falsy(g:IsBookmarked("starter:primo-avvio"))
    -- la confidenza compare nell'intestazione
    g:Open("starter:forever-pvp")
    truthy(V.metaFS:GetText():find("Confidenza B", 1, true), V.metaFS:GetText())
    g:Open("starter:primo-avvio")
    truthy(V.metaFS:GetText():find("Confidenza A", 1, true))
end

T["viewer: un errore nella UI non esce mai verso il chiamante"] = function()
    local g = G()
    g.Viewer.Build = function() error("UI rotta") end
    local ok, a, b = pcall(g.Open, g, "starter:primo-avvio")
    truthy(ok, "Open non lancia")
    eq(a, nil)
    truthy(b)
    local ok2 = pcall(g.OpenLibrary, g, "x")
    truthy(ok2)
end

---------------------------------------------------------------------------
-- Comandi, pagina, opzioni
---------------------------------------------------------------------------

T["comando /badb guide: open, search, bookmarks"] = function(Mock)
    local g = G()
    local cmd = BadbUI.Modules:Get("Guides").commands.guide
    truthy(cmd and type(cmd.fn) == "function" and cmd.help)
    local n = #Mock.chat
    cmd.fn("search profili")
    truthy(#Mock.chat > n, "stampa i risultati")
    local found = false
    for i = n + 1, #Mock.chat do if Mock.chat[i]:find("Profili e preset", 1, true) then found = true end end
    truthy(found, "risultato pertinente")
    truthy(g.Viewer.frame and g.Viewer.frame:IsShown(), "apre la libreria con la ricerca")
    eq(g.Viewer.query, "profili")
    n = #Mock.chat
    cmd.fn("search qwertyuiop")
    truthy(Mock.chat[n + 1]:find("Nessuna guida", 1, true))
    cmd.fn("search")
    cmd.fn("bookmarks")
    truthy(Mock.chat[#Mock.chat]:find("Nessun segnalibro", 1, true))
    g:Bookmark("starter:usare-guide", true)
    cmd.fn("bookmarks")
    truthy(Mock.chat[#Mock.chat]:find("usare-guide", 1, true))
    g:Close()
    cmd.fn("open starter:ui-dps")
    truthy(g.Viewer.frame:IsShown())
    eq(g.Viewer.current, "starter:ui-dps")
    g:Close()
    cmd.fn("")
    truthy(g.Viewer.frame:IsShown())
    cmd.fn("starter:ui-tank")
    eq(g.Viewer.current, "starter:ui-tank")
    cmd.fn("boh")
    cmd.fn(nil)
    cmd.fn("open nope:x")
end

T["pagina ConfigUI: ricerca rapida, recenti, segnalibri, apri libreria"] = function()
    local g = G()
    local mod = BadbUI.Modules:Get("Guides")
    truthy(mod.page and mod.page.title and mod.page.category == "Contenuti" and type(mod.page.build) == "function")
    eq(mod.page.refresh(), nil, "refresh prima della build: nessun errore")
    local parent = CreateFrame("Frame", nil, UIParent)
    local h = mod.page.build(parent, { UI = BadbUI.ConfigUI, W = BadbUI.Widgets })
    eq(type(h), "number")
    truthy(h > 100)
    local page = mod._page
    page.search:SetText("conflitti")
    page.search.__scripts.OnEnterPressed(page.search)
    eq(page.results[1].id, "starter:conflitti-addon")
    eq(page.rResults[1].id, "starter:conflitti-addon")
    -- clic su un risultato: apre la guida
    page.rResults[1].__scripts.OnClick(page.rResults[1])
    eq(g.Viewer.current, "starter:conflitti-addon")
    g:Bookmark("starter:ui-pvp", true)
    g:Bookmark("starter:ui-raid", true)
    mod.page.refresh()
    eq(page.rMarks[1].id, "starter:ui-raid")
    eq(page.rRecent[1].id, "starter:conflitti-addon")
    page.openBtn.__scripts.OnClick(page.openBtn)
    truthy(g.Viewer.frame:IsShown())
    -- opzione autoSuggest dalla pagina
    page.autoSuggest.GetChecked = function() return false end
    page.autoSuggest.__scripts.OnClick(page.autoSuggest)
    eq(mod:Get("autoSuggest"), false)
    page.search:SetText("")
    page.search.__scripts.OnEnterPressed(page.search)
    eq(#page.results, 0)
end

T["opzioni del modulo: autoSuggest di default attivo, descrittori ConfigUI"] = function()
    local mod = BadbUI.Modules:Get("Guides")
    eq(mod:Get("autoSuggest"), true)
    eq(mod:Get("enabled"), true)
    local toggle
    for _, o in ipairs(mod.options) do if o.type == "toggle" and o.path == "autoSuggest" then toggle = o end end
    truthy(toggle)
    for _, o in ipairs(mod.options) do if o.type == "execute" then o.func() end end
end

---------------------------------------------------------------------------
-- Disattivazione e profili
---------------------------------------------------------------------------

T["disattivazione: viewer nascosto, nessun suggerimento, Open rifiutato, riattivazione"] = function(Mock)
    local g = G()
    g:Register(pack("ds", { entry("a", "Guida", { zone = "Zona Off" }) }))
    local toasts = setupZone({ value = "Zona Off" })
    g:Open("starter:primo-avvio")
    local f = g.Viewer.frame
    truthy(f:IsShown())
    BadbUI.Modules:SetEnabled("Guides", false)
    falsy(f:IsShown(), "viewer nascosto")
    Mock.Fire("PLAYER_ENTERING_WORLD")
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#toasts, 0, "nessun suggerimento da disattivato")
    local r, err = g:Open("starter:primo-avvio")
    eq(r, nil); truthy(err)
    falsy(f:IsShown())
    -- i dati restano consultabili e i segnalibri salvati
    truthy(g:Get("starter:primo-avvio"))
    eq(#g:Search("profili") > 0, true)
    BadbUI.Modules:SetEnabled("Guides", true)
    eq(g:Open("starter:primo-avvio"), true)
    Mock.Fire("PLAYER_ENTERING_WORLD")
    eq(#toasts, 1, "di nuovo attivo")
end

T["cambio profilo: segnalibri e progressi restano (per account), opzioni seguono il profilo"] = function()
    local g = G()
    g:Bookmark("starter:ui-dps", true)
    g:SetProgress("starter:primo-avvio", 2)
    local mod = BadbUI.Modules:Get("Guides")
    mod:Set("autoSuggest", false)
    BadbUI.DB:SetProfile("Secondo")
    eq(mod:Get("autoSuggest"), true, "il nuovo profilo ha i default")
    truthy(g:IsBookmarked("starter:ui-dps"))
    eq(g:GetProgress("starter:primo-avvio"), 2)
    BadbUI.DB:SetProfile("Default")
    eq(mod:Get("autoSuggest"), false)
end

return T
