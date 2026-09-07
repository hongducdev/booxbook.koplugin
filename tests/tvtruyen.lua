local T = require('booxbook.sources.tvtruyen')
local H = require('booxbook.http')
local original = H.get
local calls, body, code = 0, '', 200
H.get = function(url, opts) calls = calls + 1; assert(opts.delay_ms >= 1600); return code == 200, code, body end
assert(T.parseRef('https://www.tvtruyen.live/dao-quan.html') == 'dao-quan')
assert(T.parseRef('https://www.tvtruyen.live/dao-quan.html?utm=1') == 'dao-quan')
assert(not T.getSeries('https://evil.test/dao-quan.html') and calls == 0)
assert(not T.parseRef('/../x.html') and not T.parseRef('/x/chuong-0'))
body = '<div class="info-mobile-card"><div class="name"><a href="/dao-quan.html">Đạo Quân</a></div><img src="https://img.test/c.jpg"></div>'
assert(#T.search('đạo quân').items == 1)
assert(not T.search('') and not T.browse('latest', 0))
body = '<div class="category-list">64725 kết quả</div>'
assert(not T.browse('latest'), 'empty browse page 1 must fail closed')
assert(#T.search('xyz').items == 0, 'empty search may return no hits')
local first = '<h3 id="comic_name">Đạo Quân</h3><div id="mobile-list-chapter"><a href="/dao-quan/chuong-2" title="Hai">Hai</a></div><a rel="next" href="/dao-quan.html?page=2">Next</a>'
local second = '<div id="mobile-list-chapter"><a href="/dao-quan/chuong-1" title="Một">Một</a></div>'
H.get = function(url) calls = calls + 1; return true, 200, url:find('page=2',1,true) and second or first end
local series = assert(T.getSeries('/dao-quan.html'))
assert(#series.chapters == 2 and series.chapters[1].id == '1' and series.chapters[2].index == 2)
H.get = function(url)
    return true, 200, url:find('page=2', 1, true) and first:gsub('page=2', 'page=3') or first
end
assert(not T.getSeries('/dao-quan.html'), 'repeated TOC must stop, not return incomplete chapters')
H.get = function() return code == 200, code, body end
body = '<div id="chapter-content"><p>Tiếng Việt &amp; chữ</p><script>bad()</script><p>Hai</p></div>'
assert(T.getChapter(series.chapters[1]).html:find('Tiếng Việt &amp; chữ', 1, true))
assert(not T.getChapter(series.chapters[1]).html:find('bad',1,true))
body = '<button>Mở khóa</button>'
assert(T.getChapter(series.chapters[1]).skipped)
body = '<div id="chapter-content"><p>Teaser</p><button>Mở khóa</button></div>'
assert(T.getChapter(series.chapters[1]).skipped, 'lock button inside chapter body must skip')
body = '<div id="chapter-content">   </div>'
assert(T.getChapter(series.chapters[1]).skipped, 'empty chapter skips instead of aborting the range')
code = 429; assert(not T.getChapter(series.chapters[1])); code = 200
body = '<html>Captcha</html>'; assert(T.getChapter(series.chapters[1]).skipped, 'unparseable chapter body is skipped')
series.chapters[1].series_id = 'other'; assert(not T.getChapter(series.chapters[1]))
series.chapters[1].series_id = 'dao-quan'
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
body = '<div id="chapter-content">Nội dung thật được trả từ transport</div>'
local result = assert(Download.range(series, 1, 1))
assert(not result.error and #result.saved == 1)
assert(writes['test-output/novels/tvtruyen/dao-quan/ch-000000000001.html'])
assert(writes['test-output/novels/tvtruyen/dao-quan/index.json'])
series.chapters[1].url = 'https://www.tvtruyen.live/other/chuong-1'
assert(Download.range(series, 1, 1).error)
Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open, package.loaded.json = unpack(saved)
H.get = original
print('TVTruyen HTML, TOC pagination, URL boundaries and chapter error checks passed')
