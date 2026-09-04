local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local ReaderUI = require("apps/reader/readerui")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Publishers = require("booxbook.sources.feeds")
local Rss = require("booxbook.sources.rss")
local Settings = require("booxbook.store.settings")

local News = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function customFeeds()
    local feeds = {}
    for index, url in ipairs(Settings.get("custom_rss_feeds") or {}) do
        feeds[#feeds + 1] = {
            id = "custom-" .. index,
            title = url,
            lang = "",
            url = url,
            full_article = false,
        }
    end
    return feeds
end

function News.setLimit()
    Catalog.promptText{
        title = _("Số bài mỗi danh mục"),
        input = tostring(Settings.get("news_limit") or 10),
        on_submit = function(value)
            local limit = tonumber(value)
            if not limit or limit < 1 or limit > 20 or limit % 1 ~= 0 then
                notify(_("Nhập số nguyên từ 1 đến 20."))
                return
            end
            Settings.set("news_limit", limit)
        end,
    }
end

function News.addCustomFeed()
    Catalog.promptText{
        title = _("Thêm RSS tùy chỉnh"),
        hint = "https://example.com/feed.xml",
        on_submit = function(url)
            url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if not url:match("^https?://") then
                notify(_("URL phải bắt đầu bằng http:// hoặc https://"))
                return
            end
            local feeds = Settings.get("custom_rss_feeds") or {}
            feeds[#feeds + 1] = url
            Settings.set("custom_rss_feeds", feeds)
            notify(_("Đã thêm nguồn RSS."))
        end,
    }
end

local function onlineAction(message, action, on_success)
    -- Let the selecting menu finish updating before showing progress or another screen.
    UIManager:nextTick(function()
        NetworkMgr:beforeWifiAction(function()
            Trapper:wrap(function()
                Trapper:info(message)
                local ok, result, err = pcall(action)
                Trapper:clear()
                if not ok or not result then
                    notify(_("Không tải được tin: ") .. tostring(ok and err or result))
                    return
                end
                UIManager:nextTick(function() on_success(result) end)
            end)
        end)
    end)
end

function News.openArticle(feed, item)
    onlineAction(_("Đang mở bài: ") .. item.title, function()
        return Rss.loadArticle(feed, item)
    end, function(path)
        Catalog.clearStack()
        ReaderUI:showReader(path)
    end)
end

function News.showFeed(feed)
    onlineAction(_("Đang lấy danh sách: ") .. feed.title, function()
        return Rss.list(feed, Settings.get("news_limit") or 10)
    end, function(articles)
        local items = {}
        for _, article in ipairs(articles) do
            local current = article
            items[#items + 1] = {
                text = current.title,
                keep_menu_open = true,
                callback = function() News.openArticle(feed, current) end,
            }
        end
        Catalog.show{ title = feed.title, items = items }
    end)
end

function News.showCategories(publisher)
    local items = {}
    for _, feed in ipairs(publisher.publishers or publisher.categories) do
        local current = feed
        items[#items + 1] = {
            text = current.category or current.title,
            keep_menu_open = true,
            callback = function()
                if current.categories then
                    UIManager:nextTick(function() News.showCategories(current) end)
                else
                    News.showFeed(current)
                end
            end,
        }
    end
    Catalog.show{ title = publisher.title, items = items }
end

function News.showArticles()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        notify(_("Không đọc được thư mục tin."))
        return
    end
    local root = Settings.downloadDir() .. "/news"
    local items = {}
    if lfs.attributes(root, "mode") == "directory" then
        for feed_dir in lfs.dir(root) do
            local dir = root .. "/" .. feed_dir
            if feed_dir ~= "." and feed_dir ~= ".." and lfs.attributes(dir, "mode") == "directory" then
                for name in lfs.dir(dir) do
                    if name:match("%.html$") then
                        local path = dir .. "/" .. name
                        local article_path = path
                        items[#items + 1] = {
                            text = name:gsub("%.html$", ""),
                            keep_menu_open = true,
                            callback = function()
                                UIManager:nextTick(function()
                                    Catalog.clearStack()
                                    ReaderUI:showReader(article_path)
                                end)
                            end,
                        }
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b)
        return a.text > b.text
    end)
    Catalog.show{ title = _("Tin đã tải"), items = items }
end

function News.menu()
    local groups = {
        { title = _("Báo Việt"), publishers = {} },
        { title = _("Báo Nước Ngoài"), publishers = {} },
    }
    for _, publisher in ipairs(Publishers) do
        local group = groups[publisher.region == "vietnam" and 1 or 2].publishers
        group[#group + 1] = publisher
    end
    local custom = customFeeds()
    if #custom > 0 then
        groups[#groups + 1] = { title = _("RSS tùy chỉnh"), categories = custom }
    end
    local items = {}
    for _, publisher in ipairs(groups) do
        local current = publisher
        items[#items + 1] = {
            text = current.title,
            keep_menu_open = true,
            callback = function()
                UIManager:nextTick(function() News.showCategories(current) end)
            end,
        }
    end
    items[#items + 1] = { text = _("Tin đã tải"), keep_menu_open = true, callback = function()
        UIManager:nextTick(News.showArticles)
    end }
    items[#items + 1] = { text = _("Số bài mỗi danh mục"), keep_menu_open = true, callback = News.setLimit }
    items[#items + 1] = { text = _("Thêm RSS tùy chỉnh"), keep_menu_open = true, callback = News.addCustomFeed }
    return items
end

return News
