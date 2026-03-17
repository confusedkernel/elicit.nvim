local ok, integration = pcall(require, "elicit.cmp")

if ok then
	integration.sync()
end
