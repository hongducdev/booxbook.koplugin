-- Public HTML payload decoding adapted from Nekori LNHako/utils.ts (MIT).
-- See booxbook.koplugin/THIRD-PARTY-NOTICES.md. This only reads bytes supplied in the page.
local Html = require("booxbook.html")
local Payload = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local values = {}
for i = 1, #alphabet do values[alphabet:sub(i, i)] = i - 1 end

local function base64(value)
    value = value:gsub("%s", "")
    if value:find("[^%w+/=]") or #value % 4 ~= 0 or value:find("=.+[^=]") then return nil end
    local result, bits, accumulator = {}, 0, 0
    for char in value:gmatch(".") do
        if char ~= "=" then
            local number = values[char]
            if not number then return nil end
            accumulator, bits = accumulator * 64 + number, bits + 6
            if bits >= 8 then
                bits = bits - 8
                result[#result + 1] = string.char(math.floor(accumulator / 2 ^ bits))
                accumulator = accumulator % 2 ^ bits
            end
        end
    end
    return table.concat(result)
end

local function xor(a, b)
    local result, bit = 0, 1
    for _ = 1, 8 do
        if a % 2 ~= b % 2 then result = result + bit end
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return result
end

function Payload.decode(attrs)
    local mode = Html.attr(attrs, "data%-s") or ""
    if mode ~= "" and mode ~= "base64" and mode ~= "xor_shuffle" and mode ~= "base64_reverse" then
        return nil, "unsupported"
    end
    local key = Html.decode(Html.attr(attrs, "data%-k") or "")
    local raw = Html.decode(Html.attr(attrs, "data%-c") or ""):gsub("\\/", "/")
    local chunks = {}
    if raw:match("^%s*%[") then
        -- The JSON array contains base64 ASCII strings, never arbitrary JSON values.
        local structure = raw:gsub('"([%w+/=]+)"', function(chunk)
            chunks[#chunks + 1] = chunk; return "x"
        end):gsub("%s", "")
        if #chunks == 0 or structure ~= "[" .. string.rep("x,", #chunks - 1) .. "x]" then
            return nil, "invalid"
        end
    elseif raw ~= "" then chunks[1] = raw end
    if #chunks == 0 then return nil, "empty" end
    table.sort(chunks, function(a, b)
        return (tonumber(a:sub(1, 4)) or 0) < (tonumber(b:sub(1, 4)) or 0)
    end)
    local result = {}
    for _, chunk in ipairs(chunks) do
        local encoded = chunk:gsub("^%d%d%d%d", "", 1)
        if mode == "base64_reverse" then encoded = encoded:reverse() end
        local decoded = base64(encoded)
        if not decoded then return nil, "invalid" end
        if mode == "xor_shuffle" and key ~= "" then
            local bytes = {}
            for i = 1, #decoded do
                bytes[i] = string.char(xor(decoded:byte(i), key:byte((i - 1) % #key + 1)))
            end
            decoded = table.concat(bytes)
        end
        result[#result + 1] = decoded
    end
    return table.concat(result)
end

return Payload
