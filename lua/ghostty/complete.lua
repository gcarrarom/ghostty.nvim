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

local function normalize_theme(line)
	line = (line:gsub("%s+$", ""))
	line = line:gsub("%s*%b()%s*$", "") -- remove trailing "(resources)" etc
	return line
end

local function get_themes()
	if cache.themes then
		return cache.themes
	end
	cache.themes = syslist({ "ghostty", "+list-themes", "--plain" })
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
	s = s:lower()
	prefix = prefix:lower()
	return s:sub(1, #prefix) == prefix
end

local function current_line_and_col()
	local bufnr = vim.api.nvim_get_current_buf()
	local row, col0 = unpack(vim.api.nvim_win_get_cursor(0)) -- col is 0-based
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
	return line, col0
end

local function context_for(line, col0)
	local before = line:sub(1, col0)
	local eq = before:find("=", 1, true)
	if eq then
		return "value"
	end
	return "key"
end

local function key_for_line(line)
	return (line:match("^%s*([^=]+)%s*=") or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function value_prefix(line, col0)
	local before = line:sub(1, col0)
	local rhs = before:match("=%s*(.-)$") or ""
	return rhs:gsub("^%s+", "")
end

function M.clear_cache()
	cache.themes = nil
	cache.actions = nil
end

-- Omni completion entry point
-- :h complete-functions
function M.omnifunc(findstart, base)
	local line, col0 = current_line_and_col()
	local kind = context_for(line, col0)

	if findstart == 1 then
		-- return byte-index start of completion
		local start = col0
		if kind == "key" then
			while start > 0 and line:sub(start, start):match("[%w%-%_]") do
				start = start - 1
			end
			return start
		else
			-- for value: complete from after '=' and spaces
			local eq = line:find("=", 1, true)
			if not eq then
				return col0
			end
			start = eq + 1
			while start <= #line and line:sub(start, start):match("%s") do
				start = start + 1
			end
			return start - 1 -- 0-based
		end
	end

	local matches = {}

	if kind == "key" then
		for _, k in ipairs(KEYS) do
			if base == "" or starts_with(k, base) then
				table.insert(matches, k)
			end
		end
		return matches
	end

	local key = key_for_line(line)
	local prefix = value_prefix(line, col0)

	if key == "theme" then
		for _, raw in ipairs(get_themes()) do
			local t = normalize_theme(raw)
			if t ~= "" and (prefix == "" or starts_with(t, prefix)) then
				table.insert(matches, t)
			end
		end
	elseif key == "macos-titlebar-style" then
		for _, v in ipairs({ "hidden", "transparent", "tabs" }) do
			if prefix == "" or starts_with(v, prefix) then
				table.insert(matches, v)
			end
		end
	elseif key == "keybind" then
		for _, a in ipairs(get_actions()) do
			if prefix == "" or starts_with(a, prefix) then
				table.insert(matches, a)
			end
		end
	end

	return matches
end

return M
