local Html = require("booxbook.html")

local ReadingState = {}

local function getSettings()
    local ok, S = pcall(require, "booxbook.store.settings")
    if ok and S then return S end
    return {}
end
local MAX_JSON_BYTES = 512 * 1024

local function now()
    return os.time()
end

local function normalize(path)
    if type(path) ~= "string" then return nil end
    return (path:gsub("\\", "/"))
end

local function realpath(path)
    if type(path) ~= "string" then return nil end
    local ok, ffiUtil = pcall(require, "ffi/util")
    if ok and ffiUtil and ffiUtil.realpath then
        return normalize(ffiUtil.realpath(path) or path)
    end
    return normalize(path)
end

local function readJson(path)
    if type(path) ~= "string" then return nil end
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read(MAX_JSON_BYTES + 1)
    file:close()
    if not content or content == "" or #content > MAX_JSON_BYTES then return nil end
    local json_ok, Json = pcall(require, "json")
    if not json_ok or not Json or type(Json.decode) ~= "function" then return nil end
    local ok, decoded = pcall(Json.decode, content)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

local function writeJson(path, value)
    local json_ok, Json = pcall(require, "json")
    if not json_ok or not Json or type(Json.encode) ~= "function" then return false end
    local ok, encoded = pcall(Json.encode, value)
    if not ok or type(encoded) ~= "string" then return false end
    local ok_html, HtmlMod = pcall(require, "booxbook.html")
    if ok_html and HtmlMod and type(HtmlMod.writeFile) == "function" then
        return HtmlMod.writeFile(path, encoded)
    end
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(encoded)
    f:close()
    return true
end

local function copyProgress(info)
    if type(info) ~= "table" then return nil end
    local status = info.status == "complete" and "complete" or "reading"
    local percent = tonumber(info.read_percent) or 0
    if percent < 0 then percent = 0 elseif percent > 100 then percent = 100 end
    percent = math.floor(percent + 0.5)
    return {
        status = status,
        read_percent = percent,
        last_read_chapter = info.last_read_chapter,
        last_read_file = info.last_read_file,
        last_read_time = tonumber(info.last_read_time) or now(),
    }
end

local function historyKey(kind, source_id, series_id)
    if type(kind) ~= "string" or kind == "" or type(source_id) ~= "string" or source_id == ""
        or type(series_id) ~= "string" or series_id == "" then return nil end
    return kind .. ":" .. source_id .. ":" .. series_id
end

function ReadingState.key(kind, source_id, series_id)
    return historyKey(kind, source_id, series_id)
end

local function sortedChapters(index, filename)
    local chapters, max_number = {}, nil
    if type(index) ~= "table" or type(index.chapters) ~= "table" then return chapters, max_number end
    for id, entry in pairs(index.chapters) do
        if type(entry) == "table" then
            local number = tonumber(entry.number or id)
            if number and (not max_number or number > max_number) then max_number = number end
            if entry.file == filename then
                chapters[#chapters + 1] = {
                    id = tostring(id),
                    number = number,
                    title = entry.title,
                    url = entry.url,
                }
            end
        end
    end
    table.sort(chapters, function(a, b)
        if a.number and b.number then return a.number < b.number end
        return tostring(a.id) < tostring(b.id)
    end)
    return chapters, max_number
end

local function fallbackEpubChapters(filename)
    local first_num, last_num = filename:match("^chapters%-(%d+)%-(%d+)%.epub$")
    first_num, last_num = tonumber(first_num), tonumber(last_num)
    local chapters = {}
    if first_num and last_num and first_num <= last_num and last_num - first_num < 10000 then
        for n = first_num, last_num do
            chapters[#chapters + 1] = { id = tostring(n), number = n }
        end
        return chapters, last_num
    end
    return chapters, nil
end

local function chooseChapter(chapters, percent)
    if type(chapters) ~= "table" or #chapters == 0 then return nil end
    local pos
    if percent >= 100 then
        pos = #chapters
    else
        pos = math.floor((percent / 100) * #chapters) + 1
    end
    if pos < 1 then pos = 1 elseif pos > #chapters then pos = #chapters end
    local chapter = chapters[pos]
    return chapter and (chapter.number or chapter.id)
end

local function resolveNovel(path)
    local root = realpath(getSettings().downloadDir() .. "/novels")
    local full = realpath(path)
    if not root or not full or full:sub(1, #root + 1) ~= root .. "/" then
        return nil
    end
    local rel = full:sub(#root + 2)
    local source_id, series_id, filename = rel:match("^([^/]+)/([^/]+)/([^/]+)$")
    if not source_id or not series_id or not filename or not (filename:match("%.html$") or filename:match("%.epub$")) then
        return nil
    end

    local dir = getSettings().downloadDir() .. "/novels/" .. source_id .. "/" .. series_id
    local index = readJson(dir .. "/index.json") or readJson(dir .. "/index.json.bak")
    local chapters, max_number = sortedChapters(index, filename)
    if #chapters == 0 and filename:match("%.epub$") then
        chapters, max_number = fallbackEpubChapters(filename)
    end
    if #chapters == 0 and filename:match("^ch%-(.+)%.html$") then
        local id = filename:match("^ch%-(.+)%.html$")
        local number = tonumber(id)
        chapters[1] = { id = id, number = number }
    elseif #chapters == 0 and filename:match("^chapter%-(%d+)%.html$") then
        local number = tonumber(filename:match("^chapter%-(%d+)%.html$"))
        chapters[1] = { id = tostring(number), number = number }
    end

    local first = chapters[1]
    local last = chapters[#chapters]
    local last_number = last and last.number
    local is_last = last_number and max_number and last_number >= max_number or false
    return {
        kind = "novel",
        source_id = source_id,
        series_id = series_id,
        dir = dir,
        file_path = path,
        file = filename,
        chapters = chapters,
        chapter_id = first and first.id,
        chapter_number = first and first.number,
        chapter_title = first and first.title,
        chapter_url = first and first.url,
        last_chapter_number = last_number,
        max_chapter_number = max_number,
        is_last_chapter = is_last,
    }
end

local function readComicMeta(path)
    return readJson(path .. ".meta.json")
end
local function resolveComic(path)
    local root = realpath(getSettings().downloadDir() .. "/comics")
    local full = realpath(path)
    if not root or not full or full:sub(1, #root + 1) ~= root .. "/" or not full:match("%.cbz$") then return nil end
    local rel = full:sub(#root + 2)
    local source_id, series_id, chapter = rel:match("^([^/]+)/([^/]+)/([^/]+)%.cbz$")
    if not source_id or not series_id or not chapter then return nil end

    local dir = getSettings().downloadDir() .. "/comics/" .. source_id .. "/" .. series_id
    local manifest = readJson(dir .. "/manifest.json")
    local meta = readComicMeta(path)
    local current, current_index
    local chapters = type(manifest) == "table" and manifest.chapters
    if type(chapters) == "table" then
        for i, ch in ipairs(chapters) do
            local ch_ref = type(ch) == "table" and ch.chapter
            local url_tail = type(ch) == "table" and type(ch.url) == "string" and ch.url:match("/([^/?#]+)/?$")
            if ch_ref == chapter or url_tail == chapter then
                current, current_index = ch, i
                break
            end
        end
    end
    local index = current_index or tonumber(meta and meta.chapter_index)
    return {
        kind = "comic",
        source_id = source_id,
        series_id = series_id,
        dir = dir,
        file_path = path,
        file = chapter .. ".cbz",
        chapter = chapter,
        chapter_number = index,
        chapter_title = current and current.title or (meta and meta.chapter_title),
        chapter_url = current and current.url or (meta and meta.chapter_url),
        max_chapter_number = type(chapters) == "table" and #chapters or nil,
        is_last_chapter = index ~= nil and type(chapters) == "table" and #chapters > 0 and index >= #chapters or false,
    }
end
function ReadingState.resolveTarget(file_path)
    return resolveNovel(file_path) or resolveComic(file_path)
end


local function readSettingsProgress(kind, source_id, series_id)
    local key = historyKey(kind, source_id, series_id)
    if not key then return nil end
    local S = getSettings()
    local history = S.get and S.get("reading_history")
    local info = type(history) == "table" and history[key]
    return copyProgress(info)
end

local function mirrorPath(kind, source_id, series_id, dir)
    if type(dir) == "string" and dir ~= "" then
        return dir .. "/" .. (kind == "novel" and "index.json" or "manifest.json")
    end
    local S = getSettings()
    local download_dir = S.downloadDir and S.downloadDir()
    if not download_dir or type(source_id) ~= "string" or type(series_id) ~= "string" then return nil end
    local subdir = kind == "novel" and "novels" or "comics"
    local filename = kind == "novel" and "index.json" or "manifest.json"
    return download_dir .. "/" .. subdir .. "/" .. source_id .. "/" .. series_id .. "/" .. filename
end

local function readMirrorProgress(kind, source_id, series_id, dir)
    local path = mirrorPath(kind, source_id, series_id, dir)
    local manifest = path and readJson(path)
    if type(manifest) ~= "table" then return nil end
    return copyProgress(manifest.reading_state)
end

function ReadingState.getProgress(kind, source_id, series_id, dir)
    return readSettingsProgress(kind, source_id, series_id) or readMirrorProgress(kind, source_id, series_id, dir)
end

local function saveSettingsProgress(target, info)
    local key = historyKey(target.kind, target.source_id, target.series_id)
    if not key then return false end
    local S = getSettings()
    local history = S.get and S.get("reading_history")
    if type(history) ~= "table" then history = {} end
    history[key] = copyProgress(info)
    if S.set then S.set("reading_history", history) end
    return true
end

local function saveMirrorProgress(target, info)
    local path = mirrorPath(target.kind, target.source_id, target.series_id, target.dir)
    if not path then return false end
    local data = readJson(path)
    if type(data) ~= "table" then return false end
    data.reading_state = copyProgress(info)
    local S = getSettings()
    if S.ensureDir and target.dir then S.ensureDir(target.dir) end
    return writeJson(path, data)
end

local function saveProgress(target, info)
    if type(target) ~= "table" then return nil, "invalid target" end
    local state = copyProgress(info)
    if not state then return nil, "invalid progress" end
    state.kind = target.kind
    state.source_id = target.source_id
    state.series_id = target.series_id
    saveSettingsProgress(target, state)
    -- Single canonical authority: download metadata (index.json / manifest.json) remains immutable
    return state
end

local function percentFromPages(current_page, total_pages, is_end_of_book)
    if is_end_of_book then return 100 end
    local total = tonumber(total_pages) or 0
    local current = tonumber(current_page) or 0
    if total <= 0 then return 0 end
    if current < 0 then current = 0 elseif current > total then current = total end
    return math.floor((current * 100 / total) + 0.5)
end

function ReadingState.recordProgress(file_path, current_page, total_pages, is_end_of_book)
    local target = ReadingState.resolveTarget(file_path)
    if not target then return nil, "unsupported file" end
    local percent = percentFromPages(current_page, total_pages, is_end_of_book)
    local complete = is_end_of_book == true or (target.is_last_chapter and percent >= 100)
    local chapter = target.kind == "novel" and chooseChapter(target.chapters, percent)
        or target.chapter_number or target.chapter
    local info = {
        status = complete and "complete" or "reading",
        read_percent = complete and 100 or percent,
        last_read_chapter = chapter,
        last_read_file = target.file,
        last_read_time = now(),
    }
    return saveProgress(target, info)
end

local function targetFromArgs(kind_or_path, source_id, series_id, dir)
    if source_id == nil and series_id == nil then
        local target = ReadingState.resolveTarget(kind_or_path)
        if target then return target end
    end
    if type(kind_or_path) ~= "string" then return nil end
    if kind_or_path ~= "novel" and kind_or_path ~= "comic" then return nil end
    return { kind = kind_or_path, source_id = source_id, series_id = series_id, dir = dir }
end

function ReadingState.markComplete(kind_or_path, source_id, series_id, dir)
    local target = targetFromArgs(kind_or_path, source_id, series_id, dir)
    if not target then return nil, "unsupported target" end
    local current = ReadingState.getProgress(target.kind, target.source_id, target.series_id, target.dir) or {}
    local info = {
        status = "complete",
        read_percent = 100,
        last_read_chapter = current.last_read_chapter or target.last_chapter_number or target.chapter_number or target.chapter,
        last_read_file = current.last_read_file or target.file,
        last_read_time = now(),
    }
    return saveProgress(target, info)
end

function ReadingState.markReading(kind_or_path, source_id, series_id, dir)
    local target = targetFromArgs(kind_or_path, source_id, series_id, dir)
    if not target then return nil, "unsupported target" end
    local current = ReadingState.getProgress(target.kind, target.source_id, target.series_id, target.dir) or {}
    local percent = tonumber(current.read_percent) or 0
    if percent >= 100 then percent = 99 end
    local info = {
        status = "reading",
        read_percent = percent,
        last_read_chapter = current.last_read_chapter or target.chapter_number or target.chapter,
        last_read_file = current.last_read_file or target.file,
        last_read_time = now(),
    }
    return saveProgress(target, info)
end

function ReadingState.formatStatusBadge(info)
    local progress = copyProgress(info)
    if not progress then return "" end
    if progress.status == "complete" then return "[Đã xong]" end
    if progress.read_percent > 0 then return "[" .. tostring(progress.read_percent) .. "%]" end
    return ""
end

return ReadingState
