local env=env
local db=env.getdb()
local usedb={}
function usedb.on_connect(db)
    local prompt=(db.connection_info.jdbc_alias or ""):match('^([^:/@]+)$')
    local dbname=db.props.database=="" and "None" or db.props.database:upper()
    prompt=(prompt or dbname):match("^([^,%.&]+)")
    env.set_prompt(nil,prompt,nil,2)
    env.set_title(("Database: %s   SQL-Mode: %s"):format(dbname,db.props.sql_mode))
end

function usedb.switch_db(name)
    db:internal_call("use "..name)
    db.props.database=db:get_value("select database()") or ""
    usedb.on_connect(db)
end

function usedb.onload()
    env.event.snoop("AFTER_MYSQL_CONNECT",usedb.on_connect)
    env.event.snoop("ON_DB_DISCONNECTED",function() env.set_title("") end)
    env.set_command(nil,{"use","\\u"},"Use another database. Takes database name as argument.",usedb.switch_db,false,2)
end

return usedb