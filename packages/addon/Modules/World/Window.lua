-- Waypoint nel design system di BadbUI, senza agganci ai frame Blizzard.
local _, ns = ...
local Badb, Coordinates = ns.Badb, ns.WorldCoordinates
local M, L, UI, Theme = Badb.World, Badb.L, Badb.UI, Badb.Theme
local sp, sizes = Theme.spacing, Theme.sizes
local INTERVAL = 0.5

local function coordinates(point)
    return ("%.1f, %.1f"):format(point.x * 100, point.y * 100)
end

local function location(point)
    return Coordinates.MapName(point.map) .. "  ·  " .. coordinates(point)
end

local function markerRow(parent, window)
    local row = CreateFrame("Button", nil, parent)
    UI.AddHover(row)
    row.selected = UI:Fill(row, "selected", "BACKGROUND")
    row.selected:SetAllPoints()
    row.title = UI:Label(row, nil, "body", "text")
    row.title:SetPoint("LEFT", sp.sm, sp.sm)
    row.title:SetPoint("RIGHT", -sp.sm, sp.sm)
    row.meta = UI:Label(row, nil, "small", "textDim")
    row.meta:SetPoint("LEFT", sp.sm, -sp.sm)
    row.meta:SetPoint("RIGHT", -sp.sm, -sp.sm)
    local line = UI:Separator(row, false, "divider")
    line:SetPoint("BOTTOMLEFT", sp.sm, 0)
    line:SetPoint("BOTTOMRIGHT", -sp.sm, 0)
    row:SetScript("OnClick", function(self)
        if self.item then
            window.selection = self.item.id
            M:RefreshWindow()
        end
    end)
    return row
end

local function updateMarker(row, point, window)
    row.title:SetText(point.label)
    local following = M.target == point
    local meta = location(point)
    if following then meta = L["%s  ·  In uso"]:format(meta) end
    row.meta:SetText(meta)
    Theme:Paint(row.meta, following and "accent" or "textDim")
    row.selected:SetShown(point.id == window.selection)
end

local function field(parent, text, width, limit)
    local label = UI:Label(parent, text, "small", "textDim")
    local input = UI:EditBox(parent, width, sizes.button, { maxLetters = limit })
    input:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -sp.xs)
    return input, label
end

local function message(window, err)
    window.feedback:SetText(err or "")
end

local function afterAdd(window, id, err)
    if id then
        window.selection = id
        window.query = ""
        window.search:SetText("")
        window.list:ScrollToIndex(1)
        M:RefreshWindow()
    end
    message(window, err)
end

local function fold(value)
    if Badb.Guides and Badb.Guides.Fold then return Badb.Guides.Fold(value) end
    return value:lower()
end

function M:RefreshWindow()
    local window = self.window
    if not (window and window:IsShown()) then return end
    local rows, selected = {}, nil
    local query = fold(window.query)
    for _, point in ipairs(self.points) do
        if query == "" or fold(point.label .. " " .. Coordinates.MapName(point.map)):find(query, 1, true) then
            rows[#rows + 1] = point
            if point.id == window.selection then selected = point end
        end
    end
    selected = selected or rows[1]
    window.selection = selected and selected.id or nil
    window.list:SetData(rows)
    local empty = window.query ~= "" and L["Nessun waypoint corrisponde alla ricerca."] or L["Aggiungi il primo waypoint."]
    window.empty:SetText(#rows == 0 and empty or "")
    self:RefreshLive()
end

local function targetText(player, target)
    if not target then return "" end
    local distance = Coordinates.Distance(player, target)
    if distance then return L["%s  ·  %d iarde"]:format(target.label, distance) end
    return target.label .. "  ·  " .. location(target)
end

function M:RefreshLive()
    local player = Coordinates.Player()
    local window, hud = self.window, self.hud
    if window and window:IsShown() then
        local native, readable = self:ReadOwnership()
        local selected = self.byId[window.selection]
        local ownsSelected = self.native ~= nil and self.native == selected
        window.follow:SetEnabled(selected ~= nil)
        window.follow:SetLabel(selected and self.target == selected and L["Non seguire"] or L["Segui"])
        window.remove:SetEnabled(selected ~= nil)
        window.map:SetLabel(ownsSelected and L["Ripristina segnaposto"] or L["Segna sulla mappa"])
        window.map:SetEnabled(selected ~= nil and readable and not InCombatLockdown()
            and (ownsSelected or Coordinates.CanWrite(selected.map)))
        window.here:SetEnabled(player ~= nil)
        window.import:SetEnabled(native ~= nil)
        window.player:SetText(player and L["Qui: %s"]:format(location(player)) or L["Posizione attuale non leggibile"])
        window.destination:SetText(targetText(player, self.target))
    end
    if hud and hud:IsShown() and self.target then
        hud.title:SetText(self.target.label)
        local distance = Coordinates.Distance(player, self.target)
        hud.meta:SetText(distance and L["%s  ·  %d iarde"]:format(location(self.target), distance) or location(self.target))
    end
end

local function installPolling(frame, canRun)
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not canRun() then return end
        self.sinceRefresh = (self.sinceRefresh or 0) + elapsed
        if self.sinceRefresh < INTERVAL then return end
        self.sinceRefresh = 0
        M:RefreshLive()
    end)
end

function M:BuildWindow()
    if self.window then return self.window end
    local formWidth = sizes.sidebar + sizes.row * 3
    local window = UI:Window("BadbUIWaypoints", sizes.sidebar * 4 + sp.xl, sizes.row * 14, L["Waypoint"], {
        footer = true, resizable = true, minW = sizes.sidebar * 4 - sp.xl, minH = sizes.row * 13,
        onClose = function(frame)
            for _, input in ipairs(frame.fields) do input.edit:ClearFocus() end
        end,
    })
    window.query = ""

    local form = UI:Panel(window.body, "panel", { border = "border" })
    form:SetWidth(formWidth)
    form:SetPoint("TOPLEFT", sp.lg, -sp.md)
    form:SetPoint("BOTTOMLEFT", sp.lg, sp.md)
    local heading = UI:Label(form, L["Nuovo waypoint"], "heading", "text")
    heading:SetPoint("TOPLEFT", sp.md, -sp.md)
    local inputWidth = formWidth - sp.md * 2
    local name, nameLabel = field(form, L["Nome facoltativo"], inputWidth, 80)
    nameLabel:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -sp.md)

    local id, idLabel = field(form, L["ID mappa"], sizes.row * 3, 10)
    local x, xLabel = field(form, "X", sizes.row * 2, 8)
    local y, yLabel = field(form, "Y", sizes.row * 2, 8)
    idLabel:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -sp.md)
    xLabel:SetPoint("TOPLEFT", idLabel, "TOPLEFT", sizes.row * 3 + sp.sm, 0)
    yLabel:SetPoint("TOPLEFT", xLabel, "TOPLEFT", sizes.row * 2 + sp.sm, 0)
    window.mapInput = id

    local save = UI:Button(form, L["Salva waypoint"], inputWidth, sizes.button, function()
        local mapID = Coordinates.ID(tonumber(id:GetText() or ""))
        afterAdd(window, self:Add(mapID, Coordinates.Percent(x:GetText()), Coordinates.Percent(y:GetText()), name:GetText()))
    end, "primary")
    save:SetPoint("TOPLEFT", id, "BOTTOMLEFT", 0, -sp.md)
    window.here = UI:Button(form, L["Salva posizione attuale"], inputWidth, sizes.button, function()
        afterAdd(window, self:AddPlayer(name:GetText()))
    end)
    window.here:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -sp.sm)
    window.import = UI:Button(form, L["Importa segnaposto di WoW"], inputWidth, sizes.button, function()
        afterAdd(window, self:ImportNative(name:GetText()))
    end)
    window.import:SetPoint("TOPLEFT", window.here, "BOTTOMLEFT", 0, -sp.sm)
    window.feedback = UI:Label(form, nil, "small", "warning")
    window.feedback:SetWordWrap(true)
    window.feedback:SetPoint("TOPLEFT", window.import, "BOTTOMLEFT", 0, -sp.md)
    window.feedback:SetPoint("TOPRIGHT", window.import, "BOTTOMRIGHT", 0, -sp.md)

    window.search = UI:EditBox(window.body, sizes.sidebar, sizes.button, {
        placeholder = L["Cerca waypoint"], maxLetters = 80,
        onChange = function(query)
            window.query = query
            window.list:ScrollToIndex(1)
            self:RefreshWindow()
        end,
    })
    window.search:SetPoint("TOPLEFT", form, "TOPRIGHT", sp.md, 0)
    window.search:SetPoint("TOPRIGHT", window.body, "TOPRIGHT", -sp.lg, -sp.md)
    window.fields = { id, x, y, name, window.search }

    window.follow = UI:Button(window.body, L["Segui"], sizes.row * 3, sizes.button, function()
        local point = self.byId[window.selection]
        if self.target == point then self:Track(nil) else self:Track(window.selection) end
        message(window)
    end, "primary")
    window.follow:SetPoint("BOTTOMLEFT", form, "BOTTOMRIGHT", sp.md, 0)
    window.map = UI:Button(window.body, L["Segna sulla mappa"], sizes.sidebar - sp.xl, sizes.button, function()
        local ok, err
        if self.native and self.native == self.byId[window.selection] then ok, err = self:RestoreNative()
        else ok, err = self:PlaceNative(window.selection) end
        message(window, not ok and err or nil)
    end)
    window.map:SetPoint("LEFT", window.follow, "RIGHT", sp.sm, 0)
    window.remove = UI:Button(window.body, L["Elimina"], sizes.row * 3, sizes.button, function()
        local point = self.byId[window.selection]
        if not point then return end
        local function remove()
            if self.byId[point.id] ~= point then return end
            local ok, err = self:Remove(point.id)
            message(window, not ok and err or nil)
        end
        if Badb.ConfigUI and Badb.ConfigUI.Confirm then
            Badb.ConfigUI:Confirm(L["Eliminare il waypoint «%s»?"]:format(point.label), remove)
        else
            remove()
        end
    end, "danger")
    window.remove:SetPoint("RIGHT", window.body, "BOTTOMRIGHT", -sp.lg, sp.md + sizes.button / 2)

    window.list = UI:ScrollList(window.body, sizes.row + sp.xs, function(parent)
        return markerRow(parent, window)
    end, function(row, point) updateMarker(row, point, window) end)
    window.list:SetPoint("TOPLEFT", window.search, "BOTTOMLEFT", 0, -sp.sm)
    window.list:SetPoint("TOPRIGHT", window.search, "BOTTOMRIGHT", 0, -sp.sm)
    window.list:SetPoint("BOTTOMLEFT", window.follow, "TOPLEFT", 0, sp.md)
    window.empty = UI:Label(window.list, nil, "body", "textDim")
    window.empty:SetPoint("TOPLEFT", sp.sm, -sp.md)
    window.empty:SetPoint("TOPRIGHT", -sp.sm, -sp.md)

    window.player = UI:Label(window.footer, nil, "small", "textDim")
    window.player:SetPoint("LEFT", sp.lg, 0)
    window.player:SetPoint("RIGHT", window.footer, "CENTER", -sp.sm, 0)
    window.destination = UI:Label(window.footer, nil, "small", "accent")
    window.destination:SetJustifyH("RIGHT")
    window.destination:SetPoint("LEFT", window.footer, "CENTER", sp.sm, 0)
    window.destination:SetPoint("RIGHT", -sp.lg, 0)
    installPolling(window, function() return self.running end)

    self.window = window
    return window
end

function M:Open(selection)
    if not self.running then return false end
    local window = self:BuildWindow()
    selection = Coordinates.ID(selection)
    if selection then
        window.selection = selection
        window.query = ""
        window.search:SetText("")
    end
    if not window.mapInput:GetText() or window.mapInput:GetText() == "" then
        local map = Coordinates.ViewedMap() or Coordinates.PlayerMap()
        if map then window.mapInput:SetText(tostring(map)) end
    end
    window:Show()
    self:RefreshWindow()
    return true
end

function M:BuildHUD()
    if self.hud then return self.hud end
    local hud = CreateFrame("Frame", "BadbUIWaypointHUD", UIParent)
    hud:Hide()
    hud:SetSize(sizes.sidebar + sizes.row * 3, sizes.header)
    hud:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, sizes.header * 4)
    hud:SetClampedToScreen(true)
    Theme:Skin(hud, { bg = "panel", border = "border" })
    hud.title = UI:Label(hud, nil, "heading", "text")
    hud.title:SetPoint("TOPLEFT", sp.md, -sp.sm)
    hud.title:SetPoint("TOPRIGHT", -sp.md, -sp.sm)
    hud.meta = UI:Label(hud, nil, "small", "textDim")
    hud.meta:SetPoint("BOTTOMLEFT", sp.md, sp.sm)
    hud.meta:SetPoint("BOTTOMRIGHT", -sp.md, sp.sm)
    hooksecurefunc(hud, "Show", function(frame)
        if not self.hudWanted then frame:Hide() end
    end)
    installPolling(hud, function() return self.running and not (self.window and self.window:IsShown()) end)
    self.hud = hud
    Badb.FrameManager:Register("BadbUIWaypointHUD", {
        frame = "BadbUIWaypointHUD", title = L["Destinazione"], category = L["Gioco"],
        movable = true, scalable = true, hideable = true,
    })
    return hud
end

function M:RefreshHUD()
    local settings = Badb.DB.profile.frames.BadbUIWaypointHUD
    self.hudWanted = self.target ~= nil and self:Get("hud") == true and not (settings and settings.hidden)
    if not self.hudWanted then
        if self.hud then self.hud:Hide() end
        return
    end
    self:BuildHUD():Show()
    self:RefreshLive()
end
