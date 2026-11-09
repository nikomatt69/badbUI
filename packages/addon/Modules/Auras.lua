-- BadbUI - Auras
-- Motore condiviso delle "aure curate": classifica le aure di un'unita' (CC, immunita', difensivi...)
-- e offre widget icona pronti. Lo usano NameplateAuras, Alerts e chiunque voglia mostrare aure
-- (unit frame, group frame): API pubblica `Badb.Auras`, documentata in docs/auras.md.
--
-- Regole Forever (docs/FOREVER_FACTS.md):
--   * Niente combat log: tutto passa dalle API aure (C_UnitAuras / UnitAura), che il client espone.
--   * Secret values: in combattimento spellId, nome, durata e stack possono essere opachi. Un valore
--     secret non si confronta, non si usa come chiave di tabella e non entra in aritmetica, ma si puo'
--     passare ai widget (SetTexture, SetCooldown...). Quindi: classificazione solo su valori leggibili,
--     poi ripiego sui filtri aure del client se il client li offre (sondati, mai presunti), e il
--     disegno (icona, countdown) lasciato al client.
local _, ns = ...
local Badb = ns.Badb
local Compat, Events, Logger = Badb.Compat, Badb.Events, Badb.Logger
local Data = Badb.AuraData

local IsSecret = Compat.IsSecret
local MAX_AURAS = 40 -- limite di sicurezza per ogni passata di lettura

local A = Badb.Modules:New("Auras", {
    title = "Aure curate",
    category = "Combattimento",
    description = "Database delle aure importanti condiviso da nameplate, avvisi e frame.",
    defaults = {
        enabled = true,       -- nessun effetto visivo da solo: e' il database usato dagli altri moduli
        matchByName = true,   -- riconosce anche i rank nuovi di Forever tramite nome localizzato
        clientFilters = true, -- con dati secret usa i filtri aure del client, se esistono
        custom = {},          -- [ "id" | "nome minuscolo" ] = categoria | "hide"
        priorities = {},      -- [categoria] = priorita' personalizzata
    },
})
Badb.Auras = A

------------------------------------------------------------------------------
-- Categorie
------------------------------------------------------------------------------
A.categories = {}   -- [key] = def
A.categoryOrder = {}
for i, c in ipairs(Data.CATEGORIES) do
    A.categories[c.key] = c
    A.categoryOrder[i] = c.key
end

function A:GetCategory(key) return self.categories[key] end

function A:GetPriority(key)
    local c = self.categories[key]
    if not c then return 0 end
    local custom = Badb.DB.profile and self:Get("priorities")
    local p = type(custom) == "table" and tonumber(custom[key])
    return p or c.priority
end

function A:GetColor(key)
    local c = self.categories[key]
    if c then return c.color[1], c.color[2], c.color[3] end
    return 0.5, 0.5, 0.5
end

------------------------------------------------------------------------------
-- Indice (ID e nomi localizzati)
------------------------------------------------------------------------------
local function spellName(id)
    local ok, name
    if C_Spell and C_Spell.GetSpellName then
        ok, name = pcall(C_Spell.GetSpellName, id)
    elseif GetSpellInfo then
        ok, name = pcall(GetSpellInfo, id)
    end
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then return name end
end
A._spellName = spellName

local function lower(s) return string.lower(s) end

-- Normalizza una chiave utente: numero -> "123", testo -> minuscolo senza spazi ai lati.
function A:NormalizeKey(key)
    if type(key) == "number" then return tostring(math.floor(key)) end
    if type(key) ~= "string" then return nil end
    key = strtrim(key)
    if key == "" then return nil end
    if key:match("^%d+$") then return tostring(tonumber(key)) end
    return lower(key)
end

function A:BuildIndex()
    local byId, byName, classIds, className = {}, {}, {}, {}
    local useNames = self:Get("matchByName") ~= false
    for _, key in ipairs(self.categoryOrder) do
        for _, fam in ipairs(Data.SPELLS[key] or {}) do
            for _, id in ipairs(fam) do
                if not byId[id] then byId[id] = key end
            end
            if useNames and not fam.noName then
                local n = spellName(fam[1])
                if n and not byName[lower(n)] then byName[lower(n)] = key end
            end
        end
    end
    for class, fams in pairs(Data.CLASS_DEBUFFS) do
        local ids, names = {}, {}
        for _, fam in ipairs(fams) do
            for _, id in ipairs(fam) do ids[id] = true end
            if useNames and not fam.noName then
                local n = spellName(fam[1])
                if n then names[lower(n)] = true end
            end
        end
        classIds[class], className[class] = ids, names
    end
    self.byId, self.byName, self.classIds, self.className = byId, byName, classIds, className
    self.indexBuilt = true
end

local function ensureIndex(self)
    if not self.indexBuilt then self:BuildIndex() end
end

------------------------------------------------------------------------------
-- Filtri aure del client (ripiego per dati secret)
------------------------------------------------------------------------------
-- Client recenti espongono in AuraUtil.AuraFilters filtri come CROWD_CONTROL o BIG_DEFENSIVE.
-- Li usiamo SOLO se la costante esiste: un filtro sconosciuto potrebbe essere ignorato dal client
-- e restituire tutte le aure, quindi non si prova mai una stringa "a caso".
A.CLIENT_FILTERS = {
    { field = "CrowdControl", category = "cc", harmful = true },
    { field = "BigDefensive", category = "defensive", harmful = false },
    { field = "ExternalDefensive", category = "defensive", harmful = false },
}

function A:ProbeClientFilters()
    local list = {}
    local F = AuraUtil and type(AuraUtil.AuraFilters) == "table" and AuraUtil.AuraFilters
    if F then
        for _, def in ipairs(self.CLIENT_FILTERS) do
            local token = F[def.field]
            if type(token) == "string" and token ~= "" and not IsSecret(token) then
                list[#list + 1] = { token = token, category = def.category, harmful = def.harmful }
            end
        end
    end
    self.clientFilterList = list
    return list
end

------------------------------------------------------------------------------
-- Lettura aure (C_UnitAuras con ripiego su UnitAura)
------------------------------------------------------------------------------
local function isNil(v) return type(v) == "nil" end

function A:GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if ok and type(data) == "table" then return data end
        return nil
    end
    if UnitAura then
        local ok, name, icon, count, dispelType, duration, expirationTime, source, _, _, spellId =
            pcall(UnitAura, unit, index, filter)
        if not ok or isNil(name) then return nil end
        return {
            name = name, icon = icon, applications = count, dispelName = dispelType,
            duration = duration, expirationTime = expirationTime, sourceUnit = source, spellId = spellId,
            isHarmful = filter:find("HARMFUL") ~= nil, isHelpful = filter:find("HELPFUL") ~= nil,
        }
    end
end

function A:HasAuraAPI()
    return (C_UnitAuras ~= nil and C_UnitAuras.GetAuraDataByIndex ~= nil) or UnitAura ~= nil
end

-- Iteratore sicuro: for i, aura in A:IterAuras(unit, "HARMFUL") do ... end
function A:IterAuras(unit, filter)
    local i = 0
    return function()
        i = i + 1
        if i > MAX_AURAS then return nil end
        local data = self:GetAura(unit, i, filter)
        if data then return i, data end
    end
end

------------------------------------------------------------------------------
-- Classificazione
------------------------------------------------------------------------------
local function readable(v, t)
    return not isNil(v) and not IsSecret(v) and type(v) == t
end

-- Restituisce la categoria di un'aura ("cc", "defensive"...) o nil. `hidden` = true se l'utente l'ha nascosta.
-- Secondo valore: "id" | "name" | "custom" | "secret" (come e' stata decisa / perche' no).
function A:Classify(aura)
    if type(aura) ~= "table" then return nil end
    ensureIndex(self)
    local custom = self:Get("custom") or {}
    local id, name = aura.spellId, aura.name
    local idOk, nameOk = readable(id, "number"), readable(name, "string")
    if idOk then
        local c = custom[tostring(id)]
        if c == "hide" then return nil, "hidden" end
        if c and self.categories[c] then return c, "custom" end
    end
    local lname = nameOk and lower(name) or nil
    if lname then
        local c = custom[lname]
        if c == "hide" then return nil, "hidden" end
        if c and self.categories[c] then return c, "custom" end
    end
    if idOk and self.byId[id] then return self.byId[id], "id" end
    if lname and self.byName[lname] then return self.byName[lname], "name" end
    if IsSecret(id) or IsSecret(name) then return nil, "secret" end
    return nil
end

-- L'aura e' stata applicata dal giocatore (o dal suo pet)? nil se non si puo' sapere.
function A:IsOwn(aura)
    local f = aura.isFromPlayerOrPlayerPet
    if readable(f, "boolean") then return f end
    local src = aura.sourceUnit
    if readable(src, "string") then return src == "player" or src == "pet" or src == "vehicle" end
    return nil
end

-- Debuff curato per la classe del giocatore?
function A:IsClassDebuff(aura, class)
    ensureIndex(self)
    class = class or (Badb.Player and Badb.Player:GetClass())
    local ids, names = self.classIds[class or ""], self.className[class or ""]
    if not ids then return false end
    local custom = self:Get("custom") or {}
    local id, name = aura.spellId, aura.name
    if readable(id, "number") then
        if custom[tostring(id)] == "hide" then return false end
        if ids[id] then return true end
    end
    if readable(name, "string") then
        local l = lower(name)
        if custom[l] == "hide" then return false end
        if names[l] then return true end
    end
    return false
end

------------------------------------------------------------------------------
-- Raccolta
------------------------------------------------------------------------------
local function wanted(set, key) return set == nil or set[key] == true end

local function instanceKey(aura)
    local k = aura.auraInstanceID
    if readable(k, "number") then return k end
end

--[[ opts:
    helpful, harmful   = bool (default true entrambi)
    categories         = set { cc = true, ... } o nil per tutte
    own                = "off" | "curated" | "all": include anche i debuff propri non curati ("own")
    class              = token classe per "curated" (default classe del giocatore)
    max                = numero massimo di voci (default illimitato)
  Ritorna un array ordinato per priorita' di voci { aura, category, priority, own, filter, index, via }.
  category == "own" per i debuff propri non classificati altrimenti.
]]
function A:Collect(unit, opts)
    opts = opts or {}
    local out, byInstance, unresolved = {}, {}, false
    if type(unit) ~= "string" or not self:HasAuraAPI() then return out end
    local ownMode = opts.own or "off"
    local passes = {}
    if opts.helpful ~= false then passes[#passes + 1] = "HELPFUL" end
    if opts.harmful ~= false then passes[#passes + 1] = "HARMFUL" end

    for _, filter in ipairs(passes) do
        local harmful = filter == "HARMFUL"
        for index, aura in self:IterAuras(unit, filter) do
            local cat, via = self:Classify(aura)
            local own = harmful and self:IsOwn(aura) or false
            local entry
            if cat and wanted(opts.categories, cat) then
                entry = { aura = aura, category = cat, priority = self:GetPriority(cat), own = own == true,
                    filter = filter, index = index, via = via }
            elseif harmful and own == true and ownMode ~= "off" and via ~= "hidden" and not cat then
                local curated = self:IsClassDebuff(aura, opts.class)
                -- Con dati secret non si puo' verificare la whitelist: si mostra comunque (meglio
                -- un debuff in piu' che perdere i propri DoT in combattimento).
                if ownMode == "all" or curated or via == "secret" then
                    entry = { aura = aura, category = "own", priority = curated and 25 or 10, own = true,
                        filter = filter, index = index, via = via or (curated and "class") }
                end
            end
            if via == "secret" and not entry then unresolved = true end
            if entry then
                out[#out + 1] = entry
                local k = instanceKey(aura)
                if k then byInstance[k] = entry end
            elseif via == "secret" then
                local k = instanceKey(aura)
                if k then byInstance[k] = false end
            end
        end
    end

    -- Ripiego: aure non leggibili -> filtri del client (solo se esistono davvero).
    if unresolved and self:Get("clientFilters") ~= false then
        for _, cf in ipairs(self.clientFilterList or self:ProbeClientFilters()) do
            local base = cf.harmful and "HARMFUL" or "HELPFUL"
            if wanted(opts.categories, cf.category) and ((cf.harmful and opts.harmful ~= false) or (not cf.harmful and opts.helpful ~= false)) then
                for index, aura in self:IterAuras(unit, base .. "|" .. cf.token) do
                    local k = instanceKey(aura)
                    local existing = k and byInstance[k]
                    if existing then
                        if existing.category == "own" then
                            existing.category, existing.priority, existing.via = cf.category, self:GetPriority(cf.category), "client"
                        end
                    elseif existing == false or k == nil then
                        local entry = { aura = aura, category = cf.category, priority = self:GetPriority(cf.category),
                            own = false, filter = base, index = index, via = "client" }
                        out[#out + 1] = entry
                        if k then byInstance[k] = entry end
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.filter ~= b.filter then return a.filter == "HARMFUL" end
        return a.index < b.index
    end)
    if opts.max and #out > opts.max then
        for i = #out, opts.max + 1, -1 do out[i] = nil end
    end
    return out
end

-- Voce con priorita' piu' alta tra le categorie richieste (set o lista), o nil.
function A:GetHighest(unit, categories, opts)
    local set = categories
    if type(categories) == "table" and categories[1] then
        set = {}
        for _, k in ipairs(categories) do set[k] = true end
    end
    local o = { categories = set, max = 1 }
    if opts then for k, v in pairs(opts) do o[k] = v end end
    local list = self:Collect(unit, o)
    return list[1]
end

function A:IsCrowdControlled(unit, includeSilence)
    return self:GetHighest(unit, includeSilence and { "cc", "silence" } or { "cc" }, { helpful = false })
end

------------------------------------------------------------------------------
-- Widget icona (riusabile da nameplate, unit frame, avvisi)
------------------------------------------------------------------------------
function A:CreateIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size or 24, size or 24)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    if f.cd.SetReverse then f.cd:SetReverse(true) end
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, 0)
    f.isBadbAuraIcon = true
    f:Hide()
    return f
end

local function setCooldown(cd, aura, unit, showNumbers)
    if not cd then return false end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not showNumbers) end
    local dur, exp = aura.duration, aura.expirationTime
    if IsSecret(dur) or IsSecret(exp) then
        -- Il client disegna il countdown da solo: niente aritmetica sui valori opachi.
        local id = aura.auraInstanceID
        if C_UnitAuras and C_UnitAuras.GetAuraDuration and cd.SetCooldownFromDurationObject and unit and not isNil(id) then
            local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, id)
            if ok and obj and pcall(cd.SetCooldownFromDurationObject, cd, obj) then cd:Show(); return true end
        end
        if cd.SetCooldownFromExpirationTime and pcall(cd.SetCooldownFromExpirationTime, cd, exp, dur) then
            cd:Show(); return true
        end
        cd:Hide()
        return false
    end
    if type(dur) == "number" and type(exp) == "number" and dur > 0 and exp > 0 then
        cd:SetCooldown(exp - dur, dur)
        cd:Show()
        return true
    end
    if cd.Clear then cd:Clear() end
    cd:Hide()
    return false
end

local function setCount(fs, aura, unit)
    if not fs then return end
    local n = aura.applications
    if IsSecret(n) then
        local id = aura.auraInstanceID
        if C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount and unit and not isNil(id) then
            local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2, 99)
            if ok then fs:SetText(txt); return end
        end
        fs:SetText("")
    elseif type(n) == "number" and n > 1 then
        fs:SetText(tostring(n))
    else
        fs:SetText("")
    end
end

-- Mostra una voce di Collect nell'icona. opts = { size, numbers = bool, border = bool }
function A:SetIcon(f, entry, unit, opts)
    opts = opts or {}
    local aura = entry.aura
    f.icon:SetTexture(aura.icon)
    if opts.size then f:SetSize(opts.size, opts.size) end
    if f.SetBackdropBorderColor then
        if opts.border == false then f:SetBackdropBorderColor(0, 0, 0, 1)
        elseif entry.category == "own" then f:SetBackdropBorderColor(0, 0, 0, 1)
        else f:SetBackdropBorderColor(self:GetColor(entry.category)) end
    end
    setCooldown(f.cd, aura, unit, opts.numbers ~= false)
    setCount(f.count, aura, unit)
    f.entry, f.unit = entry, unit
    f:Show()
end

function A:ClearIcon(f)
    if not f then return end
    f.entry, f.unit = nil, nil
    if f.cd and f.cd.Clear then f.cd:Clear() end
    f:Hide()
end

------------------------------------------------------------------------------
-- Personalizzazione (lista utente)
------------------------------------------------------------------------------
-- Imposta la categoria di un'aura (ID o nome). category = chiave categoria | "hide" | nil (rimuove).
function A:SetCustom(key, category)
    local k = self:NormalizeKey(key)
    if not k then return false, "serve un ID numerico o un nome" end
    if category ~= nil and category ~= "hide" and not self.categories[category] then
        return false, "categoria sconosciuta: " .. tostring(category)
    end
    local custom = self:Get("custom")
    if type(custom) ~= "table" then custom = {}; self:Set("custom", custom) end
    custom[k] = category
    Events:Fire("BADB_OPTION_CHANGED", self.name, "custom", custom)
    return true
end

function A:ListCustom()
    local list = {}
    for k, v in pairs(self:Get("custom") or {}) do
        local id = tonumber(k)
        list[#list + 1] = { key = k, category = v, label = id and (spellName(id) or ("#" .. k)) or k }
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

function A:ResetCustom()
    self:Set("custom", {})
    return true
end

-- Spiega come verrebbe trattata un'aura (per /badb aura check).
function A:Explain(key)
    local k = self:NormalizeKey(key)
    if not k then return nil end
    local id = tonumber(k)
    local fake = { spellId = id, name = id and spellName(id) or k }
    local cat, via = self:Classify(fake)
    return cat, via, fake.name
end

------------------------------------------------------------------------------
-- Ciclo di vita, opzioni, comandi
------------------------------------------------------------------------------
local function categoryValues(withHide)
    local v = {}
    for _, key in ipairs(A.categoryOrder) do v[#v + 1] = { value = key, text = A.categories[key].title } end
    if withHide then v[#v + 1] = { value = "hide", text = "Nascondi sempre" } end
    return v
end
A.CategoryValues = categoryValues

A._form = { key = "", category = "cc" }
A.options = {
    { type = "header", label = "Riconoscimento" },
    { type = "toggle", path = "matchByName", label = "Riconosci anche per nome (rank nuovi di Forever)" },
    { type = "toggle", path = "clientFilters", label = "In combattimento usa i filtri del client se i dati sono nascosti" },
    { type = "header", label = "Aure personalizzate" },
    { type = "text", label = "ID o nome dell'aura", width = 220,
      get = function() return A._form.key end, set = function(v) A._form.key = v end },
    { type = "select", label = "Categoria", values = function() return categoryValues(true) end,
      get = function() return A._form.category end, set = function(v) A._form.category = v end },
    { type = "execute", label = "Aggiungi", func = function()
        local ok, err = A:SetCustom(A._form.key, A._form.category)
        if not ok then Logger:Warn("Aure: %s", tostring(err)) else A._form.key = "" end
    end },
    { type = "list", label = "Elenco personale", height = 160, empty = "Nessuna aura personalizzata.",
      items = function()
        local rows = {}
        for _, e in ipairs(A:ListCustom()) do
            local cat = A.categories[e.category]
            rows[#rows + 1] = { text = e.label, detail = cat and cat.title or "Nascosta",
                actions = { { label = "Rimuovi", func = function() A:SetCustom(e.key, nil) end } } }
        end
        return rows
      end },
    { type = "execute", label = "Svuota elenco", func = function() A:ResetCustom() end },
}

local HELP = "aura status | list | add <id|nome> <categoria|hide> | remove <id|nome> | check <id|nome> | categories | reset"

-- Stato del motore sul client corrente: utile per verificare in gioco cosa espone Forever.
function A:Status()
    ensureIndex(self)
    local ids, names = 0, 0
    for _ in pairs(self.byId) do ids = ids + 1 end
    for _ in pairs(self.byName) do names = names + 1 end
    local filters = {}
    for _, f in ipairs(self.clientFilterList or self:ProbeClientFilters()) do filters[#filters + 1] = f.token end
    local api = (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and "C_UnitAuras" or (UnitAura and "UnitAura") or "nessuna"
    return { api = api, ids = ids, names = names, clientFilters = filters,
        durationObject = C_UnitAuras ~= nil and C_UnitAuras.GetAuraDuration ~= nil }
end

local function catByWord(word)
    word = word and lower(word) or ""
    if word == "hide" or word == "nascondi" then return "hide" end
    if A.categories[word] then return word end
end

A.commands = {
    aura = {
        help = HELP,
        fn = function(args)
            local sub, rest = strtrim(tostring(args or "")):match("^(%S*)%s*(.-)$")
            sub = lower(sub or "")
            if sub == "status" then
                local st = A:Status()
                Logger:Info("API aure: %s; aure curate: %d ID, %d nomi localizzati", st.api, st.ids, st.names)
                Logger:Info("Filtri del client per dati nascosti: %s; durate nascoste disegnate dal client: %s",
                    #st.clientFilters > 0 and table.concat(st.clientFilters, ", ") or "nessuno",
                    st.durationObject and "si'" or "no")
            elseif sub == "list" then
                local list = A:ListCustom()
                if #list == 0 then Logger:Info("Nessuna aura personalizzata.") end
                for _, e in ipairs(list) do Logger:Info("%s -> %s", e.label, e.category) end
            elseif sub == "add" then
                -- l'ultima parola e' la categoria; il resto e' ID o nome (anche con spazi)
                local key, word = rest:match("^(.-)%s+(%S+)$")
                local cat = catByWord(word)
                if not key or not cat then
                    Logger:Info("Uso: /badb aura add <id|nome> <categoria|hide>. Categorie: %s",
                        table.concat(A.categoryOrder, ", "))
                    return
                end
                local ok, err = A:SetCustom(key, cat)
                Logger:Info(ok and "Aura aggiornata." or ("Errore: " .. tostring(err)))
            elseif sub == "remove" then
                local ok, err = A:SetCustom(rest, nil)
                Logger:Info(ok and "Aura rimossa dall'elenco personale." or ("Errore: " .. tostring(err)))
            elseif sub == "check" then
                local cat, via, name = A:Explain(rest)
                if not name then Logger:Info("Uso: /badb aura check <id|nome>") return end
                Logger:Info("%s: %s%s", tostring(name), cat and A.categories[cat].title or "non curata",
                    via and (" (" .. via .. ")") or "")
            elseif sub == "categories" then
                for _, key in ipairs(A.categoryOrder) do
                    Logger:Info("%s - %s (priorita' %d)", key, A.categories[key].title, A:GetPriority(key))
                end
            elseif sub == "reset" then
                A:ResetCustom()
                Logger:Info("Elenco personale svuotato.")
            else
                Logger:Info("/badb " .. HELP)
            end
        end,
    },
}

function A:OnEnable()
    self:BuildIndex()
    self:ProbeClientFilters()
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module ~= self.name then return end
        if path == "matchByName" then self:BuildIndex() end
        if path == "clientFilters" then self:ProbeClientFilters() end
        Events:Fire("BADB_AURAS_CHANGED")
    end)
    -- I nomi degli incantesimi possono non essere ancora in cache al login: si ricostruisce dopo.
    self:On("PLAYER_ENTERING_WORLD", function() self:BuildIndex(); Events:Fire("BADB_AURAS_CHANGED") end)
end

function A:OnProfileChanged()
    self:BuildIndex()
    Events:Fire("BADB_AURAS_CHANGED")
end

function A:OnDisable()
    -- Il database resta consultabile (gli altri moduli lo usano): si spegne solo la ricostruzione.
end
