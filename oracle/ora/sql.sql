/*[[
    Get SQL text and online stats. Usage: @@NAME <sql_id>

    Sample Output:
    ==============
    ORCL> ora sql g6px76dmjv1jy                                                                                                                            
       TOP_SQL       PHV     PLAN_LINE PROGRAM# EVENT  AAS                                                                                             
    ------------- ---------- --------- -------- ------ ---                                                                                             
    g6px76dmjv1jy 3702721588         2          ON CPU  49                                                                                             
    g6px76dmjv1jy 3702721588         2     7294 ON CPU  44                                                                                             
    g6px76dmjv1jy 3702721588         2     7292 ON CPU  26                                                                                             
    b6usrg82hwsa3 3702721588         2    12703 ON CPU   2                                                                                                                                                                                                                                               
                                                                                                                                                       
       PHV     PROGRAM#    ACS    OUTLINE USER# EXEC PARSE ALL_ELA|AVG_ELA  CPU  IO CC CL AP PL_JAVA  BUFF CELLIO WRITE READ OFLIN OFLOUT ROWS# FETCHES
    ---------- -------- --------- ------- ----- ---- ----- -------+------- ----- -- -- -- -- ------- ----- ------ ----- ---- ----- ------ ----- -------
    3702721588 0        SHAREABLE         SYS     66    66   2.21m|  2.01s 1.96s  0  0  0  0       0 365     0  B  0  B 0  B  0  B   0  B     1       1
                                                                  |                                                                                    
                                                                                                                                                                                                                                                                                          
    Result written to D:\dbcli\cache\orcl\clob_1.txt                                                                                                   
    SQL_TEXT                                                                                                                                           
    ---------------------------------------------------------------------------------------------------------------------------------------------------
    select count(*) from wri$_optstat_opr o, wri$_optstat_opr_tasks t where o.id = t.op_id(+) and o.operation = 'gather_database_stats (auto)' and (not
     '//error'),   '^<error>ORA-200[0-9][0-9]') or  not regexp_like(   extract(xmltype('<notes>' || t.notes || '</notes>'), '//error'),   '^<error>ORA-

    --[[
        @VER12: 12.1={} default={--}
        @VER: 11.2={} DEFAULT={--}
        @check_access_hist: dba_hist_sqltext={} default={--}
        @ARGS: 1
    --]]
]]*/
set colwrap 150 feed off 
COL AVG_ELA,ALL_ELA,CPU,IO,CC,CL,AP,PL_JAVA FORMAT USMHD2
COL CELLIO,READ,WRITE,CELLIO,OFLIN,OFLOUT FORMAT KMG
COL buff for tmb
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
       &ver trim(chr(10) from ''||&ver12 decode(is_reoptimizable,'Y','REOPTIMIZABLE'||chr(10))||decode(is_resolved_adaptive_plan,'Y','RESOLVED_ADAPTIVE_PLAN'||chr(10))||
       &ver decode(IS_BIND_SENSITIVE, 'Y', 'IS_BIND_SENSITIVE'||chr(10)) || decode(IS_BIND_AWARE, 'Y', 'BIND_AWARE'||chr(10)) || decode(IS_SHAREABLE, 'Y', 'SHAREABLE'||chr(10)))
       &ver ACS,
       TRIM('/' FROM SQL_PROFILE 
       &ver || '/' || SQL_PLAN_BASELINE
       ) OUTLINE,
       parsing_schema_name user#,
       SUM(EXEC) AS EXEC,
       SUM(PARSE_CALLS) parse,
       round(SUM(elapsed_time),3) all_ela,
       '|' "|",
       round(SUM(elapsed_time)/SUM(EXEC),3) avg_ela,
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
       round(sum(ROWS_PROCESSED)/SUM(EXEC),3)  rows#,
       round(sum(fetches)/SUM(EXEC),3)  fetches
FROM   (SELECT greatest(EXECUTIONS + users_executing, 1) exec,a.* FROM gv$SQL a WHERE SQL_ID=:V1)
GROUP  BY SQL_ID,
          PLAN_HASH_VALUE,
          &ver12 is_reoptimizable,is_resolved_adaptive_plan,
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
      &check_access_hist select sql_text from dba_hist_sqltext where sql_id='&v1' union all
      select sql_fulltext sql_text from gv$sqlstats where sql_id='&v1'
) WHERE ROWNUM<2;
pro
save txt last_sql_&V1..txt
