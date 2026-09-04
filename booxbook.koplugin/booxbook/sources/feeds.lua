-- Official RSS directories verified 2026-09-04; see docs/news-categories.md.
local Publishers = {
    { id = "vnexpress", title = "VnExpress", lang = "vi", region = "vietnam",
      base_url = "https://vnexpress.net", filter_element = ".fck_detail",
      categories = {
        { "Thế giới", "/rss/the-gioi.rss" },
        { "Thời sự", "/rss/thoi-su.rss" },
        { "Kinh doanh", "/rss/kinh-doanh.rss" },
        { "Giải trí", "/rss/giai-tri.rss" },
        { "Thể thao", "/rss/the-thao.rss" },
        { "Pháp luật", "/rss/phap-luat.rss" },
        { "Giáo dục", "/rss/giao-duc.rss" },
        { "Góc nhìn", "/rss/goc-nhin.rss" },
        { "Bất động sản", "/rss/bat-dong-san.rss" },
        { "Tin mới nhất", "/rss/tin-moi-nhat.rss" },
        { "Tin nổi bật", "/rss/tin-noi-bat.rss" },
        { "Sức khỏe", "/rss/suc-khoe.rss" },
        { "Đời sống", "/rss/gia-dinh.rss" },
        { "Du lịch", "/rss/du-lich.rss" },
        { "Khoa học công nghệ", "/rss/khoa-hoc-cong-nghe.rss" },
        { "Xe", "/rss/oto-xe-may.rss" },
        { "Ý kiến", "/rss/y-kien.rss" },
        { "Tâm sự", "/rss/tam-su.rss" },
        { "VnE-GO", "/rss/vne-go.rss" },
        { "Thư giãn", "/rss/thu-gian.rss" },
        { "Spotlight", "/rss/spotlight.rss" },
        { "Tin xem nhiều", "/rss/tin-xem-nhieu.rss" },
    } },
    { id = "tuoitre", title = "Tuổi Trẻ", lang = "vi", region = "vietnam",
      base_url = "https://tuoitre.vn", filter_element = ".detail-content",
      categories = {
        { "Trang chủ", "/home.rss" },
        { "Thời sự", "/thoi-su.rss" },
        { "Thế giới", "/the-gioi.rss" },
        { "Pháp luật", "/phap-luat.rss" },
        { "Kinh doanh", "/kinh-doanh.rss" },
        { "Công nghệ", "/nhip-song-so.rss" },
        { "Xe", "/xe.rss" },
        { "Nhịp sống trẻ", "/nhip-song-tre.rss" },
        { "Văn hóa", "/van-hoa.rss" },
        { "Giải trí", "/giai-tri.rss" },
        { "Thể thao", "/the-thao.rss" },
        { "Giáo dục", "/giao-duc.rss" },
        { "Khoa học", "/khoa-hoc.rss" },
        { "Sức khỏe", "/suc-khoe.rss" },
        { "Giả thật", "/gia-that.rss" },
        { "Thư giãn", "/thu-gian.rss" },
        { "Bạn đọc", "/ban-doc.rss" },
        { "Du lịch", "/du-lich.rss" },
        { "Video", "/video.rss" },
    } },
    { id = "thanhnien", title = "Thanh Niên", lang = "vi", region = "vietnam",
      base_url = "https://thanhnien.vn", filter_element = ".detail-content-body",
      categories = require("booxbook.sources.feeds-thanhnien") },
    { id = "dantri", title = "Dân Trí", lang = "vi", region = "vietnam",
      base_url = "https://dantri.com.vn", filter_element = ".singular-content",
      categories = {
        { "Trang chủ", "/rss/home.rss" },
        { "Sự kiện", "/rss/su-kien.rss" },
        { "Thời sự", "/rss/thoi-su.rss" },
        { "Thế giới", "/rss/the-gioi.rss" },
        { "Đời sống", "/rss/doi-song.rss" },
        { "Thể thao", "/rss/the-thao.rss" },
        { "Lao động - Việc làm", "/rss/lao-dong-viec-lam.rss" },
        { "Giáo dục", "/rss/giao-duc.rss" },
        { "Tấm lòng nhân ái", "/rss/tam-long-nhan-ai.rss" },
        { "Kinh doanh", "/rss/kinh-doanh.rss" },
        { "Bất động sản", "/rss/bat-dong-san.rss" },
        { "Giải trí", "/rss/giai-tri.rss" },
        { "Du lịch", "/rss/du-lich.rss" },
        { "Pháp luật", "/rss/phap-luat.rss" },
        { "Sức khỏe", "/rss/suc-khoe.rss" },
        { "Công nghệ", "/rss/cong-nghe.rss" },
        { "Ô tô - Xe máy", "/rss/o-to-xe-may.rss" },
        { "Tình yêu - Giới tính", "/rss/tinh-yeu-gioi-tinh.rss" },
        { "Khoa học", "/rss/khoa-hoc.rss" },
        { "Nội vụ", "/rss/noi-vu.rss" },
        { "Bạn đọc", "/rss/ban-doc.rss" },
        { "Tâm điểm", "/rss/tam-diem.rss" },
        { "Dmagazine", "/rss/dmagazine.rss" },
        { "Infographic", "/rss/infographic.rss" },
        { "Photo News", "/rss/photo-news.rss" },
        { "DNews", "/rss/dnews.rss" },
        { "Tọa đàm trực tuyến", "/rss/toa-dam-truc-tuyen.rss" },
        { "Interactive", "/rss/interactive.rss" },
        { "Tết", "/rss/tet.rss" },
        { "Photo Story", "/rss/photo-story.rss" },
        { "D-Buzz", "/rss/d-buzz.rss" },
        { "Thời tiết", "/rss/thoi-tiet.rss" },
        { "DT360", "/rss/dt360.rss" },
    } },
}

for _, module in ipairs({ "feeds-tienphong", "feeds-vietnam-more", "feeds-world", "feeds-world-more" }) do
    for _, publisher in ipairs(require("booxbook.sources." .. module)) do
        Publishers[#Publishers + 1] = publisher
    end
end

for _, publisher in ipairs(Publishers) do
    for index, row in ipairs(publisher.categories) do
        local url = row[2]:match("^https?://") and row[2] or publisher.base_url .. row[2]
        local slug = url:match("^https?://[^/]+/(.*)") or publisher.id
        slug = slug:gsub("^rss/", ""):gsub("%.rss$", ""):gsub("[^%w%-]", "-")
        publisher.categories[index] = {
            id = publisher.id .. "-" .. slug,
            title = publisher.title .. " - " .. row[1],
            category = row[1],
            url = url,
            lang = publisher.lang,
            full_article = true,
            filter_element = publisher.filter_element,
        }
    end
end

return Publishers
