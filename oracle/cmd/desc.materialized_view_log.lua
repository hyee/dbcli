env.var.define_column('QUERY,QUERY_LEN','NOPRINT')
local result = obj.redirect('table')
env.table.insert(result, 1, [[
    SELECT dbms_metadata.get_ddl('MATERIALIZED_VIEW_LOG', :object_name, :owner) ddl_statement
    FROM   dual]])

result[#result] = [[
    SELECT /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
    FROM   (SELECT * FROM all_mview_logs   WHERE log_owner = :owner AND log_table = :object_name) t,
           (SELECT * FROM all_objects  WHERE owner = :owner AND object_name = :object_name AND subobject_name IS NULL) o
    WHERE  t.log_table = o.object_name]]
env.table.insert(result, #result, [[
    SELECT /*topic="Depending Mviews"*/*
    FROM   (SELECT b.owner, b.name mview_name, a.master
            FROM   all_snapshot_logs a
            LEFT   JOIN all_registered_mviews b
            ON     (a.snapshot_id = b.mview_id)
            WHERE  log_owner = :owner
            AND    log_table = :object_name)
    LEFT   JOIN all_mviews
    USING  (owner, mview_name)]])
return result
