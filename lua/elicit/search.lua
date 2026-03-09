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

local function validate_kind(kind)
	local normalized_kind = normalize_kind(kind)

	if not KIND_SET[normalized_kind] then
		return nil, string.format("invalid search kind '%s'", tostring(kind))
	end

	return normalized_kind
end

local function validate_inputs(kind, query)
	local normalized_kind, kind_err = validate_kind(kind)
	local normalized_query = normalize_query(query)

	if not normalized_kind then
		return nil, nil, kind_err
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

local function matches_query(value, lowered_query)
	if lowered_query == nil or lowered_query == "" then
		return true
	end

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
		search_text = preview,
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
		search_text = preview,
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

			if value ~= nil and matches_query(value, lowered_query) then
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

	if value ~= nil and matches_query(join_list(value), lowered_query) then
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

	local normalized_query = normalize_query(query)
	local lowered_query = normalized_query == "" and nil or normalized_query:lower()
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

local function load_telescope()
	local ok_pickers, pickers = pcall(require, "telescope.pickers")
	local ok_finders, finders = pcall(require, "telescope.finders")
	local ok_config, telescope_config = pcall(require, "telescope.config")
	local ok_actions, actions = pcall(require, "telescope.actions")
	local ok_action_state, action_state = pcall(require, "telescope.actions.state")

	if not (ok_pickers and ok_finders and ok_config and ok_actions and ok_action_state) then
		return nil, "telescope.nvim is not available"
	end

	return {
		pickers = pickers,
		finders = finders,
		telescope_config = telescope_config,
		actions = actions,
		action_state = action_state,
	}
end

local function has_jump_target(results)
	for _, result in ipairs(results) do
		if not result.is_placeholder then
			return true
		end
	end

	return false
end

local function show_telescope(results, title, opts)
	local options = opts or {}
	local telescope, telescope_err = load_telescope()

	if not telescope then
		return nil, telescope_err
	end

	local previewer = nil

	if has_jump_target(results) then
		previewer = telescope.telescope_config.values.qflist_previewer({})
	end

	local function entry_maker(result)
		if result.is_placeholder then
			local display = tostring(result.text or "No results")

			return {
				value = result,
				display = display,
				ordinal = display:lower(),
				filename = nil,
				lnum = 1,
				col = 1,
				text = display,
			}
		end

		local relative = vim.fn.fnamemodify(result.filename, ":.")
		local display = string.format("%s:%d %s", relative, result.lnum, result.text)
		local ordinal_text = tostring(result.search_text or result.text or ""):lower()

		if ordinal_text == "" then
			ordinal_text = display:lower()
		end

		return {
			value = result,
			display = display,
			ordinal = ordinal_text,
			filename = result.filename,
			lnum = result.lnum,
			col = result.col,
			text = result.text,
		}
	end

	telescope.pickers.new({}, {
		prompt_title = title,
		default_text = options.default_text,
		finder = telescope.finders.new_table({
			results = results,
			entry_maker = entry_maker,
		}),
		sorter = telescope.telescope_config.values.generic_sorter({}),
		previewer = previewer,
		attach_mappings = function(prompt_bufnr)
			telescope.actions.select_default:replace(function()
				local selection = telescope.action_state.get_selected_entry()
				telescope.actions.close(prompt_bufnr)

				if selection and selection.value and not selection.value.is_placeholder then
					open_location(selection.value)
				end
			end)

			return true
		end,
	}):find()

	return true
end

local function pick_kind_telescope(default_kind, on_select)
	local telescope, telescope_err = load_telescope()

	if not telescope then
		return nil, telescope_err
	end

	local kinds = M.kinds()
	local default_index = nil

	for index, kind in ipairs(kinds) do
		if kind == default_kind then
			default_index = index
			break
		end
	end

	telescope.pickers.new({}, {
		prompt_title = "Elicit search kind",
		finder = telescope.finders.new_table({
			results = kinds,
		}),
		sorter = telescope.telescope_config.values.generic_sorter({}),
		default_selection_index = default_index,
		attach_mappings = function(prompt_bufnr)
			telescope.actions.select_default:replace(function()
				local selection = telescope.action_state.get_selected_entry()
				telescope.actions.close(prompt_bufnr)

				if not selection then
					return
				end

				local selected_kind = selection.value

				if selected_kind then
					on_select(selected_kind)
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

local function run_telescope_interactive(kind, query)
	local normalized_kind, kind_err = validate_kind(kind)

	if not normalized_kind then
		return nil, kind_err
	end

	local normalized_query = normalize_query(query)
	local collected, collect_err = collect_matches(normalized_kind, "")

	if not collected then
		return nil, collect_err
	end

	if collected.parse_failures > 0 then
		vim.notify(string.format("elicit.nvim: skipped %d unreadable file%s", collected.parse_failures, collected.parse_failures == 1 and "" or "s"), vim.log.levels.WARN)
	end

	local results = collected.results
	local picker_results = results
	local title = string.format("elicit search: %s", normalized_kind)

	if #picker_results == 0 then
		picker_results = {
			{
				is_placeholder = true,
				text = string.format("No entries available for kind '%s'", normalized_kind),
			},
		}
	end

	local ok_telescope, telescope_err = show_telescope(picker_results, title, {
		default_text = normalized_query,
	})

	if not ok_telescope then
		return nil, telescope_err
	end

	return results
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
		if backend == "telescope" then
			local empty_results = {
				{
					is_placeholder = true,
					text = string.format("No matches for %s '%s'", normalized_kind, normalized_query),
				},
			}
			local ok_telescope, telescope_err = show_telescope(empty_results, title)

			if not ok_telescope then
				vim.notify(string.format("elicit.nvim: %s; falling back to quickfix", tostring(telescope_err)), vim.log.levels.WARN)
				show_quickfix(results, title)
			end
		else
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

	if kind ~= "" then
		local output, output_err = run_telescope_interactive(kind, query)

		if output == nil and output_err then
			vim.notify("elicit.nvim: " .. tostring(output_err), vim.log.levels.ERROR)
		end

		return output
	end

	local ok_picker, picker_err = pick_kind_telescope("", function(choice)
		local output, output_err = run_telescope_interactive(choice, query)

		if output == nil and output_err then
			vim.notify("elicit.nvim: " .. tostring(output_err), vim.log.levels.ERROR)
		end
	end)

	if not ok_picker then
		vim.notify("elicit.nvim: " .. tostring(picker_err), vim.log.levels.ERROR)
		return nil
	end

	return true
end

return M
