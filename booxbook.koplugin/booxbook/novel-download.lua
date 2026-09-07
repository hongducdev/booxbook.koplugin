local Docln = require("booxbook.sources.docln")
local Wattpad = require("booxbook.sources.wattpad")
local TruyenFull = require("booxbook.sources.truyenfull")
local Sangtacviet = require("booxbook.sources.sangtacviet")
local Html = require("booxbook.html")
local Export = require("booxbook.novel-export")
local Parser = require("booxbook.sources.docln-parser")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local Download = {}

local function chapterFileName(chapter_id)
    -- Keep short numeric ids zero-padded; never tonumber long fanqie ids.
    if chapter_id:match("^%d+$") and #chapter_id <= 12 then
        return string.format("ch-%012d.html", tonumber(chapter_id))
    end
    local safe = chapter_id:gsub("[^%w%-_]", "_")
    if safe == "" or #safe > 64 then return nil end
    return "ch-" .. safe .. ".html"
end

local function seriesLocation(series)
    series = series or {}
    local source_id = series.source_id or "docln"
    local path, id, adapter
    if source_id == "truyenfull" then
        local chapter
        id, chapter = TruyenFull.parseRef(series.url)
        path, adapter = not chapter and id or nil, TruyenFull
    elseif source_id == "wattpad" then
        id = Wattpad.refId(series.url, true)
        path, adapter = id, Wattpad
    elseif source_id == "sangtacviet" then
        local parts = Sangtacviet.parseRef(series.url or series)
        id = parts and Sangtacviet.seriesId(parts) or series.id
        path, adapter = id, Sangtacviet
    elseif source_id == "docln" then
        path, id = Parser.path(series.url)
        adapter = Docln
    else
        return nil, nil, nil, _("Nguồn truyện không hợp lệ.")
    end
    return source_id, id, path, adapter
end

function Download.savedList(series)
    series = series or {}
    local source_id, id, _path, err = seriesLocation(series)
    if not source_id then return nil, err end
    if not id or (series.id and id ~= series.id) then
        return nil, _("Không xác định được thư mục truyện.")
    end
    local json_ok, Json = pcall(require, "json")
    if not json_ok then return nil, _("Không có thư viện JSON của KOReader.") end
    local dir = Settings.downloadDir() .. "/novels/" .. source_id .. "/" .. id
    local index_path = dir .. "/index.json"
    local file, read_err, read_code = io.open(index_path, "rb")
    if not file then
        if not read_code or read_code == 2 then return {} end
        return nil, read_err
    end
    local content = file:read("*a")
    file:close()
    local ok, saved = pcall(Json.decode, content)
    if not ok or type(saved) ~= "table" or type(saved.chapters) ~= "table" then
        return nil, _("index.json bị lỗi.")
    end
    local list = {}
    for chapter_id, entry in pairs(saved.chapters) do
        if type(entry) == "table" and type(entry.file) == "string"
            and entry.file:match("^[%w_%-]+%.[%w]+$") then
            list[#list + 1] = {
                title = entry.export_title or entry.title or tostring(chapter_id),
                path = dir .. "/" .. entry.file,
                number = entry.number,
                id = chapter_id,
            }
        end
    end
    table.sort(list, function(a, b)
        local na, nb = tonumber(a.number) or 0, tonumber(b.number) or 0
        if na ~= nb then return na < nb end
        return tostring(a.id) < tostring(b.id)
    end)
    local unique, seen = {}, {}
    for _, entry in ipairs(list) do
        if not seen[entry.path] then
            unique[#unique + 1], seen[entry.path] = entry, true
        end
    end
    return unique
end

function Download.range(series, first, last, confirmed, progress)
    local source_id, id, path, adapter = seriesLocation(series)
    if not source_id then return nil, adapter end
    if not path or id ~= series.id or type(first) ~= "number" or type(last) ~= "number"
        or first % 1 ~= 0 or last % 1 ~= 0 or first < 1 or last < first or last > #series.chapters then
        return nil, _("Khoảng chương không hợp lệ.")
    end
    if last - first + 1 > 50 and not confirmed then return nil, _("Cần xác nhận khi tải hơn 50 chương.") end
    if series.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
    local json_ok, Json = pcall(require, "json")
    if not json_ok then return nil, _("Không có thư viện JSON của KOReader.") end
    local dir = Settings.downloadDir() .. "/novels/" .. source_id .. "/" .. id
    if not Settings.ensureDir(dir) then return nil, _("Không tạo được thư mục truyện.") end
    local index_path, index = dir .. "/index.json", { id = id, title = series.title, chapters = {} }
    local file, read_err, read_code = io.open(index_path, "rb")
    if not file and read_code and read_code ~= 2 then return nil, read_err end
    if file then
        local content = file:read("*a"); file:close()
        local ok, saved = pcall(Json.decode, content)
        if not ok or type(saved) ~= "table" or saved.id ~= id or type(saved.chapters) ~= "table" then
            return nil, _("index.json bị lỗi; giữ nguyên dữ liệu đã tải.")
        end
        index = saved
    end
    local result = { saved = {}, skipped = {} }
    for number = first, last do
        local chapter = series.chapters[number]
        if progress and progress(number - first + 1, last - first + 1, chapter) == false then
            result.error = _("Đã dừng tải."); break
        end
        local chapter_path, chapter_series = Parser.path(chapter)
        local chapter_id = chapter_path and chapter_path:match("/c(%d+)")
        local max_id_len = 12
        if source_id == "truyenfull" then
            chapter_series, chapter_id = TruyenFull.parseRef(chapter)
            if chapter.series_id ~= chapter_series then chapter_series = nil end
        elseif source_id == "wattpad" then
            chapter_id = Wattpad.refId(chapter, false)
            chapter_series = chapter.series_id
        elseif source_id == "sangtacviet" then
            local parts = Sangtacviet.parseRef(chapter)
            chapter_id = parts and parts.chapter_id or chapter.chapter_id or chapter.id
            chapter_series = chapter.series_id or (parts and Sangtacviet.seriesId(parts))
            max_id_len = 32
        end
        if chapter_series ~= id or not chapter_id or #chapter_id > max_id_len then
            result.error = _("Đường dẫn chương không thuộc truyện này."); break
        end
        local content, err = adapter.getChapter(chapter)
        if not content then result.error = err; break end
        local entry = { title = chapter.title, url = chapter.url, number = number }
        if content.skipped then
            entry.skipped = content.skipped
            result.skipped[#result.skipped + 1] = { title = chapter.title, reason = content.skipped }
            -- A later locked response must not remove a previously downloaded chapter.
            if index.chapters[chapter_id] then entry = index.chapters[chapter_id] end
        else
            entry.file = chapterFileName(chapter_id)
            if not entry.file then result.error = _("ID chương không hợp lệ."); break end
            local target = dir .. "/" .. entry.file
            local document = Html.wrapDocument(chapter.title, "<h1>" .. Html.escape(chapter.title) .. "</h1>" .. content.html)
            local ok, write_err = Html.writeFile(target, document)
            if not ok then result.error = write_err; break end
            result.saved[#result.saved + 1] = { title = chapter.title, path = target, id = chapter_id }
        end
        index.chapters[chapter_id] = entry
        local encoded_ok, encoded = pcall(Json.encode, index)
        if not encoded_ok or type(encoded) ~= "string" then result.error = _("Không ghi được danh sách chương."); break end
        local ok, write_err = Html.writeFile(index_path, encoded)
        if not ok then result.error = write_err; break end
    end
    Export.finish(series, dir, first, last, index, result, Json)
    return result
end

return Download
