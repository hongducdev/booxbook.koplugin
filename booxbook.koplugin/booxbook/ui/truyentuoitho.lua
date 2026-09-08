local Catalog = require("booxbook.ui.catalog")
local Download = require("booxbook.comic-download")
local Network = require("booxbook.network")
local Settings = require("booxbook.store.settings")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local Source = require("booxbook.sources.truyentuoitho")
local SeriesUI = require("booxbook.ui.series")
local _ = require("gettext")
local UI, busy = {}, false

local function notify(text) UIManager:show(InfoMessage:new{ text = tostring(text) }) end
local function open(path)
    UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(path) end)
end

local function online(message, action, done)
    UIManager:nextTick(function()
        Network.whenOnline(function()
            if busy then notify(_("Đang tải, vui lòng chờ.")); return end
            busy = true
            Trapper:wrap(function()
                local ok, result, err = pcall(function() Trapper:info(message); return action() end)
                busy = false
                Trapper:clear()
                if not ok or not result then notify(ok and err or result); return end
                UIManager:nextTick(function() done(result) end)
            end)
        end)
    end)
end

function UI.download(url)
    local path, err = Download.savedPath(url)
    if path then open(path); return end
    if err then notify(err); return end
    online(_("Đang lấy tập Truyện Tuổi Thơ…"), function()
        local result, chapter_err, partial = Download.chapter(url, function(i, count, packing)
            return Trapper:info(string.format(packing and _("Đóng gói CBZ: %d/%d — chạm để hủy")
                or _("Tải ảnh: %d/%d — chạm để hủy"), i, count))
        end)
        if not result and Download.isCancelErr(chapter_err) then
            return { cancelled = true, err = chapter_err, partial = partial, url = url }
        end
        if not result then return nil, chapter_err end
        return result
    end, function(result)
        if type(result) == "table" and result.cancelled then
            UI.onChapterCancelled(result.url, result.partial)
            return
        end
        Catalog.clearStack(); ReaderUI:showReader(result)
    end)
end

function UI.promptSearch()
    Catalog.promptText{ title = _("Tìm truyện hoặc nhập URL Truyện Tuổi Thơ"),
        input = Settings.get("truyentuoitho_last_url") or "",
        hint = _("Tên truyện, URL bộ truyện hoặc URL một tập"),
        ok_text = _("Tìm / mở"),
        on_submit = function(url)
            url = (url or ""):match("^%s*(.-)%s*$")
            if url == "" then return end
            if Source.parseRef(url) then
                Settings.set("truyentuoitho_last_url", url); UI.download(url)
            elseif Source.parseSeriesRef(url) then UI.showSeries(url)
            elseif url:match("^https?://") then notify(_("URL Truyện Tuổi Thơ không hợp lệ."))
            else UI.list(nil, url) end
        end }
end

function UI.list(kind, query, page, grid, last_screen)
    page = page or 1
    online(_("Đang tải danh sách truyện…"), function()
        if query then return Source.search(query, page) end
        return Source.browse(kind, page)
    end, function(result)
        if grid and grid._closed then return end
        local CoverGrid = require("booxbook.ui.cover-grid")
        local items, size = result.items or {}, CoverGrid.PAGE_SIZE
        local offset = last_screen and math.floor(math.max(0, #items - 1) / size) * size + 1 or 1
        local payload = { title = "Truyện Tuổi Thơ" .. (query and (" — " .. query) or ""),
            items = items, offset = offset, site_page = page, has_more = result.has_more,
            source_id = Source.id, base_url = "https://truyentuoitho.com",
            cover_referer = "https://truyentuoitho.com/", cover_delay_ms = 1600,
            on_search = UI.promptSearch, on_select = UI.showSeries }
        if grid then grid:setPage(payload) else grid = CoverGrid.show(payload) end
        local function turn(direction)
            if grid._closed then return end
            local next_offset = offset + direction * size
            if next_offset >= 1 and next_offset <= #items then
                offset = next_offset; grid:setPage{ offset = offset }
            elseif direction > 0 and result.has_more then UI.list(kind, query, page + 1, grid)
            elseif direction < 0 and page > 1 then UI.list(kind, query, page - 1, grid, true) end
        end
        grid.on_next, grid.on_prev = function() turn(1) end, function() turn(-1) end
        if #items == 0 then notify(_("Không tìm thấy truyện phù hợp.")) end
    end)
end

function UI.showOffline(series)
    local items = {}
    for _, chapter in ipairs(series.chapters) do
        local current = chapter
        local path = Download.path(current)
        local file = path and io.open(path, "rb")
        if file then
            file:close()
            items[#items + 1] = { text = current.title, mandatory = tostring(current.index),
                keep_menu_open = true, callback = function() UI.download(current.url) end }
        end
    end
    if #items == 0 then notify(_("Chưa có tập đã tải.")); return end
    Catalog.show{ title = _("Tập đã tải (offline)"), items = items }
end

function UI.downloadRange(series, first, last)
    online(_("Đang tải tập truyện…"), function()
        return Download.range(series, first, last, function(n, count, chapter, i, total, packing)
            return Trapper:info(string.format(_("Tập %d/%d: %s\n%s %d/%d — chạm để hủy"),
                n, count, chapter.title, packing and _("Đóng gói") or _("Tải ảnh"), i, total))
        end)
    end, function(result)
        if result.cancelled and result.partial_url then
            UI.onChapterCancelled(result.partial_url, result.partial, function()
                if #result.saved > 0 then UI.showOffline(series) end
            end)
            return
        end
        if #result.saved > 0 then UI.showOffline(series) end
        if result.error then
            if result.cancelled then
                notify(string.format(_("Đã hủy tải; đã giữ %d tập để tải tiếp."), #result.saved))
            else
                notify(_("Đã dừng tải: ") .. tostring(result.error))
            end
        end
    end)
end

-- Popup after a cancelled comic download: package partial CBZ or keep staging.
-- Confirm first; list/toast wait until the user answers.
function UI.onChapterCancelled(url, partial, after)
    local pages = partial and partial.downloaded
    if pages == nil then
        local staged = Download.stagingPages(url)
        pages = staged and #staged or 0
    end
    if not pages or pages <= 0 then
        notify(_("Đã hủy tải; chưa có ảnh nào được lưu."))
        if after then after() end
        return
    end
    local total = (partial and partial.total) or pages
    local function keepImages()
        notify(string.format(_("Đã hủy tải; đã giữ %d ảnh để tải tiếp."), pages))
        if after then after() end
    end
    Catalog.confirm(
        string.format(_("Đã hủy tải. Đóng gói CBZ với %d/%d ảnh đã tải?"), pages, total),
        function()
            local packed, err = Download.packageStaging(url)
            if not packed then
                notify(tostring(err or _("Không đóng gói được CBZ partial; đã giữ ảnh để tải tiếp.")))
            else
                notify(string.format(_("Đã đóng gói CBZ với %d ảnh đã tải."), pages))
                open(packed)
            end
            if after then after() end
        end,
        { ok_text = _("Đóng gói"), cancel_text = _("Giữ ảnh"), cancel_callback = keepImages }
    )
end

function UI.showSeries(ref)
    online(_("Đang lấy mục lục…"), function() return Source.getSeries(ref) end, function(series)
        local total = #series.chapters
        SeriesUI.show(series, {
            unit = _("tập"), Unit = _("Tập"),
            on_info = function()
                local TextViewer = require("ui/widget/textviewer")
                UIManager:show(TextViewer:new{ title = series.title, text = series.description or "" })
            end,
            on_go = function(n) UI.download(series.chapters[n].url) end,
            on_chapter = function(chapter) UI.download(chapter.url) end,
            on_range = function()
                SeriesUI.askRange(total, function(first, last)
                    Catalog.confirm(string.format(_("Tải %d tập CBZ? Mỗi tập có thể chiếm hàng trăm MB."), last - first + 1),
                        function() UI.downloadRange(series, first, last) end)
                end)
            end,
            on_download_all = function()
                Catalog.confirm(string.format(_("Tải toàn bộ %d tập CBZ? Có thể mất nhiều thời gian và dung lượng."), total),
                    function() UI.downloadRange(series, 1, total) end)
            end,
            on_offline = function() UI.showOffline(series) end,
        })
    end)
end

function UI.openOffline()
    local dir = Settings.downloadDir() .. "/comics/truyentuoitho"
    if not Settings.ensureDir(dir) then notify(_("Không mở được thư mục truyện.")); return end
    UIManager:nextTick(function()
        Catalog.clearStack()
        local FileManager = require("apps/filemanager/filemanager")
        if ReaderUI.instance then ReaderUI.instance:onClose() end
        if FileManager.instance then FileManager.instance.file_chooser:changeToPath(dir)
        else FileManager:showFiles(dir) end
    end)
end

function UI.openSource()
    Catalog.show{ title = "Truyện Tuổi Thơ", on_search = UI.promptSearch, items = {
        { text = _("Tìm truyện / nhập URL"), callback = UI.promptSearch },
        { text = _("Mới cập nhật"), callback = function() UI.list("latest") end },
        { text = _("Lượt xem"), callback = function() UI.list("popular") end },
        { text = _("Truyện mới"), callback = function() UI.list("new") end },
        { text = _("Thịnh hành"), callback = function() UI.list("trending") end },
        { text = _("Truyện đã tải (offline)"), callback = UI.openOffline },
    } }
end

return UI
