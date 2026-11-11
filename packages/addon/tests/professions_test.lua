local T = {}
local function loadProf()
    if BadbUI.Professions then return end
    local root = (arg and arg[1]) or "."
    local ns = { Badb = BadbUI }
    for _, rel in ipairs({ "Locales/Suite/Professions.lua", "Modules/Professions/Professions.lua" }) do
        local f = assert(io.open(root .. "/" .. rel)); local src = f:read("*a"); f:close()
        assert((loadstring or load)(src, "@" .. rel))("BadbUI", ns)
    end
    BadbUI.Modules:Enable("Professions")
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function with(globals, fn)
    local old = {}
    for k, v in pairs(globals) do old[k] = _G[k]; _G[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(globals) do _G[k] = old[k] end
    if not ok then error(err, 0) end
end

T["professioni: cattura ranghi, snapshot per personaggio e comandi"] = function(Mock) loadProf()
    with({
        GetProfessions = function() return 2, 1 end,
        GetProfessionInfo = function(i)
            if i == 1 then return "Erboristeria", nil, 120, 300 end
            return "Alchimia", nil, 75, 300
        end,
        GetSpellCooldown = function(id) if id == 100 then return Mock.time - 10, 60 end return 0, 0 end,
        GetSpellInfo = function(id) return "Incantesimo " .. tostring(id) end,
        GetTime = function() return Mock.time end,
    }, function()
        local m = BadbUI.Professions
        assert(m)
        local snap = m:Capture()
        eq(#snap.professions, 2)
        eq(snap.professions[1].name, "Alchimia")
        eq(snap.professions[2].rank, 120)
        eq(BadbUI.DB:GetStore("professions").characters[BadbUI.DB.char].professions[1].name, "Alchimia")
        eq(m:AddSpell(100), true)
        eq(m:AddSpell(100), true)
        eq(#m:GetSpellIDs(), 1)
        local cd = m:GetCooldown(100)
        eq(cd.remaining, 50)
        eq(cd.ready, false)
        eq(m.FormatRemaining(0), BadbUI.L["Pronto"])
        assert(m:SummaryLines()[1]:find("Alchimia"))
        eq(m:RemoveSpell(100), true)
        eq(#m:GetSpellIDs(), 0)
        assert(m.page.build(Mock.NewObject("Frame")) > 0)
        assert(BadbUI.ConfigUI:FindPage("mod:Professions"))
        assert(BadbUI.Guides:Get("professions:overview"))
        eq(#BadbUI.Suite:ListCoverage(), #BadbUI.Suite:ListCoverage()) -- replaces vuoto: nessuna riga finta
        for _, row in ipairs(BadbUI.Suite:ListCoverage()) do
            assert(row.module ~= "Professions", "Professions non deve dichiarare replaces")
        end
    end)
end

T["professioni: API assenti, valori segreti e dati corrotti non rompono"] = function(Mock) loadProf()
    with({
        GetProfessions = nil, GetProfessionInfo = nil,
        GetSpellCooldown = function() return Mock.Secret(), Mock.Secret() end,
    }, function()
        local m = BadbUI.Professions
        eq(m:HasProfessionAPI(), false)
        local snap, err = m:Capture()
        eq(snap, nil); assert(err)
        eq(m:GetCooldown(5), nil)
        local store = BadbUI.DB:GetStore("professions")
        store.characters = "corrotto"
        eq(m:GetSnapshot(), nil)
        store.characters = { [BadbUI.DB.char] = { professions = "x" } }
        eq(m:GetSnapshot(), nil)
        eq(m:AddSpell(0), false)
        eq(m:AddSpell("x"), false)
        eq(#m.ParseSpellIDs("1, x, 2;2 99999999"), 2)
        eq(#m.ParseSpellIDs(nil), 0)
    end)
    with({ GetProfessions = function() return 1 end,
        GetProfessionInfo = function() return Mock.Secret(), nil, Mock.Secret() end }, function()
        eq(#BadbUI.Professions:ReadProfessions(), 0)
    end)
end

T["professioni: combattimento, disattivazione e cambio profilo"] = function(Mock) loadProf()
    with({ GetProfessions = function() return 1 end,
        GetProfessionInfo = function() return "Miniera", nil, 10, 300 end }, function()
        local m = BadbUI.Professions
        Mock.combat = true
        assert(m:Capture())
        Mock.combat = false
        BadbUI.Modules:SetEnabled(m.name, false)
        eq(m.active, false)
        BadbUI.Modules:SetEnabled(m.name, true)
        eq(m.active, true)
        BadbUI.DB:SetProfile("AltroProf")
        eq(m:GetSnapshot().professions[1].name, "Miniera") -- store condiviso tra profili
    end)
end

return T
