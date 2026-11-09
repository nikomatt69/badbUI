-- AegisUI - Comandi slash. /aegis o /aui
local _, ns = ...
local Aegis = ns.Aegis
local DB, FM, Modules, Logger = Aegis.DB, Aegis.FrameManager, Aegis.Modules, Aegis.Logger

local commands = {}

commands[""] = function() Aegis.ConfigUI:Open() end
commands.config = commands[""]
commands.unlock = function() FM:SetUnlocked(not FM.unlocked) end
commands.profile = function(name)
    if name == "" then
        Logger:Info("Profili: %s (attivo: %s)", table.concat(DB:ListProfiles(), ", "), DB:GetProfileName())
    else
        DB:SetProfile(name)
    end
end
commands.export = function() Aegis.ConfigUI.TextBox("Esporta profilo", DB:ExportProfile()) end
commands.enable = function(name) Modules:SetEnabled(name, true) end
commands.disable = function(name) Modules:SetEnabled(name, false) end
commands.debug = function()
    Logger.level = Logger.level == 1 and 2 or 1
    Logger:Info("Debug %s", Logger.level == 1 and "attivo" or "disattivo")
end
commands.log = function()
    Aegis.ConfigUI.TextBox("Log AegisUI", table.concat(Logger.buffer, "\n"))
end
commands.help = function()
    Logger:Info("/aegis [config | unlock | profile <nome> | export | enable <modulo> | disable <modulo> | debug | log]")
end

SLASH_AEGISUI1, SLASH_AEGISUI2 = "/aegis", "/aui"
SlashCmdList.AEGISUI = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    local fn = commands[(cmd or ""):lower()] or commands.help
    fn(rest or "")
end
