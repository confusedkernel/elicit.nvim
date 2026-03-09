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

- `:Telescope elicit` (interactive kind + query prompts)
- `:ElicitSearch {kind} {query}` (same search engine, backend-controlled display)

## Roadmap

See `roadmap.md` for the full phased plan.
