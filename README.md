# nvim-claude-plugin

A Neovim plugin for integrating [Claude Code](https://claude.ai/code) CLI directly into your editor.

## Features

- **Multiple sessions** — run several Claude Code sessions simultaneously, each in its own working directory
- **Persistent right panel** — Claude occupies the full right column and stays pinned even when other windows open
- **Input buffer** — compose multi-line prompts in a proper Neovim buffer with markdown highlighting, then send with a single key
- **Template picker** — browse and insert reusable prompt templates via Telescope with live preview
- **Status in lualine** — model name and token usage (input / output / cache) shown in the global statusline at all times
- **Session tabs in winbar** — active session directory shown in the Claude window's winbar with per-session tab labels

## Requirements

- Neovim 0.10+
- [Claude Code CLI](https://claude.ai/code) installed at `~/.npm-global/bin/claude`
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) (optional, for statusline component)

## Installation

### lazy.nvim (local)

```lua
{
  dir = vim.fn.expand("~/nvim-claude-plugin"),
  name = "claude_nvim",
  config = function()
    require("claude_nvim").setup()
  end,
}
```

### lualine integration

Add the status component to your lualine config:

```lua
require("lualine").setup({
  options = { globalstatus = true },
  sections = {
    lualine_x = {
      { function() return require("claude_nvim").status_line() end },
      -- ... other components
    },
  },
})
```

## Usage

### Commands

| Command | Description |
|---|---|
| `:Claude` | Toggle the Claude panel (opens session picker on first launch) |
| `:ClaudeNew` | Start a new session in a selected directory |
| `:ClaudeInput` | Open the input buffer |
| `:ClaudeTemplate` | Open the template picker |

### Keymaps

| Key | Mode | Description |
|---|---|---|
| `<M-n>` | Normal / Terminal | New session |
| `<M-i>` | Normal / Terminal | Open input buffer |
| `<leader>t` | Normal | Template picker |
| `<C-t>` | Terminal | Template picker |
| `<C-j>` | Normal (input buffer) | Send prompt to Claude |
| `q` | Normal (input buffer) | Close input buffer without sending |
| `<M-Right>` | Terminal | Switch to next session |
| `<M-Left>` | Terminal | Switch to previous session |
| `<C-h>` | Terminal | Move focus to left window |
| `i` | Normal (Claude window) | Enter terminal mode |

### Templates

Place markdown files in `~/.claude/templates/`. Each file becomes a template entry in the picker.

```
~/.claude/templates/
├── explain_code.md
├── code_review.md
├── fix_bug.md
└── write_tests.md
```

## Configuration

```lua
require("claude_nvim").setup({
  new_key      = "<M-n>",    -- keymap for new session
  input_key    = "<M-i>",    -- keymap for input buffer
  template_key = "<leader>t", -- keymap for template picker
})
```

## License

MIT
