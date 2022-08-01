local M = {}

function M.workspace_path()
  return vim.fn.getcwd()
end

function M.buf_path()
  return vim.fn.expand('%:p')
end

return M
