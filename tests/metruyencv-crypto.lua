-- Run with KOReader's LuaJIT/ffi loader: luajit tests/metruyencv-crypto.lua
package.path = "./booxbook.koplugin/?.lua;" .. package.path
local C = require("booxbook.sources.metruyencv-crypto")
local AES = require("booxbook.sources.metruyencv-aes")
local Sha = require("ffi/sha2")
local function binary(hex) return (hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end)) end
-- NIST SP 800-38A AES-128 CBC first block (the implementation adds PKCS7).
assert(AES.encryptCBC(binary("6bc1bee22e409f96e93d7e117393172a"),
    binary("2b7e151628aed2a6abf7158809cf4f3c"), binary("000102030405060708090a0b0c0d0e0f")):sub(1, 16)
    == binary("7649abac8119b246cee98e9b12e9197d"))
-- Independently generated with .NET AES-CBC/PKCS7 and SHA1.
assert(C.signature("books?limit=20", 1700000000) ==
    "R8OWJRjJ0S0F0SM6fgUkTrr5bh6smwGDmH1cA1KkDgVeEX0P7P+OwwLD0dkS5onaCFYtOZcvCUwAIaMbMLlC2Q==")
assert(C.decrypt("6UFnRxmHj3XHY+SEj4SpWPHKj+jnLpbmkrycDk9rEpQ=", "0123456789abcdef") == "Tiếng Việt <&>\nDòng hai")
assert(not pcall(C.decrypt, "bad!", "0123456789abcdef"))
assert(not pcall(C.decrypt, "AAAA", "0123456789abcdef"))
-- Exercise CBC block chaining, binary bytes and every PKCS7 padding length.
local hash = "0123456789abcdef"
local key = Sha.sha1(Sha.bin_to_base64(hash .. hash):sub(1, 16)):sub(1, 16)
for length = 0, 65 do
    local input = string.rep("\000\255", math.floor(length / 2)) .. (length % 2 == 1 and "x" or "")
    assert(C.decrypt(Sha.bin_to_base64(AES.encryptCBC(input, key, key)), hash) == input)
end
local encrypted = AES.encryptCBC(string.rep("x", 16), key, key)
local invalid_padding = encrypted:sub(1, 15) .. string.char(require("bit").bxor(encrypted:byte(16), 1))
    .. encrypted:sub(17)
assert(not pcall(C.decrypt, Sha.bin_to_base64(invalid_padding), hash), "reject incorrect PKCS7 bytes")
local open = io.open
io.open = function() return nil end
assert(not pcall(C.hash), "missing random source must fail closed")
io.open = function() return { read = function() return "short" end, close = function() end } end
assert(not pcall(C.hash), "short random read must fail closed")
io.open = open
local a, b = C.hash(), C.hash()
assert(#a == 16 and a:match("^%w+$") and a ~= b)
print("MeTruyenCV portable AES/CBC, SHA1, padding and random source checks passed")
