# Hướng dẫn sử dụng

Màn hình chính hiện phiên bản ngay dưới tiêu đề. Điều hướng dùng **Quay lại / Trước / Sau** ở chân trang.

## Báo RSS

- **Báo → Báo Việt / Báo Nước Ngoài → chọn đầu báo → chọn danh mục**: chỉ lấy danh sách tiêu đề RSS khi chọn danh mục, chưa tải nội dung các bài.
- 17 đầu báo, 633 kênh RSS có bài trong lượt kiểm tra ngày 04/09/2026. Xem [phạm vi và nguồn danh mục](news-categories.md).
- Đã bỏ **Nguồn tin** và toàn bộ công tắc bật/tắt. Thiết lập tắt nguồn từ bản cũ không còn ẩn danh mục.
- **Chạm tiêu đề bài**: lấy nội dung bài đó và mở bằng KOReader; nếu lấy toàn bài lỗi, dùng bản tóm tắt RSS/Atom.
- Trang chi tiết có tiêu đề ở đầu bài; ảnh trong nội dung/tóm tắt được lưu cục bộ chỉ khi mở bài. Ảnh lỗi không chặn đọc chữ. Hỗ trợ JPEG, PNG, GIF, WebP; tối đa 20 ảnh, 2 MiB/ảnh, 10 MiB/bài.
- **Báo → Số bài mỗi danh mục**: chọn từ 1 đến 20 tiêu đề hiển thị; không giới hạn số danh mục.
- **Báo → Tin đã tải**: đọc lại các bài đã mở/lưu, không cần tải lại. Bài cũ vẫn được giữ.
- **Báo → Thêm RSS tùy chỉnh**: thêm URL bắt đầu bằng `http://` hoặc `https://`.
- RSS bạn thêm nằm trong nhóm riêng **Báo → RSS tùy chỉnh**. Kênh rỗng/lỗi chỉ báo thông báo; không làm mất danh sách danh mục.
- Dùng User-Agent desktop; riêng VnExpress có cookie chọn giao diện desktop để tránh RSS rỗng. Vẫn giãn cách lượt tải và dừng khi máy chủ trả HTTP 429; không cam kết loại bỏ mọi rate limit.
- Chỉ bài được chọn mới lưu HTML tại `koreader/booxbook/news/<feed-id>/`. Mở từ danh sách online sẽ lấy lại nội dung bài đó.
- RSS tùy chỉnh chỉ đọc nội dung/tóm tắt trong feed, không tự lấy toàn văn website.

## DocLN

- **Truyện → DocLN**: nhập từ khóa; chọn truyện để xem các tập và chương. Có **Trang tiếp** khi còn kết quả.
- **Tải chương** (icon menu góc trái thanh tiêu đề mục lục): **Tải khoảng chương** (nhập từ–đến) hoặc **Tải toàn bộ chương** (xác nhận rồi tải 1…N). **Chương đã tải (offline)** nằm trong danh sách mục lục: mở HTML đã lưu từ `index.json`, không cần mạng. Chạm một chương để chỉ tải chương đó; chọn chương trong kết quả tải để mở bằng KOReader.
- Mỗi lượt mặc định gợi ý tối đa 20 chương; hơn 50 chương cần xác nhận. Tải tuần tự, cách nhau ít nhất 1,5 giây; HTTP 429 dừng lượt tải.
- Lưu HTML từng chương và `index.json` tại `koreader/booxbook/novels/docln/<loại-truyện-id>/`. Tên file dùng ID chương ổn định. Đọc lại offline từ mục lục truyện hoặc trình quản lý file KOReader.
- Tự chuyển giữa `docln.net`, `ln.hako.vn`, `docln.sbs` khi lỗi mạng/trang; nhớ tên miền hoạt động. Dùng **Cookie DocLN** đã có trong Cài đặt nếu cần.
- Ẩn kết quả được đánh dấu 18+ khi thiết lập tắt; kiểm tra lại trên trang truyện. Chương khóa/404/không có chữ hiển thị lý do bỏ qua; lỗi mạng hoặc ghi file giữ lại các chương đã lưu.
- Hỗ trợ nội dung công khai được đóng gói trong HTML theo cách của [Nekori LNHako](https://github.com/Yuneko-dev/Nekori-plugins/tree/c29b05de71bf71e5321d6488014d027d7b2f68cb/plugins/vietnamese/LNHako). [Thông báo MIT](../booxbook.koplugin/THIRD-PARTY-NOTICES.md). Xuất EPUB và tải ảnh chương để bước sau.

## Wattpad

- Danh sách duyệt và kết quả tìm kiếm hiển thị grid 2×3 bìa/tên truyện như DocLN. Nút Trước/Sau chuyển màn hình rồi lấy trang API tiếp theo; bìa chỉ tải khi xuất hiện trên màn hình, lỗi ảnh vẫn đọc được tên truyện.
- **Truyện → Wattpad**: duyệt Nổi bật / Đề cử / Mới (tiếng Việt). Chạm kính lúp trên thanh tiêu đề để tìm kiếm hoặc nhập URL `/story/<id>`; nút này cũng có ở danh sách kết quả, giống DocLN. Khi API danh sách lỗi vẫn có thể nhập URL; Đề cử có thể rỗng.
- Mục lục dùng chung DocLN: icon menu góc trái → khoảng / toàn bộ; **Chương đã tải (offline)** trong danh sách. Lưu HTML + `index.json` tại `koreader/booxbook/novels/wattpad/<id>/`.
- Dùng **Cookie Wattpad** đã lưu; không đăng nhập bằng mật khẩu hay mở khóa chương trả phí. Ẩn truyện 18+ hoặc chưa rõ phân loại khi thiết lập 18+ tắt. Bỏ qua bản nháp, chương xóa/khóa/trống; HTTP 403/429 dừng lượt tải.
- Giãn cách ít nhất 1,6 giây; tự giải nén gzip bằng zlib của KOReader. Chỉ lưu chữ; ảnh và EPUB để bước sau.

## Sangtacviet

- **Truyện → Sangtacviet** luôn hiện trong menu. Lần đầu chạm sẽ hỏi xác nhận (cảnh báo dịch máy); sau đó mở grid. Tắt lại bằng **Cài đặt → Bật Sangtacviet**.
- Duyệt **Mới cập nhật** / **Lượt xem** dạng grid bìa; kính lúp nhận từ khóa hoặc URL `/truyen/{host}/{sty}/{bookid}/`.
- Tải chương qua AJAX (`sajax=readchapter`) kèm Referer + cookie phiên; giãn cách ≥ 2 giây. Bỏ qua VIP; captcha / rate-limit / chương trống sau lỗi dừng cả lượt tải.
- ID truyện là `{host}-{bookid}` (cùng bookid có thể trùng giữa nguồn gốc). Lưu HTML tại `koreader/booxbook/novels/sangtacviet/{host}-{bookid}/`. Chương id dài (fanqie) giữ dạng chuỗi, không `tonumber`. Icon menu trên mục lục mở **Tải khoảng / toàn bộ** như DocLN; tải toàn bộ có thể chậm vì giãn cách ≥ 2 giây và dừng khi captcha/rate-limit.
- Chỉ dùng cá nhân; nhiều bản dịch máy. Không vượt captcha/VIP. Bảng glyph PUA (sangtac/dich) theo [Nekori SangTacViet](https://github.com/Yuneko-dev/Nekori-plugins/tree/master/plugins/vietnamese/SangTacViet) — [MIT](../booxbook.koplugin/THIRD-PARTY-NOTICES.md).

## Dữ liệu trên máy

| Loại | Đường dẫn |
|---|---|
| Bài báo đã mở | `koreader/booxbook/news/<feed-id>/` |
| Chương truyện | `koreader/booxbook/novels/<nguồn>/<id>/` |
| Cài đặt + cookie | `koreader/settings/booxbook.lua` |
