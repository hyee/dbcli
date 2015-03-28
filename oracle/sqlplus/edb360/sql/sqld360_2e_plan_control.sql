DEF section_name = 'Plan Control';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

COL sql_text NOPRI

DEF title = 'SQL Profiles';
DEF main_table = 'DBA_SQL_PROFILES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM dba_sql_profiles 
 WHERE signature IN ( &&exact_matching_signature. , &&force_matching_signature. ) 
   AND ''&&tuning_pack.'' = ''Y''
 ORDER BY category, name
';
END;
/
@@sqld360_9a_pre_one.sql

COL sql_text PRI



COL sql_text NOPRI

DEF title = 'SQL Plan Baselines';
DEF main_table = 'DBA_SQL_PLAN_BASELINES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM dba_sql_plan_baselines
 WHERE signature IN ( &&exact_matching_signature. , &&force_matching_signature. ) 
 ORDER BY plan_name
';
END;
/
@@sqld360_9a_pre_one.sql

COL sql_text PRI



COL sql_text NOPRI

DEF title = 'SQL Patches';
DEF main_table = 'DBA_SQL_PATCHES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM dba_sql_patches
 WHERE signature IN ( &&exact_matching_signature. , &&force_matching_signature. ) 
 ORDER BY category, name
';
END;
/
@@sqld360_9a_pre_one.sql

COL sql_text PRI

