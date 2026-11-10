-- In-game chat surface. The embedded SDK runs outside WoW's Lua sandbox.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local M, UI, C = Badb.Chatbot, Badb.UI, Badb.ChatbotContext
local function esc(v) return (tostring(v or ""):gsub("|", "||")) end
local function label(parent, text, x, y, width, color)
    local t = UI:Label(parent, text, "body", color or "text")
    t:SetPoint("TOPLEFT", x, y); t:SetWidth(width); t:SetJustifyH("LEFT")
    return t
end
local function button(parent, text, x, y, width, fn)
    local b = UI:Button(parent, text, width, 28, fn)
    b:SetPoint("TOPLEFT", x, y)
    return b
end
local function notify(text) if Badb.ConfigUI.Toast then Badb.ConfigUI:Toast(text) end end
local function reload()
    if InCombatLockdown and InCombatLockdown() then notify("Reload outside combat."); return end
    if ReloadUI then ReloadUI() end
end
local function submit(kind, payload)
    local ok, err = M:Queue(kind, payload)
    if ok then reload() else notify(err) end
end
local function sortedItems(values)
    table.sort(values, function(a, b) return a.text:lower() < b.text:lower() end)
    return values
end
local function field(parent, title, value, y, secret)
    label(parent, title, 20, y, 510, "textDim")
    local f = UI:EditBox(parent, 510, 28, { maxLetters = 8000 })
    f:SetPoint("TOPLEFT", 20, y - 22); f:SetText(value or "")
    if secret and f.edit.SetPassword then f.edit:SetPassword(true) end
    return f
end
function M:ShowSettings()
    if InCombatLockdown and InCombatLockdown() then notify("Open settings outside combat."); return end
    if self.settingsFrame then self.settingsFrame:Hide() end
    local f = Badb.Compat.CreateFrame("Frame", nil, UIParent)
    self.settingsFrame = f
    f:SetSize(560, 650); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true)
    Badb.Theme:Skin(f, { bg = "panel", border = "border", shadow = true })
    label(f, "Chatbot settings · nikcli embedded", 20, -18, 470, "accent")
    local close = UI:CloseButton(f, function() f:Hide() end); close:SetPoint("TOPRIGHT", -10, -10)
    local state = self:State()
    local provider = field(f, "Provider ID (including custom nikcli providers)", state.provider, -54)
    local key = field(f, "API key · leave blank to keep existing credentials", "", -112, true)
    label(f, "Keys entered here pass through local SavedVariables until acknowledged and reloaded. Never share that file or its .bak backup.", 20, -172, 510, "textDim")
    button(f, "Save API key", 20, -220, 155, function()
        if provider:GetText() == "" or key:GetText() == "" then notify("Enter a provider ID and API key."); return end
        local value = key:GetText(); key:SetText("")
        submit("api-key", { provider = provider:GetText(), key = value })
    end)
    button(f, "Disconnect provider", 190, -220, 190, function()
        f:Hide()
        Badb.ConfigUI:Confirm("Remove this provider's stored nikcli credentials?", function() submit("disconnect", { provider = provider:GetText() }) end)
    end)
    local methods = {}
    for i, method in ipairs(self.bundle and self.bundle.auth and self.bundle.auth[state.provider] or {}) do
        if method.type == "oauth" then methods[#methods + 1] = { value = i - 1, text = method.label } end
    end
    local method = methods[1] and methods[1].value
    local oauth = UI:Dropdown(f, "OAuth method", methods, function() return method end, function(v) method = v end, { width = 310, buttonWidth = 300 })
    oauth:SetPoint("TOPLEFT", 20, -270)
    button(f, "Start login", 350, -270, 180, function()
        if method == nil then notify("This provider has no OAuth method. Refresh providers first."); return end
        submit("oauth-start", { provider = provider:GetText(), method = method })
    end)
    local code = field(f, "OAuth callback code (when required)", "", -320)
    button(f, "Complete login", 20, -380, 170, function()
        if method == nil then notify("Select an OAuth method."); return end
        submit("oauth-finish", { provider = provider:GetText(), method = method, code = code:GetText() })
    end)
    label(f, "OAuth may require opening the provider's sign-in page in a browser. The login URL and instructions appear in chat after reload.", 20, -422, 510, "textDim")
    button(f, "Advanced nikcli config", 20, -475, 235, function()
        f:Hide()
        Badb.ConfigUI:TextBox("nikcli configuration · JSON merge", self.bundle and self.bundle.configJSON or "{}", function(text)
            submit("configure", { json = text })
        end, "Save & reload")
    end)
    button(f, "Refresh providers", 275, -475, 235, function() submit("catalog", {}) end)
    label(f, "Advanced config uses nikcli's settings: custom providers, endpoints, models, websearch, temperature and agent options. Secrets are omitted from the displayed config; omitted fields keep their existing values.", 20, -525, 510, "textDim")
    label(f, "Settings changes are exported on reload. Wait for the local AI runtime, then use Check replies.", 20, -595, 510, "accent")
    f:Show()
end
local function build(parent)
    local state = M:State()
    local width = math.max(500, (parent.GetWidth and parent:GetWidth() or 600) - 12)
    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(width, 520); root:SetPoint("TOPLEFT", 0, 0)
    M.frame = root
    label(root, "CHATBOT", 4, -6, width - 250, "accent")
    button(root, "Settings", width - 220, 0, 100, function() M:ShowSettings() end)
    button(root, "New chat", width - 110, 0, 105, function()
        Badb.ConfigUI:Confirm("Clear this character's chat and start a new conversation?", function()
            local ok, err = M:NewConversation()
            if ok then Badb.ConfigUI:Refresh() else notify(err) end
        end)
    end)
    local half = math.floor((width - 18) / 2)
    local providerItems = function()
        local list = {}
        for _, p in ipairs(M.bundle and M.bundle.providers or {}) do
            list[#list + 1] = { value = p.id, text = p.name .. (p.connected and " · connected" or " · not connected"), connected = p.connected }
        end
        table.sort(list, function(a, b)
            if a.connected ~= b.connected then return a.connected == true end
            return a.text:lower() < b.text:lower()
        end)
        return list
    end
    label(root, "Provider", 4, -38, half, "textDim")
    local providers = UI:Dropdown(root, nil, providerItems, function() return state.provider end, function(v)
        state.provider, state.model, state.variant, state.modelFilter = v, nil, nil, ""; Badb.ConfigUI:Refresh()
    end, { width = half, buttonWidth = half - 8, maxRows = 12 })
    providers:SetPoint("TOPLEFT", 4, -58)
    local modelItems = function()
        local list = {}
        local filter = (state.modelFilter or ""):lower()
        for _, p in ipairs(M.bundle and M.bundle.providers or {}) do
            if p.id == state.provider then
                for _, model in ipairs(p.models or {}) do
                    if filter == "" or (model.name .. " " .. model.id):lower():find(filter, 1, true) then list[#list + 1] = { value = model.id, text = model.name, desc = model.id } end
                end
            end
        end
        return sortedItems(list)
    end
    label(root, "Model", half + 16, -38, half, "textDim")
    local models = UI:Dropdown(root, nil, modelItems, function() return state.model end, function(v)
        state.model, state.variant = v, nil; Badb.ConfigUI:Refresh()
    end, { width = half, buttonWidth = half - 8, maxRows = 12 })
    models:SetPoint("TOPLEFT", half + 16, -58)
    local variants = { { value = "", text = "Default reasoning" } }
    for _, p in ipairs(M.bundle and M.bundle.providers or {}) do
        if p.id == state.provider then for _, model in ipairs(p.models or {}) do
            if model.id == state.model then for _, variant in ipairs(model.variants or {}) do variants[#variants + 1] = { value = variant, text = variant } end end
        end end
    end
    local reasoning = UI:Dropdown(root, nil, variants, function() return state.variant or "" end, function(v) state.variant = v end, { width = 190, buttonWidth = 185 })
    reasoning:SetPoint("TOPLEFT", 4, -96)
    local filter = UI:EditBox(root, math.max(80, width - 420), 28, { placeholder = "Filter models", maxLetters = 100, onChange = function(text)
        state.modelFilter = text; models:Refresh()
    end })
    filter:SetPoint("TOPLEFT", 200, -96); filter:SetText(state.modelFilter or "")
    button(root, "Check replies · reload", width - 210, -96, 205, reload)
    local history = UI:EditBox(root, width - 8, 160, { multiline = true, maxLetters = 1000000 })
    history:SetPoint("TOPLEFT", 4, -134)
    history.edit:SetScript("OnTextChanged", nil)
    local lines = {}
    if not M.bundle then
        lines[#lines + 1] = "Welcome to your WoW assistant. Start the local nikcli embedded runtime, then click Check replies to load your providers and models."
    end
    for _, h in ipairs(state.history) do
        lines[#lines + 1] = "YOU\n" .. esc(h.question)
        lines[#lines + 1] = h.status == "pending" and "AI · Waiting for the runtime. After sending, wait for Reply ready, then Check replies."
            or ((h.status == "error" and "ERROR\n" or "AI\n") .. esc(h.answer))
        for _, url in ipairs(h.sources or {}) do lines[#lines + 1] = esc(url) end
    end
    for _, r in ipairs(M.bundle and M.bundle.receipts or {}) do
        if r.character == C.Identity() and r.kind ~= "ask" then lines[#lines + 1] = esc(r.text) end
    end
    if #lines == 0 then lines[1] = "Ask about quests, items or your next step. Attach quests below to focus the answer." end
    history:SetText(table.concat(lines, "\n\n"))
    if history.edit.SetCursorPosition then history.edit:SetCursorPosition(#history:GetText()) end
    label(root, "Character: " .. esc(C.Call(UnitName, "player")) .. " · level " .. tostring(C.Call(UnitLevel, "player") or "?") .. " · " .. esc(C.Call(GetZoneText)), 4, -304, width - 8, "textDim")
    local chips = label(root, "", 4, -330, width - 8, "accent")
    chips:SetHeight(20)
    local chipButtons, questMenu = {}, nil
    local function updateChips()
        local selected = {}
        for _, q in ipairs(C.Quests()) do if state.selected[q.key] then selected[#selected + 1] = q end end
        for _, b in ipairs(chipButtons) do b:Hide() end
        chips:SetText(#selected == 0 and "No quest attached · level and zone are included automatically" or "")
        local chipWidth = math.floor((width - 12) / math.max(1, math.min(#selected, 3)))
        for i = 1, math.min(#selected, 3) do
            local q = selected[i]
            if not chipButtons[i] then
                chipButtons[i] = button(root, "", 4 + (i - 1) * chipWidth, -326, chipWidth - 4, function(b)
                    state.selected[b.questKey] = nil
                    if questMenu then questMenu:Hide(); questMenu = nil end
                    updateChips()
                end)
            end
            local b = chipButtons[i]
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", 4 + (i - 1) * chipWidth, -326); b:SetWidth(chipWidth - 4)
            b.questKey, b.tooltip = q.key, q.title
            b:SetText(esc(q.title:sub(1, 24)) .. ((i == 3 and #selected > 3) and (" +" .. (#selected - 3)) or "") .. " ×"); b:Show()
        end
    end
    updateChips()
    local composer
    local function send()
        if not state.provider or not state.model then notify("Choose a provider and model first."); return end
        local ok, err = M:Ask(composer:GetText())
        if not ok then notify(err); return end
        state.draft = ""; composer:SetText(""); reload()
    end
    composer = UI:EditBox(root, width - 8, 76, { multiline = true, maxLetters = 4000, placeholder = "Ask about your quests… · Ctrl+Enter to send", onEnter = send, onChange = function(text) state.draft = text end })
    composer:SetPoint("TOPLEFT", 4, -356); composer:SetText(state.draft or "")
    button(root, "+ Add quests", 4, -442, 110, function()
        if questMenu then questMenu:Hide(); questMenu = nil; return end
        questMenu = Badb.Compat.CreateFrame("Frame", nil, root)
        questMenu:SetPoint("BOTTOMLEFT", composer, "TOPLEFT", 0, 6); questMenu:SetSize(width - 8, 270); questMenu:SetFrameStrata("DIALOG"); questMenu:EnableMouse(true)
        Badb.Theme:Skin(questMenu, { bg = "panel", border = "border", shadow = true })
        label(questMenu, "YOUR QUEST LOG · click to attach or remove", 12, -10, width - 44, "accent")
        local scroll, content = UI:ScrollFrame(questMenu)
        scroll:SetPoint("TOPLEFT", 10, -38); scroll:SetPoint("BOTTOMRIGHT", -12, 12)
        local quests = C.Quests()
        for i, q in ipairs(quests) do
            local b
            local function title() return (state.selected[q.key] and "[x] " or "[ ] ") .. "[" .. tostring(q.level or "?") .. "] " .. esc(q.title) .. (q.complete and " · complete" or "") end
            b = button(content, title(), 0, -(i - 1) * 32, width - 60, function()
                state.selected[q.key] = not state.selected[q.key] or nil; b:SetText(title()); updateChips()
            end)
        end
        if #quests == 0 then label(content, "No readable quests. Open your quest log and try again.", 0, 0, width - 50) end
        content:SetHeight(math.max(40, #quests * 32)); questMenu:Show()
    end)
    button(root, "Clear quests", 122, -442, 90, function() state.selected = {}; updateChips() end)
    button(root, state.includeBags and "Bags: included" or "Bags: excluded", 220, -442, 130, function(b)
        state.includeBags = not state.includeBags; b:SetText(state.includeBags and "Bags: included" or "Bags: excluded")
    end)
    button(root, "Send & reload", width - 150, -442, 145, send)
    label(root, "Send saves your question and character snapshot. Wait for Reply ready in the local runtime, then Check replies. WoW requires a UI reload to exchange data.", 4, -480, width - 8, "textDim")
    return 520
end
M.page = { title = "Chatbot", category = L["Contenuti"], order = 1, keywords = "AI nikcli quests chat provider model", build = build }
