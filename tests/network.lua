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

state.online, state.connected = true, false
assert(Network.statusText() == "Đã kết nối mạng", "online status label")
state.online, state.connected = false, true
assert(Network.statusText():find("liên kết", 1, true), "connected-only status label")
state.online, state.connected = false, false
assert(Network.statusText():find("Chưa kết nối", 1, true), "offline status label")

package.loaded["ui/network/manager"] = saved
package.loaded["booxbook.network"] = nil
print("Network whenOnline guard checks passed")
