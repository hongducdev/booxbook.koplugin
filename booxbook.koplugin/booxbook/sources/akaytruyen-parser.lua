-- Pure parsing for AkayTruyen (akaytruyen.com). No HTTP lives here, so the
-- adapter stays small and the selectors can be unit-tested against fixtures.
--
-- Site shapes this module knows about (verified 2026-09):
--   story page   -> /truyen/<slug>
--   chapter page -> /<slug>/<chapter-slug>          (one path segment)
--   chapter TOC  -> /truyen/<slug>/search-chapters?search=&page=N   (JSON.html)
--   listings     -> one anchor per story: <a href="/truyen/<slug>"> + <img alt>
local Html = require("booxbook.html")

local Parser = {}

local MAX_SLUG = 180
local MAX_CHAPTER_SLUG = 64

local function trim(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

function Parser.plain(value)
    if value == nil then return "" end
    local text = tostring(value):gsub("<[^>]+>", " ")
    text = Html.decode(text)
    return trim(text:gsub("%s+", " "))
end

-- Listings glue status badges onto the title ("... Full", "... Hot"). The badge
-- span is dropped by taking the story-name element first, but old templates did
-- not have one, so strip the trailing markers too.
function Parser.cleanTitle(raw)
    local title = Parser.plain(raw)
    local previous
    repeat
        previous = title
        title = title:gsub("%s*[%(%-–—]+%s*[Ff]ull%s*[%)%-–—]*%s*$", "")
        title = title:gsub("%s*[%-–—]+%s*[Ff]ull%s*[%-–—]*%s*$", "")
        title = title:gsub("%s+[Ff]ull%s*$", "")
        title = title:gsub("%s+[Hh]ot%s*$", "")
        title = title:gsub("%s+[Nn]ew%s*$", "")
        title = title:gsub("%s+Đang viết%s*$", "")
        title = title:gsub("%s+Đang ra%s*$", "")
    until title == previous
    return title
end

function Parser.absolute(href)
    if type(href) ~= "string" or href == "" then return nil end
    href = Html.decode(href)
    if href:match("^https?://") then return href end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    return nil
end

local function validSlug(slug, limit)
    return type(slug) == "string" and slug ~= "" and #slug <= (limit or MAX_SLUG)
        and slug ~= "truyen" and slug:sub(1, 1) ~= "." and not slug:find("%.%.")
end

-- "/truyen/<slug>" is the only canonical story URL shape on this site.
local function storySlug(href)
    local url = Parser.absolute(href)
    if not url then return nil end
    url = url:gsub("[#?].*$", ""):gsub("/+$", "")
    local slug = url:match("^https?://[^/]+/truyen/([%w%-_%.]+)$")
    if not validSlug(slug) then return nil end
    return slug
end

local function classHas(attrs, token)
    local class = Html.attr(attrs, "class")
    if not class then return false end
    for value in class:gmatch("%S+") do
        if value == token then return true end
    end
    return false
end

local function imgPart(inner, attribute)
    return inner:match('<img[^>]-' .. attribute .. '%s*=%s*"([^"]+)"')
        or inner:match("<img[^>]-" .. attribute .. "%s*=%s*'([^']+)'")
end

-- One story card is a single anchor wrapping the cover, the title and the
-- badges. The same card markup is used by the homepage sections, genre pages
-- and search results.
function Parser.items(html, base)
    local items, seen = {}, {}
    for _, anchor in ipairs(Html.elements(html or "", "a")) do
        local slug = storySlug(Html.attr(anchor.attrs, "href"))
        if slug and not seen[slug] then
            seen[slug] = true
            local inner = anchor.inner or ""
            local named = inner:match('<h3[^>]-story%-name[^>]*>([%s%S]-)</h3>')
            local title = Parser.cleanTitle(named or imgPart(inner, "alt")
                or Html.attr(anchor.attrs, "title") or "")
            if title == "" then title = Parser.cleanTitle(inner) end
            if title ~= "" then
                local cover = imgPart(inner, "data%-src") or imgPart(inner, "src")
                local cover_url = cover and Parser.absolute(cover)
                items[#items + 1] = { ref = "/truyen/" .. slug .. "/",
                    url = base .. "/truyen/" .. slug, title = title, name = title,
                    cover = cover_url }
            end
        end
    end
    return items
end

local function slice(html, from, to)
    local start = html:find(from, 1, true)
    if not start then return nil end
    local stop = html:find(to, start + #from, true)
    return html:sub(start, (stop and stop - 1) or #html)
end

local HOT = '<div class="section-stories-hot'
local ONGOING = '<div class="section-stories-new'
local COMPLETED = '<div class="section-stories-full'
local HOME_END = '<div id="id_feedback_button"'

-- The homepage carries all three browse lists in one document. The "Đang ra"
-- cards have no cover of their own, so covers are joined from the other two
-- sections by story reference.
function Parser.homeSections(html, base)
    html = html or ""
    local hot = slice(html, HOT, ONGOING)
    local ongoing = slice(html, ONGOING, COMPLETED)
    local completed = slice(html, COMPLETED, HOME_END)
    if not hot or not ongoing or not completed then return nil end
    local groups = { hot = Parser.items(hot, base), ongoing = Parser.items(ongoing, base),
        completed = Parser.items(completed, base) }
    local covers = {}
    for _, group in ipairs({ groups.hot, groups.completed }) do
        for _, item in ipairs(group) do
            if item.cover then covers[item.ref] = item.cover end
        end
    end
    for _, item in ipairs(groups.ongoing) do
        item.cover = item.cover or covers[item.ref]
    end
    return groups
end

local function meta(html, key)
    for tag in (html or ""):gmatch("<meta%s+[^>]*>") do
        local property = Html.attr(tag, "property") or Html.attr(tag, "name")
        if property == key then return Html.decode(Html.attr(tag, "content") or "") end
    end
end

function Parser.details(html)
    html = html or ""
    local details = { description = "" }
    local title = Parser.plain(Html.select(html, ".story-name") or "")
    if title == "" then
        title = Parser.plain((meta(html, "og:title") or ""):gsub("%s*[%-–—]%s*Akay Truyện%s*$", ""))
    end
    if title ~= "" then details.title = title end
    details.description = Parser.plain(Html.select(html, ".story-detail__top--desc") or "")
    if details.description == "" then details.description = meta(html, "og:description") or "" end
    local author = meta(html, "og:book:author")
    if not author then
        for _, anchor in ipairs(Html.elements(html, "a")) do
            if Html.attr(anchor.attrs, "itemprop") == "author" then
                author = Parser.plain(anchor.inner)
                break
            end
        end
    end
    if author and trim(author) ~= "" then details.author = trim(author) end
    local cover = meta(html, "og:image")
    if cover and cover:match("^https?://") then details.cover = cover end
    return details
end

-- Page count of a full story page: an explicit jump box, else the pagination
-- links. The chapter fragment carries neither, so it falls back to 1.
function Parser.pageCount(html)
    local total = 1
    for tag in (html or ""):gmatch("<input[^>]*>") do
        if classHas(tag, "jump-input") then
            total = math.max(total, tonumber(Html.attr(tag, "max")) or 1)
        end
    end
    if total == 1 then
        for value in (html or ""):gmatch("[?&;]page=(%d+)") do
            total = math.max(total, tonumber(value) or 1)
        end
    end
    return total
end

function Parser.hasMore(html, page)
    local want = tostring((tonumber(page) or 1) + 1)
    -- "&amp;page=N" is the common form inside pagination hrefs.
    for value in (html or ""):gmatch("[?&;]page=(%d+)") do
        if value == want then return true end
    end
    for value in (html or ""):gmatch("/trang%-(%d+)") do
        if value == want then return true end
    end
    return false
end

-- Chapter links live one segment below the story root; the same chapter appears
-- once in the mobile grid and once in the desktop grid, so URLs are deduped.
function Parser.chapters(html, base, series_slug)
    local prefix = base .. "/" .. series_slug .. "/"
    local chapters, seen = {}, {}
    for _, anchor in ipairs(Html.elements(html or "", "a")) do
        local url = Parser.absolute(Html.attr(anchor.attrs, "href"))
        if url then
            url = url:gsub("[#?].*$", ""):gsub("/+$", "")
            local tail = url:sub(1, #prefix) == prefix and url:sub(#prefix + 1)
            if validSlug(tail, MAX_CHAPTER_SLUG) and not tail:find("/", 1, true) and not seen[url] then
                local inner = anchor.inner or ""
                if classHas(anchor.attrs, "chapter-link-mobile") or classHas(anchor.attrs, "chapter-link-desktop")
                        or inner:find("chapter-number", 1, true) or inner:find("chapter-title", 1, true) then
                    seen[url] = true
                    local number = Parser.plain(inner:match(
                        '<div[^>]-class="[^"]*chapter%-number[^"]*"[^>]*>([%s%S]-)</div>') or "")
                    local named = Parser.plain(inner:match(
                        '<div[^>]-class="[^"]*chapter%-title[^"]*"[^>]*>([%s%S]-)</div>') or "")
                    local title
                    if number ~= "" and named ~= "" then title = number .. ": " .. named
                    elseif number ~= "" then title = number
                    elseif named ~= "" then title = named
                    else title = Parser.plain(inner) end
                    if title == "" then title = Html.decode(Html.attr(anchor.attrs, "title") or tail) end
                    chapters[#chapters + 1] = { id = tail, url = url, title = title,
                        locked = inner:find("fa%-lock") ~= nil or nil }
                end
            end
        end
    end
    return chapters
end

-- Paywall markers. A free page only mentions "access-denied-container" inside
-- its stylesheet, so the check needs an actual <div>, exactly like the original
-- plugin did.
function Parser.locked(html)
    if type(html) ~= "string" then return false end
    return html:find("Chương này dành cho tài khoản VIP", 1, true) ~= nil
        or html:find("<div[^>]-access%-denied%-container") ~= nil
end

function Parser.chapterTitle(html)
    local title = (html or ""):match('<h1[^>]-custom%-text[^>]*>([%s%S]-)</h1>')
        or (html or ""):match("<h1[^>]*>([%s%S]-)</h1>")
    return title and Parser.plain(title) or nil
end

-- #chapter-content is a flat run of <p>/<br>. Everything is reduced to plain
-- paragraphs before re-escaping, so no site markup or event handler survives.
function Parser.paragraphs(content)
    content = tostring(content or "")
    content = content:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]%s*>", "\n")
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = Parser.plain(line)
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    return table.concat(paragraphs, "\n")
end

-- The chapter-list endpoint answers JSON. Decoding goes through KOReader's json
-- module; without it the caller falls back to the full story page.
function Parser.decodeFragment(body)
    if type(body) ~= "string" or body == "" then return nil end
    local payload
    local ok, json = pcall(require, "json")
    if ok and type(json) == "table" and type(json.decode) == "function" then
        local decoded_ok, decoded = pcall(json.decode, body)
        if decoded_ok then payload = decoded end
    end
    if type(payload) ~= "table" then
        local util_ok, ko_util = pcall(require, "util")
        if util_ok and ko_util and type(ko_util.jsonDecode) == "function" then
            local decoded_ok, decoded = pcall(ko_util.jsonDecode, body)
            if decoded_ok then payload = decoded end
        end
    end
    if type(payload) ~= "table" or type(payload.html) ~= "string" then return nil end
    return payload.html, payload.has_more == true
end

return Parser
