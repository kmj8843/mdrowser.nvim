local M = {}

local state = {
	bufnr = nil,
	winid = nil,
}

local function trim(str)
	if str == nil then
		return ""
	end
	if vim.trim then
		return vim.trim(str)
	end
	return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function extract_domain(url)
	if not url or url == "" then
		return nil
	end
	local domain = url:match("^(https?://[^/%s]+)")
	if not domain then
		domain = url:match("^(%a+://[^/%s]+)")
	end
	return domain
end

local function ensure_output_target()
	if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
		state.bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.bufnr })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.bufnr })
		vim.api.nvim_set_option_value("swapfile", false, { buf = state.bufnr })
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = state.bufnr })
		state.winid = nil
	end

	if not (state.winid and vim.api.nvim_win_is_valid(state.winid)) then
		vim.cmd("vsplit")
		state.winid = vim.api.nvim_get_current_win()
	end

	vim.api.nvim_win_set_buf(state.winid, state.bufnr)

	return state.bufnr, state.winid
end

local function display_markdown(lines)
	vim.schedule(function()
		local bufnr = ensure_output_target()
		if not bufnr then
			return
		end
		vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
		vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
	end)
end

local function run_command(url)
	local cleaned = trim(url)
	if cleaned == "" then
		return
	end

	local domain = extract_domain(cleaned)
	if not domain then
		vim.notify("[mdrowser] Failed to extract domain from URL", vim.log.levels.ERROR)
		return
	end

	local escaped_url = vim.fn.shellescape(cleaned)
	local escaped_domain = vim.fn.shellescape(domain)
	local cmd = string.format("curl --no-progress-meter %s | html2markdown --domain=%s", escaped_url, escaped_domain)

	local stdout, stderr = {}, {}
	local job = vim.fn.jobstart({ "bash", "-lc", cmd }, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				stdout[#stdout + 1] = line
			end
		end,
		on_stderr = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line ~= "" then
					stderr[#stderr + 1] = line
				end
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				local message = #stderr > 0 and table.concat(stderr, "\n")
					or string.format("Command exited with code %d", code)
				vim.schedule(function()
					vim.notify("[mdrowser] " .. message, vim.log.levels.ERROR)
				end)
				return
			end
			if #stdout == 0 then
				stdout = { "" }
			elseif stdout[#stdout] == "" then
				stdout[#stdout] = nil
			end
			display_markdown(stdout)
		end,
	})

	if job <= 0 then
		vim.notify("[mdrowser] Failed to start command", vim.log.levels.ERROR)
	end
end

local function prompt_for_url()
	vim.ui.input({ prompt = "Fetch URL: " }, function(input)
		if not input or trim(input) == "" then
			return
		end
		run_command(input)
	end)
end

local function find_link_under_cursor()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local col = cursor[2] + 1 -- Lua index is 1-based
	local line = vim.api.nvim_get_current_line()
	local init = 1

	while true do
		local start_idx, end_idx, _, url = line:find("%[([^%]]+)%]%(([^)]+)%)", init)
		if not start_idx then
			return nil
		end
		if col >= start_idx and col <= end_idx then
			return url
		end
		init = end_idx + 1
	end
end

local function follow_link()
	local url = find_link_under_cursor()
	print(url)
	if not url or trim(url) == "" then
		vim.notify("[mdrowser] No markdown link under cursor", vim.log.levels.WARN)
		return
	end
	run_command(url)
end

local function ensure_command()
	vim.api.nvim_create_user_command("Mdrowser", function()
		M.url()
	end, { desc = "mdrowser: fetch URL" })
end

function M.url()
	prompt_for_url()
end

function M.follow()
	follow_link()
end

function M.setup()
	if vim.fn.executable("curl") ~= 1 then
		vim.schedule(function()
			vim.notify("[mdrowser] curl executables are required for this plugin to work.", vim.log.levels.ERROR)
		end)
		return
	end

	if vim.fn.executable("html2markdown") ~= 1 then
		vim.schedule(function()
			vim.notify(
				"[mdrowser] html2markdown executables are required for this plugin to work.",
				vim.log.levels.ERROR
			)
		end)
		return
	end

	ensure_command()
end

return M
