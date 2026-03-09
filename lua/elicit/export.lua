local config = require("elicit.config")
local parser = require("elicit.parser")
local util = require("elicit.util")

local M = {}

local FORMATS = { "markdown", "typst", "json" }
local SCOPES = { "example", "session", "status" }

local FORMAT_SET = util.to_set(FORMATS)
local SCOPE_SET = util.to_set(SCOPES)
local FORMAT_EXTENSION = {
	markdown = "md",
	typst = "typ",
	json = "json",
}

local function normalize_value(value)
	return util.trim(tostring(value or ""))
end

local function normalize_format(value)
	return normalize_value(value):lower()
end

local function normalize_scope(value)
	return normalize_value(value):lower()
end

local function list_to_string(values)
	if type(values) ~= "table" then
		return tostring(values or "")
	end

	local out = {}

	for _, value in ipairs(values) do
		table.insert(out, tostring(value))
	end

	return table.concat(out, ", ")
end

local function compact_text(value)
	local text = normalize_value(list_to_string(value))
	return text:gsub("%s+", " ")
end

local function relative_path(path)
	local normalized = normalize_value(path)

	if normalized == "" then
		return "[No Name]"
	end

	return vim.fn.fnamemodify(normalized, ":.")
end

local function sanitize_token(value)
	local token = normalize_value(value):lower()

	token = token:gsub("[^%w%-_]+", "-")
	token = token:gsub("%-+", "-")
	token = token:gsub("^%-+", "")
	token = token:gsub("%-+$", "")

	if token == "" then
		return "export"
	end

	return token
end

local function ordered_example_fields(example, example_cfg)
	local ordered = {}
	local seen = {}

	for _, field_name in ipairs(example_cfg.fields or {}) do
		if example.fields[field_name] ~= nil then
			table.insert(ordered, {
				name = field_name,
				value = example.fields[field_name],
			})
			seen[field_name] = true
		end
	end

	local extras = {}

	for field_name, _ in pairs(example.fields or {}) do
		if not seen[field_name] then
			table.insert(extras, field_name)
		end
	end

	table.sort(extras)

	for _, field_name in ipairs(extras) do
		table.insert(ordered, {
			name = field_name,
			value = example.fields[field_name],
		})
	end

	return ordered
end

local function build_record(path, session_data, example, example_cfg)
	local id = normalize_value(example.id)

	if id == "" then
		id = "<unknown-id>"
	end

	return {
		path = path,
		session = vim.deepcopy(session_data or {}),
		example = {
			id = id,
			start_line = example.start_line or 1,
			fields = ordered_example_fields(example, example_cfg),
		},
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

local function sort_records(records)
	table.sort(records, function(left, right)
		if left.path ~= right.path then
			return left.path < right.path
		end

		if left.example.start_line ~= right.example.start_line then
			return left.example.start_line < right.example.start_line
		end

		return left.example.id < right.example.id
	end)
end

local function find_example_at_cursor(examples)
	local line = vim.api.nvim_win_get_cursor(0)[1]

	for _, example in ipairs(examples or {}) do
		if line >= (example.start_line or 1) and line <= (example.end_line or example.start_line or 1) then
			return example
		end
	end

	return nil
end

local function find_example_by_id(examples, target_id)
	for _, example in ipairs(examples or {}) do
		if normalize_value(example.id) == target_id then
			return example
		end
	end

	return nil
end

local function collect_example_scope(raw_value, cfg)
	local parsed = parser.parse_buffer(0)
	local path = parsed.path
	local session_data = parsed.frontmatter and parsed.frontmatter.data or {}
	local examples = parsed.examples or {}

	if #examples == 0 then
		return nil, "no examples found in current buffer"
	end

	local requested_id = normalize_value(raw_value)
	local target_example = nil

	if requested_id == "" then
		target_example = find_example_at_cursor(examples)

		if not target_example then
			return nil, "example scope requires an example id or cursor inside an example"
		end
	else
		target_example = find_example_by_id(examples, requested_id)

		if not target_example then
			return nil, string.format("example '%s' not found in current session", requested_id)
		end
	end

	local record = build_record(path, session_data, target_example, cfg.example or {})

	return {
		scope = "example",
		value = record.example.id,
		records = { record },
		session_path = path,
		parse_failures = 0,
	}
end

local function collect_session_scope(cfg)
	local parsed = parser.parse_buffer(0)
	local path = parsed.path
	local session_data = parsed.frontmatter and parsed.frontmatter.data or {}
	local records = {}

	for _, example in ipairs(parsed.examples or {}) do
		table.insert(records, build_record(path, session_data, example, cfg.example or {}))
	end

	sort_records(records)

	return {
		scope = "session",
		value = "",
		records = records,
		session_path = path,
		parse_failures = 0,
	}
end

local function collect_status_scope(raw_value, cfg)
	local requested_status = normalize_value(raw_value)

	if requested_status == "" then
		return nil, "status scope requires a status value"
	end

	local corpus_glob = config.corpus_glob(cfg)
	local files, files_err = glob_corpus_files(corpus_glob)

	if not files then
		return nil, files_err
	end

	local target_status = requested_status:lower()
	local records = {}
	local parse_failures = 0

	for _, path in ipairs(files) do
		local parsed = parser.parse_file(path)

		if not parsed then
			parse_failures = parse_failures + 1
		else
			local session_data = parsed.frontmatter and parsed.frontmatter.data or {}

			for _, example in ipairs(parsed.examples or {}) do
				local status_value = ""

				if example.fields and example.fields.Status ~= nil then
					status_value = normalize_value(example.fields.Status)
				end

				if status_value ~= "" and status_value:lower() == target_status then
					table.insert(records, build_record(path, session_data, example, cfg.example or {}))
				end
			end
		end
	end

	sort_records(records)

	return {
		scope = "status",
		value = requested_status,
		records = records,
		session_path = "",
		parse_failures = parse_failures,
		corpus_glob = corpus_glob,
	}
end

local function resolve_output_dir(cfg)
	local export_cfg = cfg.export or {}
	local output_dir = normalize_value(export_cfg.output_dir)

	if output_dir == "" then
		output_dir = "export"
	end

	if not util.is_absolute_path(output_dir) then
		output_dir = util.join_path(vim.fn.getcwd(), output_dir)
	end

	output_dir = util.normalize_path(output_dir)

	local mkdir_ok = vim.fn.mkdir(output_dir, "p")

	if mkdir_ok == 0 and vim.fn.isdirectory(output_dir) ~= 1 then
		return nil, string.format("failed to create export directory: %s", output_dir)
	end

	return output_dir
end

local function build_output_basename(bundle)
	local stamp = os.date("%Y%m%d-%H%M%S")
	local token = "export"

	if bundle.scope == "example" then
		token = sanitize_token(bundle.value)
	elseif bundle.scope == "session" then
		local session_path = normalize_value(bundle.session_path)

		if session_path ~= "" then
			token = sanitize_token(vim.fn.fnamemodify(session_path, ":t:r"))
		else
			token = "session"
		end
	elseif bundle.scope == "status" then
		token = "status-" .. sanitize_token(bundle.value)
	end

	return string.format("elicit-%s-%s-%s", bundle.scope, token, stamp)
end

local function ensure_unique_output_path(dir, basename, extension)
	local candidate = util.join_path(dir, basename .. "." .. extension)
	local index = 1

	while util.file_exists(candidate) do
		candidate = util.join_path(dir, string.format("%s-%02d.%s", basename, index, extension))
		index = index + 1
	end

	return candidate
end

local function markdown_field_lines(record)
	local lines = {}

	for _, field in ipairs(record.example.fields) do
		if field.name ~= "Status" then
			local value = compact_text(field.value)

			if value ~= "" then
				table.insert(lines, string.format("- %s: %s", field.name, value))
			end
		end
	end

	if #lines == 0 then
		table.insert(lines, "- (no exported fields)")
	end

	return lines
end

local function render_markdown(bundle)
	local lines = {
		"# Elicit Export",
		"",
		string.format("- Scope: %s", bundle.scope),
		string.format("- Generated: %s", os.date("%Y-%m-%d %H:%M:%S")),
		string.format("- Count: %d", #bundle.records),
	}

	if bundle.scope == "status" then
		table.insert(lines, string.format("- Status filter: %s", bundle.value))
	end

	table.insert(lines, "")

	for _, record in ipairs(bundle.records) do
		table.insert(lines, string.format("## %s", record.example.id))
		table.insert(lines, string.format("- Source: %s:%d", relative_path(record.path), record.example.start_line))

		local speaker = compact_text(record.session.speaker)

		if speaker ~= "" then
			table.insert(lines, string.format("- Speaker: %s", speaker))
		end

		local session_number = compact_text(record.session.session)

		if session_number ~= "" then
			table.insert(lines, string.format("- Session: %s", session_number))
		end

		for _, field_line in ipairs(markdown_field_lines(record)) do
			table.insert(lines, field_line)
		end

		table.insert(lines, "")
	end

	return lines
end

local function typst_string(value)
	local text = tostring(value or "")

	text = text:gsub("\\", "\\\\")
	text = text:gsub('"', '\\"')
	text = text:gsub("\r", "")
	text = text:gsub("\n", "\\n")

	return '"' .. text .. '"'
end

local function field_value(record, target_name)
	for _, field in ipairs(record.example.fields) do
		if field.name == target_name then
			return compact_text(field.value)
		end
	end

	return ""
end

local function render_typst(bundle)
	local lines = {
		"// Generated by elicit.nvim",
		string.format("// Scope: %s", bundle.scope),
		string.format("// Count: %d", #bundle.records),
		"",
		"#let elicit_gloss(id, text, segmentation, gloss, translation) = [",
		"  == #id",
		"  #if text != \"\" [#text]",
		"  #if segmentation != \"\" [#linebreak() #segmentation]",
		"  #if gloss != \"\" [#linebreak() #smallcaps[#gloss]]",
		"  #if translation != \"\" [#linebreak() _#translation_]",
		"]",
		"",
	}

	for _, record in ipairs(bundle.records) do
		local text = field_value(record, "Text")
		local segmentation = field_value(record, "Segmentation")
		local gloss = field_value(record, "Gloss")
		local translation = field_value(record, "Translation")

		table.insert(lines, string.format("// source: %s:%d", relative_path(record.path), record.example.start_line))
		table.insert(lines, "#elicit_gloss(")
		table.insert(lines, string.format("  %s,", typst_string(record.example.id)))
		table.insert(lines, string.format("  %s,", typst_string(text)))
		table.insert(lines, string.format("  %s,", typst_string(segmentation)))
		table.insert(lines, string.format("  %s,", typst_string(gloss)))
		table.insert(lines, string.format("  %s,", typst_string(translation)))
		table.insert(lines, ")")
		table.insert(lines, "")
	end

	return lines
end

local function encode_json(value)
	if vim.json and vim.json.encode then
		local ok, encoded = pcall(vim.json.encode, value)

		if ok then
			return encoded
		end
	end

	local ok, encoded = pcall(vim.fn.json_encode, value)

	if ok then
		return encoded
	end

	return nil, "failed to encode JSON"
end

local function render_json(bundle)
	local payload = {
		scope = bundle.scope,
		value = bundle.value,
		generated_at = os.date("%Y-%m-%dT%H:%M:%S"),
		count = #bundle.records,
		items = {},
	}

	for _, record in ipairs(bundle.records) do
		local fields = {}

		for _, field in ipairs(record.example.fields) do
			table.insert(fields, {
				name = field.name,
				value = field.value,
			})
		end

		table.insert(payload.items, {
			source = {
				path = record.path,
				line = record.example.start_line,
			},
			session = record.session,
			example = {
				id = record.example.id,
				fields = fields,
			},
		})
	end

	local encoded, encode_err = encode_json(payload)

	if not encoded then
		return nil, encode_err
	end

	return { encoded }
end

local function write_lines(path, lines)
	local ok, write_err = pcall(vim.fn.writefile, lines, path)

	if not ok then
		return nil, string.format("failed to write export file: %s", tostring(write_err))
	end

	return true
end

local function collect_scope_data(scope, value, cfg)
	if scope == "example" then
		return collect_example_scope(value, cfg)
	end

	if scope == "session" then
		return collect_session_scope(cfg)
	end

	if scope == "status" then
		return collect_status_scope(value, cfg)
	end

	return nil, string.format("invalid export scope '%s'", scope)
end

local function render_scope(format_name, bundle)
	if format_name == "markdown" then
		return render_markdown(bundle)
	end

	if format_name == "typst" then
		return render_typst(bundle)
	end

	if format_name == "json" then
		return render_json(bundle)
	end

	return nil, string.format("invalid export format '%s'", format_name)
end

function M.formats()
	return vim.deepcopy(FORMATS)
end

function M.scopes()
	return vim.deepcopy(SCOPES)
end

function M.run(format_name, scope, value)
	local normalized_format = normalize_format(format_name)
	local normalized_scope = normalize_scope(scope)

	if not FORMAT_SET[normalized_format] then
		return nil, string.format("invalid export format '%s'", tostring(format_name))
	end

	if not SCOPE_SET[normalized_scope] then
		return nil, string.format("invalid export scope '%s'", tostring(scope))
	end

	local cfg = config.get()
	local bundle, collect_err = collect_scope_data(normalized_scope, value, cfg)

	if not bundle then
		return nil, collect_err
	end

	local output_dir, output_dir_err = resolve_output_dir(cfg)

	if not output_dir then
		return nil, output_dir_err
	end

	local extension = FORMAT_EXTENSION[normalized_format]
	local basename = build_output_basename(bundle)
	local output_path = ensure_unique_output_path(output_dir, basename, extension)
	local lines, render_err = render_scope(normalized_format, bundle)

	if not lines then
		return nil, render_err
	end

	local write_ok, write_err = write_lines(output_path, lines)

	if not write_ok then
		return nil, write_err
	end

	if bundle.parse_failures and bundle.parse_failures > 0 then
		vim.notify(string.format("elicit.nvim: skipped %d unreadable file%s during export", bundle.parse_failures, bundle.parse_failures == 1 and "" or "s"), vim.log.levels.WARN)
	end

	vim.notify(string.format("elicit.nvim: exported %d example%s to %s", #bundle.records, #bundle.records == 1 and "" or "s", output_path), vim.log.levels.INFO)

	return output_path
end

return M
