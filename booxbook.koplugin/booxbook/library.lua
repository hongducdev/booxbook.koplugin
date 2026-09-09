-- Offline library index: search + quota + recent. Pure functions for tests;
-- filesystem scan is injected so unit tests never touch lfs.
local Library = {}

function Library.matchQuery(name, query)
    if type(query) ~= "string" or query:match("^%s*$") then return true end
    if type(name) ~= "string" then return false end
    local q = query:lower():match("^%s*(.-)%s*$")
    if q == "" then return true end
    return name:lower():find(q, 1, true) ~= nil
end

function Library.filter(items, query)
    local out = {}
    for _, item in ipairs(items or {}) do
        local name = type(item) == "table" and (item.name or item.title or item.path) or tostring(item)
        if Library.matchQuery(name, query) then
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
    if bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%d KB", math.floor(bytes / 1024))
    end
    return tostring(bytes) .. " B"
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

return Library
