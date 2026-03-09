local M = {}

M.defaults = {
	session = {
		dir = "sessions",
		luasnip = {
			enable = false,
			trigger = "session",
			filetypes = { "markdown" },
		},
		fields = {
			"date",
			"language",
			"speaker",
			"session",
			"location",
			"topic",
			"audio",
			"status",
			"tags",
		},
		defaults = {
			language = "",
			status = "in-progress",
		},
	},
	example = {
		id_format = "LID-YYYYMMDD-NNN",
		luasnip = {
			enable = false,
			trigger = "example",
			filetypes = { "markdown" },
		},
		fields = {
			"Prompt",
			"Text",
			"Segmentation",
			"Gloss",
			"Translation",
			"Notes",
			"Status",
			"Audio",
		},
		required_fields = { "Text", "Translation" },
		status_cycle = { "draft", "needs-review", "checked" },
	},
	validation = {
		delimiter = "%s+",
		placeholders = { "?", "TODO", "XXX" },
	},
	search = {
		backend = "telescope",
		corpus_glob = nil,
	},
	export = {
		formats = { "markdown", "typst", "json" },
		output_dir = "export",
	},
}

M.options = nil

local function deepcopy(value)
	return vim.deepcopy(value)
end

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", deepcopy(M.defaults), opts or {})
	return M.options
end

function M.get()
	if not M.options then
		return M.setup({})
	end

	return M.options
end

function M.corpus_glob(opts)
	local cfg = opts or M.get()
	local search = cfg.search or {}
	local session = cfg.session or {}

	if type(search.corpus_glob) == "string" and search.corpus_glob ~= "" then
		return search.corpus_glob
	end

	local dir = session.dir or M.defaults.session.dir
	dir = dir:gsub("/+$", "")

	if dir == "" then
		dir = "."
	end

	return dir .. "/**/*.md"
end

return M
