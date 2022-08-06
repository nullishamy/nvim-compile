local M = {}

function M.workspace_path()
  return vim.fn.getcwd()
end

function M.buf_path()
  local val = vim.fn.expand('%:p')

  if string.len(val) == 0 then
    return nil
  end

  return val
end

return M
