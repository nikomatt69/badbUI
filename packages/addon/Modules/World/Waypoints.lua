-- BadbUI - Segnalibri e destinazione della sessione.
local _, ns = ...
local Badb, Coordinates = ns.Badb, ns.WorldCoordinates
local L, Compat = Badb.L, Badb.Compat

local VERSION = 1
local MAX_POINTS = 100
local GUIDE = "badb-world:waypoints"
local M = Badb.Modules:New("World", {
    title = L["Waypoint"],
    category = L["Gioco"],
    description = L["Salva coordinate e segui una destinazione usando la mappa di WoW."],
    defaults = { enabled = true, hud = true },
    page = { title = L["Waypoint"], category = L["Gioco"], order = 50,
        keywords = { "TomTom", L["Mappa"], L["Coordinate"], L["Destinazione"] } },
    replaces = {
        { addon = "TomTom", coverage = "partial",
          note = L["Segnalibri, coordinate e distanza nella stessa mappa. Restano esclusi freccia, percorsi e segnalini sulla minimappa."] },
    },
})
Badb.World = M

local function clean(value)
    if type(value) ~= "table" then return nil end
    local id = Coordinates.ID(value.id)
    local point = Coordinates.Point(value.map, value.x, value.y)
    if not (id and point) then return nil end
    point.id, point.label = id, Coordinates.Text(value.label, 80) or L["Punto %d"]:format(id)
    return point
end

function M:OnInitialize()
    local store = Badb.DB:GetStore("world")
    self.points, self.byId = {}, {}
    if not store or (type(store.version) == "number" and store.version > VERSION) then return end
    if store.version == VERSION and type(store.points) == "table" then
        for index = 1, MAX_POINTS do
            local point = clean(store.points[index])
            if point and not self.byId[point.id] then
                self.points[#self.points + 1] = point
                self.byId[point.id] = point
            end
        end
    end
    store.version, store.points = VERSION, self.points
end

function M:List()
    local points = {}
    for index, point in ipairs(self.points or {}) do
        points[index] = { id = point.id, label = point.label, map = point.map, x = point.x, y = point.y }
    end
    return points
end

function M:Add(map, x, y, label)
    if not self.running then return nil end
    local point = Coordinates.Point(map, x, y)
    if not point then return nil, L["Inserisci coordinate da 0 a 100 e un ID mappa valido."] end
    label = Coordinates.Text(label, 80)
    for _, existing in ipairs(self.points) do
        if Coordinates.Same(point, existing) and (not label or label == existing.label) then return existing.id end
    end
    if #self.points >= MAX_POINTS then return nil, L["Hai raggiunto il limite di 100 waypoint."] end
    local id = 1
    while self.byId[id] do id = id + 1 end
    point.id, point.label = id, label or L["Punto %d"]:format(id)
    table.insert(self.points, 1, point)
    self.byId[id] = point
    self:UpdateViews()
    return id
end

function M:AddPlayer(label)
    local point = Coordinates.Player()
    if not point then return nil, L["La posizione del personaggio non è leggibile qui."] end
    return self:Add(point.map, point.x, point.y, label)
end

function M:ImportNative(label)
    local point = Coordinates.ReadNative()
    if not point then return nil, L["Imposta prima un segnaposto nella mappa di WoW."] end
    return self:Add(point.map, point.x, point.y, label)
end

function M:Track(id)
    if not self.running then return false end
    id = Compat.SafeValue(id)
    if id == nil then
        self.target = nil
    else
        local point = self.byId[Coordinates.ID(id)]
        if not point then return false end
        self.target = point
    end
    self:UpdateViews()
    return true
end

function M:ReadOwnership()
    local current, readable = Coordinates.ReadNative()
    if self.native and readable and not Coordinates.Same(self.native, current) then
        self.native, self.previous = nil, nil
    end
    return current, readable
end

function M:PlaceNative(id)
    if not self.running then return false end
    local point = self.byId[Coordinates.ID(id)]
    if not point then return false end
    if InCombatLockdown() then return false, L["Modifica il segnaposto della mappa fuori dal combattimento."] end
    if not Coordinates.CanWrite(point.map) then return false, L["Il client non accetta segnaposti su questa mappa."] end

    local current, readable = self:ReadOwnership()
    if not readable then return false, L["Il segnaposto di WoW non è leggibile."] end
    if Coordinates.Same(point, current) then return self:Track(point.id) end
    local previous = current
    if self.native then previous = self.previous end
    if not Coordinates.WriteNative(point) then return false, L["WoW non ha impostato il segnaposto."] end
    local observed, verified = Coordinates.ReadNative()
    if not verified or not Coordinates.Same(point, observed) then return false, L["WoW non ha impostato il segnaposto."] end

    self.native, self.previous = point, previous
    return self:Track(point.id)
end

function M:RestoreNative()
    if not self.native then return true end
    if InCombatLockdown() then return false, L["Modifica il segnaposto della mappa fuori dal combattimento."] end
    local _, readable = self:ReadOwnership()
    if not readable then return false, L["Il segnaposto di WoW non è leggibile."] end
    if not self.native then return true end
    local previous = self.previous
    if not Coordinates.WriteNative(previous) then return false, L["WoW non ha ripristinato il segnaposto."] end
    local observed, verified = Coordinates.ReadNative()
    if not verified or not Coordinates.Same(previous, observed) then return false, L["WoW non ha ripristinato il segnaposto."] end
    self.native, self.previous = nil, nil
    self:UpdateViews()
    return true
end

function M:Remove(id)
    if not self.running then return false end
    local point = self.byId[Coordinates.ID(id)]
    if not point then return false end
    if self.native == point then
        local ok, err = self:RestoreNative()
        if not ok then return false, err end
    end
    for index, entry in ipairs(self.points) do
        if entry == point then
            table.remove(self.points, index)
            break
        end
    end
    self.byId[point.id] = nil
    if self.target == point then self.target = nil end
    self:UpdateViews()
    return true
end

function M:UpdateViews()
    if self.RefreshWindow then self:RefreshWindow() end
    if self.RefreshHUD then self:RefreshHUD() end
end

function M:OnEnable()
    self.running = true
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module == self.name and path == "hud" then self:UpdateViews() end
    end)
end

function M:OnDisable()
    self.running, self.target, self.hudWanted = false, nil, false
    if self.window then self.window:Hide() end
    if self.hud then self.hud:Hide() end
    if self.native then
        Badb.Events:RunOutOfCombat("worldWaypointRelease", function()
            local ok, err = self:RestoreNative()
            if not ok and err then Badb.Logger:Warn("%s", err) end
        end)
    end
end

function M:OnProfileChanged()
    self:UpdateViews()
end

local function command(args)
    if not M.running then
        Badb.Logger:Warn(L["Attiva Waypoint in BadbUI per aprirlo."])
        return
    end
    args = type(args) == "string" and strtrim(args) or ""
    if args == "" then M:Open(); return end
    local first, second, label = args:match("^(%S+)%s+(%S+)%s*(.*)$")
    local map = Coordinates.PlayerMap()
    local id, err = M:Add(map, Coordinates.Percent(first), Coordinates.Percent(second), label)
    if id then
        M:Track(id)
        M:Open(id)
    elseif err then
        Badb.Logger:Warn("%s", err)
    end
end

M.commands = {
    waypoint = { help = L["waypoint [x y nome] - apri il navigatore o salva un punto nella mappa attuale"], fn = command },
}
M.options = {
    { type = "label", text = M.description },
    { type = "execute", label = L["Apri waypoint"], disabled = function() return not M.running end, func = function() command("") end },
    { type = "toggle", path = "hud", label = L["Mostra la destinazione sullo schermo"] },
    { type = "execute", label = L["Guida ai waypoint"], func = function()
        if Badb.Guides then Badb.Guides:Open(GUIDE) end
    end },
}

if Badb.Guides then
    Badb.Guides:Register({
        id = "badb-world", title = L["Waypoint"], category = L["Gioco"], version = 1,
        entries = { {
            id = "waypoints", title = L["Guida ai waypoint"], tags = { L["Mappa"], L["Coordinate"] },
            body = {
                { type = "step", text = L["Apri Gioco > Waypoint in BadbUI oppure digita /badb waypoint."] },
                { type = "step", text = L["Salva la posizione attuale o inserisci l'ID mappa e le coordinate da 0 a 100. Puoi anche importare il segnaposto già presente sulla mappa di WoW."] },
                { type = "step", text = L["Seleziona un punto e scegli Segui per vedere la destinazione e la distanza sulla stessa mappa."] },
                { type = "tip", text = L["Segna sulla mappa usa il segnaposto di WoW. Ripristina segnaposto rimette il punto precedente finché BadbUI possiede il segnaposto."] },
            },
        } },
    })
end
