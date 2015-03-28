@@sqld360_0b_pre.sql
@@&&skip_diagnostics.sqld360_0x_xtract_ash.sql
@@sqld360_0t_xtract_tables.sql
DEF max_col_number = '5';
DEF column_number = '0';
SPO &&sqld360_main_report..html APP;
PRO <table><tr class="main">
PRO <td class="c">1/&&max_col_number.</td>
PRO <td class="c">2/&&max_col_number.</td>
PRO <td class="c">3/&&max_col_number.</td>
PRO <td class="c">4/&&max_col_number.</td>
PRO <td class="c">5/&&max_col_number.</td>
PRO </tr><tr class="main"><td>
PRO <img src="SQLd360_img.jpg" alt="SQLd360" height="102" width="165"
PRO title="SQLd360 is a free tool that provides a 360-degree view of a SQL statement. 
PRO Its output can be used for SQL tuning or to just collect a baseline for a critical statement.
PRO
PRO With SQLd360, a user with limited access can acquire a good understanding of a SQL statement 
PRO without having to log into the server directly. 
PRO This capability is of great value to developers, system administrators, 3rd party consultants, 
PRO or any remote user with restricted access.">
PRO <br>
PRO
SPO OFF;

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '1';

@@&&from_edb360.sqld360_1a_configuration.sql
@@sqld360_1b_identification.sql
@@&&skip_10g.&&skip_11r1.sqld360_1c_xpand.sql
@@sqld360_1d_standalone.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '2';

SPO &&sqld360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@sqld360_2a_plans.sql
@@sqld360_2e_plan_control.sql
@@sqld360_2b_performance.sql
@@sqld360_2c_binds.sql
@@sqld360_2d_cursor_sharing.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '3';

SPO &&sqld360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@sqld360_3a_objects.sql
@@sqld360_3c_stats_history.sql
@@sqld360_3d_metadata.sql


PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '4';

SPO &&sqld360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@sqld360_4a_impact.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DEF column_number = '5';

SPO &&sqld360_main_report..html APP;
PRO
PRO </td><td>
PRO
SPO OFF;

@@&&skip_10g.&&skip_11r1.sqld360_5f_10053.sql
@@&&skip_tuning.&&skip_10g.sqld360_5b_sqlmon.sql
-- @@&&skip_diagnostics.sqld360_5c_ash.sql
@@&&skip_tcb.&&skip_10g.sqld360_5a_tcb.sql
@@&&skip_diagnostics.sqld360_5r_rawash.sql
@@&&from_edb360.&&skip_diagnostics.sqld360_5e_eadam_ash.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- log footer
SPO &&sqld360_log..txt APP;
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
DEF;
PRO
PRO end log
SPO OFF;

-- main footer
SPO &&sqld360_main_report..html APP;
PRO
PRO </td></tr></table>
SPO OFF;
@@sqld360_0c_post.sql
