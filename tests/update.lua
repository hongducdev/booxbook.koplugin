package.loaded["booxbook.update"] = nil
local Http = require("booxbook.http")
local Update = require("booxbook.update")

assert(Update.compare("0.0.2", "0.0.1") == 1, "newer remote compares greater")
assert(Update.compare("0.0.1", "v0.0.1") == 0, "v prefix is ignored in compare")
assert(Update.compare("1.2", "1.2.0") == 0, "missing dotted part is zero")
assert(Update.compare("0.0.1", "0.0.2") == -1, "older remote compares less")
assert(Update.needsUpdate("0.0.2", "0.0.1") == true, "needs update when remote is newer")
assert(Update.needsUpdate("0.0.1", "0.0.1") == false, "same version does not need update")
assert(Update.needsUpdate("0.0.1", "0.0.2") == false, "older remote does not need update")

assert(Update.safeRelPath("booxbook/update.lua") == "booxbook/update.lua", "relative plugin path is allowed")
assert(Update.safeRelPath("foo/../bar") == nil, "parent segments are rejected")
assert(Update.safeRelPath("/etc/passwd") == nil, "absolute unix path is rejected")
assert(Update.safeRelPath("C:/Windows/system.ini") == nil, "absolute windows path is rejected")
assert(Update.safeRelPath("booxbook.koplugin/../../secrets") == nil, "zip-slip parent path is rejected")

assert(Update.zipHasPluginRoot({
    "booxbook.koplugin/main.lua",
    "booxbook.koplugin/_meta.lua",
}) == true, "release zip with plugin folder strips")
assert(Update.zipHasPluginRoot({
    "main.lua",
    "booxbook/update.lua",
}) == false, "flat plugin zip does not strip")

local parsed, parse_err = Update.parseRelease({
    tag_name = "v0.0.2",
    assets = {
        { name = "source.zip", browser_download_url = "https://example.com/source.zip" },
        {
            name = "booxbook.koplugin.zip",
            browser_download_url = "https://github.com/hongducdev/booxbook.koplugin/releases/download/v0.0.2/booxbook.koplugin.zip",
        },
    },
})
assert(parse_err == nil, "parseRelease accepts a decoded table")
assert(parsed.version == "0.0.2", "parseRelease strips leading v")
assert(parsed.zip_url:find("booxbook.koplugin.zip", 1, true), "parseRelease picks the plugin zip")

local missing, missing_err = Update.parseRelease({
    tag_name = "v0.0.2",
    assets = { { name = "other.zip", browser_download_url = "https://example.com/other.zip" } },
})
assert(missing == nil and missing_err == "no_asset", "missing plugin zip is no_asset")
assert(select(2, Update.parseRelease({ assets = {} })) == "parse", "missing tag_name is parse")
assert(Update.allowedDownloadUrl("https://github.com/hongducdev/booxbook.koplugin/releases/download/v0.0.2/booxbook.koplugin.zip"), "github.com asset host is allowed")
assert(Update.allowedDownloadUrl("https://objects.githubusercontent.com/github-production-release-asset/1") == true, "GitHub CDN host is allowed")
assert(not Update.allowedDownloadUrl("https://evil.example/booxbook.koplugin.zip"), "off-host zip URL is rejected")
local hijack = Update.parseRelease({
    tag_name = "v0.0.2",
    assets = {{
        name = "booxbook.koplugin.zip",
        browser_download_url = "https://evil.example/booxbook.koplugin.zip",
    }},
})
assert(hijack == nil, "parseRelease ignores plugin zip on a foreign host")

Update._jsonDecode = function(body)
    assert(body == '{"tag_name":"v0.0.3","assets":[]}', "string parse uses injected decoder")
    return { tag_name = "v0.0.3", assets = {} }
end
assert(select(2, Update.parseRelease('{"tag_name":"v0.0.3","assets":[]}')) == "no_asset", "JSON string without zip is no_asset")
Update._jsonDecode = nil

assert(Update.currentVersion() == "0.0.8", "installed version is 0.0.8")
assert(Http.MAX_BODY == 2 * 1024 * 1024, "article HTTP cap stays 2 MiB")

local original_get = Http.get
Http.get = function(url, opts)
    assert(url == Update.API_URL, "fetchLatest hits GitHub latest release")
    assert(opts.delay_ms == 0, "GitHub check is not rate-delayed")
    assert(opts.headers.Accept == "application/vnd.github+json", "GitHub API accept header")
    return true, 200, {
        tag_name = "v0.0.2",
        assets = {{
            name = "booxbook.koplugin.zip",
            browser_download_url = "https://github.com/hongducdev/booxbook.koplugin/releases/download/v0.0.2/booxbook.koplugin.zip",
        }},
    }
end
local latest = assert(Update.fetchLatest())
assert(latest.version == "0.0.2", "fetchLatest parses mocked GitHub JSON")
Http.get = function()
    return false, 403, ""
end
local _, fetch_err, fetch_code = Update.fetchLatest()
assert(fetch_err == "http" and fetch_code == 403, "GitHub HTTP errors surface the status")
Http.get = original_get

local original_request = Http.request
local seen
Http.request = function(opts)
    seen = opts
    return true, 200, "", {}
end
local caller_opts = { delay_ms = 0 }
local ok = Http.downloadToFile("https://example.com/a.zip", "tmp-update.zip", caller_opts)
assert(ok == true, "downloadToFile reports request success")
assert(seen.dest_file == "tmp-update.zip", "downloadToFile streams to the given path")
assert(seen.max_body == 30 * 1024 * 1024, "zip download allows 30 MiB")
assert(seen.timeout == 60, "zip download uses a longer timeout")
assert(caller_opts.dest_file == nil, "downloadToFile does not mutate caller opts")
Http.request = original_request
os.remove("tmp-update.zip")

local extracted = {}
package.loaded["ffi/archiver"] = {
    Reader = {
        new = function()
            return {
                open = function() return true end,
                close = function() end,
                iterate = function()
                    local i = 0
                    local entries = {
                        { path = "booxbook.koplugin/main.lua", mode = "file", size = 8 },
                        { path = "../evil.lua", mode = "file", size = 8 },
                        { path = "booxbook.koplugin/booxbook/update.lua", mode = "file", size = 8 },
                        { path = "booxbook.koplugin/link", mode = "symlink", size = 8 },
                    }
                    return function()
                        i = i + 1
                        return entries[i]
                    end
                end,
                extractToPath = function(_, src, dest)
                    extracted[#extracted + 1] = dest
                    return true
                end,
            }
        end,
    },
}
assert(Update.unpackZip("unused.zip", "staging", false) == true, "unpackZip extracts a wrapped plugin zip")
local joined = table.concat(extracted, "\n")
assert(joined:find("staging/booxbook.koplugin/main.lua", 1, true), "wrapped zip keeps plugin root")
assert(not joined:find("evil", 1, true), "zip-slip entries are not extracted")
assert(not joined:find("link", 1, true), "non-file archive entries are skipped")
package.loaded["ffi/archiver"] = nil

print("Update version and GitHub release checks passed")
