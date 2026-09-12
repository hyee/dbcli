local env=env
local loader=env.class(env.data_loader)

--mysql claims LOAD as a pass-through to the server (mysql.lua:onload), so the loader is
--published under its own name here instead of being shadowed by it
loader.load_command='dataload'
--only dataload is claimed here: unload already resolves to env.data_loader, leave it that way
loader.unload_command=false

return loader.new()
