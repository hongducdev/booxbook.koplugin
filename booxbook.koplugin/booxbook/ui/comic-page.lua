-- One catalogue + volume list + CBZ download page for every comic adapter.
--
-- Presentation lives in `adapter.view`; the download flow (manifest, partial
-- CBZ recovery, staged pages, continuation) lives here so both comic sources
-- share a single implementation.
--
-- Dependencies are resolved inside create() so a page always binds the module
-- instances that are loaded at the time it is built (the test harness reloads
-- KOReader widgets per fixture).
local Page = {}

-- view.base_url may be a function for sources whose domain can change at runtime.
local function resolve(value)
    if type(value) == "function" then return value() end
    return value
end

function Page.create(adapter)
    assert(type(adapter) == "table" and adapter.id, "adapter with id required")
    local Catalog = require("booxbook.ui.catalog")
    local Download = require("booxbook.comic-download")
    local Network = require("booxbook.network")
    local Settings = require("booxbook.store.settings")
    local Trapper = require("ui/trapper")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local ReaderUI = require("apps/reader/readerui")
    local SeriesUI = require("booxbook.ui.series")
    local _ = require("gettext")

    local view = adapter.view or {}
    local source_id = adapter.id
    local name = adapter.name or adapter.id
    local loading = view.loading and _(view.loading) or _("Đang tải tập %s…")
    local UI = { adapter = adapter, view = view }
    local Async = require("booxbook.async")
    local busy = false

    -- Every failure reaches the reader as a sentence, never as a file:line.
    local function notify(text, subject)
        return require("booxbook.fault").notify(text, subject)
    end

    local function open(path)
        UIManager:nextTick(function() Catalog.clearStack(); ReaderUI:showReader(path) end)
    end

    -- Serialise network work for this source and report failures in one place.
    local function online(message, action, done, budget)
        UIManager:nextTick(function()
            Network.whenOnline(function()
                if busy then notify(_("Đang tải, vui lòng chờ.")); return end
                busy = true
                Trapper:wrap(function()
                    local ok, result, err = require("booxbook.http").runWithBudget(budget, function()
                        Trapper:info(message); return action()
                    end)
                    busy = false
                    Trapper:clear()
                    if not ok or not result then notify(ok and err or result); return end
                    UIManager:nextTick(function() done(result) end)
                end)
            end)
        end)
    end

    -- Same contract, resumable: lists and tables of contents yield between
    -- requests so Android never sees a blocked main thread. CBZ downloads keep
    -- online() because they need the progress line and tap-to-cancel.
    local function onlineResumable(message, action, done, budget)
        UIManager:nextTick(function()
            Network.whenOnline(function()
                if busy then notify(_("Đang tải, vui lòng chờ.")); return end
                busy = true
                local Http = require("booxbook.http")
                Async.run(function()
                    pcall(Trapper.info, Trapper, message)
                    return Http.withBudget(budget, action)
                end, function(ok, result, err)
                    busy = false
                    pcall(Trapper.clear, Trapper)
                    if not ok then notify(tostring(result)); return end
                    if not result then notify(tostring(err or result)); return end
                    UIManager:nextTick(function() done(result) end)
                end)
            end)
        end)
    end

    function UI.download(url, series, index)
        local meta
        if series and type(series.chapters) == "table" then
            if not index then
                for i, ch in ipairs(series.chapters) do
                    if ch.url == url or (ch.ref and ch.ref.url == url) then
                        index = i
                        break
                    end
                end
            end
            local current = series.chapters[index or 1]
            local next_ch = series.chapters[(index or 1) + 1]
            local ref = adapter.parseRef and adapter.parseRef(url)
            if ref and Download.writeManifest then
                Download.writeManifest(Settings.downloadDir() .. "/comics/" .. source_id .. "/"
                    .. (series.id or ref.series), series)
            end
            local next_ref = next_ch and adapter.parseRef and adapter.parseRef(next_ch)
            if next_ch and (not next_ref or (ref and next_ref.series ~= ref.series)) then
                next_ch = nil
                next_ref = nil
            end
            meta = {
                source_id = source_id,
                series_id = series.id or (ref and ref.series),
                series_title = series.title,
                series_url = series.url,
                chapter = ref and ref.chapter,
                chapter_title = current and current.title or (ref and ref.chapter),
                chapter_url = url,
                chapter_index = index or 1,
                next_url = next_ch and next_ch.url,
                next_title = next_ch and next_ch.title,
                next_chapter = next_ref and next_ref.chapter,
            }
        end
        local path, err = Download.savedPath(url)
        if path then
            if meta and Download.writeMeta then Download.writeMeta(path, meta) end
            open(path)
            return
        end
        if err then notify(err); return end
        online(string.format(loading, name), function()
            -- One CBZ is a bulk job: extend past the short budget `online` starts with.
            local Http = require("booxbook.http")
            return Http.withBudget(Http.BULK_TIMEOUT, function()
                local result, chapter_err, partial = Download.chapter(url, function(i, count, packing)
                    return Trapper:info(string.format(packing and _("Đóng gói CBZ: %d/%d — chạm để hủy")
                        or _("Tải ảnh: %d/%d — chạm để hủy"), i, count))
                end, meta)
                if not result and Download.isCancelErr(chapter_err) then
                    return { cancelled = true, err = chapter_err, partial = partial, url = url }
                end
                if not result then return nil, chapter_err end
                return result
            end)
        end, function(result)
            if type(result) == "table" and result.cancelled then
                UI.onChapterCancelled(result.url, result.partial)
                return
            end
            if Settings.transientComics() then
                -- Fresh download in this session: drop it when the document closes.
                require("booxbook.transient").mark(result)
            end
            Catalog.clearStack(); ReaderUI:showReader(result)
        end)
    end

    function UI.promptSearch()
        Catalog.promptText{
            title = string.format(_("Tìm truyện hoặc nhập URL %s"), name),
            input = Settings.get(view.last_url_key) or "",
            hint = view.search_hint and _(view.search_hint),
            ok_text = _("Tìm / mở"),
            on_submit = function(url)
                url = (url or ""):match("^%s*(.-)%s*$")
                if url == "" then return end
                if adapter.parseRef(url) then
                    Settings.set(view.last_url_key, url); UI.download(url)
                elseif adapter.parseSeriesRef(url) then UI.showSeries(url)
                elseif url:match("^https?://") then notify(string.format(_("URL %s không hợp lệ."), name))
                else UI.list(nil, url) end
            end }
    end

    function UI.list(kind, query, page, grid, last_screen)
        page = page or 1
        onlineResumable(_("Đang tải danh sách truyện…"), function()
            if query then return adapter.search(query, page) end
            return adapter.browse(kind, page)
        end, function(result)
            if grid and grid._closed then return end
            local CoverGrid = require("booxbook.ui.cover-grid")
            local items, size = result.items or {}, CoverGrid.PAGE_SIZE
            local offset = last_screen and math.floor(math.max(0, #items - 1) / size) * size + 1 or 1
            local base = resolve(view.base_url) or ""
            local payload = { title = name .. (query and (" — " .. query) or ""),
                items = items, offset = offset, site_page = page, has_more = result.has_more,
                source_id = source_id, base_url = base,
                cover_referer = base .. "/", cover_delay_ms = view.cover_delay_ms,
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
            -- A whole range is a bulk job: keep the long budget.
            local Http = require("booxbook.http")
            return Http.withBudget(Http.BULK_TIMEOUT, function()
                return Download.range(series, first, last, function(n, count, chapter, i, total, packing)
                    return Trapper:info(string.format(_("Tập %d/%d: %s\n%s %d/%d — chạm để hủy"),
                        n, count, chapter.title, packing and _("Đóng gói") or _("Tải ảnh"), i, total))
                end)
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
        onlineResumable(_("Đang lấy mục lục…"), function() return adapter.getSeries(ref) end, function(series)
            local first_ch = series.chapters and series.chapters[1]
            local ref_first = first_ch and adapter.parseRef and adapter.parseRef(first_ch.url or first_ch)
            if ref_first and Download.writeManifest then
                Download.writeManifest(Settings.downloadDir() .. "/comics/" .. source_id .. "/"
                    .. ref_first.series, series)
            end
            local total = #series.chapters
            SeriesUI.show(series, {
                unit = _("tập"), Unit = _("Tập"),
                on_info = function()
                    local TextViewer = require("ui/widget/textviewer")
                    UIManager:show(TextViewer:new{ title = series.title, text = series.description or "" })
                end,
                on_go = function(n) UI.download(series.chapters[n].url, series, n) end,
                on_chapter = function(chapter, i) UI.download(chapter.url, series, i) end,
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
                follow_label = require("booxbook.ui.follow").followLabel(series),
                on_follow = function() require("booxbook.ui.follow").toggle(series) end,
            })
        end)
    end

    function UI.openOffline()
        local dir = Settings.downloadDir() .. "/comics/" .. source_id
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
        local items = { { text = _("Tìm truyện / nhập URL"), callback = UI.promptSearch } }
        for _index, entry in ipairs(view.browse or {}) do
            local kind = entry.kind
            items[#items + 1] = { text = _(entry.text), callback = function() UI.list(kind) end }
        end
        items[#items + 1] = {
            text = Settings.transientComics() and _("Đọc xong không lưu: BẬT")
                or _("Đọc xong không lưu: tắt"),
            callback = function()
                Settings.set("transient_comics", not Settings.transientComics())
                if Settings.transientComics() then
                    notify(_("Đã bật: chương tải trong phiên này sẽ bị xoá sau khi đóng."))
                else
                    notify(_("Đã tắt: chương tải về được giữ lại."))
                end
            end,
        }
        items[#items + 1] = { text = _("Truyện đã tải (offline)"), callback = UI.openOffline }
        Catalog.show{ title = name, on_search = UI.promptSearch, items = items }
    end

    return UI
end

return Page
