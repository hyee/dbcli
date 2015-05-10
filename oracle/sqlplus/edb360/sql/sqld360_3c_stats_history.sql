DEF section_name = 'Statistics Versions';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Tables Statistics Versions';
DEF main_table = 'WRI$_OPTSTAT_TAB_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       o.owner owner,
       o.object_name table_name,
       h.*
  FROM sys.wri$_optstat_tab_history h,
       dba_objects o
 WHERE (o.owner, o.object_name) in &&tables_list.
   AND o.object_type = ''TABLE''
   AND o.object_id = h.obj#
   AND ''&&diagnostics_pack.'' = ''Y''
 ORDER BY o.owner, o.object_name, h.savtime desc
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Indexes Statistics Versions';
DEF main_table = 'WRI$_OPTSTAT_IND_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       i.owner,
       i.table_name,
       i.index_name, 
       h.*
  FROM sys.wri$_optstat_ind_history h,
       dba_objects o,
       dba_indexes i
 WHERE (i.table_owner, i.table_name) in &&tables_list.
   AND i.index_name = o.object_name
   AND i.owner = o.owner
   AND o.object_type = ''INDEX''
   AND o.object_id = h.obj#
   AND ''&&diagnostics_pack.'' = ''Y''
 ORDER BY i.table_owner, i.table_name, i.index_name, h.savtime desc
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Columns Statistics Versions';
DEF main_table = 'WRI$_OPTSTAT_IND_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       c.owner,
       c.table_name,
       c.column_name, 
       h.*
  FROM sys.wri$_optstat_histhead_history h,
       dba_objects o,
       dba_tab_cols c
 WHERE (c.owner, c.table_name) IN &&tables_list.
   AND c.table_name = o.object_name
   AND c.owner = o.owner
   AND o.object_type = ''TABLE''
   AND o.object_id = h.obj#
   AND c.column_id = h.intcol#
   AND ''&&diagnostics_pack.'' = ''Y''
 ORDER BY c.owner, c.table_name, c.column_id, h.savtime desc
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Partitions Statistics Versions';
DEF main_table = 'WRI$_OPTSTAT_IND_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
        p.table_owner, 
        p.table_name,
        p.partition_name,
        p.partition_position, 
        h.*
  FROM (SELECT table_owner, table_name, partition_name, partition_position,
               ROW_NUMBER() OVER (ORDER BY partition_position) rn, COUNT(*) OVER () num_part
          FROM dba_tab_partitions 
         WHERE (table_owner, table_name) IN &&tables_list.
       ) p,
       dba_objects o,
       sys.wri$_optstat_tab_history h
 WHERE (p.rn <= &&sqld360_conf_first_part OR p.rn >= num_part-&&sqld360_conf_last_part)
   AND o.object_type = ''TABLE PARTITION''
   AND p.table_owner = o.owner
   AND p.table_name = o.object_name
   AND p.partition_name = o.subobject_name
   AND o.object_id = h.obj#
   AND ''&&diagnostics_pack.'' = ''Y''
 ORDER BY p.table_owner, p.table_name, p.partition_name, p.partition_position DESC, h.savtime desc 
';
END;
/
@@sqld360_9a_pre_one.sql
