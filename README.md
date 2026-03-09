# elicit.nvim

`elicit.nvim` is a Neovim plugin for linguistic fieldwork: session notes, elicitation examples, gloss validation, corpus search, and export.

This project is currently under development (v0.1 MVP complete; v0.2 in progress). You can check planned features in `roadmap.md`.

## Commands

- `:ElicitNewSession [name]` (implemented)
- `:ElicitNewExample` (implemented)
- `:ElicitValidate` (implemented)
- `:ElicitSearch {kind} {query}` (implemented)
- `:ElicitExport {format} {scope} [value]` (implemented)

## Features

- Session file creation under `session.dir` with YAML frontmatter template.
- Session names are relative to `session.dir` and `.md` is auto-appended.
- Configurable frontmatter fields via `session.fields`.
- Auto-generated example block insertion with configurable `example.id_format`.
- ID token replacement for `LID`, `YYYYMMDD`, and `N...` counter runs.
- LuaSnip-powered field jumping after `:ElicitNewExample` with `<Tab>` / `<S-Tab>`.
- LuaSnip trigger for example insertion (e.g. type `example` then expand).
- Session validation with quickfix diagnostics for token mismatches, missing required fields, and placeholder markers.
- Corpus search by `form`, `gloss`, `status`, `speaker`, and `session`.
- Search result display through quickfix or Telescope (`search.backend`).
- Export output for `markdown`, `typst`, and `json` under `export.output_dir`.
- Export scopes for single example, current session, or status-filtered corpus subset.

## Setup

```lua
require("elicit").setup({
  session = {
    dir = "sessions",
  },
  example = {
    luasnip = {
      enable = true,       -- enable LuaSnip snippet integration
      trigger = "example", -- trigger word for insert-mode expansion
      filetypes = { "markdown" },
    },
  },
  search = {
    backend = "telescope", -- or "quickfix"
  },
})
```

Default corpus discovery is:

`session.dir .. "/**/*.md"`

unless `search.corpus_glob` is explicitly configured.

## Telescope Integration

If you use `telescope.nvim`, load the extension:

```lua
require("telescope").load_extension("elicit")
```

Then run:

- `:Telescope elicit` (pick kind, then filter live in Telescope prompt)
- `:ElicitSearch {kind} {query}` (same search engine, backend-controlled display)

## nvim-cmp Tab Integration

When using LuaSnip with nvim-cmp, ensure `luasnip.expand_or_jumpable()` is
checked **before** `cmp.visible()` in your `<Tab>` mapping so that Tab jumps
through snippet fields instead of selecting a completion item:

```lua
local cmp = require("cmp")
local luasnip = require("luasnip")

cmp.setup({
  mapping = {
    ["<Tab>"] = cmp.mapping(function(fallback)
      if luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      elseif cmp.visible() then
        cmp.select_next_item()
      else
        fallback()
      end
    end, { "i", "s" }),
    ["<S-Tab>"] = cmp.mapping(function(fallback)
      if luasnip.jumpable(-1) then
        luasnip.jump(-1)
      elseif cmp.visible() then
        cmp.select_prev_item()
      else
        fallback()
      end
    end, { "i", "s" }),
  },
})
```

## LuaSnip Trigger Integration

Enable this in `elicit.setup()` if you want snippet-trigger insertion:

```lua
require("elicit").setup({
  example = {
    luasnip = {
      enable = true,
      trigger = "example",
      filetypes = { "markdown" },
    },
  },
})
```

Then type `example` in a supported filetype and use your LuaSnip expand key.
The snippet auto-generates the same example ID format as `:ElicitNewExample`.
If LuaSnip is lazy-loaded, elicit will retry snippet registration on buffer/insert events.

## Roadmap

See `roadmap.md` for the full phased plan.
