-- Test del layout Edit Mode predefinito (Data/EditModeDefault.lua + Modules/EditModeBridge.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}
local function B() return BadbUI.EditModeBridge end

-- Edit Mode finto: una lista di layout di account, conversione stringa <-> info, layout attivo.
local function fakeEditMode(opts)
    opts = opts or {}
    local env = { layouts = opts.layouts or {}, active = 1, saves = 0, converted = 0 }
    BadbUI.Compat.hasEditMode = true
    Enum = Enum or {}
    Enum.EditModeLayoutType = { Account = 1, Character = 2 }
    Enum.EditModePresetLayoutsMeta = { NumValues = 2 }
    C_EditMode = {
        GetLayouts = function() return { layouts = env.layouts, activeLayout = env.active } end,
        SaveLayouts = function(l)
            if opts.saveFails then error("limite layout") end
            env.layouts = l.layouts; env.saves = env.saves + 1
        end,
        SetActiveLayout = function(i) env.active = i end,
        ConvertStringToLayoutInfo = function(s)
            env.converted = env.converted + 1
            if opts.badString then return nil end
            return { source = s }
        end,
        ConvertLayoutInfoToString = function(info) return info.source end,
    }
    return env
end

T["dati: il layout predefinito e' una stringa Edit Mode ben formata"] = function()
    local d = B():GetDefault()
    truthy(d, "layout predefinito assente")
    eq(d.name, "BadbUI")
    truthy(d.layout:match("^%d+ %d+ %d+ "), "intestazione non numerica")
    truthy(d.layout:find("MainActionBar", 1, true))
    truthy(not d.layout:find("\n", 1, true), "la stringa non deve contenere a capo")
end

T["primo avvio: installa il layout, lo associa al profilo e lo attiva una volta sola"] = function()
    local env = fakeEditMode()
    eq(B():ApplyDefault(false), true)
    eq(#env.layouts, 1)
    eq(env.layouts[1].layoutName, "BadbUI")
    eq(env.layouts[1].layoutType, 1)
    eq(env.layouts[1].source, B():GetDefault().layout)
    eq(env.active, 3, "attivo = indice + 2 preset Blizzard")
    eq(B():Get("layoutName"), "BadbUI")
    eq(B():Get("layoutString"), B():GetDefault().layout)
    eq(B():Get("defaultApplied"), 1)
    eq(B():ApplyDefault(false), false, "seconda volta: nessuna azione")
    eq(env.saves, 1)
end

T["rispetta un layout gia' associato al profilo e l'opzione spenta"] = function()
    local env = fakeEditMode()
    B():Set("layoutName", "Mio")
    eq(B():ApplyDefault(false), false)
    eq(#env.layouts, 0)
    B():Set("layoutName", nil)
    B():Set("useDefault", false)
    eq(B():ApplyDefault(false), false)
    eq(#env.layouts, 0)
end

T["un layout di account 'BadbUI' esistente non viene sovrascritto senza richiesta"] = function()
    local env = fakeEditMode({ layouts = { { layoutName = "Altro" }, { layoutName = "BadbUI", source = "modificato" } } })
    eq(B():ApplyDefault(false), true)
    eq(env.layouts[2].source, "modificato")
    eq(env.saves, 0)
    eq(env.active, 4)
    -- richiesta esplicita: torna al predefinito
    eq(B():ApplyDefault(true), true)
    eq(env.layouts[2].source, B():GetDefault().layout)
    eq(#env.layouts, 2)
end

T["stringa rifiutata dal client o salvataggio fallito: nessun errore e profilo intatto"] = function()
    fakeEditMode({ badString = true })
    eq(B():ApplyDefault(false), true)
    eq(B():Get("layoutName"), nil)
    eq(B():Get("defaultApplied"), 0)
    fakeEditMode({ saveFails = true })
    eq(B():ApplyDefault(true), true)
    eq(B():Get("layoutName"), nil)
end

T["in combattimento l'installazione aspetta la fine dello scontro"] = function(Mock)
    local env = fakeEditMode()
    Mock.combat = true
    eq(B():ApplyDefault(false), true)
    eq(#env.layouts, 0)
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(#env.layouts, 1)
    eq(B():Get("layoutName"), "BadbUI")
end

T["senza Edit Mode o con dati corrotti: rifiuto pulito"] = function()
    BadbUI.Compat.hasEditMode = false
    local ok, err = B():ApplyDefault(true)
    eq(ok, false); eq(type(err), "string")
    fakeEditMode()
    local saved = BadbUI.EditModeDefault
    for _, bad in ipairs({ false, {}, { name = "", layout = saved.layout }, { name = "X", layout = 5 }, { name = "X", layout = "corta" } }) do
        BadbUI.EditModeDefault = bad
        ok = B():ApplyDefault(true)
        eq(ok, false)
    end
    BadbUI.EditModeDefault = saved
end

T["un profilo nuovo riceve il predefinito al cambio profilo; comando /badb layout default"] = function()
    local env = fakeEditMode()
    BadbUI.Modules:SetEnabled("EditModeBridge", false)
    BadbUI.Modules:SetEnabled("EditModeBridge", true)
    BadbUI.DB:NewProfile("Secondo")
    BadbUI.DB:SetProfile("Secondo")
    eq(B():Get("layoutName"), "BadbUI")
    eq(#env.layouts, 1)
    env.layouts[1].source = "toccato"
    eq(BadbUI.Slash:Dispatch("layout default"), true)
    eq(env.layouts[1].source, B():GetDefault().layout)
    env.layouts[1].source = "toccato di nuovo"
    eq(BadbUI.Slash:Dispatch("editmode default"), true)
    eq(env.layouts[1].source, B():GetDefault().layout)
    eq(BadbUI.Slash:Dispatch("editmode"), true)
end

return T
