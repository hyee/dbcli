env.var.define_column('QUERY,QUERY_LEN','NOPRINT')
local result=obj.redirect('table')
env.table.insert(result,1,[[select dbms_metadata.get_ddl('MATERIALIZED_VIEW_LOG',:object_name,:owner) DDL_STATEMENT from dual]])

result[#result]=[[
    SELECT /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
    FROM   (SELECT * FROM ALL_MVIEW_LOGS   WHERE LOG_OWNER = :owner AND LOG_TABLE = :object_name) T,
           (SELECT * FROM ALL_OBJECTS  WHERE OWNER = :owner AND OBJECT_NAME = :object_name) O
    WHERE  T.LOG_TABLE=O.OBJECT_NAME]]
env.table.insert(result,#result,[[
    SELECT /*topic="Depending Mviews"*/*
    FROM   (SELECT B.OWNER,B.NAME MVIEW_NAME,A.MASTER
            FROM   ALL_SNAPSHOT_LOGS A
            LEFT   JOIN ALL_REGISTERED_MVIEWS B
            ON     (a.snapshot_id=b.mview_id)
            WHERE  LOG_OWNER = :owner
            AND    LOG_TABLE = :object_name)
    LEFT   JOIN ALL_MVIEWS
    USING  (OWNER,MVIEW_NAME)]])
return result