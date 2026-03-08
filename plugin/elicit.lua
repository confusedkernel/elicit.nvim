if vim.g.loaded_elicit_nvim == 1 then
	return
end

vim.g.loaded_elicit_nvim = 1

require("elicit")._bootstrap()
