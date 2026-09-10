-- OPML 2.0 parser & generator for RSS feeds.
-- Lightweight, zero external dependencies, handles entities and nested outlines.
local Opml = {}

local function trim(str)
    return tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function safeUtf8Char(raw, num)
    num = tonumber(num)
    if not num or num <= 0 or num > 0x10FFFF or (num >= 0xD800 and num <= 0xDFFF) then
        return raw
    end
    if num < 0x80 then
        return string.char(num)
    elseif num < 0x800 then
        return string.char(
            0xC0 + math.floor(num / 0x40),
            0x80 + (num % 0x40)
        )
    elseif num < 0x10000 then
        return string.char(
            0xE0 + math.floor(num / 0x1000),
            0x80 + (math.floor(num / 0x40) % 0x40),
            0x80 + (num % 0x40)
        )
    else
        return string.char(
            0xF0 + math.floor(num / 0x40000),
            0x80 + (math.floor(num / 0x1000) % 0x40),
            0x80 + (math.floor(num / 0x40) % 0x40),
            0x80 + (num % 0x40)
        )
    end
end

local named_entities = {
    amp = "&",
    apos = "'",
    gt = ">",
    lt = "<",
    nbsp = " ",
    quot = '"',
}

function Opml.decodeEntities(str)
    if type(str) ~= "string" then return "" end
    return str:gsub("^%s*<!%[CDATA%[", "")
        :gsub("%]%]>%s*$", "")
        :gsub("(&#[Xx](%x+);)", function(raw, hex)
            return safeUtf8Char(raw, tonumber(hex, 16))
        end)
        :gsub("(&#(%d+);)", function(raw, num)
            return safeUtf8Char(raw, tonumber(num, 10))
        end)
        :gsub("&([%a][%w]+);", function(name)
            return named_entities[name] or named_entities[name:lower()] or ("&" .. name .. ";")
        end)
end

function Opml.escape(str)
    if type(str) ~= "string" then str = tostring(str or "") end
    return str:gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&apos;")
end

local function findTagEnd(xml, start_pos)
    local quote
    local i = start_pos
    while i <= #xml do
        local ch = xml:sub(i, i)
        if quote then
            if ch == quote then quote = nil end
        elseif ch == '"' or ch == "'" then
            quote = ch
        elseif ch == ">" then
            return i
        end
        i = i + 1
    end
    return nil
end

local function parseAttrs(tag_body)
    local attrs = {}
    for name, value in tag_body:gmatch('([%w_:%.-]+)%s*=%s*"([^"]*)"') do
        attrs[name:lower()] = value
    end
    for name, value in tag_body:gmatch("([%w_:%.-]+)%s*=%s*'([^']*)'") do
        attrs[name:lower()] = value
    end
    for name, value in tag_body:gmatch("([%w_:%.-]+)%s*=%s*([^%s/>]+)") do
        local key = name:lower()
        if attrs[key] == nil and value:sub(1, 1) ~= '"' and value:sub(1, 1) ~= "'" then
            attrs[key] = value
        end
    end
    return attrs
end

local function nextOutline(xml, pos)
    local start_pos, name_end = xml:find("<%s*[Oo][Uu][Tt][Ll][Ii][Nn][Ee]", pos)
    while start_pos do
        local boundary = xml:sub(name_end + 1, name_end + 1)
        if boundary == "" or boundary:match("[%s>/]") then
            local tag_end = findTagEnd(xml, name_end + 1)
            if not tag_end then return nil end
            return start_pos, tag_end, xml:sub(name_end + 1, tag_end - 1)
        end
        start_pos, name_end = xml:find("<%s*[Oo][Uu][Tt][Ll][Ii][Nn][Ee]", name_end + 1)
    end
    return nil
end

function Opml.parse(xml)
    if type(xml) ~= "string" or xml == "" then return {} end
    xml = xml:gsub("^\239\187\191", ""):gsub("<!%-%-.-%-%->", "")

    local feeds = {}
    local seen = {}
    local pos = 1

    while true do
        local _, tag_end, tag_body = nextOutline(xml, pos)
        if not tag_body then break end
        pos = tag_end + 1

        local attrs = parseAttrs(tag_body)
        local xml_url = attrs.xmlurl or attrs.url
        xml_url = trim(Opml.decodeEntities(xml_url))

        if xml_url:match("^https?://") and not seen[xml_url] then
            seen[xml_url] = true

            local display_title = trim(Opml.decodeEntities(attrs.title or attrs.text or xml_url))
            if display_title == "" then display_title = xml_url end

            feeds[#feeds + 1] = {
                title = display_title,
                xmlUrl = xml_url,
                htmlUrl = trim(Opml.decodeEntities(attrs.htmlurl or "")),
            }
        end
    end

    return feeds
end

function Opml.generate(feeds, title)
    local doc_title = trim(title)
    if doc_title == "" then doc_title = "BooxBook RSS Feeds" end

    local parts = {}
    local seen = {}
    parts[#parts + 1] = '<?xml version="1.0" encoding="UTF-8"?>'
    parts[#parts + 1] = '<opml version="2.0">'
    parts[#parts + 1] = '  <head>'
    parts[#parts + 1] = '    <title>' .. Opml.escape(doc_title) .. '</title>'
    parts[#parts + 1] = '    <dateCreated>' .. os.date("!%a, %d %b %Y %H:%M:%S GMT") .. '</dateCreated>'
    parts[#parts + 1] = '  </head>'
    parts[#parts + 1] = '  <body>'

    for _, feed in ipairs(feeds or {}) do
        local url = type(feed) == "table" and (feed.xmlUrl or feed.xmlurl or feed.url) or feed
        url = trim(url)
        if url:match("^https?://") and not seen[url] then
            seen[url] = true
            local item_title = type(feed) == "table" and (feed.title or feed.text) or url
            item_title = trim(item_title)
            if item_title == "" then item_title = url end
            local html_url = type(feed) == "table" and feed.htmlUrl or ""

            parts[#parts + 1] = string.format(
                '    <outline text="%s" title="%s" type="rss" xmlUrl="%s" htmlUrl="%s"/>',
                Opml.escape(item_title),
                Opml.escape(item_title),
                Opml.escape(url),
                Opml.escape(trim(html_url))
            )
        end
    end

    parts[#parts + 1] = '  </body>'
    parts[#parts + 1] = '</opml>'
    return table.concat(parts, "\n")
end

return Opml
