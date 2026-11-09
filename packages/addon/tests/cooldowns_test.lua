-- Test del modulo Cooldowns
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

local T = {}

T["attiva il countdown nativo e ripristina la CVar"] = function(Mock)
    eq(Mock.cvars.countdownForCooldowns, "1", "CVar attivata")
    BadbUI.Modules:SetEnabled("Cooldowns", false)
    eq(Mock.cvars.countdownForCooldowns, "0", "CVar ripristinata al valore originale")
end

T["stile del testo sui pulsanti"] = function()
    local cd = ActionButton1Cooldown
    cd:SetCooldown(90, 30)
    local font, size = cd:GetCountdownFontString():GetFont()
    eq(font, BadbUI.ActionBarsLib.Font("number"), "font numerico del tema")
    eq(size, 17, "dimensione proporzionale (40 * 0.42)")
    eq(cd.__hideNumbers, false, "numeri visibili")
end

T["GCD senza numeri"] = function()
    ActionButton1Cooldown:SetCooldown(100, 1.5)
    eq(ActionButton1Cooldown.__hideNumbers, true, "numeri nascosti sotto la soglia")
end

T["colore per tempo rimanente"] = function(Mock)
    local Lib = BadbUI.ActionBarsLib
    local cd = ActionButton1Cooldown
    cd:SetCooldown(100, 120)
    local driver = BadbUI.Modules:Get("Cooldowns")._driver
    driver.__scripts.OnUpdate(driver, 0.2)
    eq(cd:GetCountdownFontString().__color[1], select(1, Lib.Color("textDim")), "oltre il minuto")
    Mock.time = 217
    driver.__scripts.OnUpdate(driver, 0.2)
    eq(cd:GetCountdownFontString().__color[1], select(1, Lib.Color("danger")), "in scadenza")
end

T["durate secret: solo stile, nessun errore"] = function(Mock)
    local cd = ActionButton2Cooldown
    cd:SetCooldown(Mock.Secret(), Mock.Secret())
    eq(cd.__hideNumbers, false, "il client disegna il countdown")
end

T["cooldown esterni ignorati salvo opzione"] = function()
    local other = CreateFrame("Cooldown", "SomeBuffCooldown")
    other:SetCooldown(100, 30)
    eq(other.__hideNumbers, nil, "non toccato")
    BadbUI.Modules:Get("Cooldowns"):Set("allCooldowns", true)
    other:SetCooldown(100, 30)
    eq(other.__hideNumbers, false, "stilato con allCooldowns")
    local forbidden = CreateFrame("Cooldown", "NameplateCooldown")
    forbidden.__forbidden = true
    forbidden:SetCooldown(100, 30)
    eq(forbidden.__hideNumbers, nil, "frame forbidden mai toccati")
end

T["pulse a fine cooldown lungo"] = function()
    local CD = BadbUI.Modules:Get("Cooldowns")
    local played = 0
    local orig = CD.Pulse
    CD.Pulse = function(self, tex) played = played + 1; return orig(self, tex) end
    ActionButton1.icon:SetTexture(12345)
    ActionButton1Cooldown:SetCooldown(100, 30)
    ActionButton1Cooldown.__scripts.OnCooldownDone(ActionButton1Cooldown)
    eq(played, 1, "pulse dopo 30s")
    ActionButton1Cooldown:SetCooldown(100, 1.5)
    ActionButton1Cooldown.__scripts.OnCooldownDone(ActionButton1Cooldown)
    eq(played, 1, "niente pulse per il GCD")
end

T["pulse registrato nel FrameManager"] = function()
    local desc = BadbUI.FrameManager.registry.CooldownPulse
    assert(desc, "pulse non registrato")
    eq(desc.frame, _G.BadbUICooldownPulse, "frame del pulse")
end

T["edge: CVar gia' attiva resta attiva dopo la disattivazione"] = function(Mock)
    -- Lo stato originale e' salvato alla prima attivazione nel DB globale.
    BadbUI.Modules:SetEnabled("Cooldowns", false)
    Mock.cvars.countdownForCooldowns = "1"
    BadbUI.Modules:SetEnabled("Cooldowns", true)
    BadbUI.Modules:SetEnabled("Cooldowns", false)
    eq(Mock.cvars.countdownForCooldowns, "1", "valore utente rispettato")
end

T["edge: numeri disattivati"] = function()
    BadbUI.Modules:Get("Cooldowns"):Set("numbers", false)
    ActionButton1Cooldown:SetCooldown(100, 30)
    eq(ActionButton1Cooldown.__hideNumbers, true, "numeri nascosti")
end

T["edge: cooldown azzerato (start 0) non resta nel driver"] = function()
    local CD = BadbUI.Modules:Get("Cooldowns")
    ActionButton1Cooldown:SetCooldown(0, 0)
    CD._driver.__scripts.OnUpdate(CD._driver, 0.2)
    eq(CD._driver:IsShown(), false, "driver fermo senza cooldown attivi")
end

T["edge: frame con larghezza 0 (non ancora layoutato)"] = function()
    ActionButton3Cooldown.__width = 0
    ActionButton3Cooldown:SetCooldown(100, 30)
    eq(select(2, ActionButton3Cooldown:GetCountdownFontString():GetFont()), 15, "dimensione di fallback (36 * 0.42)")
end

T["edge: pulse con texture secret o modulo spento"] = function(Mock)
    local CD = BadbUI.Modules:Get("Cooldowns")
    local played = 0
    CD.Pulse = function() played = played + 1 end
    ActionButton1.icon:SetTexture(Mock.Secret())
    ActionButton1Cooldown:SetCooldown(100, 30)
    ActionButton1Cooldown.__scripts.OnCooldownDone(ActionButton1Cooldown)
    eq(played, 0, "texture opaca ignorata")
    ActionButton1.icon:SetTexture(1)
    CD:Set("pulse", false)
    ActionButton1Cooldown.__scripts.OnCooldownDone(ActionButton1Cooldown)
    eq(played, 0, "pulse disattivato")
end

T["edge: disattivazione ripristina stile Blizzard"] = function()
    ActionButton1Cooldown:SetCooldown(100, 30)
    BadbUI.Modules:SetEnabled("Cooldowns", false)
    eq(ActionButton1Cooldown:GetCountdownFontString():GetFont(), "Fonts\\FRIZQT__.TTF", "font originale")
    eq(ActionButton1Cooldown.__swipe[4], 0.8, "swipe Blizzard")
    ActionButton1Cooldown:SetCooldown(100, 1)
    eq(ActionButton1Cooldown.__hideNumbers, false, "hook inerte da spento")
end

return T
