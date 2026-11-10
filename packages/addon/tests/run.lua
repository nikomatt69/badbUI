-- BadbUI - test runner minimale (Lua 5.1, nessuna dipendenza).
-- Uso:  lua5.1 tests/run.lua            (dalla radice del repo)
-- Ogni file tests/*_test.lua restituisce una tabella { ["nome test"] = function(Mock) ... end }
-- e viene eseguito in un ambiente pulito: addon ricaricato da zero per ogni file.
local root = arg and arg[1] or "."
local onlySuite = arg and arg[2]

-- Auto-discovery: ogni tests/*_test.lua viene eseguito (ordine alfabetico).
local SUITES = {}
do
    local p = io.popen('ls "' .. root .. '/tests" 2>/dev/null')
    if p then
        for name in p:lines() do
            if name:match("_test%.lua$") and (not onlySuite or name:find(onlySuite, 1, true)) then
                SUITES[#SUITES + 1] = "tests/" .. name
            end
        end
        p:close()
    end
    table.sort(SUITES)
    assert(#SUITES > 0, "nessuna suite trovata in " .. root .. "/tests")
end

local passed, failed = 0, 0

local function freshEnv()
    -- Ripulisce i globali creati dal caso precedente.
    package.loaded["tests.wow_mock"] = nil
    for _, k in ipairs({ "BadbUI", "BadbUIDB", "BadbUI_GuildExport", "BadbUI_GuildSync", "BadbUI_ChatbotExport", "BadbUI_ChatbotSync", "MainActionBar", "MultiBarBottomLeft" }) do _G[k] = nil end
    local Mock = dofile(root .. "/tests/wow_mock.lua")
    Mock.CreateActionButtons("ActionButton", 12, "ACTIONBUTTON")
    Mock.CreateActionButtons("MultiBarBottomLeftButton", 12, "MULTIACTIONBAR1BUTTON")
    MainActionBar = Mock.NewObject("Frame")
    MultiBarBottomLeft = Mock.NewObject("Frame")
    Mock.LoadAddon(root, "BadbUI.toc")
    Mock.Fire("ADDON_LOADED", "BadbUI")
    Mock.Fire("PLAYER_LOGIN")
    Mock.Fire("PLAYER_ENTERING_WORLD")
    return Mock
end

for _, file in ipairs(SUITES) do
    local suite = dofile(root .. "/" .. file)
    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local Mock = freshEnv()
        local ok, err = pcall(suite[name], Mock)
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
