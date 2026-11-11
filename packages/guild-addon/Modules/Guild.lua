-- Ponte gilda Forever: legge esclusivamente API disponibili nel client, accoda azioni nelle
-- SavedVariables e visualizza il bundle ricevuto dal companion. Nessuna rete dall'addon.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local M = Badb.Modules:New("Guild", {
    title = L["Gilda"], category = L["Contenuti"], defaults = { enabled = true },
    description = L["Consulta calendario, armory e tattiche di gilda dal companion."],
})
Badb.Guild = M
local days = { L["Lun"], L["Mar"], L["Mer"], L["Gio"], L["Ven"], L["Sab"], L["Dom"] }
local slots = { L["Mattina"], L["Pomeriggio"], L["Sera"] }
local function safe(v)
    if Badb.Compat.IsSecret(v) then return nil end
    return v
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local function pack(...) return { n = select("#", ...), ... } end
    local result = pack(pcall(fn, ...))
    if not result[1] then return nil end
    for i = 2, result.n do result[i] = safe(result[i]) end
    return unpack(result, 2, result.n)
end
local function text(v) return type(v) == "string" and v or nil end
local function number(v) return type(v) == "number" and v or nil end
local function now() return number(call(GetServerTime)) or number(call(time)) or 0 end
local function clean(v) return tostring(v or ""):gsub("|", "||") end
local function out(message) Badb.Logger:Info(L["[Gilda] %s"], clean(message)) end
local function fullName(unit)
    local name = text(call(UnitName, unit))

    return name
end
local function store()
    if type(BadbUI_GuildExport) ~= "table" then BadbUI_GuildExport = {} end
    local s = BadbUI_GuildExport
    s.version = ns.version
    s.characters = type(s.characters) == "table" and s.characters or {}
    s.actions = type(s.actions) == "table" and s.actions or {}
    s.roster = type(s.roster) == "table" and s.roster or {}
    local version, build, _, interface = call(GetBuildInfo)
    s.client = { version = text(version) or "", build = text(build) or "", interface = number(interface) or 0 }
    return s
end
function M:Capture()
    if InCombatLockdown and InCombatLockdown() then return false end
    local s = store()
    if s.client.interface ~= 16001 then return false end
    local player = Badb.Player:GetSnapshot()
    local name, level = fullName("player"), number(call(UnitLevel, "player"))
    if not name or not level or not player.class then return false end
    local gear, professions, complete = {}, {}, true
    for slot = 1, 19 do
        local link = text(call(GetInventoryItemLink, "player", slot))
        local id = number(call(GetInventoryItemID, "player", slot))
        if not id and link then id = tonumber(link:match("item:(%d+)")) end
        if id then
            local itemName, _, quality, ilvl = call(C_Item and C_Item.GetItemInfo or GetItemInfo, link or id)
            local detailed = number(call(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link or id))
            if not text(itemName) or not number(quality) then complete = false end
            gear[#gear + 1] = { slot = slot, id = id, name = text(itemName) or "", quality = number(quality) or 1, ilvl = detailed or number(ilvl) }
        end
    end
    local indexes = { call(GetProfessions) }
    for _, index in pairs(indexes) do
        if type(index) == "number" then
            local profession, _, rank = call(GetProfessionInfo, index)
            if text(profession) and number(rank) then professions[#professions + 1] = { name = profession, rank = rank } end
        end
    end
    local guild, rank = call(GetGuildInfo, "player")
    local _, equipped = call(GetAverageItemLevel)
    local spec = player.treeKey == "beastmastery" and "beast-mastery" or player.treeKey
    local character = { name = name, realm = text(call(GetRealmName)) or "", cls = player.class:lower(),
        spec = spec, level = level, race = text(call(UnitRace, "player")), guildRank = text(rank),
        itemLevel = number(equipped) and math.floor(equipped) or nil, gear = gear, professions = professions, scanned = now() }
    -- Un ruolo dedotto soltanto dalla classe non viene esportato come osservazione.
    if player.roleConfidence ~= "low" then character.role = player.role end
    if not complete then return false end -- GET_ITEM_INFO_RECEIVED riprova senza spacciare cache parziali per una scansione nuova
    s.characters[name] = character
    s.guildName = text(guild)
    return true
end
function M:CaptureRoster()
    local s, roster = store(), {}
    if s.client.interface ~= 16001 then return end
    local count = number(call(GetNumGuildMembers))
    if not count or count == 0 or count > 1000 then return end
    for i = 1, count do
        local name, rank, _, level, _, _, _, _, _, _, cls = call(GetGuildRosterInfo, i)
        if not text(name) or not number(level) or not text(cls) then return end -- mai un roster parziale
        roster[#roster + 1] = { name = name, cls = cls:lower(), level = level, guildRank = text(rank) }
    end
    s.roster, s.rosterAt = roster, now()
end
function M:Import()
    local s = store()
    local data = type(BadbUI_GuildSync) == "table" and BadbUI_GuildSync or nil
    self.bundle = data
    if not data then return end
    local received = {}
    for _, id in ipairs(data.applied or {}) do received[id] = true end
    for _, failure in ipairs(data.rejected or {}) do
        received[failure.id] = true
        out(L["Azione rifiutata: "] .. tostring(failure.error))
    end
    local queue = {}
    for _, action in ipairs(s.actions) do if not received[action.id] then queue[#queue + 1] = action end end
    s.actions = queue
end
function M:Queue(action)
    local s = store()
    if #s.actions >= 200 then out(L["Coda piena: sincronizza il companion prima di continuare."]); return false end
    s.sequence = (tonumber(s.sequence) or 0) + 1
    action.id = tostring(now()) .. "-" .. tostring(s.sequence)
    action.at = now()
    s.actions[#s.actions + 1] = action
    out(L["Azione accodata. /reload per esportare; attendi il companion e poi /reload per ricevere la risposta."])
    return true
end
-- Esportazione di sola lettura del roster gia' catturato: nessuna API protetta.
function M:ExportRoster()
    local s = store()
    local roster = type(s.roster) == "table" and s.roster or {}
    if #roster == 0 then return nil, L["Roster vuoto: apri il pannello di gilda in gioco e riprova."] end
    local rows = { "name;class;level;rank" }
    local sorted = {}
    for _, r in ipairs(roster) do if type(r) == "table" then sorted[#sorted + 1] = r end end
    table.sort(sorted, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    for _, r in ipairs(sorted) do
        local function f(v) return tostring(v or ""):gsub("[;\r\n|]", " ") end
        rows[#rows + 1] = f(r.name) .. ";" .. f(r.cls) .. ";" .. f(r.level) .. ";" .. f(r.guildRank)
    end
    return table.concat(rows, "\n")
end
function M:Signup(id, status)
    if status ~= "yes" and status ~= "no" and status ~= "maybe" and status ~= "bench" then return false end
    local name = fullName("player")
    if not name then return false end
    return self:Queue({ type = "signup", eventId = id, character = name, status = status, note = "" })
end
function M:Availability(mask)
    if type(mask) ~= "string" or #mask ~= 21 or mask:find("[^01]") then return false end
    if not self.bundle or not self.bundle.week then out(L["Collega prima il companion per ricevere la settimana della gilda."]); return false end
    return self:Queue({ type = "availability", week = self.bundle.week, mask = mask })
end
function M:OnInitialize() store(); self:Import() end
function M:OnEnable()
    self:Capture()
    self:On("PLAYER_LOGOUT", function() self:Capture() end)
    self:On("PLAYER_EQUIPMENT_CHANGED", function() self:Capture() end)
    self:On("GET_ITEM_INFO_RECEIVED", function() self:Capture() end)
    self:On("PLAYER_LEVEL_UP", function() self:Capture() end)
    self:On("BADB_PLAYER_CHANGED", function() self:Capture() end)
    self:On("GUILD_ROSTER_UPDATE", function() self:CaptureRoster() end)
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
end
function M:OnDisable() if self.frame then self.frame:Hide() end end
local function button(parent, label, x, y, width, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24); b:SetPoint("TOPLEFT", x, y); b:SetText(label); b:SetScript("OnClick", fn)
    return b
end
function M:Show()
    if not self.enabled then out(L["Attiva il modulo Gilda per aprire il pannello."]); return end
    if InCombatLockdown and InCombatLockdown() then out(L["Apri il pannello fuori dal combattimento."]); return end
    if self.frame then self.frame:Show(); return end
    local f = Badb.Compat.CreateFrame("Frame", "BadbUIGuild", UIParent)
    self.frame = f
    f:SetSize(760, 610); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -24); title:SetText("Fratelli di Azeroth — WoW Forever")
    button(f, L["Chiudi"], 650, -20, 84, function() f:Hide() end)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 25, -65); scroll:SetPoint("BOTTOMRIGHT", -45, 25)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(660, 1000); scroll:SetScrollChild(content)
    local y = -5
    local function line(value, font)
        local t = content:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        t:SetPoint("TOPLEFT", 0, y); t:SetWidth(655); t:SetJustifyH("LEFT"); t:SetText(clean(value))
        y = y - math.max(24, (t.GetStringHeight and t:GetStringHeight() or 20) + 10)
    end
    local data = self.bundle
    if not data then
        line(L["Collega il companion dal profilo del sito. Nessun dato dimostrativo è caricato."])
        line(L["1. Installa il companion e collega il codice addon del tuo profilo."])
        line(L["2. /reload per esportare. Attendi “Dati pronti” nel companion."])
        line(L["3. /reload per leggere calendario, tattiche e risposte dal server."])
    else
        line((data.guild and data.guild.name or L["Gilda"]) .. L[" — revisione "] .. tostring(data.rev), "GameFontNormalLarge")
        line("Snapshot: " .. tostring(data.generated) .. " · " .. tostring(#store().actions) .. L[" azioni da inviare"])
        line(L["CALENDARIO RAID"], "GameFontNormalLarge")
        for _, event in ipairs(data.events or {}) do
            line(event.title .. " · " .. event.date .. " · " .. string.format("%02d:%02d", math.floor(event.start / 60), event.start % 60) .. " · " .. event.status, "GameFontNormal")
            local names = {}
            for _, signup in ipairs(event.signups or {}) do names[#names + 1] = signup.name .. " (" .. signup.status .. (signup.picked and L[", titolare"] or "") .. ")" end
            line(table.concat(names, ", "))
            if event.status == "open" then
                local eventId = event.id
                button(content, L["Ci sono"], 0, y, 120, function() self:Signup(eventId, "yes") end)
                button(content, L["Forse"], 130, y, 120, function() self:Signup(eventId, "maybe") end)
                button(content, L["Non ci sono"], 260, y, 120, function() self:Signup(eventId, "no") end)
                y = y - 40
            end
        end
        line(L["DISPONIBILITÀ — "] .. tostring(data.week), "GameFontNormalLarge")
        local mask = "000000000000000000000"
        for _, week in ipairs(data.availability or {}) do
            if week.week == data.week then
                for _, person in ipairs(week.people or {}) do
                    line(person.name .. " · " .. person.mask)
                    if data.user and person.name == data.user.name then mask = person.mask end
                end
            end
        end
        local bits, buttons = {}, {}
        for i = 1, 21 do bits[i] = mask:sub(i, i) == "1" end
        for day = 1, 7 do
            for slot = 1, 3 do
                local index = (day - 1) * 3 + slot
                local label = days[day] .. " " .. slots[slot]:sub(1, 1)
                local b
                b = button(content, (bits[index] and "[x] " or "[ ] ") .. label, (day - 1) * 92, y - (slot - 1) * 29, 87, function()
                    bits[index] = not bits[index]; b:SetText((bits[index] and "[x] " or "[ ] ") .. label)
                end)
                buttons[index] = b
            end
        end
        y = y - 100
        button(content, L["Salva disponibilità"], 0, y, 210, function()
            local value = {}; for i = 1, 21 do value[i] = bits[i] and "1" or "0" end
            self:Availability(table.concat(value))
        end)
        y = y - 50
        line(L["BOSS E TATTICHE — valutazioni degli ufficiali, non statistiche ufficiali"], "GameFontNormal")
        for _, boss in ipairs(data.bosses or {}) do
            line(boss.name, "GameFontNormalLarge"); line(boss.notes)
            for _, role in ipairs({ "tank", "healer", "dps" }) do
                local best = {}; for _, fit in ipairs(boss.best and boss.best[role] or {}) do best[#best + 1] = fit.label .. " " .. (fit.score and tostring(fit.score) or L["non valutato"]) end
                line(role .. ": " .. table.concat(best, ", "))
            end
        end
        line(L["DIARIO DI GILDA"], "GameFontNormalLarge")
        for _, post in ipairs(data.news or {}) do line(post.title, "GameFontNormal"); line(post.excerpt) end
        line(L["GUIDE DI GILDA"], "GameFontNormalLarge")
        for _, guide in ipairs(data.guides or {}) do line(guide.title, "GameFontNormal"); line(guide.body) end
        line(L["ARMORY — SNAPSHOT RICEVUTI DAL SERVER"], "GameFontNormalLarge")
        for _, character in ipairs(data.armory or {}) do
            line(character.name .. " · " .. tostring(character.level) .. " · " .. character.cls .. " · " .. (character.spec or L["spec non rilevata"]), "GameFontNormal")
            line(character.scannedAt and (L["Scansione client: "] .. tostring(character.scannedAt)) or L["Scheda manuale o roster: equipaggiamento non verificato"])
            for _, item in ipairs(character.gear or {}) do line("Slot " .. tostring(item.slot) .. ": " .. (item.name or tostring(item.id))) end
        end
    end
    content:SetHeight(math.max(500, -y + 20)); f:Show()
end
M.commands = {
    guild = { help = L["Calendario, disponibilità e tattiche della gilda"], fn = function(args)
        if type(args) == "string" and args:match("^%s*export%s*$") then
            local str, err = M:ExportRoster()
            if not str then out(err); return end
            if Badb.ConfigUI and Badb.ConfigUI.TextBox then Badb.ConfigUI.TextBox(L["Esporta roster"], str)
            else out(str) end
            return
        end
        M:Show()
    end },
    gilda = { help = L["Calendario, disponibilità e tattiche della gilda"], fn = function() M:Show() end },
    guildscan = { help = L["Aggiorna lo snapshot Forever; /reload per inviarlo al companion"], fn = function() M:Capture(); M:CaptureRoster(); out(L["Snapshot aggiornato; /reload per esportare."]) end },
}

M.options = {
    { type = "execute", label = L["Apri pannello gilda"], func = function() M:Show() end },
}

M:On("ADDON_LOADED", function(_, name)
    if name ~= ns.name then return end
    M:Off("ADDON_LOADED")
    M:OnInitialize()
    if IsLoggedIn and IsLoggedIn() and M:Get("enabled") then Badb.Modules:Enable(M.name) end
end)
