-- Thin shim: the shared comic page lives in booxbook.ui.comic-page and is
-- configured entirely by the adapter's `view` table.
return require("booxbook.ui.comic-page").create(require("booxbook.sources.truyentuoitho"))
