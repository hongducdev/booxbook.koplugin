local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Catalog = require("booxbook.ui.catalog")
local Settings = require("booxbook.store.settings")
local Server = require("booxbook.wifi-transfer-server")
local _ = require("gettext")
local Transfer = {}
local server, screen, tick, standby, generation = nil, nil, nil, nil, 0

function Transfer.stop()
    generation = generation + 1
    if tick then UIManager:unschedule(tick); tick = nil end
    if server then server:stop(); server = nil end
    if standby then UIManager:allowStandby(); standby = nil end
    if screen then
        local old = screen
        screen = nil
        Catalog.pop(old)
    end
end

local function start(expected_generation)
    if expected_generation ~= generation then return end
    if server then return end
    local dir = Settings.downloadDir() .. "/received"
    local err
    if Settings.ensureDir(dir) then
        local interface
        if type(NetworkMgr.getNetworkInterfaceName) == "function" then
            local ok, value = pcall(NetworkMgr.getNetworkInterfaceName, NetworkMgr)
            if ok then interface = value end
        end
        server, err = Server.new(dir, Server.localAddress(interface), Server.sessionToken())
    else err = _("Không tạo được thư mục nhận sách.") end
    if not server then UIManager:show(InfoMessage:new{ text=err }); return end
    local current = server
    current.on_received = function(name)
        UIManager:show(InfoMessage:new{ text=_("Đã nhận sách:") .. "\n" .. name, timeout=3 })
    end
    screen = Catalog.show{
        title = _("Gửi sách qua Wi-Fi"),
        subtitle = _("Giữ màn hình này mở trong khi gửi sách"),
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
                UIManager:show(InfoMessage:new{ text=current.url .. "\n\n" .. _("Mã phiên:") .. "\n" .. current.token
                    .. "\n\n" .. _("Nhập địa chỉ web và mã phiên trên điện thoại/máy tính cùng mạng Wi-Fi.") })
            end },
            { text=_("Xem kết quả nhận sách"), keep_menu_open=true, callback=function()
                UIManager:show(InfoMessage:new{ text=_("Số sách đã nhận:") .. " " .. current.received
                    .. "\n" .. (current.last_name or "") .. "\n\n" .. _("Thư mục:") .. " " .. dir })
            end },
            { text=_("Dừng nhận sách"), callback=Transfer.stop },
        },
    }
    UIManager:preventStandby()
    standby = true
    tick = function()
        local ok = pcall(current.poll, current)
        if not ok then
            Transfer.stop()
            UIManager:show(InfoMessage:new{ text=_("Nhận sách bị gián đoạn. Hãy mở lại phiên nhận.") })
            return
        end
        UIManager:scheduleIn(0.05, tick)
    end
    UIManager:scheduleIn(0.05, tick)
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
