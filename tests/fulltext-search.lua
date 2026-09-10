-- Unit tests for FulltextSearch (Phase 04)
local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local FulltextSearch = require("booxbook.fulltext-search")

-- 1. Accent folding
assert(FulltextSearch.fold("Tiếng Việt") == "tieng viet", "vietnamese accent folding")
assert(FulltextSearch.fold("ĐẤU LA ĐẠI LỤC") == "dau la dai luc", "uppercase accent folding")
assert(FulltextSearch.fold("Hello World") == "hello world", "plain ascii lowercasing")

-- 2. HTML stripping
local dirty_html = [[
<html>
<head><style>body { color: red; }</style></head>
<body>
  <!-- Comment -->
  <script>alert('evil');</script>
  <h1>Tiêu đề</h1>
  <p>Nội dung <b>chương 1</b>.<br/>Dòng tiếp theo.</p>
</body>
</html>
]]
local clean = FulltextSearch.stripHtml(dirty_html)
assert(clean:find("alert", 1, true) == nil, "script removed")
assert(clean:find("color", 1, true) == nil, "style removed")
assert(clean:find("Comment", 1, true) == nil, "comment removed")
assert(clean:find("Tiêu đề", 1, true) ~= nil, "h1 content kept")
assert(clean:find("chương 1", 1, true) ~= nil, "paragraph content kept")
assert(clean:find("Dòng tiếp theo", 1, true) ~= nil, "br converted to space")

-- 3. searchFile: matching and snippets
local sample_text = [[<p>Bạch Tiểu Thuần nhìn lên bầu trời xanh biếc. Hắn thở dài một hơi thật sâu rồi tiếp tục luyện công.</p>]]
local mock_files = {
    ["novel/ch1.html"] = sample_text,
}

local mock_reader = function(path, max_bytes)
    return mock_files[path] or ""
end

-- Match unaccented query against accented text
local res1 = FulltextSearch.searchFile("novel/ch1.html", "tieu thuan", {
    file_reader = mock_reader,
})
assert(#res1 == 1, "found 1 match using unaccented query")
assert(res1[1].match == "Tiểu Thuần", "extracted original accented text as match")
assert(res1[1].snippet:find("[Tiểu Thuần]", 1, true) ~= nil, "highlighted match in snippet")

-- Match accented query
local res2 = FulltextSearch.searchFile("novel/ch1.html", "Tiểu Thuần", {
    file_reader = mock_reader,
})
assert(#res2 == 1, "found 1 match using accented query")
assert(res2[1].match == "Tiểu Thuần", "match preserved")

-- 4. Bounded limits: max_matches and max_file_bytes
local repeating_html = string.rep("<p>từ khóa đặc biệt</p>\n", 50)
mock_files["novel/repeat.html"] = repeating_html

local res_capped = FulltextSearch.searchFile("novel/repeat.html", "tu khoa", {
    file_reader = mock_reader,
    max_matches = 5,
})
assert(#res_capped == 5, "capped at max_matches = 5")

local res_truncated = FulltextSearch.searchFile("novel/repeat.html", "tu khoa", {
    file_reader = mock_reader,
    max_file_bytes = 100, -- very small cutoff
})
assert(res_truncated.stats.truncated == true, "stats indicate file was truncated")

-- 5. searchTree directory traversal and bounds
local mock_tree = {
    ["/dl"] = {
        { name = "novels", path = "/dl/novels", is_dir = true },
        { name = "news", path = "/dl/news", is_dir = true },
        { name = "image.jpg", path = "/dl/image.jpg", is_dir = false }, -- ignored extension
    },
    ["/dl/novels"] = {
        { name = "ch1.html", path = "/dl/novels/ch1.html", is_dir = false },
        { name = "ch2.html", path = "/dl/novels/ch2.html", is_dir = false },
    },
    ["/dl/news"] = {
        { name = "art1.html", path = "/dl/news/art1.html", is_dir = false },
    },
}

local mock_fs = {
    ["/dl/novels/ch1.html"] = "<p>Bí kíp võ công cửu âm chân kinh.</p>",
    ["/dl/novels/ch2.html"] = "<p>Không có gì ở đây.</p>",
    ["/dl/news/art1.html"] = "<p>Võ công truyền thống được bảo tồn.</p>",
}

local mock_lister = function(dir)
    return mock_tree[dir] or {}
end
local tree_reader = function(path)
    return mock_fs[path] or ""
end

local tree_res = FulltextSearch.searchTree("/dl", "vo cong", {
    max_matches = 10,
}, mock_lister, tree_reader)

assert(#tree_res == 2, "found 2 matches across novels and news")
assert(tree_res.stats.files_scanned == 3, "scanned 3 html files, ignored jpg")
assert(tree_res[1].path == "/dl/novels/ch1.html", "first match in novel")
assert(tree_res[2].path == "/dl/news/art1.html", "second match in news")

-- Bound check: max_matches stops tree traversal early
local tree_res_limit = FulltextSearch.searchTree("/dl", "vo cong", {
    max_matches = 1,
}, mock_lister, tree_reader)
assert(#tree_res_limit == 1, "stopped at max_matches = 1")
assert(tree_res_limit.stats.stopped_by == "max_matches", "stopped_by stat recorded")

print("FulltextSearch checks passed: bounded search, snippets and folding verified")
