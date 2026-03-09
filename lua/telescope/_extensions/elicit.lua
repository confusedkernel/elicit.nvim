local search = require("elicit.search")

local function run_picker(opts)
	return search.telescope(opts or {})
end

return require("telescope").register_extension({
	exports = {
		elicit = run_picker,
		search = run_picker,
	},
})
