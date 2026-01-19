local uv,print=luv,print

local handle, pid,stdin

local function onexit(code, signal)
  print("exit")
end

local function onclose()
    print("close")
end

local p=true
local function onread(err, chunk)
  if (chunk) then
    env.printer.write(chunk)
    if p then
        p=false
        env.printer.write("select * from dual;\n")
        stdin:write("select * from dual;\n")
    end
  else
    print("exit")
  end
end

local function onshutdown()
  uv.close(handle, onclose)
end

local function process()
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    stdin = uv.new_pipe(false)

    handle, pid = uv.spawn("sqlplus", {
    stdio = {stdin, stdout, stderr},
    args={"/nolog"}
    }, onexit)
    uv.read_start(stdout, onread)
    uv.read_start(stderr, onread)
    uv.run()
end

local c={}
function c.onload()
    env.set_command(nil,"testprocess",nil,process,false,1)
end
return c