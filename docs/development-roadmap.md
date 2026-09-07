# Lộ trình phát triển

## Giữ HTML và tự xóa báo — 2026-09-06

- [x] Tách công tắc giữ HTML; chỉ xóa sau khi EPUB và index đã lưu.
- [x] Offline hỗ trợ EPUB không trùng; tự xóa báo hoàn tất sau khi đóng.
- [x] Test lỗi ghi/xóa, đường dẫn, đọc dở và mở lại bài.
- [x] Sửa EndOfBook sticky, verify EPUB, dừng xóa HTML, FAT rename, `..` trong index.
- [ ] Kiểm tra thao tác đọc xong và xóa báo trên điện thoại thật.

## EPUB và Thư viện — 2026-09-06

- [x] Tùy chọn EPUB dùng chung cho ba nguồn truyện; giữ HTML phục hồi.
- [x] Thư viện bằng trình quản lý file KOReader và thao tác file sẵn có.
- [x] Kiểm tra cú pháp LuaJIT và test hồi quy/download/archive/navigation.
- [ ] Kiểm tra trực tiếp trên Boox: EPUB nhiều chương, nhấn giữ file, chuyển
      từ sách đang đọc sang Thư viện rồi mở lại; phát hành sau kiểm tra thiết bị.

Chi tiết: [changelog](project-changelog.md), [hướng dẫn](usage.md).

## Truyện Full — 2026-09-07

- [x] Adapter HTML Nekori 1.0.7: duyệt/tìm, mục lục phân trang, `#chapter-c`.
- [x] Menu, registry, tải HTML/EPUB/offline; skip chương trống; fail-closed listing.
- [ ] Kiểm tra thao tác trên Boox/Kindle/Kobo thật.
