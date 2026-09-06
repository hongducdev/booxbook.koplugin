local Epub = require("booxbook.epub")
local previous = package.loaded["ffi/archiver"]
local old_rename, old_remove, old_open = os.rename, os.remove, io.open
local entries, order, compression, removed, renamed, fail, dest_removed = {}, {}, nil, {}, false, nil, false
local verify_count = nil
local writer = {
    open = function()
        entries, order = {}, {}
        return true
    end,
    setZipCompression = function(_, method) compression = method; return true end,
    addFileFromMemory = function(self, name, content)
        if fail == name then self.err = "disk full"; return nil end
        entries[name] = content
        order[#order + 1] = { name, compression }
        return true
    end,
    close = function(self)
        self.err = nil -- Native writer clears err on close, too.
        if fail == "close" then error("close failed") end
    end,
}
package.loaded["ffi/archiver"] = {
    Writer = { new = function() return writer end },
    Reader = {
        new = function()
            return {
                open = function()
                    if fail == "verify" then return nil end
                    return true
                end,
                iterate = function()
                    local n, i = verify_count or #order, 0
                    return function()
                        i = i + 1
                        if i <= n then return { i } end
                    end
                end,
                close = function() end,
            }
        end,
    },
}
os.rename = function(from, to)
    assert(from == "book.epub.tmp" and to == "book.epub")
    if fail == "rename" then return nil, "rename failed" end
    if fail == "exists-once" then
        fail = nil
        return nil, "File exists"
    end
    renamed = true
    return true
end
os.remove = function(path)
    if path == "book.epub" then
        dest_removed = true
        return true
    end
    removed[path] = true
    return true
end
local book = { title = "Tiếng Việt & sách", chapters = {
    { title = "Một", html = "<p>Tiếng Việt<br>mới</p>" },
    { title = "Hai", html = "<p>Hai</p>" },
} }
assert(Epub.write("book.epub", book))
assert(renamed and order[1][1] == "mimetype" and order[1][2] == "store")
assert(entries.mimetype == "application/epub+zip")
assert(entries["OEBPS/chapter-001.xhtml"]:find("Tiếng Việt<br/>", 1, true))
assert(entries["OEBPS/toc.ncx"]:find("chapter-002.xhtml", 1, true))
local uid = entries["OEBPS/content.opf"]:match('<dc:identifier id="BookId">(.-)</dc:identifier>')
assert(entries["OEBPS/toc.ncx"]:find('content="' .. uid .. '"', 1, true))
for _, failure in ipairs({ "OEBPS/chapter-002.xhtml", "close", "rename" }) do
    fail, renamed, writer.err, dest_removed = failure, false, nil, false
    local ok, err = Epub.write("book.epub", book)
    assert(not ok and err and not renamed and removed["book.epub.tmp"])
    assert(not dest_removed, "failed export must not delete the previous EPUB")
end
fail, writer.err = "verify", nil
renamed, dest_removed = false, false
local verified, verify_err = Epub.write("book.epub", book)
assert(not verified and tostring(verify_err):find("verify", 1, true) and not renamed)
fail = nil
verify_count = 1
renamed = false
local incomplete, incomplete_err = Epub.write("book.epub", book)
assert(not incomplete and tostring(incomplete_err):find("incomplete", 1, true) and not renamed)
verify_count = nil
fail = "exists-once"
renamed, dest_removed = false, false
local tmp = assert(old_open("book.epub.tmp", "wb"))
assert(tmp:write("tmp")); tmp:close()
assert(Epub.write("book.epub", book))
assert(dest_removed and renamed, "existing EPUB is replaced after a FAT rename failure")
old_remove("book.epub.tmp")
fail, writer.err = nil, nil
assert(not Epub.write("book.epub", { chapters = {} }))

-- Exercise real chapter-file reads, including malformed/missing HTML.
local chapter_path = os.tmpname()
local file = assert(io.open(chapter_path, "wb"))
assert(file:write(require("booxbook.html").wrapDocument("Chapter", "<h1>Title</h1><p>Text</p>")))
assert(file:close())
book.chapters = { { title = "Chapter", path = chapter_path } }
assert(Epub.write("book.epub", book))
local xhtml = entries["OEBPS/chapter-001.xhtml"]
local _, body_count = xhtml:gsub("<body>", "")
assert(body_count == 1 and xhtml:find("<h1>Title</h1>", 1, true))
file = assert(io.open(chapter_path, "wb")); file:write("broken"); file:close()
assert(not Epub.write("book.epub", book))
old_remove(chapter_path)
assert(not Epub.write("book.epub", book))
writer.open = function() return nil end
assert(not Epub.write("book.epub", book))
writer.open = function() error("archiver unavailable") end
assert(not Epub.write("book.epub", book))
os.rename, os.remove = old_rename, old_remove
package.loaded["ffi/archiver"] = previous
print("EPUB contents, TOC, file reads and failure preservation checks passed")
