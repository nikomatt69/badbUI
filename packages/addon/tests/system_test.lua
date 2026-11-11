local T = {}
T["tier da risoluzione e FPS, API assenti sicure"] = function()
    local M = BadbUI.SystemProfile
    assert(M.Classify(1920, 1080, 90) == "balanced")
    assert(M.Classify(3840, 2160, 90) == "ultra")
    assert(M.Classify(3840, 2160, 20) == "performance")
    assert(M.Classify(2560, 1440, 60) == "quality")
    assert(M.Classify(nil, nil, nil) == nil)
    assert(M.PROFILES.ultra.cvars.shadowQuality == "3")
    assert(M:Get("cameraLock") == true)
    M:ApplyCamera()
    local tier, p = M:Detect()
    assert(tier == nil or type(tier) == "string")
    assert(type(p) == "table")
end
return T
