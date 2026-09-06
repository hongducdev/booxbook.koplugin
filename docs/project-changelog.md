# Changelog

## 0.0.2 — 2026-09-07

- Tùy chọn lưu khoảng chương thành EPUB (cả ba nguồn), Thư viện file KOReader,
  công tắc giữ HTML, và tự xóa báo đã đọc xong.
- Xóa báo khi đóng chỉ nếu đã đánh dấu complete, hoặc EndOfBook mà vẫn ở cuối bài.
- EPUB: mở lại archive trước khi đổi tên; FAT đè file đích; close lỗi không còn được coi là thành công im lặng.
- `novel_keep_html=false`: dừng xóa HTML ở lỗi đầu, trả file còn lại vào index.
- Offline: từ chối tên file `.` / `..`.
