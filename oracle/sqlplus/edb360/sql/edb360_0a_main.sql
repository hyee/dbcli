@@edb360_00_config.sql
@@edb360_0b_pre.sql
DEF section_id = '0a';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
DEF max_col_number = '7';
DEF column_number = '0';
SPO &&edb360_main_report..html APP;
PRO <table><tr class="main">
PRO <td class="c">1/&&max_col_number.</td>
PRO <td class="c">2/&&max_col_number.</td>
PRO <td class="c">3/&&max_col_number.</td>
PRO <td class="c">4/&&max_col_number.</td>
PRO <td class="c">5/&&max_col_number.</td>
PRO <td class="c">6/&&max_col_number.</td>
PRO <td class="c">7/&&max_col_number.</td>
PRO </tr><tr class="main"><td>
PRO <img src="edb360_img.jpg" alt="eDB360" height="123" width="195"
PRO title="eDB360 is a free tool that provides a 360-degree view of an Oracle database. 
PRO Its output can be used as a foundation for a database health-check, 
PRO a performance evaluation or to collect OS resource utilization needed for a sizing and provisioning plan.
PRO
PRO With eDB360, a user with limited access can acquire a good understanding of an Oracle database 
PRO without having to log into the server directly. 
PRO This capability is of great value to developers, system administrators, 3rd party consultants, 
PRO or any remote user with restricted access.">
PRO <br>
SPO OFF;

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '1';

@@&&edb360_1a.configuration.sql
@@&&edb360_1b.security.sql
@@&&edb360_1c.audit.sql
@@&&edb360_1d.memory.sql
@@&&edb360_1e.resources.sql
@@&&edb360_1f.resources_statspack.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '2';

SPO &&edb360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&edb360_2a.admin.sql
@@&&edb360_2b.storage.sql
@@&&edb360_2c.asm.sql
@@&&edb360_2d.rman.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '3';

SPO &&edb360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&edb360_3a.resource_mgm.sql
@@&&edb360_3b.plan_stability.sql
@@&&edb360_3c.cbo_stats.sql
@@&&edb360_3d.performance.sql
@@&&skip_diagnostics.&&edb360_3e.os_stats.sql
@@&&is_single_instance.&&skip_diagnostics.&&edb360_3f.ic_latency.sql
@@&&is_single_instance.&&skip_diagnostics.&&edb360_3g.ic_performance.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '4';

SPO &&edb360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&skip_diagnostics.&&edb360_4a.sga_stats.sql
@@&&skip_diagnostics.&&edb360_4b.pga_stats.sql
@@&&skip_diagnostics.&&edb360_4c.mem_stats.sql
@@&&skip_diagnostics.&&edb360_4d.time_model.sql
@@&&skip_diagnostics.&&edb360_4e.time_model_comp.sql
@@&&skip_diagnostics.&&skip_10g.&&edb360_4f.io_waits.sql
@@&&skip_diagnostics.&&skip_10g.&&edb360_4g.io_waits_top.sql
@@&&edb360_4h.parallel_execution.sql
@@&&skip_diagnostics.&&edb360_4i.sysmetric_history.sql
@@&&skip_diagnostics.&&edb360_4j.sysmetric_summary.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '5';

SPO &&edb360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&skip_diagnostics.&&edb360_5a.ash.sql
@@&&skip_diagnostics.&&edb360_5b.ash_wait.sql
@@&&skip_diagnostics.&&edb360_5c.ash_top.sql
@@&&skip_diagnostics.&&edb360_5d.sysstat.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '6';

SPO &&edb360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&skip_diagnostics.&&edb360_6a.ash_class.sql
@@&&skip_diagnostics.&&edb360_6b.ash_event.sql
@@&&skip_diagnostics.&&edb360_6c.ash_sql.sql
@@&&skip_diagnostics.&&edb360_6d.ash_programs.sql
@@&&skip_diagnostics.&&edb360_6e.ash_modules.sql
@@&&skip_diagnostics.&&edb360_6f.ash_users.sql
@@&&skip_diagnostics.&&edb360_6g.ash_plsql.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '7';

SPO &&edb360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&skip_diagnostics.&&edb360_7a.rpt.sql
@@&&skip_diagnostics.&&edb360_7b.sql_sample.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- log footer
SPO &&edb360_log..txt APP;
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
DEF;
SHOW PARAMETERS;
PRO
PRO end log
SPO OFF;

-- main footer
SPO &&edb360_main_report..html APP;
PRO
PRO </td></tr></table>
SPO OFF;
@@edb360_0c_post.sql
EXEC DBMS_APPLICATION_INFO.SET_MODULE(NULL,NULL);

-- list of generated files
HOS unzip -l &&edb360_main_filename._&&edb360_file_time.
