-- Prefer DNS reachability (isOnline) like kagi-news/quickrss.
-- beforeWifiAction alone prompts "turn on Wi-Fi" even when the device already has WAN.
local NetworkMgr = require("ui/network/manager")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end

local Network = {}

local function call(method)
    if type(NetworkMgr[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(NetworkMgr[method], NetworkMgr)
    if ok then
        return value
    end
end

function Network.statusText()
    -- isOnline can return true unconditionally on platforms without Wi-Fi toggling.
    -- Android's isConnected queries the actual OS network state instead.
    -- Kindle checks wlan0's operational state and assigned address.
    local connected = call("isConnected")
    if connected == false then
        return _("Chưa kết nối mạng")
    end
    if connected ~= true then
        return _("Chưa xác định trạng thái mạng")
    end
    if call("isOnline") then
        return _("Đã kết nối mạng")
    end
    return _("Có liên kết mạng (chưa chắc Internet)")
end

-- Passive gate: runs the callback only when already online/connected.
-- Never prompts for Wi-Fi (unlike whenOnline). For silent periodic checks.
function Network.ifOnline(callback)
    if type(callback) ~= "function" then
        return false
    end
    if call("isOnline") then
        callback()
        return true
    end
    if call("isConnected") then
        callback()
        return true
    end
    return false
end

function Network.whenOnline(callback)
    if type(callback) ~= "function" then
        return
    end
    if call("isOnline") then
        callback()
        return
    end
    -- Connected LAN/Wi-Fi without a clean DNS probe: still attempt the request.
    if call("isConnected") then
        callback()
        return
    end
    if type(NetworkMgr.beforeWifiAction) == "function" then
        NetworkMgr:beforeWifiAction(callback)
        return
    end
    callback()
end

return Network
