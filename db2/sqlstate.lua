local env,stategroup,statecode=env
local db=env.getdb()
local sqlstate={}
function sqlstate.parse_error(info)
    local sqlcode=info.error:match('SQLCODE=%D?(%d+)')
    if sqlcode then info.error='SQL-'..sqlcode..': '..info.error:gsub('%s*SQLCODE.*',''):gsub('%.+%s*','.') end
    return info
end

function sqlstate.onload()
    env.event.snoop('ON_SQL_ERROR',sqlstate.parse_error,nil,1)
    env.event.snoop('ON_SQL_PARSE_ERROR',sqlstate.parse_error,nil,1)
end

return sqlstate
