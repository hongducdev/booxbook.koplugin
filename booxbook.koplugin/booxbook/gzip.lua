local Gzip = {}
local initialized = false

-- Wattpad storytext sends gzip even with Accept-Encoding: identity.
-- KOReader bundles zlib; its Lua wrapper exposes only zlib-format uncompress.
function Gzip.decode(body, limit)
    local ok, result = pcall(function()
        local ffi = require("ffi")
        if not initialized then
            ffi.cdef[[
                typedef struct {
                    const unsigned char *next_in;
                    unsigned int avail_in;
                    unsigned long total_in;
                    unsigned char *next_out;
                    unsigned int avail_out;
                    unsigned long total_out;
                    char *msg;
                    void *state;
                    void *(*zalloc)(void *, unsigned int, unsigned int);
                    void (*zfree)(void *, void *);
                    void *opaque;
                    int data_type;
                    unsigned long adler;
                    unsigned long reserved;
                } booxbook_z_stream;
                const char *zlibVersion(void);
                int inflateInit2_(booxbook_z_stream *, int, const char *, int);
                int inflate(booxbook_z_stream *, int);
                int inflateEnd(booxbook_z_stream *);
            ]]
            initialized = true
        end
        local lib = ffi.loadlib("z", 1)
        local stream = ffi.new("booxbook_z_stream[1]")
        local output = ffi.new("unsigned char[?]", limit + 1)
        stream[0].next_in, stream[0].avail_in = body, #body
        stream[0].next_out, stream[0].avail_out = output, limit + 1
        assert(lib.inflateInit2_(stream, 31, lib.zlibVersion(), ffi.sizeof(stream[0])) == 0)
        local status = lib.inflate(stream, 4) -- Z_FINISH; validates gzip CRC and length.
        local size, remaining = tonumber(stream[0].total_out), stream[0].avail_in
        lib.inflateEnd(stream)
        assert(status == 1 and size <= limit and remaining == 0)
        return ffi.string(output, size)
    end)
    if ok then return result end
    return nil
end

return Gzip
