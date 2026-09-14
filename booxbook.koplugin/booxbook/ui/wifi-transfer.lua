local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Catalog = require("booxbook.ui.catalog")
local Settings = require("booxbook.store.settings")
local Server = require("booxbook.wifi-transfer-server")
local _ = require("gettext")
local Transfer = {}
local server, screen, tick, standby, generation = nil, nil, nil, nil, 0
local firewall_rules = {}

local function firewallCommand(action, rule)
    local ok, status = pcall(os.execute, "iptables " .. action .. " " .. rule)
    return ok and (status == 0 or status == true)
end

local function openFirewall(port)
    local Device = require("device")
    if not Device:isKindle() then return true end
    -- Match KOReader's HTTP Inspector, using the port actually bound (8080 may be busy).
    for _, rule in ipairs({
        "INPUT -p tcp --dport " .. port .. " -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT",
        "OUTPUT -p tcp --sport " .. port .. " -m conntrack --ctstate ESTABLISHED -j ACCEPT",
    }) do
        if not firewallCommand("-A", rule) then return false end
        firewall_rules[#firewall_rules + 1] = rule
    end
    return true
end

function Transfer.stop()
    generation = generation + 1
    if tick then UIManager:unschedule(tick); tick = nil end
    if server then server:stop(); server = nil end
    for index = #firewall_rules, 1, -1 do
        if firewallCommand("-D", firewall_rules[index]) then
            table.remove(firewall_rules, index)
        end
    end
    if standby then UIManager:allowStandby(); standby = nil end
    if screen then
        local old = screen
        screen = nil
        Catalog.pop(old)
    end
end

-- KOReader knows which interface carries the current network; a VPN still counts as
-- active there, so the server ranks tunnels last instead of trusting this name alone.
local function preferredInterface()
    if type(NetworkMgr.getNetworkInterfaceName) ~= "function" then return end
    local ok, value = pcall(NetworkMgr.getNetworkInterfaceName, NetworkMgr)
    if ok then return value end
end

local function primaryAddress(current)
    return (current.addresses or {})[1]
end

local function addressText(current)
    local lines = { _("Mở một trong các địa chỉ sau trên điện thoại/máy tính cùng mạng Wi-Fi:") }
    for index, address in ipairs(current.addresses or {}) do
        lines[#lines + 1] = "http://" .. address .. ":" .. tostring(current.port) .. "/"
            .. (index == 1 and "  ← " .. _("thử trước") or "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Mã phiên:") .. " " .. tostring(current.token)
    if #(current.addresses or {}) > 1 then
        lines[#lines + 1] = _("Địa chỉ đầu không mở được thì thử địa chỉ tiếp theo.")
    end
    if Server.isLanAddress(primaryAddress(current)) == false then
        lines[#lines + 1] = _("Địa chỉ này không thuộc mạng nội bộ (VPN/4G). Hãy tắt VPN hoặc kiểm tra Wi-Fi.")
    end
    return table.concat(lines, "\n")
end

local function resultText(current, dir)
    local connections = current.connections or 0
    local lines = {
        _("Kết nối đã nhận:") .. " " .. tostring(connections)
            .. " · " .. _("yêu cầu:") .. " " .. tostring(current.requests or 0)
            .. " · " .. _("sách:") .. " " .. tostring(current.received or 0),
    }
    if #(current.recent_hosts or {}) > 0 then
        lines[#lines + 1] = _("Địa chỉ đã gọi:") .. " " .. table.concat(current.recent_hosts, ", ")
    else
        lines[#lines + 1] = _("Địa chỉ đã gọi:") .. " " .. _("chưa có")
    end
    if (current.rejected or 0) > 0 then
        lines[#lines + 1] = _("Bị từ chối:") .. " " .. tostring(current.rejected)
            .. " — " .. _("mở đúng địa chỉ đang hiển thị và nhập đúng mã phiên.")
    end
    if (current.https_attempts or 0) > 0 then
        lines[#lines + 1] = _("Trình duyệt thử HTTPS:") .. " " .. tostring(current.https_attempts)
            .. " — " .. _("gõ http:// trước địa chỉ.")
    end
    if connections == 0 then
        lines[#lines + 1] = _("Chưa có kết nối nào tới máy đọc sách: kiểm tra hai máy cùng một mạng Wi-Fi,")
            .. " " .. _("tắt VPN và tránh mạng khách chặn thiết bị nội bộ.")
    end
    if current.last_name then lines[#lines + 1] = current.last_name end
    lines[#lines + 1] = _("Thư mục:") .. " " .. tostring(dir)
    return table.concat(lines, "\n")
end

local function start(expected_generation)
    if expected_generation ~= generation then return end
    if server then return end
    local dir = Settings.downloadDir() .. "/received"
    local err
    if Settings.ensureDir(dir) then
        server, err = Server.new(dir, Server.localAddresses(preferredInterface()), Server.sessionToken())
    else err = _("Không tạo được thư mục nhận sách.") end
    if not server then UIManager:show(InfoMessage:new{ text=err }); return end
    if not openFirewall(server.port) then
        Transfer.stop()
        UIManager:show(InfoMessage:new{
            text=_("Không mở được cổng nhận sách qua tường lửa Kindle. Hãy khởi động lại KOReader và thử lại."),
        })
        return
    end
    local current = server
    current.on_received = function(name)
        UIManager:show(InfoMessage:new{ text=_("Đã nhận sách:") .. "\n" .. name, timeout=3 })
    end
    local subtitle = _("Giữ màn hình này mở trong khi gửi sách")
    if Server.isLanAddress(primaryAddress(current)) == false then
        subtitle = subtitle .. " — " .. _("kiểm tra Wi-Fi/VPN!")
    end
    screen = Catalog.show{
        title = _("Gửi sách qua Wi-Fi"),
        subtitle = subtitle,
        on_close = Transfer.stop,
        items = {
            { text=current.url, select_enabled=false },
            { text=_("Mã phiên:") .. " " .. current.token, select_enabled=false },
            { text=_("Quét QR để gửi từ điện thoại"), keep_menu_open=true, callback=function()
                local QRMessage = require("ui/widget/qrmessage")
                local Screen = require("device").screen
                local size = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.85)
                UIManager:show(QRMessage:new{ text=current.url .. "#" .. current.token,
                    width=size, height=size, scale_factor=1 })
            end },
            { text=_("Xem địa chỉ và mã phiên"), keep_menu_open=true, callback=function()
                UIManager:show(InfoMessage:new{ text=addressText(current) })
            end },
            { text=_("Kiểm tra kết nối và kết quả"), keep_menu_open=true, callback=function()
                UIManager:show(InfoMessage:new{ text=resultText(current, dir) })
            end },
            { text=_("Dừng nhận sách"), callback=Transfer.stop },
        },
    }
    UIManager:preventStandby()
    standby = true
    tick = function()
        local ok, busy = pcall(current.poll, current)
        if not ok then
            Transfer.stop()
            UIManager:show(InfoMessage:new{ text=_("Nhận sách bị gián đoạn. Hãy mở lại phiên nhận.") })
            return
        end
        -- 20 Hz only while a device is connected; an idle session wakes 4x less often.
        UIManager:scheduleIn((busy or 0) > 0 and 0.05 or 0.2, tick)
    end
    UIManager:scheduleIn(0.2, tick)
end

function Transfer.show()
    generation = generation + 1
    local expected_generation = generation
    UIManager:nextTick(function()
        if expected_generation ~= generation then return end
        -- LAN only: no Internet reachability/DNS requirement.
        if NetworkMgr:isConnected() then start(expected_generation)
        else NetworkMgr:beforeWifiAction(function() start(expected_generation) end) end
    end)
end

return Transfer
