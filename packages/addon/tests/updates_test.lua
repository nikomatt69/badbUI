local T = {}
local function fixture(Mock)
    local u = BadbUI.Updates
    local originalTime = time
    local at = 1800000000
    time = function() return at end
    BadbUI.version = "1.0.9"
    BadbUI.UpdateStatus = { installed = "1.0.9", latest = "1.0.10", checkedAt = at }
    return u, BadbUI.DB:GetStore("updates"), function() time = originalTime; Mock.combat = false end
end

T["conferma, richiesta persistente e annullamento"] = function(Mock)
    local u, store, done = fixture(Mock)
    local ok, err = pcall(function()
        assert(u:Status() == "available")
        local options = u:Options()
        local ui = BadbUI.ConfigUI
        local confirm, toast = ui.Confirm, ui.Toast
        local accept
        ui.Confirm = function(_, _, yes) accept = yes end
        ui.Toast = function() end
        options[3].func()
        assert(accept and not store.request, "serve conferma prima di scrivere la richiesta")
        accept()
        assert(store.request and store.request.version == "1.0.10")
        assert(store.request.from == "1.0.9" and store.request.id == "1800000000-1")
        assert(u:Status() == "pending" and not u:CanRequest())
        options[4].func()
        assert(not store.request and u:CanRequest())
        ui.Confirm, ui.Toast = confirm, toast
    end)
    done()
    assert(ok, err)
end

T["catalogo scaduto, combattimento, ricevuta e nuova release"] = function(Mock)
    local u, store, done = fixture(Mock)
    local ok, err = pcall(function()
        local status = BadbUI.UpdateStatus
        Mock.combat = true
        assert(not u:Request() and not store.request)
        Mock.combat = false
        status.checkedAt = status.checkedAt - 601
        assert(u:Status() == "unknown" and not u:Request())
        status.checkedAt = time()
        assert(u:Request())
        status.receipt = { id = store.request.id, result = "installed" }
        status.installed, BadbUI.version = "1.0.10", "1.0.10"
        assert(u:Status() == "installed")
        status.latest = "1.1.0"
        assert(u:Status() == "available" and u:CanRequest())
    end)
    done()
    assert(ok, err)
end

return T
