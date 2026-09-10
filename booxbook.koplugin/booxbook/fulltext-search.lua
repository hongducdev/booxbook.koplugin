local FulltextSearch = {}

local ok_settings, Settings = pcall(require, "booxbook.store.settings")
local ok_html, Html = pcall(require, "booxbook.html")

local DEFAULTS = {
    max_matches = 30,
    max_file_bytes = 256 * 1024,
    max_files_scanned = 200,
    snippet_context = 40,
    highlight_prefix = "[",
    highlight_suffix = "]",
}

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

local function settingNumber(key, fallback)
    if ok_settings and Settings and type(Settings.get) == "function" then
        local ok, value = pcall(Settings.get, key)
        value = ok and tonumber(value) or nil
        if value and value > 0 then return value end
    end
    return fallback
end

local function optNumber(opts, key)
    local value = opts and tonumber(opts[key]) or nil
    if value and value > 0 then return value end
    return settingNumber("fulltext_" .. key, DEFAULTS[key])
end

local function optString(opts, key)
    local value = opts and opts[key]
    if type(value) == "string" then return value end
    return DEFAULTS[key]
end

local function trim(text)
    return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function cleanWhitespace(text)
    text = tostring(text or "")
    text = text:gsub("[%z\1-\31]+", " ")
    text = text:gsub("%s+", " ")
    return trim(text)
end

local function utf8Len(first_byte)
    if not first_byte then return 0 end
    if first_byte < 0x80 then return 1 end
    if first_byte >= 0xC2 and first_byte < 0xE0 then return 2 end
    if first_byte >= 0xE0 and first_byte < 0xF0 then return 3 end
    if first_byte >= 0xF0 and first_byte < 0xF5 then return 4 end
    return 1
end

local function nextChar(text, pos)
    local len = utf8Len(text:byte(pos))
    if pos + len - 1 > #text then len = 1 end
    return text:sub(pos, pos + len - 1), pos + len
end

local function foldedWithMap(text)
    local folded, map_start, map_end = {}, {}, {}
    local folded_len = 0
    local pos = 1
    text = tostring(text or "")
    while pos <= #text do
        local start_pos = pos
        local ch
        ch, pos = nextChar(text, pos)
        local replacement = accents[ch] or ch:lower()
        folded[#folded + 1] = replacement
        for i = 1, #replacement do
            folded_len = folded_len + 1
            map_start[folded_len] = start_pos
            map_end[folded_len] = pos - 1
        end
    end
    return table.concat(folded), map_start, map_end
end

function FulltextSearch.fold(text)
    local folded = foldedWithMap(text)
    return folded
end

function FulltextSearch.stripHtml(raw)
    local text = tostring(raw or "")
    text = text:gsub("<!%-%-.-%-%->", " ")
    text = text:gsub("<%s*[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.-<%s*/%s*[Ss][Cc][Rr][Ii][Pp][Tt]%s*>", " ")
    text = text:gsub("<%s*[Ss][Tt][Yy][Ll][Ee][^>]*>.-<%s*/%s*[Ss][Tt][Yy][Ll][Ee]%s*>", " ")
    text = text:gsub("<%s*/?%s*[Bb][Rr][^>]*>", " ")
    text = text:gsub("<%s*/%s*[PpDdIiVvHh][^>]*>", " ")
    text = text:gsub("<[^>]*>", " ")
    if ok_html and Html and type(Html.decode) == "function" then
        text = Html.decode(text)
    else
        text = text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&amp;", "&")
    end
    return cleanWhitespace(text)
end

local function charSpans(text)
    local starts, ends = {}, {}
    local pos = 1
    while pos <= #text do
        local start_pos = pos
        local _
        _, pos = nextChar(text, pos)
        starts[#starts + 1] = start_pos
        ends[#ends + 1] = pos - 1
    end
    return starts, ends
end

local function charIndexAt(starts, ends, byte_pos)
    local lo, hi = 1, #starts
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if byte_pos < starts[mid] then
            hi = mid - 1
        elseif byte_pos > ends[mid] then
            lo = mid + 1
        else
            return mid
        end
    end
    return math.max(1, math.min(#starts, lo))
end

local function makeSnippet(text, start_byte, end_byte, opts, starts, ends)
    if #text == 0 then return "" end
    local context = optNumber(opts, "snippet_context")
    local first_match = charIndexAt(starts, ends, start_byte)
    local last_match = charIndexAt(starts, ends, end_byte)
    local first = math.max(1, first_match - context)
    local last = math.min(#starts, last_match + context)
    local snippet_start = starts[first] or 1
    local snippet_end = ends[last] or #text
    local snippet = text:sub(snippet_start, snippet_end)
    local rel_start = start_byte - snippet_start + 1
    local rel_end = end_byte - snippet_start + 1
    local prefix = optString(opts, "highlight_prefix")
    local suffix = optString(opts, "highlight_suffix")
    snippet = snippet:sub(1, rel_start - 1) .. prefix .. snippet:sub(rel_start, rel_end) .. suffix .. snippet:sub(rel_end + 1)
    if first > 1 then snippet = "..." .. snippet end
    if last < #starts then snippet = snippet .. "..." end
    return snippet
end

local function defaultReader(path, max_bytes)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read(max_bytes)
    file:close()
    return content or ""
end

local function isSearchableFile(path)
    if type(path) ~= "string" then return false end
    local ext = path:match("%.([^%.\\/]+)$")
    if not ext then return false end
    ext = ext:lower()
    return ext == "html" or ext == "htm" or ext == "txt"
end

function FulltextSearch.searchFile(path, query, opts)
    opts = opts or {}
    local results = {}
    if type(path) ~= "string" or path == "" then return results end
    local folded_query = trim(FulltextSearch.fold(query or ""))
    if folded_query == "" then return results end

    local max_matches = optNumber(opts, "max_matches")
    local max_file_bytes = optNumber(opts, "max_file_bytes")
    local reader = opts.file_reader or defaultReader
    local ok, raw = pcall(reader, path, max_file_bytes)
    if not ok or type(raw) ~= "string" then return results end
    if #raw > max_file_bytes then raw = raw:sub(1, max_file_bytes) end

    local text = FulltextSearch.stripHtml(raw)
    local folded, map_start, map_end = foldedWithMap(text)
    local starts, ends
    local pos = 1
    while #results < max_matches do
        local found_start, found_end = folded:find(folded_query, pos, true)
        if not found_start then break end
        local original_start = map_start[found_start]
        local original_end = map_end[found_end]
        if original_start and original_end then
            if not starts then starts, ends = charSpans(text) end
            results[#results + 1] = {
                path = path,
                match = text:sub(original_start, original_end),
                snippet = makeSnippet(text, original_start, original_end, opts, starts, ends),
                byte_start = original_start,
                byte_end = original_end,
            }
        end
        pos = found_end + 1
    end
    results.stats = {
        matches = #results,
        truncated = #raw >= max_file_bytes,
        bytes_read = #raw,
    }
    return results
end

local function defaultLfs()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then return lfs end
    ok, lfs = pcall(require, "lfs")
    if ok and lfs then return lfs end
    return nil
end

local function defaultLister()
    local lfs = defaultLfs()
    if not lfs or type(lfs.dir) ~= "function" then return nil end
    return function(dir)
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok or not iter then return nil end
        local entries = {}
        for name in iter, state do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local attrs = lfs.attributes and lfs.attributes(path) or nil
                entries[#entries + 1] = {
                    name = name,
                    path = path,
                    is_dir = attrs and attrs.mode == "directory",
                    mode = attrs and attrs.mode,
                }
            end
        end
        return entries
    end
end

local function joinPath(dir, name)
    if dir:match("[/\\]$") then return dir .. name end
    return dir .. "/" .. name
end

local function normalizeEntry(dir, entry)
    local name, path, is_dir, mode
    if type(entry) == "table" then
        path = entry.path
        name = entry.name or (type(path) == "string" and path:match("([^/\\]+)$"))
        mode = entry.mode
        is_dir = entry.is_dir == true or mode == "directory"
    elseif type(entry) == "string" then
        name = entry
    end
    if type(name) ~= "string" or name == "" or name == "." or name == ".." then return nil end
    path = path or joinPath(dir, name)
    if is_dir == nil then
        is_dir = not isSearchableFile(path)
    end
    return { name = name, path = path, is_dir = is_dir }
end

function FulltextSearch.searchTree(root_dir, query, opts, file_lister, file_reader)
    opts = opts or {}
    local results = {}
    if type(root_dir) ~= "string" or root_dir == "" then return results end
    local folded_query = trim(FulltextSearch.fold(query or ""))
    if folded_query == "" then return results end

    local lister = file_lister or defaultLister()
    if type(lister) ~= "function" then return results end

    local max_matches = optNumber(opts, "max_matches")
    local max_files = optNumber(opts, "max_files_scanned")
    local max_file_bytes = optNumber(opts, "max_file_bytes")
    local dirs, dir_index = { root_dir }, 1
    local files_scanned = 0
    local stopped_by

    while dirs[dir_index] and #results < max_matches and files_scanned < max_files do
        local dir = dirs[dir_index]
        dir_index = dir_index + 1
        local ok, entries = pcall(lister, dir)
        if ok and type(entries) == "table" then
            for _, raw_entry in ipairs(entries) do
                local entry = normalizeEntry(dir, raw_entry)
                if entry then
                    if entry.is_dir then
                        dirs[#dirs + 1] = entry.path
                    elseif isSearchableFile(entry.path) then
                        files_scanned = files_scanned + 1
                        local remaining = max_matches - #results
                        local file_opts = {}
                        for k, v in pairs(opts) do file_opts[k] = v end
                        file_opts.max_matches = remaining
                        file_opts.max_file_bytes = max_file_bytes
                        file_opts.file_reader = file_reader or opts.file_reader
                        local matches = FulltextSearch.searchFile(entry.path, folded_query, file_opts)
                        for _, match in ipairs(matches) do
                            results[#results + 1] = match
                            if #results >= max_matches then
                                stopped_by = "max_matches"
                                break
                            end
                        end
                        if #results >= max_matches or files_scanned >= max_files then break end
                    end
                end
            end
        end
    end
    if not stopped_by and files_scanned >= max_files then stopped_by = "max_files_scanned" end
    results.stats = {
        files_scanned = files_scanned,
        matches = #results,
        stopped_by = stopped_by,
    }
    return results
end

FulltextSearch.DEFAULTS = DEFAULTS

return FulltextSearch
