-- Ebook detail screen: format rows, download -> open prompt, saved copies opening
-- directly, failure messages, and the dispatch from Novels.showSeries.
local names = { "gettext", "ui/uimanager", "ui/widget/infomessage", "ui/widget/textviewer", "ui/trapper",
    "ui/network/manager", "apps/reader/readerui", "booxbook.network", "booxbook.async", "booxbook.fault",
    "booxbook.ui.catalog", "booxbook.ui.series", "booxbook.ui.ebook-detail", "booxbook.ui.novels" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

local menu, confirmed, opened, cleared, viewer
local notes, closed, shown, queue = {}, {}, {}, {}
local online = true
package.loaded.gettext = function(text) return text end
package.loaded["ui/uimanager"] = {
    show = function(_, widget) shown[#shown + 1] = widget end,
    close = function(_, widget) closed[#closed + 1] = widget end,
    nextTick = function(_, callback) callback() end,
}
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/widget/textviewer"] = { new = function(_, value) viewer = value; return value end }
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end, info = function() end, clear = function() end }
package.loaded["ui/network/manager"] = { isOnline = function() return online end,
    isConnected = function() return online end, beforeWifiAction = function(_, fn) fn() end }
package.loaded["apps/reader/readerui"] = { showReader = function(_, path) opened = path end }
package.loaded["booxbook.network"] = { whenOnline = function(callback) if online then callback() end end }
-- Async.run: run the work to completion at once, as the test double of the coroutine runner.
package.loaded["booxbook.async"] = { run = function(work, done)
    local ok, a, b = pcall(work)
    done(ok, a, b)
end }
package.loaded["booxbook.fault"] = { notify = function(text) notes[#notes + 1] = text end }
package.loaded["booxbook.ui.catalog"] = {
    show = function(opts) menu = opts end,
    confirm = function(text, on_ok, opts) confirmed = { text = text, ok = on_ok, opts = opts } end,
    clearStack = function() cleared = true end,
    promptText = function() end, push = function() end, pop = function() end,
}
package.loaded["booxbook.ui.ebook-detail"] = nil

local Download = require("booxbook.ebook-download")
local original = { Download.fetch, Download.existing }
local Detail = require("booxbook.ui.ebook-detail")

local series = { id = "ba-han_27460", source_id = "dtvebook", title = "Bá Hạn", author = "Tác giả A",
    status = "Hoàn Thành", tags = { "Kiếm hiệp", "Cổ đại" }, description = "Mô tả.",
    files = { { format = "EPUB", url = "https://docs.google.com/uc?export=download&id=E1234567890" },
        { format = "PDF", url = "https://docs.google.com/uc?export=download&id=P1234567890" } } }
local adapter = { id = "dtvebook", kind = "ebook" }
local on_disk, fetched = {}, {}
Download.existing = function(_, file) return on_disk[file.format] end
Download.fetch = function(_, file)
    fetched[#fetched + 1] = file.format
    if file.format == "PDF" then return nil, "Google Drive đang giới hạn lượt tải; thử lại sau." end
    return "/books/dtvebook/Bá Hạn [27460].epub", "epub"
end

-- ---- format rows ---------------------------------------------------------
adapter.getSeries = function(ref) assert(ref == "/ba-han_27460.html"); return series end
Detail.show("/ba-han_27460.html", adapter)
assert(menu and menu.title == "Bá Hạn", "the detail screen opens with the book title")
assert(#menu.items == 3, "a blurb row and one row per format")
assert(menu.items[1].text == "Giới thiệu" and menu.items[1].mandatory == "Tác giả A")
assert(menu.items[2].text == "Tải EPUB" and menu.items[3].text == "Tải PDF")
assert(menu.items[2].mandatory == nil, "nothing is marked as saved yet")
assert(#closed == #shown and #shown >= 1, "the progress box is closed after the lookup")

menu.items[1].callback()
assert(viewer.title == "Bá Hạn" and viewer.text:find("Tác giả: Tác giả A", 1, true)
    and viewer.text:find("Tình trạng: Hoàn Thành", 1, true)
    and viewer.text:find("Thể loại: Kiếm hiệp, Cổ đại", 1, true)
    and viewer.text:find("Mô tả.", 1, true), "the blurb shows author, status, genres and description")

-- ---- download, then offer to open ----------------------------------------
menu.items[2].callback()
assert(#fetched == 1 and fetched[1] == "EPUB")
assert(confirmed and confirmed.text:find("Bá Hạn [27460].epub", 1, true), "the prompt names the saved file")
assert(not confirmed.text:find("/books/", 1, true), "only the file name is shown")
assert(opened == nil, "nothing opens before the reader agrees")
confirmed.ok()
assert(opened == "/books/dtvebook/Bá Hạn [27460].epub" and cleared, "agreeing opens the book in the reader")

-- ---- failure -------------------------------------------------------------
notes, confirmed = {}, nil
menu.items[3].callback()
assert(#notes == 1 and notes[1]:find("giới hạn lượt tải", 1, true), "a failed download is reported")
assert(confirmed == nil)

-- ---- an already saved format opens straight away ---------------------------
on_disk.EPUB = "/books/dtvebook/saved.epub"
Detail.showFiles(series)
assert(menu.items[2].text == "Mở EPUB" and menu.items[2].mandatory == "đã tải")
opened, fetched = nil, {}
menu.items[2].callback()
assert(opened == "/books/dtvebook/saved.epub" and #fetched == 0, "no second download")

-- ---- lookup failure and offline ------------------------------------------
notes = {}
adapter.getSeries = function() return nil, "Sách này không có link tải trên DTV eBook." end
menu = nil
Detail.show("/x_1.html", adapter)
assert(menu == nil and notes[1] == "Sách này không có link tải trên DTV eBook.")
notes = {}
adapter.getSeries = function() error("boom") end
Detail.show("/x_1.html", adapter)
assert(#notes == 1 and menu == nil, "an error inside the lookup reaches the reader as a message")
online, notes = false, {}
adapter.getSeries = function() error("must not be called while offline") end
Detail.show("/x_1.html", adapter)
assert(#notes == 0 and menu == nil, "offline: the network prompt handles it and no request is made")
online = true

-- ---- Novels.showSeries sends ebook sources here -----------------------------
local dispatched
package.loaded["booxbook.ui.ebook-detail"] = { show = function(ref, source) dispatched = { ref, source } end }
package.loaded["booxbook.ui.novels"] = nil
local Novels = dofile("booxbook.koplugin/booxbook/ui/novels.lua")
Novels.showSeries("/ba-han_27460.html", adapter)
assert(dispatched and dispatched[1] == "/ba-han_27460.html" and dispatched[2] == adapter,
    "an ebook adapter gets the file picker, not the chapter list")

Download.fetch, Download.existing = original[1], original[2]
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Ebook detail rows, download-and-open, saved copies, failures and novel dispatch passed")
