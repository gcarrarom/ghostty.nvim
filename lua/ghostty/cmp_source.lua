local source = {}

function source:new()
	return setmetatable({}, { __index = source })
end

function source:is_available()
	return vim.bo.filetype == "ghostty"
end

function source:get_debug_name()
	return "ghostty"
end

function source:complete(_, callback)
	local ok, mod = pcall(require, "ghostty.complete")
	if not ok then
		return callback({ items = {}, isIncomplete = false })
	end

	local items = mod.items_for_cursor()
	-- Map string kinds to cmp kinds
	local cmp = require("cmp")
	local kind_map = {
		Property = cmp.lsp.CompletionItemKind.Property,
		Value = cmp.lsp.CompletionItemKind.Value,
		Function = cmp.lsp.CompletionItemKind.Function,
	}

	local out = {}
	for _, it in ipairs(items) do
		table.insert(out, {
			label = it.label,
			kind = kind_map[it.kind] or cmp.lsp.CompletionItemKind.Text,
			insertText = it.label,
		})
	end

	callback({ items = out, isIncomplete = true })
end

return source
