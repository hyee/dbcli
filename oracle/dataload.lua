local env=env
local loader=env.class(env.oracle.C.loader)

--oracle/loader.lua already publishes load/unload, so this module only adds the dataload name
loader.load_command='dataload'
loader.unload_command=false

return loader.new()
