-- Prefer DNS reachability (isOnline) like kagi-news/quickrss.
-- beforeWifiAction alone prompts "turn on Wi-Fi" even when the device already has WAN.
local NetworkMgr = require("ui/network/manager")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local has_settings, Settings = pcall(require, "booxbook.store.settings")

local Network = {}

-- Status glyphs are ones the menu already renders (✓ in item rows, • in the home footer,
-- ○ for unchecked rows). Emoji are avoided: KOReader's reader fonts do not cover them and
-- e-ink would show empty boxes.
local ICONS = { online = "✓", linked = "•", offline = "○", unknown = "?" }

-- Interface families, used when the platform cannot report a network name.
local TRANSPORTS = {
    { "^wlan", "Wi-Fi" }, { "^wifi", "Wi-Fi" }, { "^ap%d", "Wi-Fi" },
    { "^eth", "Ethernet" }, { "^en%d", "Ethernet" },
    { "^rmnet", "4G" }, { "^pdp", "4G" }, { "^ccmni", "4G" }, { "^wwan", "4G" },
    { "^tun", "VPN" }, { "^utun", "VPN" }, { "^wg", "VPN" },
}

local DETAIL_TTL = 60
local DETAIL_LIMIT = 30
local detail_cache, detail_time

local function call(method)
    if type(NetworkMgr[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(NetworkMgr[method], NetworkMgr)
    if ok then
        return value
    end
end

local function transportLabel(interface)
    if type(interface) ~= "string" then return end
    for _, entry in ipairs(TRANSPORTS) do
        if interface:match(entry[1]) then return entry[2] end
    end
end

-- Android devices report the transport through KOReader's android module instead of an
-- interface name: 1 = Wi-Fi, 2 = mobile data, 3 = Ethernet (the launcher's enum).
local ANDROID_TRANSPORTS = { [1] = "Wi-Fi", [2] = "4G", [3] = "Ethernet" }

local function androidTransport()
    local ok_module, android = pcall(require, "android")
    if not ok_module or type(android) ~= "table" or type(android.getNetworkInfo) ~= "function" then
        return
    end
    local ok, _, kind = pcall(android.getNetworkInfo)
    if not ok then return end
    return ANDROID_TRANSPORTS[tonumber(kind)]
end

local function commandLine(command)
    if type(io.popen) ~= "function" then return end
    local ok, pipe = pcall(io.popen, command)
    if not ok or not pipe then return end
    local first = pipe:read("*l")
    pcall(pipe.close, pipe)
    if type(first) ~= "string" then return end
    local trimmed = first:match("^%s*(.-)%s*$")
    if trimmed ~= "" then return trimmed end
end

-- wpa_supplicant is the only SSID source a plugin can read, and only on Linux readers.
-- An Android app cannot read it: KOReader holds no ACCESS_WIFI_STATE/location grant,
-- `cmd wifi` is shell-only, and there is no iwgetid//proc/net/wireless on Android.
local function wpaSsid(interface)
    if type(interface) ~= "string" or not interface:match("^[%w%.%-]+$") then return end
    if type(io.popen) ~= "function" then return end
    local ok, pipe = pcall(io.popen, "wpa_cli -i " .. interface .. " status 2>/dev/null")
    if not ok or not pipe then return end
    local name
    for _ = 1, 40 do
        local line = pipe:read("*l")
        if not line then break end
        name = line:match("^ssid=(.+)$") or name
    end
    pcall(pipe.close, pipe)
    if name and name ~= "" then return name end
end

local function isAndroid()
    return (pcall(require, "android"))
end

local function ssidName(interface)
    if isAndroid() then return end
    local from_command = commandLine("iwgetid -r 2>/dev/null")
    if from_command then return from_command end
    return wpaSsid(interface)
end

-- Routing-table probe: no DNS lookup and no packet is sent.
local function localAddress()
    local ok, address = pcall(function()
        local socket = require("socket")
        local probe = socket.udp()
        if not probe then return end
        local routed = probe:setpeername("203.0.113.1", 9)
        local value = routed and probe:getsockname()
        probe:close()
        if value and value ~= "0.0.0.0" and not value:match("^127%.") then return value end
    end)
    if ok then return address end
end

local function settingText(key)
    if not has_settings or type(Settings.get) ~= "function" then return end
    local ok, value = pcall(Settings.get, key)
    if ok and type(value) == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed ~= "" then return trimmed end
    end
end
-- "Which network am I on": the name the user stored, otherwise the SSID where the platform
-- allows reading it, otherwise the transport. Android apps cannot read the SSID (no
-- ACCESS_WIFI_STATE/location grant and `cmd wifi` is shell-only), and the address is not
-- shown here because the transfer screen already lists the addresses to type.
local function networkDetail()
    -- Detection is cached; the stored name is read fresh so editing it shows immediately.
    local now = os.time()
    if detail_cache == nil or now - detail_time >= DETAIL_TTL then
        local interface = call("getNetworkInterfaceName")
        detail_cache = ssidName(interface) or transportLabel(interface) or androidTransport()
        detail_time = now
    end
    local stored = settingText("wifi_label")
    if stored and (detail_cache == nil or detail_cache == "Wi-Fi") then return stored end
    return detail_cache
end

-- One-shot read for Android devices where the user grants root: KOReader itself has no
-- way to see the SSID, and the shell can. Called from the settings menu, never from the
-- status line, because su may block on a consent prompt.
function Network.readWifiNameByRoot()
    if not isAndroid() then return nil, "android_only" end
    if type(io.popen) ~= "function" then return nil, "no_shell" end
    local ok, pipe = pcall(io.popen, "timeout 8 su -c \"cmd wifi status\" 2>/dev/null")
    if not ok or not pipe then return nil, "no_root" end
    local name
    for _ = 1, 120 do
        local line = pipe:read("*l")
        if not line then break end
        local found = line:match('SSID:%s*"(.-)"')
        if found and found ~= "" and found ~= "<unknown ssid>" then
            name = found
            break
        end
    end
    pcall(pipe.close, pipe)
    if name then return name end
    return nil, "not_found"
end


-- Best-effort detection for the settings screen: wpa_supplicant where it exists, root on
-- Android. The status line itself never runs the root path, so it cannot block on a
-- consent prompt.
function Network.detectWifiName()
    local interface = call("getNetworkInterfaceName")
    local name = ssidName(interface)
    if name then return name end
    return (Network.readWifiNameByRoot())
end
-- UTF-8 safe truncation so a long network name stays inside the title bar.
local function shorten(text)
    if type(text) ~= "string" or #text <= DETAIL_LIMIT then return text end
    local cut = text:sub(1, DETAIL_LIMIT)
    while #cut > 0 do
        local byte = cut:byte(#cut)
        if byte < 0x80 or byte >= 0xC0 then break end
        cut = cut:sub(1, #cut - 1)
    end
    return cut .. "…"
end

-- Plain text status, kept for tools and tests that compare labels exactly.
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

-- Decorated status for the home title bar: icon, label, and the network in use.
function Network.statusLine()
    local connected = call("isConnected")
    if connected == false then
        return ICONS.offline .. " " .. _("Chưa kết nối mạng")
    end
    if connected ~= true then
        return ICONS.unknown .. " " .. _("Chưa xác định trạng thái mạng")
    end
    local icon, label
    if call("isOnline") then
        icon, label = ICONS.online, _("Đã kết nối mạng")
    else
        icon, label = ICONS.linked, _("Có liên kết mạng (chưa chắc Internet)")
    end
    local detail = shorten(networkDetail())
    if detail then return icon .. " " .. label .. " · " .. detail end
    return icon .. " " .. label
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
