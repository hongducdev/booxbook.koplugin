local T = require('booxbook.sources.cbunu')
local H = require('booxbook.http')
local get_original, post_original = H.get, H.post
local get_calls, post_calls, body, code = 0, 0, '', 200
local jar, post_code, post_jar = nil, 200, nil

H.get = function(url, opts)
    get_calls = get_calls + 1
    assert(opts.delay_ms >= 1600, 'GET keeps a per-source pacing floor')
    return code == 200, code, body, nil, jar
end
H.post = function(url, post_body, opts)
    post_calls = post_calls + 1
    assert(post_body:match('^access_pass='), 'gate answer posts access_pass')
    assert(opts.max_hops == 0, 'gate answer must not follow its own redirect')
    return post_code == 200, post_code, '', nil, post_jar
end

-- --- reference parsing -------------------------------------------------------
assert(T.parseSeriesRef('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295').id == 'hang-xom-nha-ben-295')
assert(T.parseSeriesRef('https://cbunu.com/truyen-tranh/salt-society--230/').id == 'salt-society--230')
assert(not T.parseSeriesRef('https://evil.test/truyen-tranh/hang-xom-nha-ben-295'), 'foreign host rejected')
assert(not T.parseSeriesRef('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html'), 'chapter is not a series')
assert(not T.parseSeriesRef('https://cucbongunu.com/'))

local ch = T.parseRef('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.5.html')
assert(ch and ch.series == 'hang-xom-nha-ben-295' and ch.number == 19.5, 'fractional chapter number')
assert(ch.url == 'https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.5.html')
assert(T.parseRef('https://cbunu.com/truyen-tranh/blue-lie-326-chap-9').number == 9, 'extension-less chapter URL')
assert(not T.parseRef('https://evil.test/truyen-tranh/blue-lie-326-chap-9.html'), 'foreign chapter host rejected')
assert(not T.parseRef('https://cucbongunu.com/truyen-tranh/blue-lie-326-chap-0.html'), 'chapter 0 rejected')
assert(not T.parseRef('https://cucbongunu.com/truyen-tranh/blue-lie-326'), 'series URL is not a chapter')

-- --- listing -----------------------------------------------------------------
local home = table.concat({
    '<div class="story-item"><a href="https://cucbongunu.com/truyen-tranh/blue-lie-326" title="Blue Lie">',
    '<img class="story-cover lazy_cover" src="https://cucbongunu.com/page/upload/story/190x247/blue-lie.jpg" alt="Blue Lie"/></a>',
    '<h3 class="title-book"><a href="https://cucbongunu.com/truyen-tranh/blue-lie-326">Blue Lie</a></h3></div>',
    '<div class="story-item"><a href="https://cucbongunu.com/truyen-tranh/salt-society--230" title="Salt Society">',
    '<img src="https://cucbongunu.com/page/upload/story/190x247/salt.jpg" alt="Salt Society"/></a>',
    '<h3 class="title-book"><a href="https://cucbongunu.com/truyen-tranh/salt-society--230">Salt Society</a></h3></div>',
    '<div class="story-item"><a href="https://cucbongunu.com/truyen-tranh/blue-lie-326" title="Blue Lie">',
    '<img src="https://cucbongunu.com/page/upload/story/190x247/blue-lie.jpg" alt="Blue Lie"/></a></div>',
    '<div class="story-item"><a href="https://evil.test/truyen-tranh/foreign-1" title="Foreign">x</a></div>',
    '<a class="pagination-link" href="https://cucbongunu.com/trang-2.html">2</a>',
}, '')
body = home
local listed = assert(T.parseList(home, 1))
assert(#listed.items == 2, 'deduped story items, foreign host dropped: ' .. #listed.items)
assert(listed.items[1].title == 'Blue Lie' and listed.items[1].name == 'Blue Lie')
assert(listed.items[1].cover == 'https://cucbongunu.com/page/upload/story/190x247/blue-lie.jpg')
assert(listed.items[1].url == 'https://cucbongunu.com/truyen-tranh/blue-lie-326', 'list item keeps its series URL')
assert(listed.has_more, 'a later page link means more')

local browse_url
H.get = function(url, opts)
    get_calls = get_calls + 1
    browse_url = url
    return true, 200, home, nil, nil
end
assert(#assert(T.browse('latest', 1)).items == 2)
assert(browse_url == 'https://cucbongunu.com/', 'page 1 is the homepage')
T.browse('latest', 2)
assert(browse_url == 'https://cucbongunu.com/trang-2.html', 'page 2 is /trang-2.html')
T.browse('hay', 1)
assert(browse_url == 'https://cucbongunu.com/truyen-tranh-hay.html')
T.browse('hay', 3)
assert(browse_url == 'https://cucbongunu.com/truyen-tranh-hay/trang-3.html')
T.browse('completed', 2)
assert(browse_url == 'https://cucbongunu.com/truyen-hoan-thanh/trang-2.html')
assert(not T.browse('khong-co', 1), 'unknown list kind is rejected')
assert(not T.browse('latest', 0), 'invalid page rejected')

local search_url
H.get = function(url) search_url = url; return true, 200, home, nil, nil end
assert(#assert(T.search('blue lie')).items == 2)
assert(search_url == 'https://cucbongunu.com/tim-kiem.html?q=blue%20lie', 'search URL: ' .. search_url)
assert(not T.search(''))
-- A search with no hits is a legitimate empty result, not a changed page.
H.get = function() return true, 200, '<html><body><p>Không có kết quả</p></body></html>', nil, nil end
local empty = assert(T.search('zzzqqq'))
assert(#empty.items == 0 and not empty.has_more)
-- But an empty browse page 1 means the layout moved under us.
assert(not T.browse('latest', 1), 'empty browse page 1 fails closed')

-- --- series ------------------------------------------------------------------
local story = table.concat({
    '<div class="block01"><div class="left"><img src="/page/upload/story/190x247/cnt-hang-xom.png" alt="Hàng Xóm Nhà Bên"/></div>',
    '<div class="center box"><h1 itemprop="name">Hàng Xóm Nhà Bên</h1>',
    '<div class="txt"><span class="info-item">Tên Khác: Next Door</span>',
    '<p class="info-item">Tác giả: <a class="org" href="#">MunKkwa</a></p>',
    '<p class="info-item">Tình trạng: Đang tiến hành</p></div></div></div>',
    '<ul class="list01"><li><a>BL</a></li><li><a>Manhwa</a></li></ul>',
    '<meta name="description" content="Đọc truyện tranh Hàng Xóm Nhà Bên tiếng việt."/>',
    '<div class="works-chapter-list">',
    '<div class="works-chapter-item row"><a href="https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.5.html">Chương 19.5 - Chim khôm che</a></div>',
    '<div class="works-chapter-item row"><a href="https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html">Chương 19 - H+</a></div>',
    '<div class="works-chapter-item row"><a href="https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-2.html">Chương 2</a></div>',
    '<div class="works-chapter-item row"><a href="https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-2.html">Chương 2 lặp</a></div>',
    '<div class="works-chapter-item row"><a href="https://cucbongunu.com/truyen-tranh/khac-1-chap-1.html">Truyện khác</a></div>',
    '</div>',
}, '')
H.get = function() return true, 200, story, nil, nil end
local series = assert(T.getSeries('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295'))
assert(series.title == 'Hàng Xóm Nhà Bên' and series.source_id == 'cbunu')
assert(series.author == 'MunKkwa', 'author from .info-item: ' .. tostring(series.author))
assert(series.cover == 'https://cucbongunu.com/page/upload/story/190x247/cnt-hang-xom.png')
assert(series.description == 'Đọc truyện tranh Hàng Xóm Nhà Bên tiếng việt.')
assert(#series.chapters == 3, 'deduped, other series dropped: ' .. #series.chapters)
assert(series.chapters[1].number == 2 and series.chapters[2].number == 19 and series.chapters[3].number == 19.5,
    'chapters are sorted into reading order')
assert(series.chapters[1].index == 1 and series.chapters[3].index == 3)
assert(#series.volumes == 1 and #series.volumes[1].chapters == 3)
assert(T.seriesUrl('hang-xom-nha-ben-295') == 'https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295')

-- --- chapter -----------------------------------------------------------------
local chapter_html = table.concat({
    '<h1 class="detail-title"><a href="#">Hàng Xóm Nhà Bên</a> Chap 19</h1>',
    '<div class="story-see-content">',
    '<img src="/asset/image/thong_bao_chap.jpg?v2"/>',
    '<img class="lazy" src="https://cucbongunu.com/page/upload/chap/manga/hang-xom-nha-ben/19/01.webp" alt="p1"/>',
    '<img class="lazy" src="https://cucbongunu.com/page/upload/chap/manga/hang-xom-nha-ben/19/02.webp" alt="p2"/>',
    '<img class="lazy" src="https://evil.test/page/upload/chap/manga/x/19/03.webp" alt="p3"/>',
    '<script>bad()</script>',
    '</div>',
}, '')
H.get = function() return true, 200, chapter_html, nil, nil end
local parsed = assert(T.getChapter('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html'))
assert(#parsed.pages == 2, 'notice image and foreign image dropped: ' .. #parsed.pages)
assert(parsed.pages[1] == 'https://cucbongunu.com/page/upload/chap/manga/hang-xom-nha-ben/19/01.webp')
assert(parsed.pages[2]:match('02%.webp$'))
assert(parsed.title == 'Hàng Xóm Nhà Bên Chap 19', 'title from h1: ' .. tostring(parsed.title))
assert(not parsed.pages[1]:find('script', 1, true))

-- --- access gate -------------------------------------------------------------
get_calls, post_calls = 0, 0
local unlocked = false
H.post = function(_url, post_body, opts)
    post_calls = post_calls + 1
    assert(post_body == 'access_pass=2026' or post_body == 'access_pass=12345')
    assert(opts.max_hops == 0)
    -- The gate answers 302 and sets its session cookie on that same response.
    return false, 302, '', { ['set-cookie'] = 'access_pass=ok; Path=/' }, { access_pass = 'ok' }
end
-- Following the redirect would have fetched the login page again; the adapter
-- must read the jar off the 302 and retry the chapter with it.
H.get = function(url, opts)
    get_calls = get_calls + 1
    if opts and opts.cookies and opts.cookies.access_pass == 'ok' then
        unlocked = true
        return true, 200, chapter_html, nil, nil
    end
    return false, 403, '<html><title>Đăng nhập</title></html>', nil, nil
end
local gated = assert(T.getChapter('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html'))
assert(post_calls == 1, 'first shared password is enough: ' .. post_calls)
assert(unlocked and #gated.pages == 2, 'the unlocked chapter is parsed')

-- Both passwords refused: the chapter is reported as locked, not as a crash.
-- Reload the adapter first so the session cookie the successful unlock cached
-- does not leak into this case.
package.loaded['booxbook.sources.cbunu'] = nil
T = require('booxbook.sources.cbunu')
H.post = function() post_calls = post_calls + 1; return false, 403, '', nil, nil end
local refused, refuse_err = T.getChapter('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html')
assert(refused == nil and type(refuse_err) == 'string' and not refuse_err:find('%.lua:'), 'gate refusal is a sentence')

-- A rate limit must not be mistaken for the gate.
H.get = function() return false, 429, '', nil, nil end
local _rate, rate_err = T.getChapter('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html')
assert(rate_err and rate_err:find('429', 1, true), 'rate limit reported: ' .. tostring(rate_err))

-- A page cap exists so a runaway chapter cannot fill the disk.
local many = { '<div class="story-see-content">' }
for i = 1, 700 do
    many[#many + 1] = '<img class="lazy" src="https://cucbongunu.com/page/upload/chap/manga/x/1/'
        .. string.format('%03d', i) .. '.webp"/>'
end
many[#many + 1] = '</div>'
H.get = function() return true, 200, table.concat(many), nil, nil end
local _capped, cap_err = T.getChapter('https://cucbongunu.com/truyen-tranh/hang-xom-nha-ben-295-chap-19.html')
assert(cap_err and cap_err:find('600', 1, true), '600-page cap enforced: ' .. tostring(cap_err))

H.get, H.post = get_original, post_original
