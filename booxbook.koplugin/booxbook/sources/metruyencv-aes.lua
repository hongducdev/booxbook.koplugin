-- AES-128 encryption for signatures; KOReader Android exports only AES decryption.
local bit = require("bit")
local bxor, band, lshift, rshift = bit.bxor, bit.band, bit.lshift, bit.rshift
local AES = {}
local function xtime(a)
    return bxor(band(lshift(a, 1), 255), a >= 128 and 27 or 0)
end
local function multiply(a, b)
    local result = 0
    for _ = 1, 8 do
        if band(b, 1) ~= 0 then result = bxor(result, a) end
        a, b = xtime(a), rshift(b, 1)
    end
    return result
end
local sbox = {}
for a = 0, 255 do
    local inverse, power, exponent = 1, a, 254
    while exponent > 0 do
        if exponent % 2 == 1 then inverse = multiply(inverse, power) end
        power, exponent = multiply(power, power), math.floor(exponent / 2)
    end
    local value = inverse
    for shift = 1, 4 do
        value = bxor(value, band(lshift(inverse, shift), 255), rshift(inverse, 8 - shift))
    end
    sbox[a] = bxor(value, 99)
end

local function expand(key)
    assert(#key == 16, "AES-128 key required")
    local bytes, rcon = { key:byte(1, 16) }, 1
    for offset = 17, 176, 4 do
        local t = { unpack(bytes, offset - 4, offset - 1) }
        if (offset - 1) % 16 == 0 then
            t = { bxor(sbox[t[2]], rcon), sbox[t[3]], sbox[t[4]], sbox[t[1]] }
            rcon = xtime(rcon)
        end
        for i = 0, 3 do bytes[offset + i] = bxor(bytes[offset + i - 16], t[i + 1]) end
    end
    return bytes
end

local function encrypt(block, keys)
    local state = { block:byte(1, 16) }
    for i = 1, 16 do state[i] = bxor(state[i], keys[i]) end
    for round = 1, 10 do
        local shifted = {}
        for column = 0, 3 do
            for row = 0, 3 do shifted[column * 4 + row + 1] = sbox[state[((column + row) % 4) * 4 + row + 1]] end
        end
        state = shifted
        if round < 10 then
            for i = 1, 16, 4 do
                local a, b, c, d = unpack(state, i, i + 3)
                local all = bxor(a, b, c, d)
                state[i] = bxor(a, all, xtime(bxor(a, b)))
                state[i + 1] = bxor(b, all, xtime(bxor(b, c)))
                state[i + 2] = bxor(c, all, xtime(bxor(c, d)))
                state[i + 3] = bxor(d, all, xtime(bxor(d, a)))
            end
        end
        for i = 1, 16 do state[i] = bxor(state[i], keys[round * 16 + i]) end
    end
    return string.char(unpack(state))
end

function AES.encryptCBC(input, key, iv)
    assert(#iv == 16, "AES IV required")
    local padding = 16 - #input % 16
    input = input .. string.rep(string.char(padding), padding)
    local keys, blocks = expand(key), {}
    for offset = 1, #input, 16 do
        local block = {}
        for i = 1, 16 do block[i] = bxor(input:byte(offset + i - 1), iv:byte(i)) end
        iv = encrypt(string.char(unpack(block)), keys)
        blocks[#blocks + 1] = iv
    end
    return table.concat(blocks)
end
return AES
