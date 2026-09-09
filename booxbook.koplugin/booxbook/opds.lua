-- Minimal OPDS 1.2 catalog over the local received/ library.
-- Served by wifi-transfer-server on GET /opds (see Server route).
local Html = require("booxbook.html")

local Opds = {}

local function entry(id, title, updated, href, mime)
    return string.format(
        '<entry><id>%s</id><title>%s</title><updated>%s</updated>' ..
        '<link type="%s" href="%s"/></entry>',
        Html.escape(id), Html.escape(title), Html.escape(updated),
        Html.escape(mime or "application/octet-stream"), Html.escape(href))
end

function Opds.catalog(files, base)
    base = base or "/opds"
    local parts = {}
    parts[#parts + 1] = [[<?xml version="1.0" encoding="UTF-8"?>]] ..
        [[<feed xmlns="http://www.w3.org/2005/Atom" ]] ..
        [[xmlns:opds="http://opds-spec.org/2010/catalog">]] ..
        [[<id>urn:booxbook:received</id><title>BooxBook Thư viện</title>]] ..
        [[<updated>]] .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. [[</updated>]]
    for _, file in ipairs(files or {}) do
        local name = type(file) == "table" and (file.name or file.path) or tostring(file)
        if type(name) == "string" and name ~= "" then
            parts[#parts + 1] = entry("urn:booxbook:" .. name, name,
                os.date("!%Y-%m-%dT%H:%M:%SZ"), base .. "/file/" .. name, "application/octet-stream")
        end
    end
    parts[#parts + 1] = [[</feed>]]
    return table.concat(parts, "\n")
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
