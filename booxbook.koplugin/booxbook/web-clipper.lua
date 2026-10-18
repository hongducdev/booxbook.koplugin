local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end

local Clipper = {}

local function isPrivateIpv4(first, second)
    return first == 0 or first == 10 or first == 127
        or (first == 100 and second >= 64 and second <= 127)
        or (first == 169 and second == 254)
        or (first == 172 and second >= 16 and second <= 31)
        or (first == 192 and second == 168)
end

-- Validate URL and block loopback, private and link-local targets. Called for the
-- first URL and again for every redirect hop (see Clipper.clip).
function Clipper.isSafeUrl(url)
    if type(url) ~= "string" or url == "" then
        return false, _("URL không hợp lệ.")
    end
    url = url:gsub("^%s+", ""):gsub("%s+$", "")
    local proto, authority = url:match("^(https?)://([^/%?#]+)")
    if not proto or not authority then
        return false, _("Chỉ hỗ trợ liên kết HTTP hoặc HTTPS.")
    end
    local host = authority:match("([^@]*)$"):gsub(":%d*$", ""):lower()
    local blocked = _("Không thể cắt liên kết nội bộ thiết bị.")
    -- IPv6 literals are refused outright; no news site needs one.
    if host == "" or host:find("[%[%]:]") then return false, blocked end
    if host == "localhost" or host:match("%.localhost$") or host:match("%.local$")
        or host:match("%.lan$") or host:match("%.internal$") or host:match("%.home$") then
        return false, blocked
    end
    -- A lone number or hex literal is an IPv4 address in disguise (2130706433, 0x7f000001).
    if host:match("^%d+$") or host:match("^0x%x+$") then return false, blocked end
    local a, b, c, d = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if a and isPrivateIpv4(tonumber(a), tonumber(b)) then
        return false, _("Không thể cắt liên kết mạng riêng tư.")
    end
    return true, url
end

local function cleanText(str)
    if not str then return "" end
    str = Html.decode(str)
    str = str:gsub("<[^>]+>", "")
    str = str:gsub("%s+", " ")
    return str:gsub("^%s+", ""):gsub("%s+$", "")
end

function Clipper.extractTitle(html)
    html = html or ""
    -- 1. OpenGraph title
    local og = html:match('<meta[^>]+property%s*=%s*["\']og:title["\'][^>]+content%s*=%s*["\']([^"\']+)["\']')
        or html:match('<meta[^>]+content%s*=%s*["\']([^"\']+)["\'][^>]+property%s*=%s*["\']og:title["\']')
    if og and #og > 0 then return cleanText(og) end

    -- 2. Twitter title
    local tw = html:match('<meta[^>]+name%s*=%s*["\']twitter:title["\'][^>]+content%s*=%s*["\']([^"\']+)["\']')
        or html:match('<meta[^>]+content%s*=%s*["\']([^"\']+)["\'][^>]+name%s*=%s*["\']twitter:title["\']')
    if tw and #tw > 0 then return cleanText(tw) end

    -- 3. Standard <title>
    local title = html:match("<title[^>]*>(.-)</title>")
    if title and #title > 0 then
        local cleaned = cleanText(title)
        cleaned = cleaned:gsub("%s*[%-|—].-$", "")
        if #cleaned > 0 then return cleaned end
    end

    -- 4. <h1>
    local h1 = html:match("<h1[^>]*>(.-)</h1>")
    if h1 and #h1 > 0 then return cleanText(h1) end

    return _("Bài viết không tên")
end

local CONTAINER_PATTERNS = {
    "<article[^>]*>(.-)</article>",
    "<div[^>]+class%s*=%s*[\"'][^\"']*fck_detail[^\"']*[\"'][^>]*>(.-)</div>",
    "<div[^>]+class%s*=%s*[\"'][^\"']*detail%-content[^\"']*[\"'][^>]*>(.-)</div>",
    "<div[^>]+class%s*=%s*[\"'][^\"']*article%-body[^\"']*[\"'][^>]*>(.-)</div>",
    "<div[^>]+class%s*=%s*[\"'][^\"']*post%-content[^\"']*[\"'][^>]*>(.-)</div>",
    "<div[^>]+class%s*=%s*[\"'][^\"']*entry%-content[^\"']*[\"'][^>]*>(.-)</div>",
    "<div[^>]+class%s*=%s*[\"'][^\"']*content%-detail[^\"']*[\"'][^>]*>(.-)</div>",
    "<div[^>]+itemprop%s*=%s*[\"']articleBody[\"'][^>]*>(.-)</div>",
    "<main[^>]*>(.-)</main>",
}

function Clipper.extractContent(html)
    html = html or ""
    html = Html.stripDangerous(html)

    for _, pattern in ipairs(CONTAINER_PATTERNS) do
        local body = html:match(pattern)
        if body and #cleanText(body) >= 150 then
            return body
        end
    end

    -- Fallback: collect all paragraphs
    local paragraphs = {}
    for p in html:gmatch("<p[^>]*>(.-)</p>") do
        local text = cleanText(p)
        if #text >= 25 then
            paragraphs[#paragraphs + 1] = "<p>" .. p .. "</p>"
        end
    end

    if #paragraphs > 0 then
        return table.concat(paragraphs, "\n")
    end

    return "<p>" .. cleanText(html) .. "</p>"
end

function Clipper.normalizeImages(body, base_url)
    if not body then return "" end
    return body:gsub('(<img[^>]+src%s*=%s*["\'])([^"\']+)(["\'][^>]*>)', function(prefix, src, suffix)
        local resolved = src
        if src:match("^//") then
            resolved = "https:" .. src
        elseif not src:match("^https?://") and not src:match("^data:") then
            resolved = Http.resolveUrl(base_url or "", src)
        end
        return prefix .. resolved .. suffix
    end)
end

function Clipper.extractArticle(raw_html, base_url)
    raw_html = raw_html or ""
    local title = Clipper.extractTitle(raw_html)

    local author = raw_html:match('<meta[^>]+name%s*=%s*["\']author["\'][^>]+content%s*=%s*["\']([^"\']+)["\']')
    if author then author = cleanText(author) end

    local site = raw_html:match('<meta[^>]+property%s*=%s*["\']og:site_name["\'][^>]+content%s*=%s*["\']([^"\']+)["\']')
    if site then site = cleanText(site) end

    local raw_content = Clipper.extractContent(raw_html)
    local sanitized = Html.sanitize(raw_content)
    local content_with_images = Clipper.normalizeImages(sanitized, base_url)

    local header_parts = {
        "<h1>" .. Html.escape(title) .. "</h1>",
    }
    local meta_line = {}
    if site and #site > 0 then meta_line[#meta_line + 1] = Html.escape(site) end
    if author and #author > 0 then meta_line[#meta_line + 1] = Html.escape(author) end
    if base_url and #base_url > 0 then
        meta_line[#meta_line + 1] = '<a href="' .. Html.escape(base_url) .. '">' .. _("Nguồn gốc") .. '</a>'
    end

    if #meta_line > 0 then
        header_parts[#header_parts + 1] = '<p style="font-size:0.9em;color:#555"><em>' .. table.concat(meta_line, " · ") .. "</em></p><hr/>"
    else
        header_parts[#header_parts + 1] = "<hr/>"
    end

    local full_body = table.concat(header_parts, "\n") .. "\n" .. content_with_images
    return {
        title = title,
        author = author,
        site = site,
        url = base_url,
        body = full_body,
    }
end

function Clipper.clip(url_text, target_dir)
    local safe, clean_url = Clipper.isSafeUrl(url_text)
    if not safe then return nil, clean_url end

    local ok, status, body = Http.get(clean_url, {
        max_hops = 5, timeout = 15,
        allow_url = function(next_url) return (Clipper.isSafeUrl(next_url)) end,
    })
    if not ok or status ~= 200 or not body or #body == 0 then
        return nil, string.format(_("Không thể tải trang web (HTTP %s)."), tostring(status or "lỗi kết nối"))
    end

    local article = Clipper.extractArticle(body, clean_url)
    local doc = Html.wrapDocument(article.title, article.body)

    target_dir = target_dir or (Settings.downloadDir() .. "/news/web-clipper")
    if not Settings.ensureDir(target_dir) then
        return nil, _("Không tạo được thư mục lưu bài báo.")
    end

    local raw_title = article.title or "article"
    local ok_lib, Library = pcall(require, "booxbook.library")
    if ok_lib and Library and Library.fold then
        raw_title = Library.fold(raw_title)
    end
    local slug = raw_title:lower():gsub("[^%w%s]", ""):gsub("%s+", "-"):gsub("^%-+", ""):gsub("%-+$", ""):sub(1, 40)
    if slug == "" then slug = "article" end

    local filename = os.date("%Y%m%d-%H%M%S") .. "-" .. slug .. ".html"
    local filepath = target_dir .. "/" .. filename

    local written, write_err = Html.writeFile(filepath, doc)
    if not written then
        return nil, write_err or _("Không thể ghi file bài báo.")
    end

    return {
        title = article.title,
        path = filepath,
        filename = filename,
        url = clean_url,
    }
end

return Clipper
