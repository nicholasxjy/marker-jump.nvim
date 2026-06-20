# marker-jump.nvim

A terminal-first Neovim plugin that marks functions in the current buffer and
lets you jump to them with short two-key labels.

## Features

- Scans the current buffer for common function declarations.
- Adds two-character marks in the signcolumn and optional virtual text hints.
- Opens a left or right TUI list with `mark  function  line`.
- Refreshes the marks and list when you switch to another buffer.
- Jumps from the source buffer by typing the visible mark, such as `aa` or `as`.
- Jumps from the list window by moving the cursor to a row and pressing Enter.

## Setup

```lua
require("marker-jump").setup({
  keymaps = {
    toggle = "<leader>mj",
  },
})
```

You can also map the toggle yourself:

```lua
vim.keymap.set("n", "<leader>mj", require("marker-jump").toggle)
```

## Commands

- `:MarkerJumpToggle`
- `:MarkerJumpOpen`
- `:MarkerJumpClose`
- `:MarkerJumpRefresh`

## Configuration

```lua
require("marker-jump").setup({
  keymaps = {
    toggle = nil,
    close = "q",
    refresh = "r",
    jump = "<CR>",
  },
  window = {
    width = 42,
    position = "right", -- "right" or "left"
    focus_on_open = true,
    cursorline = true,
    cursorline_hl = "MarkerJumpSelected",
  },
  jump_keys = "asdfghjklqwertyuiopzxcvbnm",
  labels = nil,
  virtual_text = true,
  signs = true,
  auto_refresh = true,
  auto_close_on_jump = false,
})
```

## Usage

Open the list with your configured toggle key or `:MarkerJumpToggle`. While the
list is open, the current buffer gets temporary marks like `aa`, `as`, and `df`.
Type a mark to jump directly to that function.

In the list window, move the cursor to a function row and press Enter to jump.
Press `r` to rescan the buffer or `q` to close the list.
