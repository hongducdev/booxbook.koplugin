local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Library = require("booxbook.library")
local Settings = require("booxbook.store.settings")

local UI = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = tostring(text) })
end

function UI.openBook(path)
    if not path or path == "" then return end
    UIManager:nextTick(function()
        Catalog.clearStack()
        ReaderUI:showReader(path)
    end)
end

function UI.openFileManager()
    local dir = Settings.downloadDir()
    if not Settings.ensureDir(dir) then
        notify(_("Không mở được thư mục tải."))
        return
    end
    UIManager:nextTick(function()
        local FileManager = require("apps/filemanager/filemanager")
        Catalog.clearStack()
        if ReaderUI.instance then ReaderUI.instance:onClose() end
        if FileManager.instance then
            FileManager.instance.file_chooser:changeToPath(dir)
        else
            FileManager:showFiles(dir)
        end
    end)
end

function UI.searchPrompt(default_query)
    Catalog.promptText{
        title = _("Tìm sách offline"),
        hint = _("Nhập tên sách, truyện hoặc tác giả..."),
        input = default_query or "",
        on_submit = function(value)
            UI.showSearchResults(value)
        end,
    }
end

function UI.showSearchResults(query)
    local root = Settings.downloadDir()
    local files = Library.collect(root)
    local filtered = Library.filter(files, query)
    table.sort(filtered, function(a, b)
        return (tonumber(a.mtime) or 0) > (tonumber(b.mtime) or 0)
    end)

    local q_clean = (query or ""):match("^%s*(.-)%s*$")
    local title = _("Tìm sách offline")
    local subtitle
    if q_clean == "" then
        title = _("Tất cả sách trên máy")
        subtitle = string.format(_("%d file · Mới nhất trước"), #filtered)
    else
        subtitle = string.format(_("Từ khóa: \"%s\" · %d kết quả"), q_clean, #filtered)
    end

    local items = {}
    for i = 1, math.min(100, #filtered) do
        local book = filtered[i]
        items[#items + 1] = {
            text = book.title or book.name,
            mandatory = Library.formatBytes(book.size),
            keep_menu_open = true,
            callback = function()
                UI.openBook(book.path)
            end,
        }
    end

    if #filtered == 0 then
        items[#items + 1] = {
            text = _("Không tìm thấy sách nào phù hợp."),
            select_enabled = false,
        }
        items[#items + 1] = {
            text = _("Thử tìm từ khóa khác"),
            keep_menu_open = true,
            callback = function()
                UI.searchPrompt(query)
            end,
        }
    end

    Catalog.show{
        title = title,
        subtitle = subtitle,
        on_search = function() UI.searchPrompt(query) end,
        items = items,
    }
end

function UI.showFileList(title, files)
    local sorted = {}
    for i, f in ipairs(files or {}) do sorted[#sorted + 1] = f end
    table.sort(sorted, function(a, b)
        return (tonumber(a.mtime) or 0) > (tonumber(b.mtime) or 0)
    end)

    local items = {}
    for i, book in ipairs(sorted) do
        local current = book
        items[#items + 1] = {
            text = current.name or current.title,
            mandatory = Library.formatBytes(current.size),
            keep_menu_open = true,
            callback = function()
                UI.openBook(current.path)
            end,
        }
    end

    if #items == 0 then
        items[#items + 1] = {
            text = _("Không có file nào."),
            select_enabled = false,
        }
    end

    Catalog.show{
        title = title,
        subtitle = string.format(_("%d file"), #sorted),
        on_search = function() UI.searchPrompt() end,
        items = items,
    }
end

local function groupSeries(items)
    local series_map = {}
    local series_order = {}
    for i, item in ipairs(items or {}) do
        local s = (item.series and item.series ~= "") and item.series or _("Truyện khác")
        if not series_map[s] then
            series_map[s] = {}
            series_order[#series_order + 1] = s
        end
        local list = series_map[s]
        list[#list + 1] = item
    end
    return series_map, series_order
end

function UI.showNovels(novels)
    local series_map, series_order = groupSeries(novels)
    local items = {}
    for i, series_name in ipairs(series_order) do
        local list = series_map[series_name]
        local count = #list
        local current_series = series_name
        local current_list = list
        items[#items + 1] = {
            text = current_series,
            mandatory = string.format(_("%d chương/file"), count),
            keep_menu_open = true,
            callback = function()
                UI.showFileList(current_series, current_list)
            end,
        }
    end

    if #items == 0 then
        items[#items + 1] = {
            text = _("Chưa có truyện chữ nào được tải."),
            select_enabled = false,
        }
    end

    Catalog.show{
        title = _("Truyện chữ đã tải"),
        subtitle = string.format(_("%d bộ truyện · %d file"), #series_order, #novels),
        on_search = function() UI.searchPrompt() end,
        items = items,
    }
end

function UI.showComics(comics)
    local series_map, series_order = groupSeries(comics)
    local items = {}
    for i, series_name in ipairs(series_order) do
        local list = series_map[series_name]
        local count = #list
        local current_series = series_name
        local current_list = list
        items[#items + 1] = {
            text = current_series,
            mandatory = string.format(_("%d tập"), count),
            keep_menu_open = true,
            callback = function()
                UI.showFileList(current_series, current_list)
            end,
        }
    end

    if #items == 0 then
        items[#items + 1] = {
            text = _("Chưa có truyện tranh nào được tải."),
            select_enabled = false,
        }
    end

    Catalog.show{
        title = _("Truyện tranh đã tải"),
        subtitle = string.format(_("%d bộ truyện · %d tập"), #series_order, #comics),
        on_search = function() UI.searchPrompt() end,
        items = items,
    }
end

function UI.showCategories()
    local root = Settings.downloadDir()
    local files = Library.collect(root)
    local summary = Library.summarize(files)

    local novels = {}
    local comics = {}
    local received = {}
    local news = {}
    local other = {}

    for i, file in ipairs(files) do
        if file.category == "novels" then
            novels[#novels + 1] = file
        elseif file.category == "comics" then
            comics[#comics + 1] = file
        elseif file.category == "received" then
            received[#received + 1] = file
        elseif file.category == "news" then
            news[#news + 1] = file
        else
            other[#other + 1] = file
        end
    end

    local quota = string.format(_("Tổng: %d file · %s"), summary.count, Library.formatBytes(summary.bytes))
    local items = {
        {
            text = _("Tìm sách offline"),
            keep_menu_open = true,
            callback = function()
                UI.searchPrompt()
            end,
        },
    }

    if #novels > 0 then
        items[#items + 1] = {
            text = string.format(_("Truyện chữ (%d)"), #novels),
            keep_menu_open = true,
            callback = function()
                UI.showNovels(novels)
            end,
        }
    end

    if #comics > 0 then
        items[#items + 1] = {
            text = string.format(_("Truyện tranh (%d)"), #comics),
            keep_menu_open = true,
            callback = function()
                UI.showComics(comics)
            end,
        }
    end

    if #received > 0 then
        items[#items + 1] = {
            text = string.format(_("Sách đã nhận (%d)"), #received),
            keep_menu_open = true,
            callback = function()
                UI.showFileList(_("Sách đã nhận"), received)
            end,
        }
    end

    if #news > 0 then
        items[#items + 1] = {
            text = string.format(_("Báo & Tin tức đã lưu (%d)"), #news),
            keep_menu_open = true,
            callback = function()
                UI.showFileList(_("Báo & Tin tức đã lưu"), news)
            end,
        }
    end

    if #other > 0 then
        items[#items + 1] = {
            text = string.format(_("File khác (%d)"), #other),
            keep_menu_open = true,
            callback = function()
                UI.showFileList(_("File khác"), other)
            end,
        }
    end

    if #files == 0 then
        items[#items + 1] = {
            text = _("Chưa có sách hoặc báo nào được tải."),
            select_enabled = false,
        }
    end

    items[#items + 1] = {
        text = _("Mở trong Trình quản lý file"),
        keep_menu_open = true,
        callback = function()
            UI.openFileManager()
        end,
    }

    Catalog.show{
        title = _("Thư mục trên máy"),
        subtitle = quota,
        on_search = function() UI.searchPrompt() end,
        items = items,
    }
end

function UI.open(query)
    if type(query) == "string" and query:match("%S") then
        UI.showSearchResults(query)
    else
        UI.showCategories()
    end
end

return UI
