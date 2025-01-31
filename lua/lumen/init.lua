local M = {}

-- Default configuration
M.config = {
	journal_dir = vim.fn.expand("~/journal"), -- Default journal directory
	db_name = "lumen.db", -- Default database name
	anthropic_api_key = os.getenv("ANTHROPIC_API_KEY"), -- Get API key from environment
	model = "claude-2", -- Default model
}

-- Claude API endpoint
local CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"

-- Function to make HTTP requests
local function make_request(url, method, headers, body)
	local curl_command = string.format(
		'curl -s -X %s "%s" -H "Content-Type: application/json" %s',
		method,
		url,
		table.concat(
			vim.tbl_map(function(h)
				return string.format('-H "%s"', h)
			end, headers),
			" "
		)
	)

	if body then
		curl_command = string.format("%s -d '%s'", curl_command, vim.fn.json_encode(body))
	end

	local response = vim.fn.system(curl_command)
	if vim.v.shell_error ~= 0 then
		error(string.format("API request failed: %s", response))
	end

	return vim.fn.json_decode(response)
end

-- Function to call Claude API
function M.call_claude(prompt, context)
	if not M.config.anthropic_api_key then
		error("Anthropic API key not set. Please set ANTHROPIC_API_KEY environment variable or configure it in setup()")
	end

	local headers = {
		string.format("x-api-key: %s", M.config.anthropic_api_key),
		"anthropic-version: 2023-06-01",
	}

	local messages = {
		{
			role = "user",
			content = context and string.format("%s\n\nContext:\n%s", prompt, context) or prompt,
		},
	}

	local body = {
		model = M.config.model,
		messages = messages,
		max_tokens = 1024,
	}

	local response = make_request(CLAUDE_API_URL, "POST", headers, body)

	if response.error then
		error(string.format("Claude API error: %s", vim.inspect(response.error)))
	end

	return response.content[1].text
end

-- Function to execute SQLite commands
local function sqlite_exec(query)
	local db_path = vim.fs.joinpath(M.config.journal_dir, M.config.db_name)
	local cmd = string.format("sqlite3 %s '%s'", vim.fn.shellescape(db_path), query)
	local output = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		vim.notify("SQLite error: " .. output, vim.log.levels.ERROR)
		return nil
	end

	return output
end

-- Function to create a new journal entry
function M.create_journal_entry()
	-- Get today's date in YYYY-MM-DD format
	local date = os.date("%Y-%m-%d")
	local filename = date .. ".md"
	-- Use proper path joining for cross-platform compatibility
	local filepath = vim.fs.joinpath(M.config.journal_dir, filename)

	-- Create and open the file
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))

	-- If the file is new (empty), add a template
	if vim.fn.getfsize(filepath) == -1 or vim.fn.getfsize(filepath) == 0 then
		local template = {
			"# Journal Entry: " .. date,
			"",
			"## Notes",
			"",
		}
		vim.api.nvim_buf_set_lines(0, 0, -1, false, template)
	end
end

-- Private function to get database information
local function get_database_info()
	local info = {}

	-- Get database file size
	local db_path = vim.fs.joinpath(M.config.journal_dir, M.config.db_name)
	local size = vim.fn.getfsize(db_path)
	table.insert(info, string.format("Database Size: %.2f KB", size / 1024))
	table.insert(info, string.format("Location: %s", db_path))
	table.insert(info, "")

	-- Get SQLite version
	local version = sqlite_exec("SELECT sqlite_version();")
	if version then
		table.insert(info, string.format("SQLite Version: %s", version:gsub("%s+$", "")))
	end
	table.insert(info, "")

	-- Get all tables with row counts
	local tables_output = sqlite_exec('SELECT name FROM sqlite_master WHERE type="table" ORDER BY name')
	local tables = {}
	if tables_output then
		for table_name in tables_output:gmatch("([^\n]+)") do
			table.insert(tables, { table_name })
		end
	end

	table.insert(info, "Tables:")
	table.insert(info, string.rep("-", 40))

	-- For each table, get column information and row count
	if tables and #tables > 0 then
		for _, table_data in ipairs(tables) do
			local table_name = table_data[1]
			local columns_output = sqlite_exec(string.format("PRAGMA table_info(%s)", table_name))
			local columns = {}
			if columns_output then
				for line in columns_output:gmatch("([^\n]+)") do
					local cid, name, type, notnull, dflt_value, pk =
						line:match("(%d+)|([^|]+)|([^|]+)|(%d+)|([^|]*)|(%d+)")
					table.insert(columns, { tonumber(cid), name, type, tonumber(notnull), dflt_value, tonumber(pk) })
				end
			end

			local row_count_result = sqlite_exec(string.format("SELECT COUNT(*) FROM %s", table_name))
			local row_count = row_count_result and tonumber(row_count_result:match("(%d+)")) or 0

			-- Table header with row count
			table.insert(info, string.format("📊 %s (%d rows)", table_name, row_count))

			-- Column details
			for _, col in ipairs(columns) do
				local name = col[2]
				local type = col[3]
				local notnull = col[4] == 1 and "NOT NULL" or "NULL"
				local pk = col[6] == 1 and "PRIMARY KEY" or ""
				local constraints = table.concat(
					vim.tbl_filter(function(s)
						return s ~= ""
					end, { notnull, pk }),
					", "
				)

				if constraints ~= "" then
					table.insert(info, string.format("  ├─ %s (%s) - %s", name, type, constraints))
				else
					table.insert(info, string.format("  ├─ %s (%s)", name, type))
				end
			end
			table.insert(info, "")
		end
	else
		table.insert(info, "No tables found in database")
	end

	return info
end

-- Function to show database information in a floating window
function M.show_db_info()
	local info = get_database_info()

	-- Display the information in a floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, info)

	local width = math.min(80, vim.o.columns - 4)
	local height = math.min(#info + 2, vim.o.lines - 4)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Database Info ",
		title_pos = "center",
	})

	-- Set buffer options
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "dbinfo"

	-- Set window options
	vim.wo[win].wrap = false
	vim.wo[win].conceallevel = 0
	vim.wo[win].foldenable = false

	-- Close window with q or ESC
	local opts = { silent = true, noremap = true, buffer = buf }
	vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
	vim.keymap.set("n", "<esc>", "<cmd>close<cr>", opts)
end

-- Setup function to allow user configuration
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Ensure journal directory exists
	if vim.fn.isdirectory(M.config.journal_dir) == 0 then
		vim.fn.mkdir(M.config.journal_dir, "p")
	end

	-- Create commands
	vim.api.nvim_create_user_command("JournalNew", function()
		M.create_journal_entry()
	end, {})

	vim.api.nvim_create_user_command("JournalDBInfo", function()
		M.show_db_info()
	end, {})
end

return M
