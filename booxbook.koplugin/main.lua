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
    Settings.load()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function comingSoon()
    notify(_("Chức năng sẽ có ở bước sau."))
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
    Catalog.show{
        title = _("BooxBook"),
        subtitle = Network.statusText(),
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
                        } }
                    end)
                end,
            },
            {
                text = _("Thư viện"),
                callback = comingSoon,
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

function BooxBook:settingsMenu()
    return {
        {
            text = _("Kiểm tra cài đặt"),
            callback = function()
                self:runSelfTest()
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
    }
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
