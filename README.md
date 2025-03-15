# lumen.nvim

Lumen is a Neovim plugin for maintaining a daily journal where data is extracted as it is mentioned. The data is stored in a SQLite database using tables that you define. Claude analyzes your journal entries and populates your tables with the extracted data.

https://github.com/user-attachments/assets/90606d8d-bc71-42cd-88e8-28c52004bfe8

## Prerequisites

- Neovim >= 0.8.0
- SQLite3 installed on your system
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- An Anthropic API key for Claude

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'nilszeilon/lumen.nvim',
    dependencies = {
        'nvim-lua/plenary.nvim',
    },
    config = function()
        require('lumen').setup({
            -- Optional: override default config
            journal_dir = vim.fn.expand("~/lumen"),
            db_name = "lumen.db",
            anthropic_api_key = os.getenv("ANTHROPIC_API_KEY"),
            model = "claude-3-5-sonnet-20241022",
        })
    -- In your init.lua or other config file
    vim.keymap.set('n', '<leader>jn', require('lumen').create_journal_entry, { desc = "Create new journal entry" })
    vim.keymap.set('n', '<leader>jd', require('lumen').show_db_info, { desc = "Show journal database info" })
    vim.keymap.set('n', '<leader>ja', require('lumen').analyze_journal_entry, { desc = "Analyze current journal entry" })
    vim.keymap.set('n', '<leader>jt', require('lumen').create_table, { desc = "Create a new table" })

    end
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
    'username/lumen.nvim',
    requires = { 'nvim-lua/plenary.nvim' },
    config = function()
        require('lumen').setup()
    end
}
```
## Usage

### Creating Journal Entries

Use the `:LumenNew` command or the mapped keybinding (default: `<leader>jn`) to create a new journal entry for the current date. The file will be created in your configured journal directory with a filename based on the current date.

### Creating Database Tables

Before Lumen can extract data from your journal entries, you need to create tables to store this data:

1. Use the `:LumenCreateTable` command or the mapped keybinding (default: `<leader>jt`) 
2. Enter a name for your new table
3. Edit the SQL CREATE TABLE statement to define your table schema
4. Press `Ctrl+S` to save and create the table

Example table schemas you might create:

```sql
-- For tracking mood
CREATE TABLE mood (
  id INTEGER PRIMARY KEY,
  date TEXT NOT NULL,
  rating INTEGER NOT NULL,
  notes TEXT,
  timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

-- For tracking workouts
CREATE TABLE workout (
  id INTEGER PRIMARY KEY,
  date TEXT NOT NULL,
  type TEXT NOT NULL,
  duration INTEGER,
  notes TEXT,
  timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### Analyzing Journal Entries

After creating tables, you can analyze your journal entries:

1. Open a journal entry file
2. Use the `:LumenAnalyze` command or the mapped keybinding (default: `<leader>ja`)
3. Claude will analyze your journal content and extract data into your existing tables

### Viewing Database Information

Use the `:LumenDBInfo` command or the mapped keybinding (default: `<leader>jd`) to view information about your database, including:

- Database size and location
- SQLite version
- List of all tables with their schemas
- Row counts for each table

## License

MIT

