# lumen.nvim

Lumen is my idea of having a single input, a daily journal where data is extracted as it is mentioned. The data is stored in a sqlite database, and will add tables over time to fit the data in your journal entries.

https://github.com/user-attachments/assets/2c45fa07-1db3-4c11-9135-3bf6b63b8cf8

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
## License

MIT

