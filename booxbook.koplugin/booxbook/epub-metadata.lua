local Html = require("booxbook.html")
local Metadata = {}

function Metadata.xml(book)
    local fields = {}
    local function add(tag, value)
        if type(value) == "string" and value ~= "" then
            fields[#fields + 1] = "<dc:" .. tag .. ">" .. Html.escape(value) .. "</dc:" .. tag .. ">"
        end
    end
    add("creator", book.author)
    add("description", book.description)
    add("source", book.url)
    add("publisher", book.publisher)
    add("date", book.date)
    add("rights", book.rights)
    for _, tag in ipairs(type(book.tags) == "table" and book.tags or {}) do add("subject", tag) end
    if book.cover_data then fields[#fields + 1] = '<meta name="cover" content="cover-image"/>' end
    return table.concat(fields, "\n    ")
end

function Metadata.cover(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local data = file:read(2 * 1024 * 1024 + 1)
    file:close()
    if not data or #data > 2 * 1024 * 1024 then return nil, "cover too large or empty" end
    local ext, mime
    if data:sub(1, 3) == "\255\216\255" then ext, mime = "jpg", "image/jpeg"
    elseif data:sub(1, 8) == "\137PNG\13\10\26\10" then ext, mime = "png", "image/png"
    elseif data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a" then ext, mime = "gif", "image/gif"
    else return nil, "EPUB cover requires JPEG, PNG or GIF" end
    return { data = data, name = "cover." .. ext, mime = mime }
end

return Metadata
