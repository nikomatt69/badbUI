local T = {}

local function eq(actual, expected)
    assert(actual == expected, ("atteso %s, ottenuto %s"):format(tostring(expected), tostring(actual)))
end

local function withClient(Mock, run)
    local c = {
        cost = 300, funds = 500, repairs = 0, junk = 3, sold = 0,
        id = 42, choices = 0, moneyRequired = 0, currencyRequired = 0,
        accepted = 0, advanced = 0, rewards = 0, pending = {},
        shift = false, hasNPC = true, playerNPC = false,
        available = true, shown = true, autoAccept = false, fromArea = false, fromMap = false,
    }

    local function visible() return c.shown end
    local frame = { IsVisible = visible }
    local globals = {
        IsShiftKeyDown = function() return c.shift end,
        CanMerchantRepair = function() return c.available end,
        GetRepairAllCost = function() return c.cost, c.available end,
        GetMoney = function() return c.funds end,
        RepairAllItems = function(guild)
            eq(guild, nil)
            c.repairs = c.repairs + 1
        end,
        MerchantFrame = frame,
        C_MerchantFrame = {
            IsSellAllJunkEnabled = function() return c.available end,
            GetNumJunkItems = function() return c.junk end,
            SellAllJunkItems = function() c.sold = c.sold + 1 end,
        },
        UnitExists = function(unit) return unit == "npc" and c.hasNPC end,
        UnitIsPlayer = function(unit) return unit == "npc" and c.playerNPC end,
        GetQuestID = function() return c.id end,
        QuestGetAutoAccept = function() return c.autoAccept end,
        QuestIsFromAdventureMap = function() return c.fromMap end,
        QuestIsFromAreaTrigger = function() return c.fromArea end,
        AcceptQuest = function() c.accepted = c.accepted + 1 end,
        IsQuestCompletable = function() return c.available end,
        CompleteQuest = function() c.advanced = c.advanced + 1 end,
        GetQuestMoneyToGet = function() return c.moneyRequired end,
        GetNumQuestCurrencies = function() return c.currencyRequired end,
        GetNumQuestChoices = function() return c.choices end,
        GetQuestReward = function(choice)
            c.choice = choice
            c.rewards = c.rewards + 1
        end,
        QuestFrameDetailPanel = frame,
        QuestFrameProgressPanel = frame,
        QuestFrameRewardPanel = frame,
    }

    local original = {}
    for k, value in pairs(globals) do
        original[k] = _G[k]
        _G[k] = value
    end

    local origAfter, origConfirm = BadbUI.Compat.After, BadbUI.ConfigUI.Confirm
    BadbUI.Compat.After = function(_, callback)
        c.pending[#c.pending + 1] = callback
    end
    BadbUI.ConfigUI.Confirm = function(_, _, confirm)
        c.confirm = confirm
    end

    function c:Flush()
        local callbacks = self.pending
        self.pending = {}
        for _, callback in ipairs(callbacks) do callback() end
    end

    function c:Fire(event, ...)
        Mock.Fire(event, ...)
        self:Flush()
    end

    local ok, err = pcall(run, c, BadbUI.QoL)
    BadbUI.Compat.After, BadbUI.ConfigUI.Confirm = origAfter, origConfirm
    for k in pairs(globals) do _G[k] = original[k] end
    if not ok then error(err, 0) end
end

T["le automazioni sono facoltative e le azioni manuali chiedono conferma"] = function(Mock)
    withClient(Mock, function(c, m)
        c:Fire("MERCHANT_SHOW")
        c:Fire("QUEST_DETAIL")
        c:Fire("QUEST_PROGRESS")
        eq(c.repairs, 0)
        eq(c.accepted, 0)
        eq(c.advanced, 0)
        eq(m:ConfirmJunkSale(), true)
        eq(c.sold, 0)
        eq(m:ConfirmJunkSale(), false)
        c.confirm()
        c.confirm()
        eq(c.sold, 1)
    end)
end

T["il bottino segue il profilo e ripristina il CVar quando il modulo viene spento"] = function(Mock)
    local m, DB = BadbUI.QoL, BadbUI.DB
    Mock.cvars.autoLootDefault = "0"
    m:Set("autoLoot", true)
    eq(Mock.cvars.autoLootDefault, "1")

    DB:SetProfile("Riposo")
    eq(Mock.cvars.autoLootDefault, "0")
    DB:SetProfile("Default")
    eq(Mock.cvars.autoLootDefault, "1")

    BadbUI.Modules:SetEnabled(m.name, false)
    eq(Mock.cvars.autoLootDefault, "0")
end

T["modifiche al bottino in combattimento si riconciliano con lo stato finale"] = function(Mock)
    local m = BadbUI.QoL
    Mock.cvars.autoLootDefault = "0"
    Mock.combat = true
    m:Set("autoLoot", true)
    eq(Mock.cvars.autoLootDefault, "0")
    BadbUI.Modules:SetEnabled(m.name, false)
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(Mock.cvars.autoLootDefault, "0")

    BadbUI.Modules:SetEnabled(m.name, true)
    eq(Mock.cvars.autoLootDefault, "1")
    Mock.combat = true
    m:Set("autoLoot", false)
    eq(Mock.cvars.autoLootDefault, "1")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(Mock.cvars.autoLootDefault, "0")
end

T["riparazione personale al massimo una volta per visita con tetto e saldo"] = function(Mock)
    withClient(Mock, function(c, m)
        m:Set("autoRepair", true)
        c:Fire("MERCHANT_SHOW")
        c:Fire("MERCHANT_SHOW")
        eq(c.repairs, 1)

        c:Fire("MERCHANT_CLOSED")
        c.funds = 200
        c:Fire("MERCHANT_SHOW")
        eq(c.repairs, 1)

        c:Fire("MERCHANT_CLOSED")
        m:Set("repairCap", 1)
        c.funds = 20000
        c.cost = 10001
        c:Fire("MERCHANT_SHOW")
        eq(c.repairs, 1)

        c:Fire("MERCHANT_CLOSED")
        m:Set("repairCap", { invalid = true })
        eq(m:GetRepairCap(), 10)
        c:Fire("MERCHANT_SHOW")
        eq(c.repairs, 2)
    end)
end

T["riparazione ignora shift, combattimento, dati segreti e interazioni concluse"] = function(Mock)
    withClient(Mock, function(c, m)
        m:Set("autoRepair", true)
        c.shift = true
        c:Fire("MERCHANT_SHOW")
        c:Fire("MERCHANT_CLOSED")

        c.shift, Mock.combat = false, true
        c:Fire("MERCHANT_SHOW")
        Mock.combat = false
        c:Fire("PLAYER_REGEN_ENABLED")
        c:Fire("MERCHANT_CLOSED")

        local cost = c.cost
        c.cost = Mock.Secret()
        c:Fire("MERCHANT_SHOW")
        c:Fire("MERCHANT_CLOSED")
        c.cost = cost

        Mock.Fire("MERCHANT_SHOW")
        c:Fire("MERCHANT_CLOSED")
        eq(c.repairs, 0)
    end)
end

T["conferma cianfrusaglie annullata se cambiano borse, visita o combattimento"] = function(Mock)
    withClient(Mock, function(c, m)
        c:Fire("MERCHANT_SHOW")
        eq(m:ConfirmJunkSale(), true)
        c:Fire("BAG_UPDATE", 0)
        c.confirm()

        eq(m:ConfirmJunkSale(), true)
        c:Fire("MERCHANT_CLOSED")
        c:Fire("MERCHANT_SHOW")
        c.confirm()

        eq(m:ConfirmJunkSale(), true)
        Mock.combat = true
        c.confirm()
        eq(c.sold, 0)
    end)
end

T["missioni dal PNG accettate e consegnate senza scegliere tra più ricompense"] = function(Mock)
    withClient(Mock, function(c, m)
        m:Set("autoAccept", true)
        m:Set("autoComplete", true)
        c:Fire("QUEST_DETAIL")
        eq(c.accepted, 1)
        c:Fire("QUEST_PROGRESS")
        eq(c.advanced, 1)
        c:Fire("QUEST_COMPLETE")
        eq(c.rewards, 1)
        eq(c.choice, 0)

        c.choices = 1
        c:Fire("QUEST_COMPLETE")
        eq(c.rewards, 2)
        eq(c.choice, 1)

        c.choices = 2
        c:Fire("QUEST_COMPLETE")
        eq(c.rewards, 2)
    end)
end

T["missioni da oggetti, valori segreti, offerte fuori contesto e costi restano manuali"] = function(Mock)
    withClient(Mock, function(c, m)
        m:Set("autoAccept", true)
        m:Set("autoComplete", true)

        c:Fire("QUEST_DETAIL", 12840)
        c:Fire("QUEST_DETAIL", Mock.Secret())
        c.playerNPC = true
        c:Fire("QUEST_DETAIL")
        c.playerNPC, c.shift = false, true
        c:Fire("QUEST_DETAIL")
        c.shift = false
        c.autoAccept = true
        c:Fire("QUEST_DETAIL")

        c.id = Mock.Secret()
        c:Fire("QUEST_DETAIL")
        c.id = 42
        c.moneyRequired = 10
        c:Fire("QUEST_PROGRESS")
        c:Fire("QUEST_COMPLETE")

        c.moneyRequired = 0
        c.currencyRequired = 1
        c:Fire("QUEST_PROGRESS")
        c.currencyRequired = Mock.Secret()
        c:Fire("QUEST_COMPLETE")
        eq(c.accepted, 0)
        eq(c.advanced, 0)
        eq(c.rewards, 0)
    end)
end

T["dialoghi pendenti invalidati quando la missione si chiude o cambia profilo"] = function(Mock)
    withClient(Mock, function(c, m)
        m:Set("autoAccept", true)
        Mock.Fire("QUEST_DETAIL")
        c:Fire("QUEST_FINISHED")
        Mock.Fire("QUEST_DETAIL")
        BadbUI.DB:SetProfile("Altro")
        c:Flush()
        eq(c.accepted, 0)
    end)
end

T["pagina, guida e copertura parziale funzionano con API assenti"] = function(Mock)
    withClient(Mock, function(c, m)
        C_MerchantFrame, GetQuestID, CanMerchantRepair = nil, nil, nil
        eq(m:HasJunkAPI(), false)
        eq(m:HasAcceptAPI(), false)
        eq(m:HasCompleteAPI(), false)
        eq(m:HasRepairAPI(), false)
        eq(m:HasLootAPI(), false)
        eq(m:ConfirmJunkSale(), false)
        Mock.Methods.Disable = function(self) self.__disabled = true end
        assert(m.page.build(Mock.NewObject("Frame")) > 0)
        assert(BadbUI.ConfigUI:FindPage("mod:QoL"))
        assert(BadbUI.Guides:Get("qol:automation"))
        for _, row in ipairs(BadbUI.Suite:ListCoverage()) do
            if row.addon == "Leatrix_Plus" then
                eq(row.coverage, "partial")
                eq(row.removable, false)
                return
            end
        end
        error("copertura Leatrix Plus non registrata")
    end)
end

return T
