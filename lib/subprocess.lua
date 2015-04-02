
local subproc=env.class()

function subproc:start(cmd,args,is_windows_cmd)
    local fdo,fdi
    self.pid = sys.pid()
    self.fdi, fdo = sys.handle(), sys.handle()
    self.fdo, fdi = sys.handle(), sys.handle()
    self.end_stack= 'dbcli_cmd_completed'
    self.stack_cmd='echo '..self.end_stack
    self.line_end=is_windows_cmd and '\r\n' or '\n'
    env.checkerr(self.fdi:pipe(fdo),'Unable to pipe file input to remote stdout!')
    env.checkerr(fdi:pipe(self.fdo),'Unable to pipe file output and remote stdin!')
    env.checkerr(sys.spawn(cmd, args, self.pid, fdi, fdo, fdo,false),SYS_ERR)
    self:exec("echo off")
    --fdo:close()
end

function subproc:exec(line)
    local out,count
    if type(line)=="string" then
        line={line}
    elseif type(line)~="table" then
        return
    end
    line[#line+1]=self.stack_cmd
    self.fdo:write(table.concat(line,self.line_end)..self.line_end)
    self.fdo:flush()
    local start=0
    while true do
        out=self.fdi:read()
        --if not out then break end
        out,count=out:gsub(self.end_stack,'')
        if start==1 then print(out) end
        if count>0 then
            start=start+1
            if start==2 then
                break 
            end
        end
    end
end

function subproc:close()
    self.fdi:close()
    self.fdo:close()
    self.pid:kill()
    self=nil
end

return subproc