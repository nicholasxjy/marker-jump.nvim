if vim.g.loaded_marker_jump == 1 then
  return
end
vim.g.loaded_marker_jump = 1

local marker_jump = require("marker-jump")

vim.api.nvim_create_user_command("MarkerJumpToggle", marker_jump.toggle, {})
vim.api.nvim_create_user_command("MarkerJumpOpen", marker_jump.open, {})
vim.api.nvim_create_user_command("MarkerJumpClose", marker_jump.close, {})
vim.api.nvim_create_user_command("MarkerJumpRefresh", marker_jump.refresh, {})
