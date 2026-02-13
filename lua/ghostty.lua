local M = {}

function M.setup(opts)
	opts = opts or {}
	local target = vim.fn.expand(opts.target or "~/.config/ghostty/config")

	local aug = vim.api.nvim_create_augroup("GhosttyConfig", { clear = true })

	-- Filetype + commentstring for no-extension file
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = aug,
		pattern = target,
		desc = "Set ghostty filetype/options",
		callback = function()
			vim.bo.filetype = "ghostty"
			vim.bo.commentstring = "# %s"
		end,
	})

	local function parse_assignment(line)
		local main, cmt = line, nil
		local before, after = line:match("^(.-)%s+#%s*(.*)$")
		if before then
			main = before
			cmt = after
		end

		local key, val = main:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
		if not (key and val) then
			return nil
		end

		key = key:gsub("%s+$", "")
		return { key = key, val = val, cmt = cmt }
	end

	local function format_ghostty_lines(lines)
		local out = {}
		local block = {}
		local max_key = 0

		local function flush_block()
			if #block == 0 then
				return
			end

			for _, item in ipairs(block) do
				if item.kind == "comment" then
					table.insert(out, item.text)
				else
					local pad = string.rep(" ", max_key - #item.key)
					local line = ("%s%s = %s"):format(item.key, pad, item.val)

					if item.cmt ~= nil then
						if item.cmt ~= "" then
							line = line .. "  # " .. item.cmt
						else
							line = line .. "  #"
						end
					end

					table.insert(out, line)
				end
			end

			block = {}
			max_key = 0
		end

		for _, line in ipairs(lines) do
			if line:match("^%s*$") then
				flush_block()
				table.insert(out, "")
			elseif line:match("^%s*#") then
				table.insert(block, { kind = "comment", text = line:gsub("%s+$", "") })
			else
				local a = parse_assignment(line)
				if a then
					max_key = math.max(max_key, #a.key)
					table.insert(block, { kind = "assign", key = a.key, val = a.val, cmt = a.cmt })
				else
					flush_block()
					table.insert(out, line:gsub("%s+$", ""))
				end
			end
		end

		flush_block()
		return out
	end

	local function format_ghostty_buf(bufnr)
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local formatted = format_ghostty_lines(lines)

		-- avoid unnecessary buffer changes
		if table.concat(lines, "\n") == table.concat(formatted, "\n") then
			return
		end

		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted)
	end

	-- Format before save (protected)
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = aug,
		pattern = target,
		desc = "Format Ghostty config on save (aligned blocks)",
		callback = function(args)
			local ok, err = pcall(function()
				if vim.api.nvim_buf_get_name(args.buf) ~= target then
					return
				end
				format_ghostty_buf(args.buf)
			end)

			if not ok then
				vim.schedule(function()
					vim.notify("ghostty.nvim formatter error: " .. tostring(err), vim.log.levels.WARN)
				end)
			end
		end,
	})

	-- Debounce reload (prevents multiple rapid reloads)
	local reload_timer = nil

	local function reload_ghostty()
		if vim.fn.executable("osascript") ~= 1 then
			return
		end

		local script = [[
tell application "Ghostty" to activate
delay 0.2
tell application "System Events"
  tell process "Ghostty"
    click menu item "Reload Configuration" of menu 1 of menu bar item "Ghostty" of menu bar 1
  end tell
end tell
]]

		pcall(function()
			vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
		end)
	end

	-- Reload after save (protected)
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = aug,
		pattern = target,
		desc = "Reload Ghostty when its config is saved",
		callback = function(args)
			if vim.api.nvim_buf_get_name(args.buf) ~= target then
				return
			end

			-- debounce
			if reload_timer then
				reload_timer:stop()
				reload_timer:close()
			end

			reload_timer = vim.loop.new_timer()
			reload_timer:start(150, 0, function()
				reload_timer:stop()
				reload_timer:close()
				reload_timer = nil

				vim.schedule(function()
					reload_ghostty()
				end)
			end)
		end,
	})
end

return M
