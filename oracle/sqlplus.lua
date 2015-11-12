
local env,db,os,java=env,env.oracle,os,java
local ora=db.C.ora
local sqlplus=env.class(env.scripter)

function sqlplus:ctor()
    self.db=env.oracle
    self.command="sp"
    self.name="sqlplus"
    self.help_title='Run SQL*Plus script under the "sqlplus" directory. '
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."sqlplus",{}
end

function sqlplus:start(...)
    env.find_extension(self.name)
    local tnsadm=tostring(java.system:getProperty("oracle.net.tns_admin"))
    local export=env.OS=="windows" and "set " or "export "
    local props={}
    if tnsadm and tnsadm~="" then
        props[2]=export..'"TNS_ADMIN='..tnsadm..'"'
    end

    local args,work_path={...},(self.work_path or self.script_dir)

    for i=#args,1,-1 do
        if args[i]:lower():find("^%-d") then
            work_path=args[i]:sub(3):gsub('"','')
            table.remove(args,i)
        end
    end

    props[1]='cd '..(env.OS=="windows" and "/d " or "")..'"'..work_path..'"'
    if db.props.db_nls_lang then
        props[3]=export..'"NLS_LANG='..db.props.db_nls_lang..'"'
    end


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
    --print(cmd)
    os.execute(cmd)
end

function sqlplus:run_sql(g_sql,g_args,g_cmd,g_file)
   
    for i=1,#g_sql do
        local sql,args,cmd,file=g_sql[i],g_args[i],g_cmd[i],g_file[i]
        local content=[[SET FEED OFF SERVEROUTPUT ON SIZE 1000000 TRIMSPOOL ON LONG 5000 LINESIZE 900 PAGESIZE 9999
                        ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
                        SET FEED ON ECHO OFF VERIFY OFF
                        DEF _WORK_DIR_="%s"
                        DEF _FILE_DIR_="%s"
                        DEF _SQLPLUS_DIR_="%s"
                        %s
                        @"%s" %s
                        EXIT;]]

        env.checkerr(db:is_connect(),"Database is not connected.")
        local context=""
        for k,v in pairs(args) do
            if v==db.NOT_ASSIGNED then v='' end
            local msg='DEF '..k.."='"..v.."'\n"
            context=context..msg
            if k:match("^V%d+$") then context=context..msg:gsub("V(%d+)",'%1',1) end
        end

        self.work_path=env._CACHE_PATH
        local subdir=args.FILE_OUTPUT_DIR
        if subdir then
            self.work_path=self.work_path..subdir
            os.execute('mkdir "'..self.work_path..'" >nul')
        end
        self.work_path=self.work_path:gsub(env.PATH_DEL..'+$','')
        local file_dir=file:gsub('[\\/][^\\/]+$',"")
        local tmpfile='sqlplus.tmp'
        tmpfile=self.work_path..env.PATH_DEL..tmpfile
        local f,err=io.open(tmpfile,'w')
        env.checkerr(f,"Unable to write file "..tmpfile)
        content=content:format(self.work_path,file_dir,self.script_dir,context,file,arg or ""):gsub('[\n\r]+%s+','\n')..'\n'
        f:write(content)
        f:close()
        self:start('-s','@"'..tmpfile..'"')
    end
end

function sqlplus:after_script()
    self.work_path=nil
end

function sqlplus:onload()
    set_command(self,"sqlplus",  "Switch to sqlplus with same login, the default working folder is 'oracle/sqlplus'. Usage: sqlplus [-d<work_path>] [other args]",self.start,false,9)
end

return sqlplus.new()