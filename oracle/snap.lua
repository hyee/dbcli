local env=env

local snap=env.class(env.snapper)
function snap:ctor()
    self.db=env.getdb()
    self.command="snap"

    self.script_dir=self.db.ROOT_PATH.."snap"
end
--[[
function snap:before_exec_action()
    --self.db:internal_call("BEGIN DBMS_FLASHBACK.ENABLE_AT_TIME(systimestamp);END;")
    if self.db:is_connect() then self.db:internal_call("ALTER SESSION SET ISOLATION_LEVEL=SERIALIZABLE") end
end

function snap:after_exec_action()
    if self.db:is_connect() then 
        self.db:internal_call("BEGIN COMMIT;EXECUTE IMMEDIATE 'ALTER SESSION SET ISOLATION_LEVEL=READ COMMITTED';COMMIT;END;") 
    end
end
--]]
function snap:get_db_time()
    return self.db:get_value("select /*INTERNAL_DBCLI_CMD*/ to_char(sysdate,'yyyy-mm-dd hh24:mi:ss') from dual")
end

function snap:onload()
    self.validate_accessable=self.db.C.ora.validate_accessable
end

return snap.new()
