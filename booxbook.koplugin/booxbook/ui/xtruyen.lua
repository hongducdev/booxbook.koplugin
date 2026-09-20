-- Thin shim: the shared catalogue page lives in booxbook.ui.source-page and is
-- configured entirely by the adapter's `view` table.
return require("booxbook.ui.source-page").create(require("booxbook.sources.xtruyen"))
