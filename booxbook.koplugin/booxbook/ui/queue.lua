local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Http = require("booxbook.http")
local Network = require("booxbook.network")
local Queue = require("booxbook.queue")
local Settings = require("booxbook.store.settings")
local Upload = require("booxbook.wifi-upload")

local UI = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function queuePath()
    return Queue.path(Settings.downloadDir() .. "/received")
end

local function uniqueTarget(dir, name)
    local stem, extension = name:match("^(.*)(%.[^.]+)$")
    if not stem then return nil end
    local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local exists = function(path)
        if lfs_ok and lfs and lfs.symlinkattributes then
            return lfs.symlinkattributes(path) ~= nil
        end
        local file = io.open(path, "rb")
        if file then file:close(); return true end
        return false
    end
    for suffix = 0, 999 do
        local candidate = suffix == 0 and name or stem .. " (" .. suffix .. ")" .. extension
        local target, pending = dir .. "/" .. candidate, dir .. "/." .. candidate .. ".part"
        if not exists(target) and not exists(pending) then return target, pending end
    end
end

function UI.download(url)
    local raw = tostring(url or ""):match("^%s*(.-)%s*$")
    local name = Upload.safeFilename(raw:match("/([^/?#]+)$") or "")
    if not name then
        notify(_("Link này không phải file sách hỗ trợ trực tiếp. Mở bằng trình duyệt để tải."))
        return
    end
    Catalog.confirm(_("Tải về thư viện?") .. "\n" .. name, function()
        UIManager:nextTick(function()
            Network.whenOnline(function()
                Trapper:wrap(function()
                    Trapper:info(_("Đang tải: ") .. name)
                    local dir = Settings.downloadDir() .. "/received"
                    local target, pending
                    if Settings.ensureDir(dir) then
                        target, pending = uniqueTarget(dir, name)
                    end
                    local ok, result, err
                    if target then
                        ok, result = Http.downloadToFile(raw, pending,
                            { max_body = Upload.MAX_BYTES, delay_ms = 0 })
                    end
                    Trapper:clear()
                    if not target then
                        notify(_("Không tạo được chỗ lưu (trùng tên hoặc thiếu thư mục)."))
                        return
                    end
                    if not ok then
                        os.remove(pending)
                        notify(_("Không tải được: ") .. tostring(result))
                        return
                    end
                    if not os.rename(pending, target) then
                        os.remove(pending)
                        notify(_("Không lưu được sách vào thư viện."))
                        return
                    end
                    Queue.remove(queuePath(), url)
                    notify(_("Đã tải sách:") .. "\n" .. target)
                    UIManager:nextTick(function() UI.open() end)
                end)
            end)
        end)
    end)
end

function UI.open()
    local path = queuePath()
    local items = Queue.read(path)
    local rows = {
        { text = string.format(_("Hàng đợi Wi-Fi: %d link"), #items), select_enabled = false },
    }
    -- NOTE: never name the loop index `_` here; it would shadow gettext `_()`.
    for _index, url in ipairs(items) do
        local current = url
        local short = #current > 60 and (current:sub(1, 57) .. "...") or current
        rows[#rows + 1] = { text = short, keep_menu_open = true, callback = function()
            Catalog.show{ title = _("Link trong hàng đợi"), items = {
                { text = _("Tải file này"), keep_menu_open = true,
                    callback = function() UI.download(current) end },
                { text = _("Xóa link này"), keep_menu_open = true, callback = function()
                    Queue.remove(path, current)
                    notify(_("Đã xóa link."))
                    UIManager:nextTick(function() UI.open() end)
                end },
            } }
        end }
    end
    if #items > 0 then
        rows[#rows + 1] = { text = _("Xóa toàn bộ hàng đợi"), keep_menu_open = true, callback = function()
            Catalog.confirm(_("Xóa mọi link trong hàng đợi?"), function()
                Queue.clear(path)
                notify(_("Đã xóa hàng đợi."))
                UIManager:nextTick(function() UI.open() end)
            end)
        end }
    else
        rows[#rows + 1] = { text = _("Hàng đợi trống. Gửi link từ trang web Wi-Fi (form hàng đợi)."),
            select_enabled = false }
    end
    Catalog.show{ title = _("Hàng đợi Wi-Fi"), items = rows }
end

return UI
