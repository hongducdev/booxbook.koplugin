-- DTV eBook adapter: reference parsing, diacritic-free search, list pages (duplicated
-- desktop/mobile blocks, cover prefix, pagination), and the book detail page with its
-- Google Drive download links.
package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path
local T = require("booxbook.sources.dtvebook")
local H = require("booxbook.http")
local original_get = H.get

assert(T.id == "dtvebook" and T.kind == "ebook" and T.capabilities.login == false)
assert(T.capabilities.search and T.capabilities.browse)
assert(T.view.base_url == "https://dtv-ebook.com.vn" and T.view.cover_referer == "https://dtv-ebook.com.vn/")
assert(T.view.is_ref("https://dtv-ebook.com.vn/so-tay-danh-cho-trader_27609.html"))
assert(T.view.is_ref("/so-tay-danh-cho-trader_27609.html"))
assert(not T.view.is_ref("sổ tay trader"))
assert(#T.genres > 20 and T.genres[1].key and T.genres[1].name)

-- ---- parseRef ------------------------------------------------------------
local id, path = T.parseRef("https://dtv-ebook.com.vn/so-tay-danh-cho-trader_27609.html")
assert(id == "so-tay-danh-cho-trader_27609" and path == "/so-tay-danh-cho-trader_27609.html")
assert(T.parseRef("/so-tay-danh-cho-trader_27609.html?x=1#download") == "so-tay-danh-cho-trader_27609")
assert(T.parseRef("https://www.dtv-ebook.com.vn/ba-han_27460.html") == "ba-han_27460")
assert(T.parseRef({ url = "https://dtv-ebook.com.vn/ba-han_27460.html" }) == "ba-han_27460")
assert(not T.parseRef("https://evil.test/ba-han_27460.html"))
assert(not T.parseRef("https://dtv-ebook.com.vn.evil.test/ba-han_27460.html"))
assert(not T.parseRef("/the-loai-truyen-313/1.html"), "a category page is not a book")
assert(not T.parseRef("/ba-han.html") and not T.parseRef("/../ba-han_1.html") and not T.parseRef("/a/b_1.html"))
assert(not T.parseRef(nil) and not T.parseRef(7) and not T.parseRef({}))
assert(T.locate{ url = "https://dtv-ebook.com.vn/ba-han_27460.html" } == "ba-han_27460")

-- ---- diacritics ----------------------------------------------------------
assert(T.stripDiacritics("Đắc Nhân Tâm") == "Dac Nhan Tam")
assert(T.stripDiacritics("  ngôn tình xuyên không ") == "ngon tinh xuyen khong")
assert(T.stripDiacritics("Ư Ờ Ở đ Đ ỹ") == "U O O d D y")
assert(T.stripDiacritics("ba han 123") == "ba han 123", "plain text is untouched")

-- ---- stubs ---------------------------------------------------------------
local last_url, rules = nil, {}
local function serve(rule) table.insert(rules, 1, rule) end
H.get = function(url, opts)
    last_url = url
    assert(opts.delay_ms >= 1600, "delay_ms must stay bounded")
    assert(type(opts.referer) == "string", "referer required")
    for _, rule in ipairs(rules) do
        if url:find(rule.match, 1, true) then
            if rule.code and rule.code >= 400 then return false, rule.code, rule.body end
            return true, 200, rule.body
        end
    end
    return false, 404, nil
end

local function card(slug, number, title, image)
    local href = "https://dtv-ebook.com.vn/" .. slug .. "_" .. number .. ".html"
    local block = '<a href="' .. href .. '" title="' .. title .. '" class="th radius"><img src="' .. image
        .. '" alt="' .. title .. '" class="hinhtruyen lazy" /></a><p><a href="' .. href .. '" title="' .. title
        .. '"><h2 class="tensanpham">' .. title .. '</h2></a></p>'
    -- The site renders each book twice: a desktop block and a mobile one.
    return '<li class="itemtruyen wow fadeInLeft"><div class="hide-for-small-only">' .. block
        .. '</div><div class="show-for-small-only"><ul class="small-block-grid-2"><li>' .. block
        .. '</li></ul></div></li>'
end
local NAV = '<a href="https://dtv-ebook.com.vn/huong-dan-tai-ebook_1318.html" title="Hướng dẫn">Hướng dẫn</a>'
local function list(count, pager)
    local parts = { NAV }
    for index = 1, count do
        parts[#parts + 1] = card("sach-" .. index, 100 + index, "Sách &amp; " .. index,
            index == 1 and "https://dtv-ebook.com.vn/https://dtv-ebook.com.vn/images/a.jpg" or "/images/b" .. index .. ".jpg")
    end
    parts[#parts + 1] = '<a href="https://dtv-ebook.com.vn/ung-ho_1883.html" title="Ủng hộ">Ủng hộ</a>'
    if pager then parts[#parts + 1] = pager end
    return table.concat(parts)
end
local PAGER_MORE = '<ul class="pagination"><li class="current"><a>1</a></li><li><a href="/x/2.html">2</a></li>'
    .. '<li class="arrow"><a href="/x/2.html">&raquo;</a></li></ul>'
local PAGER_LAST = '<ul class="pagination"><li><a href="/x/1.html">1</a></li><li class="current"><a>2</a></li></ul>'

-- ---- browse --------------------------------------------------------------
serve{ match = "/the-loai-truyen-313/", body = list(24, PAGER_MORE) }
serve{ match = "/ngon-tinh-487/", body = list(2, PAGER_LAST) }
local all = assert(T.browse("all", 1))
assert(last_url == "https://dtv-ebook.com.vn/the-loai-truyen-313/1.html")
assert(#all.items == 24, "the desktop and mobile copies of a book are listed once")
assert(all.has_more, "a pagination arrow offers the next page")
assert(all.items[1].title == "Sách & 1" and all.items[1].name == all.items[1].title)
assert(all.items[1].ref == "/sach-1_101.html" and all.items[1].url == "https://dtv-ebook.com.vn/sach-1_101.html")
assert(all.items[1].cover == "https://dtv-ebook.com.vn/images/a.jpg", "the repeated origin prefix is dropped")
assert(all.items[2].cover == "https://dtv-ebook.com.vn/images/b2.jpg", "relative covers get the origin")
for _, listed in ipairs(all.items) do
    assert(not listed.url:find("huong%-dan") and not listed.url:find("ung%-ho"), "site pages are not books")
end
local genre = assert(T.browse("ngon-tinh-487", 2))
assert(last_url == "https://dtv-ebook.com.vn/ngon-tinh-487/2.html" and #genre.items == 2)
assert(not genre.has_more, "no pagination arrow: this is the last page")
assert(T.browse(nil, 1) and last_url:find("the-loai-truyen-313", 1, true), "no kind means the default catalogue")
assert(not T.browse("../etc", 1) and not T.browse("all", 0) and not T.browse("all", "x") and not T.browse("all", 1.5))
serve{ match = "/the-loai-truyen-313/", body = "<html>trống</html>" }
assert(not T.browse("all", 1), "an unrecognised first page is reported as a site change")
serve{ match = "/the-loai-truyen-313/", code = 503, body = "" }
local _, err = T.browse("all", 1)
assert(err and err:find("503", 1, true), "an HTTP failure names its status")

-- ---- search --------------------------------------------------------------
serve{ match = "/tim-kiem.html", body = list(3) }
local found = assert(T.search("Bá Hạn", 2))
assert(last_url == "https://dtv-ebook.com.vn/tim-kiem.html?keyword=Ba%20Han&type=&page=2",
    "accents are removed and the query is percent-encoded")
assert(#found.items == 3 and not found.has_more, "a short result list is the last page")
assert(not T.search("   ", 1) and not T.search(nil, 1) and not T.search(string.rep("a", 301), 1))
assert(not T.search("ba han", 0))

-- ---- getSeries -----------------------------------------------------------
local function drive(id, label)
    return '<div class="download-box"><a href="https://docs.google.com/uc?export=download&id=' .. id
        .. '" rel="nofollow">\226\135\147 T\225\186\163i ' .. label .. '</a></div>'
        .. '<a href="https://docs.google.com/uc?export=download&id=' .. id .. '" target="_blank"></a>'
end
local DETAIL = '<html><head><meta property="og:image" content="https://dtv-ebook.com.vn/https://dtv-ebook.com.vn/og.jpg"/></head><body>'
    .. '<img class="hinhdaidien" data-caption="" src="https://dtv-ebook.com.vn/images/cover.jpg" width="" />'
    .. '<table class="tblChiTietDiDong"><tr><td colspan="2"><h2 class="ten_san_pham text-center">Sổ Tay Trader</h2></td></tr>'
    .. '<tr><td><strong>Tác giả</strong></td><td><a class="label" href="/x" title="Phạm Tuân">\n  Phạm Tuân\n </a></td></tr>'
    .. '<tr><td><strong>Thể loại</strong></td><td><a class="label" href="/k">Kinh Tế</a><a class="label" href="/t">Tài Chính</a></td></tr>'
    .. '<tr><td><strong>Tình trạng</strong></td><td><span class="label radius">Hoàn Thành</span></td></tr></table>'
    .. '<main class="content"><h2 id="intro">Giới thiệu</h2>\n<p>Đoạn <em>một</em> &amp; hai.</p>\n'
    .. '<blockquote>Trích dẫn.</blockquote><div class="book-meta"><div class="label">Tác giả</div></div>'
    .. '<h2 id="download">Tải ebook</h2>' .. drive("PDFPDFPDFPDF1", "PDF") .. drive("EPUBEPUBEPUB2", "EPUB")
    .. drive("MOBIMOBIMOBI3", "MOBI") .. drive("AZW3AZW3AZW34", "AZW3")
    .. '<a href="https://example.com/uc?export=download&id=OTHEROTHEROTHER">PDF</a></main></body></html>'
serve{ match = "/so-tay-trader_27609.html", body = DETAIL }
local series = assert(T.getSeries("https://dtv-ebook.com.vn/so-tay-trader_27609.html"))
assert(last_url == "https://dtv-ebook.com.vn/so-tay-trader_27609.html")
assert(series.id == "so-tay-trader_27609" and series.source_id == "dtvebook")
assert(series.url == "https://dtv-ebook.com.vn/so-tay-trader_27609.html")
assert(series.title == "Sổ Tay Trader" and series.author == "Phạm Tuân")
assert(series.cover == "https://dtv-ebook.com.vn/images/cover.jpg")
assert(#series.tags == 2 and series.tags[1] == "Kinh Tế" and series.tags[2] == "Tài Chính")
assert(series.status == "Hoàn Thành", series.status)
assert(series.description == "Đoạn một & hai.\n\nTrích dẫn.", series.description)
assert(#series.files == 4, "one entry per format; the duplicate link and foreign hosts are ignored")
assert(series.files[1].format == "EPUB" and series.files[2].format == "AZW3"
    and series.files[3].format == "MOBI" and series.files[4].format == "PDF", "reflowable formats come first")
assert(series.files[1].id == "EPUBEPUBEPUB2")
assert(series.files[1].url == "https://docs.google.com/uc?export=download&id=EPUBEPUBEPUB2")
assert(#series.chapters == 0)

serve{ match = "/review_1.html", body = '<h2 class="ten_san_pham">Bài review</h2><h2 id="intro">Giới thiệu</h2><p>x</p>' }
local none, none_err = T.getSeries("/review_1.html")
assert(not none and none_err:find("không có link tải", 1, true), "a review page reports that it has no files")
serve{ match = "/empty_2.html", body = "<html></html>" }
assert(not T.getSeries("/empty_2.html"), "a page without a title is a site change")
serve{ match = "/gone_3.html", code = 404, body = "" }
assert(not T.getSeries("/gone_3.html"))
local calls_before = last_url
assert(not T.getSeries("https://evil.test/x_1.html") and last_url == calls_before, "rejected refs cost no request")

H.get = original_get
print("DTV eBook references, accent-free search, lists, detail and download links passed")
