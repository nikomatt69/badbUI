-- Language is chosen before descriptors, guides and module titles are built.
-- Changing the preference takes effect on /reload; stored IDs never change.
local _, ns = ...
local Badb = ns.Badb
local Localization = { locales = {}, supported = { enUS = true, itIT = true } }
Badb.Localization = Localization

function Localization:Resolve(preference, clientLocale)
    if self.supported[preference] then return preference end
    return clientLocale == "itIT" and "itIT" or "enUS"
end

function Localization:GetPreference()
    local global = type(BadbUIDB) == "table" and BadbUIDB.global
    local language = type(global) == "table" and global.language
    return self.supported[language] and language or "auto"
end

Localization.language = Localization:Resolve(Localization:GetPreference(), GetLocale and GetLocale())

function Localization:RegisterLocale(locale, translations)
    assert(self.supported[locale], "Unsupported locale: " .. tostring(locale))
    local entries = self.locales[locale] or {}
    for key, value in pairs(translations) do
        assert(type(key) == "string" and type(value) == "string", "Invalid translation")
        entries[key] = value
    end
    self.locales[locale] = entries
end

function Localization:Translate(key, locale)
    local entries = self.locales[locale or self.language]
    local translated = entries and entries[key]
    if translated ~= nil then return translated end
    -- Most source keys are Italian. New English keys can fall back to enUS.
    if (locale or self.language) ~= "itIT" then
        local english = self.locales.enUS
        if english and english[key] ~= nil then return english[key] end
    end
    return key
end

function Localization:SetPreference(preference)
    if preference ~= "auto" and not self.supported[preference] then
        return false, Badb.L["Language must be auto, enUS or itIT."]
    end
    BadbUIDB = type(BadbUIDB) == "table" and BadbUIDB or {}
    BadbUIDB.global = type(BadbUIDB.global) == "table" and BadbUIDB.global or {}
    BadbUIDB.global.language = preference
    -- Existing descriptors contain translated strings: keep one consistent
    -- language until the next load instead of switching only some labels.
    return true, self:Resolve(preference, GetLocale and GetLocale()) ~= self.language
end

setmetatable(Badb.L, { __index = function(_, key) return Localization:Translate(key) end })
