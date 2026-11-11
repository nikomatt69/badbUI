local T = {}
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function withLocale(locale, saved, full, Mock, fn)
    local oldLocale, oldAddon, oldDB = GetLocale, BadbUI, BadbUIDB
    GetLocale = function() return locale end
    BadbUIDB = saved
    local ok, err = pcall(function()
        if full then
            Mock.LoadAddon(".", "BadbUI.toc")
            Mock.Fire("ADDON_LOADED", "BadbUI"); Mock.Fire("PLAYER_LOGIN")
            fn(BadbUI)
        else
            local ns = {}
            for _, path in ipairs({ "Core/Init.lua", "Core/Localization.lua", "Locales/enUS.lua", "Locales/itIT.lua" }) do
                assert(loadfile(path))("BadbUI", ns)
            end
            fn(ns.Badb)
        end
    end)
    GetLocale, BadbUI, BadbUIDB = oldLocale, oldAddon, oldDB
    assert(ok, err)
end
T["English-only on Italian, English and unsupported clients"] = function()
    for _, locale in ipairs({ "itIT", "enUS", "enGB", "frFR", "deDE", "koKR", "zhCN" }) do
        withLocale(locale, nil, false, nil, function(B)
            eq(B.Localization.language, "enUS")
            eq(B.L["Gestione"], "Management")
        end)
    end
end
T["saved override applies before modules and guides load"] = function(Mock)
    withLocale("itIT", { global = { language = "enUS" } }, true, Mock, function(B)
        eq(B.Localization.language, "enUS")
        eq(B.ConfigUI:FindPage("profiles").title, "Profiles")
        eq(B.ConfigUI:FindPage("help").title, "Help")
        eq(B.Modules:Get("Contexts").title, "Contexts")
        local ok, err = B.DB.NormalizeName("")
        eq(ok, nil); eq(err, "the name cannot be empty")
        assert(B.Guides:Get("starter:primo-avvio").title:find("First", 1, true))
        local report = B.Diagnostics:Report()
        assert(report:find("WARNING", 1, true) or report:find("[OK]", 1, true))
        assert(not report:find("AVVISO", 1, true))
        assert(B.Help:Open("all"))
        assert(not B.ConfigUI.pageFrames.help.failed)
        eq(B.ConfigUI.pageFrames.help.lastErr, nil)
        assert(B.ConfigUI.pageFrames.help.height < 20000)
        local rows = B.MainPages.moduleRows()
        assert(not rows[1].detail:find("attivo", 1, true))
        assert(B.ConfigUI:Open("appearance"))
        assert(not B.ConfigUI.pageFrames.appearance.failed)
    end)
    withLocale("enUS", { global = { language = "itIT" } }, true, Mock, function(B)
        eq(B.ConfigUI:FindPage("profiles").title, "Profiles")
        eq(B.ConfigUI:FindPage("help").title, "Help")
    end)
end
T["missing entries fall back without caching and late registrations work"] = function()
    withLocale("enUS", nil, false, nil, function(B)
        eq(B.L["future key"], "future key")
        B.Localization:RegisterLocale("enUS", { ["future key"] = "Translated" })
        eq(B.L["future key"], "Translated"); eq(rawget(B.L, "future key"), nil)
    end)
end
T["preference persists without mixing live descriptors or touching profile data"] = function(Mock)
    local saved = { global = {}, profiles = { Default = { marker = "unchanged" } } }
    withLocale("itIT", saved, true, Mock, function(B)
        local ok, needsReload = B.Localization:SetPreference("enUS")
        eq(ok, true); eq(needsReload, false); eq(saved.global.language, "enUS")
        eq(B.L["Gestione"], "Management"); eq(B.ConfigUI:FindPage("profiles").title, "Profiles")
        eq(saved.profiles.Default.marker, "unchanged")
        eq(B.Localization:SetPreference("frFR"), false); eq(saved.global.language, "enUS")
        B.DB:SetProfile("Another profile"); eq(B.Localization:GetPreference(), "enUS")
        eq(B.Localization:SetPreference("auto"), true); eq(saved.global.language, "auto")
    end)
end
T["invalid saved preference falls back to client language"] = function()
    for _, global in ipairs({ { language = "xxXX" }, { language = false }, { language = {} } }) do
        withLocale("enGB", { global = global }, false, nil, function(B)
            eq(B.Localization:GetPreference(), "auto"); eq(B.Localization.language, "enUS")
        end)
    end
end
local function signature(text)
    local codes = {}
    for code in text:gmatch("%%[-+ #0]*%d*%.?%d*[cdeEfgGiouXxqs%%]") do codes[#codes + 1] = code end
    return table.concat(codes, "|")
end
T["translations preserve formatting placeholders and color escapes"] = function()
    withLocale("enUS", nil, false, nil, function(B)
        local count = 0
        for _, entries in pairs(B.Localization.locales) do
            for key, value in pairs(entries) do
                eq(signature(key), signature(value))
                local function colors(s)
                    local codes = {}
                    for c in s:gmatch("|c%x%x%x%x%x%x%x%x") do codes[#codes + 1] = c end
                    return table.concat(codes, ",")
                end
                eq(colors(key), colors(value)); count = count + 1
            end
        end
        assert(count > 1900)
    end)
end
T["macro bodies and guide IDs stay identical across interface languages"] = function(Mock)
    local snapshots = {}
    for _, locale in ipairs({ "itIT", "enUS" }) do
        withLocale(locale, nil, true, Mock, function(B)
            local bodies = {}
            for _, id in ipairs(B.Macros.order) do bodies[id] = B.Macros:Render(id) end
            snapshots[locale] = bodies
            assert(B.Guides:Get("starter:integrazioni"))
        end)
    end
    local count = 0
    for id, body in pairs(snapshots.itIT) do eq(body, snapshots.enUS[id]); count = count + 1 end
    assert(count >= 635)
end
T["language command stores a preference; display stays English"] = function(Mock)
    withLocale("itIT", nil, true, Mock, function(B)
        eq(B.Slash:Dispatch("language enGB"), true)
        eq(B.Localization:GetPreference(), "enUS"); eq(B.Localization.language, "enUS")
        eq(B.Slash:Dispatch("language itIT"), true); eq(B.Localization:GetPreference(), "itIT")
    end)
end
return T
