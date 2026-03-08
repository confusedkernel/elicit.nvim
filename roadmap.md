# elicit.nvim — Feature Roadmap

A Neovim plugin for linguistic fieldwork: sentence elicitation, interlinear glossing, and corpus management. Designed to be language-agnostic so it works for any documentation or description project, not just one language.

Files are plain Markdown with YAML frontmatter, so they stay readable in Obsidian or any other Markdown tool.

---

## Design Principles

- **Plain text first.** Everything is Markdown + YAML. No database, no binary format.
- **Language-agnostic.** The plugin should never assume a specific language's phonology, morphology, or orthography. All language-specific resources (abbreviation sets, wordlists, morpheme inventories) live in project-local config, not in the plugin itself.
- **Session-oriented.** One file per elicitation session. Metadata lives in frontmatter; examples are headed sections within the file.
- **Incremental adoption.** Each feature should be useful on its own. Users should not need the full stack to benefit from any single part.

---

## v0.1 — Core MVP

The minimum set that makes elicitation and glossing meaningfully easier than raw Markdown.

### 1. Session template generator

One command creates a new session file with frontmatter pre-filled.

Default fields:

```yaml
---
date: 2026-03-08
language: ""
speaker: ""
session: 1
location: ""
topic: ""
audio: ""
status: in-progress
tags: []
---
```

The field list should be configurable through `opts.session.fields`, since different projects track different metadata.

### 2. New-example block insertion

A single command inserts a formatted elicitation block at the cursor:

```markdown
## LID-YYYYMMDD-NNN
- Prompt:
- Text:
- Segmentation:
- Gloss:
- Translation:
- Notes:
- Status: draft
- Audio:
```

The example ID is auto-generated from the language ID, date, and a session-local counter. The ID scheme should be configurable.

### 3. Segmentation–gloss alignment validator

Checks that the number of tokens in `Segmentation` matches the number of tokens in `Gloss`, using a configurable delimiter (default: whitespace). Reports mismatches inline or in a quickfix list.

Also flags:

- Empty required fields (Text, Translation)
- Placeholder markers like `?`, `TODO`, `XXX`

This is the single highest-value automated check for glossing work.

### 4. Search

At minimum, these queries:

- Search by surface form (across Text or Segmentation fields)
- Search by gloss label
- Search by status (draft, needs-review, checked)
- Search by speaker or session metadata

Results should open in a quickfix list or Telescope picker so you can jump directly to the example.

### 5. Export

Export targets for v0.1:

- **Markdown** (cleaned, without plugin-internal metadata)
- **Typst** (interlinear gloss layout using `#gloss()` or equivalent)
- **JSON** (structured, for programmatic consumption)

Scope options: single example, entire session, or filtered subset (e.g., all checked examples).

---

## v0.2 — Consistency and Lookup

These features address the problem of keeping a growing corpus internally consistent.

### 6. Gloss abbreviation helper

Autocomplete for standard gloss labels (1SG, ERG, REDUP, etc.) based on the Leipzig Glossing Rules appendix as a default set.

Projects can extend or override this with a local abbreviation file. Each abbreviation can carry a short description shown in a floating window or completion menu.

### 7. Morpheme consistency checker

Maintains an index of morpheme-to-gloss mappings seen across the corpus. When you gloss a morpheme differently from previous occurrences, the plugin warns you.

Example: if `m-` has been glossed as `AV` in 30 examples and you type `AF`, the plugin should flag the divergence. This is not necessarily an error (you might be switching conventions deliberately), but it should always be visible.

The index should be project-scoped and rebuildable from existing files.

### 8. Project-local wordlist / novelty detector

A wordlist that grows as you work. Every root or stem you enter gets recorded; forms the plugin has not seen before are flagged.

This is not a spellchecker in the traditional sense. It does not prescribe correct spelling. It tells you "this form is new to your corpus," which is useful both for catching typos and for noticing genuinely new lexical items.

The wordlist can optionally be seeded from an external source (a published dictionary, a word frequency list, etc.), but the plugin should never hard-reject a form; it should only highlight novelty.

### 9. Status tracking

A small state machine per example:

```
draft → needs-review → checked
```

Commands to cycle status, plus filtering by status in search and export.

---

## v0.3 — Navigation, Audio, and Feedback

### 10. Example navigation

- Next / previous example in current session
- Jump to example by ID
- List all examples in current file (with ID, status, and first few words of Text)

### 11. Dictionary lookup

A project-local dictionary with structured entries: headword, part of speech, definition, variant forms, and optionally links back to example IDs where the word appears.

During glossing, the plugin can suggest dictionary matches for forms in the Text or Segmentation line. Suggestions appear in a floating window or completion menu.

The dictionary is strictly a suggestion layer. It never rejects or autocorrects a form, because dialectal differences, speaker variation, and novel derivations are all expected in fieldwork. If a form does not match any dictionary entry, the plugin notes this silently (or with a soft highlight if the user opts in), but it never blocks input.

The dictionary can be seeded from an external source (a published wordlist, an existing lexical database export) or built up manually. Entries are stored in a local file (JSON or YAML) and are editable by hand.

### 12. Audio timestamp support

Each example can store:

```yaml
- Audio: session-2026-03-08.wav
- Start: 00:03:42.100
- End: 00:03:45.800
```

No playback integration is required in v0.3; just structured storage. (Playback could come later via a terminal audio tool or an external player command.)

### 13. Inline diagnostics

Visual markers (virtual text, signs, or highlights) for:

- Token count mismatches between Segmentation and Gloss
- Empty required fields
- Unresolved placeholders
- Morpheme gloss divergences (from the consistency checker)

### 14. Session summary

A command that prints:

- Total examples in session
- Count by status (draft / needs-review / checked)
- Examples with missing translations
- Examples with unresolved glosses or placeholders
- Examples missing audio timestamps

---

## v1.0 — Polish and Interop

### 15. Snippet library

Bundled and user-defined snippets for:

- New example blocks (with variants for different project conventions)
- Common note templates ("speaker self-corrected", "prompted form rejected", "free variation with X")
- Frequent gloss patterns

### 16. Typst pretty-printing

A proper interlinear layout in Typst output: aligned columns for segmentation, gloss, and translation, with example numbering. Should handle both left-to-right and right-to-left scripts.

### 17. Structured export: CSV, JSON-lines, FLEx-compatible XML

For moving data into other tools:

- **CSV** for quick spreadsheet work
- **JSON-lines** for scripting pipelines
- **FLEx-compatible XML** for SIL FieldWorks import (FLEx uses a specific XML schema for interlinear text; matching it avoids manual reformatting)

### 18. Obsidian command palette integration

If the user also uses Obsidian (likely, given the Markdown-first design), a companion Obsidian plugin or compatible keybindings that mirror the Neovim commands.

---

## Future / Post-v1

These are valuable but not urgent for a working fieldwork tool.

- **Paradigm view.** Display all elicited forms of a root organized by morphological pattern (focus type, tense, mood, etc.). Requires a way to tag examples with paradigm cell labels.
- **Cross-session index.** A project-wide index of all examples, searchable and filterable, possibly as a separate buffer or Telescope extension.
- **Dialect/variety comparison.** Side-by-side display of cognate forms across speaker varieties. Requires tagging examples with dialect or community metadata.
- **ELAN integration.** Import from or export to ELAN `.eaf` files for time-aligned annotation. ELAN's XML format is well-documented but verbose; a dedicated converter would be needed.
- **Reduplication and morphophonology helpers.** Language-specific modules that can be opted into per project. For example, a reduplication highlighter that recognizes common reduplication patterns (Ca-, full-stem, etc.) and marks them visually. These should be optional extensions, not core features.

---

## Configuration

The plugin is configured through a standard `setup(opts)` call in Lua. All project-specific settings live in the opts table.

```lua
require("elicit").setup({
  -- Session template fields
  session = {
    fields = {
      "date", "language", "speaker", "session",
      "location", "topic", "audio", "status", "tags",
    },
    defaults = {
      language = "",
      status = "in-progress",
    },
  },

  -- Example block settings
  example = {
    id_format = "LID-YYYYMMDD-NNN",  -- pattern for auto-generated IDs
    fields = {
      "Prompt", "Text", "Segmentation", "Gloss",
      "Translation", "Notes", "Status", "Audio",
    },
    required_fields = { "Text", "Translation" },
    status_cycle = { "draft", "needs-review", "checked" },
  },

  -- Validation
  validation = {
    delimiter = "%s+",             -- Lua pattern for token splitting
    placeholders = { "?", "TODO", "XXX" },
    warn_on_gloss_divergence = true,
  },

  -- Gloss abbreviations (Leipzig defaults + project-local additions)
  abbreviations = {
    use_leipzig = true,            -- load bundled Leipzig Glossing Rules set
    extra = {
      -- { label = "REDUP", description = "Reduplication" },
    },
  },

  -- Wordlist / novelty detector
  wordlist = {
    enabled = false,
    path = nil,                    -- path to seed file, one form per line
    auto_add = true,               -- add new forms automatically
  },

  -- Dictionary
  dictionary = {
    enabled = false,
    path = nil,                    -- path to seed file (JSON or YAML)
    suggest_on_gloss = true,       -- show suggestions while glossing
    strict = false,                -- never hard-reject; suggestions only
  },

  -- Export
  export = {
    formats = { "markdown", "typst", "json" },
    output_dir = "./export",
  },

  -- Search
  search = {
    backend = "telescope",         -- "telescope" or "quickfix"
  },
})
```

Runtime data that the plugin generates (the morpheme-to-gloss index, the accumulated wordlist) is stored in a `.elicit/` directory at the project root. These files are auto-generated and can be rebuilt from the corpus at any time; they should not need manual editing.

```
.elicit/
  morpheme-index.json   # auto-generated morpheme-to-gloss mappings
  wordlist.txt          # accumulated known forms
  dictionary.json       # lexical entries (headword, POS, definition, variants)
```

---

## Summary Table

| Version | Features | Focus |
|---------|----------|-------|
| v0.1 | Template, insertion, validation, search, export | Fast entry, immediate feedback |
| v0.2 | Abbreviations, morpheme consistency, wordlist, status | Corpus consistency |
| v0.3 | Navigation, dictionary, audio, inline diagnostics, session summary | Session workflow |
| v1.0 | Snippets, Typst layout, structured export, Obsidian compat | Polish and interop |
| Post-v1 | Paradigms, cross-session index, dialect comparison, ELAN | Advanced analysis |
