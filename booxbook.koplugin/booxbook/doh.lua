local ltn12 = require("ltn12")
local socket = require("socket")

local Dns = {}
local cache = {}
local DOH_HOST = "cloudflare-dns.com"
local DOH_IP = "1.1.1.1"
local DOH_MAX_BODY = 64 * 1024
local TLS_TIMEOUT = 60

local function dnsNameMatches(pattern, host)
    pattern, host = tostring(pattern or ""):lower(), tostring(host or ""):lower()
    if pattern:find("\0", 1, true) or not pattern:match("^[%w%.%-%*]+$")
        or not host:match("^[%w%.%-]+$") then return false end
    if pattern == host then return true end
    local suffix = pattern:match("^%*%.(.+)$")
    if not suffix or suffix:find("*", 1, true) then return false end
    local label = host:match("^([^.]+)%." .. suffix:gsub("([^%w])", "%%%1") .. "$")
    return label ~= nil
end

function Dns.certificateMatchesHost(cert, host)
    local ok, extensions = pcall(cert.extensions, cert)
    if not ok or type(extensions) ~= "table" then return false end
    for _, extension in pairs(extensions) do
        if type(extension) == "table" and type(extension.dNSName) == "table" then
            for _, name in ipairs(extension.dNSName) do
                if dnsNameMatches(name, host) then return true end
            end
        end
    end
    return false
end

local function tlsSocket(host, port, connect_host, params, verify_host)
    local ssl = require("ssl")
    local raw, wrapped
    local ok, result = pcall(function()
        raw = assert(socket.tcp())
        raw:settimeout(TLS_TIMEOUT)
        assert(raw:connect(connect_host, port))
        wrapped = assert(ssl.wrap(raw, params))
        wrapped:sni(host)
        wrapped:settimeout(TLS_TIMEOUT)
        assert(wrapped:dohandshake())
        if verify_host then
            assert(Dns.certificateMatchesHost(assert(wrapped:getpeercertificate()), host),
                "TLS hostname mismatch")
        end
        return wrapped
    end)
    if ok then return result end
    local closing = wrapped or raw
    if closing then pcall(closing.close, closing) end
    return nil, result
end

local function register(conn)
    local methods = getmetatable(conn.sock).__index
    for name, method in pairs(methods) do
        if type(method) == "function" then
            conn[name] = function(self, ...)
                return method(self.sock, ...)
            end
        end
    end
end

local function connector(resolve, fallback, cafile)
    return function()
        local conn = { timeout = TLS_TIMEOUT }
        function conn:settimeout(timeout)
            self.timeout = timeout or TLS_TIMEOUT
            return 1
        end
        function conn:connect(host, port)
            local params = {
                mode = "client",
                protocol = "any",
                options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
                verify = cafile and "peer" or "none",
                cafile = cafile,
            }
            local addresses = resolve(host)
            local last_error
            local function tryAddresses(items)
                for _, address in ipairs(items) do
                    local result, err = tlsSocket(host, port, address, params, cafile ~= nil)
                    if result then
                        self.sock = result
                        self.sock:settimeout(self.timeout)
                        register(self)
                        return 1
                    end
                    last_error = err
                end
            end
            if tryAddresses(addresses) then return 1 end
            if fallback then
                if tryAddresses(fallback(host)) then return 1 end
            end
            error(last_error or "connection failed")
        end
        return conn
    end
end

local function isIpv4(value)
    local count = 0
    for part in tostring(value or ""):gmatch("[^.]+") do
        local number = tonumber(part)
        if not number or number < 0 or number > 255 or tostring(number) ~= part then return false end
        count = count + 1
    end
    return count == 4
end

function Dns.parse(body, now)
    local ok, json = pcall(require, "json")
    if not ok then return nil end
    local decoded_ok, data = pcall(json.decode, body)
    if not decoded_ok or type(data) ~= "table" or data.Status ~= 0 then return nil end
    local addresses, ttl = {}, 3600
    local answers = type(data.Answer) == "table" and data.Answer or {}
    for _, answer in ipairs(answers) do
        if answer.type == 1 and isIpv4(answer.data) then
            addresses[#addresses + 1] = answer.data
            ttl = math.min(ttl, tonumber(answer.TTL) or ttl)
        end
    end
    if #addresses == 0 then return nil end
    return addresses, (now or os.time()) + math.max(60, math.min(ttl, 3600))
end

local bootstrapConnector = connector(function() return { DOH_IP } end)

local function escapeQuery(value)
    return (value:gsub("([^%w%.%-])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function resolveDoh(host)
    local now = os.time()
    local saved = cache[host]
    if saved and saved.expires > now then return saved.addresses end

    local chunks, received = {}, 0
    local http = require("socket.http")
    local _, code = http.request({
        url = "https://" .. DOH_HOST .. "/dns-query?name=" .. escapeQuery(host) .. "&type=A",
        headers = { accept = "application/dns-json" },
        sink = function(chunk, err)
            if chunk then
                received = received + #chunk
                if received > DOH_MAX_BODY then return nil, "DoH response too large" end
                chunks[#chunks + 1] = chunk
            end
            if err then return nil, err end
            return 1
        end,
        redirect = false,
        create = bootstrapConnector,
    })
    if code ~= 200 then return {} end
    local addresses, expires = Dns.parse(table.concat(chunks), now)
    if not addresses then return {} end
    cache[host] = { addresses = addresses, expires = expires }
    return addresses
end

function Dns.create(cafile)
    -- Prefer DoH so poisoned system DNS cannot silently lead to an ISP block page.
    return connector(resolveDoh, function(host) return { host } end, cafile)
end

return Dns
