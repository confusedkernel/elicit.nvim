local M = {}

function M.trim(value)
	if value == nil then
		return ""
	end

	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

function M.join_path(...)
	local parts = { ... }
	local cleaned = {}

	for _, part in ipairs(parts) do
		if part and part ~= "" then
			table.insert(cleaned, part:gsub("/+$", ""))
		end
	end

	return table.concat(cleaned, "/")
end

function M.split_words(text)
	local out = {}

	for word in string.gmatch(text or "", "%S+") do
		table.insert(out, word)
	end

	return out
end

function M.concat_from(list, index, separator)
	local out = {}

	for i = index, #list do
		table.insert(out, list[i])
	end

	return table.concat(out, separator or " ")
end

function M.to_set(list)
	local out = {}

	for _, item in ipairs(list or {}) do
		out[item] = true
	end

	return out
end

function M.today()
	return os.date("%Y-%m-%d")
end

return M
