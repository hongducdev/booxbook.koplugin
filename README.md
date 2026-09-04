# BooxBook

Plugin [KOReader](https://github.com/koreader/koreader) để đọc báo (RSS Việt Nam và nước ngoài) và truyện chữ từ DocLN, Wattpad, Sangtacviet. Tải về HTML trên máy, đọc bằng KOReader.

Dùng như trình đọc RSS / trình duyệt cá nhân. Không phát tán nội dung đã tải. Không vượt VIP, paywall hay captcha.

Giấy phép: [AGPL-3.0-or-later](./LICENSE).

## Cài trên Boox (Android)

1. Copy thư mục `booxbook.koplugin` vào:

   `/sdcard/koreader/plugins/booxbook.koplugin/`

   Trong thư mục đó phải có `main.lua`, `_meta.lua` và thư mục `booxbook/` (các module nội bộ).

2. Restart KOReader.

3. Bật plugin: **Tools → More tools → Plugin management → BooxBook**.

4. Chạm **Tools → BooxBook** để mở giao diện toàn màn hình.

## Đọc báo RSS

- **Báo → Báo Việt / Báo Nước Ngoài → chọn đầu báo → chọn danh mục**: chỉ lấy danh sách tiêu đề RSS khi chọn danh mục, chưa tải nội dung các bài.
- 17 đầu báo, 633 danh mục/kênh RSS có bài trong lượt kiểm tra ngày 04/09/2026. **Báo Việt** có 9 báo: VnExpress, Tuổi Trẻ, Thanh Niên, Dân Trí, Tiền Phong, VietnamPlus, Báo Tin tức, Nhân Dân, Sài Gòn Giải Phóng. **Báo Nước Ngoài** có 8 nguồn: BBC News, The Guardian, DW, Sky News, The Independent, Al Jazeera, France 24, ABC News Australia. Xem [phạm vi và nguồn danh mục](docs/news-categories.md).
- Đã bỏ **Nguồn tin** và toàn bộ công tắc bật/tắt. Các thiết lập tắt nguồn từ bản cũ không còn ẩn danh mục.
- **Chạm tiêu đề bài**: lấy nội dung bài đó và mở bằng KOReader; nếu lấy toàn bài lỗi, dùng bản tóm tắt RSS/Atom.
- Trang chi tiết có tiêu đề ở đầu bài; ảnh trong nội dung/tóm tắt được lưu cục bộ chỉ khi mở bài. Ảnh lỗi không chặn đọc chữ. Hỗ trợ JPEG, PNG, GIF, WebP; tối đa 20 ảnh, 2 MiB/ảnh, 10 MiB/bài.
- **Báo → Số bài mỗi danh mục**: chọn từ 1 đến 20 tiêu đề hiển thị; không giới hạn số danh mục.
- **Báo → Tin đã tải**: đọc lại các bài đã mở/lưu, không cần tải lại. Bài cũ vẫn được giữ.
- **Báo → Thêm RSS tùy chỉnh**: thêm URL bắt đầu bằng `http://` hoặc `https://`.
- RSS bạn thêm nằm trong nhóm riêng **Báo → RSS tùy chỉnh**. Kênh rỗng/lỗi chỉ báo thông báo; không làm mất danh sách danh mục.
- Dùng User-Agent desktop; riêng VnExpress có cookie chọn giao diện desktop để tránh RSS rỗng. Vẫn giãn cách lượt tải và dừng khi máy chủ trả HTTP 429; không cam kết loại bỏ mọi rate limit.

## Kiểm tra cài đặt

**BooxBook → Cài đặt → Kiểm tra cài đặt**

Cần Wi-Fi. Plugin gọi `example.com` (kèm header Referer), ghi `_selftest.html` (có chữ `Tiếng Việt`) và thử tạo EPUB vào `koreader/booxbook/`.

## Cài đặt

- Cookie từng nguồn: dán session từ trình duyệt. Cookie không được in ra log.
- Sangtacviet **tắt mặc định**. Bật trong Cài đặt sau hộp cảnh báo.
- Nội dung 18+: tắt mặc định. **Tải ảnh minh họa**: bật mặc định; nếu trước đây đã tắt, bật lại trong Cài đặt. Mở lại bài từ danh mục online để cập nhật bài cũ với tiêu đề/ảnh.
- Chỉ bài được chọn mới lưu HTML tại `koreader/booxbook/news/<feed-id>/` để KOReader mở; không tải hàng loạt. Mở từ danh sách online sẽ lấy lại nội dung bài đó.
- RSS tùy chỉnh chỉ đọc nội dung/tóm tắt trong feed, không tự lấy toàn văn website.

## Phát triển

LuaJIT, không thêm native library. Xem `docs/development-rules.md`.

Chạy unit test (Lua 5.1 / LuaJIT):

```sh
luajit tests/run.lua
```

Rà mọi danh mục bằng RSS thật (cần mạng, mất vài phút): `pwsh -File tests/news-feeds-live.ps1 -All`.
