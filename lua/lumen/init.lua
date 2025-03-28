local M = {}
local curl = require("plenary.curl")

-- Default configuration
M.config = {
	journal_dir = vim.fn.expand("~/lumen"), -- Default journal directory
	db_name = "lumen.db", -- Default database name
	anthropic_api_key = os.getenv("ANTHROPIC_API_KEY"), -- Get API key from environment
	model = "claude-3-5-sonnet-20241022", -- Default model
	template = function(date)
		return {
			"# Journal Entry: " .. date,
			"",
			"",
		}
	end,
}

-- Claude API endpoint
local CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"

-- Function to make HTTP requests
local function make_request(url, method, headers, body)
	-- Convert headers array to dictionary format for plenary.curl
	local header_dict = {
		["Content-Type"] = "application/json",
	}
	for _, header in ipairs(headers) do
		local key, value = header:match("([^:]+):%s*(.*)")
		if key and value then
			header_dict[key] = value
		end
	end

	local response = curl[method:lower()]( -- plenary.curl methods are lowercase
		url,
		{
			headers = header_dict,
			body = body and vim.fn.json_encode(body) or nil,
		}
	)

	if not response or response.status ~= 200 then
		error(string.format("API request failed: %s", vim.inspect(response)))
	end

	return vim.fn.json_decode(response.body)
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
	-- Escape BOTH the database path and the query
	local escaped_db = vim.fn.shellescape(db_path)
	local escaped_query = vim.fn.shellescape(query)

	-- Use -batch and -cmd for non-interactive execution
	local cmd = string.format("sqlite3 -batch %s %s", escaped_db, escaped_query)
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
		local template = M.config.template(date)
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

function M.analyze_journal_entry()
	-- Check if current file is in journal directory
	local current_file = vim.fn.expand("%:p")
	if not string.match(current_file, "^" .. vim.fn.escape(M.config.journal_dir, "%-%.()[]*+?^$")) then
		vim.notify("Current file is not in the journal directory", vim.log.levels.ERROR)
		return
	end

	-- Get current file content
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Get existing table schemas
	local schemas = get_database_info()
	local schemas_str = vim.inspect(schemas)

	-- Prepare prompt for Claude
	local prompt = [[
    Analyze this journal entry and generate SQLite statements to store any data points found.

    Rules:
    1. Return ONLY valid SQL statements, one per line
    2. Use ONLY existing tables - DO NOT create new tables
    3. Include ONLY INSERT statements for data
    4. Do not return any CREATE TABLE statements
    5. Do not drop or modify existing tables
    6. Use appropriate data types (TEXT, INTEGER, REAL, DATE)
    7. Add timestamps where appropriate
    8. Return only the SQL statements, no explanations
    9. Do not link any tables
    10. If there's data that doesn't fit into existing tables, ignore it

    Existing tables and their schemas:
    ]] .. schemas_str .. [[

    Journal content to analyze:
    ]] .. content

	-- Call Claude API
	local sql_statements = M.call_claude(prompt, nil)
	if not sql_statements then
		vim.notify("Failed to get SQL statements from Claude", vim.log.levels.ERROR)
		return
	end
	-- Execute all SQL statements at once
	local result = sqlite_exec(sql_statements)
	if result ~= nil then
		vim.notify("Successfully stored entries to the database.", vim.log.levels.INFO)
	else
		vim.notify("Failed to store entries to the database.", vim.log.levels.ERROR)
	end
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

-- Function to create a new table in the database
function M.create_table()
	-- Create input dialog for table name
	vim.ui.input({ prompt = "Enter table name: " }, function(table_name)
		if not table_name or table_name == "" then
			vim.notify("Table creation cancelled", vim.log.levels.INFO)
			return
		end

		-- Create buffer for SQL CREATE TABLE statement
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"-- Enter your CREATE TABLE statement below",
			"-- Example:",
			"-- CREATE TABLE " .. table_name .. " (",
			"--   id INTEGER PRIMARY KEY,",
			"--   name TEXT NOT NULL,",
			"--   value REAL,",
			"--   timestamp TEXT DEFAULT CURRENT_TIMESTAMP",
			"-- );",
			"",
			"CREATE TABLE " .. table_name .. " (",
			"  id INTEGER PRIMARY KEY,",
			"  -- Add your columns here",
			"  timestamp TEXT DEFAULT CURRENT_TIMESTAMP",
			");",
		})

		-- Open the buffer in a floating window
		local width = math.min(80, vim.o.columns - 4)
		local height = math.min(20, vim.o.lines - 4)

		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			style = "minimal",
			border = "rounded",
			title = " Create Table: " .. table_name .. " ",
			title_pos = "center",
		})

		-- Set buffer options
		vim.bo[buf].modifiable = true
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].filetype = "sql"

		-- Set window options
		vim.wo[win].wrap = false
		vim.wo[win].conceallevel = 0
		vim.wo[win].foldenable = false

		-- Add mappings for saving or canceling
		local opts = { silent = true, noremap = true, buffer = buf }
		vim.keymap.set("n", "<esc>", function()
			vim.api.nvim_win_close(win, true)
			vim.notify("Table creation cancelled", vim.log.levels.INFO)
		end, opts)

		vim.keymap.set("n", "<C-s>", function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local sql = table.concat(vim.tbl_filter(function(line)
				return not line:match("^%s*%-%-") -- Filter out comment lines
			end, lines), "\n")

			-- Execute the SQL statement
			local result = sqlite_exec(sql)
			vim.api.nvim_win_close(win, true)

			if result ~= nil then
				vim.notify("Table '" .. table_name .. "' created successfully", vim.log.levels.INFO)
			else
				vim.notify("Failed to create table", vim.log.levels.ERROR)
			end
		end, opts)

		-- Display help text at the bottom of the window
		vim.api.nvim_create_autocmd("BufEnter", {
			buffer = buf,
			once = true,
			callback = function()
				vim.api.nvim_echo({
					{ "Press <C-s> to save, <Esc> to cancel", "WarningMsg" },
				}, false, {})
			end,
		})
	end)
end

-- Setup function to allow user configuration
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Ensure journal directory exists
	if vim.fn.isdirectory(M.config.journal_dir) == 0 then
		vim.fn.mkdir(M.config.journal_dir, "p")
	end

	-- Create commands
	vim.api.nvim_create_user_command("LumenNew", function()
		M.create_journal_entry()
	end, {})

	vim.api.nvim_create_user_command("LumenDBInfo", function()
		M.show_db_info()
	end, {})

	vim.api.nvim_create_user_command("LumenAnalyze", function()
		M.analyze_journal_entry()
	end, {})

	vim.api.nvim_create_user_command("LumenCreateTable", function()
		M.create_table()
	end, {})
end

return M
