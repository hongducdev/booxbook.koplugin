local T = require('booxbook.sources.xtruyen')
local H = require('booxbook.http')
local Settings = require('booxbook.store.settings')
local original = H.get
local calls, body, code = 0, '', 200
H.get = function(url, opts) calls = calls + 1; assert(opts.referer and opts.delay_ms >= 1600); return code == 200, code, body end

-- parseRef: /truyen/{slug}/ is a series; a chapter adds one segment. Both hosts
-- are accepted because the site links stories on xtruyen.vn and www.xtruyen.vn.
assert(T.parseRef('https://xtruyen.vn/truyen/o-do-la-tinh-duc-ma-tu/') == 'o-do-la-tinh-duc-ma-tu')
assert(T.parseRef('https://www.xtruyen.vn/truyen/o-do-la-tinh-duc-ma-tu/') == 'o-do-la-tinh-duc-ma-tu')
assert(T.parseRef('/truyen/dao-dich/') == 'dao-dich')
local book, cid, path = T.parseRef('https://www.xtruyen.vn/truyen/dao-dich/chuong-1106/')
assert(book == 'dao-dich' and cid == '1106' and path == '/truyen/dao-dich/chuong-1106/')
local ibook, iid, ipath = T.parseRef('/truyen/dao-dich/gioi-thieu/')
assert(ibook == 'dao-dich' and iid == 'gioi-thieu' and ipath == '/truyen/dao-dich/gioi-thieu/')
assert(select(2, T.parseRef('/truyen/x/phan-12/')) == '12', 'phan-N keeps the number as the id')
assert(not T.parseRef('https://evil.test/truyen/dao-dich/'), 'foreign host rejected')
assert(not T.parseRef('https://xtruyen.vn/truyen/feed/'), 'the feed path is not a story')
assert(not T.parseRef('https://xtruyen.vn/') and not T.parseRef('/truyen/'))
assert(not T.parseRef('/truyen/a/b/c/'), 'depth is bounded')
assert(not T.parseRef('/truyen/a/chuong-0/') and not T.parseRef('/truyen/a/chuong-1234567890123/'))
assert(not T.parseRef(nil) and not T.parseRef(42) and not T.parseRef(''))
assert(not T.getSeries('https://evil.test/truyen/dao-dich/') and calls == 0)

-- Search and browse share one card parser; the .content_archive_3 scope keeps
-- the "Truyện mới" sidebar widget out of the results.
local cards = '<div class="container my-4 content_archive_3"><div class="row ">'
    .. '<div class="col-12 col-md-12 col-lg-12"><div class="popular-item-wrap">'
    .. '<div class="popular-img widget-thumbnail c-image-hover"><a title="Đạo (Dịch)" href="https://xtruyen.vn/truyen/dao-dich/">'
    .. '<img src="https://thumb.xtruyen.vn/dao-dich.webp" alt="" onerror="this.onerror=null;this.src=\'https://xtruyen.vn/x.png\';"></a></div>'
    .. '<div class="popular-content"><h5 class="widget-title"> <i class="fas fa-check-circle"> </i>'
    .. '<a title="Đạo (Dịch)" href="https://xtruyen.vn/truyen/dao-dich/">Đạo (Dịch)</a></h5>'
    .. '<div class="list-chapter"><a href="https://xtruyen.vn/truyen/dao-dich/chuong-1106/">Chương 1106</a></div></div>'
    .. '</div></div></div><nav aria-label="Page navigation"><ul class="pagination">'
    .. '<li class="page-item"><a class=\'page-link\' href=\'?m_orderby=latest&amp;page=2\'>2</a></li></ul></nav></div>'
    .. '<div class="widget-content" id="last_story_content"><div class="popular-item-wrap">'
    .. '<h5 class="widget-title"><a href="https://xtruyen.vn/truyen/sidebar-1/">Sidebar</a></h5></div></div>'
body = cards
local listed = assert(T.search('dao dich'))
assert(#listed.items == 1, 'sidebar widget cards are not search hits, got ' .. #listed.items)
assert(listed.items[1].ref == '/truyen/dao-dich/' and listed.items[1].title == 'Đạo (Dịch)')
assert(listed.items[1].url == 'https://xtruyen.vn/truyen/dao-dich/')
assert(listed.items[1].cover == 'https://thumb.xtruyen.vn/dao-dich.webp', 'cover comes from the card image')
assert(listed.has_more, 'the page-2 link means has_more')
assert(not T.search('') and not T.search(string.rep('x', 301)))
assert(not T.search('x', 0) and not T.search('x', 'abc'))
assert(not T.browse('khong-co-the-loai'), 'unknown list kind is rejected')
body = '<html>chrome only</html>'
assert(not T.browse('latest'), 'empty browse page 1 fails closed')
assert(#T.search('khong-co-gi').items == 0, 'empty search may return no hits')

local seen_urls = {}
local base_get = H.get
H.get = function(url, opts) seen_urls[#seen_urls + 1] = url; return base_get(url, opts) end
body = cards
assert(#assert(T.browse('latest', 1)).items == 1)
assert(#assert(T.browse('popular', 3)).items == 1)
assert(#assert(T.browse('completed', 1)).items == 1)
assert(seen_urls[1] == 'https://xtruyen.vn/truyen/?m_orderby=latest&page=1', 'latest URL: ' .. tostring(seen_urls[1]))
assert(seen_urls[2] == 'https://xtruyen.vn/truyen/?m_orderby=trending&page=3', 'popular URL: ' .. tostring(seen_urls[2]))
assert(seen_urls[3] == 'https://xtruyen.vn/truyen/?m_orderby=trending&status=end&page=1', 'completed URL: ' .. tostring(seen_urls[3]))
assert(#assert(T.browse('tien-hiep', 2)).items == 1)
assert(seen_urls[4] == 'https://xtruyen.vn/theloai/tien-hiep/?page=2', 'genre URL: ' .. tostring(seen_urls[4]))
local seen_keys, seen_names = {}, {}
for _, genre in ipairs(T.genres) do
    assert(not seen_keys[genre.key], 'duplicate genre key: ' .. genre.key)
    assert(not seen_names[genre.name], 'duplicate genre name: ' .. genre.name)
    assert(genre.key:match('^[a-z0-9%-]+$'), 'genre key must be URL-safe: ' .. genre.key)
    seen_keys[genre.key], seen_names[genre.name] = true, true
end
assert(not T.browse('sac'), 'the 18+ genre is blocked while 18+ is off')
Settings.set('adult_content', true)
assert(#assert(T.browse('sac', 1)).items == 1, 'the 18+ genre is allowed when 18+ is on')
assert(seen_urls[5] == 'https://xtruyen.vn/theloai/sac/', 'adult genre URL: ' .. tostring(seen_urls[5]))
Settings.set('adult_content', false)
H.get = base_get

-- getSeries: title/description/author/cover plus the chapter range built from
-- the two nav buttons (the full TOC is only rendered by the site's JS).
local story = '<div class="post-title center"><h1> Đạo (Dịch) </h1></div>'
    .. '<div class="tab-summary"><div class="summary_image"><img src="https://img.xtruyen.vn/dao-dich.webp" alt=""></div>'
    .. '<div class="summary_content_wrap"><div class="summary_content"><div class="post-content">'
    .. '<div class="summary__content show-more"><p>Lâm Vũ Văn sau một giấc ngủ &amp; tỉnh dậy.</p><p>  Đó rốt cuộc là gì?</p></div>'
    .. '<div class="post-content_item"><div class="summary-heading"><h3>Tác giả</h3></div><div class="summary-content">'
    .. '<div class="author-content"><a href="https://www.xtruyen.vn/tacgia/ma-tu/" rel="tag">Mã Tử</a></div></div></div>'
    .. '</div></div></div></div>'
    .. '<div id="init-links" class="nav-links"><a href="https://xtruyen.vn/truyen/dao-dich/chuong-1/" class="c-btn c-btn_style-1">Chương đầu</a>'
    .. '<a href="https://xtruyen.vn/truyen/dao-dich/chuong-3/" class="c-btn c-btn_style-1">Chương cuối</a></div>'
H.get = function(url) calls = calls + 1; return true, 200, story end
local series = assert(T.getSeries('/truyen/dao-dich/'))
assert(series.id == 'dao-dich' and series.title == 'Đạo (Dịch)')
assert(series.author == 'Mã Tử')
assert(series.description == 'Lâm Vũ Văn sau một giấc ngủ & tỉnh dậy.\n\nĐó rốt cuộc là gì?', tostring(series.description))
assert(series.cover == 'https://img.xtruyen.vn/dao-dich.webp')
assert(#series.chapters == 3, 'range 1..3, got ' .. #series.chapters)
assert(series.chapters[1].id == '1' and series.chapters[1].title == 'Chương 1' and series.chapters[1].index == 1)
assert(series.chapters[3].id == '3' and series.chapters[3].index == 3)
assert(series.chapters[1].series_id == 'dao-dich')
assert(series.chapters[1].url == 'https://xtruyen.vn/truyen/dao-dich/chuong-1/')
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters)

-- An unnumbered intro page must be kept and put first.
local intro = story:gsub('dao%-dich/chuong%-1/', 'dao-dich/gioi-thieu/'):gsub('dao%-dich/chuong%-3/', 'dao-dich/chuong-2/')
H.get = function() calls = calls + 1; return true, 200, intro end
local with_intro = assert(T.getSeries('/truyen/dao-dich/'))
assert(#with_intro.chapters == 3, 'intro + 1..2, got ' .. #with_intro.chapters)
assert(with_intro.chapters[1].id == 'gioi-thieu' and with_intro.chapters[1].title == 'Giới thiệu')
assert(with_intro.chapters[1].url == 'https://xtruyen.vn/truyen/dao-dich/gioi-thieu/')
assert(with_intro.chapters[2].id == '1' and with_intro.chapters[3].id == '2')

-- Without both nav buttons there is no trustworthy table of contents, so the
-- adapter fails closed instead of returning a partial "Mới nhất" tail.
local only_latest = '<div class="post-title center"><h1> Đạo (Dịch) </h1></div>'
    .. '<div class="l-chapter"><div class="summary-content-chapter">'
    .. '<a class="chapter-title btn-link" href="https://xtruyen.vn/truyen/dao-dich/chuong-9/" title="Chương 9">Chương 9</a></div></div>'
H.get = function() calls = calls + 1; return true, 200, only_latest end
assert(not T.getSeries('/truyen/dao-dich/'), 'a page without the first/last buttons fails closed')
H.get = function() calls = calls + 1; return true, 200, '<h1>x</h1>' end
assert(not T.getSeries('/truyen/dao-dich/'), 'a page without a title or TOC fails closed')
H.get = function() calls = calls + 1; return false, 500, nil end
assert(not T.getSeries('/truyen/dao-dich/'), 'HTTP error surfaces')

-- getChapter: the body only exists inside the custom-base64 zlib `data_x` blob.
-- Vector produced with Python zlib + the site's own alphabet translation.
local DATA_X = 'udFPerMFbRQxZ-7KCikSiklSbC1KhCaCwBFyrE6RgBayjn5Okmp1ylRioEG6FEQ-B0s0w-clmw=='
local RAW = string.char(120,218,115,57,188,41,47,93,33,247,225,238,153,37,54,73,69,118,46,96,110,70,98,166,130,90,98,110,129,181,66,82,162,77,113,114,81,102,65,137,93,82,98,138,134,166,141,62,148,7,0,131,227,21,90)
local PLAIN = 'Dòng một<br>Dòng hai &amp; ba<script>bad()</script>'
local chapter = series.chapters[1]
local page = '<div class="c-page-content"><h1 id="chapter-heading"><a href="/truyen/dao-dich/">Đạo</a></h1>'
    .. '<h2>Chương 1</h2><div class="reading-content"><div id="chapter-reading-content"></div></div>'
    .. '<script id="script-x">const data_x = "' .. DATA_X .. '";</script></div>'
local payload_calls, captured = 0, nil
T.inflate = function(data, limit)
    payload_calls = payload_calls + 1
    assert(limit >= 1024 * 1024, 'a sane inflate limit')
    captured = data
    return PLAIN
end
assert(T.decode('<html>no payload</html>') == nil, 'a page without data_x decodes to nothing')
local decoded = assert(T.decode(page))
assert(captured == RAW, 'custom alphabet + base64 must reproduce the exact zlib stream')
assert(decoded == PLAIN)
H.get = function() return code == 200, code, page end
local chapter_body = assert(T.getChapter(chapter))
assert(chapter_body.title == 'Chương 1')
assert(chapter_body.html == '<p>Dòng một</p>\n<p>Dòng hai &amp; ba</p>', tostring(chapter_body.html))
assert(not chapter_body.html:find('bad', 1, true), 'script body is dropped before wrapping')
-- Without a TOC title the chapter heading on the page is used.
local untitled = assert(T.getChapter({ url = chapter.url, series_id = 'dao-dich' }))
assert(untitled.title == 'Chương 1', 'page <h2> is the title fallback')

H.get = function(url) calls = calls + 1; return true, 200, url:find('lock', 1, true) and
    '<html>Vui lòng đăng nhập để đọc chương này</html>' or '<html>Captcha</html>' end
chapter.url = 'https://xtruyen.vn/truyen/dao-dich/chuong-1/'
assert(T.getChapter(chapter).skipped, 'a chapter with no payload skips instead of aborting the range')
H.get = function() return true, 200, '<html>Vui lòng đăng nhập để đọc chương này</html>' end
assert(T.getChapter(chapter).skipped, 'a login wall is reported as locked')
T.inflate = function() return '' end
assert(T.getChapter(chapter).skipped, 'an empty inflated body skips')
T.inflate = function() return nil end
assert(T.getChapter(chapter).skipped, 'a failed inflate skips rather than raising')
T.inflate = function() return PLAIN end
assert(payload_calls > 0, 'the payload pipeline is actually exercised')
-- Back to a code-aware transport for the HTTP-status branches.
H.get = function() return code == 200, code, page end
code = 404
assert(T.getChapter(chapter).skipped, 'a dead chapter link skips')
code = 429
assert(not T.getChapter(chapter), '429 stops the range so the reader can retry')
code = 200
series.chapters[1].series_id = 'other'
assert(not T.getChapter(series.chapters[1]), 'a chapter from another series is refused')
series.chapters[1].series_id = 'dao-dich'
series.chapters[1].locked = true
assert(T.getChapter(series.chapters[1]).skipped, 'a flagged locked chapter never fetches')
series.chapters[1].locked = false
assert(not T.getChapter({ url = chapter.url }), 'a chapter without series_id is refused')
assert(not T.getChapter(series), 'a series ref is not a chapter')

H.get = original
print('XTruyen list, TOC range, payload decode and chapter error checks passed')
