local T = {}
local function withSettings(fn)
    return function()
        local UI, compat = BadbUI.ConfigUI, BadbUI.Compat
        local settings, supported = Settings, compat.hasSettings
        local category, panels, open = UI.panel.settingsCategory, UI.settingsPanels, UI.OpenPage
        Settings, compat.hasSettings = {}, true
        UI.panel.settingsCategory, UI.settingsPanels = {}, {}
        local ok, err = pcall(fn)
        Settings, compat.hasSettings = settings, supported
        UI.panel.settingsCategory, UI.settingsPanels, UI.OpenPage = category, panels, open
        if not ok then error(err, 0) end
    end
end

T["native Settings: child categories attach to BadbUI and open the requested section"] = withSettings(function()
    local UI = BadbUI.ConfigUI
    local original = Settings.RegisterCanvasLayoutSubcategory
    local captured = {}
    Settings.RegisterCanvasLayoutSubcategory = function(parent, panel, title)
        local category = { parent = parent, title = title }
        captured[#captured + 1] = { parent = parent, panel = panel, title = title, category = category }
        return category
    end
    local open = UI.OpenPage
    local ok, err = pcall(function()
        UI.settingsPanels = {}
        UI:RegisterSettingsShortcuts()
        assert(#captured == 4, "BadbUI must have native children to show the expand button")
        for _, child in ipairs(captured) do
            assert(child.parent == UI.panel.settingsCategory, "child attached to the wrong parent")
            assert(child.panel.settingsCategory == child.category)
        end
        UI:RegisterSettingsShortcuts()
        assert(#captured == 4, "duplicate registration")
        local opened
        UI.OpenPage = function(_, key) opened = key end
        captured[1].panel.openButton.__scripts.OnClick(captured[1].panel.openButton)
        assert(opened == "home")
        captured[2].panel.openButton.__scripts.OnClick(captured[2].panel.openButton)
        assert(opened == "Macros")
        captured[3].panel.openButton.__scripts.OnClick(captured[3].panel.openButton)
        assert(opened == "profiles")
    end)
    UI.OpenPage = open
    Settings.RegisterCanvasLayoutSubcategory = original
    if not ok then error(err, 0) end
end)

T["native Settings: missing subcategory API keeps the root panel available"] = withSettings(function()
    local UI = BadbUI.ConfigUI
    local original = Settings.RegisterCanvasLayoutSubcategory
    Settings.RegisterCanvasLayoutSubcategory = nil
    local ok, err = pcall(function()
        UI.settingsPanels = {}
        UI:RegisterSettingsShortcuts()
        assert(#UI.settingsPanels == 0)
        assert(UI.panel.openButton, "root launcher must still work")
    end)
    Settings.RegisterCanvasLayoutSubcategory = original
    if not ok then error(err, 0) end
end)

return T
