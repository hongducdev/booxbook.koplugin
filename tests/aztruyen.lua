local T = require('booxbook.sources.aztruyen')
local H = require('booxbook.http')
local Settings = require('booxbook.store.settings')
local original = H.get
local calls, body, code = 0, '', 200
H.get = function(url, opts) calls = calls + 1; assert(opts.referer and opts.delay_ms >= 1600); return code == 200, code, body end

-- parseRef: /{slug}-{id}/ is a series, /{slug}-{id}/{chapter}-{cid}/ a chapter.
assert(T.parseRef('https://aztruyen.top/oneshot-406872661/') == 'oneshot-406872661')
assert(T.parseRef('/ai-bao-quan-kinh-thanh-co-tien-co-thit-113207702/') == 'ai-bao-quan-kinh-thanh-co-tien-co-thit-113207702')
local book, cid, path = T.parseRef('https://aztruyen.top/oneshot-406872661/1-1603899570/')
assert(book == 'oneshot-406872661' and cid == '1603899570' and path == '/oneshot-406872661/1-1603899570/')
assert(T.parseRef('https://evil.test/oneshot-406872661/') == nil, 'foreign host rejected')
assert(T.parseRef('https://aztruyen.top/sidebar-111/') == 'sidebar-111')
assert(not T.parseRef('https://aztruyen.top/khong-co-id/'), 'series needs the numeric id')
assert(not T.parseRef('/oneshot-406872661/chuong-abc/'), 'chapter needs a numeric tail')
assert(not T.parseRef('/oneshot-406872661/1-1603899570/2-2/'), 'depth is bounded')
assert(not T.parseRef(nil) and not T.parseRef(42) and not T.parseRef(''))
assert(not T.getSeries('https://evil.test/oneshot-406872661/') and calls == 0)

-- Search + browse share one card parser; sidebar li.story-top must stay out.
local cards = '<div class="col-lg-9 content"><div class="row storylist">'
    .. '<div class="col-sm-12 col-md-6 story"> <a href="https://aztruyen.top/oneshot-406872661/" class="thumbnail" title="Oneshot"><img '
    .. 'src="https://aztruyen.top/images-135x203/oneshot-406872661.webp" data-src="https://aztruyen.top/images/oneshot-406872661.webp" alt="Oneshot">'
    .. '<span class="full-label"></span></a><div class="text"><h2 class="crop-text-2" itemprop="name">'
    .. '<a href="https://aztruyen.top/oneshot-406872661/" title="Oneshot">Oneshot &#8211; Hai</a></h2></div></div>'
    .. '</div><div class="pagination-control"><ul class="page"><li class="active"><a href="#">1</a></li>'
    .. '<li><a href="https://aztruyen.top/tim-kiem/x?page=2">2</a></li></ul></div></div>'
    .. '<div class="col-lg-3 sidebar"><ul><li class="story-top"><h3 class="titles">'
    .. '<a href="https://aztruyen.top/sidebar-111/">Sidebar</a></h3></li></ul></div>'
body = cards
local listed = assert(T.search('oneshot'))
assert(#listed.items == 1, 'sidebar cards are not search hits')
assert(listed.items[1].ref == '/oneshot-406872661/' and listed.items[1].title == 'Oneshot \226\128\147 Hai')
assert(listed.items[1].cover == 'https://aztruyen.top/images/oneshot-406872661.webp', 'data-src beats the thumbnail')
assert(listed.items[1].url == 'https://aztruyen.top/oneshot-406872661/')
assert(listed.has_more, 'page 2 link means has_more')
assert(not T.search('') and not T.search(string.rep('x', 301)))
assert(not T.browse('khong-co-the-loai'), 'unknown list kind is rejected')
assert(not T.browse('latest', 0) and not T.browse('latest', 'abc'))
body = '<html>chrome only</html>'
assert(not T.browse('latest'), 'empty browse page 1 fails closed')
assert(#T.search('khong-co-gi').items == 0, 'empty search may return no hits')

-- Genre keys are the site slugs, so browse() needs no extra mapping.
local genre_url
local base_get = H.get
H.get = function(url, opts) genre_url = url; return base_get(url, opts) end
body = cards
assert(#assert(T.browse('truyen-teen', 2)).items == 1)
assert(genre_url == 'https://aztruyen.top/the-loai/truyen-teen/?page=2', 'genre browse URL: ' .. tostring(genre_url))
H.get = base_get
local seen_keys, seen_names = {}, {}
for _, genre in ipairs(T.genres) do
    assert(not seen_keys[genre.key], 'duplicate genre key: ' .. genre.key)
    assert(not seen_names[genre.name], 'duplicate genre name: ' .. genre.name)
    assert(genre.key:match('^[a-z0-9%-]+$'), 'genre key must be URL-safe: ' .. genre.key)
    seen_keys[genre.key], seen_names[genre.name] = true, true
end
assert(#T.genres == 28, 'the live taxonomy has 28 genres')

-- getSeries: title/author/description/cover, and the widest chapter list wins.
local first = '<div class="col-xs-12 col-sm-4 col-md-4 col-lg-3"><div class="center thumb">'
    .. '<img src="https://aztruyen.top/images/ai-bao-quan-113207702.webp" itemprop="image" class="cover" alt="A"></div>'
    .. '<div class="infos"><p class="author"><svg viewBox="0 0 24 24"><path d="M1 1"></path></svg><a href="https://aztruyen.top/tac-gia/trieu-hi-chi/">Triệu Hi Chi</a></p></div></div>'
    .. '<h1 itemprop="name" class="title">Ai Bảo Quan Kinh Thành</h1>'
    .. '<div class="description show" itemprop="description"><p>Quan ở kinh thành &amp; có thịt. <br />Giới thiệu: nhiều chữ.</p>'
    .. '<div class="tag-meta">Tags: <a href="https://aztruyen.top/tim-kiem/quan">#quan</a></div></div>'
    .. '<div class="box_stories" id="chapters"><div class="title">Chương mới nhất</div><ul class="chapters">'
    .. '<li class="listc"> <a href="https://aztruyen.top/ai-bao-quan-113207702/chuong-2-222/" title="Chương 2: Hai">Chương 2: Hai</a></li>'
    .. '<li class="listc"> <a href="https://aztruyen.top/ai-bao-quan-113207702/chuong-3-333/" title="Chương 3: Ba">Chương 3: Ba</a></li>'
    .. '</ul><div class="title">Danh sách chương</div><ul class="chapters">'
    .. '<li class="listc"> <a href="https://aztruyen.top/ai-bao-quan-113207702/chuong-1-111/" title="Chương 1: Một">Chương 1: Một</a></li>'
    .. '<li class="listc"> <a href="https://aztruyen.top/ai-bao-quan-113207702/chuong-2-222/" title="Chương 2: Hai">Chương 2: Hai</a></li>'
    .. '<li class="listc"> <a href="https://aztruyen.top/ai-bao-quan-113207702/chuong-3-333/" title="Chương 3: Ba">Chương 3: Ba</a></li>'
    .. '</ul></div>'
H.get = function(url) calls = calls + 1; return true, 200, first end
local series = assert(T.getSeries('/ai-bao-quan-113207702/'))
assert(series.title == 'Ai Bảo Quan Kinh Thành' and series.id == 'ai-bao-quan-113207702')
assert(series.author == 'Triệu Hi Chi' and series.description == 'Quan ở kinh thành & có thịt.\nGiới thiệu: nhiều chữ.')
assert(series.cover == 'https://aztruyen.top/images/ai-bao-quan-113207702.webp')
assert(#series.chapters == 3, 'dedup: latest block + full list = 3 unique chapters, got ' .. #series.chapters)
assert(series.chapters[1].id == '111' and series.chapters[1].title == 'Chương 1: Một' and series.chapters[1].index == 1)
assert(series.chapters[3].id == '333' and series.chapters[3].index == 3)
assert(series.chapters[1].series_id == 'ai-bao-quan-113207702', 'chapter carries its series id')
assert(series.chapters[1].url == 'https://aztruyen.top/ai-bao-quan-113207702/chuong-1-111/')
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters)

-- A page without any chapter link of this story must fail closed.
H.get = function() calls = calls + 1; return true, 200, '<h1 itemprop="name" class="title">X</h1>' end
assert(not T.getSeries('https://aztruyen.top/ai-bao-quan-113207702/'), 'no TOC is a hard error')
H.get = function() calls = calls + 1; return false, 500, nil end
assert(not T.getSeries('https://aztruyen.top/ai-bao-quan-113207702/'), 'HTTP error surfaces')

-- getChapter: content extraction, script stripped, entities decoded.
H.get = function() return code == 200, code, body end
body = '<div class="chapter_show"><h2 class="chapter-title" id="chapter">1.</h2>'
    .. '<div class="chapter-content"> <p>Tiếng Việt &amp; chữ</p><script>bad()</script><br><br><p>Dòng hai</p> </div>'
    .. '<p class="chapter-end"> Bạn đang đọc truyện trên: AzTruyen.Top </p></div>'
local chapter = series.chapters[1]
local text = assert(T.getChapter(chapter))
assert(text.title == 'Chương 1: Một')
assert(text.html:find('<p>Tiếng Việt &amp; chữ</p>', 1, true), 'entities decoded then re-escaped: ' .. text.html)
assert(text.html:find('<p>Dòng hai</p>', 1, true))
assert(not text.html:find('bad', 1, true), 'script body is dropped')
assert(not text.html:find('Bạn đang đọc', 1, true), 'watermark outside the content div is dropped')

body = '<div class="chapter-content"> <p>Teaser</p><button>Mở khóa</button><form action="/x"></form> </div>'
assert(T.getChapter(chapter).skipped, 'lock button inside the body must skip')
body = '<html>Vui lòng đăng nhập để đọc chương này</html>'
assert(T.getChapter(chapter).skipped, 'login wall skips instead of aborting the range')
body = '<div class="chapter-content">   </div>'
assert(T.getChapter(chapter).skipped, 'empty chapter skips')
body = '<html>Captcha</html>'
assert(T.getChapter(chapter).skipped, 'unparseable chapter body is skipped')
code = 404
assert(T.getChapter(chapter).skipped, '404 chapter is skipped, not fatal')
code = 429
assert(not T.getChapter(chapter), '429 stops the range so the reader can retry')
code = 200
series.chapters[1].series_id = 'other'
assert(not T.getChapter(series.chapters[1]), 'a chapter from another series is refused')
series.chapters[1].series_id = 'ai-bao-quan-113207702'
series.chapters[1].locked = true
assert(T.getChapter(series.chapters[1]).skipped, 'flagged locked chapter never fetches')
series.chapters[1].locked = false
assert(not T.getChapter({ url = 'https://aztruyen.top/oneshot-406872661/1-1603899570/', title = 'x' }),
    'a chapter without series_id is refused')
assert(T.parseRef('https://aztruyen.top/oneshot-406872661/1-1603899570/') == 'oneshot-406872661')
assert(not T.getChapter(T.parseRef('https://aztruyen.top/oneshot-406872661/')), 'a series ref is not a chapter')

H.get = original
print('AzTruyen list, TOC order/dedup, chapter extraction and error checks passed')
