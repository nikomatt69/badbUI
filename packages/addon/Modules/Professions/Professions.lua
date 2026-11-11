-- Professioni del personaggio e tempi di recupero configurati dall'utente.
-- Solo API sondate del client: nessuna ricetta o database inventato.
local _, ns = ...
local Badb = ns.Badb
local L, Compat, Logger = Badb.L, Badb.Compat, Badb.Logger

local MAX_SPELLS, MAX_PROFS, MAX_CHARS = 20, 12, 50

local M = Badb.Modules:New("Professions", {
    title = L["Professioni"],
    category = L["Gioco"],
    description = L["Gradi delle professioni del personaggio e tempi di recupero che configuri."],
    defaults = { enabled = true, cooldownSpells = "" },
    replaces = {},
})
Badb.Professions = M

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return Compat.SafeValue(a), Compat.SafeValue(b), Compat.SafeValue(c), Compat.SafeValue(d)
end
local function isInt(v, lo, hi)
    return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end
local function now()
    local t = call(GetServerTime) or call(GetTime)
    return isInt(t, 0, math.huge) and t or 0
end
local function charKey()
    if Badb.DB and type(Badb.DB.char) == "string" and Badb.DB.char ~= "" then return Badb.DB.char end
    local name, realm = call(UnitName, "player"), call(GetRealmName)
    if type(name) == "string" and name ~= "" then return name .. " - " .. (type(realm) == "string" and realm or "?") end
    return nil
end

function M:HasProfessionAPI()
    return type(GetProfessions) == "function" and type(GetProfessionInfo) == "function"
end
function M:HasCooldownAPI()
    return type(GetSpellCooldown) == "function" and type(GetTime) == "function"
end

-- Ritorna lista { index, name, rank, maxRank } oppure nil se API assente.
function M:ReadProfessions()
    if not self:HasProfessionAPI() then return nil end
    local out, seen = {}, {}
    local indexes = { call(GetProfessions) }
    -- GetProfessions ritorna piu' valori (primarie, secondarie...): li raccogliamo via pcall diretto.
    if type(GetProfessions) == "function" then
        local ok, a, b, c, d, e, f = pcall(GetProfessions)
        if ok then indexes = { Compat.SafeValue(a), Compat.SafeValue(b), Compat.SafeValue(c), Compat.SafeValue(d), Compat.SafeValue(e), Compat.SafeValue(f) } end
    end
    for _, idx in ipairs(indexes) do
        if isInt(idx, 1, 999) and not seen[idx] then
            seen[idx] = true
            local name, _, rank, maxRank = call(GetProfessionInfo, idx)
            if type(name) == "string" and name ~= "" and isInt(rank, 0, 100000) then
                out[#out + 1] = { index = idx, name = name:sub(1, 64), rank = rank,
                    maxRank = isInt(maxRank, 0, 100000) and maxRank or nil }
                if #out >= MAX_PROFS then break end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function M:GetStore()
    if not (Badb.DB and Badb.DB.GetStore) then return nil end
    local store = Badb.DB:GetStore("professions")
    if type(store) ~= "table" then return nil end
    if store.version ~= 1 then store.version = 1 end
    if type(store.characters) ~= "table" then store.characters = {} end
    return store
end

-- Salva lo snapshot del personaggio corrente. Ritorna snapshot o nil,err.
function M:Capture()
    local list = self:ReadProfessions()
    if not list then return nil, L["Professioni non disponibili su questo client."] end
    local key, store = charKey(), self:GetStore()
    if not key or not store then return nil, L["Personaggio non disponibile."] end
    local snap = { version = 1, at = now(), professions = list }
    store.characters[key] = snap
    -- Limite personaggi: rimuovi i piu' vecchi.
    local keys = {}
    for k in pairs(store.characters) do keys[#keys + 1] = k end
    if #keys > MAX_CHARS then
        table.sort(keys, function(a, b)
            local ta = type(store.characters[a]) == "table" and store.characters[a].at or 0
            local tb = type(store.characters[b]) == "table" and store.characters[b].at or 0
            return (type(ta) == "number" and ta or 0) < (type(tb) == "number" and tb or 0)
        end)
        for i = 1, #keys - MAX_CHARS do store.characters[keys[i]] = nil end
    end
    self.snapshot = snap
    return snap
end

function M:GetSnapshot()
    local store, key = self:GetStore(), charKey()
    if store and key and type(store.characters[key]) == "table" then
        local s = store.characters[key]
        if type(s.professions) == "table" then return s end
    end
    return self.snapshot
end

function M.ParseSpellIDs(text)
    local out, seen = {}, {}
    if type(text) ~= "string" then return out end
    for token in text:gmatch("[^,%s;]+") do
        local id = tonumber(token)
        if isInt(id, 1, 9999999) and not seen[id] then
            seen[id] = true; out[#out + 1] = id
            if #out >= MAX_SPELLS then break end
        end
    end
    return out
end
function M.FormatSpellIDs(ids)
    local parts = {}
    for _, id in ipairs(ids or {}) do parts[#parts + 1] = tostring(id) end
    return table.concat(parts, ",")
end
function M:GetSpellIDs() return M.ParseSpellIDs(self:Get("cooldownSpells")) end

function M:AddSpell(id)
    if not isInt(id, 1, 9999999) then return false end
    local ids = self:GetSpellIDs()
    for _, v in ipairs(ids) do if v == id then return true end end
    if #ids >= MAX_SPELLS then return false end
    ids[#ids + 1] = id
    self:Set("cooldownSpells", M.FormatSpellIDs(ids))
    return true
end
function M:RemoveSpell(id)
    local ids, found = {}, false
    for _, v in ipairs(self:GetSpellIDs()) do
        if v == id then found = true else ids[#ids + 1] = v end
    end
    if found then self:Set("cooldownSpells", M.FormatSpellIDs(ids)) end
    return found
end

-- { spellID, name, remaining, duration, ready } o nil se API/valori non utilizzabili.
function M:GetCooldown(spellID)
    if not isInt(spellID, 1, 9999999) or not self:HasCooldownAPI() then return nil end
    local start, duration = call(GetSpellCooldown, spellID)
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    local t = call(GetTime)
    if type(t) ~= "number" then return nil end
    local name = call(GetSpellInfo, spellID)
    if type(name) ~= "string" then name = nil end
    local remaining = 0
    if duration > 0 and start > 0 then remaining = math.max(0, math.floor(start + duration - t)) end
    return { spellID = spellID, name = name, remaining = remaining, duration = duration, ready = remaining <= 0 }
end
function M:GetCooldowns()
    local out = {}
    for _, id in ipairs(self:GetSpellIDs()) do
        local cd = self:GetCooldown(id)
        if cd then out[#out + 1] = cd end
    end
    return out
end

function M.FormatRemaining(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return L["Pronto"] end
    seconds = math.floor(seconds)
    local h, m, s = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

function M:SummaryLines()
    local lines = {}
    if not self:HasProfessionAPI() then
        lines[#lines + 1] = L["Professioni non disponibili su questo client."]
        return lines
    end
    local snap = self:GetSnapshot()
    if not snap or #snap.professions == 0 then
        lines[#lines + 1] = L["Nessuna professione rilevata per questo personaggio."]
    else
        for _, p in ipairs(snap.professions) do
            if type(p) == "table" and type(p.name) == "string" and isInt(p.rank, 0, 100000) then
                local line = p.name .. ": " .. tostring(p.rank)
                if isInt(p.maxRank, 0, 100000) then line = line .. "/" .. tostring(p.maxRank) end
                lines[#lines + 1] = line
            end
        end
    end
    if #self:GetSpellIDs() == 0 then
        lines[#lines + 1] = L["Nessun tempo di recupero configurato. Usa /badb prof add <ID incantesimo>."]
    elseif not self:HasCooldownAPI() then
        lines[#lines + 1] = L["Tempi di recupero non disponibili su questo client."]
    else
        for _, cd in ipairs(self:GetCooldowns()) do
            lines[#lines + 1] = (cd.name or ("#" .. tostring(cd.spellID))) .. ": " .. M.FormatRemaining(cd.remaining)
        end
    end
    return lines
end

-- Pagina ---------------------------------------------------------------
local pageState
function M:RefreshPage()
    if pageState and pageState.render then pageState.render() end
end
local function buildPage(parent, ctx)
    local UI, Theme = Badb.UI, Badb.Theme
    local stack = UI:Stack(parent)
    stack:Add(UI:SectionHeader(parent, L["Professioni"]), Theme.sizes.button)
    local body = UI:Label(parent, "", "small", "textDim"); body:SetWordWrap(true)
    stack:Add(body, Theme.sizes.header * 3)
    local addBtn = UI:Button(parent, L["Aggiorna"], nil, nil, function()
        M:Capture(); M:RefreshPage()
    end)
    stack:Add(addBtn, Theme.sizes.button)
    local hint = UI:Label(parent, L["Aggiungi un tempo di recupero con /badb prof add <ID incantesimo>. Rimuovilo con /badb prof remove <ID incantesimo>."], "small", "textDim")
    hint:SetWordWrap(true)
    stack:Add(hint, Theme.sizes.header)
    pageState = { render = function()
        if not M:HasProfessionAPI() then body:SetText(L["Professioni non disponibili su questo client."]) return end
        body:SetText(table.concat(M:SummaryLines(), "\n"))
    end }
    pageState.render()
    return stack:Height()
end

function M:OnInitialize()
    self:GetStore()
end
function M:OnEnable()
    self.active = true
    self:Capture()
    self:On("SKILL_LINES_CHANGED", function() self:Capture(); self:RefreshPage() end)
    self:On("PLAYER_LOGOUT", function() self:Capture() end)
end
function M:OnDisable()
    self.active = false
end
function M:OnProfileChanged()
    self:RefreshPage()
end

M.page = {
    title = L["Professioni"], order = 85, category = L["Gioco"],
    keywords = { L["Professioni"], "professions", L["tempi di recupero"] },
    build = buildPage,
    refresh = function() M:RefreshPage() end,
}
M.options = {
    { type = "execute", label = L["Aggiorna professioni"], func = function() M:Capture(); M:RefreshPage() end },
}

local function handleProf(args)
    args = type(args) == "string" and args or ""
    local cmd, rest = args:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "open" then
        if Badb.ConfigUI then Badb.ConfigUI:OpenPage(M.name) end
        return
    elseif cmd == "list" or cmd == "show" then
        M:Capture()
        for _, line in ipairs(M:SummaryLines()) do Logger:Info("%s", line) end
    elseif cmd == "refresh" then
        local snap, err = M:Capture()
        if snap then Logger:Info("%s", L["Professioni aggiornate."]) else Logger:Warn("%s", err) end
        M:RefreshPage()
    elseif cmd == "add" then
        local id = tonumber(rest)
        if not isInt(id, 1, 9999999) then Logger:Warn("%s", L["ID incantesimo non valido."]) return end
        if M:AddSpell(id) then Logger:Info("%s", string.format(L["Tempo di recupero aggiunto: %d."], id))
        else Logger:Warn("%s", L["Elenco dei tempi di recupero pieno."]) end
        M:RefreshPage()
    elseif cmd == "remove" or cmd == "del" then
        local id = tonumber(rest)
        if not isInt(id, 1, 9999999) or not M:RemoveSpell(id) then Logger:Warn("%s", L["ID incantesimo non presente."]) return end
        Logger:Info("%s", string.format(L["Tempo di recupero rimosso: %d."], id))
        M:RefreshPage()
    elseif cmd == "clear" then
        M:Set("cooldownSpells", "")
        Logger:Info("%s", L["Tempi di recupero rimossi."])
        M:RefreshPage()
    else
        Logger:Info("%s", L["Uso: /badb prof [list|add <ID>|remove <ID>|clear|refresh]"])
    end
end
M.commands = {
    prof = { help = L["prof - professioni e tempi di recupero configurati"], fn = handleProf },
    professions = { help = L["prof - professioni e tempi di recupero configurati"], fn = handleProf },
}

if Badb.Guides and Badb.Guides.Register then
    local ok = pcall(Badb.Guides.Register, Badb.Guides, {
        id = "professions", title = L["Professioni"], category = "BadbUI", version = 1, author = "BadbUI",
        entries = { {
            id = "overview", title = L["Professioni e tempi di recupero con BadbUI"],
            tags = { L["Professioni"] }, confidence = "B",
            body = {
                { type = "step", text = L["Apri /badb prof per vedere gradi e tempi di recupero."] },
                { type = "step", text = L["Aggiungi un incantesimo con /badb prof add <ID incantesimo>. BadbUI mostra solo il tempo restante letto dal client."] },
                { type = "warn", text = L["Da verificare in gioco: la disponibilità delle azioni dipende dalle API del client Forever."] },
            },
        } },
    })
    if not ok then Logger:Debug("Professions guide registration failed") end
end
