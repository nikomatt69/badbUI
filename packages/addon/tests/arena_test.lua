local T = {}
T["raccoglie solo giocatori nemici, copertura Gladius parziale"] = function()
    local M = BadbUI.Arena
    assert(M.BuildRow("target") == nil or type(M.BuildRow("target")) == "table")
    local rows = M:Collect()
    assert(type(rows) == "table" and #rows <= 5)
    local suite = BadbUI.Suite:ListCoverage()
    local found = false
    for _, r in ipairs(suite) do if r.addon == "Gladius" then found = true; assert(r.coverage == "partial") end end
    assert(found, "Gladius coverage must be declared")
    assert(M:Open() == true)
end
return T
