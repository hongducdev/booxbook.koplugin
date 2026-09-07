# Changelog

## Chưa phát hành — sửa mã hóa MeTruyenCV trên Android

- Sửa lỗi chặn toàn bộ nguồn: Android monolibtic không export các hàm AES-CBC,
  Encrypt, RAND_bytes và Base64 mà adapter cũ gọi trực tiếp.
- Ký bằng Lua AES; tái sử dụng `ffi/sha2`, giải mã `ffi/crypto` AES-ECB + CBC XOR.
  Hash dùng `/dev/urandom` chung Android/Linux. Không thêm thư viện native.
- Test vector độc lập, CBC/binary/PKCS7, thiếu nguồn ngẫu nhiên; thiết kế cho
  KOReader Android/Kindle/Kobo/Linux, chưa xác nhận trên Kindle/Kobo thật.

## Chưa phát hành — MeTruyenCV

- Thêm nguồn MeTruyenCV dựa trên Nekori 1.0.6: mới cập nhật, lượt xem, tìm kiếm,
  metadata, mục lục theo thứ tự và giải mã nội dung bằng OpenSSL có sẵn.
- Nối menu, registry, tải HTML/EPUB và thư viện offline; bỏ qua chương khóa,
  dừng ở lỗi mạng/giải mã/HTTP 401 (chữ ký hỏng, không coi là khóa). Hỗ trợ ID số; URL slug dùng tìm tên thay thế.
- Kiểm thử LuaJIT hồi quy, vector AES/SHA1 độc lập, lỗi/phân trang/download/UI.
  API thật 2026-09-07: danh sách 20 truyện, mục lục 1.214 chương, một chương
  giải mã thành công, tìm tên trả đúng truyện. Chưa kiểm tra trực tiếp trên Boox.

## Chưa phát hành — TVTruyen

- Thêm nguồn tvtruyen.live dùng HTML trực tiếp, không AES/JavaScript.
- Duyệt/tìm, gộp mục lục nhiều trang, tải chương và dùng luồng HTML/EPUB/offline.
- Xác thực host/slug/chương; trang 1 listing trống fail-closed; bỏ qua chương
  khóa/trống, dừng khi HTTP lỗi.
- Kiểm tra web thật: 24 truyện hot, 28 kết quả tìm kiếm, 47 trang mục lục
  Đạo Quân với 2.347 liên kết (website thiếu số 1197), tải chương 1 thành công.
  Đã chép 46 file lên điện thoại và đối chiếu SHA256; cần restart KOReader.

## Chưa phát hành — mở chương bất kỳ

- Thêm mục nhập số thứ tự chương trên mục lục chung cho sáu nguồn.
- Tải một chương rồi mở trực tiếp ReaderUI; giữ thông báo chương khóa/lỗi tải.
- Kiểm tra đầu vào và test hồi quy mở reader, locked, lỗi ghi đều qua.

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
