
local env,db=env,env.getdb()
local cfg=env.set
local autotrace={}
local stmt=[[show warnings]]
local term=nil
function autotrace.trace(item)
    if autotrace.is_exec then return end
    if term then cfg.set('TERMOUT','on') end
    local db,sql,sql_id=item[1],item[2]
    if not db or not sql then return end
    local typ,objtype,objname=db.get_command_type(sql)
    if db:is_internal_call() or typ=='SHOW' then return end
    local done,rs=pcall(db.exec_cache,db,stmt,{},'Internal_GetSQLSTATS_Next')
    if done then
        rs=db.resultset:rows(rs,-1)[2]
        if rs then
            env.warn("WARNING %s: %s",rs[2],rs[3])
        end
    else
        print(rs)
    end
end

function autotrace.onload()
    env.event.snoop("AFTER_DB_EXEC",autotrace.trace,nil,99)

end
return autotrace