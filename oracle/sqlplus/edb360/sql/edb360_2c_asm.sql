@@&&edb360_0g.tkprof.sql
DEF section_id = '2c';
DEF section_name = 'Automatic Storage Management (ASM)';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'ASM Attributes';
DEF main_table = 'V$ASM_ATTRIBUTE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$asm_attribute
 ORDER BY
       1, 2
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'ASM Client';
DEF main_table = 'V$ASM_CLIENT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$asm_client
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'ASM Template';
DEF main_table = 'V$ASM_TEMPLATE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$asm_template
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'ASM Disk Group';
DEF main_table = 'V$ASM_DISKGROUP_STAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$asm_diskgroup_stat
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'ASM Disk';
DEF main_table = 'V$ASM_DISK_STAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$asm_disk_stat
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'ASM Disk IO Stats';
DEF main_table = 'GV$ASM_DISK_IOSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$asm_disk_iostat
 ORDER BY
       1, 2, 3, 4, 5
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql
