local config = require("elicit.config")

local M = {}

local retry_group = vim.api.nvim_create_augroup("ElicitCmpSync", { clear = true })
local retry_registered = false
local source_id = nil

local function clear_retry_autocmds()
	if not retry_registered then
		return
	end

	retry_registered = false
	pcall(vim.api.nvim_clear_autocmds, { group = retry_group })
end

local function sync_callback()
	local synced, err = M.sync()

	if synced == true or synced == false then
		clear_retry_autocmds()
		return
	end

	if err ~= "nvim-cmp is not available" then
		clear_retry_autocmds()
	end
end

local function ensure_retry_autocmds()
	if retry_registered then
		return
	end

	retry_registered = true

	vim.api.nvim_create_autocmd({ "InsertEnter", "BufEnter" }, {
		group = retry_group,
		callback = sync_callback,
	})

	vim.api.nvim_create_autocmd("User", {
		group = retry_group,
		pattern = "CmpReady",
		callback = sync_callback,
	})
end

local function cmp_enabled()
	local abbrev_cfg = config.get().abbreviations or {}
	local cmp_cfg = abbrev_cfg.cmp or {}

	return cmp_cfg.enable == true
end

local function unregister_source()
	if not source_id then
		return
	end

	local ok, cmp = pcall(require, "cmp")

	if ok then
		pcall(cmp.unregister_source, source_id)
	end

	source_id = nil
end

function M.sync()
	if not cmp_enabled() then
		unregister_source()
		clear_retry_autocmds()
		return false
	end

	local ok, cmp = pcall(require, "cmp")

	if not ok then
		ensure_retry_autocmds()
		return nil, "nvim-cmp is not available"
	end

	if source_id then
		clear_retry_autocmds()
		return true
	end

	local source_ok, source = pcall(require, "cmp_elicit")

	if not source_ok then
		clear_retry_autocmds()
		return nil, source
	end

	local registered, id = pcall(cmp.register_source, "elicit", source)

	if not registered then
		clear_retry_autocmds()
		return nil, id
	end

	source_id = id
	clear_retry_autocmds()

	return true
end

return M
