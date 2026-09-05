-- Local cover cache for novel grids. Downloads only when a card is visible.
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")

local Covers = {
    MAX_BYTES = 256 * 1024,
}

local function extension(body)
    if body:sub(1, 8) == "\137PNG\13\10\26\10" then return "png" end
    if body:sub(1, 3) == "\255\216\255" then return "jpg" end
    if body:sub(1, 6) == "GIF87a" or body:sub(1, 6) == "GIF89a" then return "gif" end
    if body:sub(1, 4) == "RIFF" and body:sub(9, 12) == "WEBP" then return "webp" end
end

local function hash(value)
    local h = 2166136261
    for i = 1, #value do
        h = (h * 16777619 + value:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

function Covers.dir(source_id)
    return Settings.downloadDir() .. "/covers/" .. tostring(source_id or "unknown")
end

function Covers.pathFor(source_id, url, ext)
    return Covers.dir(source_id) .. "/" .. hash(tostring(url or "")) .. "." .. (ext or "bin")
end

function Covers.find(source_id, url)
    if type(url) ~= "string" or url == "" or not url:match("^https?://") then return nil end
    local root = Covers.dir(source_id)
    local stem = hash(url)
    for _, ext in ipairs({ "jpg", "png", "webp", "gif" }) do
        local path = root .. "/" .. stem .. "." .. ext
        local file = io.open(path, "rb")
        if file then
            file:close()
            return path
        end
    end
end

-- Returns a local file path, or nil on any failure (caller shows title fallback).
function Covers.fetch(source_id, url, opts)
    opts = opts or {}
    if type(url) ~= "string" or url == "" or not url:match("^https?://") or url:find("[%c]") then
        return nil
    end
    local existing = Covers.find(source_id, url)
    if existing then return existing end
    local dir = Covers.dir(source_id)
    if not Settings.ensureDir(dir) then return nil end
    local ok, _, body = Http.get(url, {
        referer = opts.referer,
        cookies = opts.cookies,
        delay_ms = opts.delay_ms or 0,
        timeout = opts.timeout or 5,
        maxtime = opts.maxtime or 8,
        headers = { accept = "image/jpeg,image/png,image/gif,image/webp" },
    })
    if not ok or type(body) ~= "string" or #body == 0 or #body > Covers.MAX_BYTES then
        return nil
    end
    local ext = extension(body)
    if not ext then return nil end
    local path = Covers.pathFor(source_id, url, ext)
    local file = io.open(path, "wb")
    if not file then return nil end
    local written = file:write(body)
    file:close()
    if not written then
        os.remove(path)
        return nil
    end
    return path
end

return Covers
