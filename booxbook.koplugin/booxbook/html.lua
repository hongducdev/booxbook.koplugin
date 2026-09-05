local has_util, Util = pcall(require, "util")
local Html = {}

local function utf8(code)
    if not code or code < 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then
        return nil
    elseif code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

function Html.decode(text)
    text = tostring(text or ""):gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    if has_util and Util.htmlEntitiesToUtf8 then
        return Util.htmlEntitiesToUtf8(text)
    end
    text = text:gsub("&#x([%da-fA-F]+);", function(value)
        local code = tonumber(value, 16)
        return utf8(code) or "&#x" .. value .. ";"
    end)
    text = text:gsub("&#(%d+);", function(value)
        local code = tonumber(value)
        return utf8(code) or "&#" .. value .. ";"
    end)
    return text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
        :gsub("&apos;", "'"):gsub("&amp;", "&")
end



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

-- Tiny selectors for the known site markup; return non-overlapping elements.
function Html.elements(html, selector, first_only)
    html = (html or ""):gsub("<!%-%-.-%-%->", "")
    local result, pos = {}, 1
    while true do
        local start, finish, tag = findTagOpen(html:sub(pos), function(name, attrs)
            if selector:sub(1, 1) == "#" then return attrValue(attrs, "[Ii][Dd]") == selector:sub(2) end
            if selector:sub(1, 1) == "." then return classListContains(attrs, selector:sub(2)) end
            return name == selector
        end)
        if not start then break end
        start, finish = start + pos - 1, finish + pos - 1
        local inner, outer = extractElement(html, start, finish, tag)
        result[#result + 1] = { inner = inner, outer = outer,
            attrs = html:sub(start, finish):match("<%s*[%w:-]+(.-)>"), tag = tag }
        if first_only then break end
        pos = start + #outer
    end
    return result
end

function Html.selectAllInner(html, selector)
    local result = {}
    for _, element in ipairs(Html.elements(html, selector)) do result[#result + 1] = element.inner end
    return result
end

function Html.select(html, selector)
    local first = Html.elements(html, selector, true)[1]
    return first and first.inner
end

Html.attr = attrValue

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
    local pending = path .. ".part"
    local file, err = io.open(pending, "wb")
    if not file then
        return false, err
    end
    local written, write_err = file:write(content)
    local closed, close_err = file:close()
    if not written or not closed then
        os.remove(pending)
        return false, write_err or close_err
    end
    -- Keep the previous article intact if a refresh cannot be written completely.
    local renamed, rename_err = os.rename(pending, path)
    if not renamed then
        os.remove(pending)
        return false, rename_err
    end
    return true
end

return Html
