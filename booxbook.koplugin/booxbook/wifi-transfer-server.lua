local socket = require("socket")
local Upload = require("booxbook.wifi-upload")
local page = require("booxbook.wifi-transfer-page")
local _ = require("gettext")
local Server = {}
Server.__index = Server

-- Interface names that never carry phone traffic: VPN/overlay tunnels and cellular
-- links. Deprioritising them keeps a working Wi-Fi address on screen while a VPN is up.
local NON_LAN_INTERFACES = { "^tun", "^utun", "^tap", "^ppp", "^wg", "^zt", "^tailscale",
    "^vpn", "^ip6tnl", "^sit%d", "^rmnet", "^ccmni", "^wwan", "^pdp", "^svnet" }
local LAN_INTERFACES = { "^wlan", "^wifi", "^eth", "^en", "^ap%d", "^br%-", "^bridge" }

-- Another application holding 8080 (HTTP Inspector, a proxy, ...) must not end the
-- session, so the next free port is used and shown on screen.
Server.PORT_CANDIDATES = { 8080, 8081, 8082, 8083, 8084, 8085, 8086, 8087, 8088 }

Server.isLanAddress = Upload.isLanAddress

local function matchesAny(name, patterns)
    if type(name) ~= "string" then return false end
    for _, pattern in ipairs(patterns) do
        if name:match(pattern) then return true end
    end
    return false
end

local function interfacePenalty(name)
    if matchesAny(name, NON_LAN_INTERFACES) then return 2 end
    if matchesAny(name, LAN_INTERFACES) then return 0 end
    return 1
end

-- A link-local first-hop address works but is rarely the one the phone should type,
-- so a routable LAN address always wins, and a public one (cellular WAN) loses.
local function addressPenalty(address)
    if address:match("^169%.254%.") then return 1 end
    if Upload.isLanAddress(address) then return 0 end
    return 2
end

-- Best address first: LAN interfaces, the interface KOReader reports as active, other
-- addresses, then tunnels/cellular.
local function rankKey(entry, preferred, index)
    return { interfacePenalty(entry.name),
        (preferred and entry.name == preferred) and 0 or 1,
        addressPenalty(entry.address),
        index }
end

local function keyLess(left, right)
    for position = 1, #left do
        if left[position] ~= right[position] then return left[position] < right[position] end
    end
    return false
end

function Server.rankAddresses(entries, preferred)
    local ranked = {}
    for index, raw in ipairs(entries or {}) do
        local name, address
        if type(raw) == "table" then name, address = raw.name, raw.address else address = raw end
        if type(address) == "string" and address:match("^%d+%.%d+%.%d+%.%d+$") then
            local entry = { name = name, address = address }
            ranked[#ranked + 1] = { entry = entry, key = rankKey(entry, preferred, index) }
        end
    end
    table.sort(ranked, function(left, right) return keyLess(left.key, right.key) end)
    local ordered = {}
    for index = 1, #ranked do ordered[index] = ranked[index].entry end
    return ordered
end

function Server.pickAddress(entries, preferred)
    local ordered = Server.rankAddresses(entries, preferred)
    return ordered[1] and ordered[1].address
end

function Server.addressList(entries, preferred)
    local list = {}
    for _, entry in ipairs(Server.rankAddresses(entries, preferred)) do
        list[#list + 1] = entry.address
        if #list >= 8 then break end
    end
    return list
end

local function interfaceAddresses()
    local ok, entries = pcall(function()
        local ffi = require("ffi")
        require("ffi/posix_h")
        local C, result = ffi.C, {}
        local head = ffi.new("struct ifaddrs *[1]")
        if C.getifaddrs(head) ~= 0 then return result end
        local current = head[0]
        while current ~= nil do
            if current.ifa_addr ~= nil and current.ifa_addr.sa_family == C.AF_INET then
                local host = ffi.new("char[?]", C.NI_MAXHOST)
                if C.getnameinfo(current.ifa_addr, ffi.sizeof("struct sockaddr_in"),
                    host, C.NI_MAXHOST, nil, 0, C.NI_NUMERICHOST) == 0 then
                    local address = ffi.string(host)
                    if not address:match("^127%.") then
                        result[#result + 1] = { name=ffi.string(current.ifa_name), address=address }
                    end
                end
            end
            current = current.ifa_next
        end
        C.freeifaddrs(head[0])
        return result
    end)
    return ok and entries or {}
end

local function probeAddress()
    -- Ask the routing table only: no DNS lookup or packet is sent.
    local probe = socket.udp()
    if not probe then return end
    local ok = probe:setpeername("203.0.113.1", 9)
    local address = ok and probe:getsockname()
    probe:close()
    if address and address ~= "0.0.0.0" and not address:match("^127%.") then return address end
end

local function localAddressEntries()
    local entries, seen = {}, {}
    for _, entry in ipairs(interfaceAddresses()) do
        if not seen[entry.address] then
            seen[entry.address] = true
            entries[#entries + 1] = entry
        end
    end
    local probed = probeAddress()
    -- The routing table answers with the default-route address, e.g. a VPN or a cellular
    -- link on a tablet without Wi-Fi. It ranks after every LAN-named interface.
    if probed and not seen[probed] then entries[#entries + 1] = { address = probed } end
    return entries
end

function Server.localAddress(preferred)
    return Server.pickAddress(localAddressEntries(), preferred)
end

-- Every address the phone may use, best first. Shown on screen so a user whose first
-- address is unreachable (VPN, second interface) can try the next one.
function Server.localAddresses(preferred)
    return Server.addressList(localAddressEntries(), preferred)
end

function Server.sessionToken()
    local file = io.open("/dev/urandom", "rb")
    if not file then return end
    for _ = 1, 16 do
        local bytes = file:read(3)
        if not bytes or #bytes ~= 3 then break end
        local a, b, c = bytes:byte(1, 3)
        local value = a * 65536 + b * 256 + c
        -- Reject the uneven tail so every six-digit code has equal probability.
        if value < 16000000 then
            file:close()
            return string.format("%06d", value % 1000000)
        end
    end
    file:close()
end

function Server.new(dir, addresses, token, port)
    if type(addresses) == "string" then addresses = { addresses } end
    local list, seen = {}, {}
    for _, raw in ipairs(type(addresses) == "table" and addresses or {}) do
        local address = type(raw) == "table" and raw.address or raw
        if type(address) == "string" and address:match("^%d+%.%d+%.%d+%.%d+$") and not seen[address] then
            seen[address] = true
            list[#list + 1] = address
        end
    end
    if #list == 0 or type(token) ~= "string" or not token:match("^%d%d%d%d%d%d$") then
        return nil, _("Không lấy được địa chỉ Wi-Fi hoặc mã phiên an toàn.")
    end
    local listener, last_error
    for _, candidate in ipairs(port and { port } or Server.PORT_CANDIDATES) do
        -- Listen on every interface: the phone may reach the device through an address
        -- we did not pick, and the Host header still has to match this server.
        local bound, err = socket.bind("0.0.0.0", candidate, 4)
        if bound then
            listener = bound
            break
        end
        last_error = err
    end
    if not listener then return nil, _("Không mở được cổng nhận sách:") .. " " .. tostring(last_error) end
    listener:settimeout(0)
    local _, actual_port = listener:getsockname()
    actual_port = tonumber(actual_port) or tonumber(port) or Server.PORT_CANDIDATES[1]
    local authority = list[1] .. ":" .. tostring(actual_port)
    return setmetatable({ listener=listener, dir=dir, token=token, addresses=list,
        port=actual_port, authority=authority, url="http://" .. authority .. "/",
        clients={}, serial=0, received=0, failed_auth={},
        -- Diagnostics shown on the device: a phone that never appears here never
        -- reached this process at all.
        connections=0, requests=0, rejected=0, https_attempts=0, recent_hosts={} }, Server)
end

function Server:noteRequest(host)
    if type(host) ~= "string" or host == "" then return end
    for _, value in ipairs(self.recent_hosts) do
        if value == host then return end
    end
    self.recent_hosts[#self.recent_hosts + 1] = host
    if #self.recent_hosts > 3 then table.remove(self.recent_hosts, 1) end
end

local function close(client)
    if client.request then Upload.abort(client.request) end
    if client.output_file then client.output_file:close(); client.output_file = nil end
    client.socket:close()
    client.closed = true
end

local function isRefusal(code)
    -- 404/500 answer a broken client, not an intruder, and would only add noise to the
    -- diagnostics screen.
    return code ~= 404 and code ~= 500 and code >= 400
end

local function respond(self, client, code, body, html)
    if client.request then Upload.abort(client.request) end
    if isRefusal(code) then self.rejected = self.rejected + 1 end
    client.output = "HTTP/1.1 " .. code .. " Result\r\nContent-Type: "
        .. (html and "text/html" or "text/plain") .. "; charset=utf-8\r\nContent-Length: " .. #body
        .. "\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer"
        .. "\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; "
        .. "script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; "
        .. "frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\n\r\n" .. body
    client.sent = 0
    client.buffer = nil
end

local function libraryRoot(received_dir)
    local ok_settings, Settings = pcall(require, "booxbook.store.settings")
    if ok_settings and Settings and Settings.downloadDir then
        local ok_dir, dir = pcall(Settings.downloadDir)
        if ok_dir and type(dir) == "string" and dir ~= "" then return dir end
    end
    if type(received_dir) == "string" then
        return received_dir:match("^(.*)/received$") or received_dir
    end
    return "."
end

local function atom(client, body)
    client.output = "HTTP/1.1 200 Result\r\nContent-Type: application/atom+xml; charset=utf-8\r\nContent-Length: "
        .. #body .. "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n" .. body
    client.sent = 0
    client.buffer = nil
end

local function fileResponse(client, file, size, mime)
    client.output = "HTTP/1.1 200 Result\r\nContent-Type: " .. mime .. "\r\nContent-Length: "
        .. size .. "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
    client.output_file = file
    client.sent = 0
    client.buffer = nil
end

local function queueOutputFileChunk(client)
    if not client.output_file then return false end
    local chunk = client.output_file:read(65536)
    if chunk and #chunk > 0 then
        client.output = chunk
        client.sent = 0
        return true
    end
    client.output_file:close()
    client.output_file = nil
    close(client)
    return false
end


function Server:consume(client, chunk)
    if not client.request then
        client.buffer = client.buffer .. chunk
        if client.buffer:byte(1) == 0x16 and client.buffer:byte(2) == 0x03 then
            -- A browser that upgraded the address to HTTPS speaks TLS to this plain port.
            self.https_attempts = self.https_attempts + 1
            return respond(self, client, 400,
                _("Hãy gõ http:// trước địa chỉ. Trình duyệt đang thử HTTPS."))
        end
        local boundary = client.buffer:find("\r\n\r\n", 1, true)
        if not boundary then
            if #client.buffer > 8192 then respond(self, client, 431, _("Header quá dài.")) end
            return
        end
        if boundary > 8192 then return respond(self, client, 431, _("Header quá dài.")) end
        local request, code, message = Upload.headers(client.buffer:sub(1, boundary + 3), self.authority, self.token)
        if request then
            self.requests = self.requests + 1
            self:noteRequest(request.host)
            if request.page then return respond(self, client, 200, page, true) end
            if request.opds then
                local ok_opds, Opds = pcall(require, "booxbook.opds")
                if ok_opds and Opds and Opds.fullCatalog then
                    local ok_cat, xml = pcall(Opds.fullCatalog, libraryRoot(self.dir), "/opds")
                    if ok_cat and type(xml) == "string" then
                        atom(client, xml)
                        return
                    end
                end
                return respond(self, client, 500, _("Không tạo được OPDS."))
            end
            if request.opds_file then
                local ok_opds, Opds = pcall(require, "booxbook.opds")
                local mime = ok_opds and Opds and Opds.mimeType and Opds.mimeType(request.opds_file) or nil
                if not mime then return respond(self, client, 404, _("Không tìm thấy.")) end
                local root = libraryRoot(self.dir)
                local root_norm = (root:gsub("\\", "/"))
                local path = root_norm .. "/" .. request.opds_file
                local ffiUtil = package.loaded["ffi/util"]
                if not ffiUtil then pcall(function() ffiUtil = require("ffi/util") end) end
                local real_root = (ffiUtil and ffiUtil.realpath and ffiUtil.realpath(root_norm) or root_norm):gsub("\\", "/")
                local real_path = (ffiUtil and ffiUtil.realpath and ffiUtil.realpath(path) or path):gsub("\\", "/")
                if not real_path or real_path:sub(1, #real_root + 1) ~= real_root .. "/" then
                    return respond(self, client, 404, _("Không tìm thấy."))
                end
                local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
                if not ok_lfs or not lfs then pcall(function() lfs = require("lfs") end) end
                if lfs and lfs.symlinkattributes then
                    local sym = lfs.symlinkattributes(real_path, "mode")
                    if sym == "link" then
                        return respond(self, client, 404, _("Không tìm thấy."))
                    end
                end
                local file = io.open(real_path, "rb")
                if not file then return respond(self, client, 404, _("Không tìm thấy.")) end
                local size = file:seek("end")
                file:seek("set", 0)
                if not size or size < 1 or size > Upload.MAX_BYTES then
                    file:close()
                    return respond(self, client, 413, _("File quá lớn cho OPDS, hãy copy qua USB."))
                end
                fileResponse(client, file, size, mime)
                return
            end
            if request.queue then
                client.request = request
                client.request.queue_body = ""
                chunk = client.buffer:sub(boundary + 4)
                client.buffer = nil
                if chunk ~= "" then
                    -- Fall through to queue accumulation below.
                    self:consume(client, "")
                    if not client.closed then self:consume(client, chunk) end
                end
                return
            end
        end
        local peer = client.peer or "unknown"
        local failures = self.failed_auth[peer] or 0
        if failures >= 5 then
            return respond(self, client, 429, _("Nhập sai mã 5 lần. Hãy đóng rồi mở lại phiên nhận trên máy đọc sách."))
        end
        if code == 401 then self.failed_auth[peer] = failures + 1 end
        if not request then return respond(self, client, code, message) end
        self.failed_auth[peer] = nil
        client.request = request
        local ok
        ok, code, message = Upload.begin(request, self.dir, self.token .. "-" .. client.id)
        if not ok then return respond(self, client, code, message) end
        chunk = client.buffer:sub(boundary + 4)
        client.buffer = nil
    end
    if client.request.queue then
        client.request.queue_body = (client.request.queue_body or "") .. (chunk or "")
        if #client.request.queue_body > client.request.remaining then
            return respond(self, client, 413, _("URL quá dài."))
        end
        if #client.request.queue_body >= client.request.remaining then
            local ok_opds, Opds = pcall(require, "booxbook.opds")
            local url, err
            if ok_opds and Opds then url, err = Opds.normalizeQueueUrl(client.request.queue_body) end
            if not url then return respond(self, client, 400, _("URL không hợp lệ.")) end
            local queue_path = self.dir .. "/queue.txt"
            local file = io.open(queue_path, "ab")
            if not file then return respond(self, client, 500, _("Không ghi được hàng đợi.")) end
            file:write(url .. "\n")
            file:close()
            return respond(self, client, 201, _("Đã thêm vào hàng đợi."))
        end
        return
    end
    local ok, result = Upload.write(client.request, chunk)
    if not ok then return respond(self, client, 500, result) end
    if result == "complete" then
        self.received = self.received + 1
        self.last_name = client.request.name
        if self.on_received then pcall(self.on_received, self.last_name) end
        respond(self, client, 201, _("Đã lưu vào thư viện."))
    end
end

function Server:step(client)
    local now = socket.gettime()
    if now - client.active > 30 or now - client.started > 1800 then return close(client) end
    if client.output then
        local sent, err, partial = client.socket:send(client.output, client.sent + 1)
        local count = sent or partial or client.sent
        if count > client.sent then client.active = now end
        client.sent = count
        if count >= #client.output then
            if client.output_file then queueOutputFileChunk(client) else close(client) end
        elseif err and err ~= "timeout" then close(client) end
        return
    end
    -- ponytail: at most 1 MiB/client/tick; use socket readiness polling if throughput becomes limiting.
    for _ = 1, 16 do
        local chunk, err, partial = client.socket:receive(65536)
        chunk = chunk or partial or ""
        if #chunk > 0 then
            client.active = now
            self:consume(client, chunk)
        end
        if client.output then return end
        if err and err ~= "timeout" then return close(client) end
        if err then return end
    end
end

function Server:poll()
    if not self.listener then return end
    for i = #self.clients, 1, -1 do
        local client = self.clients[i]
        local ok = pcall(self.step, self, client)
        if not ok then close(client) end
        if client.closed then table.remove(self.clients, i) end
    end
    -- Bound open sockets even if browsers preconnect or clients stall.
    for _ = 1, 4 do
        local peer = self.listener:accept()
        if not peer then break end
        peer:settimeout(0)
        local address = peer:getpeername()
        if not Upload.isLocalPeer(address, self.addresses) then
            -- Reachable on every interface, so a remote source is refused before it can
            -- occupy one of the few client slots.
            self.rejected = self.rejected + 1
            peer:close()
        elseif #self.clients >= 4 then
            peer:close()
        else
            self.serial = self.serial + 1
            self.connections = self.connections + 1
            local now = socket.gettime()
            self.clients[#self.clients + 1] = { socket=peer, buffer="", id=self.serial,
                peer=address or "unknown", active=now, started=now }
        end
    end
    -- Callers poll faster only while a device is connected.
    return #self.clients
end

function Server:stop()
    for _, client in ipairs(self.clients) do close(client) end
    self.clients = {}
    if self.listener then self.listener:close(); self.listener = nil end
end

return Server
