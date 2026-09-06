local S = require("booxbook.sources.sangtacviet")
local Glyphs = require("booxbook.sources.sangtacviet-glyphs")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Html = require("booxbook.html")
local Download = require("booxbook.novel-download")

local original = {
    Http.get, Http.post, package.loaded.json, Settings.cookie("sangtacviet"),
    Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open,
}
local get_calls, post_calls, last_get, last_post = {}, {}, nil, nil

local function decode_json(value)
    if value == "bad" then error("invalid") end
    local start = value:find("{", 1, true) or 1
    value = value:sub(start)
    local code = value:match('"code"%s*:%s*"?([%w%-]+)"?')
    if code == "100" and value:find('"list"', 1, true) then
        local items = {}
        for host, id, tname, thumb in value:gmatch(
            '"host"%s*:%s*"([^"]+)"%s*,%s*"id"%s*:%s*"([^"]+)"%s*,%s*"tname"%s*:%s*"([^"]*)"[^}]-"thumb"%s*:%s*"([^"]*)"') do
            items[#items + 1] = { host = host, id = id, tname = tname, thumb = thumb }
        end
        -- Fallback looser extraction if pretty-printed order differs.
        if #items == 0 then
            for block in value:gmatch("%b{}") do
                if block:find('"host"', 1, true) and block:find('"id"', 1, true) then
                    items[#items + 1] = {
                        host = block:match('"host"%s*:%s*"([^"]+)"'),
                        id = block:match('"id"%s*:%s*"([^"]+)"'),
                        tname = block:match('"tname"%s*:%s*"([^"]*)"'),
                        thumb = block:match('"thumb"%s*:%s*"([^"]*)"'),
                    }
                end
            end
        end
        return { code = 100, list = items }
    end
    if code == "0" then
        local data = value:match('"data"%s*:%s*"(.-)"%s*,%s*"chaptername"')
            or value:match('"data"%s*:%s*"(.-)"')
        if data then
            data = data:gsub("\\n", "\n"):gsub('\\"', '"'):gsub("\\/", "/")
        end
        return {
            code = "0",
            data = data or "<p>ok</p>",
            chaptername = value:match('"chaptername"%s*:%s*"(.-)"') or "C1",
            bookhost = value:match('"bookhost"%s*:%s*"(.-)"') or "fanqie",
        }
    end
    if code == "100" then
        return { code = 100, book = {
            tname = value:match('"tname"%s*:%s*"(.-)"') or "Tiêu đề",
            hauthor = "A", thumb = "/t.jpg", info = "mô tả",
        } }
    end
    if code == "1" and value:find("-/-", 1, true) then
        local data = value:match('"data"%s*:%s*"(.-)"')
        return { code = 1, data = data }
    end
    if code == "1" then return { code = 1 } end
    if code == "7" then return { code = 7 } end
    if code == "12" then return { code = 12 } end
    if code == "21" then return { code = 21 } end
    return {}
end

package.loaded.json = { decode = decode_json, encode = function() return "{}" end }
Settings.setCookie("sangtacviet", "paste=1")
Settings.set("stv_home", "https://sangtacviet.com")
S._resetSession()

Http.get = function(url, opts)
    get_calls[#get_calls + 1] = { url = url, opts = opts }
    last_get = { url = url, opts = opts }
    assert(opts.delay_ms >= 2000, "STV delay must be >= 2s")
    if opts.cookies then
        local header = Http.cookieHeader(opts.cookies)
        assert(header and header:find("transmode=name", 1, true))
        assert(header:find("foreignlang=vi", 1, true))
    end
    return true, 200, [[
<a class="booksearch" href="/truyen/fanqie/1/99/">
<span class="searchbooktitle">Truyện A</span><img src="/c.jpg"/></a>
]], {}, {}
end

Http.post = function(url, body, opts)
    post_calls[#post_calls + 1] = { url = url, body = body, opts = opts }
    last_post = { url = url, body = body, opts = opts }
    assert(opts.delay_ms >= 2000)
    return true, 200, '{"code":"0","data":"<p>ok</p>","chaptername":"C","bookhost":"fanqie"}', {}, { _ac = "rotated" }
end

assert(Glyphs.MAP_SIZE == 242)
local pua = string.char(0xEE, 0x80, 0x9B) -- U+E01B
assert(Glyphs.decode(pua .. "!") == "A!")
assert(S._normalizeBody("sangtac", pua .. "<br>x"):find("<p>A</p>", 1, true))
assert(S._normalizeBody("sangtac", "[img=1,2]http://x[/img]hi"):find("hi", 1, true))

assert(S.parseRef("https://sangtacviet.app/truyen/fanqie/1/123/").bookid == "123")
assert(S.seriesId(S.parseRef("/truyen/fanqie/1/123/")) == "fanqie-123")
assert(S.parseRef("https://evil.test/truyen/fanqie/1/123/") == nil)
assert(not S.getSeries("https://evil.test/truyen/fanqie/1/1"))

local browse = assert(S.browse("update", 1))
assert(#browse.items == 1 and browse.items[1].ref == "fanqie-99")
assert(last_get.url:find("sort=update", 1, true))
assert(S.browse("view") and last_get.url:find("sort=view", 1, true))
assert(not S.browse("hot"))

-- Live CDN often returns JSON when Accept includes application/json.
Http.get = function(url, opts)
    last_get = { url = url, opts = opts }
    assert(opts.delay_ms >= 2000)
    return true, 200, [[{
      "code":100,
      "list":[
        {"host":"fanqie","id":"7614470742809250840","tname":" Truyện JSON ",
         "thumb":"https://cdn.example/cover.jpg"},
        {"host":"qidian","id":"1048172826","tname":"Truyện 2","thumb":"/t2.jpg"}
      ]
    }]], {}, {}
end
local json_browse = assert(S.browse("update", 1))
assert(#json_browse.items == 2)
assert(json_browse.items[1].ref == "fanqie-7614470742809250840")
assert(json_browse.items[1].title == "Truyện JSON")
assert(json_browse.items[1].cover == "https://cdn.example/cover.jpg")
assert(json_browse.items[2].ref == "qidian-1048172826")
assert(json_browse.has_more == false)

Http.get = function(url, opts)
    last_get = { url = url, opts = opts }
    assert(opts.delay_ms >= 2000)
    assert(opts.referer or (opts.headers and opts.headers.referer))
    if url:find("bookinfo", 1, true) then
        assert(opts.headers["x-stv-transport"] == "app")
        return true, 200, '{"code":100,"book":{"tname":"Fanqie Story","hauthor":"A","thumb":"/t.jpg"}}', {}, {}
    end
    if url:find("getchapterlist", 1, true) then
        return true, 200,
            '{"code":1,"data":"1-/-7678581890042825752-/-Chuong 1-/-unvip-//-1-/-99-/-VIP chap-/-vipcoin"}', {}, {}
    end
    return true, 200, 'document.cookie="_ac=prime; path=/"; document.cookie="_gac=g; path=/";', {}, { PHPSESSID = "s" }
end

local series = assert(S.getSeries("https://sangtacviet.com/truyen/fanqie/1/55/"))
assert(series.id == "fanqie-55" and series.source_id == "sangtacviet")
assert(#series.chapters == 2)
assert(series.chapters[1].id == "7678581890042825752")
assert(series.chapters[2].locked == true)
assert(S.getChapter(series.chapters[2]).skipped)

S._resetSession()
local prime_bodies = {}
Http.post = function(url, body, opts)
    last_post = { url = url, body = body, opts = opts }
    post_calls[#post_calls + 1] = last_post
    prime_bodies[#prime_bodies + 1] = body
    assert(opts.referer and opts.referer:find("/truyen/fanqie/", 1, true), "chapter POST needs Referer")
    assert(body == "prime" or body == "rotated" or body == "r" or body == "x"
        or (type(body) == "string" and not body:find("path=", 1, true)),
        "POST body must be bare _ac token")
    local payload = '\239\187\191{"code":"0","data":"<p>Hello &amp; Viet</p>","chaptername":"C1","bookhost":"fanqie"}'
    return true, 200, payload, {}, { _ac = "rotated" }
end
local content = assert(S.getChapter(series.chapters[1]))
assert(content.html:find("Hello", 1, true), "readable chapter html")
assert(prime_bodies[1] == "prime", "rotation POST uses bare _ac from document.cookie")
assert(#post_calls >= 1)

-- Empty body after retry stops the queue.
S._resetSession()
local empty_posts = 0
Http.get = function()
    return true, 200, 'document.cookie="_ac=x; path=/";', {}, { PHPSESSID = "s" }
end
Http.post = function(url, body, opts)
    empty_posts = empty_posts + 1
    assert(body == "x" or body == "rotated")
    if empty_posts <= 2 then
        -- prime rotate may succeed with jar; chapter posts return empty twice
        if url:find("readchapter", 1, true) and empty_posts >= 1 then
            return true, 200, "", {}, { _ac = "rotated" }
        end
    end
    return true, 200, "", {}, { _ac = "rotated" }
end
local empty_result, empty_err = S.getChapter(series.chapters[1])
assert(empty_result == nil and empty_err:find("trống", 1, true))
assert(empty_posts >= 2, "empty body retries once before stop")

S._resetSession()
Http.get = function()
    return true, 200, 'document.cookie="_ac=x; path=/";', {}, {}
end
Http.post = function()
    return true, 200, '{"code":21}', {}, {}
end
local stopped, stop_err = S.getChapter(series.chapters[1])
assert(stopped == nil and stop_err:find("captcha", 1, true))

S._resetSession()
Http.post = function()
    return true, 200, '{"code":7}', {}, {}
end
stopped, stop_err = S.getChapter(series.chapters[1])
assert(stopped == nil and stop_err:find("giới hạn", 1, true))

S._resetSession()
Http.post = function()
    return true, 200, '{"code":12}', {}, {}
end
assert(S.getChapter(series.chapters[1]).skipped)

S._resetSession()
Http.get = function()
    return true, 200, 'document.cookie="_ac=x; path=/";', {}, {}
end
Http.post = function()
    return true, 200, '{"code":"0","data":"<p>Tieng Viet dai id</p>","chaptername":"C1","bookhost":"fanqie"}', {}, { _ac = "r" }
end
local writes = {}
Settings.downloadDir = function() return "test-output" end
Settings.ensureDir = function(path)
    assert(path == "test-output/novels/sangtacviet/fanqie-55")
    return true
end
io.open = function() return nil, "not found", 2 end
Html.writeFile = function(path, text) writes[path] = text; return true end
local result = assert(Download.range(series, 1, 2))
assert(#result.saved == 1 and #result.skipped == 1)
assert(writes["test-output/novels/sangtacviet/fanqie-55/ch-7678581890042825752.html"])
assert(writes["test-output/novels/sangtacviet/fanqie-55/index.json"])

Http.get, Http.post = original[1], original[2]
package.loaded.json = original[3]
Settings.setCookie("sangtacviet", original[4])
Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open =
    original[5], original[6], original[7], original[8]
S._resetSession()
print("Sangtacviet adapter/download checks passed")
