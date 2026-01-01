env.var.define_column('QUERY,MVIEW_NAME','NOPRINT')
local result=obj.redirect('table')
result[#result]=result[#result]:gsub('TABLE','MVIEW')
env.table.insert(result,1,[[
    SELECT QUERY TEXT FROM ALL_MVIEWS
    WHERE OWNER=:owner AND MVIEW_NAME=:object_name     
]])

if db:check_access("dba_mview_log_filter_cols",true) then
    env.table.insert(result,#result,[[
        SELECT /*INTERNAL_DBCLI_CMD topic="Detail Relations"*/ /*+opt_param('_optimizer_unnest_scalar_sq' 'false')*/
              a.*,
             (SELECT listagg(column_name,','||CHR(10)) WITHIN GROUP(ORDER BY column_name)
              FROM   dba_mview_log_filter_cols b
              WHERE b.owner=a.detailobj_owner AND b.name=a.detailobj_name) logged_columns
        FROM  ALL_MVIEW_DETAIL_RELATIONS a
        WHERE owner=:owner AND mview_name=:object_name]])    
else
    env.table.insert(result,#result,
        [[SELECT /*INTERNAL_DBCLI_CMD topic="Detail Relations"*/* FROM ALL_MVIEW_DETAIL_RELATIONS WHERE OWNER=:owner AND MVIEW_NAME=:object_name]])
end
env.table.insert(result,#result,
    [[SELECT /*INTERNAL_DBCLI_CMD topic="Mview Logs"*/* FROM (SELECT snapid snapshot_id FROM ALL_SNAPSHOTS A WHERE OWNER=:owner AND NAME=:object_name) LEFT JOIN ALL_SNAPSHOT_LOGS USING(snapshot_id)]])
return result