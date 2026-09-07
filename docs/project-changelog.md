# Changelog

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
