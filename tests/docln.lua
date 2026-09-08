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
-- Chapter pacing must not freeze cover fetches on the UI thread.
local seen_delay
Http.get = function(url, options)
    seen_delay = options.delay_ms
    return true, 200, '\255\216\255' .. string.rep('z', 20)
end
assert(Covers.fetch('docln', 'https://docln.net/img/paced.jpg', { referer = 'https://docln.net/', delay_ms = 2000 }))
assert(seen_delay ~= nil and seen_delay <= 200, 'cover delay capped for UI safety')
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
assert(#downloaded.saved == 2 and #downloaded.skipped == 1 and #writes == 6)
assert(writes[1][2]:find('charset="utf-8"', 1, true) and writes[1][2]:find('Tiếng Việt', 1, true))
assert(index.chapters['11'].file ~= index.chapters['13'].file and index.chapters['12'].skipped)

-- A valid indexed file is reused without touching the chapter endpoint; a stale
-- index entry falls through to the normal download path.
local indexed = index
package.loaded.json.decode = function() return indexed end
io.open = function(path)
    if path:match('index%.json$') then
        return { read = function() return '{"id":"truyen-1"}' end, close = function() end }
    end
    if path:match('ch%-000000000011%.html$') then return { close = function() end } end
    return nil, 'no such file', 2
end
Http.get = function() error('existing chapter must not request') end
local writes_before_reuse = #writes
local reused = assert(Download.range(series, 1, 1))
assert(#reused.saved == 0 and #reused.existing == 1 and reused.existing[1].path:match('%.html$'))
assert(#writes == writes_before_reuse, 'existing-only range must not write files')
local requests = 0
io.open = function(path)
    if path:match('index%.json$') then
        return { read = function() return '{"id":"truyen-1"}' end, close = function() end }
    end
    return nil, 'no such file', 2
end
Http.get = function()
    requests = requests + 1
    return true, 200, '<div id="chapter-content"><p>Tải lại</p></div>'
end
local refreshed = assert(Download.range(series, 1, 1))
assert(#refreshed.saved == 1 and #refreshed.existing == 0 and requests == 1)
io.open = function() return nil end
package.loaded.json.decode = nil
Http.get = function() return true, 200, '<div id="chapter-content"><p>Tiếng Việt</p></div>' end
local Epub = require('booxbook.epub')
local old_epub_write, exports = Epub.write, 0
local Export = require('booxbook.novel-export')
Epub.write = function(path, book)
    exports = exports + 1
    assert(path:find('/chapters-1-1.epub', 1, true) and #book.chapters == 1)
    return true
end
Settings.set('novel_epub', false)
local manual = { saved = { downloaded.saved[1] }, skipped = {}, keep_html = true }
Export.finish(series, '/test', 1, 1, index, manual, package.loaded.json, true)
assert(exports == 1 and #manual.saved == 2 and manual.saved[1].path:match('%.epub$'),
    'explicit EPUB export works while automatic export is disabled and keeps HTML')
exports = 0
Settings.set('novel_epub', true)
Epub.write = function(path, book)
    exports = exports + 1
    assert(path:find('/chapters-1-3.epub', 1, true))
    assert(#book.chapters == 2 and book.chapters[1].path:match('%.html$'))
    return true
end
local epub_result = assert(Download.range(series, 1, 3))
assert(#epub_result.saved == 3 and epub_result.saved[1].path:match('%.epub$'))
local Covers = require('booxbook.covers')
local old_fetch, old_cover, successful_write = Covers.fetch, series.cover, Epub.write
series.cover = '/original-cover.jpg'
Covers.fetch = function(source, url, opts)
    assert(source == 'docln' and url:match('^https://.+/original%-cover.jpg$'))
    assert(opts.referer:match('^https://') and opts.cookies == nil)
    return '/cached/cover.jpg'
end
Epub.write = function(_, book)
    assert(book.title == series.title and book.author == series.author)
    assert(book.cover_path == '/cached/cover.jpg' and book.url:match('^https://'))
    assert(book.identifier:find('#chapters-1-3', 1, true))
    return true
end
assert(not Download.range(series, 1, 3).error)
Covers.fetch = function() return nil end
assert(Download.range(series, 1, 3).error, 'missing cover must not silently export a coverless EPUB')
Covers.fetch, series.cover, Epub.write = old_fetch, old_cover, successful_write
local interrupted = Download.range(series, 1, 3, false, function(n) return n < 2 end)
assert(interrupted.error and #interrupted.saved == 1 and exports == 1)
assert(interrupted.cancelled and interrupted.saved[1].number == 1)
local old_json_decode, old_io_open = package.loaded.json.decode, io.open
package.loaded.json.decode = function() return index end
io.open = function(path)
    if tostring(path):find('index.json', 1, true) then
        return { read = function() return '{"id":"ok"}' end, close = function() end }
    end
    return nil
end
Settings.set('novel_keep_html', false)
Epub.write = function(path, book)
    exports = exports + 1
    assert(path:find('/chapters-1-1.epub', 1, true))
    assert(#book.chapters == 1 and book.chapters[1].path:match('%.html$'))
    return true
end
local packaged = assert(Download.packagePartial(series, 1, 1, interrupted.saved))
assert(not packaged.error and #packaged.saved == 2 and packaged.saved[1].path:match('%.epub$'))
assert(packaged.saved[2].path:match('%.html$') and exports == 2, 'cancel pack keeps HTML even when novel_keep_html=false')
io.open, package.loaded.json.decode = old_io_open, old_json_decode
Epub.write = function() return false, 'archive failed' end
Settings.set('novel_keep_html', false)
local failed_epub = Download.range(series, 1, 3)
assert(failed_epub.error:find('archive failed', 1, true) and #failed_epub.saved == 2)
Epub.write = function() error('no EPUB for all-skipped range') end
assert(#Download.range(series, 2, 2).saved == 0)
Epub.write = function() return true end
local old_remove, deleted = os.remove, {}
os.remove = function(path)
    assert(index.chapters['11'].file == 'chapters-1-3.epub', 'index committed before HTML deletion')
    assert(path:match('ch%-%d+%.html$'), 'only this download HTML is removed')
    deleted[#deleted + 1] = path
    return true
end
local only_epub = Download.range(series, 1, 3)
assert(not only_epub.error and #only_epub.saved == 1 and #deleted == 2)
assert(index.chapters['13'].file == 'chapters-1-3.epub')
os.remove = function() return nil, 'permission denied' end
local cleanup_failure = Download.range(series, 1, 3)
assert(cleanup_failure.error and #cleanup_failure.saved == 3)
assert(index.chapters['11'].file:match('%.html$') and index.chapters['13'].file:match('%.html$'))
local deletes = 0
os.remove = function(path)
    deletes = deletes + 1
    if deletes == 1 then return true end
    return nil, 'permission denied'
end
local partial_cleanup = Download.range(series, 1, 3)
assert(partial_cleanup.error and #partial_cleanup.saved == 2 and deletes == 2)
assert(index.chapters['11'].file == 'chapters-1-3.epub')
assert(index.chapters['13'].file:match('%.html$'), 'remaining HTML is restored in index')
local previous_write = Html.writeFile
Html.writeFile = function(path, content)
    if path:match('index.json$') and index.chapters['11'].file:match('%.epub$') then
        return false, 'index write failed'
    end
    return previous_write(path, content)
end
os.remove = function() error('never delete HTML before committing EPUB index') end
local index_failure = Download.range(series, 1, 3)
assert(index_failure.error:find('index write failed', 1, true) and #index_failure.saved == 3)
Html.writeFile, os.remove = previous_write, old_remove
Settings.set('novel_keep_html', true)
Epub.write = old_epub_write
Settings.set('novel_epub', false)
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
io.open = function(path)
    if tostring(path):find('index.json', 1, true) then
        return { read = function() return '{}' end, close = function() end }
    end
    return nil
end
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
