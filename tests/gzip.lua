-- Run under KOReader/LuaJIT with its bundled zlib (or host ffi.loadlib shim).
local Gzip = require("booxbook.gzip")
local bytes = { 31,139,8,0,0,0,0,0,2,3,203,72,205,201,201,7,0,134,166,16,54,5,0,0,0 }
local packed = string.char(unpack(bytes))
assert(Gzip.decode(packed, 5) == "hello")
assert(not Gzip.decode(packed, 4))
assert(not Gzip.decode(packed:sub(1, -2), 100))
assert(not Gzip.decode(packed:sub(1, 17) .. string.rep('\0', 8), 100))
assert(not Gzip.decode(packed .. packed, 100))
print("Gzip size, truncation, CRC and trailing-data checks passed")
