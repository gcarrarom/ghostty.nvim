local M = {}

-- Cache results from ghostty CLI
local cache = {
	themes = nil,
	actions = nil,
	keybinds = nil,
	last = {},
}

local function syslist(cmd)
	if vim.fn.executable(cmd[1]) ~= 1 then
		return {}
	end
	local ok, out = pcall(vim.fn.systemlist, cmd)
	if not ok or type(out) ~= "table" then
		return {}
	end
	-- trim empties
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
	-- ghostty +list-themes output varies; we just return lines as candidates
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

local function get_keybinds()
	if cache.keybinds then
		return cache.keybinds
	end
	cache.keybinds = syslist({ "ghostty", "+list-keybinds" })
	return cache.keybinds
end

-- Minimal key list (extend whenever)
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

-- Determine whether cursor is completing a key (LHS) or value (RHS)
local function context_for_line(line, col0)
	-- col0 is 0-based byte index
	local before = line:sub(1, col0)
	local eq = before:find("=", 1, true)
	if not eq then
		return "key"
	end
	-- if we're after '=' -> value
	return "value"
end

-- Extract current token being completed
local function current_token(line, col0, kind)
	local before = line:sub(1, col0)
	if kind == "key" then
		local tok = before:match("([%w%-%_]+)$") or ""
		return tok
	else
		-- value token: anything after '=' up to cursor, trim leading spaces
		local rhs = before:match("=%s*(.-)$") or ""
		-- token: last non-space chunk
		local tok = rhs:match("([^%s]+)$") or rhs
		return tok
	end
end

-- Provide completion items for omnifunc
-- See :h complete-functions
function M.omnifunc(findstart, base)
	local bufnr = vim.api.nvim_get_current_buf()
	local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""

	if findstart == 1 then
		-- return byte index where completion starts
		local kind = context_for_line(line, col0)
		local start = col0
		if kind == "key" then
			while start > 0 and line:sub(start, start):match("[%w%-%_]") do
				start = start - 1
			end
			return start
		else
			-- value: walk back until whitespace
			while start > 0 and not line:sub(start, start):match("%s") do
				start = start - 1
			end
			return start
		end
	end

	-- findstart == 0: return matches
	local kind = context_for_line(line, col0)
	local tok = base or ""
	local matches = {}

	if kind == "key" then
		for _, k in ipairs(KEYS) do
			if starts_with(k, tok) then
				table.insert(matches, k)
			end
		end
		return matches
	end

	-- value completions based on key on this line
	local key = (line:match("^%s*([^=]+)%s*=") or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if key == "theme" then
		local themes = get_themes()
		for _, t in ipairs(themes) do
			if tok == "" or starts_with(t, tok) then
				table.insert(matches, t)
			end
		end
	elseif key == "keybind" then
		-- offer actions after '=' by suggesting action names.
		-- User still needs to type "shift+enter=" etc. This is just helpful.
		local actions = get_actions()
		for _, a in ipairs(actions) do
			if tok == "" or starts_with(a, tok) then
				table.insert(matches, a)
			end
		end
	elseif key == "macos-titlebar-style" then
		local vals = { "hidden", "transparent", "tabs" }
		for _, v in ipairs(vals) do
			if tok == "" or starts_with(v, tok) then
				table.insert(matches, v)
			end
		end
	end

	return matches
end

function M.clear_cache()
	cache.themes = nil
	cache.actions = nil
	cache.keybinds = nil
end

return M
