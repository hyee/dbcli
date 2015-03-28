@@&&edb360_0g.tkprof.sql
DEF section_id = '1d';
DEF section_name = 'Memory';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'SGA';
DEF main_table = 'GV$SGA';
BEGIN
  :sql_text := '
SELECT /*+ RESULT_CACHE */
       inst_id,
       name,
       value,
       CASE 
       WHEN value > POWER(2,50) THEN ROUND(value/POWER(2,50),1)||'' P''
       WHEN value > POWER(2,40) THEN ROUND(value/POWER(2,40),1)||'' T''
       WHEN value > POWER(2,30) THEN ROUND(value/POWER(2,30),1)||'' G''
       WHEN value > POWER(2,20) THEN ROUND(value/POWER(2,20),1)||'' M''
       WHEN value > POWER(2,10) THEN ROUND(value/POWER(2,10),1)||'' K''
       ELSE value||'' B'' END approx
  FROM gv$sga
 ORDER BY
       name,
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SGA Info';
DEF main_table = 'GV$SGAINFO';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       inst_id,
       name,
       bytes,
       CASE 
       WHEN bytes > POWER(2,50) THEN ROUND(bytes/POWER(2,50),1)||'' P''
       WHEN bytes > POWER(2,40) THEN ROUND(bytes/POWER(2,40),1)||'' T''
       WHEN bytes > POWER(2,30) THEN ROUND(bytes/POWER(2,30),1)||'' G''
       WHEN bytes > POWER(2,20) THEN ROUND(bytes/POWER(2,20),1)||'' M''
       WHEN bytes > POWER(2,10) THEN ROUND(bytes/POWER(2,10),1)||'' K''
       ELSE bytes||'' B'' END approx,
       resizeable
  FROM gv$sgainfo
 ORDER BY
       name,
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SGA Stat';
DEF main_table = 'GV$SGASTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       inst_id,
       name,
       bytes,
       CASE 
       WHEN bytes > POWER(2,50) THEN ROUND(bytes/POWER(2,50),1)||'' P''
       WHEN bytes > POWER(2,40) THEN ROUND(bytes/POWER(2,40),1)||'' T''
       WHEN bytes > POWER(2,30) THEN ROUND(bytes/POWER(2,30),1)||'' G''
       WHEN bytes > POWER(2,20) THEN ROUND(bytes/POWER(2,20),1)||'' M''
       WHEN bytes > POWER(2,10) THEN ROUND(bytes/POWER(2,10),1)||'' K''
       ELSE bytes||'' B'' END approx
  FROM gv$sgastat
 ORDER BY
       pool NULLS FIRST,
       name,
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'PGA Stat';
DEF main_table = 'GV$PGASTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       inst_id,
       name,
       value,
       unit,
       CASE unit WHEN ''bytes'' THEN 
       CASE
       WHEN value > POWER(2,50) THEN ROUND(value/POWER(2,50),1)||'' P''
       WHEN value > POWER(2,40) THEN ROUND(value/POWER(2,40),1)||'' T''
       WHEN value > POWER(2,30) THEN ROUND(value/POWER(2,30),1)||'' G''
       WHEN value > POWER(2,20) THEN ROUND(value/POWER(2,20),1)||'' M''
       WHEN value > POWER(2,10) THEN ROUND(value/POWER(2,10),1)||'' K''
       ELSE value||'' B'' END 
       END approx
  FROM gv$pgastat
 ORDER BY
       name,
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql