/*[[Get SQL text. Usage: sql <sql_id>]]*/
set linesize 32767 colwrap 300
SELECT * FROM(
  select sql_text from dba_hist_sqltext where sql_id=:V1
  union all
  select sql_fulltext from gv$sqlarea where sql_id=:V1
) WHERE ROWNUM<2
