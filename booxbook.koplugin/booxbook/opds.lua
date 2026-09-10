-- OPDS 1.2 catalog for books stored in BooxBook's local library tree.
local Html = require("booxbook.html")

local Opds = {}

local MIME_TYPES = {
    epub = "application/epub+zip",
    cbz = "application/x-cbz",
    html = "text/html",
    pdf = "application/pdf",
}

local LIBRARY_DIRS = { "novels", "comics", "news", "received" }

local function basename(path)
    return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function titleFor(path)
    local name = basename(path)
    return (name:gsub("%.[^.]*$", ""))
end

local function urlEncode(path)
    return tostring(path or ""):gsub("([^A-Za-z0-9_%.%-%~%/])", function(char)
        return string.format("%%%02X", char:byte())
    end)
end

local function entry(id, title, updated, href, mime, size)
    local length = ""
    if type(size) == "number" and size >= 0 then
        length = string.format(' length="%d"', size)
    end
    return string.format(
        '<entry><id>%s</id><title>%s</title><updated>%s</updated>' ..
        '<link rel="http://opds-spec.org/acquisition" type="%s" href="%s"%s/></entry>',
        Html.escape(id), Html.escape(title), Html.escape(updated),
        Html.escape(mime or "application/octet-stream"), Html.escape(href), length)
end

function Opds.mimeType(filename)
    if type(filename) ~= "string" then return end
    local ext = filename:match("%.([^.]+)$")
    if not ext then return end
    return MIME_TYPES[ext:lower()]
end

function Opds.catalog(files, base, title)
    base = base or "/opds"
    title = title or "BooxBook Thư viện"
    local updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local parts = {}
    parts[#parts + 1] = [[<?xml version="1.0" encoding="UTF-8"?>]]
    parts[#parts + 1] = [[<feed xmlns="http://www.w3.org/2005/Atom" ]] ..
        [[xmlns:opds="http://opds-spec.org/2010/catalog">]]
    parts[#parts + 1] = [[<id>urn:booxbook:library</id><title>]] .. Html.escape(title) ..
        [[</title><updated>]] .. updated .. [[</updated>]]
    parts[#parts + 1] = [[<link rel="self" type="application/atom+xml;profile=opds-catalog;kind=acquisition" href="]] ..
        Html.escape(base) .. [["/>]]
    for _, file in ipairs(files or {}) do
        local path = type(file) == "table" and (file.relpath or file.path or file.name) or tostring(file)
        if type(path) == "string" and path ~= "" then
            local mime = type(file) == "table" and file.mime or Opds.mimeType(path)
            if mime then
                local file_title = type(file) == "table" and file.title or nil
                file_title = file_title or titleFor(path)
                local size = type(file) == "table" and tonumber(file.size) or nil
                local href = base .. "/file/" .. urlEncode(path)
                parts[#parts + 1] = entry("urn:booxbook:" .. path, file_title, updated, href, mime, size)
            end
        end
    end
    parts[#parts + 1] = [[</feed>]]
    return table.concat(parts, "\n")
end

local function attr(lfs, path, key)
    if not (lfs and lfs.attributes) then return end
    local ok, value = pcall(lfs.attributes, path, key)
    if ok and value ~= nil then return value end
    ok, value = pcall(lfs.attributes, path)
    if ok and type(value) == "table" then return value[key] end
end

local function appendFile(files, root, path, relpath, lfs)
    local mime = Opds.mimeType(relpath)
    if not mime then return end
    files[#files + 1] = {
        relpath = relpath,
        title = titleFor(relpath),
        size = tonumber(attr(lfs, path, "size")),
        mime = mime,
    }
end

local function scan(files, root, path, relpath, lfs)
    local mode = attr(lfs, path, "mode")
    if mode == "directory" then
        local ok, iter, state = pcall(lfs.dir, path)
        if not (ok and iter) then return end
        for name in iter, state do
            if name ~= "." and name ~= ".." then
                local child = path .. "/" .. name
                local child_rel = relpath ~= "" and (relpath .. "/" .. name) or name
                scan(files, root, child, child_rel, lfs)
            end
        end
    elseif mode == "file" or mode == nil then
        appendFile(files, root, path, relpath, lfs)
    end
end

function Opds.fullCatalog(root_dir, base, collector_fn)
    local files = {}
    if type(collector_fn) == "function" then
        local returned = collector_fn(root_dir, LIBRARY_DIRS, function(file)
            files[#files + 1] = file
        end)
        if type(returned) == "table" then files = returned end
        if returned ~= nil or #files > 0 then
            return Opds.catalog(files, base, "BooxBook Thư viện")
        end
    end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok_lfs and lfs and lfs.dir then
        for _, dir in ipairs(LIBRARY_DIRS) do
            local path = tostring(root_dir or "") .. "/" .. dir
            scan(files, root_dir, path, dir, lfs)
        end
    end
    table.sort(files, function(a, b) return (a.relpath or "") < (b.relpath or "") end)
    return Opds.catalog(files, base, "BooxBook Thư viện")
end

-- Queue endpoint: POST /queue with plain-text http(s) URL in body.
-- Returns normalized URL or nil + error. Storage is a queue.txt file.
function Opds.normalizeQueueUrl(body)
    if type(body) ~= "string" then return nil, "empty" end
    local url = body:match("^%s*(.-)%s*$")
    if not url or url == "" or #url > 2048 then return nil, "empty" end
    if not url:match("^https?://[^ /]+") then return nil, "url" end
    return url
end

return Opds
