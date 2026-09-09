local socket = require("socket")
local Upload = require("booxbook.wifi-upload")
local page = require("booxbook.wifi-transfer-page")
local _ = require("gettext")
local Server = {}
Server.__index = Server

function Server.pickAddress(entries, preferred)
    for _, entry in ipairs(entries) do
        if entry.name == preferred then return entry.address end
    end
    for _, pattern in ipairs({ "^wlan%d*$", "^wifi%d*$", "^eth%d*$", "^en%d*$" }) do
        for _, entry in ipairs(entries) do
            if entry.name:match(pattern) then return entry.address end
        end
    end
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

function Server.localAddress(preferred)
    local address = Server.pickAddress(interfaceAddresses(), preferred)
    if address then return address end
    -- Ask the routing table only: no DNS lookup or packet is sent.
    local probe = socket.udp()
    if not probe then return end
    local ok = probe:setpeername("203.0.113.1", 9)
    address = ok and probe:getsockname()
    probe:close()
    if address and address ~= "0.0.0.0" and not address:match("^127%.") then return address end
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

function Server.new(dir, address, token, port)
    if not address or type(token) ~= "string" or not token:match("^%d%d%d%d%d%d$") then
        return nil, _("Không lấy được địa chỉ Wi-Fi hoặc mã phiên an toàn.")
    end
    local listener, err = socket.bind(address, port or 8080, 4)
    if not listener then return nil, _("Không mở được cổng nhận sách:") .. " " .. tostring(err) end
    listener:settimeout(0)
    local _, actual_port = listener:getsockname()
    local authority = address .. ":" .. tostring(actual_port)
    return setmetatable({ listener=listener, dir=dir, token=token, authority=authority,
        url="http://" .. authority .. "/", clients={}, serial=0, received=0, failed_auth={} }, Server)
end

local function close(client)
    if client.request then Upload.abort(client.request) end
    client.socket:close()
    client.closed = true
end

local function respond(client, code, body, html)
    if client.request then Upload.abort(client.request) end
    client.output = "HTTP/1.1 " .. code .. " Result\r\nContent-Type: "
        .. (html and "text/html" or "text/plain") .. "; charset=utf-8\r\nContent-Length: " .. #body
        .. "\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer"
        .. "\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; "
        .. "script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; "
        .. "frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\n\r\n" .. body
    client.sent = 0
    client.buffer = nil
end

function Server:consume(client, chunk)
    if not client.request then
        client.buffer = client.buffer .. chunk
        local boundary = client.buffer:find("\r\n\r\n", 1, true)
        if not boundary then
            if #client.buffer > 8192 then respond(client, 431, _("Header quá dài.")) end
            return
        end
        if boundary > 8192 then return respond(client, 431, _("Header quá dài.")) end
        local request, code, message = Upload.headers(client.buffer:sub(1, boundary + 3), self.authority, self.token)
        if request and request.page then return respond(client, 200, page, true) end
        if request and request.opds then
            local ok_opds, Opds = pcall(require, "booxbook.opds")
            local files = {}
            if ok_opds and Opds then
                local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
                if ok_lfs and lfs and lfs.dir then
                    for name in lfs.dir(self.dir) do
                        if name ~= "." and name ~= ".." and Upload.safeFilename(name) then
                            files[#files + 1] = { name = name }
                        end
                    end
                end
                local ok_cat, xml = pcall(Opds.catalog, files, "/opds")
                if ok_cat and type(xml) == "string" then
                    client.output = "HTTP/1.1 200 Result\r\nContent-Type: application/atom+xml; charset=utf-8\r\nContent-Length: "
                        .. #xml .. "\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" .. xml
                    client.sent = 0
                    client.buffer = nil
                    return
                end
            end
            return respond(client, 500, _("Không tạo được OPDS."))
        end
        if request and request.opds_file then
            local path = self.dir .. "/" .. request.opds_file
            local file = io.open(path, "rb")
            if not file then return respond(client, 404, _("Không tìm thấy.")) end
            local size = file:seek("end")
            file:seek("set", 0)
            if not size or size < 1 or size > 32 * 1024 * 1024 then
                file:close()
                return respond(client, 413, _("File quá lớn cho OPDS, hãy copy qua USB."))
            end
            local body = file:read("*a") or ""
            file:close()
            client.output = "HTTP/1.1 200 Result\r\nContent-Type: application/octet-stream\r\nContent-Length: "
                .. #body .. "\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" .. body
            client.sent = 0
            client.buffer = nil
            return
        end
        if request and request.queue then
            client.request = request
            client.request.queue_body = ""
            chunk = client.buffer:sub(boundary + 4)
            client.buffer = nil
            if chunk ~= "" then
                -- Fall through to queue accumulation below.
                self:consume(client, "")
                if not client.closed then self:consume(client, chunk) end
                return
            end
            return
        end
        local peer = client.peer or "unknown"
        local failures = self.failed_auth[peer] or 0
        if failures >= 5 then
            return respond(client, 429, _("Nhập sai mã 5 lần. Hãy đóng rồi mở lại phiên nhận trên máy đọc sách."))
        end
        if code == 401 then self.failed_auth[peer] = failures + 1 end
        if not request then return respond(client, code, message) end
        self.failed_auth[peer] = nil
        client.request = request
        local ok
        ok, code, message = Upload.begin(request, self.dir, self.token .. "-" .. client.id)
        if not ok then return respond(client, code, message) end
        chunk = client.buffer:sub(boundary + 4)
        client.buffer = nil
    end
    if client.request.queue then
        client.request.queue_body = (client.request.queue_body or "") .. (chunk or "")
        if #client.request.queue_body > client.request.remaining then
            return respond(client, 413, _("URL quá dài."))
        end
        if #client.request.queue_body >= client.request.remaining then
            local ok_opds, Opds = pcall(require, "booxbook.opds")
            local url, err
            if ok_opds and Opds then url, err = Opds.normalizeQueueUrl(client.request.queue_body) end
            if not url then return respond(client, 400, _("URL không hợp lệ.")) end
            local queue_path = self.dir .. "/queue.txt"
            local file = io.open(queue_path, "ab")
            if not file then return respond(client, 500, _("Không ghi được hàng đợi.")) end
            file:write(url .. "\n")
            file:close()
            return respond(client, 201, _("Đã thêm vào hàng đợi."))
        end
        return
    end
    local ok, result = Upload.write(client.request, chunk)
    if not ok then return respond(client, 500, result) end
    if result == "complete" then
        self.received = self.received + 1
        self.last_name = client.request.name
        if self.on_received then pcall(self.on_received, self.last_name) end
        respond(client, 201, _("Đã lưu vào thư viện."))
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
        if count >= #client.output or (err and err ~= "timeout") then close(client) end
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
        if #self.clients >= 4 then peer:close()
        else
            peer:settimeout(0)
            self.serial = self.serial + 1
            local now = socket.gettime()
            local address = peer:getpeername()
            self.clients[#self.clients + 1] = { socket=peer, buffer="", id=self.serial,
                peer=address or "unknown", active=now, started=now }
        end
    end
end

function Server:stop()
    for _, client in ipairs(self.clients) do close(client) end
    self.clients = {}
    if self.listener then self.listener:close(); self.listener = nil end
end

return Server
