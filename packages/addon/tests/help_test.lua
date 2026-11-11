local T = {}
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
T["manual covers every module and links resolve"] = function()
    local B, seen = BadbUI, {}
    for _, entry in ipairs(B.Help:ModuleEntries()) do
        assert(entry.documented, "Missing module documentation: " .. entry.id)
        assert(#entry.text > 20); seen[entry.id] = true
    end
    for _, id in ipairs(B.Modules.order) do assert(seen[id], id) end
    local topics = {}
    for _, section in ipairs(B.Help:Sections()) do
        assert(not topics[section.id], section.id); topics[section.id] = true
        if section.guide then assert(B.Guides:Get(section.guide), section.guide) end
        if section.page then assert(B.ConfigUI:ResolveKey(section.page), section.page) end
    end
    for _, id in ipairs({ "start", "language", "profiles", "layout", "macros", "contexts", "scripts", "chatbot", "guides", "troubleshooting", "limits", "modules", "commands" }) do assert(topics[id], id) end
    assert(not topics.guild)
end
T["module descriptions supply localized manual text without a static entry"] = function()
    local B = BadbUI
    local key = "A fixture describing the new module"
    B.Localization:RegisterLocale("enUS", { [key] = "Searchable description of the fixture module." })
    B.Modules:New("ManualFixture", { title = "Fixture", description = B.L[key] })
    eq(B.HelpData.modules.ManualFixture, nil)

    local fixture, suite
    for _, entry in ipairs(B.Help:ModuleEntries()) do
        if entry.id == "ManualFixture" then fixture = entry end
        if entry.id == "Suite" then suite = entry end
    end
    assert(fixture and fixture.documented and suite and suite.documented)
    eq(fixture.text, "Searchable description of the fixture module.")
    eq(suite.text, B.Modules:Get("Suite").description)

    B.Help:Select("modules", "searchable")
    eq(B.Help:MatchesModule(fixture), true)
    eq(B.Help:MatchesModule(suite), false)
    for _, section in ipairs(B.Help:Sections()) do
        if section.id == "modules" then eq(B.Help:Matches(section), true) end
    end
end
T["manual builds filters resizes and handles empty searches"] = function()
    local B = BadbUI
    eq(B.Help:Open("start"), true)
    local page = B.ConfigUI.pageFrames.help
    assert(page and not page.failed, page and page.buildError)
    local startHeight = page.height
    B.Help:Select("all", ""); assert(page.height > startHeight)
    assert(page.height < 20000, "The complete manual must fit the scrollable page")
    B.Help:Select("start", "profile")
    local matched = 0
    for _, section in ipairs(B.Help:Sections()) do if B.Help:Matches(section) then matched = matched + 1 end end
    assert(matched >= 2)
    B.Help:Select("all", "no-results-xyz-123")
    for _, section in ipairs(B.Help:Sections()) do eq(B.Help:Matches(section), false) end
    assert(page.height < startHeight)
    B.Help:Select("invalid-topic", ""); eq(B.Help.topic, "start")
    B.Help:Select("all", string.rep("x", 500)); eq(#B.Help.query, 120)
    eq(page.lastErr, nil)
end
T["help command opens a topic and keeps the chat reference"] = function(Mock)
    eq(BadbUI.Slash:Dispatch("help MACROS"), true)
    eq(BadbUI.ConfigUI.current, "help"); eq(BadbUI.Help.topic, "macros")
    local found = false
    for _, line in ipairs(Mock.chat) do if line:find("/badb macro", 1, true) then found = true end end
    assert(found)
end
T["command reference discovers new commands live"] = function()
    assert(BadbUI.Slash:Register("helpfixture", function() end, "A newly installed command"))
    assert(BadbUI.Help:CommandText():find("/badb helpfixture - A newly installed command", 1, true))
end
T["manual works with Guides and Diagnostics disabled"] = function()
    BadbUI.Modules:SetEnabled("Guides", false); BadbUI.Modules:SetEnabled("Diagnostics", false)
    eq(BadbUI.Help:Open("all"), true)
    assert(not BadbUI.ConfigUI.pageFrames.help.failed)
    eq(BadbUI.ConfigUI.pageFrames.help.lastErr, nil)
end
return T
