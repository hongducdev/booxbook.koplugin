local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local GDrive = require("booxbook.gdrive")
local Network = require("booxbook.network")
local Backup = require("booxbook.backup")
local Settings = require("booxbook.store.settings")

local UI = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function online(message, action, on_success)
    UIManager:nextTick(function()
        Network.whenOnline(function()
            Trapper:wrap(function()
                Trapper:info(message)
                local called, result, err = pcall(action)
                Trapper:clear()
                if not called or not result then
                    notify(tostring(called and err or result))
                    return
                end
                if on_success then UIManager:nextTick(function() on_success(result) end) end
            end)
        end)
    end)
end

local function sizeText(bytes)
    bytes = tonumber(bytes)
    if not bytes then return "?" end
    if bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / 1024 / 1024) end
    if bytes >= 1024 then return string.format("%d KB", math.floor(bytes / 1024)) end
    return tostring(bytes) .. " B"
end

function UI.showLogin(info)
    info = info or GDrive.loginInfo()
    local items = {}
    if info then
        items[#items + 1] = { text = info.verification_uri, select_enabled = false }
        items[#items + 1] = { text = _("Mã:") .. " " .. info.user_code, select_enabled = false }
        items[#items + 1] = { text = _("Quét QR để mở trang đăng nhập"), keep_menu_open = true, callback = function()
            local QRMessage = require("ui/widget/qrmessage")
            local screen = require("device").screen
            local size = math.floor(math.min(screen:getWidth(), screen:getHeight()) * 0.85)
            UIManager:show(QRMessage:new{ text = info.verification_uri,
                width = size, height = size, scale_factor = 1 })
        end }
        items[#items + 1] = { text = _("Đã đăng nhập, kiểm tra"), keep_menu_open = true, callback = function()
            online(_("Đang kiểm tra đăng nhập Google..."), GDrive.finishLogin, function()
                notify(_("Đã đăng nhập Google Drive."))
                Catalog.clearStack()
                UI.showFolder(nil, "Google Drive")
            end)
        end }
    end
    items[#items + 1] = { text = info and _("Tạo mã đăng nhập mới") or _("Đăng nhập Google Drive"),
        keep_menu_open = true, callback = function()
            online(_("Đang tạo mã đăng nhập Google..."), GDrive.startLogin, UI.showLogin)
        end }
    Catalog.show{ title = _("Đăng nhập Google Drive"), items = items }
end

function UI.download(item)
    Catalog.confirm(_("Tải về thư viện?") .. "\n" .. item.name .. " · " .. sizeText(item.size), function()
        online(_("Đang tải:") .. " " .. item.name, function() return GDrive.download(item) end, function(path)
            notify(_("Đã tải sách:") .. "\n" .. path)
        end)
    end)
end

function UI.uploadBackup()
    online(_("Đang tải bản sao lưu lên Google Drive..."), function()
        local body, err = Backup.export(Settings.get)
        if not body then return nil, err end
        return GDrive.uploadFile(Backup.filename(), body, "application/json")
    end, function()
        notify(_("Đã tải bản sao lưu lên Google Drive."))
    end)
end

function UI.showFolder(folder_id, title)
    online(_("Đang lấy danh sách Google Drive..."), function() return GDrive.list(folder_id) end, function(entries)
        local items = {}
        for _index, entry in ipairs(entries) do
            local current = entry
            if current.folder then
                items[#items + 1] = { text = _("Thư mục:") .. " " .. current.name,
                    keep_menu_open = true, callback = function() UI.showFolder(current.id, current.name) end }
            else
                items[#items + 1] = { text = current.name, mandatory = sizeText(current.size),
                    keep_menu_open = true, callback = function() UI.download(current) end }
            end
        end
        items[#items + 1] = { text = _("Tải lên bản sao lưu & theo dõi"),
            keep_menu_open = true, callback = UI.uploadBackup }
        Catalog.show{ title = title or "Google Drive", items = items }
    end)
end

function UI.open()
    if not GDrive.validClientId(GDrive.clientId()) then
        notify(_("Chưa cấu hình Google client ID. Vào Cài đặt → OneDrive."))
        return
    end
    if not GDrive.hasAuth() and not GDrive.loginInfo() then
        UI.showLogin()
        return
    end
    if not GDrive.hasAuth() then
        UI.showLogin()
        return
    end
    UI.showFolder(nil, "Google Drive")
end

return UI
