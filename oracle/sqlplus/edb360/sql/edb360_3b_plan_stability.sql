@@&&edb360_0g.tkprof.sql
DEF section_id = '3b';
DEF section_name = 'Plan Stability';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'SQL Patches';
DEF main_table = 'DBA_SQL_PATCHES';
BEGIN
  :sql_text := '
SELECT *
  FROM dba_sql_patches
 ORDER BY
       created DESC
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql       

DEF title = 'SQL Profiles';
DEF main_table = 'DBA_SQL_PROFILES';
BEGIN
  :sql_text := '
SELECT *
  FROM dba_sql_profiles
 ORDER BY
       created DESC
';
END;
/
@@&&skip_tuning.edb360_9a_pre_one.sql       

DEF title = 'SQL Plan Profiles Summary by Type and Status';
DEF main_table = 'DBA_SQL_PROFILES';
BEGIN
  :sql_text := '
SELECT COUNT(*),
       category,
       type,
       status,
       MIN(created) min_created,
       MAX(created) max_created,
       MEDIAN(created) median_created
  FROM dba_sql_profiles
 GROUP BY
       category,
       type,
       status
 ORDER BY
       1 DESC, 2, 3, 4
';
END;
/
@@&&skip_tuning.edb360_9a_pre_one.sql       

DEF title = 'SQL Profiles Summary by Creation Month';
DEF main_table = 'DBA_SQL_PROFILES';
BEGIN
  :sql_text := '
SELECT TO_CHAR(TRUNC(created, ''MM''), ''YYYY-MM'') created,
       COUNT(*)
  FROM dba_sql_profiles
 GROUP BY
       TRUNC(created, ''MM'')
 ORDER BY
       1
';
END;
/
@@&&skip_tuning.edb360_9a_pre_one.sql       

DEF title = 'SQL Plan Baselines';
DEF main_table = 'DBA_SQL_PLAN_BASELINES';
BEGIN
  :sql_text := '
SELECT *
  FROM dba_sql_plan_baselines
 ORDER BY
       created DESC
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql       

DEF title = 'SQL Plan Baselines Summary by Status';
DEF main_table = 'DBA_SQL_PLAN_BASELINES';
BEGIN
  :sql_text := '
SELECT COUNT(*),
       enabled,
       accepted,
       fixed,
       reproduced,
       MIN(created) min_created,
       MAX(created) max_created,
       MEDIAN(created) median_created
  FROM dba_sql_plan_baselines
 GROUP BY
       enabled,
       accepted,
       fixed,
       reproduced
 ORDER BY
       1 DESC, 2, 3, 4, 5
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql       

DEF title = 'SQL Plan Baselines Summary by Creation Month';
DEF main_table = 'DBA_SQL_PLAN_BASELINES';
BEGIN
  :sql_text := '
SELECT TO_CHAR(TRUNC(created, ''MM''), ''YYYY-MM'') created,
       COUNT(*)
  FROM dba_sql_plan_baselines
 GROUP BY
       TRUNC(created, ''MM'')
 ORDER BY
       1
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql       


