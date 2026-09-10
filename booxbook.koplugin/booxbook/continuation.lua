local Settings = require("booxbook.store.settings")
local Download = require("booxbook.comic-download")
local Catalog = require("booxbook.ui.catalog")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end

local Continuation = {
    prompted_path = nil,
}

function Continuation.reset()
    Continuation.prompted_path = nil
end

local function realpath(p)
    if type(p) ~= "string" then return p end
    local ok, ffiUtil = pcall(require, "ffi/util")
    if ok and ffiUtil and ffiUtil.realpath then
        return ffiUtil.realpath(p) or p
    end
    return p
end

-- Resolve next comic chapter info from a CBZ path.
-- Purely local and non-blocking: reads sidecar or local manifest.json.
function Continuation.resolveComicNext(path)
    if type(path) ~= "string" or not path:match("%.cbz$") then return nil end
    local real_path = realpath(path)
    local real_root = realpath(Settings.downloadDir() .. "/comics")
    if not real_path or not real_root then return nil end
    if real_path:sub(1, #real_root + 1) ~= real_root .. "/" then return nil end

    local meta = Download.readMeta(real_path)
    if not meta then
        meta = Download.buildMetaFromPath(real_path)
        if meta then
            Download.writeMeta(real_path, meta)
        end
    end

    if not meta then
        return nil, "no_meta"
    end

    if not meta.next_url then
        return {
            end_of_series = true,
            source_id = meta.source_id,
            series_id = meta.series_id,
            current_title = meta.chapter_title or meta.chapter,
        }
    end

    local NextAdapter = Download.adapterFor(meta.next_url)
    if not NextAdapter or NextAdapter.id ~= meta.source_id then return nil end
    local next_ref = NextAdapter.parseRef and NextAdapter.parseRef(meta.next_url)
    if not next_ref or (meta.series_id and next_ref.series ~= meta.series_id) then return nil end

    local saved_path, saved_err = Download.savedPath(meta.next_url)
    if saved_err then return nil end

    local is_downloaded = (saved_path ~= nil)
    local next_path = saved_path or Download.path(meta.next_url)

    if is_downloaded and saved_path and not Download.readMeta(saved_path) then
        local next_meta = Download.buildMeta(meta.next_url)
        if next_meta then
            Download.writeMeta(saved_path, next_meta)
        end
    end

    return {
        source_id = meta.source_id,
        series_id = meta.series_id,
        series_url = meta.series_url,
        current_title = meta.chapter_title or meta.chapter,
        next_title = meta.next_title or meta.next_chapter or _("tập tiếp theo"),
        next_url = meta.next_url,
        next_path = next_path,
        downloaded = is_downloaded,
    }
end

-- Resolve next novel chapter info from an EPUB or HTML path.
function Continuation.resolveNovelNext(path)
    if type(path) ~= "string" then return nil end
    local real_path = realpath(path)
    local real_novel_root = realpath(Settings.downloadDir() .. "/novels")
    if not real_path or not real_novel_root then return nil end
    if real_path:sub(1, #real_novel_root + 1) ~= real_novel_root .. "/" then return nil end

    local rel = real_path:sub(#real_novel_root + 2)
    local source_id, series_id, filename = rel:match("^([^/]+)/([^/]+)/([^/]+)$")
    if not source_id or not series_id or not filename then return nil end

    local dir = Settings.downloadDir() .. "/novels/" .. source_id .. "/" .. series_id
    local index_path = dir .. "/index.json"
    local file = io.open(index_path, "rb")
    if not file then return nil end
    local content = file:read(512 * 1024 + 1)
    file:close()
    if not content or content == "" or #content > 512 * 1024 then return nil end
    local json_ok, Json = pcall(require, "json")
    if not json_ok or not Json or not Json.decode then return nil end
    local ok, index = pcall(Json.decode, content)
    if not ok or type(index) ~= "table" then return nil end

    local last_num = nil
    local first_num, last_epub = filename:match("^chapters%-(%d+)%-(%d+)%.epub$")
    if last_epub then
        last_num = tonumber(last_epub)
    elseif filename:match("^chapter%-(%d+)%.html$") then
        last_num = tonumber(filename:match("^chapter%-(%d+)%.html$"))
    elseif filename == "book.epub" then
        local max_num = 0
        for num_str, entry in pairs(index.chapters or {}) do
            local n = tonumber(entry.number or num_str)
            if n and n > max_num then max_num = n end
        end
        if max_num > 0 then last_num = max_num end
    end

    if not last_num then return nil end
    local next_num = last_num + 1

    local current_entry = index.chapters and (index.chapters[tostring(last_num)] or index.chapters[last_num])
    local current_title = current_entry and current_entry.title or (_("Chương ") .. last_num)

    local next_entry = index.chapters and (index.chapters[tostring(next_num)] or index.chapters[next_num])
    local next_title = next_entry and next_entry.title or (_("Chương ") .. next_num)

    local is_downloaded = false
    local next_path = nil
    if next_entry and next_entry.file then
        local candidate = dir .. "/" .. next_entry.file
        local probe = io.open(candidate, "rb")
        if probe then
            probe:close()
            is_downloaded = true
            next_path = candidate
        end
    end

    return {
        kind = "novel",
        source_id = source_id,
        series_id = series_id,
        series_title = index.title,
        current_title = current_title,
        next_title = next_title,
        next_number = next_num,
        next_path = next_path,
        chapter_url = current_entry and current_entry.url,
        downloaded = is_downloaded,
    }
end

function Continuation.promptContinuation(next_info)
    if not next_info then return end

    if UIManager and UIManager.getTopmostVisibleWidget then
        local top = UIManager:getTopmostVisibleWidget()
        if top and top.name == "end_document" then
            UIManager:close(top)
        end
    end

    local current_title = next_info.current_title or _("tập hiện tại")
    local next_title = next_info.next_title or _("tập tiếp theo")

    if next_info.kind == "novel" then
        if next_info.downloaded and next_info.next_path then
            local msg = string.format(_("Đã đọc xong %s.\nMở tiếp %s?"), current_title, next_title)
            Catalog.confirm(msg, function()
                if ReaderUI.showReader then
                    ReaderUI:showReader(next_info.next_path)
                end
            end, {
                name = "end_document",
                ok_text = _("Đọc tiếp"),
                cancel_text = _("Để sau"),
            })
            return true
        else
            local msg = string.format(_("Đã đọc xong %s.\nBạn có muốn tải tiếp %s để đọc tiếp không?"), current_title, next_title)
            Catalog.confirm(msg, function()
                local ok, Novels = pcall(require, "booxbook.ui.novels")
                if ok and Novels and Novels.downloadChapter then
                    Novels.downloadChapter(next_info.source_id, next_info.series_id, next_info.next_number, next_info.chapter_url)
                end
            end, {
                name = "end_document",
                ok_text = _("Tải và đọc tiếp"),
                cancel_text = _("Để sau"),
            })
            return true
        end
    end

    if next_info.end_of_series then
        local msg = string.format(_("Đã đọc xong %s.\nBạn đã đọc đến tập mới nhất hiện có của bộ truyện này."), current_title)
        Catalog.confirm(msg, nil, {
            name = "end_document",
            ok_text = _("Đóng"),
            cancel_text = _("Về đầu tập"),
            cancel_callback = function()
                if ReaderUI.instance and ReaderUI.instance.gotoPage then
                    ReaderUI.instance:gotoPage(1)
                end
            end,
        })
        return true
    elseif next_info.downloaded and next_info.next_path then
        local msg = string.format(_("Đã đọc xong %s.\nMở tiếp %s?"), current_title, next_title)
        Catalog.confirm(msg, function()
            if ReaderUI.showReader then
                ReaderUI:showReader(next_info.next_path)
            end
        end, {
            name = "end_document",
            ok_text = _("Đọc tiếp"),
            cancel_text = _("Để sau"),
        })
        return true
    elseif next_info.next_url then
        local msg = string.format(_("Đã đọc xong %s.\nBạn có muốn tải tiếp %s để đọc tiếp không?"), current_title, next_title)
        Catalog.confirm(msg, function()
            local SourceUI
            if next_info.source_id == "truyenqq" then
                local ok, QQ = pcall(require, "booxbook.ui.truyenqq")
                if ok then SourceUI = QQ end
            elseif next_info.source_id == "truyentuoitho" then
                local ok, TT = pcall(require, "booxbook.ui.truyentuoitho")
                if ok then SourceUI = TT end
            end
            if SourceUI and SourceUI.download then
                SourceUI.download(next_info.next_url)
            end
        end, {
            name = "end_document",
            ok_text = _("Tải và đọc tiếp"),
            cancel_text = _("Để sau"),
        })
        return true
    end
end

function Continuation.bootstrapOnline(source_id, series_id, chapter, real_path, series_url)
    local Network = require("booxbook.network")
    local Trapper = require("ui/trapper")
    if type(series_url) ~= "string" or series_url == "" then
        series_url = nil
    end
    if not series_url then
        if source_id == "truyenqq" then
            series_url = "https://truyenqqko.com/truyen-tranh/" .. series_id
        elseif source_id == "truyentuoitho" then
            series_url = "https://truyentuoitho.com/manga/" .. series_id .. "/"
        end
    end
    if not series_url then return end

    local Source
    if source_id == "truyenqq" then
        local ok_q, Q = pcall(require, "booxbook.sources.truyenqq")
        if ok_q then Source = Q end
    elseif source_id == "truyentuoitho" then
        local ok_t, T = pcall(require, "booxbook.sources.truyentuoitho")
        if ok_t then Source = T end
    end
    if not Source or not Source.getSeries then return end

    UIManager:nextTick(function()
        Network.ifOnline(function()
            Trapper:wrap(function()
                local ok, fetched = pcall(function()
                    Trapper:info(_("Đang lấy mục lục tiếp nối…"))
                    return Source.getSeries(series_url)
                end)
                Trapper:clear()
                if ok and type(fetched) == "table" and type(fetched.chapters) == "table" then
                    local dir = Settings.downloadDir() .. "/comics/" .. source_id .. "/" .. series_id
                    Download.writeManifest(dir, fetched)
                    local next_info = Continuation.resolveComicNext(real_path)
                    if next_info then
                        Continuation.prompted_path = real_path
                        UIManager:nextTick(function()
                            Continuation.promptContinuation(next_info)
                        end)
                        return
                    end
                end
                Continuation.promptBootstrapFailure(source_id, series_id, chapter, real_path)
            end)
        end)
    end)
end

function Continuation.promptBootstrapFailure(source_id, series_id, chapter, real_path)
    if UIManager and UIManager.getTopmostVisibleWidget then
        local top = UIManager:getTopmostVisibleWidget()
        if top and top.name == "end_document" then
            UIManager:close(top)
        end
    end
    Continuation.prompted_path = real_path
    local msg = _("Đã đọc xong tập này nhưng chưa lấy được mục lục tiếp nối (ngoại tuyến hoặc mạng bận).\nThử lại?")
    Catalog.confirm(msg, function()
        Continuation.prompted_path = nil
        Continuation.bootstrapOnline(source_id, series_id, chapter, real_path)
    end, {
        name = "end_document",
        ok_text = _("Thử lại"),
        cancel_text = _("Để sau"),
    })
end

function Continuation.onEndOfBook(ui)
    local path = ui and ui.document and ui.document.file
    if not path then return nil end
    local real_path = realpath(path)

    local real_comic_root = realpath(Settings.downloadDir() .. "/comics")
    local real_novel_root = realpath(Settings.downloadDir() .. "/novels")
    local is_comic = real_comic_root and real_path:sub(1, #real_comic_root + 1) == real_comic_root .. "/" and real_path:match("%.cbz$")
    local is_novel = real_novel_root and real_path:sub(1, #real_novel_root + 1) == real_novel_root .. "/" and (real_path:match("%.epub$") or real_path:match("%.html$"))

    if not is_comic and not is_novel then return nil end

    if Continuation.prompted_path == real_path then
        return true
    end

    if is_comic then
        local next_info, reason = Continuation.resolveComicNext(real_path)
        if next_info then
            Continuation.prompted_path = real_path
            Continuation.promptContinuation(next_info)
            return true
        end

        if reason == "no_meta" then
            local rel = real_path:sub(#real_comic_root + 2)
            local source_id, series_id, chapter = rel:match("^([^/]+)/([^/]+)/([^/]+)%.cbz$")
            if source_id and series_id and chapter then
                Continuation.bootstrapOnline(source_id, series_id, chapter, real_path)
                return true
            end
        end
    elseif is_novel then
        local next_info = Continuation.resolveNovelNext(real_path)
        if next_info then
            Continuation.prompted_path = real_path
            Continuation.promptContinuation(next_info)
            return true
        end
    end

    return nil
end

return Continuation
