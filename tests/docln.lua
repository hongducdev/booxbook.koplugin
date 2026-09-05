local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Rate = require("booxbook.rate_limit")
local Parser = require("booxbook.sources.docln-parser")
local Payload = require("booxbook.sources.docln-payload")
local Docln = require("booxbook.sources.docln")
local Download = require("booxbook.novel-download")
assert(#Html.selectAllInner('<div class="v"><div>x</div></div><div class="v">y</div>', '.v') == 2)
assert(Html.select('<p>First</p><p>Second</p>', 'p') == 'First')
assert(not Parser.path('https://evil.example/truyen/1'))
assert(not Parser.path('//evil.example/truyen/1'))
assert(not Parser.path('/truyen/1/../../secret'))
assert(not Parser.path('/truyen/1%2f..'))
assert(Parser.path('https://ln.hako.vn/truyen/1-a/c12-b') == '/truyen/1-a/c12-b')
local search = [[<main class="sect-body"><div class="thumb-item-flow"><a href="/truyen/1-book/c1">Latest</a>
<div class="series-title"><a href="/truyen/1-book" title="Tiếng Việt &amp; LN">short</a></div></div>
<div class="thumb-item-flow"><span>18+</span><div class="series-title"><a href="/truyen/2-adult">Adult</a></div></div>
</main><div class="pagination_wrap"><a href="?keywords=x&amp;page=2">Next</a></div>]]
local found = Parser.search(search, 1, false)
assert(#found.items == 1 and found.items[1].title == 'Tiếng Việt & LN' and found.has_more)
assert(#Parser.search(search, 1, true).items == 2)
assert(not Parser.search(search, 2, false).has_more)
local toc = [[<span class="series-name">Tiếng Việt</span><div class="series-information">
<div class="info-item"><span class="info-name">Tác giả:</span><span class="info-value">Nguyễn A</span></div></div>
<section class="volume-list"><span class="sect-title">Tập 1</span><ul class="list-chapters">
<li><div class="chapter-name"><a href="/truyen/1-book/c11-one">Một</a></div></li>
<li><i class="fa-lock"></i><div class="chapter-name"><a href="/truyen/1-book/c12-two">Hai</a></div></li>
</ul></section><section class="volume-list"><span class="sect-title">Tập 2</span><ul class="list-chapters">
<li><div class="chapter-name"><a href="https://ln.hako.vn/truyen/1-book/c13-three">Ba</a></div></li>
</ul></section>]]
local series = assert(Parser.series(toc, '/truyen/1-book'))
assert(series.author == 'Nguyễn A' and #series.volumes == 2 and #series.chapters == 3)
assert(series.chapters[2].locked and series.chapters[3].index == 3)
assert(Parser.chapter('<div id="chapter-content"><div><p class="none">Hidden</p><p>Tiếng Việt</p></div>'
    .. '<script>bad()</script><p style="display: none">Hide</p><p><a href="javascript:bad()">OK</a></p></div>')
    == '<p>Tiếng Việt</p>\n<p>OK</p>')
assert(not Parser.chapter('<div id="chapter-content"><p class="none">No text</p></div>'))
assert(Payload.decode([[data-s="base64" data-c='["0002PHA+QjwvcD4=","0001PHA+QTwvcD4="]']]) == '<p>A</p><p>B</p>')
assert(Payload.decode([[data-s="base64_reverse" data-c='0001=4DcvwTQ+AH!P']]) == nil)
assert(Payload.decode([[data-s="base64_reverse" data-c='0001=4DcvwTQ+AHP']]) == '<p>A</p>')
assert(Payload.decode([[data-s="xor_shuffle" data-k="a" data-c='0001XRFfIF1OEV8=']]) == '<p>A</p>')
assert(not Payload.decode([[data-s="base64" data-c='["0001PHA+QTwvcD4=", "broken!"]']]))
assert(Parser.chapter([[<div id="chapter-content"><p>Before</p><div id="chapter-c-protected"
    data-s="base64" data-c="0001PHA+QTwvcD4="></div><p>After</p></div>]])
    == '<p>Before</p>\n<p>A</p>\n<p>After</p>')
assert(not Payload.decode([[data-s="unknown" data-c="QQ=="]]))
assert(not Payload.decode([[data-s="xor_shuffle" data-c="!"]]))

local original = { Http.get, Rate.wait, Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open,
    Settings.get('docln_home'), Settings.cookie('docln'), Settings.adultContent(), package.loaded.json }
local calls = {}
Rate.wait = function(_, delay) assert(delay >= 1500) end
Settings.set('docln_home', nil); Settings.setCookie('docln', 'test-session'); Settings.set('adult_content', false)
Http.get = function(url, options)
    assert(options.delay_ms >= 1500 and options.cookies == 'test-session')
    calls[#calls + 1] = url
    if url:find('docln.net', 1, true) then return false, 503 end
    return true, 200, search .. '<script src="/cdn-cgi/challenge-platform/script"></script>'
end
assert(Docln.search('a & b', 1))
assert(#calls == 2 and calls[2]:find('a%20%26%20b', 1, true))
assert(Settings.get('docln_home') == 'https://ln.hako.vn')
calls = {}
Http.get = function(url) calls[#calls + 1] = url; return false, 429 end
assert(not Docln.search('a', 1) and #calls == 1, '429 must stop, not switch mirrors')
Http.get = function() return true, 200, toc .. '<div class="series-gernes">Adult</div>' end
assert(not Docln.getSeries('/truyen/1-book'), 'direct open checks adult metadata')
Settings.set('adult_content', true)
assert(Docln.getSeries('/truyen/1-book'))
Settings.set('adult_content', false)
Http.get = function() error('locked chapter must not request') end
assert(Docln.getChapter(series.chapters[2]).skipped)
Http.get = function() return false, 404 end
assert(Docln.getChapter(series.chapters[1]).skipped)
assert(not Docln.search('', 1) and not Docln.search('x', 1.5))
assert(not Docln.getChapter('file:///private'))
assert(Docln.capabilities.browse == true)
assert(Docln.LIST_LIMIT == 6)
calls = {}
Http.get = function(url, options)
    calls[#calls + 1] = url
    assert(options.delay_ms >= 1500)
    return true, 200, search
end
local browsed = assert(Docln.browse('latest', 1))
assert(#browsed.items >= 1 and #browsed.items <= Docln.LIST_LIMIT)
assert(calls[1]:find('/tim%-kiem%-nang%-cao', 1) and calls[1]:find('sapxep=capnhat', 1, true))
-- Many thumb cards must be capped to one grid screen and keep paging.
local many = { '<main class="sect-body">' }
for i = 1, 12 do
    many[#many + 1] = string.format(
        '<div class="thumb-item-flow"><div class="series-title"><a href="/truyen/%d" title="T%d">T%d</a></div></div>',
        i, i, i)
end
many[#many + 1] = '</main>'
Http.get = function() return true, 200, table.concat(many) end
local capped = assert(Docln.search('many', 1))
assert(#capped.items == 6 and capped.has_more == true, 'search results capped to LIST_LIMIT')
calls = {}
Http.get = function(url)
    calls[#calls + 1] = url
    return true, 200, search
end
assert(Docln.browse('popular', 2))
assert(calls[1]:find('sapxep=top', 1, true) and calls[1]:find('page=2', 1, true))
assert(not Docln.browse('other', 1) and not Docln.browse('latest', 0))

-- Cover cache: only valid image signatures are stored; failures stay nil for title fallback.
local Covers = require('booxbook.covers')
assert(Covers.MAX_BYTES == 256 * 1024)
local cover_writes = {}
Settings.downloadDir = function() return '/covers-root' end
Settings.ensureDir = function() return true end
io.open = function(path, mode)
    if mode == 'rb' then return nil end
    if mode == 'wb' then
        return {
            write = function(_, data) cover_writes[#cover_writes + 1] = { path = path, data = data }; return true end,
            close = function() end,
        }
    end
end
Http.get = function(url, options)
    assert(options.referer:find('docln.net', 1, true) or options.referer:find('hako', 1, true))
    return true, 200, '\255\216\255' .. string.rep('x', 20)
end
local cover_path = assert(Covers.fetch('docln', 'https://docln.net/img/a.jpg', { referer = 'https://docln.net/' }))
assert(cover_path:find('%.jpg$') and #cover_writes == 1)
Http.get = function() return true, 200, 'not-an-image' end
assert(not Covers.fetch('docln', 'https://docln.net/img/bad.bin', { referer = 'https://docln.net/' }))
Http.get = function() return true, 200, '\255\216\255' .. string.rep('y', Covers.MAX_BYTES) end
assert(not Covers.fetch('docln', 'https://docln.net/img/huge.jpg', { referer = 'https://docln.net/' }), 'oversized covers rejected')
Http.get = function() error('should use cache') end
io.open = function(path, mode)
    if mode == 'rb' and path == cover_path then return { close = function() end } end
    return nil
end
assert(Covers.fetch('docln', 'https://docln.net/img/a.jpg', { referer = 'https://docln.net/' }) == cover_path)

-- Boundary doubles keep the real parser, adapter, range loop and index mutations under test.
local writes, index = {}, nil
Settings.downloadDir = function() return '/test' end
Settings.ensureDir = function() return true end
io.open = function() return nil end
package.loaded.json = { encode = function(value) index = value; return '{"id":"truyen-1"}' end }
Html.writeFile = function(path, text) writes[#writes + 1] = { path, text }; return true end
Http.get = function() return true, 200, '<div id="chapter-content"><p>Tiếng Việt</p></div>' end
local downloaded = assert(Download.range(series, 1, 3))
assert(#downloaded.saved == 2 and #downloaded.skipped == 1 and #writes == 5)
assert(writes[1][2]:find('charset="utf-8"', 1, true) and writes[1][2]:find('Tiếng Việt', 1, true))
assert(index.chapters['11'].file ~= index.chapters['13'].file and index.chapters['12'].skipped)
assert(not Download.range(series, 4, 4))
assert(not Download.range(series, 1.5, 2))
local many = { url = series.url, id = series.id, chapters = {} }
for i = 1, 51 do many.chapters[i] = series.chapters[1] end
assert(not Download.range(many, 1, 51))
assert(#Download.range(many, 1, 51, true).saved == 51)
Html.writeFile = function() return false, 'disk full' end
assert(Download.range(series, 1, 1).error == 'disk full')
Settings.ensureDir = function() return false end
assert(not Download.range(series, 1, 1))
Settings.ensureDir = function() return true end
Html.writeFile = function() return true end
Http.get = function() return false, 429 end
assert(Download.range(series, 1, 3).error)
assert(Download.range(series, 1, 3, false, function() return false end).error)
local stored = { id = series.id, chapters = { ['11'] = { file = 'existing.html' } } }
io.open = function() return { read = function() return '{}' end, close = function() end } end
package.loaded.json.decode = function() return stored end
series.chapters[1].locked = true
local preserved = Download.range(series, 1, 1)
assert(#preserved.skipped == 1 and index.chapters['11'].file == 'existing.html')
series.chapters[1].locked = false
package.loaded.json.decode = function() return nil end
assert(not Download.range(series, 1, 1), 'corrupt index must not be overwritten')
io.open = function() return nil end
Http.get = function() return true, 200, '<div id="chapter-content"><p>Text</p></div>' end
package.loaded.json.encode = function() return nil end
assert(Download.range(series, 1, 1).error, 'JSON serialization failures must stop the job')
Http.get, Rate.wait, Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open = unpack(original, 1, 6)
Settings.set('docln_home', original[7]); Settings.setCookie('docln', original[8]); Settings.set('adult_content', original[9])
package.loaded.json = original[10]
print('DocLN parser, payload, failover, adult/locked guards and range checks passed')
