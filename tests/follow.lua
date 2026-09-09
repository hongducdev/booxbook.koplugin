local Follow = require("booxbook.follow")

assert(Follow.key("docln", "abc") == "docln/abc", "follow key joins source and id")
assert(Follow.key("docln", "") == nil, "empty id has no key")
assert(Follow.key("bad id", "x") == nil, "source id rejects spaces")

local data = {}
data = assert(Follow.follow(data, { source_id = "docln", id = "s1", title = "Truyen A",
    url = "https://docln.net/x", chapters = { 1, 2, 3 } }))
assert(Follow.isFollowed(data, "docln", "s1") == true, "followed series is marked")
assert(data["docln/s1"].last_count == 3, "follow stores chapter count")
assert(#Follow.list(data) == 1, "follow list has one entry")

assert(Follow.checkUpdate(data["docln/s1"], 5) == 2, "two new chapters detected")
assert(Follow.checkUpdate(data["docln/s1"], 3) == 0, "same count means no update")
assert(Follow.checkUpdate(data["docln/s1"], 1) == 0, "shrunk TOC never negative")

assert(Follow.noteChecked(data, "docln", "s1", 5) == true, "noteChecked updates count")
assert(data["docln/s1"].last_count == 5, "checked count persists")

data = assert(select(1, Follow.unfollow(data, "docln", "s1")))
assert(Follow.isFollowed(data, "docln", "s1") == false, "unfollow clears entry")

print("Follow checks passed")
