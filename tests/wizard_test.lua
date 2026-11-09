-- Test del Setup Wizard (Config/Wizard.lua): logica a passi, piano di esecuzione, stato, UI nel mock.
-- Presets / Player / Contexts / Backups / Integrations / Diagnostics sono FINTI (definiti qui): registrano le chiamate.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso vero", 2) end end

local T = {}

------------------------------------------------------------------------------
-- Fake
------------------------------------------------------------------------------
local function fakePresets(env)
    local P = {}
    local log = env.log
    P.roles = {
        tank = { title = "Tank", description = "t", icon = "x" },
        healer = { title = "Healer", description = "h", icon = "x" },
        dps = { title = "DPS", description = "d", icon = "x" },
    }
    P.roleOrder = { "tank", "healer", "dps" }
    P.content = {}
    P.contentOrder = { "leveling", "dungeon", "raid", "pvp" }
    for _, id in ipairs(P.contentOrder) do P.content[id] = { title = id, description = id, icon = "x" } end

    local function def(class, mode, scenario, extra)
        local d = { key = class:lower() .. "-" .. mode .. "-" .. scenario, class = class, mode = mode, scenario = scenario,
            title = scenario .. " " .. class, rationale = "Perche' si': " .. scenario }
        for k, v in pairs(extra or {}) do d[k] = v end
        return d
    end
    P.defs = {}
    for _, class in ipairs({ "PRIEST", "WARRIOR", "HUNTER", "DRUID" }) do
        P.defs[#P.defs + 1] = def(class, "pve", "dungeon")
        P.defs[#P.defs + 1] = def(class, "pve", "raid", { variants = { ["10"] = {}, ["20"] = {}, ["40"] = {} } })
        P.defs[#P.defs + 1] = def(class, "pve", "solo")
        P.defs[#P.defs + 1] = def(class, "pvp", "bg")
        P.defs[#P.defs + 1] = def(class, "pvp", "av")
        P.defs[#P.defs + 1] = def(class, "pvp", "world")
    end
    P.stack = {}

    function P:List(f)
        f = f or {}
        local out = {}
        for _, d in ipairs(self.defs) do
            local ok = true
            if not self.ignoreFilters then
                if f.class and d.class ~= f.class then ok = false end
                if f.mode and d.mode ~= f.mode then ok = false end
            end
            if ok then out[#out + 1] = d end
        end
        return out
    end
    function P:Get(key) for _, d in ipairs(self.defs) do if d.key == key then return d end end end
    function P:Diff(key) if not self:Get(key) then return {} end return { { module = "A" }, { module = "B" }, { module = "C" } } end
    function P:Build(c) return { title = tostring(c.content) .. " " .. tostring(c.role), modules = {} } end
    function P:Describe() return { "riga uno", "riga due" } end
    function P:Recommend() return { content = "dungeon", role = "healer", pixelPerfect = true, hideClutter = false, friendlyPlates = false } end
    local function newProfile(name)
        local DB = BadbUI.DB
        local prev = DB:GetProfileName()
        table.insert(self_stack or P.stack, prev)
        DB:CopyProfile(prev, name)
        DB:SetProfile(name)
    end
    function P:Apply(a, opts)
        if type(a) == "table" then
            log[#log + 1] = "apply-spec:" .. tostring(a.title)
            if self.failSpec then return nil end
            local name = "Badb - " .. a.title
            newProfile(name)
            return name
        end
        log[#log + 1] = string.format("apply:%s:%s:%s", tostring(a), tostring(opts and opts.variant), tostring(opts and opts.role))
        if self.failKey == a then return false, "boom" end
        if self.throwKey == a then error("esplosione") end
        newProfile((opts and opts.profileName) or ("Badb - " .. a))
        return true
    end
    function P:Undo()
        log[#log + 1] = "undo"
        local prev = table.remove(self.stack)
        if not prev then return false, "niente da annullare" end
        BadbUI.DB:SetProfile(prev)
        return true
    end
    function P:CanUndo() return #self.stack > 0 end
    return P
end

local function fakePlayer(opts)
    local snap = { class = opts.class or "PRIEST", role = opts.role or "healer", roleSource = "tree-name",
        roleConfidence = opts.confidence or "high", roleAmbiguous = opts.ambiguous or false }
    local roles = { PRIEST = { "healer", "dps" }, HUNTER = { "dps" }, DRUID = { "dps", "tank", "healer" }, WARRIOR = { "dps", "tank" } }
    local Pl = { overrides = {}, snap = snap }
    Pl.CLASSES = {}
    for token, r in pairs(roles) do Pl.CLASSES[#Pl.CLASSES + 1] = { token = token, roles = r } end
    function Pl:GetSnapshot() return self.snap end
    function Pl:GetClassInfo(token) for _, c in ipairs(self.CLASSES) do if c.token == token then return c end end end
    function Pl:SetRoleOverride(role)
        opts.env.log[#opts.env.log + 1] = "override:" .. tostring(role)
        self.overrides[#self.overrides + 1] = role or false
        return true
    end
    return Pl
end

local function fakeContexts(env, opts)
    local C = { rules = {}, nextId = 1 }
    function C:ListRules() return self.rules end
    function C:AddRule(rule)
        env.log[#env.log + 1] = "addrule:" .. tostring(rule.name) .. ":" .. tostring(rule.when and rule.when.instance) .. ":" .. tostring(rule.profile)
        if opts.failAddRule then return nil, "regola rifiutata" end
        local id = self.nextId; self.nextId = id + 1
        self.rules[#self.rules + 1] = { id = id, name = rule.name }
        return id
    end
    function C:RemoveRule(id)
        env.log[#env.log + 1] = "removerule:" .. tostring(id)
        for i, r in ipairs(self.rules) do if r.id == id then table.remove(self.rules, i); return true end end
        return false, "regola inesistente"
    end
    if not opts.noClassRules then
        function C:AddRulesForClass(class, o)
            env.log[#env.log + 1] = string.format("classrules:%s:%s:%s", tostring(class), tostring(o and o.pvpProfile ~= nil), tostring(o and o.pveProfile ~= nil))
            local a, b = self.nextId, self.nextId + 1
            self.nextId = b + 1
            self.rules[#self.rules + 1] = { id = a, name = "c1" }
            self.rules[#self.rules + 1] = { id = b, name = "c2" }
            return { a, b }
        end
    end
    return C
end

-- Installa i fake. opts: class, role, confidence, ambiguous, noContexts, noIntegrations, noDiagnostics, noBackups, noPlayer,
-- failAddRule, noClassRules, ignoreFilters
local function setup(Mock, opts)
    opts = opts or {}
    local Badb = BadbUI
    local env = { log = {}, Mock = Mock, Badb = Badb }
    opts.env = env
    Badb.Presets = fakePresets(env)
    Badb.Presets.ignoreFilters = opts.ignoreFilters
    Badb.Player = (not opts.noPlayer) and fakePlayer(opts) or nil
    Badb.Contexts = (not opts.noContexts) and fakeContexts(env, opts) or nil
    Badb.Backups = (not opts.noBackups) and { Create = function(_, label, kind)
        env.log[#env.log + 1] = "backup:" .. tostring(label) .. ":" .. tostring(kind)
        return "bk1"
    end } or nil
    Badb.Integrations = (not opts.noIntegrations) and {
        List = function() return { { id = "elvui", title = "ElvUI", loaded = true, supported = true },
            { id = "wa", title = "WeakAuras", loaded = true, supported = false },
            { id = "plater", title = "Plater", loaded = false, supported = true } } end,
        Capture = function(_, id)
            env.log[#env.log + 1] = "capture:" .. id
            if opts.failCapture then return false, "adapter rotto" end
            return true
        end,
    } or nil
    Badb.Diagnostics = (not opts.noDiagnostics) and { RunChecks = function()
        return { { id = "a", level = "warn", title = "ClassicUI Forever attivo" }, { id = "b", level = "ok", title = "ok" } }
    end } or nil
    local W = Badb.Wizard
    W:Reset()
    W.sessionStarted, W.wasOpen = nil, false
    env.W = W
    env.DB = Badb.DB
    function env.count(prefix)
        local n = 0
        for _, l in ipairs(env.log) do if l:sub(1, #prefix) == prefix then n = n + 1 end end
        return n
    end
    function env.index(prefix)
        for i, l in ipairs(env.log) do if l:sub(1, #prefix) == prefix then return i end end
    end
    -- Cattura Compat.After per controllare il ritardo dell'avvio automatico.
    env.timers = {}
    Badb.Compat.After = function(delay, fn) env.timers[#env.timers + 1] = { delay = delay, fn = fn } end
    -- Mock: gli oggetti Checkbutton leggono lo stato dal flag
    return env
end

local function keys(steps)
    local out = {}
    for i, st in ipairs(steps) do out[i] = st.key end
    return table.concat(out, ",")
end

------------------------------------------------------------------------------
-- Avvio automatico
------------------------------------------------------------------------------
T["avvio automatico: una sola volta, dopo il ritardo"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    Mock.Fire("PLAYER_ENTERING_WORLD") -- senza isLogin/isReload (cambio zona): niente
    eq(#env.timers, 0, "nessun timer senza login")
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#env.timers, 1)
    eq(env.timers[1].delay, 3, "ritardo breve")
    eq(W.wasOpen, false, "non ancora aperto prima del timer")
    env.timers[1].fn()
    eq(W.wasOpen, true, "aperto dopo il ritardo")
    W:Close()
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#env.timers, 1, "una sola volta per sessione")
end

T["avvio automatico: mai in combattimento, differito"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    Mock.combat = true
    env.timers[1].fn()
    eq(W.wasOpen, false, "in combattimento non si apre")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(W.wasOpen, true, "si apre a fine combattimento")
end

T["avvio automatico: non riparte se completato o saltato"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    truthy(W:Skip())
    truthy(W:IsCompleted())
    eq(env.DB.sv.global.wizard.completed, true, "persistito")
    eq(env.DB.sv.global.wizard.skipped, true, "skipped salvato")
    W.sessionStarted = nil
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#env.timers, 0, "dopo Skip non parte piu'")
    local ok, err = W:Start(false)
    eq(ok, false); truthy(err, "motivo")
    eq(W.wasOpen, false)
end

T["Reset riporta allo stato iniziale"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true); W:Skip()
    truthy(W:IsCompleted())
    W:Reset()
    eq(W:IsCompleted(), false)
    eq(env.DB.sv.global.wizardDone, nil, "flag legacy rimosso")
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#env.timers, 1, "riparte")
end

T["migrazione dal vecchio flag wizardDone"] = function(Mock)
    local env = setup(Mock)
    env.DB.sv.global.wizardDone = true
    truthy(env.W:IsCompleted())
    eq(env.W:DetectMode(), nil, "nessun wizard da proporre")
end

T["disattivazione del modulo"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    truthy(W:Start(true))
    BadbUI.Modules:SetEnabled("Wizard", false)
    eq(W.wasOpen, false, "chiuso alla disattivazione")
    local ok = W:Start(true)
    eq(ok, false, "Start rifiutato")
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#env.timers, 0, "nessun avvio automatico")
    BadbUI.Modules:SetEnabled("Wizard", true)
    truthy(W:Start(true), "riattivato")
end

------------------------------------------------------------------------------
-- Passi, saltati, validazione, persistenza risposte
------------------------------------------------------------------------------
T["passi completi con tutti i moduli"] = function(Mock)
    local env = setup(Mock)
    truthy(env.W:Start(true))
    eq(keys(env.W:GetSteps()), "welcome,role,template,details,rules,integrations,summary")
    local st = env.W:GetState()
    eq(st.step, "welcome"); eq(st.stepIndex, 1); eq(st.stepCount, 7)
end

T["passi saltati se mancano i moduli opzionali"] = function(Mock)
    local env = setup(Mock, { noContexts = true, noIntegrations = true, noDiagnostics = true })
    truthy(env.W:Start(true))
    eq(keys(env.W:GetSteps()), "welcome,role,template,details,summary")
    -- Presets senza supporto ai template di classe: passo template saltato, compare "content"
    BadbUI.Presets.List = nil
    eq(keys(env.W:GetSteps()), "welcome,role,content,details,summary")
    -- senza Badb.Player niente classe: niente template
    BadbUI.Presets = fakePresets(env)
    BadbUI.Player = nil
    eq(keys(env.W:GetSteps()), "welcome,role,content,details,summary")
    -- "Scelta generica" salta il passo template e mostra "content"
    BadbUI.Player = fakePlayer({ env = env })
    env.W.choices.useTemplate = false
    eq(keys(env.W:GetSteps()), "welcome,role,template,content,details,summary")
end

T["Presets assente: la finestra non si apre e non genera errori"] = function(Mock)
    local env = setup(Mock)
    BadbUI.Presets = nil
    local ok, err = env.W:Start(true)
    eq(ok, false); truthy(err)
    local ok2 = env.W:Finish()
    -- Finish senza Presets: nessun errore Lua, piano vuoto
    eq(ok2, true)
end

T["validazione bloccante e risposte persistenti tra Indietro/Avanti"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    truthy(W:Start(true))
    truthy(W:Next(), "welcome -> role")
    eq(W:GetState().step, "role")
    W.choices.role = "bogus"
    local ok, err = W:Next()
    eq(ok, false); truthy(err, "messaggio di errore")
    eq(W:GetState().step, "role", "resta sul passo")
    W.choices.role = "tank" -- PRIEST non puo' essere tank
    ok = W:Next()
    eq(ok, false, "ruolo non ammesso dalla classe")
    W.choices.role = "dps"
    truthy(W:Next(), "role -> template")
    eq(W:GetState().step, "template")
    W.choices.templateMode = nil
    ok = W:Next()
    eq(ok, false, "serve PvE/PvP/entrambi")
    W.choices.templateMode = "pve"
    truthy(W:Next())
    truthy(W:Back()); truthy(W:Back())
    eq(W:GetState().step, "role")
    eq(W.choices.role, "dps", "risposta conservata")
    eq(env.DB.sv.global.wizard.answers.role, "dps", "persistita in sv.global.wizard")
    eq(W:Back(), true)
    eq(W:Back(), false, "non si va prima del primo passo")
end

T["template raid: serve la dimensione (variant)"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    W:GoId("template")
    W.choices.templateMode = "pve"
    W.choices.templatePve = "priest-pve-raid"
    W.choices.raidVariant = "99"
    local ok = W:Next()
    eq(ok, false, "variante non valida")
    W.choices.raidVariant = "40"
    truthy(W:Next())
    W:EnsureChoices()
    eq(W.choices.raidVariant, "40", "scelta non sovrascritta")
end

T["template: filtro difensivo se List ignora class/mode"] = function(Mock)
    local env = setup(Mock, { ignoreFilters = true })
    truthy(env.W:Start(true))
    local pve = env.W:ClassTemplates("pve")
    eq(#pve, 3, "solo 3 template PvE della classe")
    for _, d in ipairs(pve) do eq(d.class, "PRIEST"); eq(d.mode, "pve") end
    for _, d in ipairs(env.W:ClassTemplates("pvp")) do
        truthy(d.scenario ~= "arena", "nessuna arena")
    end
end

T["ruolo: conferma richiesta se la confidenza non e' alta"] = function(Mock)
    local env = setup(Mock, { class = "DRUID", role = "dps", confidence = "medium", ambiguous = true })
    local W = env.W
    local ri = W.RoleInfo()
    eq(ri.needsConfirm, true)
    truthy(ri.allowed.tank and ri.allowed.dps and ri.allowed.healer)
    W:Start(true)
    -- "Applica consigliato" non scavalca la conferma del ruolo
    local ok = W:ApplyRecommended()
    eq(ok, false)
    eq(W:GetState().step, "role", "porta al passo ruolo")
    eq(env.count("apply"), 0, "nulla applicato")
    -- conferma: tank, poi Finish salva l'override con Player:SetRoleOverride
    W.choices.role = "tank"
    local ok2, rec = W:Finish()
    eq(ok2, true)
    eq(env.count("override:tank"), 1)
    truthy(env.index("override:tank") < env.index("apply"), "override prima del preset")
    eq(#rec.errors, 0)
end

T["ruolo: nessuna conferma se la confidenza e' alta; ruoli limitati alla classe"] = function(Mock)
    local env = setup(Mock, { class = "HUNTER", role = "dps", confidence = "high" })
    local W = env.W
    eq(W.RoleInfo().needsConfirm, false)
    W:Start(true)
    W:GoId("role")
    W.choices.role = "healer"
    local ok = W:Next()
    eq(ok, false, "il Cacciatore e' solo dps")
    W.choices.role = "dps"
    truthy(W:Next())
    local _, rec = W:Finish()
    eq(env.count("override"), 0, "nessun override salvato")
end

T["ambiente: versione client, Edit Mode e avvisi diagnostica"] = function(Mock)
    local env = setup(Mock)
    local e = env.W:DetectEnvironment()
    eq(e.client, "1.60.0")
    eq(e.diagnostics, true)
    eq(#e.issues, 1)
    eq(e.issues[1], "ClassicUI Forever attivo")
    BadbUI.Diagnostics = nil
    local e2 = env.W:DetectEnvironment()
    eq(e2.diagnostics, false); eq(#e2.issues, 0)
    BadbUI.Diagnostics = { RunChecks = function() error("diagnostica rotta") end }
    local e3 = env.W:DetectEnvironment()
    eq(#e3.issues, 0, "errore isolato")
end

------------------------------------------------------------------------------
-- Esecuzione
------------------------------------------------------------------------------
T["esecuzione completa: Entrambi (PvE raid 20 + PvP) con regole di classe"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    local done = 0
    BadbUI.Events:On({ name = "t" }, "BADB_WIZARD_DONE", function() done = done + 1 end)
    W:Start(true)
    W.choices.templateMode = "both"
    W.choices.templatePve = "priest-pve-raid"
    W.choices.templatePvp = "priest-pvp-av"
    W.choices.raidVariant = "20"
    local before = env.DB:GetProfileName()
    local ok, rec = W:Finish()
    eq(ok, true)
    eq(#rec.errors, 0)
    eq(done, 1, "BADB_WIZARD_DONE")
    eq(rec.backup, "bk1")
    local iBackup = env.index("backup:Prima del wizard:pre-preset")
    local iPvp = env.index("apply:priest-pvp-av")
    local iPve = env.index("apply:priest-pve-raid:20:healer")
    local iRules = env.index("classrules:PRIEST:true:true")
    truthy(iBackup and iPvp and iPve and iRules, "tutte le chiamate presenti: " .. table.concat(env.log, " | "))
    truthy(iBackup < iPvp and iPvp < iPve and iPve < iRules, "ordine: backup, PvP, PvE, regole")
    truthy(env.DB:GetProfileName() ~= before, "profilo PvE attivo")
    truthy(W:IsCompleted())
    eq(env.DB.sv.global.wizard.skipped, false)
    truthy(env.DB.sv.global.wizard.chars[env.DB.char], "personaggio registrato")
    eq(W.stepId, nil, "sessione conclusa")
end

T["esecuzione completa: percorso generico, regole e integrazioni"] = function(Mock)
    local env = setup(Mock, { noClassRules = true })
    local W = env.W
    W:Start(true)
    W.choices.useTemplate = false
    W.choices.content, W.choices.role = "raid", "healer"
    W.choices.ruleRaid, W.choices.rulePvp = true, true
    W.choices.integrations = { elvui = true, wa = true, plater = true }
    local ok, rec = W:Finish()
    eq(ok, true)
    eq(#rec.errors, 0, table.concat(env.log, " | "))
    truthy(env.index("apply-spec:raid healer"), "preset generico (API esistente)")
    truthy(env.index("addrule:Wizard: raid:raid:"), "regola raid")
    truthy(env.index("addrule:Wizard: PvP:pvp:"), "regola PvP (campi di battaglia)")
    eq(env.count("addrule:Wizard: arena"), 0, "nessuna arena")
    eq(env.count("capture:elvui"), 1)
    eq(env.count("capture:wa"), 0, "integrazione non supportata ignorata")
    eq(env.count("capture:plater"), 0, "integrazione non caricata ignorata")
    -- le regole puntano a profili copiati dal profilo attivo
    truthy(BadbUI.DB.sv.profiles[env.DB:GetProfileName() .. " - Raid"], "profilo raid creato")
end

T["Entrambi senza AddRulesForClass: ripiega su AddRule per i campi di battaglia"] = function(Mock)
    local env = setup(Mock, { noClassRules = true })
    local W = env.W
    W:Start(true)
    W.choices.templateMode = "both"
    local ok, rec = W:Finish()
    eq(ok, true); eq(#rec.errors, 0, table.concat(env.log, " | "))
    eq(env.count("addrule:Wizard: PvP:pvp:"), 1)
    eq(env.count("addrule"), 1, "una sola regola, senza arena")
end

T["fallimento parziale: continua, riepiloga gli errori, completa"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    local done = 0
    BadbUI.Events:On({ name = "t2" }, "BADB_WIZARD_DONE", function() done = done + 1 end)
    BadbUI.Presets.failKey = "priest-pve-dungeon"
    W:Start(true)
    W.choices.templateMode = "both"
    W.choices.integrations = { elvui = true }
    local ok, rec = W:Finish()
    eq(ok, true, "Finish non fallisce: ritorna il resoconto")
    eq(#rec.errors, 1)
    eq(rec.errors[1].id, "template-pve")
    truthy(rec.errors[1].err:find("boom"))
    eq(env.count("apply:priest-pvp-"), 1, "il PvP e' stato applicato")
    eq(env.count("classrules"), 1, "le altre azioni proseguono")
    eq(env.count("capture:elvui"), 1)
    truthy(W:IsCompleted(), "segnato completato anche con errori")
    eq(done, 1)
    truthy(W:CanUndo(), "annullabile")
    local lines = W:FormatResult(rec)
    local joined = table.concat(lines, "\n")
    truthy(joined:find("Errore"), "il riepilogo cita l'errore")
end

T["azione che genera un errore Lua: isolata"] = function(Mock)
    local env = setup(Mock)
    BadbUI.Presets.throwKey = "priest-pve-dungeon"
    env.W:Start(true)
    local ok, rec = env.W:Finish()
    eq(ok, true)
    eq(#rec.errors, 1)
    truthy(rec.errors[1].err:find("esplosione"))
end

T["backup fallito: avviso, non blocca"] = function(Mock)
    local env = setup(Mock)
    BadbUI.Backups.Create = function() return nil, "disco pieno" end
    env.W:Start(true)
    local ok, rec = env.W:Finish()
    eq(ok, true)
    eq(#rec.errors, 0)
    eq(#rec.warnings, 1)
    eq(rec.warnings[1].id, "backup")
    eq(env.count("apply:"), 1, "il preset parte comunque")
end

T["annulla tutto"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    W.choices.templateMode = "both"
    W.choices.hideClutter = true
    local before = env.DB:GetProfileName()
    local ok, rec = W:Finish()
    eq(ok, true)
    truthy(W:CanUndo())
    truthy(env.DB:GetProfileName() ~= before)
    eq(#BadbUI.Contexts.rules, 2)
    local u, err = W:Undo()
    eq(u, true, tostring(err))
    eq(env.DB:GetProfileName(), before, "profilo di partenza ripristinato")
    eq(#BadbUI.Contexts.rules, 0, "regole rimosse")
    eq(env.count("undo"), 2, "Presets:Undo per ogni template applicato")
    eq(W:CanUndo(), false)
    local again = W:Undo()
    eq(again, false, "non si annulla due volte")
end

T["annulla: Presets senza Undo, rete di sicurezza sul profilo"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    W.choices.useTemplate = false
    W.choices.ruleRaid = true
    local before = env.DB:GetProfileName()
    BadbUI.Presets.Undo = nil
    local ok = W:Finish()
    eq(ok, true)
    local u = W:Undo()
    eq(u, true)
    eq(env.DB:GetProfileName(), before)
end

T["Finish in combattimento e' rifiutato senza effetti"] = function(Mock)
    local env = setup(Mock)
    env.W:Start(true)
    Mock.combat = true
    local ok, err = env.W:Finish()
    eq(ok, false); truthy(err)
    eq(env.count("apply"), 0)
    eq(env.W:IsCompleted(), false)
    Mock.combat = false
end

T["Finish applica i consigliati se l'utente non ha scelto nulla"] = function(Mock)
    local env = setup(Mock)
    env.W:Start(true)
    local ok = env.W:ApplyRecommended()
    eq(ok, true)
    truthy(env.index("apply:priest-pve-dungeon:nil:healer"), table.concat(env.log, " | "))
end

------------------------------------------------------------------------------
-- Personaggio nuovo e stato corrotto
------------------------------------------------------------------------------
T["personaggio nuovo: wizard breve (profilo esistente o nuovo)"] = function(Mock)
    local env = setup(Mock)
    local W, DB = env.W, env.DB
    DB.sv.global.wizard = { completed = true, skipped = false, version = 1, chars = { ["Altro - Forever"] = true },
        lastProfile = "Default" }
    eq(W:DetectMode(), "short")
    Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#env.timers, 1, "propone il wizard breve")
    env.timers[1].fn()
    eq(W.wasOpen, true)
    eq(W.mode, "short")
    eq(keys(W:GetSteps()), "charprofile,summary")
    -- nome gia' esistente: bloccato
    DB:CopyProfile("Default", "Mio")
    W.choices.charMode, W.choices.charName = "new", "Mio"
    local ok = W:Next()
    eq(ok, false, "nome duplicato")
    W.choices.charName = ""
    eq((W:Next()), false, "nome vuoto")
    W.choices.charName = "Bad|cffff0000Name"
    eq((W:Next()), false, "caratteri non validi")
    W.choices.charName = "Nuovo PG"
    truthy(W:Next())
    local fin, rec = W:Next()
    eq(fin, true); eq(#rec.errors, 0)
    eq(DB:GetProfileName(), "Nuovo PG")
    eq(env.count("backup"), 0, "nessun backup per la sola scelta del profilo")
    truthy(DB.sv.global.wizard.chars[DB.char])
    eq(W:DetectMode(), nil, "non lo ripropone")
    truthy(W:Undo())
    eq(DB:GetProfileName(), "Default")
end

T["personaggio nuovo: usa il profilo esistente"] = function(Mock)
    local env = setup(Mock)
    local W, DB = env.W, env.DB
    DB:CopyProfile("Default", "Tank")
    DB.sv.global.wizard = { completed = true, chars = { ["Altro - Forever"] = true }, lastProfile = "Tank" }
    truthy(W:Start(false))
    eq(W.choices.charProfile, "Tank", "preselezionato l'ultimo profilo usato")
    truthy(W:Next())
    truthy(W:Next())
    eq(DB:GetProfileName(), "Tank")
end

T["personaggio nuovo: se l'account ha scelto 'non mostrare piu' non si propone"] = function(Mock)
    local env = setup(Mock)
    env.DB.sv.global.wizard = { completed = true, skipped = true, chars = { ["Altro - Forever"] = true } }
    eq(env.W:DetectMode(), nil)
end

T["stato corrotto in sv.global.wizard"] = function(Mock)
    local env = setup(Mock)
    local W, DB = env.W, env.DB
    local cyc = {}
    cyc.answers, cyc.chars, cyc.step = cyc, cyc, cyc
    local samples = {
        "spazzatura", 42, true, {},
        { completed = "si", step = 7, version = "x", answers = { role = {}, hide = 1, templateMode = "arena", ruleRaid = "no",
            integrations = { x = "y", [1] = true } }, chars = "a", lastProfile = 5 },
        { completed = true, answers = "x", chars = { [1] = true, a = 5 } },
        cyc,
        { answers = { role = string.rep("x", 100000), charName = string.rep("y", 100000) } },
    }
    for i, s in ipairs(samples) do
        DB.sv.global.wizard = s
        local ok, err = pcall(function()
            W:IsCompleted(); W:GetState(); W:DetectMode()
            W:Start(true); W:Close()
        end)
        eq(ok, true, "campione " .. i .. ": " .. tostring(err))
        eq(type(DB.sv.global.wizard), "table", "normalizzato " .. i)
        eq(type(DB.sv.global.wizard.answers), "table")
    end
    DB.sv.global.wizard = { completed = "si" }
    eq(W:IsCompleted(), false, "completed non booleano = non completato")
    DB.sv.global.wizard = { answers = { role = string.rep("x", 100000) } }
    W:GetState()
    truthy(#DB.sv.global.wizard.answers.role <= 64, "stringhe limitate")
    DB.sv.global = "rotto"
    eq(pcall(W.IsCompleted, W), true, "anche global corrotto")
end

------------------------------------------------------------------------------
-- UI nel mock
------------------------------------------------------------------------------
local function click(btn)
    local fn = btn.__scripts.OnClick
    truthy(fn, "OnClick mancante")
    fn(btn)
end

T["UI: percorre tutti i passi e applica; il riepilogo ha 'Annulla tutto'"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    truthy(W:Start(true))
    local f = W:GetFrame()
    truthy(f, "finestra creata")
    eq(f.__name, "BadbUIWizard")
    local n = #W:GetSteps()
    for i = 1, n - 1 do
        eq(W:GetState().stepIndex, i)
        local page = W:GetPage(W:GetState().step)
        truthy(page, "pagina costruita " .. W:GetState().step)
        eq(page.buildError, nil, "passo " .. W:GetState().step .. ": " .. tostring(page.buildError))
        click(f.next)
    end
    eq(W:GetState().step, "summary")
    eq(f.next.text.__text, "Applica", "ultimo passo")
    click(f.next)
    eq(f.result.__shown, true, "riepilogo finale")
    eq(f.result.undo.__shown, true, "Annulla tutto disponibile")
    local before = env.DB:GetProfileName()
    click(f.result.undo)
    truthy(env.DB:GetProfileName() ~= before)
    eq(f.result.undo.__shown, false)
    eq(f.result.title.__text, "Modifiche annullate")
    click(f.result.close)
    eq(f.__shown, false)
end

T["UI: errore di validazione mostrato e passo bloccato"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    local f = W:GetFrame()
    click(f.next) -- welcome -> role
    W.choices.role = "bogus"
    click(f.next)
    eq(W:GetState().step, "role")
    truthy(f.err.__text and f.err.__text ~= "", "messaggio visibile")
    click(f.back)
    eq(W:GetState().step, "welcome")
end

T["UI: ESC chiede conferma; 'non mostrare piu'' salta in modo persistente"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    local f = W:GetFrame()
    f.__scripts.OnKeyDown(f, "ESCAPE")
    eq(f.confirm.__shown, true, "conferma")
    eq(W:IsCompleted(), false, "ESC da solo non salta")
    click(f.confirmButtons.resume)
    eq(f.confirm.__shown, false)
    f.__scripts.OnKeyDown(f, "X")
    eq(f.confirm.__shown, false, "altri tasti ignorati")
    click(f.skip)
    eq(f.confirm.__shown, true, "Salta chiede conferma")
    click(f.confirmButtons.later)
    eq(W:IsCompleted(), false, "piu' tardi non salva")
    eq(W.wasOpen, false)
    W:Start(true)
    click(f.skip)
    click(f.confirmButtons.never)
    truthy(W:IsCompleted())
    eq(env.DB.sv.global.wizard.skipped, true)
    eq(f.__shown, false)
end

T["UI: passo con build difettoso mostra un box d'errore e non blocca"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    BadbUI.Presets.roleOrder = { "inesistente" } -- la card del ruolo non si puo' costruire
    truthy(W:Start(true))
    click(W:GetFrame().next)
    eq(W:GetState().step, "role")
    truthy(W:GetPage("role").buildError, "errore registrato")
    local ok = W:Next()
    eq(ok, true, "si puo' proseguire")
end

T["UI: template selezionabili e varianti raid"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    W:Start(true)
    W:GoId("template")
    local page = W:GetPage("template")
    eq(page.buildError, nil, tostring(page.buildError))
    -- click sulla seconda card PvE = raid -> compaiono 10/20/40
    local card = page.pveBox.cards[2]
    eq(card.def.key, "priest-pve-raid")
    click(card)
    eq(W.choices.templatePve, "priest-pve-raid")
    eq(page.variantPills[1].variant, "10"); eq(page.variantPills[3].variant, "40")
    click(page.variantPills[3])
    eq(W.choices.raidVariant, "40")
    click(page.pveBox.cards[1])
    eq(page.variantPills[1].variant, nil, "senza varianti i pulsanti spariscono")
end

T["UI: costruzione con template Blizzard mancanti (CreateFrame che fallisce con template)"] = function(Mock)
    local env = setup(Mock)
    local orig = CreateFrame
    local failing = false
    CreateFrame = function(kind, name, parent, template)
        if failing and template == "InputBoxTemplate" then error("template mancante") end
        return orig(kind, name, parent, template)
    end
    failing = true
    env.DB.sv.global.wizard = { completed = true, chars = { ["Altro - Forever"] = true } }
    local ok, err = pcall(function()
        truthy(env.W:Start(false))
        local page = env.W:GetPage("charprofile")
        eq(env.W:GetState().step, "charprofile")
        truthy(page and page.nameBox, "EditBox con fallback")
    end)
    CreateFrame = orig
    eq(ok, true, tostring(err))
end

T["UI: wizard breve nel mock"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    env.DB.sv.global.wizard = { completed = true, chars = { ["Altro - Forever"] = true } }
    truthy(W:Start(false))
    local f = W:GetFrame()
    eq(W:GetPage("charprofile").buildError, nil)
    click(W:GetPage("charprofile").cycle) -- cambia profilo (c'e' solo Default: nessun errore)
    click(f.next)
    eq(W:GetState().step, "summary")
    eq(W:GetPage("summary").buildError, nil)
end

------------------------------------------------------------------------------
-- Modulo: comando, pagina, opzioni
------------------------------------------------------------------------------
T["modulo Wizard: comando wizard, pagina e opzioni"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    local m = BadbUI.Modules:Get("Wizard")
    truthy(m and m.enabled, "modulo registrato e attivo")
    truthy(m.commands.wizard and m.commands.wizard.help and m.commands.wizard.fn)
    eq(m.page.title, "Setup guidato")
    local h = m.page.build(CreateFrame("Frame"), {})
    eq(type(h), "number")
    m.page.refresh()
    m.commands.wizard.fn("")
    eq(W.wasOpen, true, "/badb wizard riapre anche se completato")
    W:Skip()
    m.commands.wizard.fn("status")
    m.commands.wizard.fn("reset")
    eq(W:IsCompleted(), false)
    m.options[1].func()
    eq(W.wasOpen, true)
    W:Close()
end

T["Start in combattimento: differito"] = function(Mock)
    local env = setup(Mock)
    local W = env.W
    Mock.combat = true
    local ok, err = W:Start(true)
    eq(ok, false); truthy(err)
    eq(W.wasOpen, false)
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(W.wasOpen, true)
end

T["i passi hanno la struttura data-driven"] = function(Mock)
    local env = setup(Mock)
    for _, st in ipairs(env.W.STEPS) do
        truthy(type(st.key) == "string" and type(st.title) == "string", "key/title")
        truthy(type(st.modes) == "table", "modes")
        truthy(type(st.apply) == "function", "apply")
    end
    -- apply di un passo esegue solo le sue azioni
    env.W:Start(true)
    env.W.choices.useTemplate = false
    local ok, rec = env.W.STEPS[4].apply(env.W.choices) -- content
    eq(ok, true)
    eq(#rec.done, 1)
end

return T
