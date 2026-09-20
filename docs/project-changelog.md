# Changelog

## 0.0.19 — 2026-09-20

- **Thêm 13 nguồn truyện từ `magicxlll/Z-Truyenviet.koplugin` (MIT)**: 11 nguồn truyện chữ
  (AkayTruyen, AzTruyen, Bàn Long VIP, Con Đường Bá Chủ, DualeoTruyenFull, Mê Truyện Chữ VN,
  Mê Truyện VN, Storya, TruyenC, Truyendich, XTruyen) và 2 nguồn truyện tranh (Cbunu, Dưa Leo
  Truyện). Hai plugin khác kiến trúc nên từng nguồn được viết lại theo hợp đồng
  `booxbook.source` (adapter + shim `ui/<id>.lua` + mục menu + test stub HTTP), không copy-paste.
  Registry giờ có 22 nguồn (17 chữ, 4 tranh, RSS).
- `booxbook/http.lua`: thêm `opts.max_hops` và trả luôn `Set-Cookie` của chính phản hồi redirect
  khi chạm trần hop — cần cho cổng truy cập của Cbunu, nơi cookie phiên nằm trên phản hồi 302.
- `Cbunu`: giữ cơ chế unlock của nguồn gốc (thử mật khẩu chung của site khi trang trả 403 hoặc
  trang đăng nhập) theo yêu cầu người dùng — ngoại lệ đã ghi trong `docs/development.md` và
  `docs/system-architecture.md`. Chương vẫn không đọc được thì báo khoá, không làm hỏng cả khoảng tải.
- Kiểm thử: 13 file `tests/<nguồn>.lua` mới (parseRef, danh sách/tìm kiếm, mục lục, nội dung
  chương, khoá/trống, chặn 18+, trần trang, và riêng Cbunu là nhánh unlock + 429).
  `luajit tests/run.lua` đạt toàn bộ.
- Đã GET thật từng site/API khi port (trừ vài nơi bị chặn — xem ghi chú bên dưới) và sửa lại chỗ
  Z đã lỗi thời: AkayTruyen dùng `key_word`; Bàn Long VIP 50 chương/trang và dùng trường `ord`;
  DualeoTruyenFull chuyển sang phân trang WordPress; XTruyen giải nén `data_x` (base64 bảng chữ tự
  chế → zlib); Truyendich đã đổi tên miền sang `truyendich.space` và dùng API JSON của chính site.
- **Ba nguồn của Z-Truyenviet đã bị loại sau khi GET thật, vì không dùng được** (không đưa vào menu,
  thay vì để một mục luôn báo lỗi): `Mizzya` (wordpress.com trả 403 JS challenge cho mọi client
  không-JS), `Gia Tộc Vượng Tài` (cả domain trả 401 `"Bạn cần đăng nhập"`) và `Hắc Ám Chi Các`
  (chương gửi `InitMangaEncryptedChapter` — PBKDF2-HMAC-SHA512 999 vòng + AES-256-CBC; Z giải mã bằng
  `ffi.load` hàng chục tên `libcrypto.so*`, trái quy ước `docs/development.md`, nên không có phần
  giải mã thì nguồn chỉ duyệt được chứ không tải được ảnh).
- **`Dưa Leo Truyện`** parse đã đối chiếu với HTML thật qua proxy: tên miền chính
  `dualeotruyenhn.com` nay 301 sang `dualeotruyenvt.com`, nên khả dụng phụ thuộc mạng của bạn.

## 0.0.18 — 2026-09-20

- **Xoá nốt thư mục cài đặt của KOReader khi đóng tài liệu**: `transient.cleanup` (Đọc xong
  không lưu) nay xoá cả `<tên>.sdr/` — nơi KOReader ghi `metadata.cbz.lua` cho tài liệu — chứ
  không chỉ file `.cbz` và `.cbz.meta.json`. Trước đó mỗi lượt đọc tạm vẫn để lại một thư mục
  ~2,6 KB mồ côi (đúng cái còn sót ghi ở mục 0.0.17), và lần tải lại chương sau đó sẽ thừa hưởng
  vị trí đọc cũ. Tên thư mục suy ra từ chính chương vừa xoá nên không thể đụng file khác, và
  `Storage.emptyDir` không làm gì khi thiếu `lfs` (không đoán bừa).
- Kiểm thử: `tests/transient.lua` thêm ca thư mục `.sdr` cho cả tên chuẩn lẫn tên ẩn
  `.chap-N-first.cbz`, và ca "cleanup bị từ chối thì không đụng thư mục cài đặt".
  `luajit tests/run.lua` đạt toàn bộ.
- Đã chạy thật trên Galaxy S24 FE (KOReader v2026.07): chương ≤ 12 trang (*Ông Xã Thú Tính*
  chương 1) khi đóng tài liệu thì `chap-1.cbz` + `chap-1.cbz.meta.json` + `chap-1.sdr` cùng biến
  mất, còn `chap-0.cbz` và `chap-0.sdr` (chương có sẵn, không thuộc phiên tải) vẫn nguyên; chương
  126 trang (*Hoa Sơn Tái Khởi* chương 2, bản 12 trang ẩn) sau khi đóng cũng sạch hoàn toàn —
  `.chap-2-first.cbz` và `.chap-2-first.sdr` đều không còn.

## 0.0.17 — 2026-09-20

- **Trần thời gian cho mọi hành động**: `booxbook/http.lua` có ngân sách theo hành động
  (`beginOperation`/`endOperation`/`remaining`/`expired`). Mặc định 20 giây cho một hành động,
  300 giây cho việc tải dung lượng lớn (có tiến trình và nút hủy). Ngân sách chỉ nới ra khi
  lồng nhau nên tải một khoảng chương vẫn giữ trần dài. Hết ngân sách thì dừng với câu
  "Việc tải mất quá nhiều thời gian nên đã dừng lại." thay vì treo.
- Timeout một request 10s→**6s** (maxtime 30s→15s) và được cắt theo thời gian còn lại;
  DoH từ **60s → 5s** (query) / **8s** (handshake TLS), tối đa 3 địa chỉ mỗi host.
  Đây là nguyên nhân chính của những lần đứng hàng phút khi host chết.
- `RateLimit.wait` nhận `max_ms`: không ngủ quá thời gian còn lại, trả `false` để caller dừng
  trước khi gửi request sớm. Mục lục Truyện Full/TVTruyen thêm trần **60 trang** và dừng khi
  hết ngân sách, giữ phần đã đọc (`series.truncated`).
- **Lỗi luôn là câu cho người dùng**: thêm `booxbook/fault.lua`, mọi thông báo đi qua
  `Fault.notify`. Chuỗi chứa chi tiết mã nguồn (`file.lua:dòng`, `stack traceback`, `attempt to …`)
  được thay bằng câu tiếng Việt (`connection refused` → "Không kết nối được tới máy chủ.",
  `timeout` → "Máy chủ phản hồi quá chậm.", 403/404/429/5xx, `operation-timeout`…); mọi câu
  đã đọc được thì giữ nguyên. Guard `busy` không còn im lặng mà báo "Đang tải, vui lòng chờ."
- Kiểm thử: thêm `tests/fault.lua` (map lỗi, idempotent, không lộ `file.lua:`),
  `tests/http-budget.lua` (ngân sách, cắt sleep, ngân sách lồng nhau, `runWithBudget`/
  `withBudget`) và ca trần mục lục trong `tests/truyenfull.lua`.
- Đã chạy thật trên Galaxy S24 FE: host chết hiện "Không kết nối được tới máy chủ." trong
  vài giây (trước đó là `…/doh.lua:102: …/doh.lua:41: connection refused`); mở mục lục một bộ
  dài trên truyenfull.live kết thúc sau ~20–30 giây và UI dùng được (trước đó treo vài phút →
  ANR). Không có lỗi Lua trong logcat.
- Sau review đối kháng, sửa thêm: connect TLS/DoH nay bị cắt theo ngân sách và chỉ fallback
  DNS hệ thống khi không có ngân sách (trước đó một host chết vẫn có thể chạm ~35–40s);
  `Fault.message` không còn chạy mẫu con trên câu đã đọc được ("chỉ lấy được 500 chương đầu"
  từng bị đổi thành "Máy chủ đang lỗi"); mục lục có trần riêng `TOC_TIMEOUT = 60` thay vì
  20s chung (MeTruyenCV thêm `truncated` khi hết ngân sách); `follow` không còn hiện "nil";
  ngân sách được lấy lại mẫu sau khi chờ rate-limit và cả nhánh 403; `morning-sync` bọc ngân
  sách; `main.lua` báo khi không kiểm tra được cập nhật thay vì im lặng.
- Chưa làm (Phase 2): fetch vẫn đồng bộ trên main thread, nên ngân sách 20s vẫn có thể bị coi là
  ANR nếu chạm liên tục trong lúc chờ. Cần coroutine + `nextTick` giữa các request.

### Phase 2 — hết ANR cho các đường load

- `booxbook/async.lua`: coroutine + nhường `UIManager:nextTick` giữa các bước mạng; `Http.request`
  và vòng địa chỉ của DoH gọi `Async.step()`. Ngoài `Async.run` thì no-op, nên caller cũ (morning-sync,
  cloud, test) không đổi hành vi.
- Áp dụng cho danh sách / tìm kiếm / phân trang / **mục lục** (`onlineResumable` trong novels và
  comic-page). Đường **tải** giữ `Trapper:wrap` đồng bộ để còn dòng tiến trình và chạm-để-huỷ.
- Hạ burst chặn lớn nhất: request 6s→**5s** (maxtime 15s→**10s**), DoH 4s/5s (trước 5s/8s).
- Kiểm chứng: probe trực tiếp trên module thật cho thấy 2 request → **2 lần nhường UI**, giá trị trả
  về nguyên vẹn, caller đồng bộ không đổi; `luajit tests/run.lua` đạt toàn bộ (fixture vốn chạy theo
  hàng đợi `nextTick`, nên phần async được chạy thật trong test); trên Galaxy S24 FE chạm 6 lần
  trong lúc tải mục lục **không ANR**, logcat không có lỗi Lua.
- Chưa xác nhận: một lượt mục lục **thành công nhiều trang qua mạng thật** trên đường async chưa
  quan sát được trên thiết bị (truyenfull.live đang rate-limit những lần thử hôm nay); thông báo lỗi
  hiện ra giống hệt bản đồng bộ trước đó.
- Đường tải không còn là nguồn ANR riêng: đọc source KOReader cho thấy `Trapper` cũng chạy trên
  coroutine và `Trapper:info` gọi `coroutine.yield()` (0,1s, để bắt chạm huỷ) khi widget hiện hành là
  InfoMessage — hộp "Đang tải…" của plugin là InfoMessage, nên đường tải vốn đã nhường UI sau mỗi
  ảnh (khớp với lượt tải CBZ 1,5MB trên máy vẫn hiện tiến trình và không ANR). Hạ nốt
  `DEFAULT_TIMEOUT` 5s→**4s** để một request đơn lẻ nằm dưới ngưỡng watchdog ~5s của Android;
  `maxtime` giữ 10s cho luồng chậm nhưng đang chảy. Vậy đơn vị chặn lớn nhất ở mọi đường mạng giờ là
  một request.

### Đọc chương truyện tranh không giữ file

- **Công tắc mới "Đọc xong không lưu"** (mục cuối menu nguồn truyện tranh, ví dụ
  **Truyện → TruyenQQ**; lưu ở `transient_comics`, mặc định tắt): chương **tải trong phiên này**
  được xoá ngay khi đóng tài liệu, nên đọc xong không để lại file. Chương đã có trong thư viện từ
  trước **không** bị xoá — chỉ file do chính phiên hiện tại tải mới được đánh dấu, và công tắc được
  đọc lại lúc xoá nên tắt giữa chừng vẫn giữ file.
- **Chương dài mở sau 12 trang đầu**: chương nhiều hơn 12 trang được tải 12 trang đầu rồi mở ngay,
  phần còn lại tải khi chọn lại chương đó (`FIRST_PAGES = 12`, ngân sách chỉ dùng một lần mỗi
  chương mỗi phiên). Bản cắt dở **không** chiếm tên chuẩn: nó nằm ở tên ẩn `.chap-N-first.cbz` cùng
  thư mục, nên `savedPath()` không bao giờ coi một chương cụt là đã tải xong và tên chuẩn vẫn trống
  cho lần tải đủ sau đó. Thông báo "Đang mở 12 trang đầu — chọn lại chương để tải đủ." giải thích
  điều vừa xảy ra.
- **Công tắc riêng cho ảnh bìa trong danh sách** (`list_covers`, mục cuối **Cài đặt** — "Ảnh
  bìa trong danh sách (tắt cho nhanh)", mặc định bật): tắt để danh sách chữ không phải chờ ảnh.
- **Kiểm chứng trên Galaxy S24 FE (KOReader v2026.07 Android), 20/09/2026** — hai điều trước đó chỉ
  có test đơn vị, nay xác nhận trên máy thật:
  - *Chương dài*: **Hoa Sơn Tái Khởi** chương 2 (126 trang) tải đúng 12 trang vào
    `.chap-2-first.cbz` (1,29 MB) kèm tiến trình "Tải ảnh: 8/126 — chạm để hủy", **không** sinh
    `chap-2.cbz`, KOReader mở đúng file ẩn và hiện "Đang mở 12 trang đầu — chọn lại chương để tải
    đủ." (thấy được sau thông báo "Opening file" của KOReader).
  - *Xoá khi đóng*: đóng tài liệu bằng nút **File browser** trên thanh menu của KOReader → file ẩn
    **biến mất**; ca tải đủ (chương ≤ 12 trang, bộ **Ông Xã Thú Tính**) cho kết quả tương tự với
    `chap-1.cbz` (1,05 MB), trong khi `chap-0.cbz` có sẵn từ phiên trước **vẫn còn nguyên**.
  - Hộp thoại **Đọc tiếp nối** của plugin thay đúng hộp mặc định của KOReader ở trang cuối; lượt
    trước đó tưởng lỗi chỉ vì một cú chạm thừa đóng hộp của plugin.
  - `luajit tests/run.lua` đạt toàn bộ; logcat không có lỗi Lua, không ANR.
- Còn sót: KOReader vẫn giữ thư mục cài đặt `.chap-N-first.sdr` (`metadata.cbz.lua` ~2,6 KB) sau khi
  file ẩn bị xoá. Chưa dọn trong bản này (đã dọn ở 0.0.18).

## Chưa phát hành — dọn trùng lặp nguồn

- **Một trang UI chung cho mọi nguồn**: thêm `booxbook/ui/source-page.lua` (truyện chữ) và
  `booxbook/ui/comic-page.lua` (truyện tranh). Bảy file `ui/truyenfull|tvtruyen|metruyencv|`
  `wattpad|sangtacviet|truyenqq|truyentuoitho.lua` từ chỗ trùng nhau gần như toàn bộ
  (~900 dòng) nay chỉ còn một dòng shim. Tổng plugin còn 14.706 dòng (từ 15.056): bỏ 1.082
  dòng code trùng, thêm 745 dòng (hai trang UI chung + metadata trong adapter).
- **Adapter tự mô tả**: mỗi nguồn khai `view` (menu duyệt, `base_url`, cover referer,
  gợi ý ô tìm kiếm, mẫu nhận URL), `locate` (ref → thư mục lưu), `chapterRef`
  (chương → `series_id`/`chapter_id`); nguồn tranh thêm `seriesUrl`. Sangtacviet giữ
  `base_url` động vì tên miền đổi lúc chạy.
- **Registry thành điểm điều phối duy nhất**: thêm `Source.ofKind`, `Source.findRef`,
  `Source.locate`. Bỏ chuỗi `if source_id == …` trong `novel-download.lua` (2 chỗ),
  `comic-download.lua` (`adapterFor`, `resolveComicNext`, quét thư mục) và
  `continuation.lua` (2 chỗ, gồm lần đoán URL bộ truyện).
- Hành vi giữ nguyên: đúng số mục menu, đúng thứ tự, đúng câu thông báo, cùng ngữ nghĩa
  busy guard và `nextTick`. `luajit tests/run.lua` đạt toàn bộ.
- Sau review đối kháng, siết thêm: mở lại menu nguồn xóa được cờ busy bị kẹt (như bản cũ),
  gợi ý ô nhập đi qua `_()` để xgettext vẫn bắt, câu "Đang tải/lấy tập…" giữ nguyên theo
  từng nguồn qua `view.loading`, `base_url` dạng hàm được resolve (chưa nguồn tranh nào
  dùng), và `continuation`/`comic-download` chỉ nhận adapter `kind == "comic"` trước khi
  ghi manifest hay gọi UI.
- Đã chạy thật trên Galaxy S24 FE (KOReader Android 15) ngày 20/09/2026: menu **Truyện →**
  Truyện Full (3 mục, lưới bìa thật), MeTruyenCV (2 mục, lưới qua API), TruyenQQ (3 mục) và
  Truyện Tuổi Thơ (6 mục) mở đúng như bản cũ; ô tìm kiếm hiện đúng tiêu đề + gợi ý tiếng Việt;
  tải thật 1 tập CBZ TruyenQQ (`chap-0.cbz` 1,5 MB + `chap-0.cbz.meta.json` +
  `manifest.json`, `source_id = "truyenqq"`) và KOReader mở ngay tập đó; tải thật 1 chương
  MeTruyenCV ra `index.json` (`id = 104789` do `adapter.locate`, khoá chương `12935750` do
  `adapter.chapterRef`) kèm EPUB 180 KB. logcat không có lỗi Lua nào.
- Phát hiện **sẵn có**, không do refactor (đã đối chứng bằng cách chạy lại đúng thao tác với
  gói trước refactor, treo y hệt): mở mục lục một bộ dài trên truyenfull.live đứng ở
  "Đang lấy mục lục…" và gây **ANR** vì fetch chạy đồng bộ trên main thread; `truyentuoitho.com`
  hiện chết (curl từ máy tính cũng bị từ chối cổng 443) nên vào nguồn này cũng ANR. Việc cần
  làm riêng: chuyển fetch ra coroutine để không chặn UI và hạ timeout cho host chết.

## 0.0.16 — 2026-09-15

- **Tìm toàn văn trong bài báo đã tải**: thêm **Báo → Tìm trong tin đã tải**, dùng lại
  tìm kiếm toàn văn sẵn có nhưng giới hạn trong `koreader/booxbook/news/`. Không phân biệt
  dấu, kết quả hiện trích đoạn quanh từ khóa rồi mở bài bằng KOReader. Trần mặc định
  200 file/30 kết quả, nên máy có rất nhiều bài có thể chưa quét hết.
- **CSS đọc trên e-ink cho mọi tài liệu sinh ra**: bài báo, chương tải về và chương EPUB
  nay nhúng chung một khối `<style>` (ảnh vừa bề rộng, `figure`/`figcaption`, `blockquote`,
  bảng, `hr`). Cố ý **không** đặt `font-size`, `line-height`, `text-align` để cài đặt
  typography của KOReader vẫn quyết định.
- **Duyệt theo thể loại cho TVTruyen và Truyện Full**: mỗi nguồn có mục **Thể loại**
  (TVTruyen 63 thể loại, Truyện Full 46) trỏ thẳng vào cây `/the-loai/…` của site; tiêu đề
  lưới hiện tên thể loại. Thể loại 18+ (Sắc, Sắc Hiệp, Adult, Mature, Ecchi, Incest,
  Netorare) chỉ hiện khi bật **Nội dung 18+**, và `browse()` chặn lại lần nữa nếu menu
  còn cũ.
- Kiểm thử LuaJIT: tìm kiếm tin offline và thứ tự tham số `root`/`title`, URL thể loại
  theo từng nguồn, chặn 18+, key thể loại trùng hoặc không an toàn trong URL, entry thể
  loại dị dạng, root tìm kiếm không tồn tại, CSS nhúng không đụng typography. Toàn bộ
  `tests/run.lua` đạt.
- Đã chạy thật trên Samsung S24 FE (KOReader Android): tìm `ukraine` ra 30 kết quả/2 trang
  trong 46 bài đã tải; lưới **Truyện Full — Tiên Hiệp** và **TVTruyen — Học Đường** tải
  truyện thật kèm bìa; bật/tắt 18+ đổi đúng danh sách; bài mới ghi ra máy có khối `<style>`;
  không có `crash.log` hay lỗi Lua trong logcat.
- Chưa gắn thể loại cho DocLN, Wattpad, MeTruyenCV, Sangtacviet: các site này không có trang
  thể loại dùng trực tiếp (Wattpad chỉ có `filter=hot/featured/new`, MeTruyenCV lọc qua API,
  Sangtacviet theo `sort`). Adapter nào thêm bảng `genres` là tự có menu.

## 0.0.15 — 2026-09-15

- **Sửa lỗi gửi sách qua Wi-Fi bị che thành "Mất kết nối" (ảnh hưởng cao)**: máy chủ trả lời
  từ chối (trùng tên, sai mã phiên, file quá lớn…) rồi đóng socket ngay khi điện thoại còn
  đang gửi body, khiến kernel gửi RST và trình duyệt báo lỗi mạng thay vì thông báo thật —
  lặp lại mỗi lần gửi. Nay máy chủ đọc nốt phần body còn lại (theo `Content-Length`, tối đa
  `Upload.MAX_BYTES`) rồi mới đóng, nên mọi định dạng file đều nhận được đúng lý do.
- **Báo lỗi chính xác ở cả hai phía**: trang gửi sách nêu tên file và nói rõ máy đọc không
  trả lời (thay câu chung `Mất kết nối`); màn hình **Kiểm tra kết nối và kết quả** trên máy
  đọc thêm dòng **Lần từ chối gần nhất** kèm mã và thông báo (`409: Sách trùng tên…`).
- Kiểm thử hồi quy LuaJIT: từ chối khi body mới nhận một phần (401 `drain = 7`, 409
  `drain = 4`), `/queue` không chờ drain, chuỗi chẩn đoán trên máy đọc; cả ba assertion mới
  đều đỏ trước khi sửa. Toàn bộ `tests/run.lua` đạt.

## 0.0.14 — 2026-09-14

- **Sửa Wi-Fi trên Kindle (ảnh hưởng cao)**: phiên nhận hiện link nhưng thiếu quy tắc
  tường lửa cho TCP vào/ra, khiến trình duyệt có thể không tới được trang gửi sách.
  Mở đúng cổng đã bind theo cách HTTP Inspector của KOReader; gỡ quy tắc khi dừng,
  suspend hoặc lỗi poll. Nếu thiết lập thất bại, đóng listener, hoàn tác phần đã mở
  và báo lỗi rõ ràng. Android/Kobo không chạy lệnh tường lửa.
- Kiểm thử hồi quy LuaJIT: mở/đóng cổng, cổng dự phòng, lỗi từng bước và cleanup;
  toàn bộ `tests/run.lua` đạt. Chưa xác nhận trên Kindle thật.

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
