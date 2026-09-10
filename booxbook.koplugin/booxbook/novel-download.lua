local Docln = require("booxbook.sources.docln")
local Wattpad = require("booxbook.sources.wattpad")
local MeTruyenCV = require("booxbook.sources.metruyencv")
local TVTruyen = require("booxbook.sources.tvtruyen")
local TruyenFull = require("booxbook.sources.truyenfull")
local Sangtacviet = require("booxbook.sources.sangtacviet")
local Html = require("booxbook.html")
local Export = require("booxbook.novel-export")
local Parser = require("booxbook.sources.docln-parser")
local Settings = require("booxbook.store.settings")
local Storage = require("booxbook.store.storage")
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
    elseif source_id == "tvtruyen" then
        local chapter
        id, chapter = TVTruyen.parseRef(series.url)
        path, adapter = not chapter and id or nil, TVTruyen
    elseif source_id == "metruyencv" then
        id = MeTruyenCV.refId(series.url, true)
        path, adapter = id, MeTruyenCV
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

local function safeEntry(entry)
    return type(entry) == "table" and type(entry.file) == "string"
        and entry.file:match("^[%w_%-]+%.[%w]+$") ~= nil
end

local function fileExists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function readIndex(path, Json, id, allow_legacy_id)
    local file, read_err, read_code = io.open(path, "rb")
    if not file then return nil, nil, read_err, not read_code or read_code == 2 end
    local content = file:read("*a")
    file:close()
    local ok, index = pcall(Json.decode, content)
    if not ok or type(index) ~= "table" or type(index.chapters) ~= "table"
        or (index.id ~= id and not (allow_legacy_id and index.id == nil)) then
        return nil, nil, _("index.json bị lỗi."), false
    end
    return index, content
end

local function loadIndex(path, Json, id, allow_legacy_id)
    local index, content, err, missing = readIndex(path, Json, id, allow_legacy_id)
    if index then return index, content end
    local backup, backup_content, backup_err, backup_missing = readIndex(path .. ".bak", Json, id, false)
    if backup then return backup, backup_content, nil, false, true end
    if missing and backup_missing then return nil, nil, nil, true end
    return nil, nil, missing and backup_err or err, false
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
    local saved, _, read_err, missing = loadIndex(index_path, Json, id, true)
    if not saved then return missing and {} or nil, read_err end
    local list = {}
    for chapter_id, entry in pairs(saved.chapters) do
        local path = safeEntry(entry) and (dir .. "/" .. entry.file)
        if path and fileExists(path) then
            list[#list + 1] = {
                title = entry.export_title or entry.title or tostring(chapter_id),
                path = path,
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
    local index_path = dir .. "/index.json"
    local index, index_content, read_err, missing, recovered = loadIndex(index_path, Json, id, false)
    if not index then
        if not missing then return nil, read_err or _("index.json bị lỗi; giữ nguyên dữ liệu đã tải.") end
        index = { id = id, title = series.title, chapters = {} }
    else
        if recovered then
            local restored, restore_err = Html.writeFile(index_path, index_content)
            if not restored then return nil, _("Không phục hồi được index.json: ") .. tostring(restore_err) end
        end
    end
    local result = { saved = {}, existing = {}, skipped = {}, cancelled = false }
    local index_changed = false
    local backup_pending = index_content ~= nil and not recovered
    for number = first, last do
        local chapter = series.chapters[number]
        if progress and progress(number - first + 1, last - first + 1, chapter) == false then
            result.cancelled = true
            result.cancelled_at = number
            result.error = _("Đã hủy tải; chọn đóng gói để giữ EPUB partial hoặc giữ HTML để tải tiếp.")
            break
        end
        local chapter_path, chapter_series = Parser.path(chapter)
        local chapter_id = chapter_path and chapter_path:match("/c(%d+)")
        local max_id_len = 12
        if source_id == "truyenfull" then
            chapter_series, chapter_id = TruyenFull.parseRef(chapter)
            if chapter.series_id ~= chapter_series then chapter_series = nil end
        elseif source_id == "tvtruyen" then
            chapter_series, chapter_id = TVTruyen.parseRef(chapter)
            if chapter.series_id ~= chapter_series then chapter_series = nil end
        elseif source_id == "metruyencv" then
            chapter_id = MeTruyenCV.refId(chapter, false)
            chapter_series = chapter.series_id
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
        local previous = index.chapters[chapter_id]
        local existing_path = safeEntry(previous) and (dir .. "/" .. previous.file)
        if existing_path and fileExists(existing_path) then
            result.existing[#result.existing + 1] = {
                title = previous.export_title or previous.title or chapter.title,
                path = existing_path,
                id = chapter_id,
                number = previous.number or number,
            }
        else
            if backup_pending then
                local backed_up, backup_err = Html.writeFile(index_path .. ".bak", index_content)
                if not backed_up then
                    result.error = _("Không sao lưu được index.json: ") .. tostring(backup_err)
                    break
                end
                backup_pending = false
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
                result.saved[#result.saved + 1] = { title = chapter.title, path = target, id = chapter_id, number = number }
            end
            index.chapters[chapter_id] = entry
            local encoded_ok, encoded = pcall(Json.encode, index)
            if not encoded_ok or type(encoded) ~= "string" then result.error = _("Không ghi được danh sách chương."); break end
            local ok, write_err = Html.writeFile(index_path, encoded)
            if not ok then result.error = write_err; break end
            index_changed = true
        end
    end
    -- Cancelled runs keep HTML/index for resume; EPUB partial is only
    -- packaged on explicit user confirmation via Download.packagePartial.
    if not result.cancelled then
        Export.finish(series, dir, first, last, index, result, Json)
    end
    if index_changed then
        local encoded_ok, encoded = pcall(Json.encode, index)
        local backup_ok, backup_err = false, _("Không ghi được danh sách chương.")
        if encoded_ok and type(encoded) == "string" then
            backup_ok, backup_err = Html.writeFile(index_path .. ".bak", encoded)
        end
        if not backup_ok and not result.error then
            result.error = _("Không sao lưu được index.json: ") .. tostring(backup_err)
        end
    end
    result.dir = dir
    return result
end

-- Package an EPUB from an already-cancelled run. `saved` is the cancelled
-- result.saved list; `last_partial` defaults to first + #saved - 1.
-- Returns the Export-updated result (result.saved gains the EPUB entry).
function Download.packagePartial(series, first, last_partial, saved)
    series = series or {}
    saved = saved or {}
    if type(first) ~= "number" or #saved == 0 then
        return nil, _("Không có chương đã tải để đóng gói.")
    end
    if type(last_partial) ~= "number" or last_partial < first then
        last_partial = first + #saved - 1
    end
    local source_id, id, _, location_err = seriesLocation(series)
    if not source_id then return nil, location_err end
    if not id or id ~= series.id then
        return nil, _("Không xác định được thư mục truyện.")
    end
    local json_ok, Json = pcall(require, "json")
    if not json_ok then return nil, _("Không có thư viện JSON của KOReader.") end
    local dir = Settings.downloadDir() .. "/novels/" .. source_id .. "/" .. id
    local index_path = dir .. "/index.json"
    local index, _, read_err = loadIndex(index_path, Json, id, false)
    if not index then return nil, read_err or _("Không đọc được danh sách chương đã tải.") end
    local partial = { saved = saved, skipped = {}, keep_html = true }
    Export.finish(series, dir, first, last_partial, index, partial, Json)
    return partial
end

function Download.packageSaved(series, first, last)
    series = series or {}
    local source_id, id, path, location_err = seriesLocation(series)
    if not source_id then return nil, location_err end
    if not path or id ~= series.id or type(first) ~= "number" or type(last) ~= "number"
        or first % 1 ~= 0 or last % 1 ~= 0 or first < 1 or last < first or last > #(series.chapters or {}) then
        return nil, _("Khoảng chương không hợp lệ.")
    end
    local json_ok, Json = pcall(require, "json")
    if not json_ok then return nil, _("Không có thư viện JSON của KOReader.") end
    local dir = Settings.downloadDir() .. "/novels/" .. source_id .. "/" .. id
    local index, index_content, read_err = loadIndex(dir .. "/index.json", Json, id, false)
    if not index then return nil, read_err or _("Không đọc được danh sách chương đã tải.") end

    local by_number = {}
    for chapter_id, entry in pairs(index.chapters) do
        local number = type(entry) == "table" and tonumber(entry.number)
        if number and number % 1 == 0 and not by_number[number] then
            by_number[number] = { id = chapter_id, entry = entry }
        end
    end
    local result = { saved = {}, skipped = {} }
    for number = first, last do
        local found = by_number[number]
        local entry = found and found.entry
        local chapter_path = safeEntry(entry) and entry.file:lower():match("%.html$") and (dir .. "/" .. entry.file)
        if chapter_path and fileExists(chapter_path) then
            result.saved[#result.saved + 1] = {
                title = entry.title or (series.chapters[number] and series.chapters[number].title) or (_("Chương") .. " " .. number),
                path = chapter_path,
                id = found.id,
                number = number,
            }
        else
            result.skipped[#result.skipped + 1] = {
                title = (series.chapters[number] and series.chapters[number].title) or (_("Chương") .. " " .. number),
                reason = _("Chưa có bản HTML."),
            }
        end
    end
    if #result.saved == 0 then return nil, _("Khoảng đã chọn không có chương HTML đã tải.") end
    Export.finish(series, dir, first, last, index, result, Json, true)
    return result
end
-- Remove orphan HTML chapter files whose chapter in index.json points to an
-- existing, verified EPUB file. Also removes associated image sidecars.
-- Reuses chapterFileName and safeEntry to safely locate files.
function Download.sweepOrphanHtml(novels_root)
    if type(novels_root) ~= "string" then return 0 end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not (ok_lfs and lfs and lfs.dir and lfs.attributes) then return 0 end
    local ok_mode, mode = pcall(lfs.attributes, novels_root, "mode")
    if not (ok_mode and mode == "directory") then return 0 end
    local json_ok, Json = pcall(require, "json")
    if not (json_ok and Json and Json.decode) then return 0 end
    local swept = 0
    local ok_sources, source_iter, source_state = pcall(lfs.dir, novels_root)
    if not (ok_sources and source_iter) then return 0 end
    for source in source_iter, source_state do
        if source ~= "." and source ~= ".." then
            local source_dir = novels_root .. "/" .. source
            local ok_s, smode = pcall(lfs.attributes, source_dir, "mode")
            if ok_s and smode == "directory" then
                local ok_series, series_iter, series_state = pcall(lfs.dir, source_dir)
                if ok_series and series_iter then
                    for series in series_iter, series_state do
                        if series ~= "." and series ~= ".." then
                            local series_dir = source_dir .. "/" .. series
                            local ok_ser, sermode = pcall(lfs.attributes, series_dir, "mode")
                            if ok_ser and sermode == "directory" then
                                local index_path = series_dir .. "/index.json"
                                local index = readIndex(index_path, Json, series, true)
                                if index and type(index.chapters) == "table" then
                                    for chapter_id, entry in pairs(index.chapters) do
                                        if safeEntry(entry) and entry.file:lower():match("%.epub$") then
                                            local epub_path = series_dir .. "/" .. entry.file
                                            if fileExists(epub_path) then
                                                local html_name = chapterFileName(tostring(chapter_id))
                                                if html_name then
                                                    local html_path = series_dir .. "/" .. html_name
                                                    if fileExists(html_path) then
                                                        if os.remove(html_path) then
                                                            swept = swept + 1
                                                            pcall(Storage.removeSidecar, html_path)
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return swept
end

return Download
