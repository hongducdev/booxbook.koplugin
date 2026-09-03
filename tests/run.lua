local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

package.preload["socket"] = function()
    return {
        gettime = function()
            return os.time()
        end,
        sleep = function() end,
        skip = function(_, a, b, c, d)
            return a, b, c, d
        end,
    }
end

package.preload["socket.http"] = function()
    return {
        request = function()
            return 1, 200, { ["set-cookie"] = "sid=abc; Path=/" }, "OK"
        end,
    }
end

package.preload["ltn12"] = function()
    return {
        sink = {
            table = function(t)
                return function(chunk)
                    if chunk then
                        t[#t + 1] = chunk
                    end
                    return true
                end
            end,
        },
        source = {
            string = function(s)
                local sent = false
                return function()
                    if sent then
                        return nil
                    end
                    sent = true
                    return s
                end
            end,
        },
    }
end

local failures = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n  expected: " .. tostring(expected) .. "\n  actual:   " .. tostring(actual) .. "\n")
    end
end

local function assert_true(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local Html = require("html")
local Source = require("source")
local RateLimit = require("rate_limit")
local Http = require("http")
local Settings = require("store.settings")

-- sanitize: drop script, keep paragraphs, keep closing tags
local dirty = '<p>Hi</p><script>alert(1)</script><p onclick="x">Tiếng Việt</p><iframe src="x"></iframe>'
local clean = Html.sanitize(dirty)
assert_true(not clean:find("script", 1, true), "script removed")
assert_true(not clean:find("iframe", 1, true), "iframe removed")
assert_true(clean:find("</p>", 1, true), "closing p kept")
assert_true(clean:find("Tiếng Việt", 1, true), "utf8 kept")
assert_true(not clean:find("onclick", 1, true), "onclick removed")

-- select #id .class tag
local sample = [[<div class="wrap"><h1 id="title">Hello</h1><div class="chapter-content"><p>One</p></div></div>]]
assert_eq(Html.select(sample, "#title"), "Hello", "select #id")
assert_true((Html.select(sample, ".chapter-content") or ""):find("<p>One</p>", 1, true), "select .class")
assert_eq(Html.select(sample, "h1"), "Hello", "select tag")
assert_eq(Html.select([[<div id="chapter-content">Body</div>]], "#chapter-content"), "Body", "select hyphen id")
assert_eq(Http.sameOrigin("https://a.com/x", "https://a.com/y"), true, "same origin")
assert_eq(Http.sameOrigin("https://a.com/x", "https://b.com/x"), false, "cross origin")
assert_eq(Http.resolveUrl("https://a.com/dir/page", "/z"), "https://a.com/z", "resolve absolute path")

assert_eq(Html.escape("<a>"), "&lt;a&gt;", "escape")

local wrapped = Html.wrapDocument("T", "<p>x</p>")
assert_true(wrapped:find('charset="utf-8"', 1, true), "wrap charset")

Source.register({ id = "docln", name = "DocLN" })
Source.register({ id = "rss", name = "RSS" })
assert_eq(Source.get("docln").name, "DocLN", "source get")
assert_eq(#Source.list(), 2, "source list")

assert_eq(RateLimit.hostFromUrl("https://docln.net/truyen/1"), "docln.net", "host parse")
RateLimit.reset()
RateLimit.wait("example", 0)

local parsed = Http.parseSetCookie("sid=abc; Path=/; HttpOnly")
assert_eq(parsed.sid, "abc", "parse set-cookie")
assert_eq(Http.cookieHeader({ b = "2", a = "1" }), "a=1; b=2", "cookie header sorted")

Settings.bind(nil)
Settings.load()
assert_eq(Settings.sangtacvietEnabled(), false, "stv default off")
Settings.setCookie("wattpad", "secret")
assert_eq(Settings.cookie("wattpad"), "secret", "cookie store")
Settings.setCookie("wattpad", "")
assert_eq(Settings.cookie("wattpad"), "", "cookie clear")

local main_file = assert(io.open(plugin_root .. "/main.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert_true(main_source:find('sorting_hint = "tools"', 1, true) ~= nil, "plugin is top-level in Tools")

if failures > 0 then
    io.stderr:write(failures .. " failure(s)\n")
    os.exit(1)
end

print("ok")
