-- Regression: follow/queue list screens must build rows without crashing.
-- On device, `for _, x` loop indexes shadowed gettext `_()` and crashed
-- KOReader when opening a non-empty follow list (follow.lua:113).
local names = { "ui/widget/infomessage", "ui/trapper", "ui/uimanager", "gettext",
    "booxbook.ui.catalog", "booxbook.store.settings", "booxbook.network",
    "booxbook.ui.follow", "booxbook.ui.queue", "booxbook.queue",
    "libs/libkoreader-lfs", "booxbook.wifi-upload", "booxbook.http" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

local notice
package.loaded.gettext = function(text) return text end
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/uimanager"] = {
    show = function(_, value) notice = value.text end,
    nextTick = function(_, fn) fn() end,
}
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end,
    info = function() end, clear = function() end }
local shown
package.loaded["booxbook.ui.catalog"] = {
    show = function(value) shown = value end,
    promptText = function() end,
    confirm = function(_, fn) fn() end,
    clearStack = function() end,
}
package.loaded["booxbook.store.settings"] = {
    get = function(key)
        if key == "followed_series" then
            return { ["docln/1"] = { source_id = "nosuch", id = "1",
                title = "Truyen", url = "", last_count = 3 } }
        end
    end,
    set = function() end,
    downloadDir = function() return "@uiopen" end,
    ensureDir = function() return true end,
}
package.loaded["booxbook.network"] = { whenOnline = function(fn) fn() end }
package.loaded["libs/libkoreader-lfs"] = { symlinkattributes = function() return nil end }

package.loaded["booxbook.ui.follow"] = nil
local FollowUI = require("booxbook.ui.follow")
FollowUI.open()
assert(shown and shown.title:find("theo d", 1, true), "follow list opens")
assert(#shown.items == 1, "follow list shows the one entry")
assert(shown.items[1].text == "Truyen", "follow entry keeps its title")
shown.items[1].callback()
assert(notice and notice:find("Ngu", 1, true), "unknown source reports instead of crashing")

package.loaded["booxbook.queue"] = {
    path = function(dir) return dir .. "/queue.txt" end,
    read = function() return { "https://example.com/book.epub" } end,
    remove = function() return true end,
    clear = function() return true end,
}
package.loaded["booxbook.ui.queue"] = nil
local QueueUI = require("booxbook.ui.queue")
QueueUI.open()
assert(shown and #shown.items == 3, "queue list shows header, link and clear rows")

for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Follow and queue list screens build rows without gettext shadowing")
