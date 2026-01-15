local res=db:get_value([[
    WITH gv AS
    (SELECT /*+materialized*/ parsing_schema_name, sql_fulltext sql_text
    FROM   GV$SQL
    WHERE  sql_id = :sql_id
    AND    rownum < 2),
    sqlmon AS
    (SELECT /*+materialized ordered_predicates*/username, to_clob(sql_text) sql_text
    FROM   gv$sql_monitor
    WHERE  (SELECT COUNT(1) FROM gv) = 0
    AND    sql_id = :sql_id
    AND    sql_text IS NOT NULL
    AND    is_full_sqltext = 'Y'),
    sqlset AS
    (SELECT /*+materialized ordered_predicates*/parsing_schema_name, sql_text
    FROM   dba_sqlset_statements
    WHERE  (SELECT COUNT(1) FROM gv) = 0
    AND    (SELECT COUNT(1) FROM sqlmon) = 0
    AND    sql_id = :sql_id
    AND    rownum < 2)
    SELECT /*+OPT_PARAM('_fix_control' '26552730:0') opt_param('optimizer_dynamic_sampling' 0)*/
        parsing_schema_name, sql_text
    FROM   dba_hist_sqltext a
    JOIN   dba_hist_sqlstat b
    USING  (dbid, sql_id)
    WHERE  (SELECT COUNT(1) FROM gv) = 0
    AND    (SELECT COUNT(1) FROM sqlmon) = 0
    AND    (SELECT COUNT(1) FROM sqlset) = 0
    AND    dbid = :dbid
    AND    sql_id = :sql_id
    AND    rownum < 2
    UNION ALL
    SELECT *
    FROM   gv
    UNION ALL
    SELECT * FROM sqlset]],obj);

env.checkerr(res,"Cannot find target SQL_ID: "..obj.sql_id)
local typ=db.get_command_type(res[2])
env.checkerr(typ=='SELECT' or typ=='DECLARE',"SQL "..obj.sql_id.." is not a query or a declare statement.")
obj[1],obj.owner,obj.query=res[1],res[1],res[2]
return obj.redirect('query')