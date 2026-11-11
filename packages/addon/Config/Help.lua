-- Offline manual, searchable topics, live module index and command reference.
local _, ns = ...
local Badb = ns.Badb
local L, UI, W = Badb.L, Badb.ConfigUI, Badb.Widgets
local Help = { topic = "start", query = "" }
local DEFAULT_MODULE_TEXT = L["Open this module's options to inspect its available settings."]
Badb.Help = Help

function Help:Sections()
    local sections = {}
    for _, section in ipairs(Badb.HelpData.sections) do sections[#sections + 1] = section end
    sections[#sections + 1] = { id = "modules", title = L["Every module explained"],
        text = L["Each module can be enabled independently. Open its options from here or from Home. A disabled module's page explains how to enable it."] }
    sections[#sections + 1] = { id = "commands", title = L["All slash commands"], text = self:CommandText() }
    return sections
end

local function description(value)
    if type(value) == "string" and value:find("%S") then return value end
end

function Help:ModuleEntries()
    local entries = {}
    for _, id in ipairs(Badb.Modules.order) do
        local module = Badb.Modules:Get(id)
        if module then
            local text = description(Badb.HelpData.modules[id]) or description(module.description)
            entries[#entries + 1] = {
                id = id, title = module.title or id, text = text or DEFAULT_MODULE_TEXT, documented = text ~= nil,
            }
        end
    end
    return entries
end

function Help:CommandText()
    local lines = { L["Use /badb or /bui before a command. Names stay the same in every language. <...> marks a required value; [...] marks an optional value. Do not type the brackets. Commands below are discovered from the installed modules."] }
    for _, command in ipairs(Badb.Slash:List()) do
        lines[#lines + 1] = "/badb " .. command.name .. " - " .. command.help
    end
    return table.concat(lines, "\n\n")
end

local function contains(entry, query)
    local text = entry.title .. " " .. entry.text .. " " .. entry.id
    return text:lower():find(query, 1, true) ~= nil
end

function Help:MatchesModule(entry)
    local query = self.query:lower()
    if query == "" then return self.topic == "all" or self.topic == "modules" end
    return contains(entry, query)
end

function Help:Matches(section)
    local query = self.query:lower()
    if query == "" then return self.topic == "all" or self.topic == section.id end
    if contains(section, query) then return true end
    if section.id == "modules" then
        for _, entry in ipairs(self:ModuleEntries()) do
            if contains(entry, query) then return true end
        end
    end
    return false
end

function Help:Select(topic, query)
    topic = tostring(topic or ""):lower()
    local found = topic == "all"
    for _, section in ipairs(self:Sections()) do if section.id == topic then found = true end end
    self.topic = found and topic or "start"
    self.query = tostring(query or ""):sub(1, 120)
    UI:RefreshPage("help")
    if UI.scroll and UI.current == "help" then W.Call(UI.scroll, "SetVerticalScroll", 0) end
end

function Help:Open(topic)
    if topic and topic ~= "" then self:Select(topic, "") end
    return UI:Open("help")
end

local function build(parent, ctx)
    local topics = { { value = "all", label = L["All topics"] } }
    local sections = Help:Sections()
    for _, section in ipairs(sections) do topics[#topics + 1] = { value = section.id, label = section.title } end
    local options = {
        { type = "label", text = L["Everything you need to get started, customize the interface and recover from problems. Available offline in English and Italian."] },
        { type = "select", label = L["Topic"], values = topics,
            get = function() return Help.topic end, set = function(value) Help:Select(value, "") end },
        { type = "text", label = L["Search all help (press Enter)"], width = 380,
            get = function() return Help.query end, set = function(value) Help:Select(Help.topic, value) end },
        { type = "execute", label = L["Clear search / show all topics"], func = function() Help:Select("all", "") end },
        { type = "label", text = L["No help topics match. Try another word or clear the search."], hidden = function()
            for _, section in ipairs(Help:Sections()) do if Help:Matches(section) then return true end end
            return false
          end },
    }
    local function add(option, section)
        option.hidden = function() return not Help:Matches(section) end
        options[#options + 1] = option
    end
    for _, section in ipairs(sections) do
        local entry = section
        add({ type = "header", label = entry.title }, entry)
        add({ type = "label", text = entry.id == "commands" and function() return Help:CommandText() end or entry.text }, entry)
        if entry.page then
            add({ type = "execute", label = L["Open settings"], func = function() UI:OpenPage(entry.page) end }, entry)
        end
        if entry.guide then
            add({ type = "execute", label = L["Read guide"], disabled = function()
                local module = Badb.Modules:Get("Guides")
                return not (module and module.enabled and Badb.Guides)
              end, func = function() Badb.Guides:Open(entry.guide) end }, entry)
        end
        if entry.id == "modules" then
            for _, module in ipairs(Help:ModuleEntries()) do
                local item = module
                local function hidden() return not Help:MatchesModule(item) end
                options[#options + 1] = { type = "header", label = item.title .. " (" .. item.id .. ")", hidden = hidden }
                options[#options + 1] = { type = "label", text = item.text, hidden = hidden }
                options[#options + 1] = { type = "execute", label = L["Open options"], hidden = hidden,
                    func = function() UI:OpenPage(item.id) end }
            end
        end
    end
    local height, _, group = W:Build(parent, nil, 8, options)
    ctx.AddRefresh(function() ctx.Resize(group:Refresh() + 16) end)
    return height + 16
end

UI:RegisterPage("help", { title = L["Help"], category = L["Gestione"], order = 20,
    keywords = { "help", "manual", "guide", "support", "faq", "aiuto", "language", "lingua" }, build = build })
