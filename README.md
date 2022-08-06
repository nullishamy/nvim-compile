# nvim-compile

A simple compile command implementation for neovim. This allows you to set a compile command for a workspace / buffer
and the run it with a keybind.

The default opts are
```lua
{
  path = Path:new(vim.fn.stdpath('data'), 'nvim-compile', 'data.json'),
  open_with = function (cmd)
    require('FTerm').scratch({ cmd = cmd })
  end,
  substitutions = {
    ['%%'] = function()
      return require('nvim-compile.util').buf_path() or 'unknown'
    end
  }
}
```

and are passed into `require('nvim-compile').setup()` to configure the plugin.

NOTE: You must call setup before you can use the plugin.

This plugin depends on the following:
- [plenary](https://github.com/nvim-lua/plenary.nvim)
- [nui](https://github.com/MunifTanjim/nui.nvim)
