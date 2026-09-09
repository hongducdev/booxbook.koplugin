local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Epub = require("booxbook.epub")
local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Network = require("booxbook.network")
local Settings = require("booxbook.store.settings")
local News = require("booxbook.ui.news")
local Novels = require("booxbook.ui.novels")
local Update = require("booxbook.update")

local BooxBook = WidgetContainer:extend{
    name = "booxbook",
    is_doc_only = false,
}

function BooxBook:onDispatcherRegisterActions()
    Dispatcher:registerAction("booxbook_selftest", {
        category = "none",
        event = "BooxBookSelfTest",
        title = _("BooxBook: kiểm tra cài đặt"),
        general = true,
    })
end

function BooxBook:init()
    self.finished_news_path = nil
    Settings.load()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function BooxBook:addToMainMenu(menu_items)
    menu_items.booxbook = {
        text = _("BooxBook"),
        sorting_hint = "tools",
        callback = function(touchmenu)
            if touchmenu then
                touchmenu:closeMenu()
            end
            UIManager:nextTick(function()
                Catalog.clearStack()
                self:showMainMenu()
            end)
        end,
        keep_menu_open = true,
    }
end

function BooxBook:showMainMenu()
    local version = Update.currentVersion()
    Catalog.show{
        title = _("BooxBook"),
        subtitle = Network.statusText(),
        footer_slots = {
            { text = _("Quay lại"), action = "back", enabled = true },
            { text = "v" .. version, enabled = false },
            { text = _("Cập nhật"), action = "update", enabled = true },
            { text = "1/1", enabled = false },
        },
        on_footer = function(action)
            if action == "update" then Update.checkAndPrompt() end
        end,
        items = {
            {
                text = _("Báo"),
                keep_menu_open = true,
                callback = function()
                    UIManager:nextTick(function()
                        Catalog.show{ title = _("Báo"), items = News.menu() }
                    end)
                end,
            },
            {
                text = _("Truyện"),
                keep_menu_open = true,
                callback = function()
                    UIManager:nextTick(function()
                        local function openSangtacviet()
                            require("booxbook.ui.sangtacviet").openSource()
                        end
                        Catalog.show{ title = _("Truyện"), items = {
                            { text = "DocLN", keep_menu_open = true, callback = Novels.openSource },
                            { text = "Wattpad", keep_menu_open = true, callback = function()
                                require("booxbook.ui.wattpad").openSource()
                            end },
                            {
                                text = "Sangtacviet",
                                keep_menu_open = true,
                                callback = function()
                                    if Settings.sangtacvietEnabled() then
                                        openSangtacviet()
                                        return
                                    end
                                    -- Discoverable from Truyện; still requires the first-run warning.
                                    Catalog.confirm(
                                        _("Sangtacviet chứa nhiều bản dịch máy. Chỉ tải trang bạn đã đọc được trên trình duyệt, không phát tán file. Bật nguồn này?"),
                                        function()
                                            Settings.set("stv_warning_accepted", true)
                                            Settings.setSangtacvietEnabled(true)
                                            openSangtacviet()
                                        end
                                    )
                                end,
                            },
                            { text = "MeTruyenCV", keep_menu_open = true, callback = function()
                                require("booxbook.ui.metruyencv").openSource()
                            end },
                            { text = "TVTruyen", keep_menu_open = true, callback = function()
                                require("booxbook.ui.tvtruyen").openSource()
                            end },
                            { text = "Truyện Full", keep_menu_open = true, callback = function()
                                require("booxbook.ui.truyenfull").openSource()
                            end },
                            { text = _("Truyện Tuổi Thơ"), keep_menu_open = true, callback = function()
                                require("booxbook.ui.truyentuoitho").openSource()
                            end },
                            { text = "TruyenQQ", keep_menu_open = true, callback = function()
                                require("booxbook.ui.truyentuoitho").openSource("truyenqq")
                            end },
                            { text = _("Truyện đang theo dõi"), keep_menu_open = true, callback = function()
                                require("booxbook.ui.follow").open()
                            end },
                        } }
                    end)
                end,
            },
            {
                text = _("Sách & cloud"),
                sub_item_table = {
                    { text = _("Thư viện trên máy"), keep_menu_open = true,
                        callback = function() self:showLibrary() end },
                    { text = _("Tìm sách offline"), keep_menu_open = true,
                        callback = function() require("booxbook.ui.library").open() end },
                    { text = "OneDrive", keep_menu_open = true,
                        callback = function() require("booxbook.ui.onedrive").open() end },
                    { text = "Google Drive", keep_menu_open = true,
                        callback = function() require("booxbook.ui.gdrive").open() end },
                },
            },
            {
                text = _("Gửi sách qua Wi-Fi"),
                keep_menu_open = true,
                callback = function() require("booxbook.ui.wifi-transfer").show() end,
            },
            {
                text = _("Cài đặt"),
                callback = function()
                    Catalog.show{ title = _("Cài đặt"), items = self:settingsMenu() }
                end,
            },
        },
    }
end

function BooxBook:stopWifiTransfer()
    local transfer = package.loaded["booxbook.ui.wifi-transfer"]
    if transfer then transfer.stop() end
end

BooxBook.onSuspend = BooxBook.stopWifiTransfer
BooxBook.onExit = BooxBook.stopWifiTransfer
BooxBook.onNetworkDisconnected = BooxBook.stopWifiTransfer
BooxBook.onCloseWidget = BooxBook.stopWifiTransfer

function BooxBook:onReaderReady(config)
    local ui = self.ui
    local path = ui.document and ui.document.file
    if not path or not ui.paging or not ui.zooming then return end
    local ffiUtil = require("ffi/util")
    local root = ffiUtil.realpath(Settings.downloadDir() .. "/comics/truyentuoitho")
    path = ffiUtil.realpath(path)
    if not root or not path or path:sub(1, #root + 1) ~= root .. "/" or not path:match("%.cbz$")
        or config:readSetting("booxbook_comic_page_layout") then return end
    -- Once per book, including files opened from the offline library. Later user
    -- zoom/scroll choices remain theirs; never change global reader preferences.
    ui.view:onSetScrollMode(false)
    ui.zooming:setZoomMode("page", true)
    config:saveSetting("kopt_page_scroll", 0)
    config:saveSetting("zoom_mode", "page")
    config:saveSetting("booxbook_comic_page_layout", true)
end

function BooxBook:onEndOfBook()
    self.finished_news_path = self.ui.document and self.ui.document.file
end

function BooxBook:onCloseDocument()
    require("booxbook.news-cleanup").afterClose(self.ui, self.finished_news_path)
    self.finished_news_path = nil
end

function BooxBook:showLibrary()
    UIManager:nextTick(function()
        local dir = Settings.downloadDir()
        if not Settings.ensureDir(dir) then
            notify(_("Không mở được thư mục tải."))
            return
        end
        local FileManager = require("apps/filemanager/filemanager")
        local ReaderUI = require("apps/reader/readerui")
        Catalog.clearStack()
        if ReaderUI.instance then ReaderUI.instance:onClose() end
        if FileManager.instance then
            FileManager.instance.file_chooser:changeToPath(dir)
        else
            FileManager:showFiles(dir)
        end
    end)
end

function BooxBook:settingsMenu()
    local items = {
        {
            text = _("Phiên bản") .. " " .. Update.currentVersion(),
            select_enabled = false,
        },
        {
            text = _("Cập nhật từ GitHub"),
            callback = function()
                Update.checkAndPrompt()
            end,
        },
        {
            text = _("Kiểm tra cài đặt"),
            callback = function()
                self:runSelfTest()
            end,
        },
        {
            text = _("Lưu truyện thành EPUB"),
            checked_func = function() return Settings.get("novel_epub") == true end,
            callback = function()
                Settings.set("novel_epub", Settings.get("novel_epub") ~= true)
            end,
        },
        {
            text = _("Giữ bản HTML khi lưu EPUB"),
            select_enabled_func = function() return Settings.get("novel_epub") == true end,
            checked_func = function() return Settings.get("novel_keep_html") ~= false end,
            callback = function()
                Settings.set("novel_keep_html", Settings.get("novel_keep_html") == false)
            end,
        },
        {
            text = _("Tự xóa HTML báo sau khi đọc xong"),
            checked_func = function() return Settings.get("news_delete_finished") == true end,
            callback = function()
                Settings.set("news_delete_finished", Settings.get("news_delete_finished") ~= true)
            end,
        },
        {
            text = _("Nội dung 18+"),
            checked_func = function()
                return Settings.adultContent()
            end,
            callback = function()
                Settings.set("adult_content", not Settings.adultContent())
            end,
        },
        {
            text = _("Tải ảnh minh họa"),
            checked_func = function()
                return Settings.includeImages()
            end,
            callback = function()
                Settings.set("include_images", not Settings.includeImages())
            end,
        },
        {
            text = _("Ảnh đã lưu") .. ": " .. BooxBook.storageText(),
            select_enabled = false,
        },
        {
            text = _("Dọn ảnh bìa và ảnh thừa"),
            callback = function()
                Catalog.confirm(_("Xóa ảnh bìa đã lưu, ảnh của bài đã xóa và bản nháp comic quá 7 ngày? Sách/truyện đã tải không bị ảnh hưởng."), function()
                    notify(BooxBook.purgeImageCache())
                end)
            end,
        },
        {
            text = _("Bật Sangtacviet"),
            checked_func = function()
                return Settings.sangtacvietEnabled()
            end,
            callback = function()
                if Settings.sangtacvietEnabled() then
                    Settings.setSangtacvietEnabled(false)
                    return
                end
                Catalog.confirm(
                    _("Sangtacviet chứa nhiều bản dịch máy. Chỉ tải trang bạn đã đọc được trên trình duyệt, không phát tán file. Bật nguồn này?"),
                    function()
                        Settings.set("stv_warning_accepted", true)
                        Settings.setSangtacvietEnabled(true)
                    end
                )
            end,
        },
        {
            text = _("Cookie DocLN"),
            callback = function()
                self:editCookie("docln", _("Cookie DocLN"))
            end,
        },
        {
            text = _("Cookie Wattpad"),
            callback = function()
                self:editCookie("wattpad", _("Cookie Wattpad"))
            end,
        },
        {
            text = _("Cookie Sangtacviet"),
            callback = function()
                self:editCookie("sangtacviet", _("Cookie Sangtacviet"))
            end,
        },
        {
            text = _("Xóa cookie đã lưu"),
            callback = function()
                Catalog.confirm(_("Xóa mọi cookie đã lưu?"), function()
                    Settings.setCookie("docln", "")
                    Settings.setCookie("wattpad", "")
                    Settings.setCookie("sangtacviet", "")
                    notify(_("Đã xóa cookie."))
                end)
            end,
        },
        {
            text = _("Microsoft client ID"),
            callback = function()
                Catalog.promptText{
                    title = _("Microsoft client ID"),
                    hint = _("Application (client) ID của public client"),
                    input = Settings.get("onedrive_client_id") or "",
                    on_submit = function(value)
                        local new_id = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if new_id ~= (Settings.get("onedrive_client_id") or "") then
                            Settings.set("onedrive_client_id", new_id)
                            require("booxbook.onedrive").clearAuth()
                        end
                    end,
                }
            end,
        },
        {
            text = _("Đăng xuất OneDrive"),
            callback = function()
                Catalog.confirm(_("Xóa thông tin đăng nhập OneDrive trên thiết bị này?"), function()
                    require("booxbook.onedrive").clearAuth()
                    notify(_("Đã đăng xuất OneDrive."))
                end)
            end,
        },
        {
            text = _("Google client ID"),
            callback = function()
                Catalog.promptText{
                    title = _("Google client ID"),
                    hint = _("xxx.apps.googleusercontent.com"),
                    input = Settings.get("gdrive_client_id") or "",
                    on_submit = function(value)
                        local new_id = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if new_id ~= (Settings.get("gdrive_client_id") or "") then
                            Settings.set("gdrive_client_id", new_id)
                            require("booxbook.gdrive").clearAuth()
                        end
                    end,
                }
            end,
        },
        {
            text = _("Sao lưu cài đặt"),
            callback = function()
                local Backup = require("booxbook.backup")
                local body = Backup.export(function(key) return Settings.get(key) end)
                if not body then notify(_("Không sao lưu được.")); return end
                local dir = Settings.downloadDir() .. "/received"
                if not Settings.ensureDir(dir) then notify(_("Không mở được thư mục tải.")); return end
                local path = dir .. "/" .. Backup.filename()
                local file = io.open(path, "wb")
                if not file then notify(_("Không ghi được file sao lưu.")); return end
                file:write(body)
                file:close()
                notify(_("Đã sao lưu: ") .. path)
            end,
        },
        {
            text = _("Tạo digest báo (EPUB)"),
            callback = function()
                require("booxbook.ui.digest").open()
            end,
        },
        {
            text = _("Đăng xuất Google Drive"),
            callback = function()
                Catalog.confirm(_("Xóa thông tin đăng nhập Google Drive trên thiết bị này?"), function()
                    require("booxbook.gdrive").clearAuth()
                    notify(_("Đã đăng xuất Google Drive."))
                end)
            end,
        },
    }
    return {
        { text = _("Đọc và tải"), sub_item_table = { items[4], items[5], items[6], items[7], items[8] } },
        { text = _("Bộ nhớ"), sub_item_table = { items[9], items[10] } },
        { text = _("Nguồn và cookie"), sub_item_table = {
            items[11], items[12], items[13], items[14], items[15],
        } },
        { text = _("OneDrive"), sub_item_table = { items[16], items[17], items[18], items[21] } },
        { text = _("Hệ thống"), sub_item_table = { items[1], items[2], items[3], items[19], items[20] } },
    }
end

local function formatBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%d KB", math.floor(bytes / 1024))
    end
    return tostring(bytes) .. " B"
end

function BooxBook.storageText()
    -- Menu build must stay light and dependency-free: Covers pulls Http,
    -- which may be stubbed in tests. Measure through Storage only.
    local ok_storage, Storage = pcall(require, "booxbook.store.storage")
    local ok_dir, root = pcall(function() return Settings.downloadDir() .. "/covers" end)
    if not ok_storage or not Storage or not ok_dir then return "?" end
    local ok_use, bytes = pcall(Storage.treeSize, root)
    if not ok_use then return "?" end
    return formatBytes(bytes)
end

function BooxBook.purgeImageCache()
    local ok, Covers = pcall(require, "booxbook.covers")
    local cleared = false
    if ok and Covers and Covers.clear then
        local ok_clear, result = pcall(Covers.clear)
        cleared = ok_clear and result == true
    end
    local swept_news, swept_comics = 0, 0
    local ok_storage, Storage = pcall(require, "booxbook.store.storage")
    if ok_storage and Storage then
        local ok_sweep, swept = pcall(Storage.sweepOrphanSidecars, Settings.downloadDir() .. "/news")
        swept_news = (ok_sweep and tonumber(swept)) or 0
    end
    local ok_dl, Download = pcall(require, "booxbook.comic-download")
    if ok_dl and Download and Download.sweepStale then
        local ok_sweep, swept = pcall(Download.sweepStale, 7)
        swept_comics = (ok_sweep and tonumber(swept)) or 0
    end
    return (cleared and _("Đã xóa ảnh bìa") or _("Không xóa được ảnh bìa"))
        .. " · " .. tostring(swept_news) .. " " .. _("thư mục ảnh thừa")
        .. " · " .. tostring(swept_comics) .. " " .. _("bản nháp comic cũ")
end

function BooxBook:editCookie(source_id, title)
    Catalog.promptText({
        title = title,
        hint = _("dán cookie, để trống để xóa"),
        input = "",
        on_submit = function(text)
            Settings.setCookie(source_id, text)
            if text == nil or text == "" then
                notify(_("Đã xóa cookie."))
            else
                notify(_("Đã lưu cookie (không hiện lại giá trị)."))
            end
        end,
    })
end

function BooxBook:runSelfTest()
    Network.whenOnline(function()
        self:performSelfTest()
    end)
end

function BooxBook:onBooxBookSelfTest()
    self:runSelfTest()
    return true
end

function BooxBook:performSelfTest()
    local ok, code = Http.get("https://example.com", {
        referer = "https://booxbook.local/",
        delay_ms = 0,
    })
    local dir = Settings.downloadDir()
    local html_path = dir .. "/_selftest.html"
    local body = Html.wrapDocument("Kiểm tra BooxBook", "<p>Tiếng Việt</p><p>BooxBook selftest.</p>")
    local html_ok, html_err = Html.writeFile(html_path, body)

    local epub_path = dir .. "/_selftest.epub"
    local epub_ok, epub_err = Epub.write(epub_path, {
        title = "Kiểm tra BooxBook",
        chapters = {
            { title = "Tiếng Việt", html = "<p>Tiếng Việt</p>" },
        },
    })

    local lines = {
        _("HTTP:") .. " " .. (ok and _("OK") or tostring(code)),
        _("HTML:") .. " " .. (html_ok and html_path or tostring(html_err)),
        _("EPUB:") .. " " .. (epub_ok and epub_path or tostring(epub_err)),
    }
    notify(table.concat(lines, "\n"))
end

return BooxBook
