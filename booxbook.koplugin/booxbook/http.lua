local ltn12 = require("ltn12")
local socket_http = require("socket.http")
local socket = require("socket")

local RateLimit = require("booxbook.rate_limit")
local Settings = require("booxbook.store.settings")
local Dns = require("booxbook.doh")

local Http = {
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36",
    MAX_BODY = 2 * 1024 * 1024,
    DEFAULT_TIMEOUT = 10,
    DEFAULT_MAXTIME = 30,
}

local function logger()
    local ok, mod = pcall(require, "logger")
    if ok then
        return mod
    end
    return {
        dbg = function() end,
        info = function() end,
        warn = function() end,
        err = function() end,
    }
end

function Http.parseSetCookie(header)
    local cookies = {}
    if header == nil then
        return cookies
    end
    local chunks = {}
    if type(header) == "table" then
        for _, item in ipairs(header) do
            chunks[#chunks + 1] = item
        end
    else
        chunks[1] = tostring(header)
    end
    for _, chunk in ipairs(chunks) do
        local pair = chunk:match("^([^;]+)")
        if pair then
            local name, value = pair:match("^%s*([^=]+)%s*=%s*(.*)$")
            if name and name ~= "" then
                cookies[name] = value
            end
        end
    end
    return cookies
end

function Http.cookieHeader(cookies)
    if type(cookies) == "string" and cookies ~= "" then
        return cookies
    end
    if type(cookies) ~= "table" then
        return nil
    end
    local parts = {}
    for name, value in pairs(cookies) do
        parts[#parts + 1] = name .. "=" .. tostring(value)
    end
    table.sort(parts)
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "; ")
end

function Http.mergeCookies(a, b)
    local out = {}
    if type(a) == "string" and a ~= "" then
        for name, value in a:gmatch("([^=;%s]+)%s*=%s*([^;]*)") do
            out[name] = value
        end
    elseif type(a) == "table" then
        for k, v in pairs(a) do
            out[k] = v
        end
    end
    if type(b) == "table" then
        for k, v in pairs(b) do
            out[k] = v
        end
    end
    return out
end

local function headerKey(value)
    return string.lower(tostring(value or ""))
end

local function redactHeaders(headers)
    local copy = {}
    if type(headers) ~= "table" then
        return copy
    end
    for k, v in pairs(headers) do
        local key = headerKey(k)
        if key == "cookie" or key == "authorization" or key == "set-cookie" then
            copy[k] = "[redacted]"
        else
            copy[k] = v
        end
    end
    return copy
end

local function setTimeout(timeout, maxtime)
    local ok, socketutil = pcall(require, "socketutil")
    if ok and socketutil.set_timeout then
        socketutil:set_timeout(timeout or Http.DEFAULT_TIMEOUT, maxtime or Http.DEFAULT_MAXTIME)
        return socketutil
    end
    return nil
end

local function resetTimeout(socketutil)
    if socketutil and socketutil.reset_timeout then
        socketutil:reset_timeout()
    end
end

local function isTimeout(code)
    if code == "timeout" or code == "wantread" or code == "wantwrite" then
        return true
    end
    local ok, socketutil = pcall(require, "socketutil")
    if ok and socketutil then
        if code == socketutil.TIMEOUT_CODE or code == socketutil.SSL_HANDSHAKE_CODE or code == socketutil.SINK_TIMEOUT_CODE then
            return true
        end
    end
    return false
end

local function requestOnce(opts)
    local chunks = {}
    local received = 0
    local headers = {}
    for k, v in pairs(opts.headers or {}) do
        headers[headerKey(k)] = v
    end
    headers["user-agent"] = headers["user-agent"] or Http.USER_AGENT
    headers["accept"] = headers["accept"] or "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8"
    local cookie = Http.cookieHeader(opts.cookies) or headers.cookie
    local host = (opts.url:match("^https?://([^/:?#]+)") or ""):lower()
    if host == "vnexpress.net" or host:match("%.vnexpress%.net$") then
        -- Presentation cookies, not login cookies: Android variants can return empty RSS.
        -- Reference: Yuneko-dev/Nekori-plugins commit c63f848 (desktop compatibility).
        cookie = Http.cookieHeader(Http.mergeCookies(cookie, { device_env = "4", device_env_real = "4" }))
    end
    if cookie then
        headers["cookie"] = cookie
    end
    if opts.referer then
        headers["referer"] = opts.referer
    end

    local method = string.upper(opts.method or "GET")
    local body = opts.body or ""
    if method ~= "GET" and method ~= "HEAD" then
        headers["content-type"] = headers["content-type"] or "application/x-www-form-urlencoded"
        headers["content-length"] = tostring(#body)
    end

    logger().dbg("BooxBook HTTP", method, opts.url, redactHeaders(headers))

    local max_body = opts.max_body or Http.MAX_BODY
    local dest_file = opts.dest_file
    local fh, fh_err
    if dest_file then
        fh, fh_err = io.open(dest_file, "wb")
        if not fh then
            return nil, fh_err or "cannot write", nil, nil
        end
    end
    local function closeDest(keep)
        local closed, close_err = true, nil
        if fh then
            local called, result, err = pcall(fh.close, fh)
            closed, close_err = called and result, called and err or result
            fh = nil
        end
        if dest_file and (not keep or not closed) then
            os.remove(dest_file)
        end
        return closed, close_err
    end

    local socketutil = setTimeout(opts.timeout, opts.maxtime)
    local request = {
        url = opts.url,
        method = method,
        headers = headers,
        sink = function(chunk, err)
            if chunk then
                received = received + #chunk
                if received > max_body then return nil, "body too large" end
                if fh then
                    local written, write_err = fh:write(chunk)
                    if not written then return nil, write_err or "write failed" end
                else
                    chunks[#chunks + 1] = chunk
                end
            end
            if err then return nil, err end
            return 1
        end,
        redirect = false,
    }
    if opts.url:match("^https://") then
        -- KOReader changes cwd to its runtime directory; DataStorage points to
        -- external user data on Android, where the bundled CA file does not live.
        local cafile = opts.verify_tls and "data/ca-bundle.crt" or nil
        request.create = Dns.create(cafile)
    end
    if method ~= "GET" and method ~= "HEAD" then
        request.source = ltn12.source.string(body)
    end

    local ok, code, response_headers, status = pcall(function()
        return socket.skip(1, socket_http.request(request))
    end)
    resetTimeout(socketutil)

    if not ok then
        closeDest(false)
        return nil, tostring(code), nil, nil
    end

    local payload = dest_file and "" or table.concat(chunks)
    if received > max_body then
        closeDest(false)
        return nil, "body too large", response_headers, dest_file and "" or payload:sub(1, max_body)
    end
    -- Redirect hops reopen dest_file with "wb"; keep the path. Drop 4xx/5xx files.
    local keep = type(code) == "number" and code >= 200 and code < 400
    local closed, close_err = closeDest(keep)
    if not closed then return nil, close_err or "file close failed", response_headers, nil end
    return code, status, response_headers, payload
end

local function headerGet(headers, name)
    if type(headers) ~= "table" then
        return nil
    end
    local want = string.lower(name)
    for key, value in pairs(headers) do
        if string.lower(tostring(key)) == want then
            if type(value) == "table" then
                return value[1]
            end
            return value
        end
    end
    return nil
end

function Http.resolveUrl(base, location)
    if type(location) ~= "string" or location == "" then
        return nil
    end
    if location:match("^https?://") then
        return location
    end
    local scheme, host, path = base:match("^(https?)://([^/]+)(.*)$")
    if not scheme then
        return location
    end
    if location:sub(1, 2) == "//" then
        return scheme .. ":" .. location
    end
    if location:sub(1, 1) == "/" then
        return scheme .. "://" .. host .. location
    end
    path = path:gsub("[?#].*$", "")
    if path == "" then path = "/" end
    path = path:gsub("[^/]*$", "")
    return scheme .. "://" .. host .. path .. location
end

function Http.sameOrigin(a, b)
    return RateLimit.hostFromUrl(a) == RateLimit.hostFromUrl(b)
end

function Http.request(opts)
    opts = opts or {}
    assert(opts.url, "url required")
    local url = opts.url
    local method = opts.method or "GET"
    local cookies = opts.cookies
    local hops = 0
    local delay_ms = opts.delay_ms or Settings.delayMs()
    local request_headers = {}
    for key, value in pairs(opts.headers or {}) do request_headers[key] = value end

    local attempts = 0
    local max_tries = 3
    local last_err
    while attempts < max_tries do
        if opts.verify_tls and not url:match("^https://") then
            return false, "verified TLS requires HTTPS"
        end
        if opts.allow_url and not opts.allow_url(url) then
            return false, "URL not allowed"
        end
        attempts = attempts + 1
        RateLimit.wait(RateLimit.hostFromUrl(url), delay_ms)
        local code, status, headers, body = requestOnce({
            url = url,
            method = method,
            headers = request_headers,
            cookies = cookies,
            referer = opts.referer,
            body = opts.body,
            timeout = opts.timeout,
            maxtime = opts.maxtime,
            dest_file = opts.dest_file,
            max_body = opts.max_body,
            verify_tls = opts.verify_tls,
        })
        if type(code) == "number" then
            if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
                local next_url = Http.resolveUrl(url, headerGet(headers, "location"))
                hops = hops + 1
                if not next_url or hops > 5 then
                    return false, code, body, headers
                end
                if not Http.sameOrigin(url, next_url) then
                    cookies = nil
                    for key in pairs(request_headers) do
                        if headerKey(key) == "cookie" or headerKey(key) == "authorization" then
                            request_headers[key] = nil
                        end
                    end
                end
                url = next_url
                if code == 303 then
                    method = "GET"
                end
                attempts = attempts - 1
            elseif code == 429 then
                -- A different UA is not permission to retry a rate-limited request.
                return false, code, body, headers
            elseif code == 403 then
                if attempts == 1 then
                    RateLimit.wait(RateLimit.hostFromUrl(url), delay_ms * 2)
                else
                    return false, code, body, headers
                end
            elseif code >= 200 and code < 300 then
                local jar = Http.parseSetCookie(headerGet(headers, "set-cookie"))
                return true, code, body, headers, jar
            else
                return false, code, body, headers
            end
        elseif isTimeout(code) or isTimeout(status) then
            last_err = code or status or "timeout"
            if attempts >= max_tries then
                return false, last_err, nil, nil
            end
        else
            return false, code or status or "request failed", body, headers
        end
    end
    return false, last_err or "request failed", nil, nil
end

function Http.get(url, opts)
    opts = opts or {}
    opts.url = url
    opts.method = "GET"
    return Http.request(opts)
end

function Http.post(url, body, opts)
    opts = opts or {}
    opts.url = url
    opts.method = "POST"
    opts.body = body
    return Http.request(opts)
end

function Http.put(url, body, opts)
    opts = opts or {}
    opts.url = url
    opts.method = "PUT"
    opts.body = body
    return Http.request(opts)
end

function Http.downloadToFile(url, dest, opts)
    local request = {}
    for key, value in pairs(opts or {}) do
        request[key] = value
    end
    request.url = url
    request.method = "GET"
    request.dest_file = dest
    request.max_body = request.max_body or (30 * 1024 * 1024)
    request.timeout = request.timeout or 60
    request.maxtime = request.maxtime or 180
    local ok, code, body, headers, jar = Http.request(request)
    if not ok and dest then
        os.remove(dest)
    end
    return ok, code, body, headers, jar
end

return Http
