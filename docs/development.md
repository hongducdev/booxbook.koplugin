# Phát triển

## Quy ước

- Plugin nằm trong `booxbook.koplugin/`. Tên thư mục phải kết thúc bằng `.koplugin`.
- Module nội bộ nằm dưới `booxbook.koplugin/booxbook/` và load bằng `require("booxbook.*")`. Không dùng tên generic (`html`, `http`, `ui.catalog`) — trùng với KOReader.
- `require` ở đầu file. Không ghi cookie hay `Authorization` ra log.
- Chuỗi giao diện: tiếng Việt, bọc `_()` từ `gettext`.
- Module nhỏ, đúng một việc; tách trước khi file ~400 dòng.
- HTTP đi qua `booxbook.http` (Referer, Cookie, rate limit, retry). Caller bọc `Network.whenOnline` / `NetworkMgr:beforeWifiAction`.
- Adapter tuân [hợp đồng `booxbook.source`](system-architecture.md#adapter-contract-booxbooksource). `getChapter` không vượt paywall/VIP.
- Mặc định lưu truyện: một file HTML mỗi chương. EPUB tùy chọn.

## Cây plugin

```
booxbook.koplugin/
  _meta.lua                 tên, mô tả, version (khớp tag Release)
  main.lua                  menu Tools, Cài đặt, selftest
  THIRD-PARTY-NOTICES.md    MIT Nekori
  booxbook/
    http.lua                GET/POST, cookie, Referer, redirect, retry
    rate_limit.lua          giãn cách theo host
    network.lua             cổng Wi-Fi
    html.lua                sanitize + select
    gzip.lua                giải nén zlib (Wattpad)
    epub.lua                EPUB tùy chọn
    article-images.lua      ảnh bài báo khi mở bài
    covers.lua              cache bìa grid
    source.lua              registry adapter
    novel-download.lua      tải khoảng chương → HTML + index.json
    update.lua              kiểm tra / cài zip GitHub Release
    store/settings.lua      LuaSettings → settings/booxbook.lua
    sources/                RSS + DocLN + Wattpad + Sangtacviet + feeds*
    ui/                     catalog, danh sách, grid, news, novels
```

Cài trên máy: `/sdcard/koreader/plugins/booxbook.koplugin/`.

## Test

Unit test thuần Lua, không cần KOReader:

```sh
luajit tests/run.lua
```

`tests/gzip.lua` chạy riêng (cần zlib của KOReader hoặc shim FFI trên máy dev).

Rà catalog RSS trên mạng:

```sh
pwsh -File scripts/news-feeds-live.ps1 -All
```

Unit test danh mục so với snapshot `tests/fixtures/feeds-audit.md` (lần rà 04/09/2026). Cập nhật fixture khi đổi catalog và đã chạy lại script live.

## Cập nhật GitHub

Version nằm trong `booxbook.koplugin/_meta.lua`. Tag `v*` (ví dụ `v0.0.1`) chạy `.github/workflows/release.yml` và đính `booxbook.koplugin.zip`.

Trong plugin: **Cài đặt → Cập nhật từ GitHub** lấy release mới nhất, giải vào thư mục staging, đổi:

1. `booxbook.koplugin` → `booxbook.koplugin.bak`
2. staging (đã kiểm `main.lua` + `_meta.lua`) → `booxbook.koplugin`

HTML/EPUB dưới `koreader/booxbook/` và `settings/booxbook.lua` nằm ngoài thư mục plugin nên không bị xóa. Restart KOReader sau khi đổi; module đã `package.loaded` không hot-reload.

Lần cài đầu vẫn copy tay / ADB. Cập nhật in-app chỉ chạy khi đã có 0.0.1 và một Release mới hơn kèm zip.

Khi triển khai tay: chạy test, copy plugin vào thư mục staging ngoài `plugins`, so hash, dời bản đang cài sang backup, rồi đưa bản mới vào chỗ. Đừng ghi đè vào thư mục plugin đang dùng — dễ sót file cũ hoặc lồng `booxbook.koplugin` trong chính nó.
