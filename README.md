# elicit.nvim

`elicit.nvim` is a Neovim plugin for linguistic fieldwork: session notes, elicitation examples, gloss validation, corpus search, and export.

This project is currently under development, you can check the planned features in `roadmap.md`.

## Commands

- `:ElicitNewSession`
- `:ElicitNewExample`
- `:ElicitValidate`
- `:ElicitSearch {kind} {query}`
- `:ElicitExport {format} {scope} [value]`

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
