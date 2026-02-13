local M = {}

function M.setup(opts)
	opts = opts or {}
	local target = vim.fn.expand(opts.target or "~/.config/ghostty/config")

	-- group so you can :autocmd! it cleanly if needed
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
				-- blank line ends block
				flush_block()
				table.insert(out, "")
			elseif line:match("^%s*#") then
				-- full-line comment: keep it, don't end block
				table.insert(block, { kind = "comment", text = line:gsub("%s+$", "") })
			else
				local a = parse_assignment(line)
				if a then
					max_key = math.max(max_key, #a.key)
					table.insert(block, { kind = "assign", key = a.key, val = a.val, cmt = a.cmt })
				else
					-- unknown line: end block and keep line
					flush_block()
					table.insert(out, line:gsub("%s+$", ""))
				end
			end
		end

		flush_block()
		return out
	end

	local function format_ghostty_buf(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local formatted = format_ghostty_lines(lines)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted)
	end

	-- Format before save
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = aug,
		pattern = target,
		desc = "Format Ghostty config on save (aligned blocks)",
		callback = function(args)
			format_ghostty_buf(args.buf)
		end,
	})

	-- Reload after save (macOS)
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = aug,
		pattern = target,
		desc = "Reload Ghostty when its config is saved",
		callback = function()
			local script = [[
        tell application "Ghostty" to activate
        delay 0.2
        tell application "System Events"
          tell process "Ghostty"
            click menu item "Reload Configuration" of menu 1 of menu bar item "Ghostty" of menu bar 1
          end tell
        end tell
      ]]
			vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
		end,
	})
end

return M
