local M = {}

-- Map our internal item kind strings to Blink-ish kinds (Blink doesn't require these)
local function to_items(raw_items)
	local items = {}
	for _, it in ipairs(raw_items or {}) do
		items[#items + 1] = {
			label = it.label,
			insertText = it.label,
			-- You can add detail/documentation later if you want
		}
	end
	return items
end

local function empty_response(callback)
	callback({
		items = {},
		is_incomplete_forward = false,
		is_incomplete_backward = false,
	})
end

function M.new(_opts)
	return setmetatable({}, { __index = M })
end

function M:enabled()
	return vim.bo.filetype == "ghostty"
end

function M:get_completions(_context, callback)
	if vim.bo.filetype ~= "ghostty" then
		empty_response(callback)
		return
	end

	local ok, mod = pcall(require, "ghostty.complete")
	if not ok then
		empty_response(callback)
		return
	end

	local ok_items, raw_items = pcall(mod.items_for_cursor)
	if not ok_items then
		empty_response(callback)
		return
	end

	callback({
		items = to_items(raw_items),
		is_incomplete_forward = true,
		is_incomplete_backward = true,
	})
end

return M
