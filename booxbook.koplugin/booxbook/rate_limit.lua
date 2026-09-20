local RateLimit = {
    default_delay_ms = 1200,
    last = {},
}

local function nowSeconds()
    local socket = package.loaded.socket
    if not socket then
        local ok, mod = pcall(require, "socket")
        if ok then
            socket = mod
        end
    end
    if socket and socket.gettime then
        return socket.gettime()
    end
    return os.time()
end

local function sleepSeconds(seconds)
    if seconds <= 0 then
        return
    end
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    if ok_ffi and ffiutil and ffiutil.sleep then
        ffiutil.sleep(seconds)
        return
    end
    local socket = package.loaded.socket
    if not socket then
        local ok, mod = pcall(require, "socket")
        if ok then
            socket = mod
        end
    end
    if socket and socket.sleep then
        socket.sleep(seconds)
        return
    end
    -- No blocking sleep available: skip rather than spin the CPU / freeze e-ink UI.
end

function RateLimit.hostFromUrl(url)
    if type(url) ~= "string" then
        return "default"
    end
    return url:match("^https?://([^/]+)") or "default"
end

-- `max_ms` caps how long we are allowed to sleep (the caller's remaining time
-- budget). Returns false when the cap was hit, so the caller can abort instead
-- of firing a request too early or blocking the UI longer.
function RateLimit.wait(host, delay_ms, max_ms)
    host = host or "default"
    delay_ms = delay_ms or RateLimit.default_delay_ms
    local delay = delay_ms / 1000
    local last = RateLimit.last[host]
    if last then
        local elapsed = nowSeconds() - last
        if elapsed < delay then
            local need = delay - elapsed
            if max_ms and max_ms < need * 1000 then
                sleepSeconds(math.max(0, max_ms) / 1000)
                RateLimit.last[host] = nowSeconds()
                return false
            end
            sleepSeconds(need)
        end
    end
    RateLimit.last[host] = nowSeconds()
    return true
end

function RateLimit.reset()
    RateLimit.last = {}
end

return RateLimit
