local M = {}

function M.insert_example()
	vim.notify(
		"elicit.nvim: :ElicitNewExample is scaffolded in phase 1 and implemented in phase 2.",
		vim.log.levels.INFO
	)
end

return M
