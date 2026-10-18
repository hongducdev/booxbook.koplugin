-- Ebook file download: content sniffing, file naming, Drive's virus-scan page,
-- failure mapping and the atomic .part -> final rename.
package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path
local saved_gettext = package.loaded.gettext
package.loaded.gettext = function(s) return s end
package.loaded["booxbook.ebook-download"] = nil
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local old_download, old_dir, old_ensure = Http.downloadToFile, Settings.downloadDir, Settings.ensureDir
local old_open, old_remove, old_rename = io.open, os.remove, os.rename

-- Virtual @ebook/ paths map onto real temporary files, as in tests/comic-download.lua.
local paths = {}
local function mapped(path)
    if type(path) ~= "string" or path:sub(1, 7) ~= "@ebook/" then return path end
    if not paths[path] then paths[path] = os.tmpname(); old_remove(paths[path]) end
    return paths[path]
end
io.open = function(path, mode) return old_open(mapped(path), mode) end
os.remove = function(path) return old_remove(mapped(path)) end
os.rename = function(a, b) return old_rename(mapped(a), mapped(b)) end
Settings.downloadDir = function() return "@ebook" end
Settings.ensureDir = function() return true end

local function read(path)
    local handle = old_open(mapped(path), "rb")
    if not handle then return nil end
    local data = handle:read("*a")
    handle:close()
    return data
end

local Download = require("booxbook.ebook-download")

-- ---- sniff ---------------------------------------------------------------
assert(Download.sniff("PK\3\4rest") == "epub")
assert(Download.sniff("%PDF-1.4\n") == "pdf")
assert(Download.sniff(string.rep("x", 60) .. "BOOKMOBI" .. "tail") == "mobi")
assert(Download.sniff("<!DOCTYPE html><html>") == "html")
assert(Download.sniff("  \n<HTML><head>") == "html")
assert(Download.sniff("<?xml version='1.0'?>") == nil, "an XML file is not mistaken for a Drive page")
assert(Download.sniff("random bytes") == nil and Download.sniff("") == nil and Download.sniff(nil) == nil)

-- ---- naming --------------------------------------------------------------
local book = { id = "so-tay-trader_27609", source_id = "dtvebook", title = 'Sổ: Tay / "Trader"?' }
assert(Download.stem(book) == "Sổ Tay Trader [27609]", Download.stem(book))
assert(Download.stem{ id = "x_5", title = "  ...  " } == "x_5 [5]", "an empty title falls back to the id")
local long = Download.stem{ id = "a_9", title = string.rep("Đắc Nhân Tâm ", 30) }
assert(#long <= 100 + #" [9]", "a long title is cut")
local rebuilt = {}
for sequence in long:gmatch("[\1-\127\194-\244][\128-\191]*") do rebuilt[#rebuilt + 1] = sequence end
assert(table.concat(rebuilt) == long, "the cut never splits a UTF-8 character")
assert(Download.dir(book) == "@ebook/books/dtvebook")

-- ---- transport stub ------------------------------------------------------
local script, urls, allow_ok = {}, {}, true
Http.downloadToFile = function(url, dest, opts)
    urls[#urls + 1] = url
    assert(dest:match("%.part$"), "the transfer goes to a .part file")
    assert(opts.max_body == Download.MAX_BYTES and type(opts.allow_url) == "function")
    assert(opts.referer == nil, "Drive rejects the book site as referer on the confirm request")
    allow_ok = allow_ok and opts.allow_url(url)
    local step = table.remove(script, 1)
    assert(step, "unexpected extra request: " .. url)
    if step.fail then return false, step.fail end
    local handle = assert(io.open(dest, "wb"))
    handle:write(step.body)
    handle:close()
    return true, 200
end
local function play(...) script, urls, allow_ok = { ... }, {}, true end
local function part_left(file)
    return read("@ebook/books/dtvebook/" .. Download.stem(book) .. "." .. file.format:lower() .. ".part") ~= nil
end

local EPUB = { format = "EPUB", url = "https://docs.google.com/uc?export=download&id=EPUBID123456" }
local PDF = { format = "PDF", url = "https://docs.google.com/uc?export=download&id=PDFID1234567" }
local AZW3 = { format = "AZW3", url = "https://docs.google.com/uc?export=download&id=AZWID1234567" }
local MOBI = { format = "MOBI", url = "https://docs.google.com/uc?export=download&id=MOBIID123456" }
local function scan(id)
    return '<!DOCTYPE html><html><head><title>Google Drive - Virus scan warning</title></head><body>'
        .. '<form id="download-form" action="https://drive.usercontent.google.com/download" method="get">'
        .. '<input type="submit" id="uc-download-link" value="Download anyway"/>'
        .. '<input type="hidden" name="id" value="' .. id .. '"><input type="hidden" name="export" value="download">'
        .. '<input type="hidden" name="confirm" value="t"><input type="hidden" name="uuid" value="48be-2018"></form></body></html>'
end

-- ---- direct download -----------------------------------------------------
assert(Download.existing(book, EPUB) == nil)
play{ body = "PK\3\4" .. string.rep("e", 100) }
local path, ext = Download.fetch(book, EPUB)
assert(path == "@ebook/books/dtvebook/Sổ Tay Trader [27609].epub" and ext == "epub", tostring(path or ext))
assert(read(path) == "PK\3\4" .. string.rep("e", 100), "the file is saved whole")
assert(not part_left(EPUB), "the .part file is renamed away")
assert(#urls == 1 and urls[1] == EPUB.url and allow_ok)
assert(Download.existing(book, EPUB) == path, "a saved format is found again")
assert(Download.existing(book, PDF) == nil, "another format is not")
play{ body = "PK\3\4new" }
assert(Download.fetch(book, EPUB) == path and read(path) == "PK\3\4new", "a re-download replaces the old copy")

-- ---- Drive virus-scan page -----------------------------------------------
play({ body = scan("PDFID1234567") }, { body = "%PDF-1.4 big" })
path, ext = Download.fetch(book, PDF)
assert(ext == "pdf" and path:match("%.pdf$") and read(path) == "%PDF-1.4 big")
assert(#urls == 2 and urls[2] == "https://drive.usercontent.google.com/download?id=PDFID1234567"
    .. "&export=download&confirm=t&uuid=48be-2018", urls[2])
assert(allow_ok, "every hop is a Google host")
assert(not part_left(PDF), "the scan page leaves no .part file behind")

-- ---- MOBI-family containers keep the requested extension ------------------
local PALM = string.rep("p", 60) .. "BOOKMOBI" .. string.rep("m", 40)
play{ body = PALM }
local azw_path, azw_ext = Download.fetch(book, AZW3)
assert(azw_ext == "azw" and azw_path:match("%.azw$"), "KOReader opens .azw, not .azw3")
assert(Download.existing(book, AZW3) == azw_path, "a saved AZW3 is found again under its .azw name")
play{ body = PALM }
assert(select(2, Download.fetch(book, MOBI)) == "mobi")

-- ---- refusals ------------------------------------------------------------
play{ body = "<html><body>Sorry, quota. Too many users have viewed or downloaded this file recently.</body></html>" }
local none, why = Download.fetch(book, EPUB)
assert(none == nil and why:find("hạn mức", 1, true), why)
assert(not part_left(EPUB))
play{ body = "<html><body>Sign in</body></html>" }
none, why = Download.fetch(book, EPUB)
assert(none == nil and why:find("không trả về file", 1, true), why)
play{ body = scan("X"):gsub("drive.usercontent.google.com", "evil.test") }
none, why = Download.fetch(book, EPUB)
assert(none == nil and why:find("không trả về file", 1, true) and #urls == 1, "a foreign form action is never followed")
play{ body = "random bytes, not a book" }
none, why = Download.fetch(book, EPUB)
assert(none == nil and why:find("không đúng định dạng", 1, true), why)
assert(not part_left(EPUB), "a rejected file is removed")
play({ body = scan("A") }, { body = scan("B") }, { body = scan("C") })
none, why = Download.fetch(book, EPUB)
assert(none == nil and why:find("liên tục", 1, true) and #urls == 3, "confirmation pages cannot loop forever")
play()
assert(not Download.fetch(book, { format = "EPUB", url = "https://evil.test/a.epub" }))
assert(not Download.fetch(book, { format = "EPUB", url = "http://docs.google.com/uc?id=1" }))
assert(not Download.fetch(nil, EPUB) and not Download.fetch(book, nil) and #urls == 0, "bad input costs no request")

-- ---- transport failures --------------------------------------------------
for _, case in ipairs({ { 404, "không còn tồn tại" }, { 403, "giới hạn lượt tải" }, { 429, "giới hạn lượt tải" },
        { "body too large", "lớn hơn" }, { "operation-timeout", "Hết thời gian" }, { 500, "500" } }) do
    play{ fail = case[1] }
    none, why = Download.fetch(book, EPUB)
    assert(none == nil and why:find(case[2], 1, true), tostring(case[1]) .. ": " .. tostring(why))
end

-- ---- confirmUrl in isolation ---------------------------------------------
assert(Download.confirmUrl(scan("Z")):find("id=Z&export=download", 1, true))
assert(not Download.confirmUrl(nil) and not Download.confirmUrl("<html></html>"))
assert(not Download.confirmUrl(scan("Z"):gsub('name="id"', 'name="idx"')), "a form without an id is refused")

Http.downloadToFile, Settings.downloadDir, Settings.ensureDir = old_download, old_dir, old_ensure
io.open, os.remove, os.rename = old_open, old_remove, old_rename
for _, real in pairs(paths) do old_remove(real) end
package.loaded.gettext = saved_gettext
print("Ebook download sniffing, naming, Drive scan page, refusals and failures passed")
