local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Catalog = require("booxbook.ui.catalog")
local Docln = require("booxbook.sources.docln")
local Download = require("booxbook.novel-download")
local Network = require("booxbook.network")
local SeriesUI = require("booxbook.ui.series")
local Settings = require("booxbook.store.settings")

local Novels = {}
local busy = false
local PAGE_SIZE = 6
local session = {
    mode = "browse", -- browse | search
    kind = "latest",
    query = nil,
    site_page = 1,
    offset = 1,
    items = {},
    has_more = false,
    grid = nil,
}

local function CoverGrid()
    return require("booxbook.ui.cover-grid")
end

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function online(message, action, done)
    UIManager:nextTick(function()
        Network.whenOnline(function()
            if busy then notify(_("Đang tải DocLN, vui lòng chờ.")); return end
            busy = true
            Trapper:wrap(function()
                local ok, result, err
                local wrapped_ok, wrapped_err = pcall(function()
                    Trapper:info(message)
                    ok, result, err = pcall(action)
                end)
                busy = false
                Trapper:clear()
                if not wrapped_ok then
                    notify(tostring(wrapped_err))
                    return
                end
                if not ok or not result then notify(tostring(ok and err or result)); return end
                UIManager:nextTick(function() done(result) end)
            end)
        end)
    end)
end

local function dropClosedGrid()
    if session.grid and session.grid._closed then
        session.grid = nil
    end
end

local function gridTitle()
    if session.mode == "search" then
        return string.format("DocLN — %s", session.query or "")
    end
    if session.kind == "popular" then
        return _("DocLN — Lượt xem")
    end
    return _("DocLN — Mới cập nhật")
end

local function applyPage(result, site_page, offset)
    session.site_page = site_page
    session.offset = offset or 1
    session.items = result.items or {}
    session.has_more = not not result.has_more
    local home = Settings.get("docln_home") or "https://docln.net"
    local payload = {
        title = gridTitle(),
        items = session.items,
        has_more = session.has_more,
        site_page = session.site_page,
        offset = session.offset,
        source_id = "docln",
        base_url = home,
        cover_referer = home .. "/",
        cover_cookies = Settings.cookie("docln"),
    }
    dropClosedGrid()
    if session.grid and not session.grid._closed then
        session.grid:setPage(payload)
    else
        session.grid = CoverGrid().show{
            title = payload.title,
            items = payload.items,
            has_more = payload.has_more,
            site_page = payload.site_page,
            offset = payload.offset,
            source_id = payload.source_id,
            base_url = payload.base_url,
            cover_referer = payload.cover_referer,
            cover_cookies = payload.cover_cookies,
            on_select = function(item) Novels.showSeries(item) end,
            on_search = function() Novels.promptSearch() end,
            on_next = function() Novels.nextPage() end,
            on_prev = function() Novels.prevPage() end,
            on_close = function() session.grid = nil end,
        }
    end
end

local function fetchList(site_page, offset)
    online(_("Đang tải danh sách truyện…"), function()
        if session.mode == "search" then
            return Docln.search(session.query, site_page)
        end
        return Docln.browse(session.kind, site_page)
    end, function(result)
        if #(result.items or {}) == 0 and site_page == 1 then
            notify(_("Không tìm thấy truyện phù hợp."))
            return
        end
        applyPage(result, site_page, offset)
    end)
end

function Novels.download(series, first, last, confirmed, open_after)
    if last - first + 1 > 50 and not confirmed then
        Catalog.confirm(_("Tải hơn 50 chương có thể mất nhiều thời gian. Tiếp tục?"), function()
            Novels.download(series, first, last, true, open_after)
        end)
        return
    end
    online(_("Đang tải chương…"), function()
        return Download.range(series, first, last, confirmed, function(number, total, chapter)
            return Trapper:info(string.format(_("Đang tải %d/%d: %s — chạm để hủy"), number, total, chapter.title))
        end)
    end, function(result)
        if result.cancelled then
            Novels.onCancelled(series, first, result, open_after)
            return
        end
        local existing = result.existing or {}
        if open_after and not result.error and (#result.saved > 0 or #existing > 0) then
            local path = (#result.saved > 0 and result.saved[1] or existing[1]).path
            UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(path) end)
            return
        end
        local items = {}
        for position, saved in ipairs(result.saved) do
            local current = saved
            items[#items + 1] = { text = current.title, keep_menu_open = true, callback = function()
                UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(current.path) end)
            end }
        end
        for position, skipped in ipairs(result.skipped) do
            items[#items + 1] = { text = skipped.title .. ": " .. skipped.reason, select_enabled = false }
        end
        if #items > 0 then Catalog.show{ title = _("Chương đã tải / bỏ qua"), items = items } end
        if #existing > 0 then
            notify(string.format(_("Đã bỏ qua %d chương đã có."), #existing))
        end
        if result.error then notify(_("Đã dừng tải: ") .. tostring(result.error)) end
    end)
end

local function showSaved(result)
    local items = {}
    for _, saved in ipairs(result.saved or {}) do
        local current = saved
        items[#items + 1] = { text = current.title, keep_menu_open = true, callback = function()
            UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(current.path) end)
        end }
    end
    for _, skipped in ipairs(result.skipped or {}) do
        items[#items + 1] = { text = skipped.title .. ": " .. skipped.reason, select_enabled = false }
    end
    if #items > 0 then Catalog.show{ title = _("Chương đã tải / bỏ qua"), items = items } end
end

function Novels.packageSaved(series, first, last)
    online(_("Đang tạo EPUB…"), function()
        return Download.packageSaved(series, first, last)
    end, function(result)
        if result.error then
            notify(_("Không tạo được EPUB: ") .. tostring(result.error))
            return
        end
        local epub = result.saved and result.saved[1]
        if not epub or not epub.path:match("%.epub$") then
            notify(_("Không tạo được EPUB."))
            return
        end
        Catalog.show{ title = _("EPUB đã tạo"), items = { {
            text = epub.title,
            keep_menu_open = true,
            callback = function()
                UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(epub.path) end)
            end,
        } } }
        if #(result.skipped or {}) > 0 then
            notify(string.format(_("Đã bỏ qua %d chương chưa có HTML."), #result.skipped))
        end
    end)
end

-- Popup after a cancelled novel download: package EPUB partial or keep HTML.
-- Confirm first; the chapter list/toast wait until the user answers so they
-- are not covered by a fullscreen menu.
function Novels.onCancelled(series, first, result, open_after)
    result = result or { saved = {}, skipped = {} }
    local saved_count = #(result.saved or {})
    if saved_count == 0 then
        notify(_("Đã hủy tải; chưa có chương nào được lưu."))
        return
    end
    local last_partial = first
    for _, saved in ipairs(result.saved) do
        if type(saved.number) == "number" and saved.number > last_partial then
            last_partial = saved.number
        end
    end
    local function keepHtml()
        showSaved(result)
        notify(string.format(_("Đã hủy tải; đã giữ %d chương HTML để tải tiếp."), saved_count))
    end
    if Settings.get("novel_epub") ~= true then
        keepHtml()
        return
    end
    Catalog.confirm(
        string.format(_("Đã hủy tải. Đóng gói EPUB với %d chương đã tải (%d–%d)? HTML được giữ để tải tiếp."),
            saved_count, first, last_partial),
        function()
            local partial, err = Download.packagePartial(series, first, last_partial, result.saved)
            if not partial then
                showSaved(result)
                notify(tostring(err or _("Không đóng gói được EPUB partial.")))
                return
            end
            if partial.error then
                showSaved(result)
                notify(tostring(partial.error))
                return
            end
            showSaved(partial)
            notify(string.format(_("Đã đóng gói EPUB với %d chương đã tải."), saved_count))
            if open_after and partial.saved[1] then
                local path = partial.saved[1].path
                UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(path) end)
            end
        end,
        { ok_text = _("Đóng gói"), cancel_text = _("Giữ HTML"), cancel_callback = keepHtml }
    )
end

function Novels.showOffline(series)
    local list, err = Download.savedList(series)
    if not list then
        notify(tostring(err or _("Không đọc được danh sách offline.")))
        return
    end
    if #list == 0 then
        notify(_("Chưa có chương đã tải."))
        return
    end
    local items = {}
    for _, saved in ipairs(list) do
        local current = saved
        items[#items + 1] = {
            text = current.title,
            mandatory = current.number and tostring(current.number) or nil,
            keep_menu_open = true,
            callback = function()
                UIManager:nextTick(function()
                    Catalog.clearStack()
                    ReaderUI:showReader(current.path)
                end)
            end,
        }
    end
    Catalog.show{ title = _("Chương đã tải (offline)"), items = items }
end

function Novels.showSeries(ref, adapter)
    online(_("Đang lấy mục lục…"), function() return (adapter or Docln).getSeries(ref) end, function(series)
        local total = #(series.chapters or {})
        SeriesUI.show(series, {
            on_go = function(number) Novels.download(series, number, number, false, true) end,
            on_chapter = function(chapter) Novels.download(series, chapter.index, chapter.index) end,
            on_range = function()
                SeriesUI.askRange(total, function(first, last) Novels.download(series, first, last) end)
            end,
            on_download_all = function()
                Catalog.confirm(
                    string.format(_("Tải toàn bộ %d chương? Có thể mất nhiều thời gian (rate-limit / captcha)."), total),
                    function() Novels.download(series, 1, total) end
                )
            end,
            on_package = function()
                SeriesUI.askRange(total, function(first, last)
                    Novels.packageSaved(series, first, last)
                end, _("Đóng gói"))
            end,
            on_offline = function() Novels.showOffline(series) end,
            follow_label = require("booxbook.ui.follow").followLabel(series),
            on_follow = function() require("booxbook.ui.follow").toggle(series) end,
        })
    end)
end

function Novels.nextPage()
    dropClosedGrid()
    local page_size = PAGE_SIZE
    if session.offset + page_size <= #session.items then
        session.offset = session.offset + page_size
        if session.grid and not session.grid._closed then
            session.grid:setPage{ offset = session.offset, items = session.items,
                has_more = session.has_more, site_page = session.site_page, title = gridTitle() }
        end
        return
    end
    if session.has_more then
        fetchList(session.site_page + 1, 1)
        return
    end
    notify(_("Hết danh sách."))
end

function Novels.prevPage()
    dropClosedGrid()
    local page_size = PAGE_SIZE
    if session.offset > 1 then
        session.offset = math.max(1, session.offset - page_size)
        if session.grid and not session.grid._closed then
            session.grid:setPage{ offset = session.offset, items = session.items,
                has_more = session.has_more, site_page = session.site_page, title = gridTitle() }
        end
        return
    end
    if session.site_page > 1 then
        online(_("Đang tải danh sách truyện…"), function()
            if session.mode == "search" then
                return Docln.search(session.query, session.site_page - 1)
            end
            return Docln.browse(session.kind, session.site_page - 1)
        end, function(result)
            local count = #(result.items or {})
            local offset = 1
            if count > page_size then
                offset = math.floor((count - 1) / page_size) * page_size + 1
            end
            applyPage(result, session.site_page - 1, offset)
        end)
        return
    end
    notify(_("Đang ở trang đầu."))
end

function Novels.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" then return end
    session.mode = "search"
    session.query = query
    session.kind = "latest"
    fetchList(page or 1, 1)
end

function Novels.browse(kind, page)
    session.mode = "browse"
    session.kind = kind == "popular" and "popular" or "latest"
    session.query = nil
    fetchList(page or 1, 1)
end

function Novels.openSource()
    -- Menu re-entry after X must not reuse a freed grid or a stuck busy flag.
    busy = false
    dropClosedGrid()
    Novels.browse("latest", 1)
end

function Novels.promptSearch()
    Catalog.promptText{ title = _("Tìm truyện DocLN"), on_submit = function(query) Novels.search(query, 1) end }
end

return Novels
