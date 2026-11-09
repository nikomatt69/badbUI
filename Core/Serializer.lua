-- AegisUI - Serializer
-- Converte tabelle in stringhe stampabili per import/export dei profili.
-- Formato: "AEGIS1:" .. base64(serializzazione) .. ":" .. checksum
-- Nessun loadstring sull'input: il parser e' scritto a mano, quindi un import malevolo non esegue codice.
local _, ns = ...
local Aegis = ns.Aegis

local S = {}
Aegis.Serializer = S

local PREFIX, VERSION = "AEGIS", 1

-- Serializzazione compatta: tipi n (number), s (string), b (bool), t (table).
local function ser(v, out)
    local tv = type(v)
    if tv == "number" then out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif tv == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif tv == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif tv == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local tk = type(k)
            if (tk == "string" or tk == "number") and type(val) ~= "function" and type(val) ~= "userdata" then
                ser(k, out); ser(val, out)
            end
        end
        out[#out + 1] = "}"
    end
end

local function deser(str, pos, depth)
    if depth > 40 then error("struttura troppo profonda") end
    local c = str:sub(pos, pos)
    if c == "n" then
        local e = str:find(";", pos, true); if not e then error("numero malformato") end
        local n = tonumber(str:sub(pos + 1, e - 1)); if not n then error("numero non valido") end
        return n, e + 1
    elseif c == "s" then
        local e = str:find(":", pos, true); if not e then error("stringa malformata") end
        local len = tonumber(str:sub(pos + 1, e - 1)); if not len then error("lunghezza non valida") end
        return str:sub(e + 1, e + len), e + 1 + len
    elseif c == "T" then return true, pos + 1
    elseif c == "F" then return false, pos + 1
    elseif c == "{" then
        local t = {}
        pos = pos + 1
        while str:sub(pos, pos) ~= "}" do
            if pos > #str then error("tabella non chiusa") end
            local k, v
            k, pos = deser(str, pos, depth + 1)
            v, pos = deser(str, pos, depth + 1)
            t[k] = v
        end
        return t, pos + 1
    end
    error("token inatteso '" .. c .. "' a " .. pos)
end

-- Base64
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64enc(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local B64INV = {}
for i = 1, 64 do B64INV[B64:byte(i)] = i - 1 end

local function b64dec(data)
    data = data:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #data, 4 do
        local a, b, c, d = data:byte(i, i + 3)
        local va, vb = B64INV[a], B64INV[b]
        if not va or not vb then error("base64 non valido") end
        local vc, vd = B64INV[c] or 0, B64INV[d] or 0
        local n = va * 262144 + vb * 4096 + vc * 64 + vd
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if c and c ~= 61 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if d and d ~= 61 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local function checksum(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- kind: "profile", "layout", "module:<nome>" ecc. Permette di rifiutare import del tipo sbagliato.
function S:Export(kind, data)
    local out = {}
    ser({ v = VERSION, kind = kind, addon = Aegis.version, data = data }, out)
    local raw = table.concat(out)
    return string.format("%s%d:%s:%s", PREFIX, VERSION, b64enc(raw), checksum(raw))
end

function S:Import(str, expectedKind)
    if type(str) ~= "string" then return nil, "input vuoto" end
    str = str:gsub("%s", "")
    local ver, body, sum = str:match("^" .. PREFIX .. "(%d+):([^:]+):(%x+)$")
    if not ver then return nil, "formato non riconosciuto" end
    if tonumber(ver) > VERSION then return nil, "stringa creata da una versione piu' recente di AegisUI" end
    local ok, raw = pcall(b64dec, body)
    if not ok then return nil, raw end
    if checksum(raw) ~= sum then return nil, "checksum non valido (stringa incompleta o modificata)" end
    local ok2, payload = pcall(deser, raw, 1, 0)
    if not ok2 or type(payload) ~= "table" then return nil, "dati corrotti: " .. tostring(payload) end
    if expectedKind and payload.kind ~= expectedKind then
        return nil, string.format("tipo atteso '%s', ricevuto '%s'", expectedKind, tostring(payload.kind))
    end
    return payload.data, payload
end
