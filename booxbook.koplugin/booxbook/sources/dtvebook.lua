local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(s) return s end

-- DTV eBook does not offer online reading: every book is a set of EPUB/PDF/AZW3/MOBI
-- files on Google Drive. The adapter therefore has kind "ebook": it lists and
-- describes books, and booxbook.ebook-download saves the chosen file. Ported from
-- the DTVEbook plugin of Yuneko-dev/Nekori-plugins (selectors re-checked on the live site).
local T = { id = "dtvebook", name = "DTV eBook", kind = "ebook",
    capabilities = { search = true, browse = true, login = false } }

local SITE = "https://dtv-ebook.com.vn"
local HOSTS = { ["dtv-ebook.com.vn"] = true, ["www.dtv-ebook.com.vn"] = true }
local DEFAULT_GENRE = "the-loai-truyen-313"
-- A list page renders ~24 books; fewer than this means the end of the catalogue.
local LIST_MIN_ITEMS = 20
-- Reading preference: reflowable first, fixed-layout last.
local FORMATS = { "EPUB", "AZW3", "MOBI", "PDF" }
local CHANGED = _("Không đọc được DTV eBook; trang có thể đã đổi hoặc yêu cầu xác minh.")

T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://dtv-ebook.com.vn/ten-sach_1234.html",
    browse = { { text = "Tất cả ebook", kind = "all" } },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/[%w%-]+_%d+%.html") ~= nil
    end,
}

local GENRES = {}
local function genre(key, name)
    local entry = { key = key, name = name }
    GENRES[key] = entry
    return entry
end

-- Key = the site's own category path segment, so browse() needs no extra mapping.
T.genres = {
    genre("best-seller-493", "Best seller"),
    genre("ngon-tinh-487", "Ngôn tình"),
    genre("tien-hiep-488", "Tiên hiệp"),
    genre("huyen-ao-497", "Huyền ảo"),
    genre("kiem-hiep-vo-hiep-526", "Kiếm hiệp - Võ hiệp"),
    genre("co-dai-511", "Cổ đại"),
    genre("xuyen-khong-498", "Xuyên không"),
    genre("trong-sinh-507", "Trọng sinh"),
    genre("do-thi-quan-truong-495", "Đô thị - Quan trường"),
    genre("dam-my-494", "Đam mỹ"),
    genre("bach-hop-510", "Bách hợp"),
    genre("di-nang-496", "Dị năng"),
    genre("kinh-di-491", "Kinh dị"),
    genre("trinh-tham-492", "Trinh thám"),
    genre("trom-mo-506", "Trộm mộ"),
    genre("tieu-thuyet-490", "Tiểu thuyết"),
    genre("truyen-ngan-536", "Truyện ngắn"),
    genre("thieu-nhi-505", "Thiếu nhi"),
    genre("khoa-huyen-524", "Khoa huyễn"),
    genre("vien-tuong-544", "Viễn tưởng"),
    genre("lich-su-quan-su-501", "Lịch sử - Quân sự"),
    genre("kinh-te-1450", "Kinh tế"),
    genre("ky-nang-song-khoi-nghiep-500", "Kỹ năng sống - Khởi nghiệp"),
    genre("quan-tri-kinh-doanh-499", "Quản trị - Kinh doanh"),
    genre("khoa-hoc-tam-ly-hoc-1470", "Khoa học - Tâm lý học"),
    genre("hoi-ky-but-ky-503", "Hồi ký - Bút ký"),
}

-- Book page: /<slug>_<id>.html. The ref handed around is that path.
function T.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if not host or not HOSTS[host:lower()] then return nil end
        ref = path
    end
    ref = ref:match("^[^?#]+") or ""
    local id = ref:match("^/([%w%-]+_%d+)%.html$")
    if id and #id <= 180 then return id, "/" .. id .. ".html" end
end

function T.locate(series)
    local id = T.parseRef(series.url or series.id)
    return id, id
end

local function text(html)
    local plain = (Html.stripDangerous(html or ""):gsub("<[^>]+>", ""))
    -- Replace the two-byte no-break space as a unit: its bytes also occur inside
    -- other Vietnamese letters, so a byte class would corrupt them.
    plain = Html.decode(plain):gsub("\194\160", " "):gsub("%s+", " ")
    return (plain:match("^%s*(.-)%s*$"))
end

-- The site's search only matches unaccented keywords.
local PLAIN = {}
for base, chars in pairs({
    a = "àáạảãâầấậẩẫăằắặẳẵ", e = "èéẹẻẽêềếệểễ", i = "ìíịỉĩ", o = "òóọỏõôồốộổỗơờớợởỡ",
    u = "ùúụủũưừứựửữ", y = "ỳýỵỷỹ", d = "đ",
    A = "ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ", E = "ÈÉẸẺẼÊỀẾỆỂỄ", I = "ÌÍỊỈĨ", O = "ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ",
    U = "ÙÚỤỦŨƯỪỨỰỬỮ", Y = "ỲÝỴỶỸ", D = "Đ",
}) do
    for char in chars:gmatch("[\1-\127\194-\244][\128-\191]*") do PLAIN[char] = base end
end

function T.stripDiacritics(value)
    return (value:gsub("[\194-\244][\128-\191]*", PLAIN):match("^%s*(.-)%s*$"))
end

local function encode(query)
    return (query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end))
end

-- og:image / list images repeat the origin ("https://x/https://x/a.jpg").
local function cover(src)
    if type(src) ~= "string" or src == "" then return nil end
    src = Html.decode(src)
    local last = src:match(".*()https?://")
    if last and last > 1 then src = src:sub(last) end
    if src:match("^//") then return "https:" .. src end
    if src:match("^/") then return SITE .. src end
    if src:match("^https?://") then return src end
end

local function request(path, referer)
    local ok, code, body = Http.get(SITE .. path, { referer = referer or (SITE .. "/"),
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được DTV eBook (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end

-- Each book is rendered twice (desktop + mobile blocks) inside its own
-- <li class="itemtruyen">; the first anchor of a block is the book's own link.
local function parseItems(html)
    local items, seen = {}, {}
    local starts = {}
    for position in html:gmatch('()<li class="itemtruyen') do starts[#starts + 1] = position end
    for index, from in ipairs(starts) do
        local block = html:sub(from, (starts[index + 1] or #html + 1) - 1)
        for attrs in block:gmatch("<a([^>]*)>") do
            local id, path = T.parseRef(Html.decode(Html.attr(attrs, "href") or ""))
            local title = text(Html.decode(Html.attr(attrs, "title") or ""))
            if id and title ~= "" then
                if not seen[id] then
                    seen[id] = true
                    items[#items + 1] = { ref = path, url = SITE .. path, title = title, name = title,
                        cover = cover(Html.attr(block:match("<img[^>]*>") or "", "src")) }
                end
                break
            end
        end
    end
    return items
end

local function hasMore(html, items)
    local pager = html:find('class="pagination"', 1, true)
    if pager then return html:find("&raquo;", pager, true) ~= nil end
    return #items >= LIST_MIN_ITEMS
end

local function validPage(page)
    page = tonumber(page or 1)
    if page and page >= 1 and page <= 10000 and page % 1 == 0 then return page end
end

local function list(path, referer)
    local html, err = request(path, referer)
    if not html then return nil, err end
    local items = parseItems(html)
    return { items = items, has_more = #items > 0 and hasMore(html, items) }, nil, html
end

function T.browse(kind, page)
    page = validPage(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    local key = (kind == nil or kind == "all") and DEFAULT_GENRE or kind
    if key ~= DEFAULT_GENRE and not GENRES[key] then return nil, _("Kiểu danh sách không hợp lệ.") end
    local result, err, html = list("/" .. key .. "/" .. page .. ".html")
    if not result then return nil, err end
    if #result.items == 0 and page == 1 then return nil, CHANGED end
    return result
end

function T.search(query, page)
    query = type(query) == "string" and T.stripDiacritics(query) or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = validPage(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    return list("/tim-kiem.html?keyword=" .. encode(query) .. "&type=&page=" .. page)
end

-- The table row whose <strong> label is `label` (up to its closing </tr>).
local function row(html, label)
    local from = html:find("<strong>" .. label .. "</strong>", 1, true)
    if not from then return nil end
    return html:sub(from, (html:find("</tr>", from, true) or #html + 1) - 1)
end

local function anchorTexts(fragment)
    local values = {}
    for inner in (fragment or ""):gmatch("<a[^>]*>(.-)</a>") do
        local value = text(inner)
        if value ~= "" then values[#values + 1] = value end
    end
    return values
end

local function description(html)
    local heading = html:find('id="intro"', 1, true)
    local from = heading and html:find("</h2>", heading, true)
    if from then
        from = from + 5
        local to = html:find('<div class="book-meta"', from, true) or html:find("<h2", from, true) or #html + 1
        local body = html:sub(from, to - 1):gsub("</[Pp]>", "\n"):gsub("</[Bb]lockquote>", "\n")
            :gsub("<[Bb][Rr]%s*/?>", "\n")
        local lines = {}
        for line in body:gmatch("[^\r\n]+") do
            line = text(line)
            if line ~= "" then lines[#lines + 1] = line end
        end
        if #lines > 0 then return table.concat(lines, "\n\n") end
    end
    local meta = html:match('<meta name="description" content="([^"]*)"')
    return meta and text(meta) or nil
end

-- Google Drive file id from the site's download links.
local function driveId(href)
    href = Html.decode(href or "")
    if not (href:match("^https://docs%.google%.com/uc%?") or href:match("^https://drive%.google%.com/")) then
        return nil
    end
    local id = href:match("[?&]id=([%w_%-]+)") or href:match("/file/d/([%w_%-]+)")
    if id and #id >= 10 and #id <= 100 then return id end
end

local function downloadFiles(html)
    local by_format = {}
    for attrs, inner in html:gmatch("<a([^>]*)>(.-)</a>") do
        local id = driveId(Html.attr(attrs, "href"))
        local label = id and text(inner):upper()
        for _index, format in ipairs(FORMATS) do
            if label and label:find(format, 1, true) and not by_format[format] then
                by_format[format] = { format = format, id = id,
                    url = "https://docs.google.com/uc?export=download&id=" .. id }
                break
            end
        end
    end
    local files = {}
    for _index, format in ipairs(FORMATS) do
        if by_format[format] then files[#files + 1] = by_format[format] end
    end
    return files
end

function T.getSeries(ref)
    local id, path = T.parseRef(ref)
    if not id then return nil, _("URL sách DTV eBook không hợp lệ.") end
    local html, err = request(path)
    if not html then return nil, err end
    local series = { id = id, source_id = T.id, url = SITE .. path, chapters = {} }
    series.title = text(Html.select(html, ".ten_san_pham") or "")
    if series.title == "" then
        series.title = text(html:match('<meta property="og:title" content="([^"]*)"') or "")
    end
    if series.title == "" then return nil, CHANGED end
    series.cover = cover(Html.attr(html:match('<img[^>]*class="hinhdaidien"[^>]*>') or "", "src")
        or html:match('<meta property="og:image" content="([^"]*)"'))
    series.author = anchorTexts(row(html, "Tác giả"))[1]
    series.tags = anchorTexts(row(html, "Thể loại"))
    local status = row(html, "Tình trạng")
    series.status = status and text(status):gsub("^Tình trạng%s*", "") or nil
    series.description = description(html)
    series.files = downloadFiles(html)
    if #series.files == 0 then
        return nil, _("Sách này không có link tải trên DTV eBook (có thể là bài review hoặc sách đang bán).")
    end
    return series
end

return T
