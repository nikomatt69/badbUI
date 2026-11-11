-- BadbUI - System profile: adatta scala e qualita' grafica al PC reale.
-- Un addon non puo' leggere modello GPU, CPU o sistema operativo: i segnali
-- legali sono risoluzione fisica, FPS misurati e le CVar grafiche esistenti.
-- La classificazione usa solo quelli; il resto e' dichiarato come limite.
local _, ns = ...
local Badb, L = ns.Badb, ns.Badb.L
local Compat, Logger = Badb.Compat, Badb.Logger

local M = Badb.Modules:New("SystemProfile", {
    title = L["Profilo PC e grafica"],
    category = L["Interfaccia"],
    description = L["Classifica il PC da risoluzione e FPS misurati e applica scala e qualita' consigliate."],
    defaults = { enabled = true, tier = "auto", samples = {} },
    page = { title = L["Profilo PC e grafica"], order = 40, category = L["Interfaccia"],
        keywords = { "pc", "gpu", "graphics", "fps", L["Grafica"], L["Prestazioni"] } },
})
Badb.SystemProfile = M

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return Compat.SafeValue(v) end
end
local function num(v, lo, hi)
    v = Compat.SafeValue(v)
    return type(v) == "number" and v == v and v >= lo and v <= hi and v or nil
end

-- Tier da megapixel del display e FPS sostenuti. Funzione pura (testabile).
function M.Classify(width, height, fps)
    local w, h = num(width, 320, 16384), num(height, 200, 16384)
    if not w or not h then return nil end
    local mp = w * h / 1000000
    local f = num(fps, 1, 1000)
    if f then
        if f < 30 then return "performance" end
        if f < 50 and mp > 2 then return "balanced" end
    end
    if mp <= 2.1 then return "balanced" end       -- fino a 1080p
    if mp <= 3.7 then return f and f >= 55 and "quality" or "balanced" end  -- 1440p
    return f and f >= 55 and "ultra" or "quality" -- 4K e oltre
end

-- Consigli per tier: scala suggerita e CVar candidate (applicate solo se esistono).
M.PROFILES = {
    performance = { scale = 0.64, cvars = { shadowQuality = "0", particleDensity = "2", farclip = "185" } },
    balanced    = { scale = 0.71, cvars = { shadowQuality = "1", particleDensity = "5", farclip = "400" } },
    quality     = { scale = 0.71, cvars = { shadowQuality = "2", particleDensity = "8", farclip = "700" } },
    ultra       = { scale = 0.82, cvars = { shadowQuality = "3", particleDensity = "10", farclip = "1000" } },
}

function M:Probe()
    local w, h
    if type(GetPhysicalScreenSize) == "function" then w, h = call(GetPhysicalScreenSize), select(2, pcall(GetPhysicalScreenSize)) end
    local fps = call(GetFramerate)
    return { width = num(w, 320, 16384), height = num(h, 200, 16384), fps = num(fps, 1, 1000) }
end

function M:Detect()
    local p = self:Probe()
    return M.Classify(p.width, p.height, p.fps), p
end

-- Registra un campione FPS (chiamato da timer, mai per frame).
function M:Sample()
    local fps = num(call(GetFramerate), 1, 1000)
    if not fps then return nil end
    local s = self:Get("samples")
    if type(s) ~= "table" then s = {} end
    s[#s + 1] = math.floor(fps)
    while #s > 30 do table.remove(s, 1) end
    self:Set("samples", s)
    local sum = 0
    for _, v in ipairs(s) do sum = sum + v end
    return sum / #s
end

function M:Apply(tier)
    tier = tier or self:Detect()
    local profile = tier and M.PROFILES[tier]
    if not profile then return false, L["Dati dello schermo non disponibili su questo client."] end
    local applied = {}
    if Badb.CVars then
        for name, value in pairs(profile.cvars) do
            if Badb.CVars:Exists(name) then Badb.CVars:Set("SystemProfile", name, value); applied[#applied + 1] = name end
        end
    end
    self:Set("tier", tier)
    Logger:Info(L["Profilo PC applicato: %s (scala consigliata %.2f, CVar: %s)"], tier, profile.scale,
        #applied > 0 and table.concat(applied, ", ") or L["nessuna"])
    return true, tier
end

function M:OnEnable()
    self:On("PLAYER_ENTERING_WORLD", function()
        local avg = self:Sample()
        local tier = self:Detect()
        if tier then Logger:Debug("SystemProfile: tier=%s fps=%s", tier, tostring(avg)) end
    end)
end
function M:OnDisable() if Badb.CVars then Badb.CVars:Restore("SystemProfile") end end

M.options = {
    { type = "label", text = function()
        local tier, p = M:Detect()
        if not tier then return L["Dati dello schermo non disponibili su questo client."] end
        return string.format(L["Display %sx%s, FPS %s. Tier rilevato: %s. Un addon non puo' leggere GPU, CPU o sistema operativo: la classifica usa risoluzione e FPS reali."],
            tostring(p.width), tostring(p.height), p.fps and string.format("%.0f", p.fps) or "?", tier)
    end },
    { type = "execute", label = L["Applica il profilo consigliato"], func = function() M:Apply() end },
    { type = "execute", label = L["Ripristina grafica originale"], func = function() if Badb.CVars then Badb.CVars:Restore("SystemProfile") end end },
}
M.commands = {
    system = { help = L["system [apply] - mostra o applica il profilo PC/grafica"], fn = function(args)
        if (args or ""):find("apply") then M:Apply()
        else local tier, p = M:Detect(); Logger:Info("System: %s (%sx%s, %s FPS)", tostring(tier), tostring(p.width), tostring(p.height), tostring(p.fps)) end
    end },
}
