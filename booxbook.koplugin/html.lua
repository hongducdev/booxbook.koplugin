local Html = {}

local ALLOWED_TAGS = {
    p = true, br = true, h1 = true, h2 = true, h3 = true,
    em = true, strong = true, b = true, i = true, u = true,
    img = true, blockquote = true, ul = true, ol = true, li = true,
    div = true, span = true, a = true, hr = true,
}

local function lower(str)
    return string.lower(str or "")
end

function Html.stripDangerous(html)
    html = html or ""
    html = html:gsub("<%s*[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.-<%s*/%s*[Ss][Cc][Rr][Ii][Pp][Tt]%s*>", "")
    html = html:gsub("<%s*[Ss][Tt][Yy][Ll][Ee][^>]*>.-<%s*/%s*[Ss][Tt][Yy][Ll][Ee]%s*>", "")
    html = html:gsub("<%s*[Nn][Oo][Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.-<%s*/%s*[Nn][Oo][Ss][Cc][Rr][Ii][Pp][Tt]%s*>", "")
    html = html:gsub("<%s*[Ii][Ff][Rr][Aa][Mm][Ee][^>]*>.-<%s*/%s*[Ii][Ff][Rr][Aa][Mm][Ee]%s*>", "")
    html = html:gsub("<%s*[Ii][Ff][Rr][Aa][Mm][Ee][^>]*/>", "")
    html = html:gsub("%s[oO][nN]%w+%s*=%s*['\"][^'\"]*['\"]", "")
    html = html:gsub("%s[oO][nN]%w+%s*=%s*[^%s>]+", "")
    return html
end

function Html.sanitize(html)
    html = Html.stripDangerous(html)
    html = html:gsub("(</?)(%w+)([^>]*)>", function(prefix, tag, rest)
        local name = lower(tag)
        if not ALLOWED_TAGS[name] then
            return ""
        end
        if prefix == "</" then
            return "</" .. name .. ">"
        end
        if name == "img" then
            local src = rest:match("[Ss][Rr][Cc]%s*=%s*['\"]([^'\"]+)['\"]") or ""
            local alt = rest:match("[Aa][Ll][Tt]%s*=%s*['\"]([^'\"]+)['\"]") or ""
            if src == "" then
                return ""
            end
            return string.format('<img src="%s" alt="%s"/>', src, alt)
        end
        if name == "br" or name == "hr" then
            return "<" .. name .. "/>"
        end
        return "<" .. name .. rest .. ">"
    end)
    return html
end

local function findTagOpen(html, predicate)
    local pos = 1
    while true do
        local s, e, name, attrs = html:find("<%s*([%w:-]+)([^>]*)>", pos)
        if not s then
            return nil
        end
        if predicate(lower(name), attrs or "", s, e) then
            return s, e, lower(name)
        end
        pos = e + 1
    end
end

local function matchingClose(html, tag, from)
    local depth = 1
    local pos = from
    local open_pat = "<%s*" .. tag .. "%f[%W]"
    local close_pat = "<%s*/%s*" .. tag .. "%s*>"
    while depth > 0 do
        local o_s = html:find(open_pat, pos)
        local c_s, c_e = html:find(close_pat, pos)
        if not c_s then
            return #html, #html
        end
        if o_s and o_s < c_s then
            depth = depth + 1
            pos = html:find(">", o_s) + 1
        else
            depth = depth - 1
            if depth == 0 then
                return c_s, c_e
            end
            pos = c_e + 1
        end
    end
    return #html, #html
end

local function extractElement(html, open_s, open_e, tag)
    local close_s, close_e = matchingClose(html, tag, open_e + 1)
    local inner = html:sub(open_e + 1, close_s - 1)
    local outer = html:sub(open_s, close_e)
    return inner, outer
end

local function attrValue(attrs, attr_name)
    local patterns = {
        "%f[%w]" .. attr_name .. "%s*=%s*\"([^\"]*)\"",
        "%f[%w]" .. attr_name .. "%s*=%s*'([^']*)'",
        "%f[%w]" .. attr_name .. "%s*=%s*([^%s>]+)",
    }
    for _, pattern in ipairs(patterns) do
        local value = attrs:match(pattern)
        if value then
            return value
        end
    end
    return nil
end

local function classListContains(attrs, class_name)
    local class_attr = attrValue(attrs, "[Cc][Ll][Aa][Ss][Ss]")
    if not class_attr then
        return false
    end
    for token in class_attr:gmatch("%S+") do
        if token == class_name then
            return true
        end
    end
    return false
end

--- Tiny CSS helper: `#id`, `.class`, `tag`. Returns inner HTML of first match.
function Html.select(html, selector)
    html = html or ""
    selector = selector or ""
    local inner

    if selector:sub(1, 1) == "#" then
        local id = selector:sub(2)
        findTagOpen(html, function(_, attrs, s, e)
            if attrValue(attrs, "[Ii][Dd]") == id then
                local tag = html:match("<%s*([%w:-]+)", s)
                inner = select(1, extractElement(html, s, e, lower(tag)))
                return true
            end
            return false
        end)
        return inner
    end

    if selector:sub(1, 1) == "." then
        local class_name = selector:sub(2)
        findTagOpen(html, function(tag, attrs, s, e)
            if classListContains(attrs, class_name) then
                inner = select(1, extractElement(html, s, e, tag))
                return true
            end
            return false
        end)
        return inner
    end

    local tag = lower(selector)
    findTagOpen(html, function(name, _, s, e)
        if name == tag then
            inner = select(1, extractElement(html, s, e, tag))
            return true
        end
        return false
    end)
    return inner
end

function Html.selectAllInner(html, selector)
    -- Phase 1: first match only helper reused later; keep API stable.
    local first = Html.select(html, selector)
    if first then
        return { first }
    end
    return {}
end

function Html.escape(text)
    text = tostring(text or "")
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub('"', "&quot;")
    return text
end

function Html.wrapDocument(title, body)
    title = Html.escape(title or "BooxBook")
    body = body or ""
    return table.concat({
        "<!DOCTYPE html>",
        '<html xmlns="http://www.w3.org/1999/xhtml" lang="vi">',
        "<head>",
        '<meta charset="utf-8"/>',
        "<title>" .. title .. "</title>",
        "</head>",
        "<body>",
        body,
        "</body>",
        "</html>",
    }, "\n")
end

function Html.writeFile(path, content)
    local file, err = io.open(path, "wb")
    if not file then
        return false, err
    end
    file:write(content)
    file:close()
    return true
end

return Html
