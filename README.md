# elicit.nvim

`elicit.nvim` is a Neovim plugin for linguistic fieldwork: session notes, elicitation examples, gloss validation, corpus search, and export.

This project is currently under development. You can check planned features in `roadmap.md`.

## Commands

- `:ElicitNewSession [name]`
- `:ElicitInitSession`
- `:ElicitNewExample`
- `:ElicitValidate`
- `:ElicitSearch {kind} {query}`
- `:ElicitExport {format} {scope} [value]`

## Features

- Session file creation under `session.dir` with YAML frontmatter template.
- Session frontmatter initialization for the current buffer (`:ElicitInitSession`).
- Session names are relative to `session.dir` and `.md` is auto-appended.
- Configurable frontmatter fields via `session.fields`.
- Auto-generated example block insertion with configurable `example.id_format`.
- ID token replacement for `LID`, `YYYYMMDD`, and `N...` counter runs.
- LuaSnip-powered field jumping after `:ElicitNewExample` with `<Tab>` / `<S-Tab>`.
- LuaSnip trigger for example insertion (e.g. type `example` then expand).
- Abbreviation config groundwork for upcoming v0.2 gloss completion features.
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
    luasnip = {
      enable = true,       -- enable LuaSnip snippet integration
      trigger = "session", -- trigger word for session frontmatter
      filetypes = { "markdown" },
    },
  },
  example = {
    luasnip = {
      enable = true,       -- enable LuaSnip snippet integration
      trigger = "example", -- trigger word for insert-mode expansion
      filetypes = { "markdown" },
    },
  },
  abbreviations = {
    use_leipzig = true,
    mode = "extend", -- or "replace"
    extra = {
      -- { label = "REDUP", description = "reduplication", aliases = { "redup" } },
    },
    path = nil, -- optional project-local abbreviation file
    gloss_fields = { "Gloss" },
    separators = { "-", "=", "~", ".", ";", ":", "\\", ">", "<", " " },
    cmp = {
      enable = true,
    },
    luasnip = {
      enable = false,
      trigger_prefix = ";",
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

## LuaSnip Trigger Integration

Enable this in `elicit.setup()` if you want snippet-trigger insertion for
example blocks and/or session frontmatter:

```lua
require("elicit").setup({
  session = {
    luasnip = {
      enable = true,
      trigger = "session",
      filetypes = { "markdown" },
    },
  },
  example = {
    luasnip = {
      enable = true,
      trigger = "example",
      filetypes = { "markdown" },
    },
  },
})
```

Then type `session` in a supported filetype and use your LuaSnip expand key to
insert session frontmatter.

Then type `example` in a supported filetype and use your LuaSnip expand key.
The snippet auto-generates the same example ID format as `:ElicitNewExample`.
If LuaSnip is lazy-loaded, elicit will retry snippet registration on buffer/insert events.

## Abbreviation Config (Phase 1)

The `abbreviations` config block is available as v0.2 groundwork. It currently
defines merge sources and integration toggles; completion/expansion behavior is
implemented in the next phases.

## Roadmap

See `roadmap.md` for the full phased plan.
