-- BadbUI - Alerts
-- Avviso centrale quando l'healer del tuo gruppo (o il tuo focus amico) finisce in CC.
-- Basato solo sulle aure (Badb.Auras): niente combat log, che su Forever non esiste.
--   * Healer = ruolo di gruppo assegnato "HEALER" oppure nomi scelti da te (/badb alert healer add <nome>).
--     Su Forever i ruoli di gruppo possono mancare: per questo l'elenco manuale.
--   * Nomi e aure possono essere secret in istanza: il nome va al widget senza concatenazioni,
--     i nomi manuali si confrontano solo se leggibili.
--   * Di default attivo solo nei campi di battaglia (instanceType "pvp").
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat, Auras, Logger = Badb.Compat, Badb.Auras, Badb.Logger
local SafeValue = Compat.SafeValue

local WHEN = {
    { value = "pvp", text = L["Solo campi di battaglia"] },
    { value = "instance", text = L["In qualunque istanza"] },
    { value = "group", text = L["Sempre, se in gruppo"] },
    { value = "always", text = L["Sempre"] },
}
local MAX_ROWS = 3
local SOUND_THROTTLE = 1.5
local TEST_SECONDS = 6

local M = Badb.Modules:New("Alerts", {
    title = L["Avvisi"],
    category = L["Combattimento"],
    description = L["Avviso grande quando l'healer del gruppo o il focus finisce in CC."],
    dependencies = { "Auras" },
    defaults = {
        enabled = false,
        healerCC = true,
        focusCC = false,
        includeSilence = true,
        when = "pvp",
        sound = true,
        scale = 1.0,
        x = 0,
        y = -160,
        healers = {}, -- [nome minuscolo] = true
    },
})

M.options = {
    { type = "header", label = "Healer in CC" },
    { type = "toggle", path = "healerCC", label = L["Avvisa quando un healer del gruppo e' in CC"] },
    { type = "toggle", path = "focusCC", label = L["Avvisa anche per il focus amico"] },
    { type = "toggle", path = "includeSilence", label = L["Conta anche silence e disarm"] },
    { type = "select", path = "when", label = L["Quando"], values = WHEN },
    { type = "toggle", path = "sound", label = L["Suono"] },
    { type = "header", label = L["Posizione"] },
    { type = "range", path = "scale", label = L["Scala"], min = 0.6, max = 2, step = 0.05 },
    { type = "range", path = "x", label = L["Orizzontale"], min = -800, max = 800, step = 5 },
    { type = "range", path = "y", label = L["Verticale"], min = -600, max = 0, step = 5 },
    { type = "execute", label = L["Prova avviso"], func = function() M:Test() end },
}

------------------------------------------------------------------------------
-- Chi sorvegliare
------------------------------------------------------------------------------
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function readableName(unit)
    local n = call(UnitName, unit)
    if type(n) == "string" and not Compat.IsSecret(n) then return string.lower(n) end
end

function M:IsActiveContext()
    local when = self:Get("when")
    if when == "always" then return true end
    if when == "group" then
        return call(IsInGroup) == true or call(IsInRaid) == true
    end
    local inInstance, itype = call(IsInInstance)
    itype = SafeValue(itype, nil)
    if when == "instance" then return SafeValue(inInstance, false) == true end
    return itype == "pvp"
end

local function groupUnits()
    local list = {}
    if call(IsInRaid) == true then
        local n = tonumber(SafeValue(call(GetNumGroupMembers), 0)) or 0
        for i = 1, math.min(n, 40) do list[#list + 1] = "raid" .. i end
    else
        local n = tonumber(SafeValue(call(GetNumSubgroupMembers), 0)) or 0
        for i = 1, math.min(n, 4) do list[#list + 1] = "party" .. i end
    end
    return list
end

local function isMe(unit) return SafeValue(call(UnitIsUnit, unit, "player"), false) == true end

function M:IsHealer(unit)
    local role = SafeValue(call(UnitGroupRolesAssigned, unit), nil)
    if role == "HEALER" then return true end
    local n = readableName(unit)
    local manual = self:Get("healers") or {}
    return n ~= nil and manual[n] == true
end

-- Ricalcola l'insieme delle unita' sorvegliate: { [unit] = "healer" | "focus" }.
function M:RebuildWatch()
    local watch = {}
    if self:Get("healerCC") then
        for _, u in ipairs(groupUnits()) do
            if SafeValue(call(UnitExists, u), false) == true and not isMe(u) and self:IsHealer(u) then
                watch[u] = "healer"
            end
        end
    end
    if self:Get("focusCC") and SafeValue(call(UnitExists, "focus"), false) == true and not isMe("focus")
        and SafeValue(call(UnitIsFriend, "player", "focus"), false) == true then
        local dup = false
        for u in pairs(watch) do
            if SafeValue(call(UnitIsUnit, u, "focus"), false) == true then dup = true end
        end
        if not dup then watch.focus = "focus" end
    end
    self.watch = watch
    -- Le unita' non piu' sorvegliate escono dagli avvisi attivi.
    for u in pairs(self.active) do
        if not watch[u] then self.active[u] = nil end
    end
    return watch
end

------------------------------------------------------------------------------
-- Stato degli avvisi
------------------------------------------------------------------------------
M.active = {} -- [unit] = { entry, kind, since }

function M:ScanUnit(unit)
    local kind = self.watch and self.watch[unit]
    if not kind or not self:IsActiveContext() then
        local had = self.active[unit] ~= nil
        self.active[unit] = nil
        return had
    end
    local entry = Auras:IsCrowdControlled(unit, self:Get("includeSilence"))
    local prev = self.active[unit]
    if entry then
        if not prev then
            self.active[unit] = { entry = entry, kind = kind, since = GetTime() }
            self:PlayAlertSound()
        else
            prev.entry, prev.kind = entry, kind
        end
    else
        self.active[unit] = nil
    end
    return true
end

function M:ScanAll()
    self:RebuildWatch()
    for u in pairs(self.watch) do self:ScanUnit(u) end
    self:Render()
end

function M:PlayAlertSound()
    if not self:Get("sound") then return end
    local now = GetTime()
    if self.lastSound and now - self.lastSound < SOUND_THROTTLE then return end
    self.lastSound = now
    local kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    call(PlaySound, kit, "Master")
end

-- Righe ordinate: prima chi e' in CC da piu' tempo (l'avviso non "salta").
function M:GetRows()
    local rows = {}
    for unit, a in pairs(self.active) do rows[#rows + 1] = { unit = unit, entry = a.entry, kind = a.kind, since = a.since } end
    table.sort(rows, function(a, b)
        if a.since ~= b.since then return a.since < b.since end
        return a.unit < b.unit
    end)
    return rows
end

------------------------------------------------------------------------------
-- Banner
------------------------------------------------------------------------------
local function buildBanner(self)
    if self.banner then return self.banner end
    local f = CreateFrame("Frame", "BadbUIAlertBanner", UIParent)
    f:SetSize(260, 40)
    if f.SetFrameStrata then f:SetFrameStrata("HIGH") end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, 0)
    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = {}
        r.icon = Auras:CreateIcon(f, 28)
        r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -22 - (i - 1) * 32)
        r.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 6)
        r.what = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.what:SetPoint("LEFT", r.icon, "RIGHT", 8, -8)
        f.rows[i] = r
    end
    f.more = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:Hide()
    self.banner = f
    return f
end

function M:Layout()
    local f = self.banner
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", self:Get("x") or 0, self:Get("y") or -160)
    f:SetScale(self:Get("scale") or 1)
end

local KIND_TITLE = { healer = "Healer in CC", focus = "Focus in CC" }

function M:Render(rows)
    rows = rows or (self.testRows or self:GetRows())
    if #rows == 0 then
        if self.banner then self.banner:Hide() end
        return
    end
    local f = buildBanner(self)
    self:Layout()
    f.title:SetText(KIND_TITLE[rows[1].kind] or "In CC")
    if f.title.SetTextColor then f.title:SetTextColor(1, 0.25, 0.25) end
    for i = 1, MAX_ROWS do
        local r, row = f.rows[i], rows[i]
        if row then
            Auras:SetIcon(r.icon, row.entry, row.unit ~= "test" and row.unit or nil, { size = 28 })
            -- Il nome puo' essere secret: va al widget cosi' com'e', senza concatenazioni.
            local name = row.name
            if type(name) == "nil" then name = call(UnitName, row.unit) end
            if type(name) == "nil" then name = "?" end
            r.name:SetText(name)
            local cat = Auras:GetCategory(row.entry.category)
            r.what:SetText(cat and cat.title or "")
            r.name:Show(); r.what:Show()
        else
            Auras:ClearIcon(r.icon)
            r.name:SetText(""); r.what:SetText("")
            r.name:Hide(); r.what:Hide()
        end
    end
    if #rows > MAX_ROWS then
        f.more:SetText(string.format("+%d", #rows - MAX_ROWS))
        f.more:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -22 - MAX_ROWS * 32)
        f.more:Show()
    else
        f.more:Hide()
    end
    f:SetHeight(26 + math.min(#rows, MAX_ROWS) * 32)
    f:Show()
end

-- Mostra un avviso finto per posizionarlo; sparisce da solo.
function M:Test()
    local now = GetTime()
    self.testRows = { {
        unit = "test", kind = "healer", since = now, name = L["Healer di prova"],
        entry = { category = "cc", aura = { icon = "Interface\\Icons\\Spell_Nature_Polymorph",
            duration = TEST_SECONDS, expirationTime = now + TEST_SECONDS, applications = 0 } },
    } }
    self:Render()
    self:PlayAlertSound()
    local token = {}
    self.testToken = token
    Compat.After(TEST_SECONDS, function()
        if self.testToken ~= token then return end
        self.testRows, self.testToken = nil, nil
        self:Render()
    end)
    return true
end

------------------------------------------------------------------------------
-- Elenco manuale degli healer
------------------------------------------------------------------------------
function M:SetManualHealer(name, on)
    if type(name) ~= "string" then return false, L["serve un nome"] end
    name = string.lower(strtrim(name))
    if name == "" then return false, L["serve un nome"] end
    local t = self:Get("healers")
    if type(t) ~= "table" then t = {}; self:Set("healers", t) end
    t[name] = on and true or nil
    Badb.Events:Fire("BADB_OPTION_CHANGED", self.name, "healers", t)
    return true
end

function M:ListManualHealers()
    local list = {}
    for n in pairs(self:Get("healers") or {}) do list[#list + 1] = n end
    table.sort(list)
    return list
end

local HELP = L["alert test | status | healer add <nome> | healer remove <nome> | healers"]
M.commands = {
    alert = {
        help = HELP,
        fn = function(args)
            local sub, rest = strtrim(tostring(args or "")):match("^(%S*)%s*(.-)$")
            sub = string.lower(sub or "")
            if sub == "test" then
                M:Test()
            elseif sub == "status" then
                local watch = M.enabled and M:RebuildWatch() or {}
                local n = 0
                for _ in pairs(watch) do n = n + 1 end
                Logger:Info(L["Avvisi %s, contesto %s, unita' sorvegliate: %d"], M.enabled and L["attivi"] or L["spenti"],
                    M:IsActiveContext() and L["attivo"] or L["non attivo"], n)
            elseif sub == "healers" then
                local list = M:ListManualHealers()
                Logger:Info(#list > 0 and (L["Healer manuali: "] .. table.concat(list, ", ")) or L["Nessun healer manuale."])
            elseif sub == "healer" then
                local action, name = rest:match("^(%S+)%s*(.-)$")
                action = action and string.lower(action)
                if (action == "add" or action == "remove") and name and name ~= "" then
                    local ok, err = M:SetManualHealer(name, action == "add")
                    Logger:Info(ok and L["Elenco healer aggiornato."] or (L["Errore: "] .. tostring(err)))
                else
                    Logger:Info(L["Uso: /badb alert healer add|remove <nome>"])
                end
            else
                Logger:Info("/badb " .. HELP)
            end
        end,
    },
}

------------------------------------------------------------------------------
-- Ciclo di vita
------------------------------------------------------------------------------
function M:OnEnable()
    self.active = {}
    self:RebuildWatch()
    self:On("UNIT_AURA", function(_, unit)
        if self.watch and self.watch[unit] then
            self:ScanUnit(unit)
            self:Render()
        end
    end)
    local rescan = function() self:ScanAll() end
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_FOCUS_CHANGED",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "BADB_AURAS_CHANGED" }) do
        self:On(e, rescan)
    end
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == self.name then self:ScanAll() end
    end)
    self:ScanAll()
end

function M:OnProfileChanged()
    if self.enabled then self:ScanAll() end
end

function M:OnDisable()
    self.active, self.watch, self.testRows, self.testToken = {}, {}, nil, nil
    if self.banner then self.banner:Hide() end
end
