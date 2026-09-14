local names = { "libs/libkoreader-lfs", "gettext", "socket", "booxbook.wifi-upload",
    "booxbook.wifi-transfer-server", "booxbook.wifi-transfer-page", "booxbook.ui.wifi-transfer",
    "ui/uimanager", "ui/network/manager", "booxbook.ui.catalog", "booxbook.store.settings",
    "ui/widget/infomessage", "device", "ui/widget/qrmessage" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
local open, remove, rename = io.open, os.remove, os.rename
local paths = {}
local function mapped(path)
    if not path:match("^@wifi/") then return path end
    if not paths[path] then paths[path] = os.tmpname(); remove(paths[path]) end
    return paths[path]
end
io.open = function(path, mode) return open(mapped(path), mode) end
os.remove = function(path) return remove(mapped(path)) end
os.rename = function(a, b) return rename(mapped(a), mapped(b)) end
package.loaded["libs/libkoreader-lfs"] = { symlinkattributes=function(path)
    local f = open(mapped(path), "rb")
    if f then f:close(); return { mode="file" } end
end }
package.loaded.gettext = function(s) return s end
package.loaded["booxbook.wifi-upload"] = nil
local Upload = require("booxbook.wifi-upload")
local token = "012345"
local function headers(name, length, extra)
    return "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nX-BooxBook-Token: " .. token
        .. "\r\nX-File-Name: " .. name .. "\r\nContent-Length: " .. length .. "\r\n" .. (extra or "") .. "\r\n"
end
for _, bad in ipairs({ "../x.epub", "%2e%2e%2fx.pdf", "a%5cb.pdf", "a%00.pdf", ".a.pdf",
    "CON.txt", "a.lua", "a.pdf.", "%aZ.txt", "a%.txt", "a%0A.txt", "a:b.txt" }) do
    assert(not Upload.filename(bad), bad)
end
assert(Upload.filename("Ti%E1%BA%BFng%20Vi%E1%BB%87t.EPUB") == "Tiếng Việt.EPUB")
for _, name in ipairs({ "a.epub", "a.pdf", "a.fb2", "a.mobi", "a.azw", "a.azw3",
        "a.djvu", "a.djv", "a.txt", "a.rtf", "a.doc", "a.chm", "a.cbz", "a.cbr" }) do
    assert(Upload.safeFilename(name) == name, name)
end
assert(not Upload.safeFilename("a.mp4") and not Upload.safeFilename("../a.epub"))
for _, raw in ipairs({ headers("x.pdf", "0"), headers("x.pdf", "536870913"),
    headers("x.pdf", "-1"), headers("x.pdf", "1", "Content-Length: 1\r\n"),
    headers("x.pdf", "1", "Origin: http://evil.test\r\n"), headers("x.pdf", "1", "Transfer-Encoding: chunked\r\n"),
    headers("x.pdf", "1", "Bad\nHeader: yes\r\n"), headers("x.pdf", "1"):gsub(token, "wrong"),
    (headers("x.pdf", "1"):gsub("127.0.0.1", "evil.test")) }) do
    assert(not Upload.headers(raw, "127.0.0.1:8080", token), raw)
end
local request = assert(Upload.headers(headers("book.epub", "5"), "127.0.0.1:8080", token))
assert(Upload.begin(request, "@wifi", "1"))
assert(Upload.write(request, "a\0"))
local ok, complete = Upload.write(request, "bcd")
assert(ok and complete == "complete")
local f = assert(io.open("@wifi/book.epub", "rb")); assert(f:read("*a") == "a\0bcd"); f:close()
assert(not Upload.begin({ name="book.epub" }, "@wifi", "2"))
local partial = { name="partial.pdf", remaining=3 }
assert(Upload.begin(partial, "@wifi", "3")); assert(Upload.write(partial, "x")); Upload.abort(partial)
assert(not io.open(partial.temp, "rb") and not io.open(partial.path, "rb"))
local failed = { name="failed.pdf", remaining=1 }
assert(Upload.begin(failed, "@wifi", "4"))
local disk_file = failed.file
failed.file = { write=function() return nil end, close=function() disk_file:close() end }
assert(not Upload.write(failed, "x")); Upload.abort(failed)
assert(not io.open(failed.temp, "rb"))

-- Local-network classification drives the peer guard and address ranking.
assert(Upload.isLanAddress("192.168.1.5") == true, "private IPv4 is local")
assert(Upload.isLanAddress("10.8.0.2:5555") == true, "host with port still parses")
assert(Upload.isLanAddress("172.31.255.254") == true and Upload.isLanAddress("172.32.0.1") == false)
assert(Upload.isLanAddress("100.64.7.9") == true, "carrier NAT counts as local")
assert(Upload.isLanAddress("169.254.10.3") == true, "link local counts as local")
assert(Upload.isLanAddress("8.8.8.8") == false, "public IPv4 is remote")
assert(Upload.isLanAddress("unknown") == nil and Upload.isLanAddress(nil) == nil, "unclassified stays unknown")

-- Every address the user may type works on the server's own port; domain names and
-- other ports stay rejected so a rebinding page cannot borrow the device address.
local function get(path, host)
    return ("GET %s HTTP/1.1\r\nHost: %s\r\nAccept: text/html\r\n\r\n"):format(path, host)
end
for _, good in ipairs({ "192.168.1.5:8080", "10.0.0.7:8080", "127.0.0.1:8080", "localhost:8080" }) do
    assert(Upload.headers(get("/", good), "192.168.1.5:8080", token), good)
end
for _, bad in ipairs({ "192.168.1.5", "192.168.1.5:9090", "boox.local:8080", "evil.test:8080", "" }) do
    assert(not Upload.headers(get("/", bad), "192.168.1.5:8080", token), bad)
end
local other_host = assert(Upload.headers(
    "POST /upload HTTP/1.1\r\nHost: 10.0.0.7:8080\r\nX-BooxBook-Token: " .. token
        .. "\r\nX-File-Name: x.pdf\r\nContent-Length: 1\r\n\r\n", "192.168.1.5:8080", token))
assert(other_host.host == "10.0.0.7:8080", "parsed request records the host it answered")
local other_origin = assert(Upload.headers(headers("x.pdf", "1", "Origin: http://10.0.0.7:8080\r\n"),
    "192.168.1.5:8080", token))
assert(other_origin.name == "x.pdf", "upload from a second device address is accepted")
assert(not Upload.headers(headers("x.pdf", "1", "Origin: https://10.0.0.7:8080\r\n"),
    "192.168.1.5:8080", token), "https origin is rejected")
-- Cross-site navigations must load; cross-site writes must not.
local navigation = get("/", "192.168.1.5:8080"):gsub("\r\n\r\n",
    "\r\nSec-Fetch-Site: cross-site\r\n\r\n")
assert(Upload.headers(navigation, "192.168.1.5:8080", token), "a tapped link still opens the page")
assert(not Upload.headers(headers("x.pdf", "1", "Sec-Fetch-Site: cross-site\r\n"),
    "192.168.1.5:8080", token), "cross-site upload is refused")
assert(Upload.isLocalPeer("192.168.1.30", {}) == true, "private peer is local")
assert(Upload.isLocalPeer("137.55.1.99", { "137.55.1.10" }) == true, "public on-link neighbour is local")
assert(Upload.isLocalPeer("8.8.8.8", { "192.168.1.16" }) == false, "internet source is remote")
assert(Upload.isLocalPeer("unknown", {}) == true, "unclassifiable peer fails open")

local now, pending, bind_calls, listeners, busy = 0, {}, {}, {}, {}
local function makeListener(port)
    local listener = { port=port, settimeout=function() end,
        getsockname=function() return "0.0.0.0", port end,
        accept=function() return table.remove(pending, 1) end,
        close=function(self) self.closed=true end }
    listeners[#listeners + 1] = listener
    return listener
end
package.loaded.socket = {
    gettime = function() return now end,
    udp = function()
        return { setpeername=function() return 1 end,
            getsockname=function() return "192.168.1.16", 55000 end, close=function() end }
    end,
    bind = function(address, port, backlog)
        bind_calls[#bind_calls + 1] = { address=address, port=port, backlog=backlog }
        if busy[port] then return nil, "address already in use" end
        return makeListener(port)
    end,
}
package.loaded["booxbook.wifi-transfer-server"] = nil
local Server = require("booxbook.wifi-transfer-server")
assert(Server.pickAddress({ {name="rmnet0",address="10.0.0.2"},
    {name="wlan0",address="192.168.1.16"} }) == "192.168.1.16")
assert(Server.pickAddress({ {name="eth0",address="192.168.2.3"},
    {name="wlan1",address="192.168.3.4"} }, "eth0") == "192.168.2.3")
-- A VPN or cellular link must never be advertised while Wi-Fi carries the session.
assert(Server.pickAddress({ {name="tun0",address="10.8.0.2"},
    {name="wlan0",address="192.168.1.16"} }) == "192.168.1.16", "tunnel never outranks Wi-Fi")
assert(Server.pickAddress({ {name="rmnet0",address="10.0.0.2"} }, "rmnet0") == "10.0.0.2",
    "single non-LAN interface still returns an address")
local ordered = Server.addressList({ {name="tun0",address="10.8.0.2"}, {name="rmnet0",address="10.0.0.2"},
    {name="wlan0",address="192.168.1.16"} })
assert(#ordered == 3 and ordered[1] == "192.168.1.16", "LAN address first")
assert(Server.addressList({ {name="wlan0",address="169.254.10.3"},
    {name="wlan1",address="192.168.1.9"} })[1] == "192.168.1.9", "routable address beats link local")
assert(#Server.addressList({ "192.168.1.16", "not-an-address", nil }) == 1, "only IPv4 literals are listed")
assert(Server.localAddresses()[1] == "192.168.1.16", "routing-table probe is the last resort")
local mapped_open = io.open
local function randomCode(bytes)
    local offset, closed = 1, false
    io.open = function(path, mode)
        if path ~= "/dev/urandom" then return mapped_open(path, mode) end
        return { read=function(_, count)
            local result = bytes:sub(offset, offset + count - 1); offset = offset + count
            return result
        end, close=function() closed=true end }
    end
    local code = Server.sessionToken()
    io.open = mapped_open
    assert(closed)
    return code
end
assert(randomCode("\0\0\0") == "000000")
assert(randomCode("\15\66\63") == "999999")
assert(randomCode("\255\255\255\0\0\7") == "000007")
assert(randomCode("\0") == nil)
assert(not Server.new("@wifi", "127.0.0.1", "12345"))
assert(not Server.new("@wifi", "127.0.0.1", "abcdef"))
assert(not Server.new("@wifi", {}, token), "an empty address list cannot serve")
assert(not Server.new("@wifi", { "not-an-address" }, token))
local server = assert(Server.new("@wifi", "127.0.0.1", token))
assert(bind_calls[#bind_calls].address == "0.0.0.0", "all interfaces are reachable")
assert(bind_calls[#bind_calls].port == 8080 and server.url == "http://127.0.0.1:8080/")
-- A busy 8080 must not end the session: the next free port is used and displayed.
busy[8080] = true
local fallback = assert(Server.new("@wifi", { "192.168.1.16", "10.8.0.2" }, token))
assert(fallback.port == 8081 and fallback.url == "http://192.168.1.16:8081/", "port fallback")
assert(#fallback.addresses == 2 and fallback.addresses[2] == "10.8.0.2",
    "every address is kept for the on-screen list")
fallback:stop()
busy[8080] = nil
local notified
server.on_received = function(name) notified = name end
local function peer(chunks)
    local p = { chunks=chunks, output="", settimeout=function() end,
        receive=function(self)
            local data = table.remove(self.chunks, 1)
            return nil, self.disconnected and "closed" or "timeout", data or ""
        end,
        send=function(self, data, start)
            local last = math.min(#data, start + 36)
            self.output = self.output .. data:sub(start, last)
            return nil, "timeout", last
        end,
        close=function(self) self.closed=true end,
        getpeername=function(self) return self.address or "192.168.1.20", 12345 end }
    pending[#pending+1] = p
    return p
end
local function serve(srv, target, limit)
    for _ = 1, limit or 200 do
        srv:poll()
        if target.closed then break end
    end
end
local h = headers("stream.pdf", "6")
local p = peer({ h:sub(1, 9), h:sub(10) .. "ab", "cd", "ef" })
serve(server, p, 200)
assert(p.closed and p.output:find("201 Result", 1, true) and server.received == 1)
assert(server.connections == 1 and server.requests == 1, "accept and request counters")
assert(notified == "stream.pdf")
f = assert(io.open("@wifi/stream.pdf", "rb")); assert(f:read("*a") == "abcdef"); f:close()
local stalled = peer({ headers("stalled.pdf", "9") .. "x" })
server:poll(); server:poll(); now=31; server:poll()
assert(stalled.closed and not io.open("@wifi/stalled.pdf", "rb"))
local disconnected = peer({ headers("disconnect.pdf", "9") .. "x" })
server:poll(); server:poll(); disconnected.disconnected=true; server:poll()
assert(disconnected.closed)
local stopped = peer({ headers("stop.pdf", "9") .. "x" })
server:poll(); server:poll(); server:stop(); server:stop()
assert(stopped.closed and listeners[1].closed)
local guarded = assert(Server.new("@wifi", "127.0.0.1", token))
for _ = 1, 5 do
    local client = { buffer="", peer="192.168.1.30", id=30 }
    guarded:consume(client, (headers("guard.pdf", "1"):gsub(token, "654321")))
    assert(client.output:find("401 Result", 1, true))
end
local locked = { buffer="", peer="192.168.1.30", id=31 }
guarded:consume(locked, headers("guard.pdf", "1") .. "x")
assert(locked.output:find("429 Result", 1, true) and not io.open("@wifi/guard.pdf", "rb"))
local allowed = { buffer="", peer="192.168.1.31", id=32 }
guarded:consume(allowed, headers("guard.pdf", "1") .. "x")
assert(allowed.output:find("201 Result", 1, true))
assert(guarded.rejected > 0, "refusals are counted for the diagnostics screen")
guarded:stop()
-- Browsers: the send-books page is served for every address of the device, and a
-- browser that upgraded to HTTPS or a source from outside the LAN is told why.
local function browser(chunks, address)
    local p = peer(chunks)
    p.address = address or "192.168.1.44"
    return p
end
local desk = assert(Server.new("@wifi", { "192.168.1.16", "10.8.0.2" }, token))
local raw_page = get("/", "192.168.1.16:8080")
-- The request arrives as two TCP segments and the reply is the whole 5 KB page.
local first = browser({ raw_page:sub(1, 40), raw_page:sub(41) })
serve(desk, first, 400)
assert(first.closed and first.output:find("200 Result", 1, true), "page served")
assert(first.output:find("Gửi sách tới", 1, true) and first.output:find("text/html", 1, true))
assert(desk.requests == 1 and desk.recent_hosts[1] == "192.168.1.16:8080")
local second = browser({ get("/", "10.8.0.2:8080") })
serve(desk, second, 400)
assert(second.output:find("200 Result", 1, true), "the device's second address also serves the page")
assert(desk.recent_hosts[2] == "10.8.0.2:8080", "the host each request used is remembered")
local domain = browser({ get("/", "evil.test:8080") })
serve(desk, domain)
assert(domain.output:find("403 Result", 1, true) and not domain.output:find("Gửi sách tới", 1, true),
    "a rebinding host never sees the page")
assert(domain.output:find("192.168.1.16:8080", 1, true), "the refusal names the address to open")
local remote = browser({ get("/", "192.168.1.16:8080") }, "8.8.8.8")
serve(desk, remote)
assert(remote.closed and remote.output == "" and desk.connections == 3,
    "internet source refused before it holds a client slot")
-- A navigation that follows a link in another app is cross-site but must still load.
local navigation = browser({ get("/", "192.168.1.16:8080"):gsub("\r\n\r\n",
    "\r\nSec-Fetch-Site: cross-site\r\nReferer: https://chat.example/\r\n\r\n") })
serve(desk, navigation, 400)
assert(navigation.output:find("200 Result", 1, true) and navigation.output:find("Gửi sách tới", 1, true),
    "cross-site navigation still reaches the page")
-- A corporate/public LAN hands out globally routable addresses: same subnet, allowed.
local office = assert(Server.new("@wifi", "137.55.1.10", token))
local neighbour = browser({ get("/", "137.55.1.10:8080") }, "137.55.1.99")
serve(office, neighbour, 400)
assert(neighbour.output:find("200 Result", 1, true), "public but on-link source is served")
local scanner = browser({ get("/", "137.55.1.10:8080") }, "203.0.113.9")
serve(office, scanner)
assert(scanner.closed and scanner.output == "" and office.rejected == 1, "off-subnet source refused")
office:stop()
local tls = browser({ "\22\3\1\0\165\1\0\0\161\3\3" })
serve(desk, tls)
assert(tls.output:find("400 Result", 1, true) and desk.https_attempts == 1, "HTTPS upgrade detected")
desk:stop()

-- UI lifecycle: LAN without Internet, close/suspend cleanup, balanced standby.
local scheduled, unscheduled, shown, balance, message = nil, 0, nil, 0, nil
package.loaded["ui/widget/infomessage"] = { new=function(_, opts) return opts end }
package.loaded["ui/uimanager"] = {
    nextTick=function(_, cb) cb() end, scheduleIn=function(_, _, cb) scheduled=cb end,
    unschedule=function() unscheduled=unscheduled+1 end,
    preventStandby=function() balance=balance+1 end, allowStandby=function() balance=balance-1 end,
    show=function(_, widget) if widget.text then message=widget end end,
}
local network_manager = { isConnected=function() return true end,
    getNetworkInterfaceName=function() return "wlan0" end,
    beforeWifiAction=function() error("LAN should not require Internet") end }
package.loaded["ui/network/manager"] = network_manager
package.loaded["booxbook.ui.catalog"] = { show=function(opts) shown=opts; return opts end,
    pop=function(opts) opts.on_close() end }
package.loaded["booxbook.store.settings"] = { downloadDir=function() return "@wifi" end,
    ensureDir=function() return true end }
local stopped_count, server_count, ui_server, requested_interface, lan_ok = 0, 0, nil, nil, true
package.loaded["booxbook.wifi-transfer-server"] = {
    isLanAddress=function() return lan_ok end,
    localAddresses=function(preferred) requested_interface = preferred; return { "192.168.1.16", "10.8.0.2" } end,
    sessionToken=function() return token end, new=function(dir, addresses)
        server_count = server_count + 1
        ui_server = { url="http://192.168.1.16:8080/", token=token, addresses=addresses, port=8080,
            received=0, connections=0, requests=0, rejected=0, https_attempts=0,
            recent_hosts={}, poll=function() end, stop=function() stopped_count=stopped_count+1 end }
        return ui_server
    end,
}
package.loaded["booxbook.ui.wifi-transfer"] = nil
local Transfer = require("booxbook.ui.wifi-transfer")
Transfer.show(); assert(shown and scheduled and balance == 1)
assert(requested_interface == "wlan0", "the active network interface is passed to the server")
assert(ui_server.addresses[1] == "192.168.1.16", "alternate addresses reach the screen")
ui_server.on_received("received.epub")
assert(message.text == "Đã nhận sách:\nreceived.epub" and message.timeout == 3)
shown.items[4].callback()
assert(message.text:find("http://192.168.1.16:8080/", 1, true), "primary address listed")
assert(message.text:find("http://10.8.0.2:8080/", 1, true), "alternate address listed")
assert(message.text:find(token, 1, true), "session code repeated")
ui_server.connections, ui_server.requests, ui_server.rejected = 2, 3, 1
ui_server.https_attempts, ui_server.recent_hosts = 1, { "192.168.1.16:8080" }
shown.items[5].callback()
assert(message.text:match("^Kết nối đã nhận: 2 · yêu cầu: 3 · sách: 0"), message.text)
assert(message.text:find("192.168.1.16:8080", 1, true) and message.text:find("HTTPS", 1, true))
ui_server.connections = 0
ui_server.recent_hosts = {}
shown.items[5].callback()
assert(message.text:find("Chưa có kết nối nào", 1, true), "zero connections is explained")
ui_server.connections = 2
local qr
package.loaded["ui/widget/qrmessage"] = { new=function(_, opts) qr=opts; return opts end }
for _, dimensions in ipairs({ {1080, 2340}, {2340, 1080}, {600, 800} }) do
    package.loaded.device = { screen={ getWidth=function() return dimensions[1] end,
        getHeight=function() return dimensions[2] end } }
    shown.items[3].callback()
    assert(qr.width == math.floor(math.min(unpack(dimensions)) * 0.85))
    assert(qr.height == qr.width and qr.scale_factor == 1)
    assert(qr.text == "http://192.168.1.16:8080/#" .. token)
end
scheduled(); shown.on_close(); Transfer.stop()
assert(balance == 0 and stopped_count == 1 and unscheduled == 1)
lan_ok = false
Transfer.show()
assert(shown.subtitle:find("kiểm tra Wi-Fi/VPN", 1, true), "non-LAN address warns on screen")
shown.items[4].callback()
assert(message.text:find("VPN", 1, true), "address sheet explains the VPN case")
Transfer.stop()
lan_ok = true
local delayed
network_manager.isConnected = function() return false end
network_manager.beforeWifiAction = function(_, callback) delayed=callback end
local opened = server_count
Transfer.show(); assert(delayed)
Transfer.stop(); delayed()
assert(server_count == opened, "closed plugin cancels delayed Wi-Fi callback")

io.open, os.remove, os.rename = open, remove, rename
for _, path in pairs(paths) do remove(path) end
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Wi-Fi transfer: address ranking, all-interface listen, host rules, peer guard, HTTPS detection, real file writes, partial I/O, timeout, disconnect and UI cleanup passed")
