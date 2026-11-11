-- BadbUI - Avversari PvP stile Gladius per campi di battaglia e world PvP.
-- Forever non ha arene ne' PvP classificato: senza unita' arena1-5 il pannello
-- segue i giocatori nemici visibili dalle nameplate. Niente combat log, niente
-- tracciamento trinket: la copertura Gladius e' dichiarata parziale.
local _, ns = ...
local Badb, L = ns.Badb, ns.Badb.L
local Compat, UI, Theme = Badb.Compat, Badb.UI, Badb.Theme

local MAX_ROWS = 5
local M = Badb.Modules:New("Arena", {
    title = L["Avversari PvP"],
    category = L["Gioco"],
    description = L["Pannello avversari stile Gladius per campi di battaglia e world PvP."],
    defaults = { enabled = true },
    replaces = {
        { addon = "Gladius", coverage = "partial",
          note = L["Avversari da nameplate in BG/world PvP con vita delegata al client. Forever non ha arene: niente unita' arena, trinket o cooldown dal combat log."] },
    },
    page = { title = L["Avversari PvP"], order = 55, category = L["Gioco"], keywords = { "gladius", "arena", "pvp", L["Avversari"] } },
})
Badb.Arena = M

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return Compat.SafeValue(v) end
end
local function text(v) v = Compat.SafeValue(v); return type(v) == "string" and v ~= "" and v:sub(1, 40) or nil end

-- Riga dati per un'unita' (nameplateN/target/focus/arenaN): mai aritmetica su segreti.
function M.BuildRow(unit)
    if type(unit) ~= "string" then return nil end
    if call(UnitIsPlayer, unit) ~= true then return nil end
    local reaction = call(UnitReaction, unit, "player")
    if type(reaction) == "number" and reaction > 4 then return nil end -- alleato
    local _, class = call(UnitClass, unit)
    return { unit = unit, name = text(call(UnitName, unit)) or unit, class = text(class),
             level = type(Compat.SafeValue(call(UnitLevel, unit))) == "number" and call(UnitLevel, unit) or nil }
end

function M:Collect()
    local rows, seen = {}, {}
    local function add(unit)
        if #rows >= MAX_ROWS or seen[unit] then return end
        local row = M.BuildRow(unit)
        if row then seen[unit] = true; rows[#rows + 1] = row end
    end
    local plates = C_NamePlate and call(C_NamePlate.GetNamePlates)
    if type(plates) == "table" then
        for _, plate in ipairs(plates) do
            local unit = type(plate) == "table" and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
            if type(unit) == "string" then add(unit) end
        end
    end
    add("target"); add("focus")
    for i = 1, MAX_ROWS do add("arena" .. i) end -- presente solo su client con arene
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = UI:Label(row, nil, "body", "text"); row.name:SetPoint("LEFT", Theme.spacing.sm, 0)
    row.hp = CreateFrame("StatusBar", nil, row)
    row.hp:SetSize(90, 10); row.hp:SetPoint("RIGHT", -Theme.spacing.sm, 0)
    row.hp:SetStatusBarTexture(Theme.textures.statusbar)
    return row
end
local function updateRow(row, entry)
    row.name:SetText(entry.class and (entry.name .. " · " .. entry.class) or entry.name)
    local pct = entry.unit and call(UnitHealthPercent, entry.unit, true)
    if type(pct) == "number" then row.hp:SetValue(math.max(0, math.min(100, pct))) else row.hp:SetValue(100) end
    row.hp:SetMinMaxValues(0, 100)
end

function M:Refresh()
    if not self.window then return end
    local rows = self:Collect()
    self.window.list:SetData(rows)
    self.window.empty:SetShown(#rows == 0)
end

function M:BuildWindow()
    if self.window then return self.window end
    local sp, sz = Theme.spacing, Theme.sizes
    local w = UI:Window("BadbUIArena", sz.sidebar * 2 + sp.xl * 2, sz.row * 8, L["Avversari PvP"], { footer = true })
    w.list = UI:ScrollList(w.body, sz.row, createRow, updateRow)
    w.list:SetPoint("TOPLEFT", sp.lg, -sp.md); w.list:SetPoint("BOTTOMRIGHT", -sp.lg, sp.sm)
    w.empty = UI:Label(w.list, L["Nessun avversario visibile. In un campo di battaglia i giocatori nemici con nameplate compaiono qui."], "body", "textDim")
    w.empty:SetPoint("TOPLEFT", sp.sm, -sp.sm); w.empty:SetWordWrap(true)
    local note = UI:Label(w.footer, L["Forever non ha arene: pannello per BG e world PvP."], "small", "textDim")
    note:SetPoint("LEFT", sp.lg, 0)
    self.window = w
    if Badb.FrameManager then Badb.FrameManager:Register("arenaPanel", { frame = w, title = L["Avversari PvP"], category = "PvP", movable = true }) end
    return w
end

function M:Open()
    if not self.enabled then return false end
    local w = self:BuildWindow(); w:Show(); self:Refresh(); return true
end
function M:OnEnable()
    self.enabled = true
    self:On("NAME_PLATE_UNIT_ADDED", function() if self.window and self.window:IsShown() then self:Refresh() end end)
    self:On("NAME_PLATE_UNIT_REMOVED", function() if self.window and self.window:IsShown() then self:Refresh() end end)
    self:On("PLAYER_TARGET_CHANGED", function() if self.window and self.window:IsShown() then self:Refresh() end end)
end
function M:OnDisable() self.enabled = false; if self.window then self.window:Hide() end end

M.options = { { type = "execute", label = L["Apri avversari PvP"], func = function() M:Open() end } }
M.commands = { arena = { help = L["arena - apre il pannello avversari PvP"], fn = function() M:Open() end } }
