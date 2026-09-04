local Http = require("booxbook.http")
local RateLimit = require("booxbook.rate_limit")
local Settings = require("booxbook.store.settings")
local transport = require("socket.http")
local original_request, original_wait = transport.request, RateLimit.wait
local requests, waits = {}, {}
transport.request = function(request)
    requests[#requests + 1] = request
    if request.url:find("redirect", 1, true) then
        return 1, 302, { location = "https://other.example/article" }, "Found"
    end
    if request.url:find("limited", 1, true) then return 1, 429, {}, "Limited" end
    return 1, 200, {}, "OK"
end
RateLimit.wait = function(host, delay) waits[#waits + 1] = { host = host, delay = delay } end
assert(Http.USER_AGENT:find("Windows NT", 1, true), "RSS needs desktop UA instead of Android")
local opts = { headers = { ["USER-AGENT"] = "Explicit Agent", Cookie = "session=kept; device_env=1" } }
assert(Http.get("https://vnexpress.net/rss/thoi-su.rss", opts))
local headers = requests[#requests].headers
assert(headers["user-agent"] == "Explicit Agent" and headers["USER-AGENT"] == nil,
    "case-insensitive UA override, no duplicate headers")
assert(headers.cookie:find("device_env=4", 1, true) and headers.cookie:find("device_env_real=4", 1, true))
assert(headers.cookie:find("session=kept", 1, true), "preserve other explicit cookies")
assert(opts.headers.Cookie == "session=kept; device_env=1", "caller headers unmodified")
for _, url in ipairs({ "https://vnexpress.net/article", "https://timkiem.vnexpress.net/search" }) do
    assert(Http.get(url))
    assert(requests[#requests].headers["user-agent"] == Http.USER_AGENT)
    assert(requests[#requests].headers.cookie:find("device_env=4", 1, true))
end
for _, url in ipairs({ "https://example.com/a", "https://vnexpress.net.evil.example/a", "https://fakevnexpress.net/a" }) do
    assert(Http.get(url))
    assert(requests[#requests].headers.cookie == nil, "presentation cookies scoped to VnExpress")
end
local before = #waits
assert(Http.get("https://vnexpress.net/redirect"))
assert(requests[#requests].headers.cookie == nil, "generated cookies never leak on cross-host redirects")
assert(#waits == before + 2 and waits[#waits].host == "other.example", "pace redirect hops too")
local old_delay = Settings.get("delay_ms")
Settings.set("delay_ms", 2300)
assert(Http.get("https://example.com/a"))
assert(waits[#waits].delay == 2300, "honor configured request spacing")
Settings.set("delay_ms", old_delay)
before = #requests
local ok, code = Http.get("https://example.com/limited")
assert(not ok and code == 429 and #requests == before + 1, "do not auto-retry HTTP 429")
local sensitive = { Cookie = "session=private", Authorization = "Bearer private" }
assert(Http.get("https://vnexpress.net/redirect", { headers = sensitive }))
assert(requests[#requests].headers.cookie == nil and requests[#requests].headers.authorization == nil,
    "explicit credentials also stripped on cross-host redirect")
assert(sensitive.Cookie == "session=private", "redirect handling preserves caller options")
local attempts = 0
transport.request = function()
    attempts = attempts + 1
    if attempts == 1 then return nil, "timeout" end
    return 1, 200, {}, "OK"
end
before = #waits
assert(Http.get("https://example.com/retry"))
assert(attempts == 2 and #waits == before + 2, "timeout retry is paced")
transport.request, RateLimit.wait = original_request, original_wait
print("Desktop UA, scoped cookies and pacing checks passed")
