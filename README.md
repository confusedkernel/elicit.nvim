# elicit.nvim

`elicit.nvim` is a Neovim plugin for linguistic fieldwork: session notes, elicitation examples, gloss validation, corpus search, and export.

This project is currently under development (v0.1 in progress). You can check planned features in `roadmap.md`.

## Commands

- `:ElicitNewSession [name]` (implemented)
- `:ElicitNewExample` (implemented)
- `:ElicitValidate`
- `:ElicitSearch {kind} {query}`
- `:ElicitExport {format} {scope} [value]`

## Features

- Session file creation under `session.dir` with YAML frontmatter template.
- Session names are relative to `session.dir` and `.md` is auto-appended.
- Configurable frontmatter fields via `session.fields`.
- Auto-generated example block insertion with configurable `example.id_format`.
- ID token replacement for `LID`, `YYYYMMDD`, and `N...` counter runs.

## Setup

```lua
require("elicit").setup({
  session = {
    dir = "sessions",
  },
})
```

Default corpus discovery is:

`session.dir .. "/**/*.md"`

unless `search.corpus_glob` is explicitly configured.

## Roadmap

See `roadmap.md` for the full phased plan.
