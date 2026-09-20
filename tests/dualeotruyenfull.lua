local T = require('booxbook.sources.dualeotruyenfull')
local Settings = require('booxbook.store.settings')
local H = require('booxbook.http')
local original = H.get
local calls, url_seen, body, code = 0, '', '', 200
H.get = function(url, opts)
    calls = calls + 1
    url_seen = url
    assert(opts and opts.delay_ms >= 1600, 'a source request must be paced')
    assert(opts.referer == 'https://dualeotruyenfull.net/', 'a source request must carry a referer')
    return code == 200, code, body
end

-- Ref parsing: series URL, relative path, chapter URL, and the rejections.
assert(T.parseRef('https://dualeotruyenfull.net/doc-truyen/linh-vu/') == 'linh-vu')
assert(T.parseRef('/doc-truyen/linh-vu/') == 'linh-vu')
assert(T.parseRef('https://www.dualeotruyenfull.net/doc-truyen/linh-vu/') == 'linh-vu')
local book, cid = T.parseRef('https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong-93/')
assert(book == 'linh-vu' and cid == '93')
assert(not T.parseRef('https://evil.test/doc-truyen/linh-vu/'), 'foreign host must not resolve')
assert(not T.parseRef('/doc-truyen//'), 'malformed slug must not resolve')
assert(not T.parseRef('/doc-truyen/linh-vu/chuong-0/'), 'chapter numbers start at 1')
assert(not T.parseRef('/doc-truyen/linh-vu/chuong-93/extra/'), 'trailing junk must not resolve')
assert(not T.parseRef(nil) and not T.parseRef(7))
local chapter = { url = 'https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong-93/', series_id = 'linh-vu' }
assert(T.chapterRef(chapter) == 'linh-vu' and select(2, T.chapterRef(chapter)) == '93')
chapter.series_id = 'other'
local no_series, no_id = T.chapterRef(chapter)
assert(no_series == nil and no_id == '93', 'chapter from another series keeps no series id')
assert(T.locate({ url = 'https://dualeotruyenfull.net/doc-truyen/linh-vu/' }) == 'linh-vu')

local function grid(slug, title)
    return '<div class="manga-item-grid">'
        .. '<a href="https://dualeotruyenfull.net/doc-truyen/' .. slug .. '/">'
        .. '<img class="image-3-4" src="https://img.test/' .. slug .. '-300x400.webp" alt="Ảnh bìa"></a>'
        .. '<h3 class="uk-h5"><a class="uk-link-heading" href="https://dualeotruyenfull.net/doc-truyen/'
        .. slug .. '/">' .. title .. '</a></h3>'
        .. '<a class="uk-button" href="https://dualeotruyenfull.net/doc-truyen/' .. slug
        .. '/chuong-9/">Chương 9</a></div>'
end
local slider = '<div class="story-cover-wrap"><a class="uk-link-toggle" '
    .. 'href="https://dualeotruyenfull.net/doc-truyen/dam-my-hay/">'
    .. '<img src="https://img.test/dam-my-hay.webp" alt="x">'
    .. '<strong class="uk-h2 slider-title">Đam Mỹ Hay</strong>'
    .. '<p class="slider-genres">#1v1 #sung</p></a></div>'
local sidebar = '<aside id="im-sidebar"><a href="https://dualeotruyenfull.net/doc-truyen/de-cu/">'
    .. 'Truyện đề cử</a></aside>'
local next_page = '<nav class="uk-pagination"><li><a href="https://dualeotruyenfull.net/moi-cap-nhat/page/2/">2</a></li></nav>'

-- Search and browse: cards plus the slider, sidebar widgets excluded, next page seen.
-- Search pages put the sidebar above the results and listings below them, so the
-- fixture does the awkward order on purpose.
body = sidebar .. grid('linh-vu', 'Linh Vũ') .. slider .. next_page
local found = assert(T.search('a b', 1))
assert(#found.items == 2, 'sidebar widgets must not join the listing')
assert(found.items[1].ref == '/doc-truyen/linh-vu/' and found.items[1].title == 'Linh Vũ')
assert(found.items[1].url == 'https://dualeotruyenfull.net/doc-truyen/linh-vu/')
assert(found.items[1].cover == 'https://img.test/linh-vu-300x400.webp')
assert(found.items[2].title == 'Đam Mỹ Hay', 'slider title must not swallow the genre list')
assert(found.items[2].cover == 'https://img.test/dam-my-hay.webp')
assert(found.has_more)
assert(url_seen == 'https://dualeotruyenfull.net/?s=a%20b', 'search URL: ' .. url_seen)
assert(#assert(T.search('a b', 2)).items == 2)
assert(url_seen == 'https://dualeotruyenfull.net/page/2/?s=a%20b', 'paged search URL: ' .. url_seen)
assert(not T.search('') and not T.search(('x'):rep(301)))
assert(url_seen == 'https://dualeotruyenfull.net/page/2/?s=a%20b', 'rejected search must not hit the network')

-- Browse entries hit the site's own listings.
assert(#assert(T.browse('latest', 2)).items == 2)
assert(url_seen == 'https://dualeotruyenfull.net/moi-cap-nhat/page/2/', 'latest URL: ' .. url_seen)
assert(#assert(T.browse('popular', 1)).items == 2)
assert(url_seen == 'https://dualeotruyenfull.net/bang-xep-hang-truyen/', 'popular URL: ' .. url_seen)
assert(#assert(T.browse('completed', 1)).items == 2)
assert(url_seen == 'https://dualeotruyenfull.net/truyen-da-hoan-thanh/', 'completed URL: ' .. url_seen)
assert(not T.browse('khong-co'), 'unknown list kind is rejected')
assert(not T.browse('latest', 0), 'page zero is rejected')
assert(not T.browse(nil, 1.5), 'fractional page is rejected')

-- An empty first listing page fails closed instead of showing an empty grid.
body = '<html>chrome only</html>'
assert(not T.browse('latest'))
assert(#T.search('xyz', 1).items == 0, 'search may legitimately return no hits')

-- Genre keys are the site filter slugs, so browse() needs no extra mapping.
local base_get = H.get
H.get = function(url, opts)
    calls = calls + 1
    url_seen = url
    assert(opts.delay_ms >= 1600)
    return true, 200, grid('linh-vu', 'Linh Vũ') .. next_page
end
assert(#assert(T.browse('sung', 2)).items == 1)
assert(url_seen == 'https://dualeotruyenfull.net/bo-loc-nang-cao/page/2/?genre%5B0%5D=sung&sort=updated',
    'genre browse URL: ' .. url_seen)
local seen_keys, seen_names = {}, {}
for _, genre in ipairs(T.genres) do
    assert(not seen_keys[genre.key], 'duplicate genre key: ' .. genre.key)
    assert(not seen_names[genre.name], 'duplicate genre name: ' .. genre.name)
    assert(genre.key:match('^[a-z0-9%-]+$'), 'genre key must be URL-safe: ' .. genre.key)
    seen_keys[genre.key], seen_names[genre.name] = true, true
end
-- The site's own description is 18+; explicit tags stay hidden until 18+ is on.
local before_adult = calls
assert(not T.browse('caoh'), 'adult genre blocked while 18+ is off')
assert(calls == before_adult, 'a blocked adult genre must not hit the network')
assert(#assert(T.browse('sung', 1)).items == 1, 'non-adult genres keep working while 18+ is off')
Settings.set('adult_content', true)
assert(#assert(T.browse('caoh', 1)).items == 1, 'adult genre allowed when 18+ is on')
Settings.set('adult_content', false)
H.get = base_get

local function story(og_image, chapters, extra)
    local parts = { '<html><head><meta property="og:image" content="' .. og_image .. '"></head><body>',
        '<h1 id="manga-title" class="uk-h3">Linh Vũ</h1>',
        '<div id="manga-description" class="uk-text-justify"><p>Tóm tắt &amp; chữ</p></div>',
        '<div class="manga-info-details">Tác giả: <a class="uk-text-capitalize" href="#">Vũ Phong</a></div>' }
    for _, n in ipairs(chapters) do
        parts[#parts + 1] = '<div class="chapter-item"><a class="uk-link-toggle" '
            .. 'href="https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong-' .. n .. '/">'
            .. '<h3 class="uk-link-heading uk-h5">Chương ' .. n .. '</h3></a></div>'
    end
    parts[#parts + 1] = extra or ''
    return table.concat(parts, '\n')
end
local toc_page1 = story('https://img.test/linh-vu.webp', { 93, 92, 92 },
    '<a href="https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong/page/2/#chapter-list">2</a>')
local toc_page2 = story('https://img.test/linh-vu.webp', { 2, 1 })
H.get = function(url)
    calls = calls + 1
    url_seen = url
    return true, 200, url:find('chuong/page/2', 1, true) and toc_page2 or toc_page1
end
local series = assert(T.getSeries('/doc-truyen/linh-vu/'))
assert(url_seen == 'https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong/page/2/', 'TOC page URL')
assert(#series.chapters == 4, 'duplicate chapters are collapsed')
assert(series.chapters[1].id == '1' and series.chapters[2].id == '2'
    and series.chapters[3].id == '92' and series.chapters[4].id == '93', 'chapters in reading order')
assert(series.chapters[1].index == 1 and series.chapters[4].index == 4)
assert(series.chapters[1].series_id == 'linh-vu' and series.chapters[1].url
    == 'https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong-1/')
assert(series.chapters[1].title == 'Chương 1')
assert(not series.truncated)
assert(series.author == 'Vũ Phong' and series.description == 'Tóm tắt & chữ')
assert(series.cover == nil, 'WebP covers are left to the grid, not the EPUB')
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters)
assert(not T.getSeries('https://evil.test/doc-truyen/linh-vu/'), 'foreign host is rejected before any request')
assert(not T.getSeries('/doc-truyen/linh-vu/chuong-1/'), 'a chapter URL is not a series URL')

-- A JPEG cover may be written into an EPUB.
H.get = function() return true, 200, story('https://img.test/linh-vu.jpg', { 1 }) end
assert(assert(T.getSeries('/doc-truyen/linh-vu/')).cover == 'https://img.test/linh-vu.jpg')

-- A TOC page that offers yet another next page but no new chapter must stop,
-- not loop or return half a table of contents.
H.get = function(url)
    local page = tonumber(url:match('/chuong/page/(%d+)/') or '1')
    return true, 200, story('https://img.test/linh-vu.jpg', { 1 },
        '<a href="https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong/page/'
        .. (page + 1) .. '/#chapter-list">' .. (page + 1) .. '</a>')
end
assert(not T.getSeries('/doc-truyen/linh-vu/'), 'a repeated TOC page must fail closed')

-- A site that always offers a next page must stop at the page cap and keep what
-- it already read, instead of spinning until the reader gives up.
local toc_calls = 0
H.get = function(url)
    toc_calls = toc_calls + 1
    local page = tonumber(url:match('/chuong/page/(%d+)/') or '1')
    return true, 200, story('https://img.test/linh-vu.jpg', { 1000 + page },
        '<a href="https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong/page/'
        .. (page + 1) .. '/#chapter-list">' .. (page + 1) .. '</a>')
end
local capped = assert(T.getSeries('/doc-truyen/linh-vu/'))
assert(capped.truncated, 'an endless table of contents is truncated')
assert(toc_calls <= 61, 'table of contents stops at the page cap, calls=' .. toc_calls)
assert(#capped.chapters == 60, 'the chapters already read are kept')

local chapter_ref = series.chapters[1]
H.get = function() return code == 200, code, body end
body = '<h1 class="uk-h2">Chương 1: Mở đầu</h1><div id="chapter-content" class="uk-article text-based">'
    .. '<div id="ads-chapter-top"></div><p>Tiếng Việt &amp; chữ</p><script>bad()</script>'
    .. '<p>Hai<br>Ba</p></div><div class="uk-margin-top">footer</div>'
local got = assert(T.getChapter(chapter_ref))
assert(got.title == 'Chương 1: Mở đầu')
assert(got.html:find('<p>Tiếng Việt &amp; chữ</p>', 1, true), 'entities are decoded and re-escaped')
assert(not got.html:find('bad', 1, true), 'scripts are stripped')
assert(not got.html:find('ads%-chapter%-top'), 'ad placeholder carries no text')
assert(got.html:find('<p>Hai</p>', 1, true) and got.html:find('<p>Ba</p>', 1, true), '<br> splits paragraphs')
assert(not got.html:find('footer', 1, true), 'only the chapter body is kept')

-- Locked, empty and unreadable bodies skip one chapter; they never abort a range.
body = '<div id="chapter-content"><p>Teaser</p><button>Mở khóa</button></div>'
assert(T.getChapter(chapter_ref).skipped, 'a lock button inside the body must skip')
body = '<html>Captcha</html>'
assert(T.getChapter(chapter_ref).skipped, 'a body without #chapter-content must skip')
body = '<div id="chapter-content">   </div>'
assert(T.getChapter(chapter_ref).skipped, 'an empty chapter must skip')
body = '<div id="chapter-content"><script>only_script()</script></div>'
assert(T.getChapter(chapter_ref).skipped, 'a script-only chapter must skip')
code = 404
assert(T.getChapter(chapter_ref).skipped, 'a missing chapter must skip')
code = 429
assert(not T.getChapter(chapter_ref), 'a rate-limited chapter must not be reported as empty')
code = 200
local locked = { url = chapter_ref.url, series_id = 'linh-vu', title = 'Chương 1', locked = true }
assert(T.getChapter(locked).skipped, 'a locked chapter must not be requested')

-- Boundaries: a chapter from another series, and a non-table ref.
assert(not T.getChapter({ url = chapter_ref.url, series_id = 'other', title = 'x' }))
assert(not T.getChapter({ url = 'https://evil.test/doc-truyen/linh-vu/chuong-1/', series_id = 'linh-vu' }))
assert(not T.getChapter('https://dualeotruyenfull.net/doc-truyen/linh-vu/chuong-1/'))

H.get = original
