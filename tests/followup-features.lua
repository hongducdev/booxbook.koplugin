package.loaded["libs/libkoreader-lfs"] = package.loaded["libs/libkoreader-lfs"]
    or { symlinkattributes = function() return nil end, attributes = function() return nil end }
package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end
package.loaded["json"] = package.loaded["json"] or { decode = function() return nil end, encode = function() return "" end }
local GDrive = require("booxbook.gdrive")
assert(GDrive.validClientId("abc.apps.googleusercontent.com") == true, "google client id accepted")
assert(GDrive.validClientId("not-a-uuid") == false, "random client id rejected")
assert(GDrive.validClientId("") == false, "empty client id rejected")
assert(GDrive.allowedName("book.epub") == true, "epub allowed on drive")
assert(GDrive.allowedName("movie.mp4") == false, "video rejected on drive")
local parsed = assert(GDrive.parseList({ files = {
    { id = "1", name = "B.epub", mimeType = "application/epub" },
    { id = "2", name = "A.pdf", mimeType = "application/pdf" },
    { id = "3", name = "clip.mp4", mimeType = "video/mp4" },
    { id = "4", name = "folder", mimeType = "application/vnd.google-apps.folder" },
} }))
assert(#parsed.items == 3 and parsed.items[1].folder and parsed.items[1].name == "folder"
    and parsed.items[2].name == "A.pdf", "drive list keeps folders first, filters and sorts")
assert(GDrive.parseList({}) == nil, "drive list rejects invalid payload")

local Backup = require("booxbook.backup")
package.loaded["json"] = { encode = function(t) return "ENCODED:" .. tostring(t.app) end,
    decode = function(s)
        assert(s == "BODY", "backup parses given body")
        return { app = "booxbook", settings = { novel_epub = true, evil = 1 } }
    end }
local exported = assert(Backup.export(function(key) return key == "novel_epub" end))
assert(exported:find("booxbook", 1, true), "backup export encodes app marker")
local restored = assert(Backup.parse("BODY"))
assert(restored.novel_epub == true and restored.evil == nil, "backup keeps allowlisted keys only")
assert(Backup.parse("nope") == nil, "backup rejects invalid payload")
assert(Backup.filename():match("^booxbook%-backup%-%d+"), "backup filename is timestamped")
package.loaded["json"] = nil

local Opds = require("booxbook.opds")
local xml = Opds.catalog({ { name = "a.epub" }, { name = "b.pdf" } }, "/opds")
assert(xml:find("<feed", 1, true) and xml:find("a.epub", 1, true), "opds catalog lists files")
assert(Opds.normalizeQueueUrl("  https://example.com/a  ") == "https://example.com/a", "queue url trimmed")
assert(Opds.normalizeQueueUrl("ftp://example.com") == nil, "queue rejects non-http")
assert(Opds.normalizeQueueUrl("") == nil, "queue rejects empty")

local Digest = require("booxbook.digest")
local picked = Digest.pick({ { path = "/x/a.html", title = "A" }, { path = "/x/b.pdf" } }, 10)
assert(#picked == 1 and picked[1].title == "A", "digest keeps html only")
assert(Digest.filename():match("^digest%-%d+%.epub$"), "digest filename is dated")

local Update = require("booxbook.update")
assert(Update.shouldCheck(0, 100) == true, "never checked means check now")
assert(Update.shouldCheck(100, 100 + Update.CHECK_INTERVAL) == true, "interval elapsed means check")
assert(Update.shouldCheck(100, 101) == false, "fresh check means skip")

local Upload = require("booxbook.wifi-upload")
local opds = assert(Upload.headers("GET /opds HTTP/1.1\r\nHost: 1:2\r\n\r\n", "1:2", "000000"))
assert(opds.opds == true, "GET /opds routes without token")
local queued = assert(Upload.headers(
    "POST /queue HTTP/1.1\r\nHost: 1:2\r\nX-BooxBook-Token: 000000\r\nContent-Length: 5\r\n\r\n", "1:2", "000000"))
assert(queued.queue == true and queued.remaining == 5, "POST /queue requires token")
local denied = select(2, Upload.headers(
    "POST /queue HTTP/1.1\r\nHost: 1:2\r\nX-BooxBook-Token: 111111\r\nContent-Length: 5\r\n\r\n", "1:2", "000000"))
assert(denied == 401, "queue rejects wrong token")

local QQ = require("booxbook.sources.truyenqq")
assert(QQ.id == "truyenqq" and QQ.kind == "comic", "second comic source registered")
local ref = assert(QQ.parseSeriesRef("https://truyenqqko.com/truyen-tranh/yeu-than-ky-746"))
assert(ref.id == "yeu-than-ky-746", "truyenqq parses series slug")
assert(QQ.parseSeriesRef("https://truyentuoitho.com/manga/x/") == nil, "truyenqq rejects other host")
assert(QQ.parseSeriesRef("https://truyenqqko.com/truyen-tranh/a-chap-1") == nil,
    "truyenqq series ref rejects chapter urls")

print("Follow-up features checks passed")
