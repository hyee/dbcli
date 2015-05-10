DEF section_name = 'Objects';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Tables';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tables
 WHERE (owner, table_name) in &&tables_list.
 ORDER BY owner, table_name
';
END;
/
@@sqld360_9a_pre_one.sql

DEF title = 'Indexes';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_indexes
 WHERE (table_owner, table_name) in &&tables_list.
 ORDER BY table_owner, table_name, index_name
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Index Columns';
DEF main_table = 'DBA_INDEXES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_ind_columns
 WHERE (table_owner, table_name) in &&tables_list.
 ORDER BY table_owner, table_name, index_name, column_position
';
END;
/
@@sqld360_9a_pre_one.sql


-- compute low and high values for each table column
-- the delete is safe, one SQL at a time
DELETE plan_table WHERE statement_id = 'SQLD360_LOW_HIGH'; 
DECLARE
  l_low VARCHAR2(256);
  l_high VARCHAR2(256);
  FUNCTION compute_low_high (p_data_type IN VARCHAR2, p_raw_value IN RAW)
  RETURN VARCHAR2 AS
    l_number NUMBER;
    l_varchar2 VARCHAR2(256);
    l_date DATE;
  BEGIN
    IF p_data_type = 'NUMBER' THEN
      DBMS_STATS.convert_raw_value(p_raw_value, l_number);
      RETURN TO_CHAR(l_number);
    ELSIF p_data_type IN ('VARCHAR2', 'CHAR', 'NVARCHAR2', 'CHAR2') THEN
      DBMS_STATS.convert_raw_value(p_raw_value, l_varchar2);
      RETURN l_varchar2;
    ELSIF SUBSTR(p_data_type, 1, 4) IN ('DATE', 'TIME') THEN
      DBMS_STATS.convert_raw_value(p_raw_value, l_date);
      RETURN TO_CHAR(l_date, 'YYYY-MM-DD HH24:MI:SS');
    ELSE
      RETURN RAWTOHEX(p_raw_value);
    END IF;
  END compute_low_high;
BEGIN
  FOR i IN (SELECT owner, table_name, column_name, data_type, low_value, high_value
              FROM dba_tab_cols
             WHERE (owner, table_name) IN &&tables_list_s.
               AND '&&sqld360_conf_translate_lowhigh.' = 'Y')
  LOOP
    l_low := compute_low_high(i.data_type, i.low_value);
    l_high := compute_low_high(i.data_type, i.high_value);
    INSERT INTO plan_table (statement_id, object_owner, object_name, object_type, partition_start, partition_stop)
    VALUES ('SQLD360_LOW_HIGH', i.owner, i.table_name, i.column_name, l_low, l_high);
  END LOOP;
END;
/

DEF title = 'Columns';
DEF main_table = 'DBA_TAB_COLS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       a.*, b.partition_start low_value_translated, b.partition_stop high_value_translated
  FROM dba_tab_cols a, 
       plan_table b
 WHERE (a.owner, a.table_name) in &&tables_list.
   AND a.owner = b.object_owner(+)
   AND a.table_name = b.object_name(+)
   AND a.column_name = b.object_type(+)
   AND b.statement_id(+) = ''SQLD360_LOW_HIGH''
 ORDER BY a.owner, a.table_name, a.column_id
';
END;
/
@@sqld360_9a_pre_one.sql


-- find if there are histograms 
COL num_histograms NEW_V num_histograms
SELECT TRIM(TO_CHAR(COUNT(DISTINCT owner||'.'||table_name))) num_histograms 
  FROM dba_tab_cols
 WHERE (owner, table_name) in &&tables_list_s.
   AND histogram <> 'NONE';
DEF title= 'Histograms'
DEF main_table = 'DBA_TAB_HISTOGRAMS'

--this one initiated a new file name, need it in the next anchor
@@sqld360_0s_pre_nondef
SET TERM OFF ECHO OFF 
-- need to fix the file name for the partitions
SPO &&sqld360_main_report..html APP;
PRO <li>Histograms <small><em>(&&num_histograms.)</em></small> 
PRO <a href="&&one_spool_filename..html">page</a>
PRO </li>
SPO OFF;
@@sqld360_3d_histograms.sql


DEF title = 'Constraints';
DEF main_table = 'DBA_CONSTRAINTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_constraints 
 WHERE (owner, table_name) in &&tables_list.
 ORDER BY owner, table_name, constraint_type
';
END;
/
@@sqld360_9a_pre_one.sql


-- in 12c need to access DBA_TAB_COL_STATISTICS too for columns NOTES and SCOPE
-- that are not included in DBA_TAB_COLS

DEF title = 'Table Partitions';
DEF main_table = 'DBA_TAB_PARTITIONS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tab_partitions
 WHERE (table_owner, table_name) in &&tables_list.
 ORDER BY table_owner, table_name, partition_position
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Index Partitions';
DEF main_table = 'DBA_IND_PARTITIONS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       a.*
  FROM dba_ind_partitions a,
       dba_indexes b
 WHERE (b.table_owner, b.table_name) in &&tables_list.
   AND a.index_owner = b.owner
   AND a.index_name = b.index_name
 ORDER BY a.index_owner, a.index_name, a.partition_position
';
END;
/
@@sqld360_9a_pre_one.sql


-- find if there are partitioned tables involved
COL cols_from_part_tables NEW_V cols_from_part_tables
COL part_tables NEW_V part_tables 
SELECT TRIM(TO_CHAR(COUNT(*))) cols_from_part_tables, 
       TRIM(TO_CHAR(COUNT(DISTINCT owner||' '||table_name))) part_tables
  FROM dba_part_col_statistics
 WHERE (owner, table_name) in &&tables_list_s.;

DEF title= 'Partitions Columns'
DEF main_table = 'DBA_TAB_PARTITIONS'

--this one initiated a new file name, need it in the next anchor
@@sqld360_0s_pre_nondef
SET TERM OFF ECHO OFF 
-- need to fix the file name for the partitions
SPO &&sqld360_main_report..html APP;
PRO <li>Partitions Columns <small><em>(&&part_tables.)</em></small> 
PRO <a href="&&one_spool_filename..html">page</a>
PRO </li>
SPO OFF;
@@sqld360_3b_partitions_columns.sql


DEF title = 'Table Modifications';
DEF main_table = 'DBA_TAB_MODIFICATIONS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tab_modifications
 WHERE (table_owner, table_name) in &&tables_list.
 ORDER BY table_owner, table_name, partition_name, subpartition_name
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Segments';
DEF main_table = 'DBA_SEGMENTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM (SELECT *
          FROM dba_segments
         WHERE (owner, segment_name) in &&tables_list.
        UNION ALL
        SELECT a.*
          FROM dba_segments a,
               dba_indexes b
         WHERE (b.table_owner, b.table_name) in &&tables_list.
           AND a.owner = b.owner
           AND a.segment_name = b.index_name)
 ORDER BY owner, segment_name, segment_type desc
';
END;
/
@@sqld360_9a_pre_one.sql

DEF title = 'Objects';
DEF main_table = 'DBA_OBJECTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM (SELECT *
          FROM dba_objects
         WHERE (owner, object_name) in &&tables_list.
        UNION ALL
        SELECT a.*
          FROM dba_objects a,
               dba_indexes b
         WHERE (b.table_owner, b.table_name) in &&tables_list.
           AND a.owner = b.owner
           AND a.object_name = b.index_name)
 ORDER BY owner, object_name, object_type desc
';
END;
/
@@sqld360_9a_pre_one.sql
