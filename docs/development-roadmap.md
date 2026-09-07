# Lộ trình phát triển

## MeTruyenCV — 2026-09-07

- [x] Sửa symbol crypto thiếu trên Android; dùng wrapper KOReader chung Linux,
      test giới hạn symbol như APK, JIT bật/tắt, vector AES/CBC/PKCS7.
- [ ] Kiểm tra trên Kindle/Kobo thật trước khi tuyên bố hỗ trợ thiết bị đã xác nhận.

- [x] Adapter API, AES-CBC/SHA1 qua OpenSSL có sẵn; menu, HTML/EPUB/offline.
- [x] Test LuaJIT, vector crypto độc lập và API thật (duyệt/tìm/mục lục/chương).
- [ ] Kiểm tra thao tác tải/đọc trực tiếp trên Boox.

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

## TVTruyen — 2026-09-07

- [x] Adapter HTML, tìm/duyệt, mục lục phân trang và chương công khai.
- [x] Menu, registry, tải HTML/EPUB/offline và kiểm tra URL/chương khóa/lỗi mạng.
- [ ] Kiểm tra thao tác trên Kindle/Kobo thật.

## Mở chương bất kỳ — 2026-09-07

- [x] Nhập thứ tự mục lục và mở chương trực tiếp trên giao diện chung.
- [x] Kiểm thử số không hợp lệ, chương khóa, lỗi ghi và hồi quy.

## Truyện Full — 2026-09-07

- [x] Adapter HTML Nekori 1.0.7: duyệt/tìm, mục lục phân trang, `#chapter-c`.
- [x] Menu, registry, tải HTML/EPUB/offline; skip chương trống; fail-closed listing.
- [ ] Kiểm tra thao tác trên Boox/Kindle/Kobo thật.
