-- Use only crypto functions exported by KOReader's Android monolibtic build.
local Crypto = {}
function Crypto.signature(path, time)
    local Sha = require("ffi/sha2")
    local AES = require("booxbook.sources.metruyencv-aes")
    local payload = string.format('{"app_id":"MeTruyenChu","time":%d,"path":"/api/%s"}',
        time or os.time(), path:match("^[^?]+"))
    return Sha.bin_to_base64(AES.encryptCBC(payload, "aa4uCch7CR8KiBdQ", "aa4uCch7CR8KiBdQ"))
end

function Crypto.hash()
    -- Android/Linux CSPRNG; no RAND_bytes symbol is exposed by KOReader.
    local file = assert(io.open("/dev/urandom", "rb"), "Random generator unavailable")
    local bytes = file:read(8)
    file:close()
    assert(bytes and #bytes == 8, "Random read failed")
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function Crypto.decrypt(content, hash)
    local Sha = require("ffi/sha2")
    local Native = require("ffi/crypto")
    local bit = require("bit")
    local seed = Sha.bin_to_base64(hash .. hash):sub(1, 16)
    local key = Sha.sha1(seed):sub(1, 16)
    assert(#content > 0 and #content % 4 == 0 and content:match("^[%w+/]*=?=?$"), "Invalid base64")
    local input = Sha.base64_to_bin(content)
    assert(#input > 0 and #input % 16 == 0, "Invalid AES block length")
    local output, length = Native.evp_decrypt(Native.get_aes_ecb_cipher(16), input, key, nil)
    assert(output and length == #input, "AES decryption failed")
    -- CBC plaintext = ECB decrypt(ciphertext) XOR previous ciphertext (IV for block one).
    local blocks, previous = {}, key
    for offset = 1, #input, 16 do
        local block = {}
        for i = 1, 16 do block[i] = bit.band(bit.bxor(output[offset + i - 2], previous:byte(i)), 255) end
        blocks[#blocks + 1] = string.char(unpack(block))
        previous = input:sub(offset, offset + 15)
    end
    local plain = table.concat(blocks)
    local padding = plain:byte(-1)
    assert(padding >= 1 and padding <= 16 and plain:sub(-padding) == string.rep(string.char(padding), padding),
        "Invalid AES padding")
    return plain:sub(1, #plain - padding)
end
return Crypto
