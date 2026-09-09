local names = { "libs/libkoreader-lfs", "gettext", "socket", "booxbook.wifi-upload",
    "booxbook.wifi-transfer-server", "booxbook.ui.wifi-transfer", "ui/uimanager",
    "ui/network/manager", "booxbook.ui.catalog", "booxbook.store.settings", "ui/widget/infomessage",
    "device", "ui/widget/qrmessage" }
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

local now, pending = 0, {}
local listener = { settimeout=function() end, getsockname=function() return "127.0.0.1", 8080 end,
    accept=function() return table.remove(pending, 1) end, close=function(self) self.closed=true end }
package.loaded.socket = { bind=function() return listener end, gettime=function() return now end }
package.loaded["booxbook.wifi-transfer-server"] = nil
local Server = require("booxbook.wifi-transfer-server")
assert(Server.pickAddress({ {name="rmnet0",address="10.0.0.2"},
    {name="wlan0",address="192.168.1.16"} }) == "192.168.1.16")
assert(Server.pickAddress({ {name="eth0",address="192.168.2.3"},
    {name="wlan1",address="192.168.3.4"} }, "eth0") == "192.168.2.3")
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
local server = assert(Server.new("@wifi", "127.0.0.1", token))
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
        getpeername=function() return "192.168.1.20", 12345 end }
    pending[#pending+1] = p
    return p
end
local h = headers("stream.pdf", "6")
local p = peer({ h:sub(1, 9), h:sub(10) .. "ab", "cd", "ef" })
for _ = 1, 40 do server:poll() end
assert(p.closed and p.output:find("201 Result", 1, true) and server.received == 1)
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
assert(stopped.closed and listener.closed)
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
guarded:consume(allowed, headers("allowed.pdf", "1") .. "x")
assert(allowed.output:find("201 Result", 1, true))
guarded:stop()
for path in pairs(paths) do
    if path:find(".part", 1, true) then assert(not io.open(path, "rb"), path) end
end

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
    beforeWifiAction=function() error("LAN should not require Internet") end }
package.loaded["ui/network/manager"] = network_manager
package.loaded["booxbook.ui.catalog"] = { show=function(opts) shown=opts; return opts end,
    pop=function(opts) opts.on_close() end }
package.loaded["booxbook.store.settings"] = { downloadDir=function() return "@wifi" end,
    ensureDir=function() return true end }
local stopped_count, server_count, ui_server = 0, 0, nil
package.loaded["booxbook.wifi-transfer-server"] = { localAddress=function() return "127.0.0.1" end,
    sessionToken=function() return token end, new=function()
        server_count = server_count + 1
        ui_server = { url="http://127.0.0.1:8080/", token=token, received=0,
            poll=function() end, stop=function() stopped_count=stopped_count+1 end }
        return ui_server
    end }
package.loaded["booxbook.ui.wifi-transfer"] = nil
local Transfer = require("booxbook.ui.wifi-transfer")
Transfer.show(); assert(shown and scheduled and balance == 1)
ui_server.on_received("received.epub")
assert(message.text == "Đã nhận sách:\nreceived.epub" and message.timeout == 3)
local qr
package.loaded["ui/widget/qrmessage"] = { new=function(_, opts) qr=opts; return opts end }
for _, dimensions in ipairs({ {1080, 2340}, {2340, 1080}, {600, 800} }) do
    package.loaded.device = { screen={ getWidth=function() return dimensions[1] end,
        getHeight=function() return dimensions[2] end } }
    shown.items[3].callback()
    assert(qr.width == math.floor(math.min(unpack(dimensions)) * 0.85))
    assert(qr.height == qr.width and qr.scale_factor == 1)
    assert(qr.text == "http://127.0.0.1:8080/#" .. token)
end
scheduled(); shown.on_close(); Transfer.stop()
assert(balance == 0 and stopped_count == 1 and unscheduled == 1)
local delayed
network_manager.isConnected = function() return false end
network_manager.beforeWifiAction = function(_, callback) delayed=callback end
Transfer.show(); assert(delayed)
Transfer.stop(); delayed()
assert(server_count == 1, "closed plugin cancels delayed Wi-Fi callback")

io.open, os.remove, os.rename = open, remove, rename
for _, path in pairs(paths) do remove(path) end
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Wi-Fi transfer: validation, real file writes, partial I/O, timeout, disconnect and UI cleanup passed")
