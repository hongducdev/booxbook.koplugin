# BooxBook

Plugin [KOReader](https://github.com/koreader/koreader) để đọc báo (RSS Việt Nam và nước ngoài) và truyện chữ từ DocLN, Wattpad, Sangtacviet. Tải về HTML trên máy, đọc bằng KOReader.

Dùng như trình đọc RSS / trình duyệt cá nhân. Không phát tán nội dung đã tải. Không vượt VIP, paywall hay captcha.

Giấy phép: [AGPL-3.0-or-later](./LICENSE).

## Cài trên Boox (Android)

1. Copy thư mục `booxbook.koplugin` vào:

   `/sdcard/koreader/plugins/booxbook.koplugin/`

   Trong thư mục đó phải có `main.lua` và `_meta.lua`.

2. Restart KOReader.

3. Bật plugin: **Tools → More tools → Plugin management → BooxBook**.

4. Menu: **Tools → BooxBook**.

## Kiểm tra cài đặt

**BooxBook → Cài đặt → Kiểm tra cài đặt**

Cần Wi-Fi. Plugin gọi `example.com` (kèm header Referer), ghi `_selftest.html` (có chữ `Tiếng Việt`) và thử tạo EPUB vào `koreader/booxbook/`.

## Cài đặt

- Cookie từng nguồn: dán session từ trình duyệt. Cookie không được in ra log.
- Sangtacviet **tắt mặc định**. Bật trong Cài đặt sau hộp cảnh báo.
- Nội dung 18+ và tải ảnh: tắt mặc định.

## Phát triển

LuaJIT, không thêm native library. Xem `docs/development-rules.md`.

Chạy unit test (Lua 5.1 / LuaJIT):

```sh
lua tests/run.lua
```
