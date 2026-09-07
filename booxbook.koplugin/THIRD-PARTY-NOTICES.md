# Third-party notices

DocLN parsing and public HTML payload decoding are adapted from
[Yuneko-dev/Nekori-plugins, LNHako](https://github.com/Yuneko-dev/Nekori-plugins/tree/c29b05de71bf71e5321d6488014d027d7b2f68cb/plugins/vietnamese/LNHako)
(`index.ts`, `utils.ts`). BooxBook uses its existing Lua networking and UI;
it does not include Nekori's TypeScript dependencies.

Wattpad endpoint selection and metadata mapping also reference
[Nekori Wattpad](https://github.com/Yuneko-dev/Nekori-plugins/blob/master/plugins/vietnamese/Wattpad/index.ts).
The Lua adapter uses BooxBook's own validation, download, and UI code.

Sangtacviet Private-Use glyph substitution (242 entries) and chapter-session
notes are ported from
[Nekori SangTacViet](https://github.com/Yuneko-dev/Nekori-plugins/blob/master/plugins/vietnamese/SangTacViet/index.ts).
BooxBook does not include Nekori's name engine, WebView helpers, or captcha UI.

Truyện Full listing/search URLs, TOC pagination (`/trang-N/#list-chapter`) and
`#chapter-c` mapping are adapted from
[Nekori TruyenFull 1.0.7](https://github.com/Yuneko-dev/Nekori-plugins/blob/master/plugins/vietnamese/TruyenFull/index.ts).
BooxBook uses its HTML/HTTP stack, not Cheerio or Nekori's filter chrome.

MIT License

Copyright (c) 2021 Rajarshee Chatterjee
Copyright (c) 2026 Elysia

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
