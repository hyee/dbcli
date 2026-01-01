env.var.define_column('QUERY,MVIEW_NAME','NOPRINT')
local result=obj.redirect('table')
env.table.insert(result,1,[[select dbms_metadata.get_ddl('MATERIALIZED_VIEW_LOG',:object_name,:owner) DDL_STATEMENT from dual]])

result[#result]=[[
    SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
    FROM   (SELECT * FROM ALL_MVIEW_LOGS   WHERE LOG_OWNER = :owner AND LOG_TABLE = :object_name) T,
           (SELECT * FROM ALL_OBJECTS  WHERE OWNER = :owner AND OBJECT_NAME = :object_name) O
    WHERE  T.LOG_TABLE=O.OBJECT_NAME]]
env.table.insert(result,#result,[[
    SELECT /*INTERNAL_DBCLI_CMD topic="Depending Mviews"*/*
    FROM   (SELECT snapshot_id snapid 
            FROM   ALL_SNAPSHOT_LOGS A
            WHERE  LOG_OWNER = :owner
            AND    LOG_TABLE = :object_name)
    LEFT   JOIN ALL_SNAPSHOTS
    USING  (snapid)]])
return result