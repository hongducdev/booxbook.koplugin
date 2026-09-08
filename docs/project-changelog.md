# Changelog

## 0.0.6 — 2026-09-08

- Hủy giữa chừng tải truyện chữ/truyện tranh: hỏi Đóng gói EPUB/CBZ partial hoặc giữ HTML/ảnh để tải tiếp; ConfirmBox hiện trước list/toast.
- Đóng gói sau hủy luôn giữ HTML; cancel dùng sentinel ổn định, không khớp chuỗi UI.
- Giới hạn cache ảnh dùng một lần (sidecar, bìa 50MB, staging comic) mà không xóa bài đã lưu.
- Sửa tìm Wattpad tiếng Việt qua API v4.

## 0.0.5 — 2026-09-08

- Thêm Truyện Tuổi Thơ (CBZ): duyệt/tìm, mục lục AJAX, tải một/khoảng/toàn bộ tập, tải tiếp, đọc offline. Giới hạn 600 trang/8 MiB ảnh/512 MiB tập.
- CBZ mặc định vừa một trang mỗi lần lật; giữ tùy chỉnh đọc sau lần mở đầu.
- Sửa HTML thẻ rỗng (`img`…) nuốt ảnh sau; HTTP báo lỗi khi đóng file thất bại; nhãn mạng ưu tiên `isConnected`.

## 0.0.4 — 2026-09-07

- Thêm MeTruyenCV (API, AES trên Android): duyệt/tìm, mục lục, giải mã chương công khai. HTTP 401 dừng khoảng tải, không skip như khóa.
- Thêm TVTruyen (HTML): duyệt/tìm, mục lục phân trang; chương khóa/trống bỏ qua; listing trang 1 trống fail-closed.
- Mở chương bất kỳ trên mục lục chung (sáu nguồn).

## 0.0.3 — 2026-09-07

- Thêm nguồn Truyện Full (truyenfull.live): duyệt mới/hot, tìm kiếm, mục lục phân trang, tải HTML chương công khai. Chương trống/khóa bỏ qua.
- EPUB giữ metadata nguồn (tên, tác giả, mô tả/thẻ, URL) và nhúng ảnh bìa JPEG/PNG/GIF (tối đa 2 MiB).

## 0.0.2 — 2026-09-07

- Tùy chọn lưu khoảng chương thành EPUB (cả ba nguồn), Thư viện file KOReader,
  công tắc giữ HTML, và tự xóa báo đã đọc xong.
- Xóa báo khi đóng chỉ nếu đã đánh dấu complete, hoặc EndOfBook mà vẫn ở cuối bài.
- EPUB: mở lại archive trước khi đổi tên; FAT đè file đích; close lỗi không còn được coi là thành công im lặng.
- `novel_keep_html=false`: dừng xóa HTML ở lỗi đầu, trả file còn lại vào index.
- Offline: từ chối tên file `.` / `..`.
