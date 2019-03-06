import config, signal from howl
import PropertyTable from howl.util

by_extension = {}
by_pattern = {}
by_shebang = {}
modes = {}
live = setmetatable {}, __mode: 'k'
mode_variables = {}

local by_name

layer_for = (name) -> 'mode:' .. name

instance_for_mode = (m) ->
  return live[m] if live[m]

  error "Unknown mode specified as parent: '#{m.parent}'", 3 if m.parent and not modes[m.parent]
  parent = if m.name != 'default' then by_name(m.parent or 'default')
  target = m.create m.name

  config_layer = layer_for m.name
  mode_config = config.proxy '', config_layer

  if target.default_config
    config.set_default(k, v, config_layer) for k,v in pairs target.default_config

  mode_vars = mode_variables[m.name]
  if mode_vars
    config.set_default(k, v, config_layer) for k,v in pairs mode_vars

  local instance
  instance = setmetatable {
    name: m.name
    config: mode_config
    :config_layer
    :parent
  }, {
    __index: (self, k) ->

      v = target[k]
      if v
        if type(v) == 'function'
          env = getfenv(v)
          new_env = setmetatable {
            super: (...) ->
              up = parent[k]
              error "No parent '#{k}' available", 2 unless up
              up instance, ...
          }, __index: env
          setfenv v, new_env
          self[k] = v

        return v

      parent and parent[k]
  }
  live[m] = instance
  instance

by_name = (name) ->
  modes[name] and instance_for_mode modes[name]

get_shebang = (file) ->
  return nil unless file.readable
  line = file\read!
  line and line\match '^#!%s*(.+)$'

for_file = (file) ->
  return by_name('default') unless file

  pattern_match = (value, patterns) ->
    return nil unless value
    for pattern, mode in pairs patterns
      return mode if value\umatch pattern

  def = pattern_match tostring(file), by_pattern
  def or= file.extension and by_extension[file.extension\lower!]
  def or= pattern_match get_shebang(file), by_shebang
  def or= modes['default']
  instance = def and instance_for_mode def
  error 'No mode available for "' .. file .. '"' if not instance
  instance

for_extension = (extension) ->
  by_extension[extension\lower!]

register = (mode = {}) ->
  error 'Missing field `name` for mode', 2 if not mode.name
  error 'Missing field `create` for mode', 2 if not mode.create

  multi_value = (v = {}) -> type(v) == 'string' and { v } or v

  by_extension[ext] = mode for ext in *multi_value mode.extensions
  by_pattern[pattern] = mode for pattern in *multi_value mode.patterns
  by_shebang[shebang] = mode for shebang in *multi_value mode.shebangs

  modes[mode.name] = mode
  modes[alias] = mode for alias in *multi_value mode.aliases

  parent = mode.parent and layer_for(mode.parent)
  config.define_layer layer_for(mode.name), :parent

  signal.emit 'mode-registered', name: mode.name

unregister = (name) ->
  mode = modes[name]
  if mode
    remove_from = (table, remove_mode) ->
      keys = [k for k, m in pairs table when m == remove_mode]
      table[k] = nil for k in *keys

    remove_from modes, mode
    remove_from by_extension, mode
    remove_from by_pattern, mode
    remove_from by_shebang, mode

    live[mode] = nil
    signal.emit 'mode-unregistered', :name

configure = (mode_name, variables) ->
  error 'Missing argument #1 (mode_name)', 2 unless mode_name
  error 'Missing argument #2 (variables)', 2 unless variables
  mode_vars = mode_variables[mode_name] or {}
  mode_vars[k] = v for k,v in pairs variables
  mode_variables[mode_name] = mode_vars

  -- update any already instantiated modes
  mode = modes[mode_name]
  if mode
    instance = live[mode]
    if instance
      instance.config[k] = v for k,v in pairs variables

signal.register 'mode-registered',
  description: 'Signaled right after a mode was registered',
  parameters:
    name: 'The name of the mode'

signal.register 'mode-unregistered',
  description: 'Signaled right after a mode was unregistered',
  parameters:
    name: 'The name of the mode'

return PropertyTable {
  :for_file
  :for_extension
  :by_name
  :register
  :unregister
  :configure
  names: get: -> [name for name in pairs modes]
}
