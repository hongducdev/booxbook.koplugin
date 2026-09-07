local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")

local Images = {}

-- Attribute names are matched as whole tokens (src must not match data-src).
local function attributes(tag, decode)
    local attrs = {}
    tag = tag:gsub("([%w:_-]+)%s*=%s*([\"'])(.-)%2", function(key, _, value)
        attrs[key:lower()] = decode(value)
        return ""
    end)
    for key, value in tag:gmatch("([%w:_-]+)%s*=%s*([^%s>]+)") do
        attrs[key:lower()] = decode(value)
    end
    return attrs
end

local function imageUrl(attrs, base)
    for _, key in ipairs({ "data-original", "data-src", "data-lazy-src", "src", "data-srcset", "srcset" }) do
        local value = attrs[key]
        if value then
            if key:find("srcset", 1, true) then value = value:match("^%s*([^%s,]+)") end
            value = value and value:match("^%s*(.-)%s*$")
            if value and value ~= "" and not value:find("[%c]")
                and not value:match("^#") and not value:match("^[%a][%w+.-]*:") then
                value = Http.resolveUrl(base, value)
            end
            if value and value:match("^https?://[^/%s]+") and not value:find("[%c]") then
                return value
            end
        end
    end
end

local function extension(body)
    if body:sub(1, 8) == "\137PNG\13\10\26\10" then return "png" end
    if body:sub(1, 3) == "\255\216\255" then return "jpg" end
    if body:sub(1, 6) == "GIF87a" or body:sub(1, 6) == "GIF89a" then return "gif" end
    if body:sub(1, 4) == "RIFF" and body:sub(9, 12) == "WEBP" then return "webp" end
end

Images.extension = extension

-- No path = pure rendering. A path is supplied only for the selected article.
function Images.process(body, base, path, decode)
    local cached, attempts, bytes = {}, 0, 0
    local dir = path and (path .. ".images")
    local ready, file_index = nil, 0
    return body:gsub("<%s*[Ii][Mm][Gg]%f[%W][^>]*>", function(tag)
        local attrs = attributes(tag, decode)
        local alt = Html.escape(attrs.alt or "")
        if not Settings.includeImages() then return "" end
        local url = imageUrl(attrs, base)
        local fallback = alt ~= "" and ("<p>" .. alt .. "</p>") or ""
        if not url then return fallback end
        local src = url
        if path then
            if cached[url] == nil then
                cached[url] = false
                -- ponytail: bound work on image-heavy pages; raise caps if needed.
                if attempts < 20 and bytes < 10 * 1024 * 1024 then
                    attempts = attempts + 1
                    local success, ok, _, data = pcall(Http.get, url, {
                        referer = base, timeout = 5, maxtime = 8,
                        headers = { accept = "image/jpeg,image/png,image/gif,image/webp" },
                    })
                    if success and ok and type(data) == "string" then
                        bytes = bytes + #data
                        local ext = extension(data)
                        if ext and #data <= 2 * 1024 * 1024 and bytes <= 10 * 1024 * 1024 then
                            if ready == nil then ready = Settings.ensureDir(dir) end
                            -- Keep assets referenced by the previous HTML intact on failed refresh.
                            local name
                            repeat
                                file_index = file_index + 1
                                name = tostring(file_index) .. "." .. ext
                                local existing = io.open(dir .. "/" .. name, "rb")
                                if not existing then break end
                                existing:close()
                            until false
                            if ready and Html.writeFile(dir .. "/" .. name, data) then
                                cached[url] = dir:match("([^/]+)$") .. "/" .. name
                            end
                        end
                    end
                end
            end
            src = cached[url]
            if not src then return fallback end
        end
        return '<img src="' .. Html.escape(src) .. '" alt="' .. alt .. '"/>'
    end)
end

return Images
