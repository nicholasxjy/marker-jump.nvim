local M = {}

local ns = vim.api.nvim_create_namespace("marker-jump")
local sign_group = "marker-jump.nvim"

local defaults = {
  keymaps = {
    toggle = nil,
    close = "q",
    refresh = "r",
    jump = "<CR>",
  },
  window = {
    width = 42,
    position = "right",
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
}

local state = {
  source_buf = nil,
  source_win = nil,
  list_buf = nil,
  list_win = nil,
  items = {},
  labels = {},
  mapped_labels_by_buf = {},
  sign_names = {},
  autocmd_group = nil,
}

M.config = vim.deepcopy(defaults)

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function truncate(value, max_width)
  if #value <= max_width then
    return value
  end
  return value:sub(1, math.max(1, max_width - 3)) .. "..."
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "MarkerJumpMark", { fg = "#e0af68", bold = true })
  vim.api.nvim_set_hl(0, "MarkerJumpActiveMark", { fg = "#63d4ff", bold = true })
  vim.api.nvim_set_hl(0, "MarkerJumpDim", { fg = "#6f7c8d" })
  vim.api.nvim_set_hl(0, "MarkerJumpHeader", { fg = "#93a1b4", bold = true })
  vim.api.nvim_set_hl(0, "MarkerJumpSelected", { bg = "#2c3f52" })
end

local function generate_labels()
  if M.config.labels then
    return vim.deepcopy(M.config.labels)
  end

  local chars = {}
  for i = 1, #M.config.jump_keys do
    chars[#chars + 1] = M.config.jump_keys:sub(i, i)
  end

  local labels = {}
  for _, first in ipairs(chars) do
    for _, second in ipairs(chars) do
      labels[#labels + 1] = first .. second
    end
  end
  return labels
end

local function match_function_name(line)
  local patterns = {
    "^%s*export%s+async%s+function%s+([%w_$]+)%s*%(",
    "^%s*export%s+function%s+([%w_$]+)%s*%(",
    "^%s*async%s+function%s+([%w_$]+)%s*%(",
    "^%s*local%s+function%s+([%w_%.:]+)%s*%(",
    "^%s*function%s+([%w_%.:%$]+)%s*%(",
    "^%s*([%w_%.:]+)%s*=%s*function%s*%(",
    "^%s*export%s+const%s+([%w_$]+)%s*=%s*async%s*[%(%w_]",
    "^%s*export%s+const%s+([%w_$]+)%s*=%s*[%(%w_].-=>",
    "^%s*const%s+([%w_$]+)%s*=%s*async%s*[%(%w_]",
    "^%s*const%s+([%w_$]+)%s*=%s*[%(%w_].-=>",
    "^%s*let%s+([%w_$]+)%s*=%s*[%(%w_].-=>",
    "^%s*var%s+([%w_$]+)%s*=%s*[%(%w_].-=>",
    "^%s*async%s+def%s+([%w_]+)%s*%(",
    "^%s*def%s+([%w_]+)%s*%(",
    "^%s*pub%s+async%s+fn%s+([%w_]+)%s*%(",
    "^%s*pub%s+fn%s+([%w_]+)%s*%(",
    "^%s*async%s+fn%s+([%w_]+)%s*%(",
    "^%s*fn%s+([%w_]+)%s*%(",
    "^%s*func%s+([%w_]+)%s*%(",
    "^%s*func%s*%([^)]*%)%s*([%w_]+)%s*%(",
  }

  for _, pattern in ipairs(patterns) do
    local name = line:match(pattern)
    if name then
      return name
    end
  end
end

local function scan(bufnr)
  local labels = generate_labels()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local items = {}

  for index, line in ipairs(lines) do
    local name = match_function_name(line)
    if name and labels[#items + 1] then
      items[#items + 1] = {
        label = labels[#items + 1],
        name = name,
        lnum = index,
        summary = truncate(trim(line), 72),
      }
    end
  end

  state.labels = labels
  state.items = items
  return items
end

local function clear_marks(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    pcall(vim.fn.sign_unplace, sign_group, { buffer = bufnr })
  end
end

local function ensure_sign(label)
  local name = "MarkerJump" .. label:gsub("%W", "_")
  if state.sign_names[name] then
    return name
  end

  vim.fn.sign_define(name, {
    text = label,
    texthl = "MarkerJumpMark",
  })
  state.sign_names[name] = true
  return name
end

local function render_marks(bufnr, items)
  clear_marks(bufnr)

  for index, item in ipairs(items) do
    if M.config.signs then
      vim.fn.sign_place(index, sign_group, ensure_sign(item.label), bufnr, {
        lnum = item.lnum,
        priority = 20,
      })
    end

    if M.config.virtual_text then
      vim.api.nvim_buf_set_extmark(bufnr, ns, item.lnum - 1, 0, {
        virt_text = { { "[" .. item.label .. "]", "MarkerJumpDim" } },
        virt_text_pos = "right_align",
      })
    end
  end
end

local function is_list_open()
  return state.list_win and vim.api.nvim_win_is_valid(state.list_win)
end

local function is_list_buffer(bufnr)
  return bufnr and bufnr == state.list_buf
end

local function is_source_buffer(bufnr)
  return bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and not is_list_buffer(bufnr)
    and vim.bo[bufnr].buftype == ""
end

local function delete_label_maps(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  for label in pairs(state.mapped_labels_by_buf[bufnr] or {}) do
    pcall(vim.keymap.del, "n", label, { buffer = bufnr })
  end
  state.mapped_labels_by_buf[bufnr] = nil
end

local function close_list_window()
  if is_list_open() then
    pcall(vim.api.nvim_win_close, state.list_win, true)
  end
  state.list_win = nil
  state.list_buf = nil
end

local function set_source(bufnr, winid)
  if not is_source_buffer(bufnr) then
    return false
  end

  if state.source_buf ~= bufnr then
    delete_label_maps(state.source_buf)
    clear_marks(state.source_buf)
  end

  local changed = state.source_buf ~= bufnr or state.source_win ~= winid
  state.source_buf = bufnr
  state.source_win = winid
  return changed
end

function M.close()
  delete_label_maps(state.source_buf)
  delete_label_maps(state.list_buf)
  clear_marks(state.source_buf)
  close_list_window()
end

local function item_for_label(label)
  for _, item in ipairs(state.items) do
    if item.label == label then
      return item
    end
  end
end

function M.jump_to_item(item)
  if not item or not state.source_win or not vim.api.nvim_win_is_valid(state.source_win) then
    return
  end

  vim.api.nvim_set_current_win(state.source_win)
  vim.api.nvim_win_set_cursor(state.source_win, { item.lnum, 0 })
  vim.cmd("normal! zz")

  if M.config.auto_close_on_jump then
    M.close()
  end
end

function M.jump_to_label(label)
  M.jump_to_item(item_for_label(label))
end

local function item_for_list_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local item_index = row - 2
  if item_index < 1 then
    return nil
  end
  return state.items[item_index]
end

function M.jump_from_list()
  M.jump_to_item(item_for_list_line())
end

local function map_label_jumps(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  state.mapped_labels_by_buf[bufnr] = state.mapped_labels_by_buf[bufnr] or {}
  for _, item in ipairs(state.items) do
    vim.keymap.set("n", item.label, function()
      M.jump_to_label(item.label)
    end, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = "Jump to " .. item.name,
    })
    state.mapped_labels_by_buf[bufnr][item.label] = true
  end
end

local function render_list()
  local width = M.config.window.width
  local lines = {
    string.format("%-4s %-28s %5s", "mark", "symbol / summary", "line"),
    string.rep("-", width),
  }

  for _, item in ipairs(state.items) do
    local name = truncate(item.name, 28)
    lines[#lines + 1] = string.format("%-4s %-28s %5d", item.label, name, item.lnum)
  end

  if #state.items == 0 then
    lines[#lines + 1] = "no functions found"
  end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(state.list_buf, ns, "MarkerJumpHeader", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(state.list_buf, ns, "MarkerJumpDim", 1, 0, -1)

  for index, item in ipairs(state.items) do
    local line = index + 1
    local mark_hl = index == 1 and "MarkerJumpActiveMark" or "MarkerJumpMark"
    vim.api.nvim_buf_add_highlight(state.list_buf, ns, mark_hl, line, 0, #item.label)
  end
end

local function set_window_option(name, value)
  pcall(vim.api.nvim_win_set_option, state.list_win, name, value)
end

local function set_list_options()
  vim.bo[state.list_buf].buftype = "nofile"
  vim.bo[state.list_buf].bufhidden = "wipe"
  vim.bo[state.list_buf].swapfile = false
  vim.bo[state.list_buf].filetype = "marker-jump"
  vim.bo[state.list_buf].modifiable = false
  vim.wo[state.list_win].number = false
  vim.wo[state.list_win].relativenumber = false
  vim.wo[state.list_win].signcolumn = "no"
  vim.wo[state.list_win].cursorline = M.config.window.cursorline ~= false
  vim.wo[state.list_win].wrap = false
  vim.wo[state.list_win].foldcolumn = "0"
  vim.wo[state.list_win].winfixwidth = true
  set_window_option("statuscolumn", "")

  if M.config.window.cursorline_hl then
    set_window_option("winhighlight", "CursorLine:" .. M.config.window.cursorline_hl)
  end
end

local function map_list_keys()
  local opts = { buffer = state.list_buf, silent = true }
  vim.keymap.set(
    "n",
    M.config.keymaps.close,
    M.close,
    vim.tbl_extend("force", opts, { desc = "Close marker-jump" })
  )
  vim.keymap.set(
    "n",
    M.config.keymaps.refresh,
    M.refresh,
    vim.tbl_extend("force", opts, { desc = "Refresh marker-jump" })
  )
  vim.keymap.set(
    "n",
    M.config.keymaps.jump,
    M.jump_from_list,
    vim.tbl_extend("force", opts, { desc = "Jump to selected function" })
  )
  map_label_jumps(state.list_buf)
end

local function open_list()
  vim.cmd("botright vertical " .. M.config.window.width .. "new")
  state.list_win = vim.api.nvim_get_current_win()
  state.list_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(state.list_buf, "MarkerJump")
  set_list_options()
  render_list()
  map_list_keys()

  if M.config.window.position == "left" then
    vim.api.nvim_set_current_win(state.list_win)
    vim.cmd("wincmd H")
    vim.cmd("vertical resize " .. M.config.window.width)
    state.list_win = vim.api.nvim_get_current_win()
  end

  if #state.items > 0 then
    vim.api.nvim_win_set_cursor(state.list_win, { 3, 0 })
  end

  if not M.config.window.focus_on_open and state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
    vim.api.nvim_set_current_win(state.source_win)
  end
end

function M.refresh()
  if not state.source_buf or not vim.api.nvim_buf_is_valid(state.source_buf) then
    local current_buf = vim.api.nvim_get_current_buf()
    if not is_source_buffer(current_buf) then
      return
    end
    state.source_buf = current_buf
  end
  if not state.source_win or not vim.api.nvim_win_is_valid(state.source_win) then
    local current_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(current_win) == state.source_buf then
      state.source_win = current_win
    end
  end

  delete_label_maps(state.source_buf)
  scan(state.source_buf)
  render_marks(state.source_buf, state.items)
  map_label_jumps(state.source_buf)

  if is_list_open() then
    delete_label_maps(state.list_buf)
    render_list()
    map_label_jumps(state.list_buf)
  end
end

function M.refresh_current_buffer()
  if not M.config.auto_refresh or not is_list_open() then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not is_source_buffer(bufnr) then
    return
  end

  set_source(bufnr, vim.api.nvim_get_current_win())
  M.refresh()
end

function M.open()
  if is_list_open() then
    return
  end

  set_source(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
  M.refresh()
  open_list()
end

function M.toggle()
  if is_list_open() then
    M.close()
  else
    M.open()
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  setup_highlights()

  state.autocmd_group = vim.api.nvim_create_augroup("marker-jump.nvim", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufReadPost" }, {
    group = state.autocmd_group,
    callback = function()
      vim.schedule(M.refresh_current_buffer)
    end,
  })

  if M.config.keymaps.toggle then
    vim.keymap.set("n", M.config.keymaps.toggle, M.toggle, {
      silent = true,
      desc = "Toggle marker-jump list",
    })
  end
end

return M
