-- Automazioni facoltative che usano soltanto le azioni native del client.
local _, ns = ...
local Badb = ns.Badb
local L, Compat, Events, Logger = Badb.L, Badb.Compat, Badb.Events, Badb.Logger

local M = Badb.Modules:New("QoL", {
    title = L["Comodità di gioco"],
    category = L["Gioco"],
    description = L["Bottino, riparazioni e dialoghi delle missioni per il profilo attivo."],
    defaults = {
        enabled = true,
        autoLoot = false,
        autoRepair = false,
        repairCap = 10,
        autoAccept = false,
        autoComplete = false,
    },
    replaces = {
        { addon = "Leatrix_Plus", title = "Leatrix Plus", coverage = "partial",
          note = L["Bottino automatico, riparazioni personali e dialoghi semplici delle missioni. Le altre funzioni di Leatrix Plus richiedono ancora l'addon originale."] },
    },
})
Badb.QoL = M

local AUTO_LOOT = "autoLootDefault"

local function api(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if not ok then return end
    return Compat.SafeValue(a), Compat.SafeValue(b)
end

local function invoke(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and not Compat.IsSecret(value) and value ~= false
end

local function visible(frame)
    return frame and api(frame.IsVisible, frame) == true
end

local function integer(value)
    return not Compat.IsSecret(value) and type(value) == "number" and value >= 0
        and value < math.huge and value == math.floor(value)
end

-- Senza una risposta certa da entrambe le guardie, l'azione resta manuale.
local function canAutomate()
    return api(InCombatLockdown) == false and api(IsShiftKeyDown) == false
end

function M:HasLootAPI()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local value = api(get, AUTO_LOOT)
    return type(set) == "function" and (value == "0" or value == "1")
end

function M:ApplyLoot()
    Events:RunOutOfCombat("QoL:autoLoot", function()
        if self.active and self:Get("autoLoot") == true and self:HasLootAPI() then
            invoke(Badb.CVars.Set, Badb.CVars, self.name, AUTO_LOOT, true)
        else
            invoke(Badb.CVars.Restore, Badb.CVars, self.name)
        end
    end)
end

function M:HasRepairAPI()
    return type(CanMerchantRepair) == "function" and type(GetRepairAllCost) == "function"
        and type(GetMoney) == "function" and type(RepairAllItems) == "function"
        and type(IsShiftKeyDown) == "function" and type(Compat.After) == "function"
end

function M:GetRepairCap()
    local value = self:Get("repairCap")
    if not integer(value) or value < 1 or value > 100 then return self.defaults.repairCap end
    return value
end

function M:TryRepair()
    if not self.active or self:Get("autoRepair") ~= true or not self.merchantOpen
        or not self:HasRepairAPI() or not canAutomate() or not visible(MerchantFrame)
        or api(CanMerchantRepair) ~= true then return end

    local cost, canRepair = api(GetRepairAllCost)
    if canRepair ~= true or not integer(cost) or cost == 0 then return end
    if cost > self:GetRepairCap() * 10000 then
        Logger:Info(L["Riparazione automatica saltata: il costo supera il limite del profilo."])
        return
    end

    local money = api(GetMoney)
    if not integer(money) or money < cost then return end
    if not invoke(RepairAllItems) then
        Logger:Warn(L["Riparazione automatica non riuscita. Usa il pulsante del mercante."])
    end
end

function M:HasJunkAPI()
    return C_MerchantFrame ~= nil
        and type(C_MerchantFrame.IsSellAllJunkEnabled) == "function"
        and type(C_MerchantFrame.GetNumJunkItems) == "function"
        and type(C_MerchantFrame.SellAllJunkItems) == "function"
end

function M:GetJunkCount()
    if not self.active or not self.merchantOpen or not visible(MerchantFrame) or not self:HasJunkAPI()
        or api(C_MerchantFrame.IsSellAllJunkEnabled) ~= true then return end
    local count = api(C_MerchantFrame.GetNumJunkItems)
    if integer(count) then return count end
end

function M:ConfirmJunkSale()
    local count = self:GetJunkCount()
    if not count or count == 0 or self.junkPending or api(InCombatLockdown) ~= false then return false end
    if not (Badb.ConfigUI and Badb.ConfigUI.Confirm) then return false end

    local visit, revision = self.merchantRevision, self.bagRevision
    self.junkPending = true
    local function clearPending()
        self.junkPending = false
        self:RefreshPage()
    end
    local opened = Badb.ConfigUI:Confirm(string.format(L["Vendere le cianfrusaglie individuate dal client? Elementi rilevati: %d."], count), function()
        clearPending()
        if not self.active or api(InCombatLockdown) ~= false or visit ~= self.merchantRevision
            or revision ~= self.bagRevision or self:GetJunkCount() ~= count then
            Logger:Warn(L["La vendita è stata annullata. Verifica il mercante e riprova."])
            return
        end
        -- Una conferma vale per un solo tentativo, anche prima di BAG_UPDATE.
        self.bagRevision = self.bagRevision + 1
        if not invoke(C_MerchantFrame.SellAllJunkItems) then
            Logger:Warn(L["Vendita non riuscita. Usa il pulsante del mercante."])
        end
    end, clearPending)
    if opened == false then clearPending() end
    self:RefreshPage()
    return opened ~= false
end

local questPanels = {
    QUEST_DETAIL = "QuestFrameDetailPanel",
    QUEST_PROGRESS = "QuestFrameProgressPanel",
    QUEST_COMPLETE = "QuestFrameRewardPanel",
}

function M:HasAcceptAPI()
    return type(GetQuestID) == "function" and type(AcceptQuest) == "function"
        and type(UnitExists) == "function" and type(UnitIsPlayer) == "function"
        and type(QuestGetAutoAccept) == "function" and type(QuestIsFromAdventureMap) == "function"
        and type(QuestIsFromAreaTrigger) == "function"
        and type(IsShiftKeyDown) == "function" and type(Compat.After) == "function"
end

function M:HasCompleteAPI()
    return type(GetQuestID) == "function" and type(IsQuestCompletable) == "function"
        and type(CompleteQuest) == "function" and type(GetQuestReward) == "function"
        and type(GetQuestMoneyToGet) == "function" and type(GetNumQuestCurrencies) == "function"
        and type(GetNumQuestChoices) == "function"
        and type(UnitExists) == "function" and type(UnitIsPlayer) == "function"
        and type(IsShiftKeyDown) == "function" and type(Compat.After) == "function"
end

local function questHasNoCost()
    return api(GetQuestMoneyToGet) == 0 and api(GetNumQuestCurrencies) == 0
end

function M:HandleQuest(event, questStartItemID)
    self.questRevision = self.questRevision + 1
    if not canAutomate() or type(Compat.After) ~= "function" then return end
    if event == "QUEST_DETAIL" then
        if self:Get("autoAccept") ~= true or not self:HasAcceptAPI() or Compat.IsSecret(questStartItemID)
            or (questStartItemID ~= nil and questStartItemID ~= 0) then return end
    elseif self:Get("autoComplete") ~= true or not self:HasCompleteAPI() then
        return
    end

    local id = api(GetQuestID)
    if not integer(id) or id == 0 then return end
    local revision = self.questRevision
    local profile = Badb.DB:GetProfileName()
    Compat.After(0, function()
        -- Il client deve prima aprire il suo pannello. Una nuova interazione invalida il lavoro pendente.
        if not self.active or revision ~= self.questRevision or profile ~= Badb.DB:GetProfileName()
            or not canAutomate() or id ~= api(GetQuestID) or not visible(_G[questPanels[event]])
            or api(UnitExists, "npc") ~= true or api(UnitIsPlayer, "npc") ~= false then return end

        if event == "QUEST_DETAIL" then
            if self:Get("autoAccept") == true and api(QuestGetAutoAccept) == false
                and api(QuestIsFromAdventureMap) == false and api(QuestIsFromAreaTrigger) == false then
                invoke(AcceptQuest)
            end
        elseif self:Get("autoComplete") == true and questHasNoCost() then
            if event == "QUEST_PROGRESS" and api(IsQuestCompletable) == true then
                invoke(CompleteQuest)
            elseif event == "QUEST_COMPLETE" then
                local choices = api(GetNumQuestChoices)
                if choices == 0 or choices == 1 then invoke(GetQuestReward, choices) end
            end
        end
    end)
end

function M:OnEnable()
    self.active = true
    self.merchantRevision = (self.merchantRevision or 0) + 1
    self.bagRevision = (self.bagRevision or 0) + 1
    self.questRevision = (self.questRevision or 0) + 1

    self:On("MERCHANT_SHOW", function()
        if self.merchantOpen then return end
        self.merchantOpen = true
        self.merchantRevision = self.merchantRevision + 1
        if type(Compat.After) ~= "function" then
            self:RefreshPage()
            return
        end
        local visit, profile = self.merchantRevision, Badb.DB:GetProfileName()
        local tryRepair = self:Get("autoRepair") == true and self:HasRepairAPI() and canAutomate()
        Compat.After(0, function()
            if visit ~= self.merchantRevision or profile ~= Badb.DB:GetProfileName() then return end
            if tryRepair then self:TryRepair() end
            self:RefreshPage()
        end)
    end)
    self:On("MERCHANT_CLOSED", function()
        self.merchantOpen = false
        self.merchantRevision = self.merchantRevision + 1
        self:RefreshPage()
    end)
    self:On("MERCHANT_UPDATE", function()
        if self.merchantOpen then self:RefreshPage() end
    end)
    self:On("BAG_UPDATE", function()
        self.bagRevision = self.bagRevision + 1
    end)
    self:On("BAG_UPDATE_DELAYED", function()
        if self.merchantOpen then self:RefreshPage() end
    end)
    self:On("PLAYER_REGEN_DISABLED", function() self:RefreshPage() end)
    self:On("PLAYER_REGEN_ENABLED", function() self:RefreshPage() end)
    for event in pairs(questPanels) do
        self:On(event, function(name, itemID) self:HandleQuest(name, itemID) end)
    end
    self:On("QUEST_FINISHED", function() self.questRevision = self.questRevision + 1 end)
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module ~= self.name then return end
        if path == "autoLoot" then self:ApplyLoot() end
        self:RefreshPage()
    end)
    self:ApplyLoot()
end

function M:OnProfileChanged()
    self.questRevision = self.questRevision + 1
    self.bagRevision = self.bagRevision + 1
    self:ApplyLoot()
    self:RefreshPage()
end

function M:OnDisable()
    self.active = false
    self.merchantOpen = false
    self.merchantRevision = self.merchantRevision + 1
    self.questRevision = self.questRevision + 1
    self:ApplyLoot()
    self:RefreshPage()
end
