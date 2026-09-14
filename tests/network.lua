-- Network.whenOnline: skip Wi-Fi prompts when DNS/connectivity already says online.
local saved = package.loaded["ui/network/manager"]
local prompts, ran = 0, 0
local state = { online = true, connected = false }
package.loaded["ui/network/manager"] = {
    isOnline = function() return state.online end,
    isConnected = function() return state.connected end,
    beforeWifiAction = function(_, fn) prompts = prompts + 1; fn() end,
}
package.loaded["booxbook.network"] = nil
local Network = require("booxbook.network")

Network.whenOnline(function() ran = ran + 1 end)
assert(ran == 1 and prompts == 0, "isOnline short-circuits without a Wi-Fi prompt")

state.online, state.connected, prompts = false, true, 0
Network.whenOnline(function() ran = ran + 1 end)
assert(ran == 2 and prompts == 0, "isConnected still runs work without prompting")

state.online, state.connected, prompts = false, false, 0
Network.whenOnline(function() ran = ran + 1 end)
assert(ran == 3 and prompts == 1, "offline falls back to beforeWifiAction")

state.online, state.connected = true, true
assert(Network.statusText() == "Đã kết nối mạng", "online status label")
state.online, state.connected = true, false
assert(Network.statusText() == "Chưa kết nối mạng", "Android disconnected overrides optimistic isOnline")
state.connected = nil
assert(Network.statusText() == "Chưa xác định trạng thái mạng", "unknown connectivity must not claim online")
state.online, state.connected = false, true
assert(Network.statusText():find("liên kết", 1, true), "connected-only status label")
state.online, state.connected = false, false
assert(Network.statusText():find("Chưa kết nối", 1, true), "offline status label")

local manager = package.loaded["ui/network/manager"]
-- Kindle: wlan0 is down, even if hostname resolution still succeeds from cache.
local online_probe = manager.isOnline
manager.isOnline = function() error("offline status must not query DNS") end
state.connected = false
assert(Network.statusText() == "Chưa kết nối mạng", "Kindle wlan0 down skips DNS")
manager.isOnline = online_probe
state.online, state.connected = true, true
assert(Network.statusText() == "Đã kết nối mạng", "reconnection refreshes status")
state.connected = false
assert(Network.statusText() == "Chưa kết nối mạng", "disconnect does not reuse online status")
manager.isConnected = function() error("network API unavailable") end
assert(Network.statusText() == "Chưa xác định trạng thái mạng", "connectivity errors remain unknown")
manager.isConnected = nil
assert(Network.statusText() == "Chưa xác định trạng thái mạng", "missing connectivity API remains unknown")

-- Home status line: an icon per state plus the network the reader is on.
local real_popen, real_socket = io.popen, package.loaded["socket"]
local popen_lines = { "PixelArt 2" }
io.popen = function()
    return { read = function() return table.remove(popen_lines, 1) end, close = function() end }
end
package.loaded["socket"] = { udp = function()
    return { setpeername = function() return 1 end,
        getsockname = function() return "192.168.1.11", 55000 end, close = function() end }
end }
manager.isOnline = function() return true end
manager.isConnected = function() return true end
manager.getNetworkInterfaceName = function() return "wlan0" end

local function statusLine()
    package.loaded["booxbook.network"] = nil
    return require("booxbook.network").statusLine()
end

local line = statusLine()
-- Glyphs are multi-byte UTF-8, so compare the first word instead of the first byte.
assert(line:match("^(%S+)") == "✓", "connected status leads with the check glyph: " .. line)
assert(line:find("PixelArt 2", 1, true) and not line:find("192.168.1.11", 1, true),
    "status line shows the Wi-Fi name instead of the address: " .. line)

-- Android hands out no SSID to apps: the transport and address stand in for it.
io.popen = nil
line = statusLine()
assert(line:find("Wi-Fi", 1, true) and not line:find("192.168.1.11", 1, true),
    "transport shown, address not used as a name: " .. line)
assert(not line:find("PixelArt", 1, true), "no stale network name is reused")

manager.isConnected = function() return false end
assert(statusLine():match("^(%S+)") == "○", "offline status leads with the open circle")
manager.isConnected = nil
assert(statusLine():match("^(%S+)") == "?", "unknown status leads with the question glyph")
manager.isConnected = function() return true end
manager.isOnline = function() return false end
assert(statusLine():match("^(%S+)") == "•", "link-only status leads with the bullet")

-- Android reads: no shell, no interface name, transport straight from KOReader's API.
package.preload["android"] = function()
    return { getNetworkInfo = function() return "1", "1" end }
end
package.loaded["android"] = nil
manager.getNetworkInterfaceName = nil
line = statusLine()
assert(line:find("Wi-Fi", 1, true) and not line:find("192.168.1.11", 1, true),
    "Android transport shown without an address: " .. line)
package.preload["android"] = nil
package.loaded["android"] = nil
manager.getNetworkInterfaceName = function() return "wlan0" end
-- A name stored in settings wins over detection and replaces the transport fallback.
local real_settings = package.loaded["booxbook.store.settings"]
package.loaded["booxbook.store.settings"] = { get = function(key)
    if key == "wifi_label" then return "  Mạng nhà  " end
end }
manager.getNetworkInterfaceName = function() return "wlan0" end
manager.isOnline = function() return true end
line = statusLine()
assert(line:find("Mạng nhà", 1, true), "stored Wi-Fi name is shown: " .. line)
assert(not line:find("Wi-Fi", 1, true), "the stored name replaces the transport label: " .. line)
package.loaded["booxbook.store.settings"] = real_settings

-- Root read: opt-in, Android only, parsed from `cmd wifi status`.
package.preload["android"] = function() return { getNetworkInfo = function() return "1", "1" end } end
package.loaded["android"] = nil
package.loaded["booxbook.network"] = nil
local RootNetwork = require("booxbook.network")
io.popen = function(command)
    assert(command:find("cmd wifi status", 1, true), "root read asks the shell for wifi status")
    assert(command:find("su -c", 1, true), "root read goes through su")
    local lines = { 'Wifi is connected to "PixelArt 2"', 'WifiInfo: SSID: "PixelArt 2", BSSID: aa:bb' }
    return { read = function() return table.remove(lines, 1) end, close = function() end }
end
assert(RootNetwork.readWifiNameByRoot() == "PixelArt 2", "root read returns the SSID")
io.popen = nil
assert(select(2, RootNetwork.readWifiNameByRoot()) == "no_shell", "without a shell the root read says so")
package.loaded["android"] = nil
package.preload["android"] = nil
io.popen, package.loaded["socket"] = real_popen, real_socket
package.loaded["ui/network/manager"] = saved
package.loaded["booxbook.network"] = nil
print("Network whenOnline guard checks passed")
