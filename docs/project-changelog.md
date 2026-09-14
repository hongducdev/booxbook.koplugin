# Changelog

## 0.0.13 — 2026-09-14

- **Dòng trạng thái mạng ở màn hình chính**: thêm icon theo trạng thái (`✓` đã kết nối,
  `•` có liên kết nhưng chưa chắc Internet, `○` chưa kết nối, `?` chưa xác định) và hiện
  **tên mạng thay vì địa chỉ IP**: Kobo/Kindle tự đọc SSID (`wpa_cli`/`iwgetid`); Android
  dùng tên ở **Cài đặt → Hệ thống → Tên Wi-Fi hiển thị**, mục này tự dò qua root nếu máy đã
  root và cho nhập tay khi không dò được (KOReader không có quyền đọc SSID nên không thể tự
  lấy), kèm fallback hiện loại mạng (`Wi-Fi`/`4G`/`Ethernet`); tra cứu cache 60 giây.
- **Sửa lỗi không mở được trang gửi sách qua Wi-Fi**: máy chủ lắng nghe trên mọi
  interface (`0.0.0.0`) và tự chuyển sang cổng trống tiếp theo trong 8080–8088 khi cổng
  8080 bận, thay vì chỉ bind đúng một địa chỉ IPv4 của interface được chọn.
- **Chọn địa chỉ LAN đúng để hiển thị**: interface VPN/cellular (`tun*`, `utun*`, `wg*`,
  `tailscale*`, `rmnet*`, `ccmni*`, `wwan*`, …) bị xếp cuối và địa chỉ routable ưu tiên
  hơn link-local; màn hình hiển thị đủ danh sách địa chỉ IPv4 (kể cả địa chỉ từ bảng
  định tuyến) để thử địa chỉ kế tiếp khi địa chỉ đầu không tới được.
- **Host/Origin linh hoạt nhưng vẫn chống DNS rebinding**: chấp nhận mọi địa chỉ IPv4
  (hoặc `localhost`) đúng cổng của máy chủ, từ chối tên miền, Origin HTTPS và
  `Sec-Fetch-Site: cross-site`; kết nối từ ngoài dải mạng nội bộ bị từ chối theo địa chỉ
  nguồn, nên bind `0.0.0.0` không mở server ra Internet.
- **Trang vẫn mở khi bấm link từ ứng dụng khác**: request ghi mới bị chặn vì
  `Sec-Fetch-Site: cross-site`; điều hướng GET (bấm link trong Zalo/Telegram, mở từ lịch sử
  trình duyệt) không còn bị trả 403, đây là nguyên nhân trực tiếp của "gõ đúng địa chỉ mà
  không thấy giao diện".
- **Nguồn ngoài mạng nội bộ bị chặn ngay khi accept**: địa chỉ nguồn phải thuộc dải
  private/link-local/loopback/CGNAT hoặc cùng hai octet đầu với một địa chỉ của máy (LAN cấp
  IP public vẫn dùng được); nhờ vậy bind `0.0.0.0` không mở server ra Internet và kẻ lạ không
  chiếm được slot kết nối.
- **Chẩn đoán ngay trên máy đọc sách** (`ui/wifi-transfer.lua`): mục mới **Kiểm tra kết nối và
  kết quả** hiển thị số kết nối/yêu cầu/bị từ chối, địa chỉ mà điện thoại đã gọi và cảnh báo khi
  trình duyệt tự nâng lên HTTPS; subtitle cảnh báo khi địa chỉ hiển thị không thuộc mạng nội bộ
  (VPN/4G).
- **Tối ưu hiệu năng** (`html.lua`, `library.lua`, `sources/rss.lua`, `fulltext-search.lua`,
  `store/settings.lua`, `main.lua`): bỏ lần `stripDangerous` trùng ở đường bài báo (6,5×);
  `Html.elements` không còn copy cả chuỗi còn lại mỗi lần khớp (6× với trang 2000 link);
  `Html.decode` có fast-path khi giá trị không chứa entity (5,5×); `Library.fold` thay ~135
  lượt `gsub` bằng một lượt quét UTF-8 (13× với tiếng Việt, 78× với chuỗi ASCII) và bảng
  dấu dùng chung một bản; `Settings.downloadDir` chỉ tạo thư mục một lần mỗi phiên; tick
  WiFi 20 Hz khi rảnh → 5 Hz. `main.lua` nạp lười module menu nên lúc khởi động KOReader
  chỉ biên dịch **2 module / 9 KB / 316 dòng** thay vì **38 module / 294 KB / 7.015 dòng**.
- **Dọn kho**: xoá `plans/reports/260904-all-feeds-audit.md` (trùng byte với
  `tests/fixtures/feeds-audit.md`, 77 KB).

## 0.0.12 — 2026-09-10

- **Tự động kiểm tra truyện & gom digest sáng** (`morning-sync.lua`): kiểm tra chương mới
  cho truyện theo dõi và gom bài báo đã tải thành digest EPUB mỗi sáng qua cổng thụ động
  `Network.ifOnline` (không bật Wi-Fi hay hiện hộp thoại); dùng rotating cursor tránh bỏ sót
  và con trỏ `(mtime, path)` không bỏ sót bài báo nào.
- **Nhập/xuất OPML RSS** (`opml.lua`): hỗ trợ định dạng chuẩn OPML 2.0, phân tích outline lồng
  nhau và giải mã entity; thêm menu "Nhập file OPML" và "Xuất file OPML" trong Báo.
- **Lịch sử & trạng thái đọc thống nhất** (`reading-state.lua`): lưu tiến độ hai lớp
  (Settings bền vững + mirror `index.json`/`manifest.json`), hiển thị nhãn `[Đang đọc %]` và
  `[Đã xong]`; bảo toàn trạng thái khi làm mới mục lục truyện tranh.
- **Tìm kiếm toàn văn offline** (`fulltext-search.lua`): quét nội dung HTML/txt cục bộ,
  hỗ trợ tìm kiếm tiếng Việt không dấu/có dấu, giới hạn bộ nhớ/kết quả chặt chẽ cho máy e-ink,
  hiển thị đoạn trích ngữ cảnh (snippet) nổi bật trên giao diện thư viện.
- **Hạn ngạch bộ nhớ & dọn rác toàn cục** (`storage.lua`): quản lý quota riêng biệt cho
  `news` (300MB), `received` (500MB), `novels` và `comics` (mặc định không giới hạn); tự động
  xóa FIFO cho báo/file nhận khi vượt trần nhưng tuyệt đối bảo vệ truyện chữ/tranh trừ khi
  chủ động bật opt-in; tự động dọn digest > 30 ngày và file `.part` mồ côi > 24 giờ.
- **Tải bản sao lưu lên OneDrive & Google Drive** (`onedrive.lua`, `gdrive.lua`): hỗ trợ
  upload thủ công bản sao lưu cài đặt và danh sách theo dõi; nâng cấp scope Microsoft sang
  `Files.ReadWrite` và Google sang `drive.readonly` + `drive.file`; có cơ chế nhận diện và
  nhắc nhở đăng nhập lại khi token cũ thiếu quyền.
- **Phục vụ OPDS toàn thư viện** (`opds.lua`, `wifi-transfer-server.lua`): mở rộng máy chủ
  Wi-Fi phục vụ toàn bộ thư viện sách (truyện chữ, truyện tranh, báo chí, sách nhận) với MIME
  chuẩn cho các app MoonReader/KOReader mobile; nâng hạn mức 512MB và chặn triệt để path traversal.

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
