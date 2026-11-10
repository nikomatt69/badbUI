-- BadbUI - Guides: libreria di guide in-game (testo + link copiabili, niente video).
--
-- Struttura del file:
--   1. Utilita' sui testi (sanificazione codici |c/|H/|T, normalizzazione per la ricerca)
--   2. Validazione e registrazione dei pack            (logica pura, nessuna UI)
--   3. Ricerca con ranking e filtri                    (logica pura, nessuna UI)
--   4. Persistenza: segnalibri, progresso, recenti     (Badb.DB.sv.global.guides)
--   5. Suggerimento contestuale per zona
--   6. Visualizzatore (finestra BadbUIGuideViewer, costruzione LAZY)
--   7. Modulo, pagina ConfigUI e comando /badb guide
--
-- Badb.Guides e' una tabella API SEPARATA dal descrittore del modulo: ModuleProto ha gia'
-- un metodo Get(path) per le opzioni, e l'API del contratto richiede Guides:Get(entryId).
-- Badb.Guides esiste gia' quando il file viene caricato, cosi' Data/Guides.lua (e altri
-- addon) possono registrare pack subito, prima ancora che il database sia inizializzato.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger, Compat = Badb.Events, Badb.Logger, Badb.Compat

local G = Badb.Guides or {}
Badb.Guides = G

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local sfind, ssub = string.find, string.sub

G.LIMITS = {
    entriesPerPack = 500,
    blocksPerEntry = 200,
    textLength = 4000,       -- byte per singolo testo (titoli, paragrafi, voci di lista...)
    titleLength = 200,
    tagsPerEntry = 20,
    tagLength = 40,
    zonesPerEntry = 10,
    itemsPerList = 100,
    linksPerEntry = 20,
    urlLength = 500,
    packBytes = 2 * 1024 * 1024, -- testo totale per pack
    results = 50,
    queryLength = 200,
    maxTerms = 8,
    recent = 8,
    listRows = 400,          -- righe massime mostrate dalla lista del visualizzatore
}
local LIM = G.LIMITS

---------------------------------------------------------------------------
-- 1. Utilita' sui testi
---------------------------------------------------------------------------

local function trimStr(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Mappa UTF-8 -> ASCII per ricerca insensibile agli accenti (lettere italiane e latine comuni).
local FOLD_MAP = {}
local function mapChars(base, chars)
    for ch in chars:gmatch("[\192-\247][\128-\191]*") do FOLD_MAP[ch] = base end
end
mapChars("a", "àáâãäåÀÁÂÃÄÅ")
mapChars("c", "çÇ")
mapChars("e", "èéêëÈÉÊË")
mapChars("i", "ìíîïÌÍÎÏ")
mapChars("n", "ñÑ")
mapChars("o", "òóôõöøÒÓÔÕÖØ")
mapChars("u", "ùúûüÙÚÛÜ")
mapChars("y", "ýÿÝ")
mapChars("ss", "ß")
mapChars("'", "’‘")
mapChars('"', "“”")
mapChars("-", "–—")
mapChars("...", "…")

-- Minuscolo + senza accenti. Funzione pura.
function G.Fold(s)
    if type(s) ~= "string" then s = tostring(s or "") end
    s = s:gsub("[\192-\247][\128-\191]*", FOLD_MAP)
    return s:lower()
end
local fold = G.Fold

-- Rimuove i codici di formattazione per ottenere il testo "semplice" (ricerca, controllo vuoto).
local function stripEscapes(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T[^|]*|t", ""):gsub("||", "|")
    return (s:gsub("\n", " "))
end
G.StripEscapes = stripEscapes

-- Texture ammesse dentro |T...|t: icone di Interface\Icons, marcatori raid e file ID numerici.
local function textureAllowed(spec)
    local path, rest = spec:match("^([^:]*)(.*)$")
    if not path or path == "" or #path > 120 then return false end
    if not rest:match("^[%d:%-%.]*$") then return false end
    if path:match("^%d+$") then return #path <= 10 end
    local p = path:lower():gsub("/", "\\")
    if sfind(p, "..", 1, true) then return false end
    if p:match("^interface\\icons\\[%w_%-%.]+$") then return true end
    if p:match("^interface\\targetingframe\\ui%-raidtargetingicon_%d$") then return true end
    return false
end

-- Sanifica un testo: consente solo colori |cAARRGGBB...|r e texture whitelisted,
-- elimina hyperlink |H...|h, atlas |A, |K e ogni altro codice sconosciuto.
-- Una pipe isolata diventa "||" (visualizzata come pipe). Funzione pura.
function G.Sanitize(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[%z\1-\8\11-\31\127]", "") -- controlli (compreso \r), tiene solo \n
    local out, i, n, colorOpen = {}, 1, #s, false
    while i <= n do
        local j = sfind(s, "|", i, true)
        if not j then
            out[#out + 1] = ssub(s, i)
            break
        end
        if j > i then out[#out + 1] = ssub(s, i, j - 1) end
        i = j
        local d = ssub(s, i + 1, i + 1)
        if d == "|" then
            out[#out + 1] = "||"; i = i + 2
        elseif d == "c" then
            local hex = s:match("^%x%x%x%x%x%x%x%x", i + 2)
            if hex then
                out[#out + 1] = "|c" .. hex; colorOpen = true; i = i + 10
            else
                i = i + 2
            end
        elseif d == "r" then
            if colorOpen then out[#out + 1] = "|r"; colorOpen = false end
            i = i + 2
        elseif d == "H" or d == "A" or d == "K" then
            -- |Hdati|h  /  |Anome|a  /  |Kdati|k : si salta l'intero blocco
            local closer = d == "H" and "|h" or (d == "A" and "|a" or "|k")
            local e = sfind(s, closer, i + 2, true)
            i = e and (e + 2) or (i + 2)
        elseif d == "T" then
            local e = sfind(s, "|t", i + 2, true)
            if e then
                if textureAllowed(ssub(s, i + 2, e - 1)) then out[#out + 1] = ssub(s, i, e + 1) end
                i = e + 2
            else
                i = i + 2
            end
        elseif d == "h" or d == "t" or d == "a" or d == "k" then
            i = i + 2 -- chiusure orfane
        elseif d == "n" then
            out[#out + 1] = "\n"; i = i + 2
        else
            out[#out + 1] = "||"; i = i + 1 -- codice sconosciuto: la pipe diventa letterale
        end
    end
    if colorOpen then out[#out + 1] = "|r" end
    return table.concat(out)
end
local sanitize = G.Sanitize

-- Valida un URL: solo http/https, nessuno spazio/controllo/pipe, host plausibile.
-- L'URL viene sempre mostrato come testo copiabile, mai aperto dall'addon.
function G.IsValidUrl(u)
    if type(u) ~= "string" or #u < 8 or #u > LIM.urlLength then return false end
    if sfind(u, "[%c%s|\"<>\\^`{}]") then return false end
    local scheme, rest = u:match("^(%a+)://(.+)$")
    if not scheme then return false end
    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then return false end
    local host = rest:match("^([^/?#]*)")
    if not host or host == "" then return false end
    host = host:gsub(":%d+$", "")
    return host:match("^[%w%.%-]+$") ~= nil and host:match("%w") ~= nil
end

---------------------------------------------------------------------------
-- 2. Validazione e registrazione dei pack
---------------------------------------------------------------------------

local BLOCK_TYPES = { h = true, p = true, list = true, step = true, tip = true, warn = true }
G.BLOCK_TYPES = BLOCK_TYPES

local packs, packOrder, entryIndex = {}, {}, {}
local listCache -- array di tutte le entry in ordine di registrazione (invalidato da Register)

local function shortStr(v) return (tostring(v):gsub("[%c|]", "?")):sub(1, 40) end

local CONFIDENCE = { A = true, B = true, C = true }
G.CONFIDENCE_LEVELS = CONFIDENCE

local function validId(v)
    return type(v) == "string" and #v >= 1 and #v <= 64 and v:match("^[%w_%-%.]+$") ~= nil
end

-- Testo sanificato o nil, errore.
local function cleanString(v, maxLen, label, singleLine, allowEmpty)
    if type(v) ~= "string" then return nil, label .. L[": atteso un testo"] end
    if #v > maxLen then return nil, string.format(L["%s: testo troppo lungo (%d > %d)"], label, #v, maxLen) end
    local s = sanitize(v)
    if singleLine then s = s:gsub("\n", " ") end
    if not allowEmpty and trimStr(stripEscapes(s)) == "" then return nil, label .. L[": testo vuoto"] end
    return s
end

-- Ritorna blocco normalizzato, byte di testo; oppure nil, errore.
local function validateBlock(b, pos)
    if type(b) ~= "table" then return nil, L["blocco #"] .. pos .. L[" non e' una tabella"] end
    local t = b.type
    if type(t) ~= "string" or not BLOCK_TYPES[t] then
        return nil, string.format(L["blocco #%d: tipo sconosciuto '%s'"], pos, shortStr(t))
    end
    local label = L["blocco #"] .. pos .. " (" .. t .. ")"
    if t == "list" then
        local items = b.items
        if type(items) ~= "table" then return nil, label .. L[": items mancante"] end
        local out, bytes = {}, 0
        for i, it in ipairs(items) do
            if i > LIM.itemsPerList then return nil, label .. L[": troppe voci"] end
            local s, err = cleanString(it, LIM.textLength, label .. L[" voce "] .. i, true)
            if not s then return nil, err end
            out[i] = s; bytes = bytes + #s
        end
        if #out == 0 then return nil, label .. L[": lista vuota"] end
        return { type = "list", items = out }, bytes
    end
    local s, err = cleanString(b.text, LIM.textLength, label)
    if not s then return nil, err end
    return { type = t, text = s }, #s
end

local function validateLevel(v)
    if v == nil then return true end
    if type(v) == "number" then
        if v ~= v or v < 0 or v > 1000 then return false end
        return true, v, v, nil
    end
    if type(v) == "table" then
        local a, b = tonumber(v[1] or v.min), tonumber(v[2] or v.max)
        if a and b and a == a and b == b and a >= 0 and b <= 1000 and a <= b then return true, a, b, { a, b } end
    end
    return false
end

local function validateEntry(e, packId, pos)
    if type(e) ~= "table" then return nil, "entry #" .. pos .. L[" non e' una tabella"] end
    if not validId(e.id) then return nil, "entry #" .. pos .. L[": id non valido ("] .. shortStr(e.id) .. ")" end
    local where = "entry '" .. e.id .. "'"
    local title, err = cleanString(e.title, LIM.titleLength, where .. L[" titolo"], true)
    if not title then return nil, err end

    local entry = {
        id = e.id, gid = packId .. ":" .. e.id, packId = packId, title = title,
        tags = {}, zones = {}, body = {}, links = {}, stepCount = 0, confidence = "A",
    }
    local bytes = #title

    -- Confidenza dell'informazione (come docs/FOREVER_FACTS.md): A = verificata, B = fonte unica o discordante,
    -- C = ipotesi da verificare in gioco. Default "A".
    if e.confidence ~= nil then
        if type(e.confidence) ~= "string" or not CONFIDENCE[e.confidence:upper()] then
            return nil, where .. L[": confidence deve essere A, B o C"]
        end
        entry.confidence = e.confidence:upper()
    end

    if e.tags ~= nil then
        if type(e.tags) ~= "table" then return nil, where .. L[": tags deve essere una lista"] end
        for i, t in ipairs(e.tags) do
            if i > LIM.tagsPerEntry then return nil, where .. L[": troppi tag"] end
            local s, terr = cleanString(t, LIM.tagLength, where .. " tag " .. i, true)
            if not s then return nil, terr end
            entry.tags[#entry.tags + 1] = s
        end
    end

    if e.zone ~= nil then
        local list = type(e.zone) == "table" and e.zone or { e.zone }
        for i, z in ipairs(list) do
            if i > LIM.zonesPerEntry then return nil, where .. L[": troppe zone"] end
            local s, zerr = cleanString(z, 100, where .. L[" zona"], true)
            if not s then return nil, zerr end
            entry.zones[#entry.zones + 1] = s
        end
        if #entry.zones == 0 then return nil, where .. L[": zone vuoto"] end
        entry.zone = entry.zones[1]
    end

    if e.level ~= nil then
        local ok, lo, hi, range = validateLevel(e.level)
        if not ok then return nil, where .. L[": level non valido"] end
        entry.level, entry.minLevel, entry.maxLevel = range or lo, lo, hi
    end

    if type(e.body) ~= "table" then return nil, where .. L[": body mancante o non valido"] end
    for i, b in ipairs(e.body) do
        if i > LIM.blocksPerEntry then
            return nil, string.format(L["%s: troppi blocchi (max %d)"], where, LIM.blocksPerEntry)
        end
        local nb, n = validateBlock(b, i)
        if not nb then return nil, where .. ": " .. n end
        if nb.type == "step" then
            entry.stepCount = entry.stepCount + 1
            nb.index = entry.stepCount
        end
        entry.body[#entry.body + 1] = nb
        bytes = bytes + n
    end

    if e.links ~= nil then
        if type(e.links) ~= "table" then return nil, where .. L[": links deve essere una lista"] end
        for i, l in ipairs(e.links) do
            if i > LIM.linksPerEntry then return nil, where .. L[": troppi link"] end
            if type(l) ~= "table" then return nil, where .. ": link #" .. i .. L[" non valido"] end
            local url = l.url or l[2]
            local label = l.label or l[1]
            if not G.IsValidUrl(url) then
                return nil, where .. ": link #" .. i .. L[" con URL non consentito (solo http/https)"]
            end
            local ls = label ~= nil and cleanString(label, 200, where .. " link", true, true) or nil
            if not ls or trimStr(stripEscapes(ls)) == "" then ls = url end
            entry.links[#entry.links + 1] = { label = ls, url = url }
        end
    end

    -- Dati per la ricerca: titolo/tag/zona pre-normalizzati, corpo calcolato al primo uso.
    local s = { title = fold(stripEscapes(title)), tags = {}, zones = {}, cat = "", pack = "" }
    for _, t in ipairs(entry.tags) do s.tags[#s.tags + 1] = fold(stripEscapes(t)) end
    for _, z in ipairs(entry.zones) do s.zones[#s.zones + 1] = fold(stripEscapes(z)) end
    s.zone = table.concat(s.zones, " | ")
    entry._s = s
    return entry, bytes
end

local function registerImpl(pack)
    if type(pack) ~= "table" then return nil, L["il pack deve essere una tabella"] end
    if not validId(pack.id) then return nil, L["pack: id non valido ("] .. shortStr(pack.id) .. ")" end
    if pack.id:find(":", 1, true) then return nil, L["pack: l'id non puo' contenere ':'"] end
    local title, err = cleanString(pack.title, LIM.titleLength, "pack '" .. pack.id .. L["' titolo"], true)
    if not title then return nil, err end
    local category = L["Generale"]
    if pack.category ~= nil then
        category, err = cleanString(pack.category, 60, L["pack categoria"], true)
        if not category then return nil, err end
    end
    local author
    if pack.author ~= nil then
        author, err = cleanString(pack.author, 100, L["pack autore"], true)
        if not author then return nil, err end
    end
    local version = pack.version == nil and 1 or tonumber(pack.version)
    if not version or version ~= version then return nil, L["pack: version non valida"] end
    if type(pack.entries) ~= "table" then return nil, L["pack: entries mancante"] end

    local out = {
        id = pack.id, title = title, category = category, author = author, version = version,
        entries = {}, byId = {},
    }
    local skipped, errors, bytes = 0, {}, 0
    for i, e in ipairs(pack.entries) do
        if i > LIM.entriesPerPack then
            return nil, string.format(L["pack '%s': troppe entry (max %d)"], pack.id, LIM.entriesPerPack)
        end
        local entry, n = validateEntry(e, pack.id, i)
        if entry and out.byId[entry.id] then
            entry, n = nil, L["id duplicato '"] .. entry.id .. "'"
        end
        if entry then
            bytes = bytes + n
            if bytes > LIM.packBytes then
                return nil, string.format(L["pack '%s': contenuto troppo grande"], pack.id)
            end
            entry.category, entry.packTitle = category, title
            entry._s.cat, entry._s.pack = fold(stripEscapes(category)), fold(stripEscapes(title))
            out.entries[#out.entries + 1] = entry
            out.byId[entry.id] = entry
        else
            skipped = skipped + 1
            errors[#errors + 1] = n
        end
    end
    if #out.entries == 0 then
        return nil, string.format(L["pack '%s': nessuna entry valida%s"], pack.id,
            errors[1] and (" (" .. errors[1] .. ")") or "")
    end

    -- Sostituisce un eventuale pack con lo stesso id (ricaricamento).
    local old = packs[pack.id]
    if old then
        for _, e in ipairs(old.entries) do entryIndex[e.gid] = nil end
    else
        packOrder[#packOrder + 1] = pack.id
    end
    packs[pack.id] = out
    for _, e in ipairs(out.entries) do entryIndex[e.gid] = e end
    listCache = nil
    return pack.id, { entries = #out.entries, skipped = skipped, errors = errors }
end

-- Registra un pack. Ritorna packId, info({entries, skipped, errors}) oppure nil, errore.
-- Mai errori Lua verso il chiamante: pack o entry invalidi producono un warning nel Logger.
-- Le entry invalide vengono saltate (con warning); il pack e' rifiutato solo se e' lui stesso
-- invalido o non ha nessuna entry valida.
function G:Register(pack)
    local ok, a, b = pcall(registerImpl, pack)
    if not ok then
        Logger:Warn(L["Guide: registrazione fallita: %s"], shortStr(a))
        return nil, L["errore interno nella validazione"]
    end
    if not a then
        Logger:Warn(L["Guide: pack rifiutato - %s"], tostring(b))
        return nil, b
    end
    for i, msg in ipairs(b.errors) do
        if i > 5 then
            Logger:Warn(L["Guide: pack '%s': altre %d entry saltate"], a, #b.errors - 5)
            break
        end
        Logger:Warn(L["Guide: pack '%s': entry saltata - %s"], a, tostring(msg))
    end
    return a, b
end

function G:Unregister(packId)
    local p = type(packId) == "string" and packs[packId]
    if not p then return false, L["pack inesistente"] end
    for _, e in ipairs(p.entries) do entryIndex[e.gid] = nil end
    packs[packId] = nil
    for i, id in ipairs(packOrder) do
        if id == packId then table.remove(packOrder, i); break end
    end
    listCache = nil
    return true
end

local function allEntries()
    if listCache then return listCache end
    local list = {}
    for _, pid in ipairs(packOrder) do
        for _, e in ipairs(packs[pid].entries) do list[#list + 1] = e end
    end
    listCache = list
    return list
end

local function lookup(entryId)
    if type(entryId) ~= "string" then return nil end
    return entryIndex[entryId]
end

local function summary(e, score)
    local tags = {}
    for i, t in ipairs(e.tags) do tags[i] = t end
    return {
        id = e.gid, entryId = e.id, packId = e.packId, title = e.title, category = e.category,
        tags = tags, zone = e.zone, level = e.level, steps = e.stepCount, score = score or 0,
        confidence = e.confidence,
    }
end

function G:ListPacks()
    local list = {}
    for _, pid in ipairs(packOrder) do
        local p = packs[pid]
        list[#list + 1] = { id = p.id, title = p.title, category = p.category, version = p.version,
            author = p.author, count = #p.entries }
    end
    return list
end

function G:ListCategories()
    local seen, list = {}, {}
    for _, e in ipairs(allEntries()) do
        local c = seen[e.category]
        if not c then
            c = { name = e.category, count = 0 }
            seen[e.category] = c
            list[#list + 1] = c
        end
        c.count = c.count + 1
    end
    return list
end

-- Copia completa (modificabile dal chiamante) di una entry; nil, errore se inesistente.
function G:Get(entryId)
    local e = lookup(entryId)
    if not e then return nil, L["guida inesistente"] end
    local copy = summary(e)
    copy.packTitle = e.packTitle
    copy.zones = Badb.CopyTable(e.zones)
    copy.body = Badb.CopyTable(e.body)
    copy.links = Badb.CopyTable(e.links)
    return copy
end

---------------------------------------------------------------------------
-- 3. Ricerca (funzioni pure: lavorano su liste di entry, nessuno stato globale)
---------------------------------------------------------------------------

local function bodyText(e)
    if e._body then return e._body end
    local parts = {}
    for _, b in ipairs(e.body) do
        if b.type == "list" then
            for _, it in ipairs(b.items) do parts[#parts + 1] = it end
        else
            parts[#parts + 1] = b.text
        end
    end
    e._body = fold(stripEscapes(table.concat(parts, " ")))
    return e._body
end

-- Spezza la query in termini normalizzati (max LIM.maxTerms).
function G.ParseQuery(query)
    local terms = {}
    if type(query) ~= "string" then return terms, "" end
    query = ssub(query, 1, LIM.queryLength)
    local f = fold(query)
    for t in f:gmatch("%S+") do
        if #terms >= LIM.maxTerms then break end
        terms[#terms + 1] = ssub(t, 1, 64)
    end
    return terms, trimStr(f)
end

-- Punteggio di una entry per i termini dati, o nil se un termine non compare (AND).
-- titolo (100, +30 a inizio parola) > tag (70 esatto / 50) > zona (30) > categoria/pack (20) > corpo (10).
function G.ScoreEntry(e, terms, phrase)
    local s = e._s
    local total = 0
    for _, t in ipairs(terms) do
        local best = 0
        local pos = sfind(s.title, t, 1, true)
        if pos then
            best = 100
            if pos == 1 or ssub(s.title, pos - 1, pos - 1) == " " then best = 130 end
        else
            for _, tag in ipairs(s.tags) do
                if tag == t then best = max(best, 70) elseif sfind(tag, t, 1, true) then best = max(best, 50) end
            end
            if best == 0 then
                if sfind(s.zone, t, 1, true) then best = 30
                elseif sfind(s.cat, t, 1, true) or sfind(s.pack, t, 1, true) then best = 20
                elseif sfind(bodyText(e), t, 1, true) then best = 10
                else return nil end
            end
        end
        total = total + best
    end
    if phrase and #terms > 1 and sfind(s.title, phrase, 1, true) then total = total + 50 end
    return total
end

local function prepareFilter(filter)
    local f = {}
    if type(filter) ~= "table" then return f end
    if type(filter.category) == "string" and filter.category ~= "" then f.category = fold(filter.category) end
    if type(filter.tag) == "string" and filter.tag ~= "" then f.tag = fold(filter.tag):gsub("^#", "") end
    if type(filter.zone) == "string" and filter.zone ~= "" then f.zone = fold(filter.zone) end
    if type(filter.pack) == "string" and filter.pack ~= "" then f.pack = filter.pack end
    f.level = tonumber(filter.level)
    if filter.bookmarked and type(filter._bookmarks) == "table" then f.bookmarks = filter._bookmarks end
    return f
end

local function passFilter(e, f)
    if f.pack and e.packId ~= f.pack then return false end
    if f.category and e._s.cat ~= f.category then return false end
    if f.tag then
        local found = false
        for _, t in ipairs(e._s.tags) do if t == f.tag then found = true; break end end
        if not found then return false end
    end
    if f.zone then
        local found = false
        for _, z in ipairs(e._s.zones) do if sfind(z, f.zone, 1, true) then found = true; break end end
        if not found then return false end
    end
    if f.level and e.minLevel and (f.level < e.minLevel or f.level > e.maxLevel) then
        -- una entry con livello scalare n e' consigliata da n in su (maxLevel == minLevel significa "da n")
        if not (e.level == e.minLevel and f.level >= e.minLevel) then return false end
    end
    if f.bookmarks and f.bookmarks[e.gid] ~= true then return false end
    return true
end

-- Funzione pura: cerca dentro una lista di entry. Ritorna array di riepiloghi ordinati per punteggio.
function G.SearchList(entries, query, filter, limit)
    limit = min(tonumber(limit) or LIM.results, LIM.results)
    local terms, phrase = G.ParseQuery(query)
    local f = prepareFilter(filter)
    local hits = {}
    for _, e in ipairs(entries) do
        if passFilter(e, f) then
            local score = #terms == 0 and 0 or G.ScoreEntry(e, terms, phrase)
            if score then hits[#hits + 1] = { e = e, score = score, key = e._s.title } end
        end
    end
    if #terms > 0 then
        table.sort(hits, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if a.key ~= b.key then return a.key < b.key end
            return a.e.gid < b.e.gid
        end)
    end
    local out = {}
    for i = 1, min(#hits, limit) do out[i] = summary(hits[i].e, hits[i].score) end
    return out
end

---------------------------------------------------------------------------
-- 4. Persistenza: Badb.DB.sv.global.guides
--    { bookmarks = {[id]=true}, progress = {[id] = {done = {[n]=true}}}, lastOpened = id, recent = {id,...} }
---------------------------------------------------------------------------

local fallbackStore -- usato solo se il DB non e' pronto (non dovrebbe succedere dopo ADDON_LOADED)

local function store()
    local DB = Badb.DB
    local g = DB and DB.sv and DB.sv.global
    local s
    if type(g) == "table" then
        s = g.guides
        if type(s) ~= "table" then s = {}; g.guides = s end
    else
        fallbackStore = fallbackStore or {}
        s = fallbackStore
    end
    if type(s.bookmarks) ~= "table" then s.bookmarks = {} end
    if type(s.progress) ~= "table" then s.progress = {} end
    if s.lastOpened ~= nil and type(s.lastOpened) ~= "string" then s.lastOpened = nil end
    if type(s.recent) ~= "table" then s.recent = {} end
    return s
end

local function doneSet(entry)
    local p = store().progress[entry.gid]
    local set, count = {}, 0
    if type(p) == "table" and type(p.done) == "table" then
        for i = 1, entry.stepCount do
            if p.done[i] == true then set[i] = true; count = count + 1 end
        end
    end
    return set, count
end

function G:IsBookmarked(entryId)
    return store().bookmarks[entryId] == true and lookup(entryId) ~= nil
end

-- Segnalibro: value true/false, nil = inverte. Ritorna true, nuovoStato oppure nil, errore.
function G:Bookmark(entryId, value)
    if not lookup(entryId) then return nil, L["guida inesistente"] end
    local s = store()
    if value == nil then value = not (s.bookmarks[entryId] == true) end
    s.bookmarks[entryId] = value and true or nil
    return true, value and true or false
end

function G:GetBookmarks()
    local list = {}
    for id, v in pairs(store().bookmarks) do
        local e = v == true and lookup(id)
        if e then list[#list + 1] = summary(e) end
    end
    table.sort(list, function(a, b)
        local ta, tb = fold(a.title), fold(b.title)
        if ta ~= tb then return ta < tb end
        return a.id < b.id
    end)
    return list
end

-- Progresso: numero di step completati e totale. nil, errore se la guida non esiste.
function G:GetProgress(entryId)
    local e = lookup(entryId)
    if not e then return nil, L["guida inesistente"] end
    local _, count = doneSet(e)
    return count, e.stepCount
end

-- Mappa { [indiceStep] = true } degli step completati (copia).
function G:GetStepsDone(entryId)
    local e = lookup(entryId)
    if not e then return {} end
    return (doneSet(e))
end

local function writeDone(e, set)
    local progress = store().progress
    if next(set) == nil then progress[e.gid] = nil else progress[e.gid] = { done = set } end
end

-- Imposta il progresso a "primi n step completati" (n limitato a 0..totale).
function G:SetProgress(entryId, n)
    local e = lookup(entryId)
    if not e then return nil, L["guida inesistente"] end
    n = tonumber(n)
    if not n or n ~= n then return nil, L["valore non valido"] end
    n = max(0, min(floor(n), e.stepCount))
    local set = {}
    for i = 1, n do set[i] = true end
    writeDone(e, set)
    return true, n
end

-- Spunta/toglie un singolo step (1..totale).
function G:SetStep(entryId, index, done)
    local e = lookup(entryId)
    if not e then return nil, L["guida inesistente"] end
    index = tonumber(index)
    if not index or index ~= floor(index) or index < 1 or index > e.stepCount then
        return nil, L["step inesistente"]
    end
    local set, count = doneSet(e)
    if done == nil then done = not set[index] end
    set[index] = done and true or nil
    writeDone(e, set)
    local _, c = doneSet(e)
    return true, c
end

function G:GetLastOpened()
    local id = store().lastOpened
    return lookup(id) and id or nil
end

-- Ultime guide aperte (piu' recente prima), solo quelle ancora esistenti.
function G:GetRecent(n)
    local list = {}
    for _, id in ipairs(store().recent) do
        local e = type(id) == "string" and lookup(id)
        if e then list[#list + 1] = summary(e) end
        if #list >= (n or LIM.recent) then break end
    end
    return list
end

local function noteOpened(gid)
    local s = store()
    s.lastOpened = gid
    local r = { gid }
    for _, id in ipairs(s.recent) do
        if id ~= gid and type(id) == "string" and #r < LIM.recent then r[#r + 1] = id end
    end
    s.recent = r
end

-- Elimina dal salvataggio tutto cio' che non e' piu' valido: segnalibri/progressi di guide
-- non piu' registrate, step oltre il totale, valori di tipo sbagliato. Ritorna il numero di voci rimosse.
-- Viene eseguita a PLAYER_LOGIN (quando tutti gli addon hanno registrato i loro pack).
function G:Cleanup()
    local s = store()
    local removed = 0
    for id, v in pairs(s.bookmarks) do
        if type(id) ~= "string" or v ~= true or not lookup(id) then s.bookmarks[id] = nil; removed = removed + 1 end
    end
    for id, p in pairs(s.progress) do
        local e = type(id) == "string" and lookup(id)
        if not e or type(p) ~= "table" or type(p.done) ~= "table" then
            s.progress[id] = nil; removed = removed + 1
        else
            local set = {}
            for i = 1, e.stepCount do if p.done[i] == true then set[i] = true end end
            local differs = false
            for k, v in pairs(p.done) do if v ~= true or not set[k] then differs = true; break end end
            if next(set) == nil then
                s.progress[id] = nil; removed = removed + 1
            elseif differs then
                s.progress[id] = { done = set }; removed = removed + 1
            end
        end
    end
    if s.lastOpened and not lookup(s.lastOpened) then s.lastOpened = nil; removed = removed + 1 end
    local r = {}
    for _, id in ipairs(s.recent) do
        if type(id) == "string" and lookup(id) and #r < LIM.recent then r[#r + 1] = id else removed = removed + 1 end
    end
    s.recent = r
    return removed
end

-- Ricerca sulla libreria registrata (con filtro opzionale "bookmarked").
function G:Search(query, filter)
    local ok, res = pcall(function()
        local f = filter
        if type(filter) == "table" and filter.bookmarked then
            f = {}
            for k, v in pairs(filter) do f[k] = v end
            f._bookmarks = store().bookmarks
        end
        return G.SearchList(allEntries(), query, f, LIM.results)
    end)
    if not ok then
        Logger:Warn(L["Guide: ricerca fallita: %s"], shortStr(res))
        return {}
    end
    return res
end

-- Elenco completo (senza limite di 50, ma con tetto di sicurezza) per la navigazione a categorie.
function G:ListEntries(filter)
    local ok, res = pcall(function()
        local f = filter
        if type(filter) == "table" and filter.bookmarked then
            f = {}
            for k, v in pairs(filter) do f[k] = v end
            f._bookmarks = store().bookmarks
        end
        local pf = prepareFilter(f)
        local out = {}
        for _, e in ipairs(allEntries()) do
            if passFilter(e, pf) then out[#out + 1] = summary(e) end
            if #out >= 2000 then break end
        end
        return out
    end)
    return ok and res or {}
end

---------------------------------------------------------------------------
-- 5. Suggerimento contestuale per zona
---------------------------------------------------------------------------

local M -- descrittore del modulo (definito nella sezione 7)
local notified = {}      -- zona normalizzata -> true (un solo avviso per zona per sessione)
local pendingSuggest = false

local function autoSuggestEnabled()
    local ok, v = pcall(function() return M and M:Get("autoSuggest") end)
    if not ok or v == nil then return true end
    return v and true or false
end

-- Nomi della zona corrente, con API sondate in modo difensivo (possono mancare o essere secret).
local function currentZones()
    local names = {}
    local function add(v)
        if type(v) ~= "string" then return end
        if Compat and Compat.IsSecret and Compat.IsSecret(v) then return end
        v = trimStr(v)
        if v ~= "" then names[#names + 1] = v end
    end
    if type(GetRealZoneText) == "function" then local ok, v = pcall(GetRealZoneText); if ok then add(v) end end
    if type(GetZoneText) == "function" then local ok, v = pcall(GetZoneText); if ok then add(v) end end
    if type(GetInstanceInfo) == "function" then local ok, v = pcall(GetInstanceInfo); if ok then add(v) end end
    return names
end

-- Entry il cui campo zone combacia (uguaglianza normalizzata) con la zona data.
function G:FindByZone(zone)
    local key = fold(stripEscapes(tostring(zone or "")))
    local list = {}
    if key == "" then return list end
    for _, e in ipairs(allEntries()) do
        for _, z in ipairs(e._s.zones) do
            if z == key then list[#list + 1] = summary(e); break end
        end
    end
    return list
end

local function notify(zone, matches)
    local text = string.format(L["Guide disponibili per %s: %s%s. Aprile con /badb guide."], zone,
        matches[1].title, #matches > 1 and (L[" e altre "] .. (#matches - 1)) or "")
    local UI = Badb.ConfigUI
    if UI and type(UI.Toast) == "function" then
        local ok = pcall(UI.Toast, UI, text, "info")
        if ok then return end
    end
    Logger:Info("%s", text)
end

-- Controlla la zona corrente. Mai apre finestre, mai in combattimento, un avviso per zona.
function G:CheckZone()
    if not autoSuggestEnabled() then return false end
    if InCombatLockdown and InCombatLockdown() then pendingSuggest = true; return false end
    pendingSuggest = false
    for _, zone in ipairs(currentZones()) do
        local key = fold(zone)
        if not notified[key] then
            local matches = G:FindByZone(zone)
            if #matches > 0 then
                notified[key] = true
                notify(zone, matches)
                return true
            end
        end
    end
    return false
end

function G:ResetSuggestions() notified = {}; pendingSuggest = false end

---------------------------------------------------------------------------
-- 6. Visualizzatore (costruzione lazy al primo Open)
---------------------------------------------------------------------------

local V = { pools = { fs = {}, step = {}, edit = {} }, used = { fs = 0, step = 0, edit = 0 }, collapsed = {}, query = "" }
G.Viewer = V

local FRAME_NAME = "BadbUIGuideViewer"
local WIDTH, HEIGHT, LIST_W, READER_W = 880, 600, 270, 528
local COLORS = {
    text = "ffd8dce6", dim = "ff8f98ab", accent = "ff3fa7ff", tip = "ff7fd68f", warn = "ffffb347", gold = "ffffd100",
}
local function paint(name, s) return "|c" .. COLORS[name] .. s .. "|r" end

local function backdrop(f, bg, border)
    if not f.SetBackdrop then return end
    pcall(function()
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        f:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end)
end

local function newFrame(kind, parent)
    local make = Compat and Compat.CreateFrame or CreateFrame
    return make(kind, nil, parent)
end

local function newScroll(parent)
    local ok, s = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if not ok or not s then s = CreateFrame("ScrollFrame", nil, parent) end
    local child = CreateFrame("Frame", nil, s)
    s:SetScrollChild(child)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        if type(range) ~= "number" then range = 0 end
        local cur = self:GetVerticalScroll()
        if type(cur) ~= "number" then cur = 0 end
        local nv = cur - delta * 40
        if nv < 0 then nv = 0 elseif nv > range then nv = range end
        self:SetVerticalScroll(nv)
    end)
    return s, child
end

-- Stima dell'altezza di un testo quando il client non la fornisce (mock, FontString appena creata).
local function estimateHeight(text, width, lineH, charW)
    local perLine = max(10, floor(width / charW))
    local lines = 0
    for seg in (text .. "\n"):gmatch("(.-)\n") do lines = lines + max(1, ceil(#seg / perLine)) end
    return lines * lineH
end

local function measure(fs, text, width, lineH)
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = estimateHeight(text, width, lineH, 6.4) end
    return h
end

-- Pool di elementi del lettore: si riusano a ogni render, cosi' i corpi grandi non creano garbage.
function V:Reset()
    self.used.fs, self.used.step, self.used.edit = 0, 0, 0
    for _, list in pairs(self.pools) do
        for _, o in ipairs(list) do o:Hide() end
    end
end

function V:AcquireFS(fontName)
    local u = self.used.fs + 1
    self.used.fs = u
    local fs = self.pools.fs[u]
    if not fs then
        fs = self.content:CreateFontString(nil, "ARTWORK", fontName)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        self.pools.fs[u] = fs
    end
    pcall(fs.SetFontObject, fs, fontName)
    fs:SetWordWrap(true)
    fs:Show()
    return fs
end

function V:AcquireStep()
    local u = self.used.step + 1
    self.used.step = u
    local row = self.pools.step[u]
    if not row then
        local ok, cb = pcall(CreateFrame, "CheckButton", nil, self.content, "UICheckButtonTemplate")
        if not ok or not cb then cb = CreateFrame("CheckButton", nil, self.content) end
        cb:SetSize(24, 24)
        cb:SetScript("OnClick", function(self2)
            local r = self2.row
            if not r or not r.entryId then return end
            G:SetStep(r.entryId, r.index, self2:GetChecked() and true or false)
            V:UpdateProgress()
            V:RefreshList()
        end)
        row = { check = cb }
        cb.row = row
        -- Il pool contiene "oggetti" con Hide/Show: la riga li inoltra al checkbox.
        row.Hide = function() cb:Hide() end
        row.Show = function() cb:Show() end
        self.pools.step[u] = row
    end
    row.check:Show()
    return row
end

function V:AcquireEdit()
    local u = self.used.edit + 1
    self.used.edit = u
    local eb = self.pools.edit[u]
    if not eb then
        eb = newFrame("EditBox", self.content)
        eb:SetAutoFocus(false)
        eb:SetHeight(22)
        eb:SetTextInsets(6, 6, 0, 0)
        if _G.ChatFontNormal then eb:SetFontObject(_G.ChatFontNormal) end
        backdrop(eb, { 0.05, 0.06, 0.08, 0.9 }, { 0.25, 0.28, 0.34, 1 })
        -- Sola lettura: il testo viene ripristinato a ogni modifica, il click lo seleziona per Ctrl+C.
        eb:SetScript("OnTextChanged", function(self2, user)
            if user and self2.url then self2:SetText(self2.url); self2:HighlightText() end
        end)
        eb:SetScript("OnEditFocusGained", function(self2) self2:HighlightText() end)
        eb:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self2) self2:ClearFocus() end)
        self.pools.edit[u] = eb
    end
    eb:Show()
    return eb
end

local FONT_FOR = { h = "GameFontNormalLarge", p = "GameFontHighlight", tip = "GameFontHighlight",
    warn = "GameFontHighlight", list = "GameFontHighlight", step = "GameFontHighlight" }

-- Disegna le sezioni del corpo dentro il contenitore scorrevole.
function V:Render(entry)
    self:Reset()
    local w = READER_W
    local y = 0
    local content = self.content
    local function place(obj, x, yy)
        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", content, "TOPLEFT", x, -yy)
    end
    local function text(font, s, x, gap)
        local fs = self:AcquireFS(font)
        local width = w - x
        fs:SetWidth(width)
        fs:SetText(s)
        place(fs, x, y)
        local h = measure(fs, s, width, font == "GameFontNormalLarge" and 20 or 15)
        fs:SetHeight(h)
        y = y + h + (gap or 8)
        return fs
    end

    for _, b in ipairs(entry.body) do
        local t = b.type
        if t == "h" then
            y = y + 6
            text(FONT_FOR.h, paint("accent", b.text), 0, 6)
        elseif t == "p" then
            text(FONT_FOR.p, b.text, 0)
        elseif t == "list" then
            local lines = {}
            for i, it in ipairs(b.items) do lines[i] = "• " .. it end
            text(FONT_FOR.list, table.concat(lines, "\n"), 12)
        elseif t == "step" then
            local row = self:AcquireStep()
            row.entryId, row.index = entry.gid, b.index
            local done = G:GetStepsDone(entry.gid)[b.index] == true
            row.check:SetChecked(done)
            place(row.check, 0, y - 3)
            local fs = text(FONT_FOR.step, b.text, 30, 8)
            row.fs = fs
        elseif t == "tip" then
            text(FONT_FOR.tip, paint("tip", L["Consiglio: "]) .. b.text, 12)
        elseif t == "warn" then
            text(FONT_FOR.warn, paint("warn", L["Attenzione: "]) .. b.text, 12)
        end
    end

    if #entry.links > 0 then
        y = y + 8
        text(FONT_FOR.h, paint("accent", L["Link (seleziona e copia con Ctrl+C)"]), 0, 6)
        for _, l in ipairs(entry.links) do
            text("GameFontNormalSmall", l.label, 0, 2)
            local eb = self:AcquireEdit()
            eb.url = l.url
            eb:SetWidth(w)
            eb:SetText(l.url)
            eb:SetCursorPosition(0)
            place(eb, 0, y)
            y = y + 28
        end
    end

    content:SetHeight(y + 24)
    self.stats = { fs = self.used.fs, steps = self.used.step, edits = self.used.edit, height = y }
    if self.scroll then self.scroll:SetVerticalScroll(0) end
end

function V:UpdateProgress()
    local e = self.current and lookup(self.current)
    if not e or not self.progressFS then return end
    if e.stepCount > 0 then
        local c = G:GetProgress(e.gid)
        self.progressFS:SetText(string.format(L["Progresso: %d/%d passi"], c or 0, e.stepCount))
    else
        self.progressFS:SetText("")
    end
end

function V:UpdateBookmark()
    local e = self.current and lookup(self.current)
    if not self.starBtn then return end
    local on = e and G:IsBookmarked(e.gid) or false
    self.starBtn.on = on
    if self.starBtn.label then
        self.starBtn.label:SetText(on and paint("gold", L["Segnalibro"]) or paint("dim", L["Segnalibro"]))
    end
    if self.starBtn.icon then
        if self.starBtn.icon.SetDesaturated then self.starBtn.icon:SetDesaturated(not on) end
    end
end

function V:ShowEntry(gid)
    local e = lookup(gid)
    if not e then return nil, L["guida inesistente"] end
    self.current = gid
    local meta = { e.packTitle, e.category }
    if e.zone then meta[#meta + 1] = e.zone end
    if e.minLevel then
        meta[#meta + 1] = e.maxLevel and e.maxLevel ~= e.minLevel and (L["livello "] .. e.minLevel .. "-" .. e.maxLevel)
            or (L["livello "] .. e.minLevel)
    end
    if e.confidence and e.confidence ~= "A" then
        meta[#meta + 1] = paint("warn", L["Confidenza "] .. e.confidence .. L[": da verificare in gioco"])
    else
        meta[#meta + 1] = L["Confidenza A"]
    end
    self.titleFS:SetText(e.title)
    self.metaFS:SetText(paint("dim", table.concat(meta, "  -  ")))
    self:Render(e)
    self:UpdateProgress()
    self:UpdateBookmark()
    self:RefreshList()
    return true
end

function V:ShowWelcome()
    self.current = nil
    self.titleFS:SetText(L["Libreria guide"])
    self.metaFS:SetText("")
    self:Reset()
    local fs = self:AcquireFS("GameFontHighlight")
    local s = string.format(L["Scegli una guida dall'elenco a sinistra o cerca per parola chiave.\n\n"] ..
        L["Hai %d guide in %d pack. I link vanno copiati con Ctrl+C e aperti nel browser: "] ..
        L["dal gioco non e' possibile riprodurre video."], #allEntries(), #packOrder)
    fs:SetWidth(READER_W)
    fs:SetText(s)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
    fs:SetHeight(measure(fs, s, READER_W, 15))
    self.content:SetHeight(measure(fs, s, READER_W, 15) + 20)
    self.progressFS:SetText("")
    self:UpdateBookmark()
    self.stats = { fs = 1, steps = 0, edits = 0, height = 0 }
end

-- Righe della lista a sinistra: categorie comprimibili con le loro guide, oppure risultati di ricerca.
function V:BuildRows()
    local rows = {}
    local filter = self.onlyBookmarks and { bookmarked = true } or nil
    if self.query ~= "" then
        local res = G:Search(self.query, filter)
        rows[#rows + 1] = { kind = "label", text = paint("dim", string.format(L["Risultati: %d"], #res)) }
        for _, s in ipairs(res) do rows[#rows + 1] = { kind = "entry", id = s.id, s = s } end
        return rows
    end
    local groups, order = {}, {}
    for _, s in ipairs(G:ListEntries(filter)) do
        local g = groups[s.category]
        if not g then g = { name = s.category, items = {} }; groups[s.category] = g; order[#order + 1] = g end
        g.items[#g.items + 1] = s
    end
    for _, g in ipairs(order) do
        local closed = self.collapsed[g.name]
        rows[#rows + 1] = { kind = "cat", name = g.name,
            text = paint("accent", (closed and "[+] " or "[-] ") .. g.name) .. paint("dim", " (" .. #g.items .. ")") }
        if not closed then
            for _, s in ipairs(g.items) do rows[#rows + 1] = { kind = "entry", id = s.id, s = s } end
        end
    end
    if #rows == 0 then rows[1] = { kind = "label", text = paint("dim", L["Nessuna guida."]) } end
    return rows
end

function V:RefreshList()
    if not self.listChild then return end
    local rows = self:BuildRows()
    local extra = #rows - LIM.listRows
    if extra > 0 then
        for i = #rows, LIM.listRows + 1, -1 do rows[i] = nil end
        rows[#rows + 1] = { kind = "label", text = paint("dim", string.format(L["... altre %d: usa la ricerca"], extra)) }
    end
    self.rows = rows
    local pool = self.rowPool
    for i, r in ipairs(rows) do
        local b = pool[i]
        if not b then
            b = CreateFrame("Button", nil, self.listChild)
            b:SetSize(LIST_W - 8, 20)
            b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            b.label:SetPoint("LEFT", b, "LEFT", 6, 0)
            b.label:SetWidth(LIST_W - 22)
            b.label:SetJustifyH("LEFT")
            b.label:SetWordWrap(false)
            b.hl = b:CreateTexture(nil, "BACKGROUND")
            b.hl:SetAllPoints(b)
            b.hl:SetColorTexture(1, 1, 1, 0.08)
            b.hl:Hide()
            b:SetScript("OnEnter", function(s2) if s2.row and s2.row.kind ~= "label" then s2.hl:Show() end end)
            b:SetScript("OnLeave", function(s2) s2.hl:Hide() end)
            b:SetScript("OnClick", function(s2)
                local row = s2.row
                if not row then return end
                if row.kind == "cat" then
                    V.collapsed[row.name] = not V.collapsed[row.name]
                    V:RefreshList()
                elseif row.kind == "entry" then
                    G:Open(row.id)
                end
            end)
            pool[i] = b
        end
        b.row = r
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.listChild, "TOPLEFT", 0, -(i - 1) * 20)
        local label = r.text
        if r.kind == "entry" then
            local s = r.s
            local prefix = G:IsBookmarked(s.id) and paint("gold", "* ") or ""
            local prog = ""
            if s.steps > 0 then
                local c = G:GetProgress(s.id) or 0
                prog = paint("dim", string.format("  %d/%d", c, s.steps))
            end
            local sel = self.current == s.id
            label = prefix .. (sel and paint("accent", s.title) or s.title) .. prog
        end
        b.label:SetText(label)
        b:Show()
    end
    for i = #rows + 1, #pool do pool[i]:Hide() end
    self.listChild:SetHeight(#rows * 20 + 8)
end

function V:SetQuery(q)
    q = type(q) == "string" and q or ""
    self.query = q
    if self.searchBox then self.searchBox:SetText(q) end
    self:RefreshList()
end

function V:Build()
    if self.frame then return self.frame end
    -- il nome globale e' fisso: serve a UISpecialFrames (chiusura con ESC) e ai test.
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    backdrop(f, { 0.07, 0.08, 0.10, 0.97 }, { 0.20, 0.22, 0.28, 1 })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
    title:SetText(L["BadbUI - Guide"])

    local okClose, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if not okClose or not close then
        close = CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        close:SetScript("OnClick", function() f:Hide() end)
        local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        x:SetPoint("CENTER")
        x:SetText("X")
    end
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- Colonna sinistra: ricerca, filtro segnalibri, lista.
    local sb = newFrame("EditBox", f)
    sb:SetSize(LIST_W - 8, 24)
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
    sb:SetAutoFocus(false)
    sb:SetTextInsets(6, 6, 0, 0)
    sb:SetMaxLetters(LIM.queryLength)
    if _G.ChatFontNormal then sb:SetFontObject(_G.ChatFontNormal) end
    backdrop(sb, { 0.05, 0.06, 0.08, 0.9 }, { 0.25, 0.28, 0.34, 1 })
    sb:SetScript("OnTextChanged", function(s)
        V.query = trimStr(s:GetText() or "")
        V:RefreshList()
    end)
    sb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    sb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    self.searchBox = sb

    local okCb, cb = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
    if not okCb or not cb then cb = CreateFrame("CheckButton", nil, f) end
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -70)
    local cbLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbLabel:SetText(L["Solo segnalibri"])
    cb:SetScript("OnClick", function(s)
        V.onlyBookmarks = s:GetChecked() and true or false
        V:RefreshList()
    end)
    self.bookmarkFilter = cb

    local listScroll, listChild = newScroll(f)
    listScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -98)
    listScroll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    listScroll:SetWidth(LIST_W)
    listChild:SetWidth(LIST_W - 8)
    listChild:SetHeight(10)
    self.listScroll, self.listChild, self.rowPool = listScroll, listChild, {}

    -- Colonna destra: intestazione fissa + corpo scorrevole.
    local x0 = LIST_W + 34
    local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -42)
    titleFS:SetWidth(READER_W - 130)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
    local metaFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metaFS:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -70)
    metaFS:SetWidth(READER_W)
    metaFS:SetJustifyH("LEFT")
    local progressFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressFS:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -88)
    progressFS:SetJustifyH("LEFT")
    self.titleFS, self.metaFS, self.progressFS = titleFS, metaFS, progressFS

    -- Segnalibro: stella (atlas, se disponibile) + etichetta.
    local star = CreateFrame("Button", nil, f)
    star:SetSize(110, 22)
    star:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -44)
    star.icon = star:CreateTexture(nil, "ARTWORK")
    star.icon:SetSize(16, 16)
    star.icon:SetPoint("LEFT", star, "LEFT", 0, 0)
    pcall(star.icon.SetAtlas, star.icon, "auctionhouse-icon-favorite")
    star.label = star:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    star.label:SetPoint("LEFT", star.icon, "RIGHT", 4, 0)
    star:SetScript("OnClick", function()
        if V.current then
            G:Bookmark(V.current)
            V:UpdateBookmark()
            V:RefreshList()
        end
    end)
    self.starBtn = star

    local scroll, content = newScroll(f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -112)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)
    content:SetWidth(READER_W)
    content:SetHeight(10)
    self.scroll, self.content = scroll, content

    -- Chiusura con ESC.
    if type(UISpecialFrames) == "table" then
        local present = false
        for _, n in ipairs(UISpecialFrames) do if n == FRAME_NAME then present = true end end
        if not present then table.insert(UISpecialFrames, FRAME_NAME) end
    end
    f:Hide()
    self.frame = f
    return f
end

-- Apre la libreria (e opzionalmente una guida). Nessun errore verso il chiamante.
local function openImpl(entryId, query)
    if not M or M.enabled ~= true then return nil, L["modulo Guide disattivato"] end
    local entry
    if entryId ~= nil then
        entry = lookup(entryId)
        if not entry then return nil, L["guida inesistente: "] .. shortStr(entryId) end
    end
    V:Build()
    V.frame:Show()
    if query ~= nil then V.query = type(query) == "string" and query or "" ; V.searchBox:SetText(V.query) end
    if not entry and query == nil then
        local last = G:GetLastOpened() -- "Apri libreria" riprende da dove eri rimasto
        entry = last and lookup(last) or nil
    end
    if entry then
        noteOpened(entry.gid)
        V:ShowEntry(entry.gid)
        Events:Fire("BADB_GUIDE_OPENED", entry.gid)
    else
        V:ShowWelcome()
        V:RefreshList()
    end
    return true
end

function G:Open(entryId)
    local ok, a, b = pcall(openImpl, entryId, nil)
    if not ok then
        Logger:Error(L["Guide: apertura fallita: %s"], shortStr(a))
        return nil, L["errore interno"]
    end
    if not a then Logger:Warn(L["Guide: %s"], tostring(b)) end
    return a, b
end

-- Apre la libreria con la ricerca precompilata (usato da /badb guide search).
function G:OpenLibrary(query)
    local ok, a, b = pcall(openImpl, nil, query or "")
    if not ok then
        Logger:Error(L["Guide: apertura fallita: %s"], shortStr(a))
        return nil, L["errore interno"]
    end
    return a, b
end

function G:Close()
    if V.frame then V.frame:Hide() end
end

---------------------------------------------------------------------------
-- 7. Modulo, pagina ConfigUI e comando /badb guide
---------------------------------------------------------------------------

local function listLines(list, n)
    local lines = {}
    for i = 1, min(#list, n) do lines[i] = string.format("%s  (%s)", list[i].title, list[i].id) end
    return lines
end

-- Pagina della ConfigUI v2: ricerca rapida, ultime guide, segnalibri, pulsante "Apri libreria".
local function buildPage(parent, ctx)
    local ROWS_RESULTS, ROWS_RECENT, ROWS_MARKS = 6, 5, 8
    local page = { query = "", results = {} }
    local function label(font, text)
        local fs = parent:CreateFontString(nil, "ARTWORK", font)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        return fs
    end
    local function makeRows(n)
        local rows = {}
        for i = 1, n do
            local b = CreateFrame("Button", nil, parent)
            b:SetSize(540, 20)
            b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
            b.label:SetWidth(530)
            b.label:SetJustifyH("LEFT")
            b.label:SetWordWrap(false)
            b:SetScript("OnClick", function(s) if s.id then G:Open(s.id) end end)
            rows[i] = b
        end
        return rows
    end

    page.header = label("GameFontNormalLarge", L["Libreria guide"])
    page.intro = label("GameFontHighlightSmall",
        L["Guide testuali per interfaccia, classi e contenuti. I link ai video vanno copiati e aperti nel browser."])
    page.intro:SetWidth(540)

    page.search = newFrame("EditBox", parent)
    page.search:SetSize(380, 24)
    page.search:SetAutoFocus(false)
    page.search:SetTextInsets(6, 6, 0, 0)
    if _G.ChatFontNormal then page.search:SetFontObject(_G.ChatFontNormal) end
    backdrop(page.search, { 0.05, 0.06, 0.08, 0.9 }, { 0.25, 0.28, 0.34, 1 })
    local function doSearch()
        page.query = trimStr(page.search:GetText() or "")
        page.results = page.query ~= "" and G:Search(page.query) or {}
        if page.refresh then page.refresh() end
    end
    page.search:SetScript("OnEnterPressed", function(s) s:ClearFocus(); doSearch() end)
    page.search:SetScript("OnTextChanged", function(_, user) if user then doSearch() end end)
    page.search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    local okBtn, openBtn = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not okBtn or not openBtn then openBtn = CreateFrame("Button", nil, parent) end
    openBtn:SetSize(150, 24)
    openBtn:SetText(L["Apri libreria"])
    openBtn:SetScript("OnClick", function() G:Open() end)
    page.openBtn = openBtn

    page.hResults = label("GameFontNormal", L["Risultati"])
    page.rResults = makeRows(ROWS_RESULTS)
    page.hRecent = label("GameFontNormal", L["Ultime guide"])
    page.rRecent = makeRows(ROWS_RECENT)
    page.hMarks = label("GameFontNormal", L["Segnalibri"])
    page.rMarks = makeRows(ROWS_MARKS)
    page.empty = label("GameFontDisableSmall", L["Nessun risultato."])

    local okCb, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not okCb or not cb then cb = CreateFrame("CheckButton", nil, parent) end
    cb:SetSize(24, 24)
    local cbLabel = label("GameFontHighlight", L["Suggerisci guide quando entro in una zona con guide dedicate"])
    cb:SetScript("OnClick", function(s) M:Set("autoSuggest", s:GetChecked() and true or false) end)
    page.autoSuggest = cb

    local total = 0
    local function fill(rows, list)
        for i, b in ipairs(rows) do
            local s = list[i]
            if s then
                b.id = s.id
                b.label:SetText(s.title .. paint("dim", "  " .. s.category))
                b:Show()
            else
                b.id = nil
                b:Hide()
            end
        end
    end
    function page.refresh()
        local y = 0
        local function put(obj, x, h, gap)
            obj:ClearAllPoints()
            obj:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
            y = y + h + (gap or 0)
        end
        put(page.header, 0, 26, 4)
        put(page.intro, 0, 30, 4)
        page.search:ClearAllPoints()
        page.search:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        page.openBtn:ClearAllPoints()
        page.openBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 390, -y)
        y = y + 34
        local hasQuery = page.query ~= ""
        page.hResults:SetShown(hasQuery)
        page.empty:SetShown(hasQuery and #page.results == 0)
        if hasQuery then
            put(page.hResults, 0, 18, 2)
            if #page.results == 0 then put(page.empty, 4, 18, 4) end
            fill(page.rResults, page.results)
            for i, b in ipairs(page.rResults) do
                if page.results[i] then put(b, 0, 20) end
            end
            y = y + 6
        else
            fill(page.rResults, {})
        end
        local recent = G:GetRecent(ROWS_RECENT)
        page.hRecent:SetShown(#recent > 0)
        if #recent > 0 then put(page.hRecent, 0, 18, 2) end
        fill(page.rRecent, recent)
        for i = 1, #recent do put(page.rRecent[i], 0, 20) end
        y = y + 6
        local marks = G:GetBookmarks()
        page.hMarks:SetShown(true)
        put(page.hMarks, 0, 18, 2)
        if #marks == 0 then
            fill(page.rMarks, {})
            page.noMarks = page.noMarks or label("GameFontDisableSmall", L["Nessun segnalibro: usa la stella nel lettore."])
            put(page.noMarks, 4, 18)
            page.noMarks:Show()
        else
            if page.noMarks then page.noMarks:Hide() end
            fill(page.rMarks, marks)
            for i = 1, min(#marks, ROWS_MARKS) do put(page.rMarks[i], 0, 20) end
        end
        y = y + 12
        page.autoSuggest:ClearAllPoints()
        page.autoSuggest:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        cbLabel:ClearAllPoints()
        cbLabel:SetPoint("LEFT", page.autoSuggest, "RIGHT", 2, 0)
        page.autoSuggest:SetChecked(autoSuggestEnabled())
        y = y + 30
        total = y
    end
    page.refresh()
    M._page = page
    -- altezza massima possibile (tutte le sezioni piene)
    return total + (ROWS_RESULTS + ROWS_MARKS) * 20 + 40
end

M = Badb.Modules:New("Guides", {
    title = L["Guide"],
    category = L["Contenuti"],
    defaults = { enabled = true, autoSuggest = true },
    options = {
        { type = "toggle", path = "autoSuggest", label = L["Suggerisci guide quando entri in una zona con guide dedicate"] },
        { type = "execute", label = L["Apri libreria guide"], func = function() G:Open() end },
    },
    page = {
        title = L["Guide"], order = 60, category = L["Contenuti"],
        build = buildPage,
        refresh = function() if M._page and M._page.refresh then M._page.refresh() end end,
    },
    commands = {
        guide = {
            help = L["guide [open [id]] | search <testo> | bookmarks"],
            fn = function(args)
                args = trimStr(tostring(args or ""))
                local sub, rest = args:match("^(%S*)%s*(.-)$")
                sub = (sub or ""):lower()
                if sub == "" or sub == "open" then
                    if rest ~= "" then G:Open(rest) else G:Open() end
                elseif sub == "search" then
                    if rest == "" then Logger:Info(L["Uso: /badb guide search <testo>"]); return end
                    local res = G:Search(rest)
                    if #res == 0 then
                        Logger:Info(L["Nessuna guida trovata per '%s'"], rest)
                    else
                        Logger:Info(L["%d guide trovate per '%s':"], #res, rest)
                        for _, line in ipairs(listLines(res, 5)) do Logger:Info("  %s", line) end
                        if #res > 5 then Logger:Info(L["  ... altre %d nella libreria"], #res - 5) end
                    end
                    G:OpenLibrary(rest)
                elseif sub == "bookmarks" or sub == "segnalibri" then
                    local list = G:GetBookmarks()
                    if #list == 0 then
                        Logger:Info(L["Nessun segnalibro."])
                    else
                        for _, line in ipairs(listLines(list, 20)) do Logger:Info("  %s", line) end
                    end
                else
                    -- un id di guida passato direttamente
                    if lookup(args) then G:Open(args)
                    else Logger:Info(L["/badb guide [open [id]] | search <testo> | bookmarks"]) end
                end
            end,
        },
    },
})

function M:OnInitialize()
    store() -- normalizza la struttura salvata
end

function M:OnEnable()
    G:Cleanup()
    self:On("PLAYER_ENTERING_WORLD", function() G:CheckZone() end)
    self:On("ZONE_CHANGED_NEW_AREA", function() G:CheckZone() end)
    self:On("PLAYER_REGEN_ENABLED", function()
        if pendingSuggest then G:CheckZone() end
    end)
end

function M:OnDisable()
    if V.frame then V.frame:Hide() end
    pendingSuggest = false
end

G.module = M
