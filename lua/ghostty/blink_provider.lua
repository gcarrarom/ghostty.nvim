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

-- Blink provider interface: provide completion items
-- We keep this minimal and defensive.
function M.complete(ctx, callback)
	-- Only for ghostty filetype
	if vim.bo.filetype ~= "ghostty" then
		return callback({ items = {}, is_incomplete = false })
	end

	local ok, mod = pcall(require, "ghostty.complete")
	if not ok then
		return callback({ items = {}, is_incomplete = false })
	end

	local ok2, raw = pcall(mod.items_for_cursor)
	if not ok2 then
		return callback({ items = {}, is_incomplete = false })
	end

	return callback({ items = to_items(raw), is_incomplete = true })
end

return M
