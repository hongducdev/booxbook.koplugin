# Changelog

## 0.0.11 — 2026-09-10

- Đọc tiếp nối tập/chương (EndOfBook): tới trang cuối CBZ/EPUB/HTML thì hỏi mở tiếp
  nếu đã tải, hỏi tải tiếp nếu chưa; hết bộ thì báo đã đọc hết. Comic dùng sidecar
  `.meta.json` + `manifest.json`, novel dùng `index.json`.
- Fix tiếp nối: không nuốt dialog EndOfBook mặc định với sách ngoài BooxBook, không
  ghi sidecar terminal khi thiếu manifest, chặn `next_url` khác bộ/khác nguồn,
  kiểm tra số chương `downloadChapter` trước khi tải.

## 0.0.10 — 2026-09-09

- Thêm OneDrive download-only: Device Code login, duyệt từng thư mục và tải các
  định dạng sách KOReader hỗ trợ vào `received/`; không upload, sync hay ghi đè.
- Cấu hình sẵn public client ID BooxBook; OAuth/Graph xác minh CA và hostname.
- Sửa Android báo `error loading CA locations`: lấy CA bundle từ runtime KOReader
  thay vì nhầm sang thư mục dữ liệu ngoài `/sdcard/koreader`.
- Sửa KOReader crash khi OneDrive trả về thư mục: biến chỉ số vòng lặp không còn
  che mất hàm dịch `gettext`; thêm kiểm thử hồi quy cho dòng thư mục.
- OneDrive tự thêm `(1)`, `(2)` khi sách trùng tên, giữ nguyên file cũ thay vì
  báo đã tồn tại trước khi tải.
- Gom thư viện local và provider cloud dưới mục **Sách & cloud**.

## 0.0.9 — 2026-09-09

- Thêm DNS over HTTPS cho request HTTPS để tránh DNS nhà mạng chặn nguồn truyện; giữ Host/SNI gốc, thử nhiều IPv4, cache TTL và fallback DNS hệ thống.
- Sửa một số bài báo báo `Invalid argument` khi tiêu đề dài bị cắt giữa ký tự UTF-8.
- Gom Cài đặt thành bốn nhóm vừa một màn hình: đọc và tải, bộ nhớ, nguồn và cookie, hệ thống.
- Tối ưu trang chủ còn năm tác vụ chính; đưa phiên bản và nút cập nhật có nhãn xuống footer.

## 0.0.8 — 2026-09-09

- Báo **Đã nhận sách** và tên file trên KOReader sau khi lưu hoàn tất.
- Ưu tiên IPv4 của interface Wi-Fi; khóa 5 lần sai theo IP nguồn và hủy callback
  bật Wi-Fi khi người dùng đã rời màn hình.

- Sửa QR nhận sách quá nhỏ: khung vuông bằng 85% cạnh ngắn màn hình,
  dùng kích thước render QR trực tiếp để giữ nét và vừa cả màn hình ngang/dọc.

- Rút mã phiên Wi-Fi còn 6 chữ số ngẫu nhiên, bàn phím số trên điện thoại;
  khóa nhận sau 5 lần sai đến khi mở lại phiên.

- Thêm **Gửi sách qua Wi-Fi** riêng trong BooxBook: web tiếng Việt cho điện thoại/máy tính,
  QR điền mã phiên, chọn nhiều sách, tiến độ gửi, lưu vào `received` trong Thư viện.
- Nhận stream tối đa 512 MiB/file; chặn tên/định dạng không hợp lệ, sai mã phiên,
  cross-origin và ghi đè. Dọn file gửi dở khi disconnect/timeout/dừng.
- Dừng khi đóng màn hình, ngủ, mất mạng hoặc thoát; không thêm dependency cho plugin.
- Qua kiểm thử LuaJIT và TCP desktop với transport kiểm thử; còn smoke test trên Boox thật.

## 0.0.7 — 2026-09-08

- Tải truyện chữ bỏ qua chương còn file, nhưng tải lại entry có file bị mất.
- Backup/fallback `index.json` hợp lệ để danh sách offline chịu được index chính hỏng.
- Thêm **Tạo EPUB từ chương đã tải** theo khoảng; không tải lại nội dung và luôn giữ HTML.

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
