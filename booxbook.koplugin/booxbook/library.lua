-- Offline library index: search + quota + recent. Pure functions for tests;
-- filesystem scan is injected so unit tests never touch lfs.
local Library = {}

local accents = {
    ["à"] = "a", ["á"] = "a", ["ả"] = "a", ["ã"] = "a", ["ạ"] = "a",
    ["ă"] = "a", ["ằ"] = "a", ["ắ"] = "a", ["ẳ"] = "a", ["ẵ"] = "a", ["ặ"] = "a",
    ["â"] = "a", ["ầ"] = "a", ["ấ"] = "a", ["ẩ"] = "a", ["ẫ"] = "a", ["ậ"] = "a",
    ["À"] = "a", ["Á"] = "a", ["Ả"] = "a", ["Ã"] = "a", ["Ạ"] = "a",
    ["Ă"] = "a", ["Ằ"] = "a", ["Ắ"] = "a", ["Ẳ"] = "a", ["Ẵ"] = "a", ["Ặ"] = "a",
    ["Â"] = "a", ["Ầ"] = "a", ["Ấ"] = "a", ["Ẩ"] = "a", ["Ẫ"] = "a", ["Ậ"] = "a",
    ["đ"] = "d", ["Đ"] = "d",
    ["è"] = "e", ["é"] = "e", ["ẻ"] = "e", ["ẽ"] = "e", ["ẹ"] = "e",
    ["ê"] = "e", ["ề"] = "e", ["ế"] = "e", ["ể"] = "e", ["ễ"] = "e", ["ệ"] = "e",
    ["È"] = "e", ["É"] = "e", ["Ẻ"] = "e", ["Ẽ"] = "e", ["Ẹ"] = "e",
    ["Ê"] = "e", ["Ề"] = "e", ["Ế"] = "e", ["Ể"] = "e", ["Ễ"] = "e", ["Ệ"] = "e",
    ["ì"] = "i", ["í"] = "i", ["ỉ"] = "i", ["ĩ"] = "i", ["ị"] = "i",
    ["Ì"] = "i", ["Í"] = "i", ["Ỉ"] = "i", ["Ĩ"] = "i", ["Ị"] = "i",
    ["ò"] = "o", ["ó"] = "o", ["ỏ"] = "o", ["õ"] = "o", ["ọ"] = "o",
    ["ô"] = "o", ["ồ"] = "o", ["ố"] = "o", ["ổ"] = "o", ["ỗ"] = "o", ["ộ"] = "o",
    ["ơ"] = "o", ["ờ"] = "o", ["ớ"] = "o", ["ở"] = "o", ["ỡ"] = "o", ["ợ"] = "o",
    ["Ò"] = "o", ["Ó"] = "o", ["Ỏ"] = "o", ["Õ"] = "o", ["Ọ"] = "o",
    ["Ô"] = "o", ["Ồ"] = "o", ["Ố"] = "o", ["Ổ"] = "o", ["Ỗ"] = "o", ["Ộ"] = "o",
    ["Ơ"] = "o", ["Ờ"] = "o", ["Ớ"] = "o", ["Ở"] = "o", ["Ỡ"] = "o", ["Ợ"] = "o",
    ["ù"] = "u", ["ú"] = "u", ["ủ"] = "u", ["ũ"] = "u", ["ụ"] = "u",
    ["ư"] = "u", ["ừ"] = "u", ["ứ"] = "u", ["ử"] = "u", ["ữ"] = "u", ["ự"] = "u",
    ["Ù"] = "u", ["Ú"] = "u", ["Ủ"] = "u", ["Ũ"] = "u", ["Ụ"] = "u",
    ["Ư"] = "u", ["Ừ"] = "u", ["Ứ"] = "u", ["Ử"] = "u", ["Ữ"] = "u", ["Ự"] = "u",
    ["ỳ"] = "y", ["ý"] = "y", ["ỷ"] = "y", ["ỹ"] = "y", ["ỵ"] = "y",
    ["Ỳ"] = "y", ["Ý"] = "y", ["Ỷ"] = "y", ["Ỹ"] = "y", ["Ỵ"] = "y",
}

local BOOK_EXTENSIONS = {
    epub = true, html = true, pdf = true, cbz = true, cbr = true,
    fb2 = true, mobi = true, azw = true, azw3 = true, djv = true,
    djvu = true, txt = true,
}

local IGNORED_DIRS = {
    ["covers"] = true,
    ["_update"] = true,
    ["settings"] = true,
    ["images"] = true,
    [".images"] = true,
    [".git"] = true,
}

function Library.fold(str)
    local res = tostring(str or "")
    for k, v in pairs(accents) do
        res = res:gsub(k, v)
    end
    return res:lower()
end

function Library.matchQuery(name, query)
    if type(query) ~= "string" or query:match("^%s*$") then return true end
    if type(name) ~= "string" then return false end
    local q = query:lower():match("^%s*(.-)%s*$")
    if q == "" then return true end
    local n = name:lower()
    if n:find(q, 1, true) ~= nil then return true end
    local folded_name = Library.fold(name)
    local folded_query = Library.fold(query):match("^%s*(.-)%s*$")
    if folded_query ~= "" and folded_name:find(folded_query, 1, true) ~= nil then
        return true
    end
    return false
end

function Library.filter(items, query)
    local out = {}
    for _, item in ipairs(items or {}) do
        local matched = false
        if type(item) == "table" then
            if Library.matchQuery(item.title, query)
                or Library.matchQuery(item.name, query)
                or Library.matchQuery(item.series, query)
                or Library.matchQuery(item.path, query) then
                matched = true
            end
        else
            matched = Library.matchQuery(tostring(item), query)
        end
        if matched then
            out[#out + 1] = item
        end
    end
    return out
end

function Library.summarize(files)
    local count, bytes = 0, 0
    for _, file in ipairs(files or {}) do
        count = count + 1
        bytes = bytes + (tonumber(file.size) or 0)
    end
    return { count = count, bytes = bytes }
end

function Library.recent(files, limit)
    limit = tonumber(limit) or 10
    local sorted = {}
    for _, file in ipairs(files or {}) do sorted[#sorted + 1] = file end
    table.sort(sorted, function(a, b)
        return (tonumber(a.mtime) or 0) > (tonumber(b.mtime) or 0)
    end)
    local out = {}
    for i = 1, math.min(limit, #sorted) do out[#out + 1] = sorted[i] end
    return out
end

function Library.formatBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 * 1024 then
        return string.format("%.1f GB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%d KB", math.floor(bytes / 1024))
    end
    return tostring(bytes) .. " B"
end

function Library.isBookFile(name)
    if type(name) ~= "string" then return false end
    if name:sub(1, 1) == "." then return false end
    if name:match("%.part$") then return false end
    if name:match("^_selftest%..*$") then return false end
    local ext = name:match("%.([^.]+)$")
    if not ext then return false end
    return BOOK_EXTENSIONS[ext:lower()] == true
end

-- Scan one directory level via injected list/stat functions.
-- listFn(dir) -> array of names; statFn(path) -> {mode=, size=, mtime=}.
function Library.scanFlat(dir, listFn, statFn)
    if type(dir) ~= "string" or type(listFn) ~= "function" then return {} end
    local names = listFn(dir) or {}
    local out = {}
    for _, name in ipairs(names) do
        if name ~= "." and name ~= ".." then
            local path = dir .. "/" .. name
            local info
            if type(statFn) == "function" then
                local ok, result = pcall(statFn, path)
                if ok then info = result end
            end
            out[#out + 1] = {
                name = name,
                path = path,
                size = tonumber(info and info.size) or 0,
                mtime = tonumber(info and info.mtime) or 0,
                is_dir = info and info.mode == "directory",
            }
        end
    end
    return out
end

local function defaultLfs()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then return lfs end
    ok, lfs = pcall(require, "lfs")
    if ok and lfs then return lfs end
    return nil
end

local function defaultReadJson(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then return nil end
    local ok_json, Json = pcall(require, "json")
    if not ok_json or not Json or not Json.decode then return nil end
    local ok, decoded = pcall(Json.decode, content)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

-- Collect books under root directory up to max_depth (default 5).
-- Injected opts: { listFn, statFn, readJson, max_depth }
function Library.collect(root, opts)
    opts = opts or {}
    local out = {}
    if type(root) ~= "string" or root == "" then return out end

    local lfs = defaultLfs()
    local listFn = opts.listFn
    if not listFn and lfs and type(lfs.dir) == "function" then
        listFn = function(dir)
            local ok, iter, state = pcall(lfs.dir, dir)
            if not ok or not iter then return nil end
            local names = {}
            for name in iter, state do names[#names + 1] = name end
            return names
        end
    end
    local statFn = opts.statFn
    if not statFn and lfs and type(lfs.attributes) == "function" then
        statFn = function(path, req)
            local ok, res = pcall(lfs.attributes, path, req)
            if ok then return res end
            return nil
        end
    end
    local readJson = opts.readJson or defaultReadJson
    if not listFn or not statFn then return out end

    local max_depth = tonumber(opts.max_depth) or 5
    local series_cache = {}

    local function getSeriesTitle(dir, category, series_id)
        if series_cache[dir] then return series_cache[dir] end
        local title = series_id
        if category == "novels" then
            local index = readJson(dir .. "/index.json")
            if index and type(index.title) == "string" and index.title ~= "" then
                title = index.title
            end
        elseif category == "comics" then
            local manifest = readJson(dir .. "/manifest.json")
            if manifest and type(manifest.title) == "string" and manifest.title ~= "" then
                title = manifest.title
            end
        end
        series_cache[dir] = title
        return title
    end

    local function scan(dir, depth, category, series_title)
        if depth > max_depth then return end
        local names = listFn(dir)
        if not names then return end

        for _, name in ipairs(names) do
            if name ~= "." and name ~= ".." and not name:match("^%.") then
                local path = dir .. "/" .. name
                local mode
                if type(statFn) == "function" then
                    local info = statFn(path, "mode")
                    if type(info) == "table" then
                        mode = info.mode
                    else
                        mode = info
                    end
                end

                if mode == "directory" then
                    if not IGNORED_DIRS[name] then
                        local next_cat = category
                        local next_series = series_title
                        if depth == 1 then
                            if name == "novels" or name == "comics" or name == "received" or name == "news" then
                                next_cat = name
                            end
                        elseif depth == 3 and (category == "novels" or category == "comics") then
                            next_series = getSeriesTitle(path, category, name)
                        end
                        scan(path, depth + 1, next_cat, next_series)
                    end
                elseif mode == "file" and Library.isBookFile(name) then
                    local size = 0
                    local mtime = 0
                    local size_info = statFn(path, "size")
                    if type(size_info) == "table" then
                        size = tonumber(size_info.size) or 0
                        mtime = tonumber(size_info.modification) or 0
                    else
                        size = tonumber(size_info) or 0
                        local time_info = statFn(path, "modification")
                        mtime = tonumber(time_info) or 0
                    end

                    local display_title = name
                    if series_title and series_title ~= "" then
                        if name:match("%.epub$") and name:lower() == (series_title:lower() .. ".epub") then
                            display_title = name
                        else
                            display_title = series_title .. " - " .. name
                        end
                    end

                    out[#out + 1] = {
                        name = name,
                        title = display_title,
                        series = series_title,
                        category = category or "other",
                        path = path,
                        size = size,
                        mtime = mtime,
                    }
                end
            end
        end
    end

    scan(root, 1, nil, nil)
    return out
end

return Library
