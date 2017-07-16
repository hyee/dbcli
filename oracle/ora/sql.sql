/*[[Get SQL text. Usage: @@NAME <sql_id>]]*/
set colwrap 150 feed off 
column sql_text new_value txt;
SELECT * FROM(
      select sql_text from dba_hist_sqltext where sql_id=:V1
      union all
      select sql_fulltext from gv$sqlarea where sql_id=:V1
) WHERE ROWNUM<2;
pro
save txt last_sql.txt
