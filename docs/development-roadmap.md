# Lộ trình phát triển

## Thêm nguồn truyện từ Z-Truyenviet — 2026-09-20

Port các nguồn truyện mà `magicxlll/Z-Truyenviet.koplugin` (MIT) có mà BooxBook chưa có,
viết lại theo hợp đồng `booxbook.source` (hai plugin khác kiến trúc, không copy-paste).
Đã thêm 13 nguồn (11 chữ + 2 tranh); 3 nguồn bị loại vì GET thật cho thấy không dùng được.
Registry: 22 nguồn (17 chữ, 4 tranh, RSS).

- [x] Hạ tầng: đăng ký adapter trong `source.lua`, shim `ui/<id>.lua`, mục menu `main.lua`, test vào `tests/run.lua`.
- [x] 11 nguồn truyện chữ: akaytruyen, aztruyen, blhvip, conduongbachu, dualeotruyenfull,
      metruyenchuvn, metruyenvn, storyaclick, truyenc, truyendich, xtruyen.
  - [x] `metruyenvn` (Mê Truyện VN): kiểm live — `.comic-item-box`, `/page/N/`, `.chapter-table`,
        `/chuong-<n>-<id>/`, `#view-chapter`, backlink `#post-category-link`; search AJAX + fallback `/?s=`.
  - [x] `akaytruyen`: chạy parser thật trên HTML thật — Hot 31 / Đang ra 27 / Hoàn thành 4 (đủ cover),
        8 trang × 50 chương, mục lục mới-nhất-trước được đảo lại; `search-chapters` trả 422 khi rỗng → fallback.
  - [x] `blhvip`: API `api.blhvip.vn` — 50 chương/trang, thứ tự theo `ord`, `/v1/story/<slug>` 403 nên metadata từ HTML.
  - [x] `storyaclick`: `api/v1/stories`, `chapters/story/<slug>?minimal=true`, `chapters/<slug>/<chap>` có `content`.
  - [x] `dualeotruyenfull`: listing 24 card, story 24 chương, chapter `#chapter-content` 90 đoạn.
  - [x] `aztruyen`: TOC `li.listc` (148 mục), chapter `div.chapter-content` + 122 đoạn.
  - [x] `xtruyen`: tự viết decoder Python đối chiếu — `data_x` 8060 ký tự → base64 bảng chữ tự chế → zlib → 17090 byte HTML.
  - [x] `truyendich`: `truyendich.space/api/novels/search` + `/chapters` (6960 chương), story `/doc-truyen/<slug>`,
        chapter `#original-content-tab` 43 đoạn. `.ai`/`.fit` vẫn nhận trong `parseRef`.
  - [x] `truyenc`: story 58 chương, chapter `.story-content` 30 đoạn, 34 thể loại (7 nhóm 18+);
        không có tìm kiếm phía server nên `capabilities.search = false`.
  - [x] `conduongbachu`: WordPress REST trả JSON hợp lệ; chapter `.entry-content` 86 đoạn.
  - [x] `metruyenchuvn`: `latest` fallback về trang chủ khi `/danh-sach/truyen-moi` 404 (34 truyện),
        `popular`/`full` 20 truyện, search lọc đúng (“Tinh Thần Đại Đạo” đầu tiên).
- [x] 2 nguồn truyện tranh: cbunu, dualeo.
  - [x] `cbunu`: mục lục `.works-chapter-list` sắp lại theo thứ tự đọc, chỉ nhận ảnh host của site;
        `Http.post(..., { max_hops = 0 })` để đọc `Set-Cookie` trên chính phản hồi 302.
  - [x] `dualeo`: `dualeotruyenhn.com` nay **301 → `dualeotruyenvt.com`**; host đích không kết nối được
        từ mạng đã kiểm nên khả dụng phụ thuộc mạng người dùng. Parse đã đối chiếu HTML thật qua proxy.
- [x] **Loại 3 nguồn sau khi GET thật cho thấy không dùng được** (xóa adapter + shim + test + mục menu):
  - `mizzya`: wordpress.com trả 403 JS challenge cho mọi client không-JS, kể cả khi gửi đủ header như bản gốc.
  - `giatocvuongtai`: cả domain lẫn `/api/public/*` trả 401 `"Bạn cần đăng nhập để truy cập nội dung này."`
  - `haccbl`: chương gửi `InitMangaEncryptedChapter` (PBKDF2-HMAC-SHA512 999 vòng + AES-256-CBC);
    Z giải mã bằng `ffi.load` hàng chục tên `libcrypto.so*`, trái quy ước `docs/development.md`.
    Không có phần giải mã thì nguồn chỉ duyệt được chứ không tải được ảnh → bỏ.
    Nếu sau này muốn có lại: làm thuần Lua (PBKDF2-HMAC-SHA512 + AES-256-CBC), kiểm offline bằng
    vector chuẩn và ciphertext thật.
- [x] `truyenc`: gate thể loại 18+ qua `Settings.adultContent()`.
- [x] Test stub HTTP mỗi nguồn; `luajit tests/run.lua` xanh (13 file test mới).
  - [x] `cbunu`: parseRef/parseList/browse/search/getSeries/parseChapter + unlock + 429 + trần 600 trang.
- [x] Smoke test thật có mạng cho từng nguồn (chỉ GET trang công khai). Kết quả ghi ở trên.
- [x] Ghi chú ngoại lệ: `cbunu` giữ cơ chế unlock (dò mật khẩu chung của site) theo yêu cầu
      người dùng — khác quy ước "không vượt paywall" trong `docs/development.md`; ghi rõ trong docs.
- [x] Cập nhật README, `website/index.html`, `docs/usage.md`, `docs/system-architecture.md`,
      `_meta.lua` (0.0.19) và changelog.
- [ ] Smoke test trên thiết bị thật (Boox/Kindle/Kobo) cho các nguồn mới.
- [x] Không đưa vào đợt này: `dilib` (thư viện số/GDrive, cả phim/nhạc) và `tve4u`
      (ebook XenForo, bắt buộc đăng nhập) — không phải nguồn truyện, khác hẳn domain.

## Nhận sách Wi-Fi trên Kindle — 2026-09-14

- [x] Bổ sung mở/đóng tường lửa theo cổng thực tế, hoàn tác khi thiết lập lỗi.
- [x] Kiểm thử hồi quy Wi-Fi và toàn bộ suite bằng LuaJIT.
- [ ] Xác nhận trên Kindle thật: mở trang từ điện thoại, gửi EPUB, dừng phiên.

## Google Drive + Digest + Follow-up — 2026-09-10

- [x] Google Drive download-only: Device flow, refresh/đăng xuất, duyệt thư mục, tải `.part` + rename, không ghi đè.
- [x] Digest báo ngày: gom tối đa 20 HTML mới nhất thành EPUB trong `received/`.
- [x] Theo dõi truyện (kiểm tra thủ công), tìm sách offline + quota, OPDS `/opds` (file ≤32MB), hàng đợi `/queue`, TruyenQQ, sao lưu cài đặt, check cập nhật 24h.
- [x] LuaJIT regression suite xanh gồm test Drive/digest/follow/library/OPDS/queue mới.
- [x] Khép vòng đợt 1: UI tiêu thụ hàng đợi (tải/xóa từng link), UI khôi phục sao lưu,
  auto-check GitHub thầm 1 lần/ngày + badge `• mới!` (không hỏi bật Wi-Fi).
- [x] Sửa crash mở follow list (`for _,` che gettext), bìa WebP không còn đánh chìm EPUB,
  tự đóng gói EPUB khi tải lại toàn chương-cũ — đều verified trên Samsung + test hồi quy.
- [x] TruyenQQ viết lại cho `truyenqqko.com` (adapter + UI + download riêng, truyenqq.net cũ
  chặn 429/anti-bot) + tổng quát `comic-download` theo adapter.
- [x] Tự động tiếp nối tập đọc (EndOfBook) cho cả truyện tranh (CBZ) và tiểu thuyết (EPUB/HTML):
  hỏi mở hoặc tải tiếp tập kế tiếp qua sidecar `.meta.json` + `manifest.json` (comic)
  và `index.json` (novel).
- [x] Fix tiếp nối: giữ dialog KOReader mặc định cho sách ngoài BooxBook, không ghi
  sidecar terminal khi thiếu manifest, chặn `next_url` cross-series, validate
  `Novels.downloadChapter` + báo hết truyện khi quá số chương mục lục mới.
- [ ] Smoke test trên Boox: đăng nhập Drive, tải sách, digest, OPDS/queue, CBZ TruyenQQ,
  khôi phục sao lưu, badge cập nhật.

## OneDrive download-only — 2026-09-09

- [x] Device Code OAuth, refresh/đăng xuất và Graph folder listing.
- [x] Chỉ hiện định dạng sách hỗ trợ; tải `.part` rồi rename, không ghi đè.
- [x] Chạy toàn bộ LuaJIT regression suite và test OneDrive mới.
- [ ] Smoke test đăng nhập, phân trang và tải sách thật trên Boox.
- [ ] Thiết kế Google Drive sau khi OneDrive được xác nhận trên thiết bị.

## Gửi sách qua Wi-Fi — 2026-09-08

- [x] Mục riêng, địa chỉ web, mã phiên và QR dùng widget KOReader.
- [x] Trang web mobile/desktop, nhiều sách, tiến độ và kết quả từng file.
- [x] Nhận stream, không ghi đè, kiểm đường dẫn/size/origin/token, dọn file dở.
- [x] Kiểm cú pháp và hồi quy LuaJIT; TCP 8 MiB đối chiếu byte với transport desktop.
- [x] Sửa chọn IP Wi-Fi, khóa mã sai theo IP, callback Wi-Fi muộn; báo nhận thành công.
- [ ] Smoke test LuaSocket native, QR, Wi-Fi, suspend trên Boox trước phát hành.

## Tối ưu tải và EPUB truyện — 2026-09-08

- [x] Bỏ qua chương đã có file; file thiếu được tải lại thay vì tin riêng index.
- [x] Backup/fallback `index.json` có kiểm tra schema và đúng series.
- [x] Tạo EPUB theo khoảng từ HTML đã tải, không tải lại và luôn giữ HTML.
- [x] Kiểm thử download, phục hồi index, EPUB thủ công, UI và toàn bộ hồi quy.
- [ ] Smoke test tải lặp, fallback index và EPUB thủ công trên Boox thật.

## Truyện Tuổi Thơ CBZ — 2026-09-07

- [x] Bản thử nhập URL tập, parser ảnh, tải tiếp và đóng gói CBZ.
- [x] Menu, tiến độ/hủy, mở ReaderUI, giữ file tạm khi lỗi và đọc offline qua Thư viện.
- [x] Kiểm thử LuaJIT: URL/redirect, ảnh thiếu, tải tiếp, hủy, lỗi archive, UI và hồi quy.
- [x] Smoke test CBZ native với wrapper KOReader/libarchive Windows và hai WebP thật; parser tập mẫu đủ 205 trang.
- [ ] Kiểm tra CBZ WebP và thao tác trên Boox thật trước khi phát hành.
- [x] Duyệt grid/tìm kiếm phân trang, thông tin bộ và mục lục AJAX.
- [x] Tải một/khoảng/toàn bộ tập, mở tập bất kỳ, danh sách offline và giữ CBZ cũ.
- [x] Kiểm tra parser bằng HTML thật: hai trang danh sách, tìm có/trống/trang 2, mục lục 28 tập.
- [x] CBZ WebP/fit-page trên điện thoại Samsung Android; Boox vẫn cần kiểm tra riêng.

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
