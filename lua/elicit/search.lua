local config = require("elicit.config")
local parser = require("elicit.parser")
local util = require("elicit.util")

local M = {}

local KINDS = { "form", "gloss", "status", "speaker", "session" }
local KIND_SET = util.to_set(KINDS)
local BACKENDS = { "quickfix", "telescope" }
local BACKEND_SET = util.to_set(BACKENDS)

local EXAMPLE_FIELDS_BY_KIND = {
	form = { "Text", "Segmentation" },
	gloss = { "Gloss" },
	status = { "Status" },
}

local SESSION_FIELDS_BY_KIND = {
	speaker = "speaker",
	session = "session",
}

local function normalize_kind(kind)
	return util.trim(tostring(kind or "")):lower()
end

local function normalize_query(query)
	return util.trim(tostring(query or ""))
end

local function normalize_backend(backend)
	return util.trim(tostring(backend or "")):lower()
end

local function validate_inputs(kind, query)
	local normalized_kind = normalize_kind(kind)
	local normalized_query = normalize_query(query)

	if not KIND_SET[normalized_kind] then
		return nil, nil, string.format("invalid search kind '%s'", tostring(kind))
	end

	if normalized_query == "" then
		return nil, nil, "search query cannot be empty"
	end

	return normalized_kind, normalized_query
end

local function join_list(value)
	if type(value) ~= "table" then
		return tostring(value or "")
	end

	local parts = {}

	for _, item in ipairs(value) do
		table.insert(parts, tostring(item))
	end

	return table.concat(parts, ", ")
end

local function compact(value)
	local text = util.trim(join_list(value))
	text = text:gsub("%s+", " ")

	if #text <= 120 then
		return text
	end

	return text:sub(1, 117) .. "..."
end

local function contains_query(value, lowered_query)
	local haystack = tostring(value or ""):lower()
	return haystack:find(lowered_query, 1, true) ~= nil
end

local function find_frontmatter_line(parsed, key)
	local frontmatter = parsed.frontmatter or {}

	if not frontmatter.found then
		return 1
	end

	local start_line = (frontmatter.start_line or 1) + 1
	local end_line = (frontmatter.end_line or start_line) - 1
	local pattern = "^" .. util.escape_lua_pattern(key) .. ":"

	for line_number = start_line, end_line do
		local line = parsed.lines[line_number]

		if line and line:match(pattern) then
			return line_number
		end
	end

	return frontmatter.start_line or 1
end

local function build_example_result(path, kind, example, field, value)
	local example_id = util.trim(tostring(example.id or ""))

	if example_id == "" then
		example_id = "<unknown-id>"
	end

	local preview = compact(value)

	if preview == "" then
		preview = "(empty)"
	end

	local lnum = example.field_lines[field] or example.start_line or 1

	return {
		filename = path,
		lnum = lnum,
		col = 1,
		kind = kind,
		example_id = example_id,
		field = field,
		text = string.format("%s | %s: %s", example_id, field, preview),
	}
end

local function build_session_result(path, parsed, kind, field, value)
	local preview = compact(value)

	if preview == "" then
		preview = "(empty)"
	end

	return {
		filename = path,
		lnum = find_frontmatter_line(parsed, field),
		col = 1,
		kind = kind,
		field = field,
		text = string.format("[session] %s: %s", field, preview),
	}
end

local function glob_corpus_files(corpus_glob)
	local ok, paths = pcall(vim.fn.glob, corpus_glob, false, true)

	if not ok then
		return nil, string.format("failed to expand corpus glob '%s'", corpus_glob)
	end

	if type(paths) ~= "table" then
		paths = { paths }
	end

	local unique = {}
	local out = {}

	for _, path in ipairs(paths) do
		local normalized = util.normalize_path(path)

		if normalized ~= "" and not unique[normalized] and util.file_exists(normalized) then
			unique[normalized] = true
			table.insert(out, normalized)
		end
	end

	table.sort(out)

	return out
end

local function push_results_for_example_kind(results, parsed, path, kind, lowered_query)
	local fields = EXAMPLE_FIELDS_BY_KIND[kind]

	if not fields then
		return
	end

	for _, example in ipairs(parsed.examples or {}) do
		for _, field in ipairs(fields) do
			local value = example.fields[field]

			if value ~= nil and contains_query(value, lowered_query) then
				table.insert(results, build_example_result(path, kind, example, field, value))
			end
		end
	end
end

local function push_results_for_session_kind(results, parsed, path, kind, lowered_query)
	local field = SESSION_FIELDS_BY_KIND[kind]

	if not field then
		return
	end

	local frontmatter_data = parsed.frontmatter and parsed.frontmatter.data or {}
	local value = frontmatter_data[field]

	if value ~= nil and contains_query(join_list(value), lowered_query) then
		table.insert(results, build_session_result(path, parsed, kind, field, value))
	end
end

local function sort_results(results)
	table.sort(results, function(left, right)
		if left.filename ~= right.filename then
			return left.filename < right.filename
		end

		if left.lnum ~= right.lnum then
			return left.lnum < right.lnum
		end

		return left.text < right.text
	end)
end

local function collect_matches(kind, query)
	local cfg = config.get()
	local corpus_glob = config.corpus_glob(cfg)
	local files, files_err = glob_corpus_files(corpus_glob)

	if not files then
		return nil, files_err
	end

	local lowered_query = query:lower()
	local results = {}
	local parse_failures = 0

	for _, path in ipairs(files) do
		local parsed = parser.parse_file(path)

		if not parsed then
			parse_failures = parse_failures + 1
		else
			push_results_for_example_kind(results, parsed, path, kind, lowered_query)
			push_results_for_session_kind(results, parsed, path, kind, lowered_query)
		end
	end

	sort_results(results)

	return {
		results = results,
		files = files,
		parse_failures = parse_failures,
		corpus_glob = corpus_glob,
	}
end

local function open_location(result)
	vim.cmd.edit(vim.fn.fnameescape(result.filename))

	local line = math.max(1, tonumber(result.lnum) or 1)
	local col = math.max(1, tonumber(result.col) or 1)

	pcall(vim.api.nvim_win_set_cursor, 0, { line, col - 1 })
end

local function to_quickfix_items(results)
	local items = {}

	for _, result in ipairs(results) do
		table.insert(items, {
			filename = result.filename,
			lnum = result.lnum,
			col = result.col,
			text = result.text,
		})
	end

	return items
end

local function show_quickfix(results, title)
	local items = to_quickfix_items(results)

	vim.fn.setqflist({}, " ", {
		title = title,
		items = items,
	})

	if #items == 0 then
		pcall(vim.cmd, "cclose")
	else
		vim.cmd("copen")
	end
end

local function show_telescope(results, title)
	local ok_pickers, pickers = pcall(require, "telescope.pickers")
	local ok_finders, finders = pcall(require, "telescope.finders")
	local ok_config, telescope_config = pcall(require, "telescope.config")
	local ok_actions, actions = pcall(require, "telescope.actions")
	local ok_action_state, action_state = pcall(require, "telescope.actions.state")

	if not (ok_pickers and ok_finders and ok_config and ok_actions and ok_action_state) then
		return nil, "telescope.nvim is not available"
	end

	local function entry_maker(result)
		local relative = vim.fn.fnamemodify(result.filename, ":.")
		local display = string.format("%s:%d %s", relative, result.lnum, result.text)

		return {
			value = result,
			display = display,
			ordinal = string.format("%s %s", relative:lower(), tostring(result.text):lower()),
			filename = result.filename,
			lnum = result.lnum,
			col = result.col,
			text = result.text,
		}
	end

	pickers.new({}, {
		prompt_title = title,
		finder = finders.new_table({
			results = results,
			entry_maker = entry_maker,
		}),
		sorter = telescope_config.values.generic_sorter({}),
		previewer = telescope_config.values.qflist_previewer({}),
		attach_mappings = function(prompt_bufnr)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)

				if selection and selection.value then
					open_location(selection.value)
				end
			end)

			return true
		end,
	}):find()

	return true
end

local function resolve_backend(opts_backend)
	local cfg = config.get()
	local search_cfg = cfg.search or {}
	local backend = opts_backend or search_cfg.backend or "quickfix"

	backend = normalize_backend(backend)

	if not BACKEND_SET[backend] then
		return nil, string.format("invalid search backend '%s'", tostring(backend))
	end

	return backend
end

local function run_telescope(kind, query)
	local output, output_err = M.run(kind, query, { backend = "telescope" })

	if output == nil and output_err then
		vim.notify("elicit.nvim: " .. tostring(output_err), vim.log.levels.ERROR)
	end

	return output
end

function M.kinds()
	return vim.deepcopy(KINDS)
end

function M.collect(kind, query)
	local normalized_kind, normalized_query, input_err = validate_inputs(kind, query)

	if not normalized_kind then
		return nil, input_err
	end

	return collect_matches(normalized_kind, normalized_query)
end

function M.run(kind, query, opts)
	local normalized_kind, normalized_query, input_err = validate_inputs(kind, query)

	if not normalized_kind then
		return nil, input_err
	end

	local backend, backend_err = resolve_backend(opts and opts.backend)

	if not backend then
		return nil, backend_err
	end

	local collected, collect_err = collect_matches(normalized_kind, normalized_query)

	if not collected then
		return nil, collect_err
	end

	local results = collected.results
	local title = string.format("elicit search: %s=%s", normalized_kind, normalized_query)

	if collected.parse_failures > 0 then
		vim.notify(string.format("elicit.nvim: skipped %d unreadable file%s", collected.parse_failures, collected.parse_failures == 1 and "" or "s"), vim.log.levels.WARN)
	end

	if #results == 0 then
		if backend == "quickfix" then
			show_quickfix(results, title)
		end

		vim.notify(string.format("elicit.nvim: no matches for %s '%s'", normalized_kind, normalized_query), vim.log.levels.INFO)
		return results
	end

	if backend == "telescope" then
		local ok_telescope, telescope_err = show_telescope(results, title)

		if not ok_telescope then
			vim.notify(string.format("elicit.nvim: %s; falling back to quickfix", tostring(telescope_err)), vim.log.levels.WARN)
			show_quickfix(results, title)
		end
	else
		show_quickfix(results, title)
	end

	vim.notify(string.format("elicit.nvim: found %d match%s", #results, #results == 1 and "" or "es"), vim.log.levels.INFO)

	return results
end

function M.telescope(opts)
	local options = opts or {}
	local kind = normalize_kind(options.kind)
	local query = normalize_query(options.query)

	if kind ~= "" and query ~= "" then
		return run_telescope(kind, query)
	end

	if kind ~= "" and not KIND_SET[kind] then
		vim.notify("elicit.nvim: " .. string.format("invalid search kind '%s'", kind), vim.log.levels.ERROR)
		return nil
	end

	local function prompt_query(selected_kind)
		vim.ui.input({
			prompt = string.format("Elicit query (%s): ", selected_kind),
			default = query,
		}, function(input)
			local selected_query = normalize_query(input)

			if selected_query == "" then
				vim.notify("elicit.nvim: search query cannot be empty", vim.log.levels.WARN)
				return
			end

			run_telescope(selected_kind, selected_query)
		end)
	end

	if kind ~= "" then
		prompt_query(kind)
		return true
	end

	vim.ui.select(M.kinds(), {
		prompt = "Elicit search kind:",
	}, function(choice)
		if not choice then
			return
		end

		prompt_query(choice)
	end)

	return true
end

return M
