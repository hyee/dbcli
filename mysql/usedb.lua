local env=env
local db=env[env.CURRENT_DB]
local usedb={}
function usedb.on_connect(db)
    env.set_title(("Database: %s    SQL-Mode: %s"):format(db.props.database,db.props.sql_mode))
end

function usedb.onload()
    env.event.snoop("AFTER_MYSQL_CONNECT",usedb.on_connect)
    env.event.snoop("ON_DB_DISCONNECTED",function() env.set_title("") end)
end

return usedb