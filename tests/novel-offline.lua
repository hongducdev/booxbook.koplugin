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
    on_offline = function() end,
})
assert(shown.left_icon == "appbar.menu" and type(shown.on_left_icon) == "function")
assert(shown.items[1].text == "Chương đã tải (offline)")
assert(shown.items[2].text == "V1")
shown.on_left_icon()
assert(shown.title == "Tải chương")
assert(shown.items[1].text == "Tải khoảng chương")
assert(shown.items[2].text == "Tải toàn bộ chương")

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
    assert(path:find("novels/docln/truyen-1/index.json", 1, true))
    return {
        read = function() return "index-body" end,
        close = function() end,
    }
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
    return { chapters = {
        ["11"] = { file = "chapters-1-3.epub", export_title = "Book (EPUB)", number = 1 },
        ["13"] = { file = "chapters-1-3.epub", export_title = "Book (EPUB)", number = 3 },
        ["14"] = { file = "../../outside.html", number = 4 },
        ["15"] = { file = "..", number = 5 },
        ["16"] = { file = ".", number = 6 },
    } }
end
list = assert(Download.savedList({ source_id = "docln", id = "truyen-1", url = "/truyen/1" }))
assert(#list == 1 and list[1].title == "Book (EPUB)" and list[1].number == 1)

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
