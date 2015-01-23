local env,db,os,java=env,env.oracle,os,java

local ora=db.C.ora
local sqlplus={script_dir=env.WORK_DIR.."oracle"..env.PATH_DEL.."sqlplus"}

function sqlplus.load(...)
    local tnsadm=tostring(java.system:getProperty("oracle.net.tns_admin"))
    local export=env.OS=="windows" and "set " or "export "
    local props={} 
    if tnsadm and tnsadm~="" then
        props[1]=export..'TNS_ADMIN='..tnsadm
    end

    props[2]='cd '..(env.OS=="windows" and "/d " or "")..sqlplus.script_dir
    if db.props.db_nls_lang then
        props[3]=export..'NLS_LANG='..db.props.db_nls_lang
    end

    local conn_str='sqlplus '..(env.packer.unpack_str(db.conn_str) or "/nolog").." "
    if db.props.service_name then
        conn_str=conn_str:gsub("%:[%w_]+ ",'/'..db.props.service_name)
    else

    end
    props[#props+1]=conn_str
    
    local args={...}
    for k,v in ipairs(args) do
        if type(v)=="string" and v:match(" ") then
            args[k]='"'..v..'"'
        end
    end
    
    local del=(env.OS=="windows" and " & " or " ; ")
    local cmd=table.concat(props,del)..' '..table.concat(args,' ')
    
    os.execute(cmd)
end

function sqlplus.rehash()
    sqlplus.cmdlist=ora.rehash(sqlplus.script_dir)
end

function sqlplus.run_script(cmd,...)
    if not sqlplus.cmdlist then
        sqlplus.rehash()
    end 

    if not cmd then
        return env.exec_command("HELP",{"SQL"})
    end

    cmd=cmd:upper()    
    if cmd=="-R" then
        return sqlplus.rehash()
    end
end

local help_ind=0
function sqlplus.helper(_,cmd)
    help_ind=help_ind+1
    if help_ind==2 and not sqlplus.cmdlist then
        sqlplus.rehash()
    end
    local help='Run SQL script under the "sqlplus" directory with SQL*Plus. Usage: sql <script_name> [parameters]. Not yet applicable.\n'
    return env.helper.get_sub_help(cmd,sqlplus.cmdlist,help)    
end

set_command(nil,"sqlplus",  "Switch to sqlplus with same login, the working folder is 'oracle/sqlplus'. Usage: sqlplus [other args]",sqlplus.load,false,9)
--env.set_command(nil,"sql", sqlplus.helper,sqlplus.run_script,false,9)

return sqlplus