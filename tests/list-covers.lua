-- Thumbnails in the news/novels lists are a separate switch from illustration
-- images inside an article: a reader may want lists to open with no cover
-- download and still see pictures in the articles they open.
local Settings = require("booxbook.store.settings")

assert(Settings.listCovers() == true, "list thumbnails default on")
assert(Settings.includeImages() == true, "article images default on")

Settings.set("list_covers", false)
assert(Settings.listCovers() == false, "list thumbnails can be turned off")
assert(Settings.includeImages() == true, "turning off thumbnails keeps article images")
assert(Settings.get("include_images") == true, "independent keys")

Settings.set("include_images", false)
assert(Settings.includeImages() == false and Settings.listCovers() == false, "both off")

Settings.set("include_images", true)
Settings.set("list_covers", true)
assert(Settings.listCovers() == true and Settings.includeImages() == true, "both back on")

print("List thumbnail switch checks passed")
