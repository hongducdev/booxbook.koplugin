# Changelog

## Chưa phát hành — metadata và bìa EPUB

- Truyền metadata từ adapter đến OPF: tên gốc, tác giả, mô tả, thẻ, URL nguồn;
  identifier ổn định theo nguồn và khoảng chương, đồng nhất OPF/NCX.
- Nhúng ảnh bìa JPEG/PNG/GIF (tối đa 2 MiB), khai báo cover metadata, manifest,
  trang bìa và guide. Lỗi tải/định dạng bìa giữ HTML và báo lỗi để thử lại.
- Wattpad giữ cover/description/tags; DocLN lấy tóm tắt/thể loại;
  Sangtacviet giữ mô tả từ book.info. Không tự bịa trường metadata thiếu.

## 0.0.2 — 2026-09-07

- Tùy chọn lưu khoảng chương thành EPUB (cả ba nguồn), Thư viện file KOReader,
  công tắc giữ HTML, và tự xóa báo đã đọc xong.
- Xóa báo khi đóng chỉ nếu đã đánh dấu complete, hoặc EndOfBook mà vẫn ở cuối bài.
- EPUB: mở lại archive trước khi đổi tên; FAT đè file đích; close lỗi không còn được coi là thành công im lặng.
- `novel_keep_html=false`: dừng xóa HTML ở lỗi đầu, trả file còn lại vào index.
- Offline: từ chối tên file `.` / `..`.
