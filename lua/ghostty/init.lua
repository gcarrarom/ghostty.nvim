local M = {}

local function safe_notify(msg, level)
	-- never let notify crash anything
	pcall(function()
		vim.schedule(function()
			if vim.notify then
				vim.notify(msg, level or vim.log.levels.WARN)
			end
		end)
	end)
end

local function xtry(fn, context)
	return xpcall(fn, function(err)
		local trace = debug.traceback(err, 2)
		safe_notify(("ghostty.nvim error (%s):\n%s"):format(context or "unknown", trace), vim.log.levels.ERROR)
		return err
	end)
end

function M.setup(opts)
	opts = opts or {}
	local target = vim.fn.expand(opts.target or "~/.config/ghostty/config")

	-- Feature flags (so you can quickly disable parts)
	local enable_format = opts.format ~= false
	local enable_reload = opts.reload ~= false

	local aug = vim.api.nvim_create_augroup("GhosttyConfig", { clear = true })

	-- Re-entrancy guards
	local formatting = false
	local reload_scheduled = false

	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = aug,
		pattern = target,
		desc = "Set ghostty filetype/options",
		callback = function(args)
			xtry(function()
				if vim.api.nvim_buf_get_name(args.buf) ~= target then
					return
				end
				vim.bo[args.buf].filetype = "ghostty"
				vim.bo[args.buf].commentstring = "# %s"

				_G._ghostty_omnifunc = _G._ghostty_omnifunc
					or function(findstart, base)
						return require("ghostty.complete").omnifunc(findstart, base)
					end
				vim.bo[args.buf].omnifunc = "v:lua._ghostty_omnifunc"
			end, "BufRead/BufNewFile")
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

		key = key:gsub("^%s+", ""):gsub("%s+$", "")
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
				-- keep comment lines, don't end block
				table.insert(block, { kind = "comment", text = line:gsub("%s+$", "") })
			else
				local a = parse_assignment(line)
				if a then
					max_key = math.max(max_key, #a.key)
					table.insert(block, { kind = "assign", key = a.key, val = a.val, cmt = a.cmt })
				else
					flush_block()
					table.insert(out, line:gsub("^%s+", ""):gsub("%s+$", ""))
				end
			end
		end

		flush_block()
		return out
	end

	local function do_format(bufnr)
		if not enable_format then
			return
		end
		if formatting then
			return
		end
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		if vim.api.nvim_buf_get_name(bufnr) ~= target then
			return
		end

		formatting = true
		local ok = xtry(function()
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local formatted = format_ghostty_lines(lines)

			-- avoid unnecessary buffer changes
			if table.concat(lines, "\n") ~= table.concat(formatted, "\n") then
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted)
			end
		end, "format")
		formatting = false
		return ok
	end

	local function do_reload()
		if not enable_reload then
			return
		end
		if vim.fn.has("mac") ~= 1 then
			return
		end
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

		xtry(function()
			vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
		end, "reload")
	end

	vim.api.nvim_create_autocmd("BufWritePre", {
		group = aug,
		pattern = target,
		desc = "Format Ghostty config on save (aligned blocks)",
		callback = function(args)
			if vim.api.nvim_buf_get_name(args.buf) ~= target then
				return
			end
			-- run synchronously so the write includes formatted content
			do_format(args.buf)
		end,
	})
	-- Reload on save: schedule OUTSIDE of autocmd stack and debounce without libuv timers
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = aug,
		pattern = target,
		desc = "Reload Ghostty when its config is saved",
		callback = function(args)
			if vim.api.nvim_buf_get_name(args.buf) ~= target then
				return
			end
			if reload_scheduled then
				return
			end
			reload_scheduled = true

			-- debounce using defer_fn (safer than libuv timers here)
			vim.defer_fn(function()
				reload_scheduled = false
				do_reload()
			end, 150)
		end,

		-- Register Blink provider (if Blink is installed)
		xtry(function()
			local ok_blink, blink = pcall(require, "blink.cmp")
			if not ok_blink then
				return
			end

			-- Blink exposes a registry for custom providers in recent versions.
			-- We'll attempt both common APIs defensively.
			local provider = require("ghostty.blink_provider")

			if blink and blink.register_provider then
				blink.register_provider("ghostty", provider)
			elseif package.loaded["blink.cmp.sources"] and require("blink.cmp.sources").register_provider then
				require("blink.cmp.sources").register_provider("ghostty", provider)
			end
		end, "blink-register"),
	})

	xtry(function()
		local ok_cmp, cmp = pcall(require, "cmp")
		if not ok_cmp then
			return
		end
		cmp.register_source("ghostty", require("ghostty.cmp_source"):new())
	end, "cmp-register")

	pcall(vim.api.nvim_del_user_command, "GhosttyClearCache")
	vim.api.nvim_create_user_command("GhosttyClearCache", function()
		require("ghostty.complete").clear_cache()
	end, { desc = "Clear ghostty.nvim completion cache" })

	pcall(vim.api.nvim_del_user_command, "GhosttyClearCache")
	vim.api.nvim_create_user_command("GhosttyClearCache", function()
		require("ghostty.complete").clear_cache()
	end, { desc = "Clear ghostty.nvim completion cache" })

	pcall(vim.api.nvim_del_user_command, "GhosttyReload")
	vim.api.nvim_create_user_command("GhosttyReload", function()
		do_reload()
	end, { desc = "Reload Ghostty config (macOS)" })

	pcall(vim.api.nvim_del_user_command, "GhosttyFormat")
	vim.api.nvim_create_user_command("GhosttyFormat", function()
		do_format(vim.api.nvim_get_current_buf())
	end, { desc = "Format Ghostty config buffer" })
end

return M
