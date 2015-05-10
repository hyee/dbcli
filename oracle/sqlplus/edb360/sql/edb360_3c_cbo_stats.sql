@@&&edb360_0g.tkprof.sql
DEF section_id = '3c';
DEF section_name = 'Cost-based Optimizer (CBO) Statistics';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'CBO System Statistics';
DEF main_table = 'SYS.AUX_STATS$';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM sys.aux_stats$
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'CBO System Statistics History';
DEF main_table = 'SYS.WRI$_OPTSTAT_AUX_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM sys.wri$_optstat_aux_history
 ORDER BY 1 DESC, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Stats History Availability';
DEF main_table = 'DBMS_STATS';
BEGIN
  :sql_text := '
SELECT DBMS_STATS.get_stats_history_availability availability,
       DBMS_STATS.get_stats_history_retention retention
  FROM dual
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables Summary';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       COUNT(*) tables_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(partitioned, ''YES'', 1, 0)) partitioned,
       SUM(DECODE(temporary, ''Y'', 1, 0)) temporary,
       SUM(DECODE(status, ''VALID'', 0, 1)) not_valid,
       SUM(DECODE(logging, ''YES'', 0, 1)) not_logging,
       SUM(DECODE(TRIM(cache), ''Y'', 1, 0)) cache,
       &&skip_10g.&&skip_11r1.SUM(DECODE(flash_cache, ''KEEP'', 1, 0)) keep_flash_cache,
       &&skip_10g.&&skip_11r1.SUM(DECODE(cell_flash_cache, ''KEEP'', 1, 0)) keep_cell_flash_cache,
       &&skip_10g.&&skip_11r1.SUM(DECODE(result_cache, ''FORCE'', 1, 0)) result_cache_force,
       SUM(DECODE(dependencies, ''ENABLED'', 1, 0)) dependencies,
       SUM(DECODE(compression, ''ENABLED'', 1, 0)) compression,
       &&skip_10g.SUM(DECODE(compress_for, ''BASIC'', 1, 0)) compress_for_basic,
       &&skip_10g.SUM(DECODE(compress_for, ''OLTP'', 1, 0)) compress_for_oltp,
       &&skip_10g.SUM(CASE WHEN compress_for IN 
       &&skip_10g.(''ARCHIVE HIGH'', ''ARCHIVE LOW'', ''QUERY HIGH'', ''QUERY LOW'') 
       &&skip_10g.THEN 1 ELSE 0 END) compress_for_hcc,
       SUM(DECODE(dropped, ''YES'', 1, 0)) dropped,
       &&skip_10g.&&skip_11r1.SUM(DECODE(read_only, ''YES'', 1, 0)) read_only,
       SUM(num_rows) sum_num_rows,
       MAX(num_rows) max_num_rows,
       SUM(blocks) sum_blocks,
       MAX(blocks) max_blocks,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_tables
 WHERE table_name NOT LIKE ''BIN$%'' -- bug 9930151 reported by brad peek
 GROUP BY
       owner
 ORDER BY
       owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tab Summary';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       object_type,
       COUNT(*) type_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(stattype_locked, NULL, 0, 1)) stats_locked,
       SUM(DECODE(stale_stats, ''YES'', 1, 0)) stale_stats,
       SUM(num_rows) sum_num_rows,
       MAX(num_rows) max_num_rows,
       SUM(blocks) sum_blocks,
       MAX(blocks) max_blocks,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_tab_statistics
 WHERE table_name NOT LIKE ''BIN$%'' -- bug 9930151 reported by brad peek
 GROUP BY
       owner, object_type
 ORDER BY
       owner, object_type
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Table Columns Summary';
DEF main_table = 'DBA_TAB_COLS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       COUNT(DISTINCT table_name) tables_count,
       COUNT(*) columns_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(hidden_column, ''YES'', 1, 0)) hidden_column,
       SUM(DECODE(virtual_column, ''YES'', 1, 0)) virtual_column,
       SUM(DECODE(histogram, ''NONE'', 0, 1)) histogram,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_tab_cols
 WHERE table_name NOT LIKE ''BIN$%'' -- bug 9930151 reported by brad peek
   AND owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 GROUP BY
       owner
 ORDER BY
       owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Indexes Summary';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       COUNT(DISTINCT table_name) tables_count,
       COUNT(*) indexes_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(partitioned, ''YES'', 1, 0)) partitioned,
       SUM(DECODE(temporary, ''Y'', 1, 0)) temporary,
       SUM(DECODE(status, ''UNUSABLE'', 1, 0)) unusable,
       &&skip_10g.SUM(DECODE(visibility, ''INVISIBLE'', 1, 0)) invisible,
       SUM(DECODE(logging, ''YES'', 0, 1)) not_logging,
       &&skip_10g.&&skip_11r1.SUM(DECODE(flash_cache, ''KEEP'', 1, 0)) keep_flash_cache,
       &&skip_10g.&&skip_11r1.SUM(DECODE(cell_flash_cache, ''KEEP'', 1, 0)) keep_cell_flash_cache,
       SUM(DECODE(compression, ''ENABLED'', 1, 0)) compression,
       SUM(DECODE(dropped, ''YES'', 1, 0)) dropped,
       SUM(leaf_blocks) sum_leaf_blocks,
       MAX(leaf_blocks) max_leaf_blocks,
       MAX(blevel) max_blevel,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_indexes
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 GROUP BY
       owner
 ORDER BY
       owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Ind Summary';
DEF main_table = 'DBA_IND_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       owner,
       object_type,
       COUNT(*) type_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(stattype_locked, NULL, 0, 1)) stats_locked,
       SUM(DECODE(stale_stats, ''YES'', 1, 0)) stale_stats,
       SUM(leaf_blocks) sum_leaf_blocks,
       MAX(leaf_blocks) max_leaf_blocks,
       MAX(blevel) max_blevel,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_ind_statistics
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 GROUP BY
       owner, object_type
 ORDER BY
       owner, object_type
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Table Partititions Summary';
DEF main_table = 'DBA_TAB_PARTITIONS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       table_owner,
       COUNT(DISTINCT table_name) tables_count,
       COUNT(*) partitions_count,
       SUM(DECODE(composite, ''YES'', 1, 0)) subpartitioned,
       SUM(subpartition_count) subpartition_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(logging, ''YES'', 0, 1)) not_logging,
       &&skip_10g.&&skip_11r1.SUM(DECODE(flash_cache, ''KEEP'', 1, 0)) keep_flash_cache,
       &&skip_10g.&&skip_11r1.SUM(DECODE(cell_flash_cache, ''KEEP'', 1, 0)) keep_cell_flash_cache,
       SUM(DECODE(compression, ''ENABLED'', 1, 0)) compression,
       &&skip_10g.SUM(DECODE(compress_for, ''BASIC'', 1, 0)) compress_for_basic,
       &&skip_10g.SUM(DECODE(compress_for, ''OLTP'', 1, 0)) compress_for_oltp,
       &&skip_10g.SUM(CASE WHEN compress_for IN 
       &&skip_10g.(''ARCHIVE HIGH'', ''ARCHIVE LOW'', ''QUERY HIGH'', ''QUERY LOW'') 
       &&skip_10g.THEN 1 ELSE 0 END) compress_for_hcc,
       SUM(num_rows) sum_num_rows,
       MAX(num_rows) max_num_rows,
       SUM(blocks) sum_blocks,
       MAX(blocks) max_blocks,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_tab_partitions
 WHERE table_owner NOT IN &&exclusion_list.
   AND table_owner NOT IN &&exclusion_list2.
 GROUP BY
       table_owner
 ORDER BY
       table_owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Index Partitions Summary';
DEF main_table = 'DBA_IND_PARTITIONS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       index_owner,
       COUNT(DISTINCT index_name) indexes_count,
       COUNT(*) partitions_count,
       SUM(DECODE(composite, ''YES'', 1, 0)) subpartitioned,
       SUM(subpartition_count) subpartition_count,
       SUM(DECODE(last_analyzed, NULL, 1, 0)) not_analyzed,
       SUM(DECODE(status, ''UNUSABLE'', 1, 0)) unusable,
       SUM(DECODE(logging, ''YES'', 0, 1)) not_logging,
       &&skip_10g.&&skip_11r1.SUM(DECODE(flash_cache, ''KEEP'', 1, 0)) keep_flash_cache,
       &&skip_10g.&&skip_11r1.SUM(DECODE(cell_flash_cache, ''KEEP'', 1, 0)) keep_cell_flash_cache,
       SUM(DECODE(compression, ''ENABLED'', 1, 0)) compression,
       SUM(leaf_blocks) sum_leaf_blocks,
       MAX(leaf_blocks) max_leaf_blocks,
       MAX(blevel) max_blevel,
       MIN(last_analyzed) min_last_analyzed,
       MAX(last_analyzed) max_last_analyzed,
       MEDIAN(last_analyzed) median_last_analyzed,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_75_percentile,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_90_percentile,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_95_percentile,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_analyzed) last_analyzed_99_percentile
  FROM dba_ind_partitions
 WHERE index_owner NOT IN &&exclusion_list.
   AND index_owner NOT IN &&exclusion_list2.
 GROUP BY
       index_owner
 ORDER BY
       index_owner
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with Missing Stats';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.owner, s.table_name, s.stale_stats, s.stattype_locked
  FROM dba_tab_statistics s,
       dba_tables t
 WHERE s.object_type = ''TABLE''
   AND s.owner NOT IN &&exclusion_list.
   AND s.owner NOT IN &&exclusion_list2.
   AND s.last_analyzed IS NULL
   AND s.table_name NOT LIKE ''BIN%''
   AND NOT (s.table_name LIKE ''%TEMP'' OR s.table_name LIKE ''%\_TEMP\_%'' ESCAPE ''\'')
   AND t.owner = s.owner
   AND t.table_name = s.table_name
   AND t.temporary = ''N''
 ORDER BY
       s.owner, s.table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with Stale Stats';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.owner, s.table_name, s.num_rows, s.last_analyzed, s.stattype_locked
  FROM dba_tab_statistics s,
       dba_tables t
 WHERE s.object_type = ''TABLE''
   AND s.owner NOT IN &&exclusion_list.
   AND s.owner NOT IN &&exclusion_list2.
   AND s.stale_stats = ''YES''
   AND s.table_name NOT LIKE ''BIN%''
   AND NOT (s.table_name LIKE ''%TEMP'' OR s.table_name LIKE ''%\_TEMP\_%'' ESCAPE ''\'')
   AND t.owner = s.owner
   AND t.table_name = s.table_name
   AND t.temporary = ''N''
 ORDER BY
       s.owner, s.table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with Outdated Stats';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.owner, s.table_name, s.num_rows, s.last_analyzed, s.stale_stats, s.stattype_locked
  FROM dba_tab_statistics s,
       dba_tables t
 WHERE s.object_type = ''TABLE''
   AND s.owner NOT IN &&exclusion_list.
   AND s.owner NOT IN &&exclusion_list2.
   AND s.last_analyzed < SYSDATE - 31
   AND s.table_name NOT LIKE ''BIN%''
   AND NOT (s.table_name LIKE ''%TEMP'' OR s.table_name LIKE ''%\_TEMP\_%'' ESCAPE ''\'')
   AND t.owner = s.owner
   AND t.table_name = s.table_name
   AND t.temporary = ''N''
 ORDER BY
       s.owner, s.table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with Locked Stats';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.owner, s.table_name, t.temporary, s.num_rows, s.last_analyzed, s.stale_stats, s.stattype_locked
  FROM dba_tab_statistics s,
       dba_tables t
 WHERE s.object_type = ''TABLE''
   AND s.owner NOT IN &&exclusion_list.
   AND s.owner NOT IN &&exclusion_list2.
   AND s.stattype_locked IS NOT NULL
   AND s.table_name NOT LIKE ''BIN%''
   AND t.owner = s.owner
   AND t.table_name = s.table_name
 ORDER BY
       s.owner, s.table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Global Temporary Tables with Stats';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.owner, s.table_name, s.num_rows, s.last_analyzed, s.stale_stats, s.stattype_locked
  FROM dba_tab_statistics s,
       dba_tables t
 WHERE s.object_type = ''TABLE''
   AND s.owner NOT IN &&exclusion_list.
   AND s.owner NOT IN &&exclusion_list2.
   AND s.last_analyzed IS NOT NULL
   AND s.table_name NOT LIKE ''BIN%''
   AND t.owner = s.owner
   AND t.table_name = s.table_name
   AND t.temporary = ''Y''
 ORDER BY
       s.owner, s.table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Temp Tables with Stats';
DEF main_table = 'DBA_TAB_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.owner, s.table_name, t.temporary, s.num_rows, s.last_analyzed, s.stale_stats, s.stattype_locked
  FROM dba_tab_statistics s,
       dba_tables t
 WHERE s.object_type = ''TABLE''
   AND s.owner NOT IN &&exclusion_list.
   AND s.owner NOT IN &&exclusion_list2.
   AND s.last_analyzed IS NOT NULL
   /*AND s.stale_stats = ''YES''*/
   AND (s.table_name LIKE ''%TEMP'' OR s.table_name LIKE ''%\_TEMP\_%'' ESCAPE ''\'')
   AND s.table_name NOT LIKE ''BIN%''
   AND t.owner = s.owner
   AND t.table_name = s.table_name
 ORDER BY
       s.owner, s.table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SYS Stats for WRH$, WRI$, WRM$ and WRR$ Tables';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
select /*+ &&top_level_hints. */ 
table_name, blocks, num_rows, sample_size, last_analyzed
from dba_tables 
where owner = ''SYS''
and table_name like ''WR_$%''
order by table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SYS Stats for WRH$, WRI$, WRM$ and WRR$ Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
select /*+ &&top_level_hints. */ 
table_name, index_name, blevel, leaf_blocks, distinct_keys, num_rows, sample_size, last_analyzed
from dba_indexes 
where owner = ''SYS''
and table_name like ''WR_$%''
order by table_name, index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Table Modifications for WRH$, WRI$, WRM$ and WRR$';
DEF main_table = 'DBA_TAB_MODIFICATIONS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       table_name, partition_name, inserts, updates, deletes, timestamp, truncated
  FROM dba_tab_modifications
 WHERE table_owner = ''SYS''
   AND table_name LIKE ''WR_$%''
 ORDER BY
       table_name, partition_name
';
END;
/
@@edb360_9a_pre_one.sql

