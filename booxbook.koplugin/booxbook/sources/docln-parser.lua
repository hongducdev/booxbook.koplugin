-- Selectors/metadata adapted from Nekori LNHako/index.ts (MIT); see third-party notices.
local Html = require("booxbook.html")
local Payload = require("booxbook.sources.docln-payload")
local Parser = {
    homes = { "https://docln.net", "https://ln.hako.vn", "https://docln.sbs" },
    selectors = { results = ".thumb-item-flow", title = ".series-title", name = ".series-name",
        volumes = ".volume-list", volume = ".sect-title", chapters = ".list-chapters",
        content = "#chapter-content", protected = "#chapter-c-protected" },
}

function Parser.text(value)
    return Html.decode((value or ""):gsub("<[^>]*>", "")):gsub("\194\160", " ")
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function Parser.path(ref)
    local path = type(ref) == "table" and ref.url or ref
    if type(path) ~= "string" or path:find("[%c\\]") then return nil end
    if path:sub(1, 1) ~= "/" or path:sub(1, 2) == "//" then
        local home, tail = path:match("^(https://[^/]+)(/.*)$")
        local trusted = false
        for _, allowed in ipairs(Parser.homes) do if home == allowed then trusted = true end end
        if not trusted then return nil end
        path = tail
    end
    if path:find("..", 1, true) or path:find("[?#%%]") then return nil end
    local kind, id = path:match("^/([%w-]+)/(%d+)")
    if (kind ~= "truyen" and kind ~= "sang-tac" and kind ~= "convert") or #id > 12 then return nil end
    if not path:match("^/[%w-]+/%d+[%w-]*$") and not path:match("^/[%w-]+/%d+[%w-]*/c%d+[%w-]*$") then return nil end
    return path, kind .. "-" .. id
end

local function firstLink(block)
    local node = Html.elements(block, "a")[1]
    if not node then return nil end
    local path = Parser.path(Html.decode(Html.attr(node.attrs, "href") or ""))
    if not path then return nil end
    return { title = Parser.text(Html.attr(node.attrs, "title") or node.inner), url = path }
end

function Parser.adult(block)
    block = (block or ""):lower()
    return block:find("18+", 1, true) ~= nil or block:find("adult", 1, true) ~= nil
        or block:find("mature", 1, true) ~= nil or block:find("hentai", 1, true) ~= nil
end

local function locked(block)
    return block:find("fa-lock", 1, true) or block:find('class="locked', 1, true)
        or block:find("chapter-locked", 1, true) or block:find("Bạn cần đăng nhập", 1, true)
        or block:find("Bạn phải đăng nhập", 1, true) or block:find("Chương bị khóa", 1, true)
end

local function cover(block)
    local attrs = (block or ""):match('<[^>]+class=["\'][^"\']*img%-in%-ratio[^"\']*["\']([^>]*)>') or ""
    return Html.decode(Html.attr(attrs, "data%-bg") or (Html.attr(attrs, "style") or ""):match("url%(['\"]?(.-)['\"]?%)") or "")
end

function Parser.search(html, page, allow_adult)
    local result, seen = { items = {}, has_more = false }, {}
    for _, node in ipairs(Html.elements(html, Parser.selectors.results)) do
        local block = node.inner
        local item = firstLink(Html.select(block, Parser.selectors.title))
        if item and not item.url:match("/c%d+") and not seen[item.url] then
            item.adult = Parser.adult(node.outer)
            item.cover = cover(block)
            if allow_adult or not item.adult then result.items[#result.items + 1] = item end
            seen[item.url] = true
        end
    end
    local pagination = Html.select(html, ".pagination_wrap") or Html.select(html, ".pagination") or ""
    for _, node in ipairs(Html.elements(pagination, "a")) do
        local next_page = tonumber(Html.decode(Html.attr(node.attrs, "href") or ""):match("[?&]page=(%d+)"))
        if next_page and next_page > page then result.has_more = true end
    end
    return result
end

function Parser.series(html, path)
    local title = Parser.text(Html.select(html, Parser.selectors.name))
    if title == "" then return nil end
    local _, id = Parser.path(path)
    local series = { id = id, url = path, title = title, author = "", volumes = {}, chapters = {},
        cover = cover(Html.select(html, ".series-cover")),
        description = Parser.text(Html.select(html, ".summary-content")), tags = {},
        adult = Parser.adult((Html.select(html, ".series-name-group") or "")
            .. (Html.select(html, ".series-gernes") or "") .. (Html.select(html, ".series-warning") or "")) }
    for _, block in ipairs(Html.selectAllInner(Html.select(html, ".series-information"), ".info-item")) do
        if Parser.text(Html.select(block, ".info-name")):lower():find("tác giả", 1, true) then
            series.author = Parser.text(Html.select(block, ".info-value"))
        end
    end
    for _, node in ipairs(Html.elements(Html.select(html, ".series-gernes"), "a")) do
        series.tags[#series.tags + 1] = Parser.text(node.inner)
    end
    local seen = {}
    for _, block in ipairs(Html.selectAllInner(html, Parser.selectors.volumes)) do
        local volume = { title = Parser.text(Html.select(block, Parser.selectors.volume)), chapters = {} }
        for _, li in ipairs(Html.elements(Html.select(block, Parser.selectors.chapters), "li")) do
            local chapter = firstLink(Html.select(li.inner, ".chapter-name") or li.inner)
            local chapter_id = chapter and chapter.url:match("/c(%d+)")
            if chapter_id and #chapter_id <= 12 and not seen[chapter_id] then
                chapter.id, chapter.locked, chapter.adult = chapter_id, not not locked(li.outer), series.adult
                chapter.index = #series.chapters + 1
                volume.chapters[#volume.chapters + 1] = chapter
                series.chapters[#series.chapters + 1] = chapter
                seen[chapter_id] = true
            end
        end
        if #volume.chapters > 0 then series.volumes[#series.volumes + 1] = volume end
    end
    return series
end

function Parser.chapter(html)
    local body = Html.select(html, Parser.selectors.content)
    if not body then return nil, locked(html) and "locked" or "changed" end
    if locked(body) then return nil, "locked" end
    local payload = Html.elements(body, Parser.selectors.protected)[1]
    if payload then
        local decoded = Payload.decode(payload.attrs)
        if not decoded then return nil, "encoded" end
        local first, last = body:find(payload.outer, 1, true)
        body = body:sub(1, first - 1) .. decoded .. body:sub(last + 1)
    end
    body = Html.stripDangerous(body):gsub("<!%-%-.-%-%->", "")
    -- Only paragraph text is exported; active markup and remote image URLs cannot survive.
    local paragraphs = {}
    for _, node in ipairs(Html.elements(body, "p")) do
        local class = " " .. (Html.attr(node.attrs, "class") or "") .. " "
        local style = (Html.attr(node.attrs, "style") or ""):lower():gsub("%s", "")
        if not class:find(" none ", 1, true) and not style:find("display:none", 1, true) then
            local text = Parser.text(node.inner:gsub("<[bB][rR]%s*/?>", " "))
            if text ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(text) .. "</p>" end
        end
    end
    if #paragraphs == 0 then return nil, "empty" end
    return table.concat(paragraphs, "\n")
end

return Parser
