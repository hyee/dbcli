local env,stategroup,statecode=env
local db=env.db2
local sqlstate={}
function sqlstate.parse_error(info)
    info.error=info.error:gsub('java[%.%w:]+','')
    return info
end

function sqlstate.onload()
    --env.event.snoop('ON_SQL_ERROR',sqlstate.parse_error,nil,1)
    --env.event.snoop('ON_SQL_PARSE_ERROR',sqlstate.parse_error,nil,1)  
end

return sqlstate
