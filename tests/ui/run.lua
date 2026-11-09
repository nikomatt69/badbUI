-- BadbUI - test del design system (Lua 5.1, nessuna dipendenza).
-- Uso:  lua5.1 tests/ui/run.lua [root]      (dalla radice del repo)
-- Ogni suite tests/ui/*_test.lua restituisce { ["nome"] = function(T) ... end }.
-- Ogni test parte da un client "pulito": mock reinstallato, addon ricaricato dalla TOC,
-- ADDON_LOADED + PLAYER_LOGIN sparati. T espone Mock, Badb, Theme, UI e asserzioni.
local root = arg and arg[1] or "."

local SUITES = {
    "tests/ui/theme_test.lua",
    "tests/ui/widgets_test.lua",
    "tests/ui/layout_test.lua",
}

local GLOBALS = { "BadbUI", "BadbUIDB", "BadbUIGallery", "BadbUIDropdownMenu", "UIParent", "GameTooltip", "issecretvalue" }

local function assertions(T)
    function T.eq(a, b, msg)
        if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
    end
    function T.ok(v, msg) if not v then error(msg or "condizione falsa", 2) end end
    function T.near(a, b, eps, msg)
        if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
            error((msg or "valori lontani") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2)
        end
    end
    function T.color(region) return region._color and unpack(region._color) end
    function T.sameColor(region, key, msg)
        local r, g, b, a = T.Theme:Get(key)
        local c = region._color
        if not c then error((msg or "region senza colore") .. " (" .. key .. ")", 2) end
        for i, v in ipairs({ r, g, b }) do
            if math.abs(c[i] - v) > 1e-6 then error((msg or "colore errato") .. ": atteso " .. key, 2) end
        end
    end
end

-- opts: { db = <BadbUIDB iniziale>, interface = n, secrets = bool, noLogin = bool, physH = n }
local function boot(opts)
    opts = opts or {}
    for _, k in ipairs(GLOBALS) do _G[k] = nil end
    for k in pairs(_G) do if type(k) == "string" and k:find("^BadbFont") then _G[k] = nil end end
    local Mock = dofile(root .. "/tests/ui/wow_mock.lua")
    Mock.install(opts)
    if opts.physH then Mock.state.physH = opts.physH end
    BadbUIDB = opts.db
    -- Core + Locales + design system + router slash: i moduli di gioco hanno la loro suite.
    Mock.loadAddon(root .. "/BadbUI.toc", "BadbUI", function(path)
        return path:find("^Core/") or path:find("^Locales/") or path:find("^UI/") or path == "Config/Slash.lua"
    end)
    Mock.fire("ADDON_LOADED", "BadbUI")
    if not opts.noLogin then Mock.fire("PLAYER_LOGIN") end
    local T = { Mock = Mock, Badb = BadbUI, Theme = BadbUI.Theme, UI = BadbUI.UI }
    assertions(T)
    T.boot = boot
    return T
end

local passed, failed = 0, 0
for _, file in ipairs(SUITES) do
    local suite = dofile(root .. "/" .. file)
    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(function() suite[name](boot, root) end)
        if ok then
            passed = passed + 1
            print("  ok    " .. file .. " :: " .. name)
        else
            failed = failed + 1
            print("  FAIL  " .. file .. " :: " .. name .. "\n        " .. tostring(err))
        end
    end
end

print(string.format("\n%d passati, %d falliti", passed, failed))
if failed > 0 then os.exit(1) end
