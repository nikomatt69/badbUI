-- BadbUI - LayoutStudio
-- Editor di layout avanzato sopra il FrameManager: undo/redo, nudge da tastiera,
-- allineamento/distribuzione, gruppi bloccabili e snap intelligente.
--
-- Principi:
--  * Non si chiama mai SetPoint direttamente: ogni spostamento passa da FM:SetOption /
--    FM:Restore / FM:Apply (il FrameManager gestisce combattimento ed Edit Mode).
--  * I frame Edit Mode non vengono mai mossi: le operazioni ritornano `false, "gestito dall'Edit Mode"`.
--  * La storia registra lo stato di DB.profile.frames[key] (prima/dopo) ascoltando
--    BADB_FRAME_CHANGED, e con due aggancio difensivi per cio' che il FrameManager fa
--    senza emettere eventi (fine drag di un mover, FM:Restore).
--  * Tutte le API pubbliche ritornano `ok, err` e non lanciano errori verso il chiamante.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat, DB, Events, FM, Logger = Badb.Compat, Badb.DB, Badb.Events, Badb.FrameManager, Badb.Logger

local MSG_EDITMODE = L["gestito dall'Edit Mode"]
local MSG_COMBAT = L["in combattimento"]
local MSG_LOCKED = L["gruppo bloccato"]
local MSG_OFF = L["modulo disattivato"]

-- Suggerimento aggiunto al messaggio quando il layout Edit Mode attivo e' un preset Blizzard
-- (non modificabile ne' esportabile: va duplicato).
local MSG_EDITMODE_PRESET = MSG_EDITMODE .. L[" (layout preset Blizzard: duplicalo in Edit Mode e usa EditModeBridge)"]

local MAX_HISTORY_CAP = 500
local MAX_GROUPS, MAX_GROUP_KEYS = 50, 100
local COORD_LIMIT = 16384

-------------------------------------------------------------------------------
-- Calcoli puri (nessuna dipendenza dal client): testabili senza frame.
-- Un "rect" e' { key, x, y, w, h } con x,y = centro relativo al centro di UIParent
-- (stessa convenzione del FrameManager: point CENTER) e w,h = dimensioni.
-------------------------------------------------------------------------------
local Calc = {}

local function isnum(v)
    return type(v) == "number" and v == v and v > -1e9 and v < 1e9
end
Calc.IsNumber = isnum

function Calc.Round(v) return math.floor(v + 0.5) end

-- Rimuove duplicati e valori non stringa mantenendo l'ordine.
function Calc.Unique(keys)
    local out, seen = {}, {}
    if type(keys) ~= "table" then return out end
    for _, k in ipairs(keys) do
        if type(k) == "string" and not seen[k] then
            seen[k] = true
            out[#out + 1] = k
        end
    end
    return out
end

-- Passo del nudge: frecce = 1px, SHIFT = griglia, CTRL = 10px.
function Calc.Step(shift, ctrl, grid)
    if shift then return isnum(grid) and grid > 0 and grid or 8 end
    if ctrl then return 10 end
    return 1
end

-- Scarta rect non validi e duplicati. Ritorna lista pulita + chiavi scartate.
function Calc.Normalize(rects)
    local out, bad, seen = {}, {}, {}
    if type(rects) ~= "table" then return out, bad end
    for _, r in ipairs(rects) do
        if type(r) == "table" and type(r.key) == "string" then
            if not seen[r.key] then
                seen[r.key] = true
                if isnum(r.x) and isnum(r.y) then
                    local w = isnum(r.w) and r.w > 0 and r.w or 0
                    local h = isnum(r.h) and r.h > 0 and r.h or 0
                    out[#out + 1] = { key = r.key, x = r.x, y = r.y, w = w, h = h }
                else
                    bad[#bad + 1] = r.key
                end
            end
        end
    end
    return out, bad
end

local ALIGN_MODES = { left = true, right = true, top = true, bottom = true, hcenter = true, vcenter = true }
Calc.ALIGN_MODES = ALIGN_MODES

function Calc.Bounds(rects)
    local l, r, b, t
    for _, q in ipairs(rects) do
        local ql, qr, qb, qt = q.x - q.w / 2, q.x + q.w / 2, q.y - q.h / 2, q.y + q.h / 2
        if not l or ql < l then l = ql end
        if not r or qr > r then r = qr end
        if not b or qb < b then b = qb end
        if not t or qt > t then t = qt end
    end
    return l, r, b, t
end

-- Allineamento: ritorna { [key] = {x=, y=} } (centri interi) oppure nil, errore.
function Calc.Align(rects, mode)
    if not ALIGN_MODES[mode] then return nil, L["modo di allineamento non valido"] end
    local list = Calc.Normalize(rects)
    if #list < 2 then return nil, L["servono almeno 2 frame"] end
    local l, r, b, t = Calc.Bounds(list)
    local out = {}
    for _, q in ipairs(list) do
        local x, y = q.x, q.y
        if mode == "left" then x = l + q.w / 2
        elseif mode == "right" then x = r - q.w / 2
        elseif mode == "top" then y = t - q.h / 2
        elseif mode == "bottom" then y = b + q.h / 2
        elseif mode == "hcenter" then x = (l + r) / 2
        elseif mode == "vcenter" then y = (b + t) / 2 end
        out[q.key] = { x = Calc.Round(x), y = Calc.Round(y) }
    end
    return out
end

-- Distribuzione: spazi uguali tra i bordi, primo e ultimo frame fermi.
function Calc.Distribute(rects, axis)
    if axis ~= "h" and axis ~= "v" then return nil, L["asse non valido (h|v)"] end
    local list = Calc.Normalize(rects)
    if #list < 3 then return nil, L["servono almeno 3 frame"] end
    local horizontal = axis == "h"
    local function size(q) return horizontal and q.w or q.h end
    local function center(q) return horizontal and q.x or q.y end
    table.sort(list, function(a, b)
        local ca, cb = center(a), center(b)
        if ca ~= cb then return ca < cb end
        return a.key < b.key
    end)
    local first, last = list[1], list[#list]
    local startEdge = center(first) - size(first) / 2
    local endEdge = center(last) + size(last) / 2
    local total = 0
    for _, q in ipairs(list) do total = total + size(q) end
    local gap = (endEdge - startEdge - total) / (#list - 1)
    local out, cursor = {}, startEdge
    for _, q in ipairs(list) do
        local c = cursor + size(q) / 2
        if horizontal then
            out[q.key] = { x = Calc.Round(c), y = Calc.Round(q.y) }
        else
            out[q.key] = { x = Calc.Round(q.x), y = Calc.Round(c) }
        end
        cursor = cursor + size(q) + gap
    end
    return out
end

-- Snap intelligente: distanza minima (entro `threshold`) tra bordi/centri del frame
-- trascinato e quelli degli altri. Ritorna dx, dy (0 se nessun aggancio).
function Calc.SnapDelta(rect, others, threshold)
    if type(rect) ~= "table" or not isnum(rect.x) or not isnum(rect.y) or type(others) ~= "table" then return 0, 0 end
    threshold = isnum(threshold) and threshold or 6
    local w = isnum(rect.w) and rect.w or 0
    local h = isnum(rect.h) and rect.h or 0
    local function axis(mine, getter)
        local best, bestAbs
        for _, o in ipairs(others) do
            if type(o) == "table" and isnum(o.x) and isnum(o.y) then
                for _, ov in ipairs(getter(o)) do
                    for _, mv in ipairs(mine) do
                        local d = ov - mv
                        local a = math.abs(d)
                        if a <= threshold and (not bestAbs or a < bestAbs) then best, bestAbs = d, a end
                    end
                end
            end
        end
        return best or 0
    end
    local dx = axis({ rect.x - w / 2, rect.x, rect.x + w / 2 }, function(o)
        local ow = isnum(o.w) and o.w or 0
        return { o.x - ow / 2, o.x, o.x + ow / 2 }
    end)
    local dy = axis({ rect.y - h / 2, rect.y, rect.y + h / 2 }, function(o)
        local oh = isnum(o.h) and o.h or 0
        return { o.y - oh / 2, o.y, o.y + oh / 2 }
    end)
    return dx, dy
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
Calc.Same = same

local function fmtNum(v)
    if v == nil then return "orig." end
    if type(v) == "number" then return tostring(math.floor(v * 100 + 0.5) / 100) end
    return tostring(v)
end

local FIELD_ORDER = { "x", "y", "scale", "alpha", "hidden", "point", "relPoint" }

-- Descrizione leggibile della differenza tra due stati: "x 120 -> 128, y 0 -> 8".
function Calc.Diff(before, after)
    before, after = before or {}, after or {}
    local fields, seen = {}, {}
    for _, f in ipairs(FIELD_ORDER) do
        fields[#fields + 1] = f; seen[f] = true
    end
    local extra = {}
    for f in pairs(before) do if not seen[f] then seen[f] = true; extra[#extra + 1] = f end end
    for f in pairs(after) do if not seen[f] then seen[f] = true; extra[#extra + 1] = f end end
    table.sort(extra, function(a, b) return tostring(a) < tostring(b) end)
    for _, f in ipairs(extra) do fields[#fields + 1] = f end
    local hasXY = not same(before.x, after.x) or not same(before.y, after.y)
    local parts = {}
    for _, f in ipairs(fields) do
        local a, b = before[f], after[f]
        if not same(a, b) and not (hasXY and (f == "point" or f == "relPoint")) then
            if f == "hidden" then
                parts[#parts + 1] = b and L["nascosto"] or L["mostrato"]
            else
                parts[#parts + 1] = string.format("%s %s -> %s", tostring(f), fmtNum(a), fmtNum(b))
            end
        end
    end
    if #parts > 3 then
        parts[4] = "..."
        for i = #parts, 5, -1 do parts[i] = nil end
    end
    return table.concat(parts, ", ")
end

-------------------------------------------------------------------------------
-- Modulo
-------------------------------------------------------------------------------
local M = Badb.Modules:New("LayoutStudio", {
    title = "Layout Studio",
    category = "Layout",
    defaults = {
        enabled = true,
        snap = true,            -- snap intelligente ai bordi/centri degli altri frame
        snapThreshold = 6,      -- px
        maxHistory = 100,       -- passi di undo
        coalesceWindow = 0.4,   -- s: modifiche ravvicinate sullo stesso frame = un passo
        groups = {},            -- { [nome] = { keys = {...}, locked = bool } }
    },
})
Badb.LayoutStudio = M
M.Calc = Calc
M.MSG = { editMode = MSG_EDITMODE, combat = MSG_COMBAT, locked = MSG_LOCKED, off = MSG_OFF }

M._undo, M._redo = {}, {}
M._shadow = {}
M._selection = {}
M._depth = 0
M._hooked = setmetatable({}, { __mode = "k" })
M._drag = {}

-- Stato di un frame = copia della sua tabella nel profilo ({} se assente).
local function copyState(c)
    local r = {}
    if type(c) == "table" then
        for k, v in pairs(c) do r[k] = type(v) == "table" and Badb.CopyTable(v) or v end
    end
    return r
end

local function liveState(key)
    local frames = DB.profile and DB.profile.frames
    return copyState(frames and frames[key])
end

local function resolveFrame(key)
    local desc = FM.registry[key]
    if not desc then return nil end
    if type(desc.frame) == "table" then return desc.frame, desc end
    return _G[desc.frame], desc
end

local function isProtected(f)
    local ok, v = pcall(f.IsProtected, f)
    return ok and v and true or false
end

-- Messaggio per i frame Edit Mode: esatto di norma, con suggerimento se il layout attivo e' un preset Blizzard.
-- Come in EditModeBridge, activeLayout oltre la lista utente = preset Blizzard.
local function editModeMessage()
    if Compat.hasEditMode and C_EditMode and C_EditMode.GetLayouts then
        local ok, layouts = pcall(C_EditMode.GetLayouts)
        if ok and type(layouts) == "table" and type(layouts.layouts) == "table"
            and layouts.activeLayout and not layouts.layouts[layouts.activeLayout] then
            return MSG_EDITMODE_PRESET
        end
    end
    return MSG_EDITMODE
end

local function title(key)
    local desc = FM.registry[key]
    return desc and desc.title or key
end

local function notify(fmt, ...) Logger:Info(fmt, ...) end

-------------------------------------------------------------------------------
-- Geometria
-------------------------------------------------------------------------------
local function parentCenter()
    local ok, ux, uy = pcall(function() return UIParent:GetCenter() end)
    if ok and isnum(ux) and isnum(uy) and not Compat.IsSecret(ux) and not Compat.IsSecret(uy) then return ux, uy end
    return 0, 0
end

local function frameSize(f)
    local ok, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
    if ok and isnum(w) and isnum(h) and not Compat.IsSecret(w) and not Compat.IsSecret(h) then return w, h end
    if ok and isnum(w) and not Compat.IsSecret(w) then return w, 0 end
    return 0, 0
end

-- Rect del frame (centro relativo a UIParent). Ritorna rect oppure nil, motivo.
local function rectOf(key)
    local f = resolveFrame(key)
    if not f then return nil, L["frame non disponibile"] end
    local w, h = frameSize(f)
    local ok, cx, cy = pcall(function() return f:GetCenter() end)
    if ok and isnum(cx) and isnum(cy) and not Compat.IsSecret(cx) and not Compat.IsSecret(cy) then
        local ux, uy = parentCenter()
        return { key = key, x = cx - ux, y = cy - uy, w = w, h = h }
    end
    local c = DB.profile and DB.profile.frames[key]
    if c and c.point == "CENTER" and (c.relPoint == nil or c.relPoint == "CENTER") and isnum(c.x) and isnum(c.y) then
        return { key = key, x = c.x, y = c.y, w = w, h = h }
    end
    return nil, L["geometria non disponibile"]
end

-- Posizione corrente per il nudge: preferisce quanto salvato dal FrameManager.
local function positionOf(key)
    local c = DB.profile and DB.profile.frames[key]
    if c and c.point == "CENTER" and (c.relPoint == nil or c.relPoint == "CENTER") and isnum(c.x) and isnum(c.y) then
        return c.x, c.y
    end
    local r = rectOf(key)
    if r then return r.x, r.y end
end

local function clampCoord(v)
    if v > COORD_LIMIT then return COORD_LIMIT end
    if v < -COORD_LIMIT then return -COORD_LIMIT end
    return v
end

-------------------------------------------------------------------------------
-- Gruppi
-------------------------------------------------------------------------------
function M:_groups()
    local g = self:Get("groups")
    if type(g) ~= "table" then g = {} end
    return g
end

-- Nome del gruppo bloccato che contiene il frame (nil se libero).
function M:LockedGroupOf(key)
    for name, g in pairs(self:_groups()) do
        if type(g) == "table" and g.locked and type(g.keys) == "table" then
            for _, k in ipairs(g.keys) do
                if k == key then return name end
            end
        end
    end
end

function M:Group(name, keys)
    if not self._active then return false, MSG_OFF end
    if type(name) ~= "string" or name == "" or #name > 40 then return false, L["nome gruppo non valido"] end
    local valid = {}
    for _, k in ipairs(Calc.Unique(keys)) do
        if FM.registry[k] and #valid < MAX_GROUP_KEYS then valid[#valid + 1] = k end
    end
    if #valid == 0 then return false, L["nessun frame valido"] end
    local groups = self:_groups()
    local count = 0
    for _ in pairs(groups) do count = count + 1 end
    if not groups[name] and count >= MAX_GROUPS then return false, L["troppi gruppi"] end
    local locked = type(groups[name]) == "table" and groups[name].locked or false
    groups[name] = { keys = valid, locked = locked and true or false }
    self:Set("groups", groups)
    return true
end

function M:Ungroup(name)
    if not self._active then return false, MSG_OFF end
    local groups = self:_groups()
    if type(name) ~= "string" or not groups[name] then return false, L["gruppo inesistente"] end
    groups[name] = nil
    self:Set("groups", groups)
    return true
end

-- Il blocco vale per le modifiche fatte da questo modulo (nudge, allinea, distribuisci, undo/redo).
-- Non impedisce al FrameManager o ad altri moduli di scrivere sul frame.
function M:SetGroupLock(name, locked)
    if not self._active then return false, MSG_OFF end
    local groups = self:_groups()
    local g = type(name) == "string" and groups[name]
    if type(g) ~= "table" then return false, L["gruppo inesistente"] end
    g.locked = locked and true or false
    self:Set("groups", groups)
    return true
end

function M:GetGroups()
    local out = {}
    for name, g in pairs(self:_groups()) do
        if type(g) == "table" then
            out[name] = { keys = Calc.Unique(g.keys), locked = g.locked and true or false }
        end
    end
    return out
end

function M:SelectGroup(name)
    local g = type(name) == "string" and self:_groups()[name]
    if type(g) ~= "table" then return false, L["gruppo inesistente"] end
    self._selection = {}
    for _, k in ipairs(Calc.Unique(g.keys)) do
        if FM.registry[k] then self._selection[#self._selection + 1] = k end
    end
    self:_selectionChanged()
    return true
end

-------------------------------------------------------------------------------
-- Controlli comuni (Edit Mode, gruppi, combattimento)
-------------------------------------------------------------------------------
-- mode "move": nudge/allinea/distribuisci. mode "replay": undo/redo (Edit Mode ammesso:
-- il FrameManager ignora gia' posizione e scala su quei frame).
function M:_guard(key, mode)
    local f = resolveFrame(key)
    if mode == "move" then
        if not FM.registry[key] then return false, L["frame sconosciuto: "] .. tostring(key) end
        if not f then return false, L["frame non disponibile: "] .. tostring(key) end
        if Compat.IsEditModeFrame(f) then return false, editModeMessage() end
    end
    local g = self:LockedGroupOf(key)
    if g then return false, MSG_LOCKED .. ": " .. g end
    if f and InCombatLockdown() and isProtected(f) then return false, MSG_COMBAT end
    return true
end

-------------------------------------------------------------------------------
-- Storia: transazioni, undo, redo
-------------------------------------------------------------------------------
function M:_max()
    local n = tonumber(self:Get("maxHistory")) or 100
    n = math.floor(n)
    if n < 1 then n = 1 end
    if n > MAX_HISTORY_CAP then n = MAX_HISTORY_CAP end
    return n
end

function M:CanUndo() return #self._undo > 0 end
function M:CanRedo() return #self._redo > 0 end

function M:_fireHistory()
    Events:Fire("BADB_LAYOUT_HISTORY", self:CanUndo(), self:CanRedo())
    self:_refreshPage()
end

function M:_resync()
    self._framesRef = DB.profile and DB.profile.frames
    self._shadow = {}
    if self._framesRef then
        for key, c in pairs(self._framesRef) do self._shadow[key] = copyState(c) end
    end
end

-- Svuota storia, selezione e transazioni (cambio profilo, disattivazione, ripristino backup...).
function M:_reset()
    self._undo, self._redo = {}, {}
    self._last = nil
    self._txn, self._depth = nil, 0
    self._drag = {}
    self._selection = {}
    self:_resync()
    self:_selectionChanged()
    self:_fireHistory()
end

-- Se la tabella frames del profilo e' cambiata la storia non e' piu' valida.
function M:_checkGen()
    if DB.profile and DB.profile.frames ~= self._framesRef then
        self:_reset()
        return true
    end
    return false
end

function M:_begin(label, auto)
    if self._depth == 0 then
        self._txn = { label = label, auto = auto and true or false, changes = {}, order = {} }
    end
    self._depth = self._depth + 1
end

function M:_touch(key, before)
    local txn = self._txn
    if not txn or txn.changes[key] then return end
    txn.changes[key] = before and copyState(before) or copyState(self._shadow[key])
    txn.order[#txn.order + 1] = key
end

function M:_commit(txn)
    local entry = { label = txn.label, time = GetTime(), keys = {}, before = {}, after = {}, auto = txn.auto }
    for _, key in ipairs(txn.order) do
        local before, after = txn.changes[key], liveState(key)
        self._shadow[key] = copyState(after)
        if not same(before, after) then
            entry.keys[#entry.keys + 1] = key
            entry.before[key], entry.after[key] = before, after
        end
    end
    if #entry.keys == 0 then return end

    -- Coalescenza: modifiche automatiche ravvicinate sullo stesso frame = un solo passo.
    local undo = self._undo
    local top = undo[#undo]
    if txn.auto and top and top == self._last and top.auto and #top.keys == 1 and #entry.keys == 1
        and top.keys[1] == entry.keys[1]
        and entry.time - top.time <= (tonumber(self:Get("coalesceWindow")) or 0.4) then
        local key = entry.keys[1]
        top.after[key], top.time = entry.after[key], entry.time
        if same(top.before[key], top.after[key]) then
            table.remove(undo)
            self._last = nil
        end
        self:_fireHistory()
        return
    end

    undo[#undo + 1] = entry
    self._last = entry
    self._redo = {}
    local max = self:_max()
    while #undo > max do table.remove(undo, 1) end
    self:_fireHistory()
end

function M:_end()
    if self._depth == 0 then return end
    self._depth = self._depth - 1
    if self._depth == 0 then
        local txn = self._txn
        self._txn = nil
        if txn then self:_commit(txn) end
    end
end

-- Transazione esplicita: tutto cio' che cambia tra Begin e End e' un unico passo di undo.
function M:Begin(label)
    if not self._active then return false, MSG_OFF end
    self:_checkGen()
    self:_begin(type(label) == "string" and label or nil, false)
    return true
end

function M:End()
    if not self._active then return false, MSG_OFF end
    self:_end()
    return true
end

-- Esegue fn dentro una transazione garantendo la chiusura anche in caso di errore.
function M:_transaction(label, fn)
    self:_checkGen()
    self:_begin(label, false)
    local ok, err = pcall(fn)
    self:_end()
    if not ok then
        Logger:Error("LayoutStudio: %s", tostring(err))
        return false, tostring(err)
    end
    return true
end

function M:_onChanged(key)
    if not self._active or self._replaying or self._quiet or type(key) ~= "string" then return end
    if self:_checkGen() then return end
    if self._depth > 0 then
        self:_touch(key)
        return
    end
    self:_begin(nil, true)
    self:_touch(key)
    self:_end()
end

-- Porta DB.profile.frames[key] allo stato `target` usando solo API pubbliche del FrameManager.
function M:_setState(key, target)
    local frames = DB.profile.frames
    local cur = frames[key] or {}
    local reset = false
    for f in pairs(cur) do
        if target[f] == nil then reset = true end
    end
    if cur.hidden and not target.hidden then reset = true end -- FM:Apply non rimostra da solo
    if reset then
        -- FM:Restore chiama Show() prima di azzerare la config: l'hook "hidden" del FrameManager
        -- lo richiuderebbe. Si toglie quindi prima il flag (vedi "Richieste al core").
        if cur.hidden then cur.hidden = nil end
        FM:Restore(key)
        local left = DB.profile.frames[key]
        if left then
            -- Restore non fa nulla senza stato originale: ripulisce i campi residui.
            for f in pairs(left) do
                if target[f] == nil then FM:SetOption(key, f, nil) end
            end
        end
    end
    local order, seen = {}, {}
    for _, f in ipairs({ "point", "relPoint", "x", "y", "scale", "alpha", "hidden" }) do
        if target[f] ~= nil then order[#order + 1] = f; seen[f] = true end
    end
    for f in pairs(target) do if not seen[f] then order[#order + 1] = f end end
    for _, f in ipairs(order) do
        local live = DB.profile.frames[key] and DB.profile.frames[key][f]
        if not same(live, target[f]) then
            local v = target[f]
            FM:SetOption(key, f, type(v) == "table" and Badb.CopyTable(v) or v)
        end
    end
end

function M:_step(from, to, stateKey, emptyMsg)
    if not self._active then return false, MSG_OFF end
    self:_checkGen()
    local e = from[#from]
    if not e then return false, emptyMsg end
    for _, key in ipairs(e.keys) do
        local ok, err = self:_guard(key, "replay")
        if not ok then return false, err end
    end
    self._replaying = true
    local ok, err = pcall(function()
        for _, key in ipairs(e.keys) do self:_setState(key, e[stateKey][key]) end
    end)
    self._replaying = false
    if not ok then
        Logger:Error("LayoutStudio: %s", tostring(err))
        return false, tostring(err)
    end
    table.remove(from)
    to[#to + 1] = e
    self._last = nil
    for _, key in ipairs(e.keys) do self._shadow[key] = liveState(key) end
    self:_fireHistory()
    return true
end

function M:Undo() return self:_step(self._undo, self._redo, "before", L["niente da annullare"]) end
function M:Redo() return self:_step(self._redo, self._undo, "after", L["niente da ripetere"]) end

local function describeEntry(e)
    if #e.keys == 1 then
        local key = e.keys[1]
        local d = Calc.Diff(e.before[key], e.after[key])
        return title(key) .. ": " .. (d ~= "" and d or L["modificato"])
    end
    return string.format(L["%s (%d frame)"], e.label or L["Modifica"], #e.keys)
end

-- Cronologia dal piu' recente al piu' vecchio. `undone` = passo annullato (ripetibile).
function M:GetHistory(limit)
    local out = {}
    limit = tonumber(limit) or MAX_HISTORY_CAP
    local function add(e, undone)
        if #out < limit then
            out[#out + 1] = { text = describeEntry(e), label = e.label, keys = Calc.Unique(e.keys), time = e.time, undone = undone }
        end
    end
    for i = 1, #self._redo do add(self._redo[i], true) end
    for i = #self._undo, 1, -1 do add(self._undo[i], false) end
    return out, self:CanUndo(), self:CanRedo()
end

function M:ClearHistory()
    self._undo, self._redo, self._last = {}, {}, nil
    self:_fireHistory()
    return true
end

-------------------------------------------------------------------------------
-- Applicazione di posizioni (via FrameManager)
-------------------------------------------------------------------------------
-- positions = { [key] = {x=, y=} } con centri relativi a UIParent.
function M:_applyPositions(positions, label)
    local keys = {}
    for key in pairs(positions) do keys[#keys + 1] = key end
    table.sort(keys)
    return self:_transaction(label, function()
        for _, key in ipairs(keys) do
            local p = positions[key]
            local c = DB.profile.frames[key] or {}
            local x, y = clampCoord(p.x), clampCoord(p.y)
            -- Il before va letto prima di toccare il frame (lo shadow puo' essere vecchio).
            self:_touch(key, c)
            if c.point ~= "CENTER" then FM:SetOption(key, "point", "CENTER") end
            if c.relPoint ~= "CENTER" then FM:SetOption(key, "relPoint", "CENTER") end
            if c.x ~= x then FM:SetOption(key, "x", x) end
            if c.y ~= y then FM:SetOption(key, "y", y) end
        end
    end)
end

local function guardAll(self, keys, mode)
    for _, key in ipairs(keys) do
        local ok, err = self:_guard(key, mode)
        if not ok then return false, err end
    end
    return true
end

function M:Nudge(frameKey, dx, dy)
    if not self._active then return false, MSG_OFF end
    if frameKey == nil then frameKey = self._selection[1] end
    if type(frameKey) ~= "string" then return false, L["frame non valido"] end
    dx, dy = tonumber(dx), tonumber(dy)
    if not (isnum(dx) and isnum(dy)) then return false, L["spostamento non valido"] end
    local ok, err = self:_guard(frameKey, "move")
    if not ok then return false, err end
    local x, y = positionOf(frameKey)
    if not x then return false, L["geometria non disponibile"] end
    return self:_applyPositions({ [frameKey] = { x = x + dx, y = y + dy } }, "Nudge")
end

-- Nudge di tutta la selezione in un solo passo di undo.
function M:NudgeSelection(dx, dy)
    if not self._active then return false, MSG_OFF end
    local keys = Calc.Unique(self._selection)
    if #keys == 0 then return false, L["nessuna selezione"] end
    dx, dy = tonumber(dx), tonumber(dy)
    if not (isnum(dx) and isnum(dy)) then return false, L["spostamento non valido"] end
    local ok, err = guardAll(self, keys, "move")
    if not ok then return false, err end
    local positions = {}
    for _, key in ipairs(keys) do
        local x, y = positionOf(key)
        if not x then return false, L["geometria non disponibile"] end
        positions[key] = { x = x + dx, y = y + dy }
    end
    return self:_applyPositions(positions, "Nudge")
end

-- Filtra le chiavi per allinea/distribuisci. Ritorna rects, info oppure nil, errore.
function M:_collect(keys)
    if type(keys) ~= "table" then return nil, L["elenco frame non valido"] end
    local list = Calc.Unique(keys)
    if #list == 0 then return nil, L["elenco frame vuoto"] end
    local info = { unknown = {}, editMode = {}, noGeometry = {} }
    local valid, editModeCount = {}, 0
    for _, key in ipairs(list) do
        local f = resolveFrame(key)
        if not FM.registry[key] or not f then
            info.unknown[#info.unknown + 1] = key
        elseif Compat.IsEditModeFrame(f) then
            info.editMode[#info.editMode + 1] = key
            editModeCount = editModeCount + 1
        else
            valid[#valid + 1] = key
        end
    end
    if #valid == 0 then
        if editModeCount > 0 and editModeCount == #list then return nil, editModeMessage() end
        return nil, L["nessun frame valido"]
    end
    local ok, err = guardAll(self, valid, "move")
    if not ok then return nil, err end
    local rects = {}
    for _, key in ipairs(valid) do
        local r = rectOf(key)
        if r then rects[#rects + 1] = r else info.noGeometry[#info.noGeometry + 1] = key end
    end
    return rects, info
end

local ALIGN_LABEL = {
    left = L["Allinea a sinistra"], right = L["Allinea a destra"], top = L["Allinea in alto"],
    bottom = L["Allinea in basso"], hcenter = L["Centra orizzontalmente"], vcenter = L["Centra verticalmente"],
}

function M:_arrange(keys, calcFn, arg, label)
    if not self._active then return false, MSG_OFF end
    local rects, info = self:_collect(keys)
    if not rects then return false, info end
    local positions, err = calcFn(rects, arg)
    if not positions then return false, err end
    local ok, terr = self:_applyPositions(positions, label)
    if not ok then return false, terr end
    local skipped = #info.unknown + #info.editMode + #info.noGeometry
    if skipped > 0 then
        notify(L["Layout: %d frame saltati (inesistenti, Edit Mode o senza geometria)"], skipped)
    end
    return true, nil, info
end

function M:Align(keys, mode)
    if not ALIGN_MODES[mode] then return false, L["modo di allineamento non valido"] end
    return self:_arrange(keys, Calc.Align, mode, ALIGN_LABEL[mode])
end

function M:Distribute(keys, axis)
    if axis ~= "h" and axis ~= "v" then return false, L["asse non valido (h|v)"] end
    return self:_arrange(keys, Calc.Distribute, axis,
        axis == "h" and L["Distribuisci orizzontalmente"] or L["Distribuisci verticalmente"])
end

-------------------------------------------------------------------------------
-- Griglia e snap
-------------------------------------------------------------------------------
function M:SetGridSize(n)
    n = tonumber(n)
    if not isnum(n) then return false, L["valore non valido"] end
    n = math.floor(n)
    if n < 1 then n = 1 end
    if n > 128 then n = 128 end
    if not (DB.sv and DB.sv.global) then return false, L["database non pronto"] end
    DB.sv.global.gridSize = n
    self:_refreshPage()
    return true, n
end

function M:GetGridSize()
    return DB.sv and DB.sv.global and DB.sv.global.gridSize or 8
end

-- Attiva/disattiva lo snap intelligente (bordi e centri degli altri frame).
-- Lo snap alla griglia del FrameManager e' del core e resta sempre attivo.
function M:ToggleSnap()
    local v = not self:Get("snap")
    self:Set("snap", v)
    self:_refreshPage()
    return v
end

function M:_smartSnap(key)
    if not self:Get("snap") or self:LockedGroupOf(key) then return end
    local r = rectOf(key)
    if not r then return end
    local others = {}
    for k in pairs(FM.registry) do
        if k ~= key then
            local f = resolveFrame(k)
            if f and f.IsShown and f:IsShown() then
                local o = rectOf(k)
                if o then others[#others + 1] = o end
            end
        end
    end
    local dx, dy = Calc.SnapDelta(r, others, tonumber(self:Get("snapThreshold")) or 6)
    if dx == 0 and dy == 0 then return end
    local c = DB.profile.frames[key] or {}
    if c.point ~= "CENTER" or not isnum(c.x) or not isnum(c.y) then return end
    if dx ~= 0 then FM:SetOption(key, "x", clampCoord(c.x + dx)) end
    if dy ~= 0 then FM:SetOption(key, "y", clampCoord(c.y + dy)) end
end

-------------------------------------------------------------------------------
-- Selezione, mover e tastiera
-------------------------------------------------------------------------------
local SEL_COLOR, BASE_COLOR = { 1, 0.82, 0, 1 }, { 0.25, 0.65, 1, 0.9 }

function M:GetSelection() return Calc.Unique(self._selection) end

function M:_paintMovers()
    local sel = {}
    for _, k in ipairs(self._selection) do sel[k] = true end
    for key, m in pairs(FM.movers or {}) do
        if type(m) == "table" and m.SetBackdropBorderColor then
            local c = (self._active and sel[key]) and SEL_COLOR or BASE_COLOR
            pcall(m.SetBackdropBorderColor, m, c[1], c[2], c[3], c[4])
        end
    end
end

function M:_selectionChanged()
    self:_paintMovers()
    self:_updateCapture()
    self:_refreshPage()
end

-- Seleziona un frame; con `add` = true alterna l'appartenenza (shift-click).
function M:Select(frameKey, add)
    if not self._active then return false, MSG_OFF end
    if frameKey == nil or frameKey == false then
        self._selection = {}
        self:_selectionChanged()
        return true
    end
    if type(frameKey) ~= "string" or not FM.registry[frameKey] then
        return false, L["frame sconosciuto: "] .. tostring(frameKey)
    end
    if add then
        local found
        for i, k in ipairs(self._selection) do
            if k == frameKey then found = i end
        end
        if found then table.remove(self._selection, found) else self._selection[#self._selection + 1] = frameKey end
    else
        self._selection = { frameKey }
    end
    self:_selectionChanged()
    return true
end

-- Seleziona tutti i frame spostabili (di una categoria, se indicata).
function M:SelectAll(category)
    if not self._active then return false, MSG_OFF end
    local keys = {}
    for key, desc in pairs(FM.registry) do
        local f = resolveFrame(key)
        if f and desc.movable ~= false and not Compat.IsEditModeFrame(f)
            and (category == nil or desc.category == category) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    self._selection = keys
    self:_selectionChanged()
    return true, #keys
end

function M:_captureWanted()
    return self._active and FM.unlocked and #self._selection > 0 and not InCombatLockdown()
end

-- Cattura la tastiera SOLO con frame sbloccati e una selezione; altrimenti non tocca nulla.
function M:_updateCapture()
    local kb = self._kb
    if not kb then return end
    if self:_captureWanted() then
        kb:Show()
        kb:EnableKeyboard(true)
        kb:SetPropagateKeyboardInput(true)
        self._capturing = true
    else
        kb:EnableKeyboard(false)
        kb:Hide()
        self._capturing = false
    end
end

function M:IsCapturing() return self._capturing and true or false end

local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

-- Ritorna true solo per i tasti consumati davvero (frecce, Ctrl+Z / Ctrl+Y).
local function handleKey(key)
    local shift = IsShiftKeyDown and IsShiftKeyDown() or false
    local ctrl = IsControlKeyDown and IsControlKeyDown() or false
    local dir = ARROWS[key]
    if dir then
        local step = Calc.Step(shift, ctrl, M:GetGridSize())
        M:NudgeSelection(dir[1] * step, dir[2] * step)
        return true
    end
    if ctrl and key == "Z" then
        if shift then M:Redo() else M:Undo() end
        return true
    end
    if ctrl and key == "Y" then
        M:Redo()
        return true
    end
    return false
end

local function createKeyboardOverlay()
    local kb = Compat.CreateFrame("Frame", nil, UIParent)
    kb:SetSize(1, 1)
    kb:EnableMouse(false)
    kb:EnableKeyboard(false)
    kb:SetScript("OnKeyDown", function(self, key)
        local handled = false
        if M._active and M:_captureWanted() then
            local ok, res = pcall(handleKey, key)
            handled = ok and res or false
        end
        -- Cio' che non gestiamo passa sempre al gioco: nessun tasto resta "mangiato".
        self:SetPropagateKeyboardInput(not handled)
    end)
    kb:Hide()
    return kb
end

-- Aggancia i mover creati dal FrameManager (sondaggio difensivo: se mancano, niente errori).
function M:_hookMovers()
    if type(FM.movers) ~= "table" then return end
    for key, m in pairs(FM.movers) do
        if type(m) == "table" and not self._hooked[m] and type(m.HookScript) == "function" then
            self._hooked[m] = true
            pcall(function()
                m:HookScript("OnMouseDown", function(_, button)
                    if not M._active or button == "RightButton" then return end
                    local add = IsShiftKeyDown and IsShiftKeyDown() or false
                    M:Select(key, add)
                end)
                m:HookScript("OnDragStart", function()
                    if M._active then M._drag[key] = liveState(key) end
                end)
                m:HookScript("OnDragStop", function()
                    if not M._active then return end
                    local before = M._drag[key]
                    M._drag[key] = nil
                    M:_checkGen()
                    M:_begin(L["Sposta"], false)
                    M:_touch(key, before)
                    pcall(M._smartSnap, M, key)
                    M:_end()
                end)
            end)
        end
    end
end

-------------------------------------------------------------------------------
-- Pagina ConfigUI e comandi
-------------------------------------------------------------------------------
local HISTORY_LINES = 10

local function selectionText()
    local sel = M:GetSelection()
    if #sel == 0 then return L["Selezione: nessuna (clic su un frame sbloccato, shift-clic per piu' frame)"] end
    local names = {}
    for i, k in ipairs(sel) do
        if i > 4 then names[#names + 1] = string.format("+%d", #sel - 4); break end
        names[#names + 1] = title(k)
    end
    return L["Selezione: "] .. table.concat(names, ", ")
end

local function report(ok, err)
    if not ok and err then Logger:Warn("Layout: %s", tostring(err)) end
    return ok, err
end

local function setEnabled(btn, state)
    if not btn then return end
    if btn.SetEnabled then btn:SetEnabled(state and true or false)
    elseif state and btn.Enable then btn:Enable()
    elseif btn.Disable then btn:Disable() end
    btn.__enabledState = state and true or false
end

function M:_refreshPage()
    local ui = self._ui
    if not ui then return end
    pcall(function()
        setEnabled(ui.undo, self:CanUndo())
        setEnabled(ui.redo, self:CanRedo())
        if ui.selection then ui.selection:SetText(selectionText()) end
        local hist = self:GetHistory(HISTORY_LINES)
        for i = 1, HISTORY_LINES do
            local line = ui.lines[i]
            if line then
                local h = hist[i]
                line:SetText(h and ((h.undone and L["(annullato) "] or "") .. h.text) or "")
            end
        end
    end)
end

local function buildPage(parent, ctx)
    local W = ctx and ctx.W or Badb.Widgets
    local B = W and W.Builders or {}
    local ui = { lines = {} }
    local y = 0

    local function place(builder, opt, x, dy)
        local build = B[builder]
        if not build then return end
        local w, h = build(parent, M, opt)
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, -y - (dy or 0))
        y = y + h
        return w
    end
    local function button(text, x, width, func)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        b:SetScript("OnClick", function() pcall(func) M:_refreshPage() end)
        return b
    end
    local function label(text, template)
        local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
        fs:SetText(text)
        return fs
    end

    place("header", { type = "header", label = "Layout Studio" })
    place("range", {
        type = "range", label = L["Dimensione griglia (px)"], min = 1, max = 64, step = 1,
        get = function() return M:GetGridSize() end,
        set = function(v) M:SetGridSize(v) end,
    }, 20, 14)
    y = y + 6
    place("toggle", {
        type = "toggle", label = L["Snap intelligente ai bordi degli altri frame"],
        get = function() return M:Get("snap") end,
        set = function(v) M:Set("snap", v and true or false) end,
    })

    y = y + 6
    button(L["Sblocca"], 16, 90, function() FM:SetUnlocked(true) end)
    button(L["Blocca"], 112, 90, function() FM:SetUnlocked(false) end)
    ui.undo = button(L["Annulla"], 220, 90, function() report(M:Undo()) end)
    ui.redo = button(L["Ripeti"], 316, 90, function() report(M:Redo()) end)
    y = y + 32

    ui.selection = label(selectionText())
    y = y + 20
    button(L["Seleziona tutti"], 16, 120, function() M:SelectAll() end)
    button(L["Deseleziona"], 142, 120, function() M:Select(nil) end)
    y = y + 32

    label(L["Allinea la selezione"], "GameFontNormal")
    y = y + 20
    local modes = {
        { "left", L["Sinistra"] }, { "right", L["Destra"] }, { "top", L["Alto"] },
        { "bottom", L["Basso"] }, { "hcenter", L["Centro O."] }, { "vcenter", L["Centro V."] },
    }
    for i, m in ipairs(modes) do
        button(m[2], 16 + (i - 1) * 86, 82, function() report(M:Align(M:GetSelection(), m[1])) end)
    end
    y = y + 28
    button(L["Distribuisci orizz."], 16, 130, function() report(M:Distribute(M:GetSelection(), "h")) end)
    button(L["Distribuisci vert."], 152, 130, function() report(M:Distribute(M:GetSelection(), "v")) end)
    y = y + 34

    label(L["Cronologia (ultime modifiche)"], "GameFontNormal")
    y = y + 20
    for i = 1, HISTORY_LINES do
        ui.lines[i] = label("")
        y = y + 16
    end

    M._ui = ui
    M:_refreshPage()
    return y + 12
end

M.page = {
    title = "Layout",
    order = 40,
    category = L["Strumenti"],
    build = buildPage,
    refresh = function() M:_refreshPage() end,
}

local function parseArgs(str)
    local t = {}
    for w in tostring(str or ""):gmatch("%S+") do t[#t + 1] = w end
    return t
end

local COMMAND_HELP = L["layout undo | redo | grid <n> | nudge <chiave> <dx> <dy> | snap"] .. " | default"

M.commands = {
    layout = {
        help = COMMAND_HELP,
        fn = function(args)
            local t = parseArgs(args)
            local sub = (t[1] or ""):lower()
            local ok, err
            if sub == "default" then
                local bridge = Badb.EditModeBridge
                if bridge and bridge.ApplyDefault then
                    ok, err = bridge:ApplyDefault(true)
                else
                    err = L["Layout predefinito non disponibile"]
                end
            elseif sub == "undo" then ok, err = M:Undo()
            elseif sub == "redo" then ok, err = M:Redo()
            elseif sub == "grid" then
                local n
                ok, n = M:SetGridSize(t[2])
                if ok then notify(L["Layout: griglia %d px"], n) else err = n end
            elseif sub == "nudge" then ok, err = M:Nudge(t[2], t[3], t[4])
            elseif sub == "snap" then
                notify(L["Layout: snap intelligente %s"], M:ToggleSnap() and L["attivo"] or L["disattivo"])
                return
            else
                notify("/badb %s", COMMAND_HELP)
                return
            end
            if not ok then Logger:Warn("Layout: %s", tostring(err)) end
        end,
    },
}

-------------------------------------------------------------------------------
-- Ciclo di vita
-------------------------------------------------------------------------------
function M:OnEnable()
    self._active = true
    self._kb = self._kb or createKeyboardOverlay()
    self._undo, self._redo, self._last = {}, {}, nil
    self._txn, self._depth, self._drag, self._selection = nil, 0, {}, {}
    self:_resync()

    -- Il drag di un mover emette "position" PRIMA del nostro hook OnDragStop, che registra gia' il passo
    -- (con lo stato di partenza e lo snap intelligente): durante un drag l'evento si ignora per non duplicarlo.
    self:On("BADB_FRAME_CHANGED", function(_, key, field)
        if field == "position" and self._drag and self._drag[key] then return end
        self:_onChanged(key)
    end)
    self:On("BADB_PROFILE_CHANGED", function()
        self:_reset()
        -- FM ripristina i frame (con Restore) nello stesso dispatch: ignora quei Restore.
        self._quiet = true
        Compat.After(0, function()
            self._quiet = false
            if self._active then self:_resync() end
        end)
    end)
    self:On("BADB_UNLOCK_CHANGED", function()
        self:_hookMovers()
        self:_paintMovers()
        self:_updateCapture()
    end)
    self:On("PLAYER_REGEN_DISABLED", function() self:_updateCapture() end)
    -- Operazioni che riscrivono i frame in blocco: la storia precedente non e' piu' affidabile.
    local function invalidate() if self._active then self:_reset() end end
    self:On("BADB_PRESET_APPLIED", invalidate)
    self:On("BADB_PRESET_UNDONE", invalidate)
    self:On("BADB_BACKUP_RESTORED", invalidate)

    self:_hookMovers()
    self:_fireHistory()
end

function M:OnProfileChanged()
    if self._active then self:_reset() end
end

function M:OnDisable()
    self._active = false
    self._capturing = false
    if self._kb then
        self._kb:EnableKeyboard(false)
        self._kb:Hide()
    end
    self._undo, self._redo, self._last = {}, {}, nil
    self._txn, self._depth, self._drag, self._selection = nil, 0, {}, {}
    self._shadow = {}
    self._replaying, self._quiet = false, false
    self:_paintMovers()
    Events:OffAll(self)
    self:_refreshPage()
    Events:Fire("BADB_LAYOUT_HISTORY", false, false)
end
