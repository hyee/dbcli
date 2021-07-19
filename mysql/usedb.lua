local env=env
local db=env.getdb()
local usedb={}
function usedb.on_connect(db)
    local prompt=(db.connection_info.jdbc_alias or ""):match('^([^:/@]+)$')
    if not db.props.database then return end
    local dbname=db.props.database=="" and "None" or db.props.database
    prompt=(prompt or dbname):match("^([^,%.&]+)")
    env.set_prompt(nil,prompt,nil,2)
    env.set_title(("Database: %s@%s   Charset: %s"):format(db.props.db_user,dbname,db.props.charset))
    console.completer.defaultSchema=dbname
end

function usedb.switch_db(name,is_charset)
    db:assert_connect()
    if not name then
        if is_charset then
            print('Current charset is '..db.props.charset) 
            db.C.show.run("charset")
        else
            print('Current databases is '..db.props.database) 
            db.C.show.run("databases")
        end
        return
    end
    local stmt=(is_charset and 'set names ' or 'use ')..name
    db.props.database,db.props.charset=table.unpack(db:get_value(stmt..";select database(),@@character_set_client") or {'',''})
    usedb.on_connect(db)
end

function usedb.switch_charset(name)
    usedb.switch_db(name,true)
end

function usedb.onload()
    env.event.snoop("AFTER_MYSQL_CONNECT",usedb.on_connect)
    env.event.snoop("ON_DB_DISCONNECTED",function() console.completer.defaultSchema=nil;env.set_title("") end)
    env.set_command(nil,{"use","\\u"},"#Use another database",usedb.switch_db,false,2)
    env.set_command(nil,{"charset","\\c"},"#Use another character set",usedb.switch_charset,false,2)
end

return usedb