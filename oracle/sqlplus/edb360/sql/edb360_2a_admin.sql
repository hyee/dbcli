@@&&edb360_0g.tkprof.sql
DEF section_id = '2a';
DEF section_name = 'Database Administration';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Latches';
DEF main_table = 'GV$LATCH';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
select v.*
from 
  (select 
      name, inst_id,
      gets,
      misses,
      round(misses*100/(gets+1), 3) misses_gets_pct,
      spin_gets,
      sleep1,
      sleep2,
      sleep3,
      wait_time,
      round(wait_time/1000000) wait_time_seconds,
   rank () over
     (order by wait_time desc) as misses_rank
   from
      gv$latch
   where gets + misses + sleep1 + wait_time > 0
   order by
      wait_time desc
  ) v
where
   misses_rank <= 25
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Invalid Objects';
DEF main_table = 'DBA_OBJECTS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_objects
 WHERE status = ''INVALID''
 ORDER BY
       owner,
       object_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Disabled Constraints';
DEF main_table = 'DBA_CONSTRAINTS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_constraints
 WHERE status = ''DISABLED''
   AND NOT (owner = ''SYSTEM'' AND constraint_name LIKE ''LOGMNR%'')
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       constraint_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Not Validated Constraints';
DEF main_table = 'DBA_CONSTRAINTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_constraints
 WHERE validated = ''NOT VALIDATED''
   AND NOT (owner = ''SYSTEM'' AND constraint_name LIKE ''LOGMNR%'')
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       constraint_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Non-indexed FK Constraints';
DEF main_table = 'DBA_CONSTRAINTS';
COL constraint_columns FOR A200;
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
WITH 
ref_int_constraints AS (
SELECT /*+ &&sq_fact_hints. */
       col.owner,
       col.constraint_name,
       col.table_name,
       con.status,
       con.r_owner,
       con.r_constraint_name,
       MAX(CASE col.position WHEN 01 THEN      col.column_name END)||
       MAX(CASE col.position WHEN 02 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 03 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 04 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 05 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 06 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 07 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 08 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 09 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 10 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 11 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 12 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 13 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 14 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 15 THEN '':''||col.column_name END)||
       MAX(CASE col.position WHEN 16 THEN '':''||col.column_name END)
       constraint_columns
  FROM dba_constraints  con,
       dba_cons_columns col
 WHERE con.constraint_type = ''R''
   --AND con.status = ''ENABLED''
   AND con.owner NOT IN &&exclusion_list.
   AND con.owner NOT IN &&exclusion_list2.
   AND col.owner = con.owner
   AND col.constraint_name = con.constraint_name
   AND col.table_name = con.table_name
 GROUP BY
       col.owner,
       col.constraint_name,
       col.table_name,
       con.status,
       con.r_owner,
       con.r_constraint_name
),
indexed_columns AS (
SELECT /*+ &&sq_fact_hints. */
       col.index_owner,
       col.index_name,
       col.table_owner,
       col.table_name,
       MAX(CASE col.column_position WHEN 01 THEN      col.column_name END)||
       MAX(CASE col.column_position WHEN 02 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 03 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 04 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 05 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 06 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 07 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 08 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 09 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 10 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 11 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 12 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 13 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 14 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 15 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 16 THEN '':''||col.column_name END)
       indexed_columns
  FROM dba_ind_columns col
 WHERE col.table_owner NOT IN &&exclusion_list.
   AND col.table_owner NOT IN &&exclusion_list2.
 GROUP BY
       col.index_owner,
       col.index_name,
       col.table_owner,
       col.table_name
)
SELECT /*+ &&top_level_hints. */
       rc.status,
       rc.owner,
       rc.table_name,
       rc.constraint_name,
       rc.constraint_columns,
       rc.r_owner,
       rc.r_constraint_name
  FROM ref_int_constraints rc,
       indexed_columns     ic
 WHERE ic.table_owner(+) = rc.owner
   AND ic.table_name(+) = rc.table_name
   AND ic.indexed_columns(+) LIKE rc.constraint_columns||''%''
   AND ic.table_name IS NULL
 ORDER BY
       rc.status DESC,
       rc.owner,
       rc.table_name,
       rc.constraint_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Unusable Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_indexes
 WHERE status = ''UNUSABLE''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Invisible Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_indexes
 WHERE visibility = ''INVISIBLE''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       index_name
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'Function-based Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_indexes
 WHERE index_type LIKE ''FUNCTION-BASED%''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Bitmap Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_indexes
 WHERE index_type LIKE ''%BITMAP''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Reversed Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_indexes
 WHERE index_type LIKE ''%REV''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Fat Indexes';
DEF main_table = 'DBA_IND_COLUMNS';
BEGIN
  :sql_text := '
WITH 
indexes_list AS (
SELECT /*+ &&sq_fact_hints. */
       index_owner owner, /*index_name,*/ COUNT(*) columns
  FROM dba_ind_columns
 WHERE index_owner NOT IN &&exclusion_list.
   AND index_owner NOT IN &&exclusion_list2.
 GROUP BY
       index_owner, index_name
)
SELECT /*+ &&top_level_hints. */
       owner,
       SUM(CASE columns WHEN  1 THEN 1 ELSE 0 END) "1 Col",
       SUM(CASE columns WHEN  2 THEN 1 ELSE 0 END) "2 Cols",     
       SUM(CASE columns WHEN  3 THEN 1 ELSE 0 END) "3 Cols",     
       SUM(CASE columns WHEN  4 THEN 1 ELSE 0 END) "4 Cols",     
       SUM(CASE columns WHEN  5 THEN 1 ELSE 0 END) "5 Cols",     
       SUM(CASE columns WHEN  6 THEN 1 ELSE 0 END) "6 Cols",
       SUM(CASE columns WHEN  7 THEN 1 ELSE 0 END) "7 Cols",
       SUM(CASE columns WHEN  8 THEN 1 ELSE 0 END) "8 Cols",
       SUM(CASE columns WHEN  9 THEN 1 ELSE 0 END) "9 Cols",
       SUM(CASE columns WHEN 10 THEN 1 ELSE 0 END) "10 Cols",
       SUM(CASE columns WHEN 11 THEN 1 ELSE 0 END) "11 Cols",
       SUM(CASE columns WHEN 12 THEN 1 ELSE 0 END) "12 Cols",     
       SUM(CASE columns WHEN 13 THEN 1 ELSE 0 END) "13 Cols",     
       SUM(CASE columns WHEN 14 THEN 1 ELSE 0 END) "14 Cols",     
       SUM(CASE columns WHEN 15 THEN 1 ELSE 0 END) "15 Cols",     
       SUM(CASE columns WHEN 16 THEN 1 ELSE 0 END) "16 Cols",
       SUM(CASE columns WHEN 17 THEN 1 ELSE 0 END) "17 Cols",
       SUM(CASE columns WHEN 18 THEN 1 ELSE 0 END) "18 Cols",
       SUM(CASE columns WHEN 19 THEN 1 ELSE 0 END) "19 Cols",
       SUM(CASE columns WHEN 20 THEN 1 ELSE 0 END) "20 Cols",
       SUM(CASE columns WHEN 21 THEN 1 ELSE 0 END) "21 Cols",
       SUM(CASE columns WHEN 22 THEN 1 ELSE 0 END) "22 Cols",     
       SUM(CASE columns WHEN 23 THEN 1 ELSE 0 END) "23 Cols",     
       SUM(CASE columns WHEN 24 THEN 1 ELSE 0 END) "24 Cols",     
       SUM(CASE columns WHEN 25 THEN 1 ELSE 0 END) "25 Cols",     
       SUM(CASE columns WHEN 26 THEN 1 ELSE 0 END) "26 Cols",
       SUM(CASE columns WHEN 27 THEN 1 ELSE 0 END) "27 Cols",
       SUM(CASE columns WHEN 28 THEN 1 ELSE 0 END) "28 Cols",
       SUM(CASE columns WHEN 29 THEN 1 ELSE 0 END) "29 Cols",
       SUM(CASE columns WHEN 30 THEN 1 ELSE 0 END) "30 Cols",
       SUM(CASE columns WHEN 31 THEN 1 ELSE 0 END) "31 Cols",
       SUM(CASE columns WHEN 32 THEN 1 ELSE 0 END) "32 Cols",     
       SUM(CASE columns WHEN 33 THEN 1 ELSE 0 END) "33 Cols",     
       SUM(CASE columns WHEN 34 THEN 1 ELSE 0 END) "34 Cols",     
       SUM(CASE columns WHEN 35 THEN 1 ELSE 0 END) "35 Cols",     
       SUM(CASE columns WHEN 36 THEN 1 ELSE 0 END) "36 Cols",
       SUM(CASE columns WHEN 37 THEN 1 ELSE 0 END) "37 Cols",
       SUM(CASE columns WHEN 38 THEN 1 ELSE 0 END) "38 Cols",
       SUM(CASE columns WHEN 39 THEN 1 ELSE 0 END) "39 Cols",
       SUM(CASE columns WHEN 40 THEN 1 ELSE 0 END) "40 Cols",
       SUM(CASE WHEN columns > 40 THEN 1 ELSE 0 END) "Over 40 Cols"
  FROM indexes_list
 GROUP BY
       owner
 ORDER BY
       owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Hidden Columns';
DEF main_table = 'DBA_TAB_COLS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tab_cols
 WHERE hidden_column = ''YES''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       table_name,
       column_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Virtual Columns';
DEF main_table = 'DBA_TAB_COLS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tab_cols
 WHERE virtual_column = ''YES''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       table_name,
       column_name
';
END;
/
@@edb360_9a_pre_one.sql
       
DEF title = 'Indexes not recently used';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
WITH
objects AS (
SELECT /*+ &&sq_fact_hints. */
       object_id,
       owner,
       object_name
  FROM dba_objects
 WHERE object_type LIKE ''INDEX%''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
),
ash_mem AS (
SELECT /*+ &&sq_fact_hints. */
       DISTINCT current_obj# 
  FROM gv$active_session_history
 WHERE sql_plan_operation = ''INDEX''
   AND current_obj# > 0
),
ash_awr AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       DISTINCT current_obj# 
  FROM dba_hist_active_sess_history
 WHERE sql_plan_operation = ''INDEX''
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND current_obj# > 0
),
sql_mem AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       DISTINCT object_owner, object_name
  FROM gv$sql_plan 
WHERE operation = ''INDEX''
),
sql_awr AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       DISTINCT object_owner, object_name
  FROM dba_hist_sql_plan
 WHERE operation = ''INDEX'' AND dbid = &&edb360_dbid.
)
SELECT /*+ &&top_level_hints. */
       i.table_owner,
       i.table_name,
       i.index_name
  FROM dba_indexes i
 WHERE (index_type LIKE ''NORMAL%'' OR index_type = ''BITMAP''  OR index_type LIKE ''FUNCTION%'')
   AND i.table_owner NOT IN &&exclusion_list.
   AND i.table_owner NOT IN &&exclusion_list2.
   AND (i.owner, i.index_name) NOT IN ( SELECT o.owner, o.object_name FROM ash_mem a, objects o WHERE o.object_id = a.current_obj# )
   AND (i.owner, i.index_name) NOT IN ( SELECT o.owner, o.object_name FROM ash_awr a, objects o WHERE o.object_id = a.current_obj# )
   AND (i.owner, i.index_name) NOT IN ( SELECT object_owner, object_name FROM sql_mem)
   AND (i.owner, i.index_name) NOT IN ( SELECT object_owner, object_name FROM sql_awr)
 ORDER BY
       i.table_owner,
       i.table_name,
       i.index_name
';
END;
/
@@&&skip_diagnostics.&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'Redundant Indexes';
DEF main_table = 'DBA_INDEXES';
COL redundant_index FOR A200;
COL superset_index FOR A200;
BEGIN
  :sql_text := '
WITH
indexed_columns AS (
SELECT /*+ &&sq_fact_hints. */
       col.index_owner,
       col.index_name,
       col.table_owner,
       col.table_name,
       idx.index_type,
       idx.uniqueness,
       MAX(CASE col.column_position WHEN 01 THEN      col.column_name END)||
       MAX(CASE col.column_position WHEN 02 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 03 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 04 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 05 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 06 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 07 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 08 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 09 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 10 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 11 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 12 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 13 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 14 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 15 THEN '':''||col.column_name END)||
       MAX(CASE col.column_position WHEN 16 THEN '':''||col.column_name END)
       indexed_columns
  FROM dba_ind_columns col,
       dba_indexes idx
 WHERE col.table_owner NOT IN &&exclusion_list.
   AND col.table_owner NOT IN &&exclusion_list2.
   AND idx.owner = col.index_owner
   AND idx.index_name = col.index_name
 GROUP BY
       col.index_owner,
       col.index_name,
       col.table_owner,
       col.table_name,
       idx.index_type,
       idx.uniqueness
)
SELECT /*+ &&top_level_hints. */
       r.table_owner,
       r.table_name,
       r.index_type,
       r.index_name||'' (''||r.indexed_columns||'')'' redundant_index,
       i.index_name||'' (''||i.indexed_columns||'')'' superset_index
  FROM indexed_columns r,
       indexed_columns i
 WHERE i.table_owner = r.table_owner
   AND i.table_name = r.table_name
   AND i.index_type = r.index_type
   AND i.index_name != r.index_name
   AND i.indexed_columns LIKE r.indexed_columns||'':%''
   AND r.uniqueness = ''NONUNIQUE''
 ORDER BY
       r.table_owner,
       r.table_name,
       r.index_name,
       i.index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with more than 5 Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       COUNT(*) indexes,
       table_owner,
       table_name,
       SUM(CASE WHEN index_type LIKE ''NORMAL%'' THEN 1 ELSE 0 END) type_normal,
       SUM(CASE WHEN index_type LIKE ''BITMAP%'' THEN 1 ELSE 0 END) type_bitmap,
       SUM(CASE WHEN index_type LIKE ''FUNCTION-BASED%'' THEN 1 ELSE 0 END) type_fbi,
       SUM(CASE WHEN index_type LIKE ''CLUSTER%'' THEN 1 ELSE 0 END) type_cluster,
       SUM(CASE WHEN index_type LIKE ''IOT%'' THEN 1 ELSE 0 END) type_iot,
       SUM(CASE WHEN index_type LIKE ''DOMAIN%'' THEN 1 ELSE 0 END) type_domain,
       SUM(CASE WHEN index_type LIKE ''LOB%'' THEN 1 ELSE 0 END) type_lob,
       SUM(CASE WHEN partitioned LIKE ''YES%'' THEN 1 ELSE 0 END) partitioned,
       SUM(CASE WHEN temporary LIKE ''Y%'' THEN 1 ELSE 0 END) temporary,
       SUM(CASE WHEN uniqueness LIKE ''UNIQUE%'' THEN 1 ELSE 0 END) is_unique,
       SUM(CASE WHEN uniqueness LIKE ''NONUNIQUE%'' THEN 1 ELSE 0 END) non_unique,
       SUM(CASE WHEN status LIKE ''VALID%'' THEN 1 ELSE 0 END) valid,
       SUM(CASE WHEN status LIKE ''N/A%'' THEN 1 ELSE 0 END) status_na,
       &&skip_10g.SUM(CASE WHEN visibility LIKE ''VISIBLE%'' THEN 1 ELSE 0 END) visible,
       &&skip_10g.SUM(CASE WHEN visibility LIKE ''INVISIBLE%'' THEN 1 ELSE 0 END) invisible,
       SUM(CASE WHEN status LIKE ''UNUSABLE%'' THEN 1 ELSE 0 END) unusable
  FROM dba_indexes
 WHERE table_owner NOT IN &&exclusion_list.
   AND table_owner NOT IN &&exclusion_list2.
 GROUP BY 
       table_owner,
       table_name
HAVING COUNT(*) > 5 
 ORDER BY
       1 DESC
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables on KEEP Buffer Pool';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       table_name
  FROM dba_tables
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND buffer_pool = ''KEEP''
 ORDER BY
       owner,
       table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables to be CACHED in Buffer Cache';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       owner,
       table_name
  FROM dba_tables
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND TRIM(cache) = ''Y''
 ORDER BY
       owner,
       table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables on KEEP Flash Cache';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       table_name
  FROM dba_tables
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND flash_cache = ''KEEP''
 ORDER BY
       owner,
       table_name
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Tables on KEEP Cell Flash Cache';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       table_name
  FROM dba_tables
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND cell_flash_cache = ''KEEP''
 ORDER BY
       owner,
       table_name
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Segments with non-default Buffer Pool';
DEF main_table = 'DBA_SEGMENTS';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       buffer_pool, owner, segment_name, segment_type, blocks
  FROM dba_segments
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND TRIM(buffer_pool) != ''DEFAULT''
 ORDER BY
       buffer_pool,
       owner,
       segment_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Segments with non-default Flash Cache';
DEF main_table = 'DBA_SEGMENTS';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       flash_cache, owner, segment_name, segment_type, blocks
  FROM dba_segments
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND TRIM(flash_cache) != ''DEFAULT''
 ORDER BY
       flash_cache,
       owner,
       segment_name
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Segments with non-default Cell Flash Cache';
DEF main_table = 'DBA_SEGMENTS';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       cell_flash_cache, owner, segment_name, segment_type, blocks
  FROM dba_segments
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND TRIM(cell_flash_cache) != ''DEFAULT''
 ORDER BY
       cell_flash_cache,
       owner,
       segment_name
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Degree of Parallelism DOP on Tables';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       SUM(CASE WHEN TRIM(degree) = ''DEFAULT'' THEN 1 ELSE 0 END) "DEFAULT",
       SUM(CASE WHEN TRIM(degree) = ''0'' THEN 1 ELSE 0 END) "0",
       SUM(CASE WHEN TRIM(degree) = ''1'' THEN 1 ELSE 0 END) "1",
       SUM(CASE WHEN TRIM(degree) = ''2'' THEN 1 ELSE 0 END) "2",
       SUM(CASE WHEN TRIM(degree) IN (''3'', ''4'') THEN 1 ELSE 0 END) "3-4",
       SUM(CASE WHEN TRIM(degree) IN (''5'', ''6'', ''7'', ''8'') THEN 1 ELSE 0 END) "5-8",
       SUM(CASE WHEN TRIM(degree) IN (''9'', ''10'', ''11'', ''12'', ''13'', ''14'', ''15'', ''16'') THEN 1 ELSE 0 END) "9-16",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 2 AND TRIM(degree) BETWEEN ''17'' AND ''32'' THEN 1 ELSE 0 END) "17-32",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 2 AND TRIM(degree) BETWEEN ''33'' AND ''64'' THEN 1 ELSE 0 END) "33-64",
       SUM(CASE WHEN (LENGTH(TRIM(degree)) = 2 AND TRIM(degree) BETWEEN ''65'' AND ''99'') OR
                     (LENGTH(TRIM(degree)) = 3 AND TRIM(degree) BETWEEN ''100'' AND ''128'') THEN 1 ELSE 0 END) "65-128",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 3 AND TRIM(degree) BETWEEN ''129'' AND ''256'' THEN 1 ELSE 0 END) "129-256",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 3 AND TRIM(degree) BETWEEN ''257'' AND ''512'' THEN 1 ELSE 0 END) "257-512",
       SUM(CASE WHEN (LENGTH(TRIM(degree)) = 3 AND TRIM(degree) > ''512'') OR
                     (LENGTH(TRIM(degree)) > 3 AND TRIM(degree) != ''DEFAULT'') THEN 1 ELSE 0 END) "HIGHER"
  FROM dba_tables
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
HAVING COUNT(*) > SUM(CASE WHEN TRIM(degree) IN (''0'', ''1'') THEN 1 ELSE 0 END)
 GROUP BY
       owner
 ORDER BY
       owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with DOP Set';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       degree,
       owner,
       table_name
  FROM dba_tables
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND TRIM(degree) NOT IN (''0'', ''1'')
 ORDER BY
       LENGTH(TRIM(degree)) DESC,
       degree DESC,
       owner,
       table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Degree of Parallelism DOP on Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       SUM(CASE WHEN TRIM(degree) = ''DEFAULT'' THEN 1 ELSE 0 END) "DEFAULT",
       SUM(CASE WHEN TRIM(degree) = ''0'' THEN 1 ELSE 0 END) "0",
       SUM(CASE WHEN TRIM(degree) = ''1'' THEN 1 ELSE 0 END) "1",
       SUM(CASE WHEN TRIM(degree) = ''2'' THEN 1 ELSE 0 END) "2",
       SUM(CASE WHEN TRIM(degree) IN (''3'', ''4'') THEN 1 ELSE 0 END) "3-4",
       SUM(CASE WHEN TRIM(degree) IN (''5'', ''6'', ''7'', ''8'') THEN 1 ELSE 0 END) "5-8",
       SUM(CASE WHEN TRIM(degree) IN (''9'', ''10'', ''11'', ''12'', ''13'', ''14'', ''15'', ''16'') THEN 1 ELSE 0 END) "9-16",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 2 AND TRIM(degree) BETWEEN ''17'' AND ''32'' THEN 1 ELSE 0 END) "17-32",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 2 AND TRIM(degree) BETWEEN ''33'' AND ''64'' THEN 1 ELSE 0 END) "33-64",
       SUM(CASE WHEN (LENGTH(TRIM(degree)) = 2 AND TRIM(degree) BETWEEN ''65'' AND ''99'') OR
                     (LENGTH(TRIM(degree)) = 3 AND TRIM(degree) BETWEEN ''100'' AND ''128'') THEN 1 ELSE 0 END) "65-128",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 3 AND TRIM(degree) BETWEEN ''129'' AND ''256'' THEN 1 ELSE 0 END) "129-256",
       SUM(CASE WHEN LENGTH(TRIM(degree)) = 3 AND TRIM(degree) BETWEEN ''257'' AND ''512'' THEN 1 ELSE 0 END) "257-512",
       SUM(CASE WHEN (LENGTH(TRIM(degree)) = 3 AND TRIM(degree) > ''512'') OR
                     (LENGTH(TRIM(degree)) > 3 AND TRIM(degree) != ''DEFAULT'') THEN 1 ELSE 0 END) "HIGHER"
  FROM dba_indexes
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 GROUP BY
       owner
HAVING COUNT(*) > SUM(CASE WHEN TRIM(degree) IN (''0'', ''1'') THEN 1 ELSE 0 END)
 ORDER BY
       owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Indexes with DOP Set';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       degree,
       owner,
       index_name
  FROM dba_indexes
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
   AND TRIM(degree) NOT IN (''0'', ''1'')
 ORDER BY
       LENGTH(TRIM(degree)) DESC,
       degree DESC,
       owner,
       index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Unused Columns';
DEF main_table = 'DBA_UNUSED_COL_TABS';
BEGIN
  :sql_text := '
-- requested by Mike Moehlman
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_unused_col_tabs
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Jobs';
DEF main_table = 'DBA_JOBS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_jobs
 ORDER BY
       job
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Jobs Running';
DEF main_table = 'DBA_JOBS_RUNNING';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_jobs_running
 ORDER BY
       job
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Scheduler Jobs';
DEF main_table = 'DBA_SCHEDULER_JOBS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_scheduler_jobs
 ORDER BY
       owner,
       job_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Scheduler Job Log for past 7 days';
DEF main_table = 'DBA_SCHEDULER_JOB_LOG';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_scheduler_job_log
 WHERE log_date > SYSDATE - 7
 ORDER BY
       log_id DESC,
       log_date DESC
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Scheduler Windows';
DEF main_table = 'DBA_SCHEDULER_WINDOWS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_scheduler_windows
 ORDER BY
       window_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Automated Maintenance Tasks';
DEF main_table = 'DBA_AUTOTASK_CLIENT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_autotask_client
 ORDER BY
       client_name
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'Current Blocking Activity';
DEF main_table = 'GV$SESSION';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
a.sid, a.sql_id sql_id_a, a.state, a.blocking_session, b.sql_id sql_id_b, b.prev_sql_id, 
a.blocking_session_status, a.seconds_in_wait
 from gv$session a, gv$session b
where a.blocking_session is not null
and a.blocking_session = b.sid
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Sequences';
DEF main_table = 'DBA_SEQUENCES';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       s.*,
       ROUND(100 * (s.last_number - s.min_value) / GREATEST((s.max_value - s.min_value), 1), 1) percent_used /* requested by Mike Moehlman */
from dba_sequences s
where
   s.sequence_owner not in &&exclusion_list.
and s.sequence_owner not in &&exclusion_list2.
and s.max_value > 0
order by s.sequence_owner, s.sequence_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Sequences prone to contention';
DEF main_table = 'DBA_SEQUENCES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       (s.last_number - CASE WHEN s.increment_by > 0 THEN s.min_value ELSE s.max_value END) / s.increment_by times_used, s.*
  FROM dba_sequences s
 WHERE s.sequence_owner not in &&exclusion_list.
   AND s.sequence_owner not in &&exclusion_list2.
   AND (s.cache_size < 1000 OR s.order_flag = ''Y'')
   AND s.min_value != s.last_number
   AND s.max_value != s.last_number
 ORDER BY 1 DESC
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with more than 254 Columns';
DEF main_table = 'DBA_TAB_COLUMNS';
DEF abstract = 'Tables with more than 254 Columns are subject to intra-block chained rows';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       COUNT(*) columns,
       owner,
       table_name
  FROM dba_tab_columns
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 GROUP BY
       owner, table_name
HAVING COUNT(*) > 254
 ORDER BY
       1 DESC, 
       owner,
       table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SQL using Literals or many children (by COUNT)';
DEF main_table = 'GV$SQL';
COL force_matching_signature FOR 99999999999999999999 HEA "SIGNATURE";
BEGIN
  :sql_text := '
WITH
lit AS (
SELECT /*+ &&sq_fact_hints. */
       force_matching_signature, COUNT(*) cnt, MIN(sql_id) min_sql_id, MAX(SQL_ID) max_sql_id
  FROM gv$sql
 WHERE force_matching_signature > 0
 GROUP BY
       force_matching_signature
HAVING COUNT(*) > 49
)
SELECT /*+ &&top_level_hints. */ 
       DISTINCT lit.cnt, s.force_matching_signature, s.parsing_schema_name owner,
       CASE WHEN o.object_name IS NOT NULL THEN o.object_name||''(''||s.program_line#||'')'' END source,
       s.sql_text
  FROM lit, gv$sql s, dba_objects o
 WHERE s.force_matching_signature = lit.force_matching_signature
   AND s.sql_id = lit.min_sql_id
   AND o.object_id(+) = s.program_id
 ORDER BY 
       1 DESC, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SQL using Literals or many children (by OWNER)';
DEF main_table = 'GV$SQL';
COL force_matching_signature FOR 99999999999999999999 HEA "SIGNATURE";
BEGIN
  :sql_text := '
WITH
lit AS (
SELECT /*+ &&sq_fact_hints. */
       force_matching_signature, COUNT(*) cnt, MIN(sql_id) min_sql_id, MAX(SQL_ID) max_sql_id
  FROM gv$sql
 WHERE force_matching_signature > 0
 GROUP BY
       force_matching_signature
HAVING COUNT(*) > 49
)
SELECT /*+ &&top_level_hints. */ 
       DISTINCT s.parsing_schema_name owner, lit.cnt, s.force_matching_signature,
       CASE WHEN o.object_name IS NOT NULL THEN o.object_name||''(''||s.program_line#||'')'' END source,
       s.sql_text
  FROM lit, gv$sql s, dba_objects o
 WHERE s.force_matching_signature = lit.force_matching_signature
   AND s.sql_id = lit.min_sql_id
   AND o.object_id(+) = s.program_id
 ORDER BY 
       1, 2 DESC, 3
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Open Cursors Count per Session';
DEF main_table = 'GV$OPEN_CURSOR';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       COUNT(*) open_cursors, inst_id, sid, user_name
  FROM gv$open_cursor
 GROUP BY
       inst_id, sid, user_name
 ORDER BY 
       1 DESC
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Open Cursors Count per SQL_ID';
DEF main_table = 'GV$OPEN_CURSOR';
DEF abstract = 'SQL statements with more than 50 Open Cursors';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       COUNT(*) open_cursors, COUNT(DISTINCT inst_id||''.''||sid) sessions, sql_id, hash_value, address, sql_text, cursor_type,
       MIN(user_name) min_user_name, MAX(user_name) max_user_name, MAX(last_sql_active_time) last_sql_active_time
  FROM gv$open_cursor
 GROUP BY
       sql_id, hash_value, address, sql_text, cursor_type
HAVING COUNT(*) >= 50 
 ORDER BY 
       1 DESC
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'High Cursor Count';
DEF main_table = 'GV$SQL';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       v1.sql_id,
       COUNT(*) child_cursors,
       MIN(inst_id) min_inst_id,
       MAX(inst_id) max_inst_id,
       MIN(child_number) min_child,
       MAX(child_number) max_child,
       (SELECT v2.sql_text FROM gv$sql v2 WHERE v2.sql_id = v1.sql_id AND ROWNUM = 1) sql_text
  FROM gv$sql v1
 GROUP BY
       v1.sql_id
HAVING COUNT(*) > 49
 ORDER BY
       child_cursors DESC,
       v1.sql_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Top SQL by Buffer Gets consolidating duplicates';
DEF main_table = 'GV$SQL';
COL total_buffer_gets NEW_V total_buffer_gets;
COL total_disk_reads NEW_V total_disk_reads;
SELECT SUM(buffer_gets) total_buffer_gets, SUM(disk_reads) total_disk_reads FROM gv$sql;
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
   FORCE_MATCHING_SIGNATURE,
   duplicate_count cnt,
   executions,
   buffer_gets,
   buffer_gets_per_exec,
   disk_reads,
   disk_reads_per_exec,
   rows_processed,
   rows_processed_per_exec,
   elapsed_seconds,
   elapsed_seconds_per_exec,
   pct_total_buffer_gets,
   pct_total_disk_reads,
   (SELECT v2.sql_text FROM gv$sql v2 WHERE v2.force_matching_signature = v1.force_matching_signature AND ROWNUM = 1) sql_text
from
  (select
      FORCE_MATCHING_SIGNATURE,
      count(*) duplicate_count,
      sum(executions) executions,
      sum(buffer_gets) buffer_gets,
      ROUND(sum(buffer_gets)/greatest(sum(executions),1)) buffer_gets_per_exec,
      sum(disk_reads) disk_reads,
      ROUND(sum(disk_reads)/greatest(sum(executions),1)) disk_reads_per_exec,
      sum(rows_processed) rows_processed,
      ROUND(sum(rows_processed)/greatest(sum(executions),1)) rows_processed_per_exec,
      round(sum(elapsed_time)/1000000, 3) elapsed_seconds,
      ROUND(sum(elapsed_time)/1000000/greatest(sum(executions),1), 3) elapsed_seconds_per_exec,
      ROUND(sum(buffer_gets)*100/&&total_buffer_gets., 1) pct_total_buffer_gets,
      ROUND(sum(disk_reads)*100/&&total_disk_reads., 1) pct_total_disk_reads,
      rank() over (order by sum(buffer_gets) desc nulls last) AS sql_rank
   from
      gv$sql
   where
      FORCE_MATCHING_SIGNATURE <> 0 and 
      FORCE_MATCHING_SIGNATURE <> EXACT_MATCHING_SIGNATURE 
   group by
      FORCE_MATCHING_SIGNATURE
   having
      count(*) >= 30
   order by
      buffer_gets desc
  ) v1
where
   sql_rank < 31
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Top SQL by number of duplicates';
DEF main_table = 'GV$SQL';
COL total_buffer_gets NEW_V total_buffer_gets;
COL total_disk_reads NEW_V total_disk_reads;
SELECT SUM(buffer_gets) total_buffer_gets, SUM(disk_reads) total_disk_reads FROM gv$sql;
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
   FORCE_MATCHING_SIGNATURE,
   duplicate_count,
   executions,
   buffer_gets,
   buffer_gets_per_exec,
   disk_reads,
   disk_reads_per_exec,
   rows_processed,
   rows_processed_per_exec,
   elapsed_seconds,
   elapsed_seconds_per_exec,
   pct_total_buffer_gets,
   pct_total_disk_reads,
   (SELECT v2.sql_text FROM gv$sql v2 WHERE v2.force_matching_signature = v1.force_matching_signature AND ROWNUM = 1) sql_text
from
  (select
      FORCE_MATCHING_SIGNATURE,
      count(*) duplicate_count,
      sum(executions) executions,
      sum(buffer_gets) buffer_gets,
      ROUND(sum(buffer_gets)/greatest(sum(executions),1)) buffer_gets_per_exec,
      sum(disk_reads) disk_reads,
      ROUND(sum(disk_reads)/greatest(sum(executions),1)) disk_reads_per_exec,
      sum(rows_processed) rows_processed,
      ROUND(sum(rows_processed)/greatest(sum(executions),1)) rows_processed_per_exec,
      round(sum(elapsed_time)/1000000, 3) elapsed_seconds,
      ROUND(sum(elapsed_time)/1000000/greatest(sum(executions),1), 3) elapsed_seconds_per_exec,
      ROUND(sum(buffer_gets)*100/&&total_buffer_gets., 1) pct_total_buffer_gets,
      ROUND(sum(disk_reads)*100/&&total_disk_reads., 1) pct_total_disk_reads,
      rank() over (order by count(*) desc nulls last) AS sql_rank
   from
      gv$sql
   where
      FORCE_MATCHING_SIGNATURE <> 0 and 
      FORCE_MATCHING_SIGNATURE <> EXACT_MATCHING_SIGNATURE 
   group by
      FORCE_MATCHING_SIGNATURE
   order by
      count(*) desc
  ) v1
where
   sql_rank < 31
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Active SQL (sql_id)';
DEF main_table = 'GV$SQL';
BEGIN
  :sql_text := '
WITH /* active_sql */ 
unique_sql AS (
SELECT /*+ &&sq_fact_hints. */
       DISTINCT sq.sql_id,
       sq.sql_text
  FROM gv$session se,
       gv$sql sq
 WHERE se.status = ''ACTIVE''
   AND sq.inst_id = se.inst_id
   AND sq.sql_id = se.sql_id
   AND sq.child_number = se.sql_child_number
   AND sq.sql_text NOT LIKE ''WITH /* active_sql */%''
)
SELECT sql_id, sql_text
  FROM unique_sql
 ORDER BY
       sql_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Active SQL (full text)';
DEF main_table = 'GV$SQL';
BEGIN
  :sql_text := '
SELECT /* active_sql */ 
       sq.inst_id, sq.sql_id, sq.child_number,
       sq.sql_fulltext
  FROM gv$session se,
       gv$sql sq
 WHERE se.status = ''ACTIVE''
   AND sq.inst_id = se.inst_id
   AND sq.sql_id = se.sql_id
   AND sq.child_number = se.sql_child_number
   AND sq.sql_text NOT LIKE ''SELECT /* active_sql */%''
 ORDER BY
       sq.inst_id, sq.sql_id, sq.child_number
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Active SQL (detail)';
DEF main_table = 'GV$SQL';
BEGIN
  :sql_text := '
SELECT /* active_sql */ 
       sq.*
  FROM gv$session se,
       gv$sql sq
 WHERE se.status = ''ACTIVE''
   AND sq.inst_id = se.inst_id
   AND sq.sql_id = se.sql_id
   AND sq.child_number = se.sql_child_number
   AND sq.sql_text NOT LIKE ''SELECT /* active_sql */%''
 ORDER BY
       sq.inst_id, sq.sql_id, sq.child_number
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Active Sessions (detail)';
DEF main_table = 'GV$SESSION';
BEGIN
  :sql_text := '
SELECT /* active_sessions */ 
       se.*
  FROM gv$session se,
       gv$sql sq
 WHERE se.status = ''ACTIVE''
   AND sq.inst_id = se.inst_id
   AND sq.sql_id = se.sql_id
   AND sq.child_number = se.sql_child_number
   AND sq.sql_text NOT LIKE ''SELECT /* active_sessions */%''
 ORDER BY
       se.inst_id, se.sid, se.serial#   
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Active Sessions (more detail)';
DEF main_table = 'GV$SESSION';
BEGIN
  :sql_text := '
-- provided by Frits Hoogland
select /*+ rule as.sql */ a.sid||'',''||a.serial#||'',@''||a.inst_id as sid_serial_inst, 
	d.spid as ospid, 
	substr(a.program,1,19) prog, 
	a.module, a.action, a.client_info,
	''SQL:''||b.sql_id as sql_id, child_number child, plan_hash_value, executions execs,
	(elapsed_time/decode(nvl(executions,0),0,1,executions))/1000000 avg_etime,
	decode(a.plsql_object_id,null,sql_text,(select distinct sqla.object_name||''.''||sqlb.procedure_name from dba_procedures sqla, dba_procedures sqlb where sqla.object_id=a.plsql_object_id and sqlb.object_id = a.plsql_object_id and a.plsql_subprogram_id = sqlb.subprogram_id)) sql_text, 
	(c.wait_time_micro/1000000) wait_s, 
	decode(a.plsql_object_id,null,decode(c.wait_time,0,decode(a.blocking_session,null,c.event,c.event||''> Blocked by (inst:sid): ''||a.final_blocking_instance||'':''||a.final_blocking_session),''ON CPU:SQL''),(select ''ON CPU:PLSQL:''||object_name from dba_objects where object_id=a.plsql_object_id)) as wait_or_cpu
from gv$session a, gv$sql b, gv$session_wait c, gv$process d
where a.status = ''ACTIVE''
and a.username is not null
and a.sql_id = b.sql_id
and a.inst_id = b.inst_id
and a.sid = c.sid
and a.inst_id = c.inst_id
and a.inst_id = d.inst_id
and a.paddr = d.addr
and a.sql_child_number = b.child_number
and sql_text not like ''select /*+ rule as.sql */%'' /* dont show this query */
order by sql_id, sql_child_number
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'Libraries calling DBMS_STATS';
DEF main_table = 'DBA_SOURCE';
BEGIN
  :sql_text := '
SELECT *
  FROM dba_source
 WHERE REPLACE(UPPER(text), '' '') LIKE ''%DBMS_STATS.%''
   AND UPPER(text) NOT LIKE ''%--%DBMS_STATS%''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner, name, type, line
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Libraries calling ANALYZE';
DEF main_table = 'DBA_SOURCE';
BEGIN
  :sql_text := '
SELECT *
  FROM dba_source
 WHERE (REPLACE(UPPER(text), '' '') LIKE ''%''''ANALYZETABLE%'' OR REPLACE(UPPER(text), '' '') LIKE ''%''''ANALYZEINDEX%'')
   AND UPPER(text) NOT LIKE ''%--%ANALYZE %''
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY owner, name, type, line
';
END;
/
-- taking long and of little use, 
-- enable only if you suspect of ANALYZE been executed by application
-- @@edb360_9a_pre_one.sql

DEF title = 'Workload Repository Control';
DEF main_table = 'DBA_HIST_WR_CONTROL';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_hist_wr_control
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'SYSAUX Occupants';
DEF main_table = 'V$SYSAUX_OCCUPANTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       v.*, ROUND(v.space_usage_kbytes / POWER(2, 20), 3) space_usage_gbs
  FROM v$sysaux_occupants v
 ORDER BY 1
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'ASH Retention ';
DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
BEGIN
  :sql_text := '
-- from http://jhdba.wordpress.com/tag/purge-wrh-tables/
SELECT /*+ &&top_level_hints. */ 
 sysdate - a.sample_time ash,
sysdate - s.begin_interval_time snap,
c.RETENTION
from sys.wrm$_wr_control c,
(
select db.dbid,
min(w.sample_time) sample_time
from sys.v_$database db,
sys.Wrh$_active_session_history w
where w.dbid = db.dbid group by db.dbid
) a,
(
select db.dbid,
min(r.begin_interval_time) begin_interval_time
from sys.v_$database db,
sys.wrm$_snapshot r
where r.dbid = db.dbid
group by db.dbid
) s
where a.dbid = s.dbid
and c.dbid = a.dbid
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'WRH$ Partitions ';
DEF main_table = 'DBA_TAB_PARTITIONS';
BEGIN
  :sql_text := '
-- from http://jhdba.wordpress.com/tag/purge-wrh-tables/
select table_name, count(*)
from dba_tab_partitions
where table_name like ''WRH$%''
and table_owner = ''SYS''
group by table_name
order by 1
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Distributed Transactions awaiting Recovery';
DEF main_table = 'DBA_2PC_PENDING';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_2pc_pending
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Connections for Pending Transactions';
DEF main_table = 'DBA_2PC_NEIGHBORS';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_2pc_neighbors
 ORDER BY
       1
';
END;
/
@@edb360_9a_pre_one.sql


DEF title = 'Segments with Next Extent at Risk';
DEF main_table = 'DBA_SEGMENTS';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
with 
max_free AS (
select /*+ &&sq_fact_hints. */
tablespace_name, max(bytes) bytes
from dba_free_space
group by tablespace_name )
select /*+ &&top_level_hints. */
s.owner, s.segment_name, s.tablespace_name, s.next_extent, max_free.bytes max_free_bytes 
from dba_segments s, max_free
where s.owner NOT IN &&exclusion_list.
and s.owner NOT IN &&exclusion_list2.
and s.next_extent > max_free.bytes 
and s.tablespace_name=max_free.tablespace_name
order by 1,2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Libraries Version';
DEF main_table = 'DBA_SOURCE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_source
 WHERE line < 4
   AND text LIKE ''%$Header%''
 ORDER BY
       1, 2, 3, 4
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Orphaned Synonyms';
DEF main_table = 'DBA_SYNONYMS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       s.owner, s.table_owner, COUNT(1)
  FROM sys.dba_synonyms s
 WHERE s.table_owner||''.''||s.table_name NOT IN
       (select o.owner||''.''||o.object_name
          from sys.dba_objects o
         where o.object_name = s.table_name
           and o.owner = s.table_owner)
   AND s.owner NOT IN (''SYS'',''SYSTEM'')
   AND s.table_owner NOT IN (''SYS'',''SYSTEM'')
   AND s.db_link IS NULL
and s.owner not in &&exclusion_list.
and s.owner not in &&exclusion_list2.
 GROUP BY s.owner, s.table_owner
 ORDER BY s.owner';
END;
/
@@edb360_9a_pre_one.sql

