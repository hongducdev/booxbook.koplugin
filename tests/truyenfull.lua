local T = require('booxbook.sources.truyenfull')
local H = require('booxbook.http')
local original = H.get
local calls, body, code = 0, '', 200
H.get = function(url, opts) calls = calls + 1; assert(opts.delay_ms >= 1600); return code == 200, code, body end
assert(T.parseRef('https://truyenfull.live/linh-vu-thien-ha/') == 'linh-vu-thien-ha')
assert(T.parseRef('/than-dao-dan-ton-6060282') == 'than-dao-dan-ton-6060282')
local book, cid = T.parseRef('https://truyenfull.live/linh-vu-thien-ha/chuong-1/')
assert(book == 'linh-vu-thien-ha' and cid == '1')
assert(not T.getSeries('https://evil.test/linh-vu-thien-ha/') and calls == 0)
assert(not T.parseRef('/../x/') and not T.parseRef('/x/chuong-0/'))
body = '<div class="list-truyen"><div class="row"><div data-image="https://img.test/c.jpg" data-classname="cover"></div>'
    .. '<h3 class="truyen-title"><a href="https://truyenfull.live/linh-vu-thien-ha/">Linh Vũ</a></h3></div></div>'
    .. '<a href="/danh-sach/truyen-moi/trang-2/">2</a>'
local listed = assert(T.search('đạo quân'))
assert(#listed.items == 1 and listed.has_more and listed.items[1].cover:find('c.jpg', 1, true))
assert(not T.search('') and not T.browse('latest', 0))
body = '<html>chrome only</html>'
assert(not T.browse('popular'), 'empty browse page 1 must fail closed')
body = '<html>chrome only</html>'
assert(#T.search('xyz').items == 0, 'empty search may return no hits')
local first = '<div class="book"><img src="https://static.test/c.jpg" alt="Linh Vũ"></div>'
    .. '<div class="desc-text">Tóm tắt</div><a itemprop="author">Vũ Phong</a>'
    .. '<div id="list-chapter"><a href="https://truyenfull.live/linh-vu-thien-ha/chuong-2/">Hai</a></div>'
    .. '<a href="https://truyenfull.live/linh-vu-thien-ha/trang-2/#list-chapter">2</a>'
local second = '<div id="list-chapter"><a href="https://truyenfull.live/linh-vu-thien-ha/chuong-1/">Một</a></div>'
H.get = function(url) calls = calls + 1; return true, 200, url:find('trang-2', 1, true) and second or first end
local series = assert(T.getSeries('/linh-vu-thien-ha/'))
assert(#series.chapters == 2 and series.chapters[1].id == '1' and series.chapters[2].index == 2)
assert(series.author == 'Vũ Phong' and series.description == 'Tóm tắt' and series.cover:find('c.jpg', 1, true))
H.get = function(url)
    return true, 200, url:find('trang-2', 1, true) and first:gsub('trang%-2', 'trang-3', 1) or first
end
assert(not T.getSeries('/linh-vu-thien-ha/'), 'repeated TOC must stop, not return incomplete chapters')
H.get = function() return code == 200, code, body end
body = '<div id="chapter-c"><p>Tiếng Việt &amp; chữ</p><script>bad()</script><p>Hai</p></div>'
assert(T.getChapter(series.chapters[1]).html:find('Tiếng Việt &amp; chữ', 1, true))
assert(not T.getChapter(series.chapters[1]).html:find('bad', 1, true))
body = '<button>Mở khóa</button>'
assert(T.getChapter(series.chapters[1]).skipped)
body = '<div id="chapter-c"><p>Teaser</p><button>Mở khóa</button></div>'
assert(T.getChapter(series.chapters[1]).skipped, 'lock button inside chapter body must skip')
body = '<div id="chapter-c">   </div>'
assert(T.getChapter(series.chapters[1]).skipped, 'empty chapter skips instead of aborting the range')
code = 404; assert(T.getChapter(series.chapters[1]).skipped); code = 200
code = 429; assert(not T.getChapter(series.chapters[1])); code = 200
body = '<html>Captcha</html>'
assert(T.getChapter(series.chapters[1]).skipped, 'unparseable chapter body is skipped')
series.chapters[1].series_id = 'other'; assert(not T.getChapter(series.chapters[1]))
series.chapters[1].series_id = 'linh-vu-thien-ha'
local Download = require('booxbook.novel-download')
local Settings = require('booxbook.store.settings')
local Html = require('booxbook.html')
local saved = {Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open, package.loaded.json}
local writes = {}
Settings.downloadDir = function() return 'test-output' end
Settings.ensureDir = function() return true end
Html.writeFile = function(path, content) writes[path] = content; return true end
io.open = function() return nil end
package.loaded.json = {encode = function() return '{}' end}
body = '<div id="chapter-c">Nội dung thật được trả từ transport</div>'
local result = assert(Download.range(series, 1, 1))
assert(not result.error and #result.saved == 1)
assert(writes['test-output/novels/truyenfull/linh-vu-thien-ha/ch-000000000001.html'])
assert(writes['test-output/novels/truyenfull/linh-vu-thien-ha/index.json'])
series.chapters[1].url = 'https://truyenfull.live/other/chuong-1/'
assert(Download.range(series, 1, 1).error)
Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open, package.loaded.json = unpack(saved)
H.get = original
print('TruyenFull HTML, TOC pagination, URL boundaries and chapter error checks passed')
