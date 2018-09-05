/*[[Get SQL text. Usage: @@NAME <sql_id>
    --[[
        @VER: 11.2={} DEFAULT={--}
    --]]
]]*/
set colwrap 150 feed off 
COL ELA,ALL_ELA,CPU,IO,CC,CL,AP,PL_JAVA FORMAT USMHD2
COL CELLIO,READ,WRITE,CELLIO,OFLIN,OFLOUT FORMAT KMG
SET BYPASSEMPTYRS ON

SELECT *
FROM   (SELECT &VER top_level_sql_id top_sql,
               sql_plan_hash_value phv,
               &VER sql_plan_line_id plan_line,
               PLSQL_ENTRY_OBJECT_ID program#,
               NVL(event, 'ON CPU') event,
               COUNT(1) aas
        FROM   gv$active_session_history
        WHERE  sql_id = :V1
        GROUP  BY sql_plan_hash_value, PLSQL_ENTRY_OBJECT_ID, event
                  &VER ,sql_plan_line_id,top_level_sql_id
        ORDER  BY aas DESC)
WHERE  ROWNUM <= 10;



SELECT PLAN_HASH_VALUE PHV,
       program_id || NULLIF('#' || program_line#, '#0') program#,
       &ver decode(IS_BIND_SENSITIVE, 'Y', 'SENS ') || decode(IS_BIND_AWARE, 'Y', 'AWARE ') || decode(IS_SHAREABLE, 'Y', 'SHARE') ACS,
       TRIM('/' FROM SQL_PROFILE 
       &ver || '/' || SQL_PLAN_BASELINE
       ) OUTLINE,
       parsing_schema_name user#,
       SUM(EXEC) AS EXEC,
       SUM(PARSE_CALLS) parse,
       round(SUM(elapsed_time),3) all_ela,
       '|' "|",
       round(SUM(elapsed_time)/SUM(EXEC),3) ela,
       round(SUM(cpu_time)/SUM(EXEC),3) CPU,
       round(SUM(USER_IO_WAIT_TIME)/SUM(EXEC),3) io,
       round(SUM(CONCURRENCY_WAIT_TIME)/SUM(EXEC),3) cc,
       round(SUM(CLUSTER_WAIT_TIME)/SUM(EXEC),3) cl,
       round(SUM(APPLICATION_WAIT_TIME)/SUM(EXEC),3) ap,
       round(SUM(PLSQL_EXEC_TIME + JAVA_EXEC_TIME)/SUM(EXEC),3) pl_java,
       round(SUM(BUFFER_GETS)/SUM(EXEC),3) AS BUFF,
       &ver round(SUM(IO_INTERCONNECT_BYTES)/SUM(EXEC),3)  cellio,
       &ver round(SUM(PHYSICAL_WRITE_BYTES)/SUM(EXEC),3)  AS WRITE,
       &ver round(SUM(PHYSICAL_READ_BYTES)/SUM(EXEC),3)  AS READ,
       &ver round(SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES)/SUM(EXEC),3)  oflin,
       &ver round(SUM(IO_CELL_OFFLOAD_RETURNED_BYTES)/SUM(EXEC),3)  oflout,
       round(sum(ROWS_PROCESSED)/SUM(EXEC),3)  rows#
FROM   (SELECT greatest(EXECUTIONS + users_executing, 1) exec,a.* FROM gv$SQL a WHERE SQL_ID=:V1)
GROUP  BY SQL_ID,
          PLAN_HASH_VALUE,
          &ver IS_BIND_SENSITIVE,
          &ver IS_BIND_AWARE,
          &ver IS_SHAREABLE,
          program_id,
          program_line#,
          SQL_PROFILE,
          &ver SQL_PLAN_BASELINE,
          parsing_schema_name;
          
column sql_text new_value txt;
SELECT * FROM(
      select sql_text from dba_hist_sqltext where sql_id=:V1
      union all
      select sql_fulltext from gv$sqlarea where sql_id=:V1
) WHERE ROWNUM<2;
pro
save txt last_sql_&V1..txt
