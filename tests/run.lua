-- Runner test: dalla root del repo, `lua tests/run.lua` (Lua 5.1+).
-- Carica i file dell'addon nell'ordine della TOC con lo stesso namespace condiviso del client.
package.path = "tests/lua/?.lua;" .. package.path
require("wowstub")

local ns = {}
local FILES = {
    "Core/Init.lua", "Core/Compat.lua", "Core/Logger.lua", "Core/Events.lua", "Core/Serializer.lua",
    "Core/Database.lua", "Core/Modules.lua", "Core/FrameManager.lua", "Core/CVars.lua",
    "Modules/Hider.lua", "Modules/Scaling.lua",
    "Modules/Nameplates.lua", "Modules/GroupFrames.lua", "Modules/Presets.lua",
}
for _, path in ipairs(FILES) do
    local chunk = assert(loadfile(path))
    chunk("BadbUI", ns)
end

local passed, failed = 0, 0
function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("  ok   " .. name)
    else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

WOWSTUB.fire("ADDON_LOADED", "BadbUI")
WOWSTUB.fire("PLAYER_LOGIN")

for _, suite in ipairs({ "test_cvars", "test_nameplates", "test_groupframes", "test_presets" }) do
    print(suite)
    local fn = assert(loadfile("tests/lua/" .. suite .. ".lua"))
    fn(ns.Badb)
end
print(string.format("\n%d passati, %d falliti", passed, failed))
if failed > 0 then os.exit(1) end
