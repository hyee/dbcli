env.var.define_column('QUERY,MVIEW_NAME','NOPRINT')
local result = obj.redirect('table')
result[#result] = result[#result]:gsub('table','mview')

env.table.insert(result, 1, ([[/*topic='DBMS_MVIEW.EXPLAIN_MVIEW'*/
DECLARE
    arr sys.explainmvarraytype := sys.explainmvarraytype();
BEGIN
    dbms_mview.explain_mview('"%s"."%s"', arr);
    OPEN :v_cur FOR
        SELECT capability_name,
               decode(possible, 'T', 'TRUE', 'FALSE') possible,
               related_num,
               related_text,
               msgtxt
        FROM   TABLE(arr)
        ORDER  BY 1, msgno;
EXCEPTION WHEN OTHERS THEN NULL;
END;
]]):format(obj.owner, obj.object_name))


env.table.insert(result, 1, [[/*topic='MVIEW TEXT'*/
    SELECT query text
    FROM   all_mviews
    WHERE  owner = :owner
    AND    mview_name = :object_name
]])

local col_table = db:check_access("dba_mview_log_filter_cols", true) and "dba_mview_log_filter_cols"
    or "(SELECT '' owner, '' name, '' column_name FROM dual)"

env.var.define_column('FULL|TIME,INCR|TIME','for','smhd2')
env.table.insert(result, #result, [[
    SELECT /*topic="Detail Relations"*/ /*+opt_param('_optimizer_unnest_scalar_sq' 'false')*/ DISTINCT
           b.last_refresh_scn "REFRESH|LAST_SCN",
           b.last_refresh_date "REFRESH|LAST_DATE",
           b.refresh_method "REFRESH|METHOD",
           b.fullrefreshtim "FULL|TIME",
           b.increfreshtim "INCR|TIME",
           TRIM(',' FROM decode(b.contains_views, 'Y', 'CONTAINS_VIEWS,')
               ||decode(b.unusable, 'Y', 'UNUSABLE,')
               ||decode(b.restricted_syntax, 'Y', 'RESTRICTED_SYNTAX,')
               ||decode(b.inc_refreshable, 'Y', 'INC_REFRESHABLE,')
               ||decode(b.known_stale, 'Y', 'KNOWN_STALE,')) "REFRESH|ATTRS",
           a.detail_owner||'.'||a.detail_relation||' ['||a.detail_type||']' "SOURCE|OBJECT",
           (SELECT listagg(owner||'.'||dimension_name, ','||chr(10)) WITHIN GROUP(ORDER BY owner, dimension_name)
            FROM   (SELECT /*+merge*/ DISTINCT owner, dimension_name, detailobj_owner, detailobj_name FROM all_dim_levels) b
            WHERE  a.detail_owner = b.detailobj_owner
            AND    a.detail_relation = b.detailobj_name) "REFERRED|DIMENSIONS",
           (SELECT listagg(column_name, ','||chr(10)) WITHIN GROUP(ORDER BY column_name)
            FROM   ]]..col_table..[[ b
            WHERE  b.owner = a.detail_owner
            AND    b.name = a.detail_relation) "MLOG$|COLUMNS"
    FROM   (SELECT a.*, '"'||detail_owner||'"."'||detail_relation||'".' obj FROM all_summary_detail_tables a) a
    JOIN   all_summaries b
    USING  (owner, summary_name)
    WHERE  owner = :owner
    AND    summary_name = :object_name]])

env.table.insert(result, #result, [[
    SELECT /*topic="Mview Refresh Schedules"*/
           refgroup               "REFRESH|GROUP",
           rowner                 "REFRESH|OWNER",
           rname                  "REFRESH|NAME",
           type                   "REFRESH|TYPE",
           job                    "JOB|ID",
           --job_name             "JOB|NAME",
           parallelism            "JOB|DoP",
           broken                 "JOB|BROKEN",
           implicit_destroy       "IMPLICIT|DESTROY",
           push_deferred_rpc      "DEFER|RPC",
           refresh_after_errors   "REFRESH|ON_ERR",
           next_date              "NEXT|DATE",
           interval               "SCHEDULE|INTERVAL",
           purge_option           "PURGE|OPTION",
           heap_size              "HEAP|SIZE",
           rollback_seg           "ROLLBACK|SEGMENT"
    FROM   all_refresh_children
    WHERE  owner = :owner
    AND    name = :object_name
    ORDER  BY 1]])

env.table.insert(result, #result,
    [[SELECT /*topic="Mview Logs"*/*
      FROM   (SELECT DISTINCT mview_id snapshot_id
              FROM   all_registered_mviews a
              WHERE  owner = :owner
              AND    name = :object_name)
      LEFT   JOIN all_snapshot_logs
      USING  (snapshot_id)]])
return result
