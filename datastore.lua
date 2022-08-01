---@class Datastore
Datastore = {
}

local Path = require('plenary.path')

function Datastore:new(config)
  self._path = config.path
  self.data = { }

  return self
end

function Datastore:init()
  local path = self:path()

  if not path:exists() then
    path:touch({ parents = path:parents() })
    path:write('[]', 'w')
  else
    self:read()
  end

  return self
end

function Datastore:path()
  return Path:new(self._path)
end

function Datastore:read()
  local path = self:path()
  local data = vim.json.decode(path:read())

  self.data = data
  return self
end

function Datastore:write()
  local path = self:path()
  local json = vim.json.encode(self.data)

  path:write(json, 'w')
  return self
end

return Datastore
