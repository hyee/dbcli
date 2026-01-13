env.var.define_column('QUERY,MVIEW_NAME','NOPRINT')
local result=obj.redirect('table')
result[#result]=result[#result]:gsub('TABLE','MVIEW')

env.table.insert(result,1,([[/*topic='DBMS_MVIEW.EXPLAIN_MVIEW'*/
DECLARE
    arr SYS.ExplainMVArrayType:=SYS.ExplainMVArrayType();
BEGIN
    DBMS_MVIEW.EXPLAIN_MVIEW('"%s"."%s"',arr);
    OPEN :v_cur FOR 
        SELECT CAPABILITY_NAME,DECODE(POSSIBLE,'T','TRUE','FALSE') POSSIBLE,RELATED_NUM,RELATED_TEXT,MSGTXT 
        FROM TABLE(arr)
        ORDER BY 1,MSGNO;
EXCEPTION WHEN OTHERS THEN NULL;
END;   
]]):format(obj.owner,obj.object_name))


env.table.insert(result,1,[[/*topic='MVIEW TEXT'*/
    SELECT QUERY TEXT FROM ALL_MVIEWS
    WHERE OWNER=:owner AND MVIEW_NAME=:object_name     
]])

if db:check_access("dba_mview_log_filter_cols",true) then
    env.var.define_column('FULL_TIME,INCR_TIME','smhd2')
    env.table.insert(result,#result, [[
        SELECT /*topic="Detail Relations"*/ /*+opt_param('_optimizer_unnest_scalar_sq' 'false')*/DISTINCT
              b.LAST_REFRESH_SCN "REFRESH|LAST_SCN",
              b.LAST_REFRESH_DATE "REFRESH|LAST_DATE",
              b.REFRESH_METHOD "REFRESH|METHOD",
              b.FULLREFRESHTIM "FULL|TIME",
              b.INCREFRESHTIM "INCR|TIME",
              trim(',' from decode(b.CONTAINS_VIEWS,'Y','CONTAINS_VIEWS,')
                  ||decode(b.UNUSABLE,'Y','UNUSABLE,')
                  ||decode(b.RESTRICTED_SYNTAX,'Y','RESTRICTED_SYNTAX,')
                  ||decode(b.INC_REFRESHABLE,'Y','INC_REFRESHABLE,')
                  ||decode(b.KNOWN_STALE,'Y','KNOWN_STALE,')) "REFRESH|ATTRS",
              a.detail_owner||'.'||a.detail_relation||' ['||a.detail_type||']' "SOURCE|OBJECT",
             (SELECT listagg(column_name,','||CHR(10)) WITHIN GROUP(ORDER BY column_name)
              FROM   dba_mview_log_filter_cols b
              WHERE b.owner=a.detail_owner AND b.name=a.detail_relation) "MLOG$|COLUMNS"
        FROM  (SELECT a.*,'"'||detail_owner||'"."'||detail_relation||'".' obj FROM all_summary_detail_tables a) a
        JOIN  all_summaries b
        USING (owner,summary_name)
        WHERE owner=:owner AND summary_name=:object_name]])
else
    env.table.insert(result,#result,
        [[SELECT /*topic="Detail Relations"*/* FROM ALL_MVIEW_DETAIL_RELATIONS WHERE OWNER=:owner AND MVIEW_NAME=:object_name]])
end


env.table.insert(result,#result,[[
    SELECT /*topic="Mview Refresh Schedules"*/
           REFGROUP "REFRESH|GROUP",
           ROWNER "REFRESH|OWNER",
           RNAME "REFRESH|NAME",
           TYPE  "REFRESH|TYPE",
           JOB   "JOB|ID",
           --JOB_NAME "JOB|NAME",
           PARALLELISM "JOB|DoP",
           BROKEN     "JOB|BROKEN",
           IMPLICIT_DESTROY  "IMPLICIT|DESTROY",   
           PUSH_DEFERRED_RPC  "DEFER|RPC",
           REFRESH_AFTER_ERRORS "REFRESH|ON_ERR",
           NEXT_DATE  "NEXT|DATE",
           INTERVAL   "SCHEDULE|INTERVAL",
           PURGE_OPTION "PURGE|OPTION",
           HEAP_SIZE    "HEAP|SIZE",
           ROLLBACK_SEG "ROLLBACK|SEGMENT"
    FROM   all_refresh_children
    WHERE  OWNER=:owner AND NAME=:object_name
    ORDER  BY 1]])

env.table.insert(result,#result,
    [[SELECT /*topic="Mview Logs"*/* FROM (SELECT distinct mview_id snapshot_id FROM ALL_REGISTERED_MVIEWS A WHERE OWNER=:owner AND NAME=:object_name) LEFT JOIN ALL_SNAPSHOT_LOGS USING(snapshot_id)]])
return result