# Danh mục báo RSS

Snapshot kiểm tra ngày 04/09/2026. Phạm vi là các kênh RSS công khai, không phải mọi URL trên website, trang tác giả, nội dung trả phí hay trình phát media.

Điều hướng: **Báo → Báo Việt / Báo Nước Ngoài → đầu báo → danh mục → bài**. 9 báo Việt, 8 nguồn nước ngoài, 633 kênh có bài sau khi rà 680 ứng viên. RSS tùy chỉnh là menu riêng, không suy từ ngôn ngữ.

| Đầu báo | Kênh | Nguồn và phạm vi |
|---|---:|---|
| VnExpress | 22 | [Mục RSS](https://vnexpress.net/rss); đã bỏ Startup |
| Tuổi Trẻ | 19 | [Mục RSS](https://tuoitre.vn/rss.htm), mọi liên kết đã công bố |
| Thanh Niên | 166 | [Mục RSS](https://thanhnien.vn/rss.html), gồm danh mục con còn bài |
| Dân Trí | 33 | [Mục RSS](https://dantri.com.vn/rss.htm), đã gộp trùng |
| BBC News | 26 | [Danh sách feed](https://www.bbc.co.uk/news/10628494), các feed còn hoạt động |
| The Guardian | 54 | [International](https://www.theguardian.com/international) theo [hướng dẫn RSS](https://www.theguardian.com/help/feeds) |
| DW | 10 | Feed tiếng Anh đã xác minh tại [rss.dw.com](https://rss.dw.com/rdf/rss-en-all); không tuyên bố đủ mục |
| Tiền Phong | 100 | [Mục RSS](https://tienphong.vn/rss.html) |
| VietnamPlus | 58 | [Mục RSS](https://www.vietnamplus.vn/rss.html); hai endpoint rỗng đã bỏ |
| Báo Tin tức | 23 | [Mục RSS](https://baotintuc.vn/rss.htm) |
| Nhân Dân | 36 | [Mục RSS](https://nhandan.vn/rss.html); nút trùng đã gộp |
| Sài Gòn Giải Phóng | 58 | [Mục RSS](https://www.sggp.org.vn/rss.html); nút trùng đã gộp |
| Sky News | 9 | [Mục RSS](https://news.sky.com/info/rss), bản HTTPS |
| The Independent | 16 | [Mục RSS](https://www.independent.co.uk/service/rss-feeds-775086.html); 41 kênh rỗng đã bỏ |
| Al Jazeera | 1 | [Feed tiếng Anh](https://www.aljazeera.com/xml/rss/all.xml) |
| France 24 | 1 | [Feed tiếng Anh](https://www.france24.com/en/rss) |
| ABC News Australia | 1 | [Just In](https://www.abc.net.au/news/feed/51120/rss.xml) |

## Kiểm tra

Lượt rà đầy đủ: 680 URL, User-Agent desktop của plugin, cookie giao diện VnExpress, giãn cách 1,2 giây/host, parse bằng `Rss.parse`. 633 kênh có bài; 47 kênh rỗng hai lần; không lỗi HTTP. Đã xóa 47 mục rỗng (VnExpress Startup; một số mục Thanh Niên/Dân Trí; 41 mục Independent).

Số liệu mô tả lần kiểm tra đó, không phải tình trạng vĩnh viễn. Nếu một kênh sau này trống, plugin vẫn báo lỗi kênh đó, không prefetch danh mục khác.

Đã loại 13 URL BBC cũ (video/audio, 404, TLS). Guardian Today's paper RSS trả 404; trang chủ dùng `/international/rss`. DW: all, top, Germany, Asia, business, sports, culture, environment, science, Europe. Mục mang tính media chỉ lấy chữ/tóm tắt; plugin không phát video.

Không đăng nhập, không vượt paywall hay chống bot. Bài không lấy được toàn văn thì dùng tóm tắt RSS.

Kiểm tra sống (thư mục gốc repo): `pwsh -File scripts/news-feeds-live.ps1 -All` rà mọi danh mục còn lại và fail nếu kênh rỗng/lỗi. Không `-All` thì rà mười feed đại diện. `-PassThru` trả bằng chứng từng kênh. Snapshot unit test: `tests/fixtures/feeds-audit.md`.

## Bảo trì

Dữ liệu catalog nằm trong `booxbook.koplugin/booxbook/sources/feeds*.lua`. Xem lại mục RSS chính thức trước khi đổi URL. Không suy slug tiếng Việt từ tiêu đề: Công nghệ trên Tuổi Trẻ dùng `nhip-song-so.rss`. Test kiểm tra số lượng, URL/ID lưu trữ duy nhất, và nhãn danh mục cha/con. Không crawl nền; chỉ tải danh mục/bài đã chọn.
