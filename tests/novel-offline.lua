-- Offline chapter list from index.json (no network).
local names = { "gettext", "ui/widget/infomessage", "ui/uimanager", "booxbook.ui.catalog" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
package.loaded.gettext = function(text) return text end
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/uimanager"] = { show = function() end }
local shown
package.loaded["booxbook.ui.catalog"] = {
    show = function(value) shown = value end,
    promptText = function() end,
    confirm = function() end,
}
package.loaded["booxbook.ui.series"] = nil

local Download = require("booxbook.novel-download")
local Settings = require("booxbook.store.settings")
local SeriesUI = require("booxbook.ui.series")

local chapters = { { title = "One", index = 1 }, { title = "Two", index = 2 } }
SeriesUI.show({ title = "Book", chapters = chapters, volumes = { { title = "V1", chapters = chapters } } }, {
    on_range = function() end,
    on_download_all = function() end,
    on_package = function() end,
    on_offline = function() end,
})
assert(shown.left_icon == "appbar.menu" and type(shown.on_left_icon) == "function")
assert(shown.items[1].text == "Chương đã tải (offline)")
assert(shown.items[2].text == "V1")
shown.on_left_icon()
assert(shown.title == "Tải chương")
assert(shown.items[1].text == "Tải khoảng chương")
assert(shown.items[2].text == "Tải toàn bộ chương")
assert(shown.items[3].text == "Tạo EPUB từ chương đã tải")
SeriesUI.show({ title = "Comic", chapters = chapters }, {
    unit = "tập", Unit = "Tập", on_go = function() end,
    on_range = function() end, on_download_all = function() end, on_offline = function() end,
})
assert(shown.items[1].text == "Mở tập bất kỳ" and shown.items[2].text == "Tập đã tải (offline)")
shown.on_left_icon()
assert(shown.title == "Tải tập" and shown.items[1].text == "Tải khoảng tập"
    and shown.items[2].text == "Tải toàn bộ tập")

local old_dir, old_open = Settings.downloadDir, io.open
Settings.downloadDir = function() return "test-output" end
package.loaded.json = {
    decode = function() return { id = "truyen-1", chapters = {} } end,
    encode = function() return "{}" end,
}
io.open = function() return nil, "no such file", 2 end
local empty = assert(Download.savedList({
    source_id = "docln",
    id = "truyen-1",
    url = "/truyen/1",
}))
assert(#empty == 0, "missing index yields empty offline list")

io.open = function(path)
    if path:find("novels/docln/truyen-1/index.json", 1, true) then
        return {
            read = function() return "index-body" end,
            close = function() end,
        }
    end
    return { close = function() end }
end
package.loaded.json.decode = function(text)
    assert(text == "index-body")
    return {
        id = "truyen-1",
        chapters = {
            ["13"] = { title = "Three", file = "ch-000000000013.html", number = 3 },
            ["11"] = { title = "One", file = "ch-000000000011.html", number = 1 },
            ["12"] = { title = "Locked", skipped = "locked", number = 2 },
        },
    }
end
local list = assert(Download.savedList({
    source_id = "docln",
    id = "truyen-1",
    url = "/truyen/1",
}))
assert(#list == 2, "skipped chapters without file are omitted")
assert(list[1].title == "One" and list[1].number == 1)
assert(list[2].title == "Three" and list[2].number == 3)
assert(list[1].path:find("ch-000000000011.html", 1, true))
package.loaded.json.decode = function()
    return { id = "truyen-1", chapters = {
        ["11"] = { file = "chapters-1-3.epub", export_title = "Book (EPUB)", number = 1 },
        ["13"] = { file = "chapters-1-3.epub", export_title = "Book (EPUB)", number = 3 },
        ["14"] = { file = "../../outside.html", number = 4 },
        ["15"] = { file = "..", number = 5 },
        ["16"] = { file = ".", number = 6 },
    } }
end
list = assert(Download.savedList({ source_id = "docln", id = "truyen-1", url = "/truyen/1" }))
assert(#list == 1 and list[1].title == "Book (EPUB)" and list[1].number == 1)

io.open = function(path)
    if path:match("index%.json$") then
        return { read = function() return "{bad" end, close = function() end }
    end
    if path:match("index%.json%.bak$") then
        return { read = function() return "backup-body" end, close = function() end }
    end
    return { close = function() end }
end
package.loaded.json.decode = function(text)
    if text == "{bad" then error("bad json") end
    return { id = "truyen-1", chapters = {
        ["11"] = { title = "Recovered", file = "ch-000000000011.html", number = 1 },
    } }
end
list = assert(Download.savedList({ source_id = "docln", id = "truyen-1", url = "/truyen/1" }))
assert(#list == 1 and list[1].title == "Recovered", "valid backup recovers offline list")

local Export = require("booxbook.novel-export")
local old_finish = Export.finish
local package_index = { id = "truyen-1", chapters = {
    ["11"] = { title = "One", file = "ch-000000000011.html", number = 1 },
    ["12"] = { title = "Two", skipped = "locked", number = 2 },
    ["13"] = { title = "Three", file = "ch-000000000013.html", number = 3 },
} }
package.loaded.json.decode = function() return package_index end
io.open = function(path)
    if path:match("index%.json$") then
        return { read = function() return "package-index" end, close = function() end }
    end
    if path:match("ch%-000000000011%.html$") then return { close = function() end } end
    return nil, "no such file", 2
end
local explicit
Export.finish = function(_, _, first, last, _, result, _, force)
    explicit = force
    assert(first == 1 and last == 3 and result.keep_html and #result.saved == 1 and #result.skipped == 2)
    table.insert(result.saved, 1, { title = "Book EPUB", path = "book.epub" })
end
local package_series = { source_id = "docln", id = "truyen-1", url = "/truyen/1", title = "Book", chapters = {
    { title = "One" }, { title = "Two" }, { title = "Three" },
} }
local packaged = assert(Download.packageSaved(package_series, 1, 3))
assert(explicit and #packaged.saved == 2 and packaged.saved[1].path == "book.epub")
io.open = function(path)
    if path:match("index%.json$") then
        return { read = function() return "package-index" end, close = function() end }
    end
    return nil, "no such file", 2
end
local no_html, no_html_err = Download.packageSaved(package_series, 1, 3)
assert(not no_html and no_html_err:find("không có chương HTML", 1, true))
Export.finish = old_finish

io.open = function()
    return { read = function() return "{bad" end, close = function() end }
end
package.loaded.json.decode = function() error("bad json") end
local bad, err = Download.savedList({ source_id = "docln", id = "truyen-1", url = "/truyen/1" })
assert(not bad and err, "corrupt index must fail")

Settings.downloadDir = old_dir
io.open = old_open
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
package.loaded["booxbook.ui.series"] = nil
package.loaded.json = nil
print("Novel offline list and series download actions checks passed")
