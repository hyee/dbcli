
local env,db,os,java=env,env.oracle,os,java
local ora=db.C.ora
local sqlplus=env.class(env.scripter)

function sqlplus:ctor()
    self.db=env.oracle
    self.command="sp"
    self.help_title='Run SQL script under the "sql" directory. '
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."sqlplus",{}
end

function sqlplus:start(...)
    local tnsadm=tostring(java.system:getProperty("oracle.net.tns_admin"))
    local export=env.OS=="windows" and "set " or "export "
    local props={} 
    if tnsadm and tnsadm~="" then
        props[2]=export..'"TNS_ADMIN='..tnsadm..'"'
    end

    props[1]='cd '..(env.OS=="windows" and "/d " or "")..'"'..(self.work_path or self.script_dir)..'"'
    if db.props.db_nls_lang then
        props[3]=export..'"NLS_LANG='..db.props.db_nls_lang..'"'
    end
    local args={...}

    local conn_str='sqlplus '
    if #args>0 then
        for k,v in ipairs(args) do
            if v:sub(1,1) ~='-' then break end
            conn_str=conn_str..v..' '
            table.remove(args,1)
        end
    end

    conn_str=conn_str..(env.packer.unpack_str(db.conn_str) or "/nolog").." "
    if db.props.service_name then
        conn_str=conn_str:gsub("%:[%w_]+ ",'/'..db.props.service_name)
    else

    end
    props[#props+1]=conn_str
    
    
    for k,v in ipairs(args) do
        if type(v)=="string" and v:match(" ") then
            args[k]='"'..v..'"'
        end
    end

    local del=(env.OS=="windows" and " & " or " ; ")
    local cmd=table.concat(props,del)..' '..table.concat(args,' ')

    os.execute(cmd)
end

function sqlplus:before_exec(cmd,arg)
    
    local content=[[set feed off serveroutput on size 1000000 trimspool on long 5000 linesize 800 pagesize 9999
                    ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
                    set feed on
                    %s
                    @"%s" %s
                    exit;]]
    local args=env.parse_args('ORA',arg)
    local print_args,sql=false
    sql,args,print_args,file=self:get_script(cmd,args,print_args)
    if not file then return end
    env.checkerr(db:is_connect(),"Database is not connected.")
    local context=""
    for k,v in pairs(args) do 
        if v~="" then context=context..'DEF '..k..'='..v..'\n' end
    end
    content=content:format(context,file,arg or "")
    self.work_path=env.WORK_DIR.."cache"
    local tmpfile='sqlplus_temp.sql'
    env.write_cache(tmpfile,content:gsub('[\n\r]+%s+','\n')..'\n')
    self:start('-s','@'..tmpfile)
end

function sqlplus:after_exec()
    self.work_path=nil
end

function sqlplus:onload()
    set_command(self,"sqlplus",  "Switch to sqlplus with same login, the working folder is 'oracle/sqlplus'. Usage: sqlplus [other args]",self.start,false,9)
    env.remove_command(self.command)
    env.set_command(self,self.command,self.helper,{self.before_exec,self.after_exec},false,3)
end    

return sqlplus.new()