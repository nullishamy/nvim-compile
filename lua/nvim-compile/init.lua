local plenary = require('plenary')
local Path = plenary.path

local util = require('nvim-compile.util')
local Datastore = require('nvim-compile.datastore')
local log = require('nvim-compile.log')

local DEFAULT_OPTS = {
  path = Path:new(vim.fn.stdpath('data'), 'nvim-compile', 'data.json'),
  open_with = function(cmd)
    require('FTerm').scratch({ cmd = cmd })
  end
}

local compile = {
  loaded = false,
  config = nil,
  datastore = nil,
}

local function show_select(prompt, on_select)
  assert(on_select, 'on_select was not set')
  assert(prompt, 'prompt was not set')
  assert(compile.datastore, 'data was not set when calling `prompt_value`')

  -- tbl_values converts from an arbitrary indexable type to a table that select() requires
  vim.ui.select(vim.tbl_values(compile.datastore.data), {
    prompt = prompt,
    format_item = function(item)
      -- Remove the workspace portion from the file path
      -- + 2, 1 indexing & cut the leading slash
      return string.format('%s (%s) [%s]', item.workspace, string.sub(item.path, string.len(item.workspace) + 2),
        item.type == 'workspace' and 'W' or 'F')
    end,
  }, on_select)
end

function compile.setup(opts)
  if compile.loaded then
    return
  end

  opts = plenary.tbl.apply_defaults(opts, DEFAULT_OPTS)

  compile.config = opts

  compile.datastore = Datastore:new(opts)
  compile.datastore:init()

  compile.loaded = true
end

local function open_popup(val, index)
  local function center(str)
    local width = 60
    local shift = math.floor(width / 2) - math.floor(string.len(str) / 2)
    return string.rep(' ', shift) .. str
  end

  local Popup = require('nui.popup')

  local popup = Popup({
    position = "50%",
    size = {
      width = 60,
      height = 20
    },
    enter = true,
    focusable = false,
    zindex = 50,
    relative = "editor",
    border = {
      style = "rounded",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, {
    '',
    center('path:'),
    center(val.path),
    '',
    center('workspace:'),
    center(val.workspace),
    '',
    center('runs:'),
    center(val.cmd),
    '',
    center('type:'),
    center(val.type),
    '',
    '',
    '',
    center('keys:'),
    center('[q: quit]'),
    center('[d: delete]')
  })

  local map_opts = {
    nowait = true
  }

  popup:map('n', 'q', function()
    popup:unmount()
  end, map_opts)

  popup:map('n', 'd', function()
    table.remove(compile.datastore.data, index)
    compile.datastore:write()

    log.info(string.format('removed command for %s %s', val.type == 'workspace' and 'workspace' or 'buffer',
      val.type == 'workspace' and val.workspace or val.path))
  end, map_opts)

  popup:mount()
end

function compile.view()
  if not compile.loaded then
    return log.error('cannot `view` without calling `setup` first!')
  end

  assert(compile.config, 'config was not set when calling `view`')
  compile.datastore:init()

  show_select('Select a command', function(val, index)
    if index == nil then
      return
    end

    open_popup(val, index)
  end)
end

local function get_entry(path, is_workspace)
  local data = compile.datastore
  assert(data, 'ran get_entry with nil data')

  -- If it's a workspace val, check workspace, and only allow workspace entries, otherwise only check files
  -- This allows for individual files to compile differently even in the precence of a workspace setting
  -- And ensures that 'file' types do not get returned for workspace queries
  for _, val in pairs(data.data) do
    if is_workspace and val.workspace == path and val.type == 'workspace' then
      return val
    else if not is_workspace and val.path == path and val.type == 'file' then
        return val
      end
    end
  end

  return nil
end

local function run_associated()
  local cur_buf = util.buf_path()

  if string.len(cur_buf) == 0 then
    cur_buf = 'unknown'
  end

  -- If the file doesnt exist, or the buffer is modified, we dont want to run
  if not Path:new(cur_buf):exists() or vim.bo.modified then
    return log.warn(string.format('cannot run compile command for an unsaved buffer (path: %s)', cur_buf))
  end

  local workspace = util.workspace_path()

  -- Prioritise per-file commands, or fall back to the workspace
  local val = get_entry(cur_buf, false) or get_entry(workspace, true)

  if val == nil then
    return log.info('could not locate compile command for this file or workspace')
  end

  -- Double % to escape it for lua pattern matching
  local cmd = string.gsub(val.cmd, '%%', cur_buf)

  -- Log the command we're running so the user can see it
  compile.config.open_with(string.format([[ echo "(nvim-compile) executing '%s' \n" && %s ]], cmd, cmd))
end

local function set_command(cmd)
  local config = compile.config
  assert(config, 'ran set_command with nil config')

  local path = util.buf_path()

  if string.len(path) == 0 then
    log.warn('cannot set compile command for an un-named buffer')
    return
  end

  local workspace = util.workspace_path()

  local input = vim.fn.input('would you like to set this command for the (W)orkspace, or just the (f)ile? ')

  if input == nil then
    return
  end

  local should_set_workspace = input == 'w'
  local val = get_entry(should_set_workspace and workspace or path, should_set_workspace)
  local exists = val ~= nil

  if exists then
    local command_input = vim.fn.input(
      string.format(
        'a command already exists for this %s, do you want to override it? [y/N] ',
        should_set_workspace and 'workspace' or 'buffer'
      )
    )

    if command_input == nil then
      return
    end

    local should_update = command_input == 'y'

    if should_update then
      assert(exists, 'entry did not exist (exists)')
      assert(val, 'entry did not exist (val)')

      val.cmd = cmd
    end

    return
  end


  -- If it doesn't exist, set it
  table.insert(compile.datastore.data, {
    path = path,
    cmd = cmd,
    -- Set the workspace regardless, we need to know for the checks above
    workspace = workspace,
    type = should_set_workspace and 'workspace' or 'file'
  })

  compile.datastore:write()
end

function compile.run(...)
  if not compile.loaded then
    return log.error('cannot `run` without calling `setup` first!')
  end

  -- Init here too, in case the file was deleted after `setup` was called
  compile.datastore:init()

  local args = { ... }

  local next = next(args)

  -- If there's no args, we get passed an empty string
  if next == nil or string.len(args[next]) == 0 then
    -- Run the associated command, no command was passed
    run_associated()
  else
    -- Set the command based on the args
    -- `args` should be all strings, no need to convert to strings
    set_command(table.concat(args, ' '))
  end
end

return compile
