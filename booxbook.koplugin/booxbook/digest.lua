-- Daily digest: bundle already-downloaded news HTML files into one EPUB.
-- Reuses booxbook.epub writer; no network here.
local Digest = { MAX_FILES = 20 }

function Digest.pick(files, limit)
    limit = math.min(tonumber(limit) or #files, Digest.MAX_FILES)
    local out = {}
    for i = 1, math.min(limit, #(files or {})) do
        local file = files[i]
        local path = type(file) == "table" and file.path or file
        local title = type(file) == "table" and (file.title or file.name) or nil
        if type(path) == "string" and path:match("%.html$") then
            out[#out + 1] = { path = path, title = title or path:match("([^/]+)$") or path }
        end
    end
    return out
end

function Digest.readChapter(path, max_bytes)
    max_bytes = tonumber(max_bytes) or (512 * 1024)
    local file = io.open(path, "rb")
    if not file then return nil, "open" end
    local body = file:read("*a") or ""
    file:close()
    if #body > max_bytes then body = body:sub(1, max_bytes) end
    -- Strip to readable text container: keep body if present.
    local inner = body:match("<body[^>]*>(.*)</body>") or body
    if inner == "" then return nil, "empty" end
    return inner
end

function Digest.filename()
    return "digest-" .. os.date("%Y%m%d") .. ".epub"
end

-- Bundle picked HTML files into one EPUB at dest_path.
-- deps = { read = Digest.readChapter, write = Epub.write } (injectable for tests).
function Digest.build(dest_path, files, deps)
    if type(dest_path) ~= "string" or dest_path == "" then
        return nil, "no destination"
    end
    deps = deps or {}
    local read = deps.read or Digest.readChapter
    local write = deps.write
    if not write then
        local ok, Epub = pcall(require, "booxbook.epub")
        if not ok or not Epub or not Epub.write then return nil, "no epub writer" end
        write = Epub.write
    end
    local picked = Digest.pick(files, Digest.MAX_FILES)
    if #picked == 0 then return nil, "no html" end
    local chapters = {}
    for _, entry in ipairs(picked) do
        local body, err = read(entry.path)
        if not body then return nil, err or "read failed" end
        chapters[#chapters + 1] = { title = entry.title, html = body }
    end
    local ok, err = write(dest_path, { title = "BooxBook Digest " .. os.date("%Y-%m-%d"), chapters = chapters })
    if not ok then return nil, err end
    return dest_path
end

return Digest
