local M = {}

local cache = {
	themes = nil,
	actions = nil,
}

local function syslist(cmd)
	if vim.fn.executable(cmd[1]) ~= 1 then
		return {}
	end
	local ok, out = pcall(vim.fn.systemlist, cmd)
	if not ok or type(out) ~= "table" then
		return {}
	end
	local res = {}
	for _, s in ipairs(out) do
		s = (s:gsub("%s+$", ""))
		if s ~= "" then
			table.insert(res, s)
		end
	end
	return res
end

local function get_themes()
	if cache.themes then
		return cache.themes
	end
	cache.themes = syslist({ "ghostty", "+list-themes" })
	return cache.themes
end

local function get_actions()
	if cache.actions then
		return cache.actions
	end
	cache.actions = syslist({ "ghostty", "+list-actions" })
	return cache.actions
end

local KEYS = {
	"theme",
	"custom-shader",
	"macos-titlebar-style",
	"keybind",
	"font-family",
	"font-size",
	"background-opacity",
}

local function starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

local function line_context(line, col0)
	local before = line:sub(1, col0)
	if before:find("=", 1, true) then
		return "value"
	end
	return "key"
end

local function current_key(line)
	return (line:match("^%s*([^=]+)%s*=") or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.items_for_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
	local kind = line_context(line, col0)

	local items = {}

	if kind == "key" then
		local tok = (line:sub(1, col0):match("([%w%-%_]+)$") or "")
		for _, k in ipairs(KEYS) do
			if tok == "" or starts_with(k, tok) then
				table.insert(items, { label = k, kind = "Property" })
			end
		end
		return items
	end

	local key = current_key(line)
	local tok = (line:sub(1, col0):match("=%s*(.-)$") or "")
	tok = (tok:match("([^%s]+)$") or tok)

	if key == "theme" then
		for _, t in ipairs(get_themes()) do
			if tok == "" or starts_with(t, tok) then
				table.insert(items, { label = t, kind = "Value" })
			end
		end
	elseif key == "macos-titlebar-style" then
		for _, v in ipairs({ "hidden", "transparent", "tabs" }) do
			if tok == "" or starts_with(v, tok) then
				table.insert(items, { label = v, kind = "Value" })
			end
		end
	elseif key == "keybind" then
		-- Suggest actions (you can refine this later to only after "action:" etc.)
		for _, a in ipairs(get_actions()) do
			if tok == "" or starts_with(a, tok) then
				table.insert(items, { label = a, kind = "Function" })
			end
		end
	end

	return items
end

function M.clear_cache()
	cache.themes = nil
	cache.actions = nil
end

return M
