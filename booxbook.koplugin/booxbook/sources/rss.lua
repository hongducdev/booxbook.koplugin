local Html = require("booxbook.html")
local Images = require("booxbook.article-images")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")

local Rss = {
    id = "rss",
    name = "RSS",
    kind = "news",
    capabilities = { browse = true },
}

local decode = Html.decode

local function field(block, name)
    return decode(block:match("<" .. name .. "[^>]*>(.-)</" .. name .. "%s*>") or "")
end

local function plain(text)
    return decode(text):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function atomLink(block)
    local attrs = block:match("<link([^>]*)/?>") or ""
    return decode(attrs:match('href%s*=%s*"([^"]+)"') or attrs:match("href%s*=%s*'([^']+)'") or "")
end

local function attrValue(attrs, name)
    return decode((attrs or ""):match(name .. '%s*=%s*"([^"]+)"')
        or (attrs or ""):match(name .. "%s*=%s*'([^']+)'")
        or "")
end

local function tagAttrs(block, name)
    return block:match("<" .. name .. "%s+([^>]*)/?>") or block:match("<" .. name .. "%s+([^>]*)>") or ""
end

local function thumbnail(block)
    local url = attrValue(tagAttrs(block, "media:thumbnail"), "url")
    if url ~= "" then return url end
    local media_attrs = tagAttrs(block, "media:content")
    if media_attrs ~= "" then
        local medium = attrValue(media_attrs, "medium")
        local content_type = attrValue(media_attrs, "type")
        url = attrValue(media_attrs, "url")
        if url ~= "" and (medium == "image" or content_type:match("^image/")
            or (medium == "" and content_type == "")) then
            return url
        end
    end
    local enclosure_attrs = tagAttrs(block, "enclosure")
    if enclosure_attrs ~= "" then
        local content_type = attrValue(enclosure_attrs, "type")
        url = attrValue(enclosure_attrs, "url")
        if url ~= "" and (content_type:match("^image/") or url:match("%.jpe?g") or url:match("%.png") or url:match("%.webp") or url:match("%.gif")) then
            return url
        end
    end
    url = attrValue(tagAttrs(block, "itunes:image"), "href")
    if url ~= "" then return url end
    return ""
end

local function firstImage(html)
    local attrs = tostring(html or ""):match("<%s*[Ii][Mm][Gg]%s+([^>]*)>") or ""
    return attrValue(attrs, "src")
end


function Rss.parse(xml)
    xml = tostring(xml or ""):gsub("^\239\187\191", "")
    local tag = xml:find("<entry[%s>]", 1) and "entry" or "item"
    local items = {}
    for block in xml:gmatch("<" .. tag .. "[^>]*>(.-)</" .. tag .. "%s*>") do
        local item = {
            title = plain(field(block, "title")),
            link = tag == "entry" and atomLink(block) or plain(field(block, "link")),
            summary = field(block, "content:encoded"),
            date = field(block, tag == "entry" and "updated" or "pubDate"),
            cover = thumbnail(block),
        }
        if item.summary == "" then
            item.summary = field(block, tag == "entry" and "content" or "description")
        end
        if item.summary == "" and tag == "entry" then
            item.summary = field(block, "summary")
        end
        if item.date == "" and tag == "entry" then
            item.date = field(block, "published")
        end
        if item.cover == "" then
            item.cover = firstImage(item.summary)
        end
        if item.title ~= "" and item.link:match("^https?://") then
            items[#items + 1] = item
        end
    end
    return items
end

function Rss.renderArticle(item, full_html, feed, path)
    local body
    if full_html then
        body = feed.filter_element and Html.select(full_html, feed.filter_element)
            or Html.select(full_html, "article")
            or Html.select(full_html, "body")
    end
    if not body or body == "" then
        body = item.summary ~= "" and item.summary or "<p>Không có nội dung tóm tắt.</p>"
    end
    body = Html.stripDangerous(body)
    -- Publisher headings may be inside or outside the extracted article container.
    body = body:gsub("<%s*[Hh]1%f[%W][^>]*>.-</%s*[Hh]1%s*>", "")
    body = Html.sanitize(Images.process(body, item.link, path, decode))
    local meta = "<h1>" .. Html.escape(item.title) .. "</h1>"
        .. "<p><strong>" .. Html.escape(item.date) .. "</strong></p>"
        .. '<p><a href="' .. Html.escape(item.link) .. '">Nguồn bài viết</a></p>'
    return Html.wrapDocument(item.title, meta .. body)
end

local function safeName(value)
    value = plain(value):gsub("[%c<>:\"/\\|%?%*]", "-"):gsub("%s+", " ")
    value = value:gsub("^%.*", ""):gsub("[%. ]+$", "")
    value = value:sub(1, 120):gsub("[\128-\191]+$", "")
    return value ~= "" and value or "article"
end

function Rss.list(feed, limit)
    if type(feed) ~= "table" or type(feed.url) ~= "string" or not feed.url:match("^https?://") then
        return nil, "URL RSS không hợp lệ"
    end
    limit = math.min(math.max(tonumber(limit) or 10, 1), 20)
    local ok, code, xml = Http.get(feed.url, { referer = feed.url })
    if not ok then
        return nil, tostring(code)
    end
    local items = Rss.parse(xml)
    if #items == 0 then
        return nil, "RSS/Atom không có bài hợp lệ"
    end

    while #items > limit do
        table.remove(items)
    end
    return items
end

function Rss.loadArticle(feed, item)
    if type(feed) ~= "table" or type(feed.url) ~= "string" or not feed.url:match("^https?://")
        or type(item) ~= "table" or type(item.link) ~= "string" or not item.link:match("^https?://") then
        return nil, "URL bài viết không hợp lệ"
    end
    local article
    if feed.full_article then
        local ok, _, body = Http.get(item.link, { referer = feed.url })
        if ok then article = body end
    end
    local dir = Settings.downloadDir() .. "/news/" .. safeName(feed.id or feed.title)
    if not Settings.ensureDir(dir) then
        return nil, "Không tạo được thư mục: " .. dir
    end
    -- Only selected articles are materialized: ReaderUI opens a local document.
    local path = dir .. "/" .. safeName((item.date or "") .. " " .. (item.title or "")) .. ".html"
    local written, err = Html.writeFile(path, Rss.renderArticle(item, article, feed, path))
    if not written then
        return nil, tostring(err)
    end
    return path
end

return Rss
