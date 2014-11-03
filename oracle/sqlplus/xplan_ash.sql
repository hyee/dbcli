-- Store current SQL*Plus environment
-- This requires at least a 10.2 SQL*Plus version to work
store set .xplan_settings replace
set echo off verify off termout off timing off define "&" concat "." trimspool on
-- If you need to debug, uncomment the following line
-- set echo on verify on termout on
set doc off
doc
-- ----------------------------------------------------------------------------------------------
--
-- Script:       xplan_ash.sql
--
-- Version:      4.1
--               June 2014
--
-- Author:       Randolf Geist
--               http://oracle-randolf.blogspot.com
--
-- Description:  Single SQL statement execution analysis using ASH (from 10.2 on)
--
--               Furthermore a free-standing SQL wrapper over DBMS_XPLAN. Provides access to the
--               DBMS_XPLAN.DISPLAY_CURSOR / DISPLAY_AWR pipelined function for a given SQL_ID and CHILD_NUMBER (PLAN_HASH_VALUE for DISPLAY_AWR)
--
--               This is a tool for an extended analysis of the data provided by the
--               Runtime Profile (aka. Rowsource Statistics enabled via
--               SQL_TRACE = TRUE, STATISTICS_LEVEL = ALL or GATHER_PLAN_STATISTICS hint)
--               and reported via the ALLSTATS/MEMSTATS/IOSTATS formatting option of
--               DBMS_XPLAN.DISPLAY_CURSOR
--
--               In addition ASH data can be reported for the following purposes:
--
--               1. Show general information about SQL execution activity
--               2. Provide activity information per SQL plan line id (11g+)
--               3. Show distribution of work between Parallel Workers / Query Coordinator / RAC Nodes based on ASH data
--
--               The ASH data options make this a kind of "real time" monitoring tool. Unfortunately the
--               free ASH implementations (and 10g versions) lack the correlation to the SQL plan line id, hence information on plan line level is only
--               possible with the original ASH implementation from 11g onwards
--
--               Note that this script supports in principle other ASH sources - everything can be configured below (S-ASH is now also supported)
--
--               A second configuration set is provided that is based on DBA_HIST_ACTIVE_SESS_HISTORY for running analysis on historic ASH data
--               Although the sample frequency of 10 seconds limits the significance of the analysis it might be much better than nothing at all
--
--               !! The (built-in) ASH reporting requires at least Enterprise Edition plus the Diagnostic Pack license !!
--
-- Versions:     This utility will work from version 10.2 and later
--               The ASH based information on plan line level is only available from 11g on (10g has ASH but no relation to SQL execution instances or SQL plan lines)
--
--               Tested with database versions 10.2.0.4, 10.2.0.5, 11.1.0.7, 11.2.0.1, 11.2.0.2 and 11.2.0.3, 12.1.0.1
--
--               Tested with SQL*Plus / client versions 10.2.0.4, 11.1.0.7, 11.2.0.1, 11.2.0.2, 12.1.0.1 including InstantClient 11.2.0.1
--
-- Required:     The same access as DBMS_XPLAN.DISPLAY_CURSOR (DISPLAY_AWR) requires. See the documentation
--               of the DBMS_XPLAN package for your Oracle version for more information
--
--               !! The ASH reporting requires at least Enterprise Edition plus the Diagnostic Pack license !!
--
--               In addition the script directly queries
--               1) (G)V$SESSION
--               2) GV$SQL_PLAN / GV$SQL_PLAN_STATISTICS_ALL (DBA_HIST_SQL_PLAN)
--               3) GV$SQL
--               4) GV$SQL_MONITOR / optionally GV$SQL_PLAN_MONITOR
--               5) GV$ACTIVE_SESSION_HISTORY (DBA_HIST_ACTIVE_SESS_HISTORY)
--               6) V$DATABASE
--               7) GV$SQLSTATS (DBA_HIST_SQLTEXT, SASH_SQLTXT)
--               8) V$ASH_INFO (fallback to GV$ACTIVE_SESSION_HISTORY if unavailable)
--
-- Note:         This script writes two files during execution (.xplan_ash_temp and .xplan_ash_settings), hence it requires write access to the current working directory
--
--               If you see some error messages similar to the following during execution:
--
--               SP2-0103: Nothing in SQL buffer to run.
--
--               SP2-0110: Cannot create save file ".xplan_ash_temp"
--
--               plan_operations as
--                               *
--               ERROR at line 14:
--               ORA-00933: SQL command not properly ended
--
--               plan_operations as
--                               *
--               ERROR at line 2:
--               ORA-00900: invalid SQL statement
--
--               then you cannot write to your current working directory
--
-- Credits:      Based on the original XPLAN implementation by Adrian Billington (http://www.oracle-developer.net/utilities.php
--               resp. http://www.oracle-developer.net/content/utilities/xplan.zip)
--               and inspired by Kyle Hailey's TCF query (http://dboptimizer.com/2011/09/20/display_cursor/)
--
-- Features:     A lot of information about a single SQL execution from Active Session History (and Real-Time SQL Monitoring if available and requested)
--               See below for a more detailed description of the information sections based on ASH / SQL Monitoring
--
--               Furthermore additional columns on execution plan line level, injected into the DBMS_XPLAN.DISPLAY* output
--
--               There are two sources for the additional columns on execution plan line level: Extended Rowsource Statistics and Active Session History/Real-Time SQL Monitoring
--
--               Extended Rowsource Statistics:
--
--               In addition to the PID (The PARENT_ID) and ORD (The order of execution, note that this doesn't account for the special cases so it might be wrong)
--               columns added by Adrian's wrapper the following additional execution plan columns over ALLSTATS are available (see column configuration where it can be customized which to show):
--
--               A_TIME_SELF        : The time taken by the operation itself - this is the operation's cumulative time minus the direct descendants operation's cumulative time
--               LIO_SELF           : The LIOs done by the operation itself - this is the operation's cumulative LIOs minus the direct descendants operation's cumulative LIOs
--               READS_SELF         : The reads performed the operation itself - this is the operation's cumulative reads minus the direct descendants operation's cumulative reads
--               WRITES_SELF        : The writes performed the operation itself - this is the operation's cumulative writes minus the direct descendants operation's cumulative writes
--               A_TIME_SELF_GRAPH  : A graphical representation of A_TIME_SELF relative to the total A_TIME
--               LIO_SELF_GRAPH     : A graphical representation of LIO_SELF relative to the total LIO
--               READS_SELF_GRAPH   : A graphical representation of READS_SELF relative to the total READS
--               WRITES_SELF_GRAPH  : A graphical representation of WRITES_SELF relative to the total WRITES
--               LIO_RATIO          : Ratio of LIOs per row generated by the row source - the higher this ratio the more likely there could be a more efficient way to generate those rows (be aware of aggregation steps though)
--               TCF_GRAPH          : Each "+"/"-" sign represents one order of magnitude based on ratio between E_ROWS_TIMES_START and A-ROWS. Note that this will be misleading with Parallel Execution (see E_ROWS_TIMES_START)
--               E_ROWS_TIMES_START : The E_ROWS multiplied by STARTS - this is useful for understanding the actual cardinality estimate for related combine child operations getting executed multiple times. Note that this will be misleading with Parallel Execution
--
--               For the special Rowsource Statistics mode 3 ("_rowsource_statistics_sampfreq" = 3) where only actual cardinalities are measured, XPLAN_ASH from version 3.0 on supports a special FORMAT option "AROWS".
--               This adds a column "A-Rows" (similar to what DISPLAY_CURSOR does when using the *STATS formatting option) since DISPLAY_CURSOR doesn't support this mode properly
--               - it doesn't show the A-Rows in that case although the columns are populated in GV$SQL_PLAN_STATISTICS_ALL
--               Note that you usually want to use "AROWS LAST" similar to "ALLSTATS LAST" if you want to see the actual cardinalities of the last execution
--
--               More information including demos can be found online at http://oracle-randolf.blogspot.com/2011/12/extended-displaycursor-with-rowsource.html
--
--               Active Session History:
--
--               The following information is available based on ASH data (from 11g on). Note that this can be configured in two ways:
--               - The "options" determine what information will be queried / shown in general (see below for more details)
--               - The column configuration can be used to customize exactly which columns to show as part the execution plan output (if available)
--
--               Act                              : Indicates the most recent active plan lines according to ASH (only applicable if the statement is currently executing)
--               Start                            : The second this the plan line was active for the first time
--               Dur(T)                           : Show the number of seconds the plan line is/was active (first sample to last sample)
--               Dur(A)                           : Show the number of seconds the plan line is/was active (active samples)
--               Time Active Graph                : Show a graphical representation of the activity timeline of the plan line
--               Parallel Distribution ASH        : Show the Top N processes names along with the number of samples found per SQL plan line id. A trailing "..." indicates that there are more than N processes found (only applicable when Parallel Execution detected). The leading number (for example "5:...") shows the unique number of processes (five in this case) found in the ASH samples for this plan line
--               Parallel Execution Skew ASH      : Indicator of data distribution skew - the bigger this graph the more relevant the skew of this execution plan line is to the overall execution time (only applicable when Parallel Execution detected)
--               Avg Act Sess Graph (T) ASH       : Show the Average Active Sessions per execution plan line (based on first sample to sample time). This allows to detect temporal skew and data distribution skew, but you need to look at all plan lines that are active at the same time to see if there is skew or not (only applicable when Parallel Execution detected, hidden by default from 4.0 on)
--               Avg Act Sess Graph (A) ASH       : Show the Average Active Sessions per execution plan line (based on active samples). This allows to detect temporal skew and data distribution skew, but you need to look at all plan lines that are active at the same time to see if there is skew or not (only applicable when Parallel Execution detected, hidden by default from 4.0 on)
--               Med Act Sess Graph ASH           : Show the Median Active Sessions per execution plan line (based on active samples). This allows to detect temporal skew and data distribution skew, but you need to look at all plan lines that are active at the same time to see if there is skew or not (only applicable when Parallel Execution detected, hidden by default from 4.0 on)
--               Activity Graph ASH               : Show a graphical representation (CPU + Other activity) of the number of samples against that SQL plan line id relative to the total number of samples
--               Top N Activity ASH               : Show the Top N activities (waits or ON CPU) from ASH for that SQL plan line id. A trailing "..." indicates that there are more than N activities found
--
--               The default value for N is 5, but can be changed in the configuration section below, for both "Parallel Distribution ASH" and the "Top N Activity ASH".
--               You can also configure the width of the ASH graphs and the character used for the "Graphs" and "Act" column
--
--               Since version 4.0 Real-Time SQL Monitoring info will be added on execution plan line level if available and requested (see the ASH options below)
--
--               The following columns are available:
--
--               Execs  : The number of times this execution plan line was started
--               A-Rows : The actual number of rows generated by this execution plan line
--               PGA    : Max. PGA usage of this execution plan operation if applicable, in (K,M,G,E)bytes
--               Temp   : Max. Temp usage of this execution plan operation if applicable, in (K,M,G,E)bytes
--               Reads  : I/O Reads of this execution plan operation if applicable, in (K,M,G,E)bytes
--               Writes : I/O Writes of this execution plan operation if applicable, in (K,M,G,E)bytes
--               CellO% : The Cell Offload Percentage of this operation if applicable
--
--               Row distribution for Parallel Execution
--
--               The column "Parallel Distribution ASH" will have also the Rowcount per Parallel Execution Server added if monitoring info gets used and is available.
--               The Rowcount is added in square brackets to the process, after the number of samples in paranthesis, something like this:
--
--               P012(44)[183K]
--
--               This means process P012 was sampled 44 times for this execution plan line and produced 183K rows according to Real-Time SQL Monitoring
--
--               Note that this information is crucial in understanding Data Distribution Skew and not available from the official Real-Time SQL Monitoring report up to 11.2
--               12c SQL Monitoring allows to extract this information via the report
--
--               If Real-Time SQL Monitoring information is available (and requested) this column will now show process and rows information even for those processes that are not sampled in ASH
--               In such a case these processes will show up with a sample count of 0 and the leading number indicating the number of processes sampled for this plan line can be less than the processes shown
--               since it refers to ASH sample data, not Real-Time SQL Monitoring
--
--               So this can look like this for example:
--
--               0:P007(0)[666K],P000(0)[0],P001(0)[0],P002(0)[0],P003(0)[0],...
--
--               Which means that for this plan line no processes were found in the ASH samples, but Real-Time SQL Monitoring information is available - and the processes will be sorted by sample count descending, rows descending
--               Since in above example no ASH samples are found, the processes are effectively sorted by rows descending
--
--               If you find this output messy and want to return to previous behaviour (show only processes from ASH samples) by setting the configuration switch "show_monitor_rowcount" to anything else than the default of "YES"
--
-- Usage:        @xplan_ash.sql 1[sql_id|sid=<nnn>[@<inst_id>]] 2[SQL_EXEC_START] 3[SQL_EXEC_ID (SQL_EXEC_END for pre-11g)] 4[*AUTO*|CURR|HIST|MIXED] 5[ON|*OFF*] 6[MONITOR|*ASH*] 7[[*ASH*|LIMITED_ASH][,][*DISTRIB*][,][*MONITOR*][,][*TIMELINE*]|[NONE]] 8[cursor_child_number (plan_hash_value for the historic ASH)] 9[DBMS_XPLAN_format_option] 10[comma_sep_column_list_to_show/hide]
--
--               Parameter 1+8:
--
--               Specify the SQL_ID to be analyzed
--
--               If the SQL_ID is omitted the previously executed SQL_ID and CHILD_NUMBER/PLAN_HASH_VALUE of the current session will be used
--
--               This will be taken either from GV$SESSION (when according to Parameter 7 no ASH should be used) or from Real-Time SQL Monitoring/ASH according to Parameter 6
--
--               Specify a CHILD_NUMBER when referring to CURRent ASH (Parameter 4), specify a PLAN_HASH_VALUE when using the MIXED/HISToric ASH configuration
--
--               Note that when using the ASH functionality (Parameter 7) you usually don't need to specify this parameter:
--
--               If the SQL_ID is specified but the CHILD_NUMBER / PLAN_HASH_VALUE (Parameter 8) is omitted then
--               - If the ASH options are disabled then CHILD_NUMBER 0 is assumed
--               - If ASH / Real-Time SQL Monitoring should be queried, the corresponding CHILD_NUMBER / PLAN_HASH_VALUE will be looked up based on the remaining options specified
--
--               This means that the CHILD_NUMBER should only be specified when using the Rowsource Statistics mode only without ASH
--
--               If instead of a SQL_ID SID=<nnn>[@<inst_id>] is specified as first argument, the most recently executed SQL_ID of the corresponding SID will be taken from either:
--               - Active Session History or Real-Time SQL Monitoring (see Parameter 6 below) when ASH functionality should be used (Parameter 7)
--               - GV$SESSION when ASH functionality should not be used (NONE as Parameter 7)
--
--               Optionally the SID's instance can be specified for RAC
--
--               Note that the SID needs to be either a Query Coordinator's SID for Parallel Execution or a normal, serial session
--               SIDs of Parallel Execution Servers won't work
--
--               This version does not support processing multiple child cursors like DISPLAY_CURSOR / AWR is capable of
--               when passing NULL as CHILD_NUMBER / PLAN_HASH_VALUE to DISPLAY_CURSOR / AWR. Hence a CHILD_NUMBER / PLAN_HASH_VALUE is mandatory, either
--               implicitly generated (see above) or explicitly passed
--
-- RAC:          A note to RAC users below 11.2.0.2: If the current instance was *not* involved in executing the SQL, and the execution plan should be displayed from the Shared Pool (CURR option), in best case the execution plan cannot be found
--               In worst case an incorrect plan will be associated from the local instance Shared Pool (You could have the same SQL_ID / CHILD_NUMBER with different plans in different RAC instances).
--               Therefore you need to be careful with cross-instance / remote-instance executions in RAC
--               Why? The tool relies on DBMS_XPLAN.DISPLAY_CURSOR for showing the execution plan from the Shared Pool - but DISPLAY_CURSOR is limited to the local Shared Pool
--
--               From 11.2.0.2 a workaround is implemented that can "remotely" execute DBMS_XPLAN.DISPLAY_CURSOR on the RAC instance where the correct plan should be in the Library Cache
--
--               Parameter 2+3:
--
--               For 11g+:
--               SQL_EXEC_START: This is required if you're looking for a specific execution instance of a statement in ASH instead of the most recent. It is a date in format "YYYY-MM-DD-HH24:MI:SS" (date mask can be changed in the configuration section, and optional date masks are now supported, see "dm_opt1"/"dm_opt2" configuration parameter)
--               SQL_EXEC_ID   : Also required for the same purpose (defaults to 16777216 if omitted and SQL_EXEC_START is specified, this default can be changed in the configuration section)
--
--               Note that since version 4.0 XPLAN_ASH tries different optional date masks if the default mask doesn't work, this is just to simplify copy&pasting of dates
--               The list of optional date masks can be found in the configuration parameter "dm_opt1/dm_opt2". Feel free to add your favorite date masks there
--
--               Furthermore since version 4.0, if SQL_EXEC_START was specified but SQL_EXEC_ID is left blank and version is 11g+, then a default SQL_EXEC_ID of 16777216 will be used
--               This default SQL_EXEC_ID can be changed - if you have a RAC environment with multiple instances this might make sense to change (configuration parameter "default_sql_exec_id")
--
--               If these two are omitted and the SID and previous session execution cases don't apply then the last execution is searched in either GV$SQL_MONITOR (MONITOR) or GV$ACTIVE_SESSION_HISTORY (the default ASH option, see Parameter 6)
--               The latter option is required if no Tuning Pack license is available, the former option can be used to make sure that the script finds the same latest execution instance as the Real-Time SQL Monitoring
--
--               This information is used as filter on SQL_EXEC_START and SQL_EXEC_ID in ASH. Together with the SQL_ID it uniquely identifies an execution instance of that SQL
--
--               For 10.2:
--               SQL_EXEC_START: This is always mandatory and determines the start samples in ASH. It is a date in format "YYYY-MM-DD-HH24:MI:SS" (date mask can be changed in the configuration section)
--               SQL_EXEC_END  : This is always mandatory and determines the end samples in ASH. It is a date in format "YYYY-MM-DD-HH24:MI:SS" (date mask can be changed in the configuration section)
--
--               For 10.2 these two are mandatory since an exact SQL execution instance cannot be identified in pre-11g ASH data
--
--               See above for SQL_EXEC_START - version 4.0 tries the same optional date masks at SQL_EXEC_END in case of 10g
--
--               Note that from version 3.0 on by default XPLAN_ASH searches for the earliest / latest sample of the identified SQL_ID within the given SQL_EXEC_START / SQL_EXEC_END time period
--               This means you can be lazy and specify a "rough range" of time where you believe the SQL_ID was active and XPLAN_ASH will automatically determine the exact range
--               However, since there is no concept of distinguishing different executions the range identified automatically by XPLAN_ASH might cover multiple executions of the same SQL_ID
--
--               This behaviour can be controlled via the configuration switch "find_min_sample_10g", see the configuration section below
--               When setting that switch != YES the pre-3.0 behaviour will be used that uses the exact given SQL_EXEC_START / SQL_EXEC_END for further processing
--
--               Parameter 4:
--
--               This determines the configuration set to use. The default is AUTO, which means that the script automatically chooses either CURR (V$ACTIVE_SESSION_HISTORY / V$SQL_PLAN) or HIST (DBA_HIST_ACTIVE_SESS_HISTORY / DBA_HIST_SQL_PLAN).
--
--               AUTO at present only works if an SQL_EXEC_START (Parameter 2) is specified. If SQL_EXEC_START is left blank, AUTO means search in CURR for the last execution.
--
--               If SQL_EXEC_START is specified AUTO determines the earliest sample in V$ACTIVE_SESSION_HISTORY and uses either CURR or HIST.
--
--               Other options include:
--
--               Specify CURR if the current ASH from GV$ACTIVE_SESSION_HISTORY should be used or the historic information from DBA_HIST_ACTIVE_SESS_HISTORY (HIST)
--
--               This also means that the CURRent configuration will use the Library Cache to get the plan (DBMS_XPLAN.DISPLAY_CURSOR), but the HIST configuration will use DBMS_XPLAN.DISPLAY_AWR to obtain the execution plan
--
--               There is also a configuration for taking the plan from AWR (DBMS_XPLAN.DISPLAY_AWR) but taking the sample data from current ASH (GV$ACTIVE_SESSION_HISTORY): MIXED
--
--               Note that you can abbreviate this option (e.g. a or A for AUTO, cu for CURR etc.)
--
--               Parameter 5:
--
--               Allows to enable/disable the EXPERIMENTAL stuff (see below for a detailed description)
--               Default is don't show EXPERIMENTAL (OFF), specify ON to have it shown
--
--               Note that you can abbreviate this option (e.g. y for YES)
--
--               Parameter 6:
--
--               For 11g+:
--               MONITOR or ASH: Determines where to search for the last execution. By default the script uses ASH.
--
--               This is only applicable if no SQL_EXEC_START / SQL_EXEC_ID is specified, or no SQL_ID at all (or a SID is specified in Parameter 1 and ASH should be used according to Parameter 7, see next argument)
--
--               Note that the scripts queries both GV$SQL_MONITOR and GV$ACTIVE_SESSION_HISTORY to determine the last execution if no SQL_EXEC_START / SQL_EXEC_ID was specified
--
--               !! If you don't have a Tuning Pack license but haven't disabled it in the CONTROL_MANAGEMENT_PACK_ACCESS parameter this query might show up as a Tuning Pack feature usage !!
--
--               Note that you can abbreviate this option (e.g. m for MONITOR)
--
--               Parameter 7:
--
--               The next argument allows specifying if ASH activity, Parallel Distribution and/or Activity Timeline information as well as Real-Time SQL Monitoring info on execution plan line level should be displayed:
--
--               [[*ASH*|LIMITED_ASH][,][*DISTRIB*][,][*MONITOR*][,][*TIMELINE*]|[NONE]]
--
--               Use the LIMITED_ASH option to avoid long running XPLAN_ASH queries when analyzing long rung statements - usually only required when the session lacks the ALTER SESSION privilege
--               This will avoid the two sections that take most of the time, see below
--
--               Note that you can abbreviate this option (e.g. a,d,t for ASH,DISTRIB,TIMELINE)
--
--               The following sections of the output will always be shown if any of options ASH, DISTRIB or TIMELINE is specified:
--               - SQL statement execution ASH Summary
--               - SQL statement execution ASH Summary per Instance (if Cross Instance Parallel Execution is detected)
--               - Activity on execution plan line level (Enterprise Edition + Diagnostics Pack + 11g+)
--
--               ASH specific output:
--               - Summary of this session's other activity
--               - Other activity details
--               - Global ASH Summary for concurrent activity         ==> skipped in case of the LIMITED_ASH option
--               - Concurrent Activity Summary (not this execution)
--               - Concurrent activity top SQL_IDs                    ==> skipped in case of the LIMITED_ASH option
--               - SQL Statement I/O Summary based on ASH (only if Experimental mode enabled and 11.2+)
--               - SQL Statement I/O Summary per Instance based on ASH (only if Cross Instance Parallel Execution is detected and Experimental mode enabled and 11.2+)
--               - Activity Class Summary
--               - Activity Class Summary per Instance (if Cross Instance Parallel Execution is detected)
--               - Activity Summary
--               - Activity Summary per Instance (if Cross Instance Parallel Execution is detected)
--
--               DISTRIB specific output:
--               - Information on Parallel Degree based on ASH (only if execution plan is available)
--               - Parallel Worker activity overview based on ASH (only if Parallel Execution is detected)
--               - Activity Timeline based on ASH (both DISTRIB or TIMELINE)
--
--               TIMELINE specific output:
--               - Activity Timeline based on ASH (both DISTRIB or TIMELINE)
--
--               MONITOR specific output:
--               - Real-Time SQL Monitoring Execution Summary
--               - Actual bind values from Real-Time SQL Monitoring
--
--               The options specified also determine the additional columns available on execution plan line level:
--
--               ASH        : Show "Act", "Activity Graph ASH" and "Top N Activity ASH" columns per SQL plan line id (default)
--
--               DISTRIB    : Show Parallel Distribution info based on ASH: Top N Parallel Processes, Parallel Distribution Graph and Average/Median Active Sessions Graphs per SQL plan line id
--
--               TIMELINE   : Show the Start Active, Duration and Time Active Graph columns based on ASH data (default)
--
--               MONITOR    : Show the "Execs", "A-Rows", "CellO%", "PGA", "TEMP", "Reads", "Writes" (the latter four in bytes) columns. These are taken from Real-Time SQL Monitoring info if available
--
--               NONE       : Do nothing of above (for example if you only want the Rowsource Statistics information)
--
--               Note that Parameter 10 allows finer control over which columns should be shown on execution plan line level
--
--               Parameter 9:
--
--               The default formatting option for the call to DBMS_XPLAN.DISPLAY_CURSOR / AWR is TYPICAL +OUTLINE +ALIAS +PEEKED_BINDS
--
--               For the special Rowsource Statistics mode 3 ("_rowsource_statistics_sampfreq" = 3) where only actual cardinalities are measured, XPLAN_ASH from version 3.0 on supports a special FORMAT option:
--
--               AROWS
--
--               This adds a column "A-Rows" (similar to what DISPLAY_CURSOR does when using the *STATS formatting option) since DISPLAY_CURSOR doesn't support this mode properly
--               - it doesn't show the A-Rows in that case although the columns are populated in GV$SQL_PLAN_STATISTICS_ALL
--
--               Note that you usually want to use "AROWS LAST" similar to "ALLSTATS LAST" if you want to see the actual cardinalities of the last execution.
--
--               Parameter 10:
--
--               Defines the column list to show on execution plan line level. Use a comma-separated list of columns with no whitespace inbetween.
--               The available list of columns can be found below in the configuration section.
--
--               Alternatively you can also specify which columns *not* to show by using a minus sign in front of the column names
--
--               Since version 4.0 there is a new option to the column list parameter: Column names can be preceded with a + sign, which means that these columns will be shown
--               in addition to the default column list, for example "+MAS_GRF" would show the median active sessions column in addition to the default columns on execution plan line level
--
--               The default is to show all columns that are configured in the configuration sections of the script (by default all columns except "average active sessions (active)" and "median active sessions")
--
-- Note:         You need a veeery wide terminal setting for this if you want to make use of all available columns on execution plan line level (e.g. format option ALLSTATS ALL), something like linesize 700 should suffice
--
--               Some ideas how you can handle these long lines:
--
--               - If you're on Windows the CMD.EXE does a good job - just set the "Width" in "Screen Buffer Size" under "Properties" to 700 and you should be fine. The columnar selection of CMD.EXE is also helpful for tracking
--                 the long lines, for example if you are on the right hand side of the execution plan output and want to see which operations belong to that, just highlight the line and while highlighting move to the left
--
--                 So the easiest way to handle the long lines is to use SQLPLUS.EXE from a Windows client under CMD.EXE to connect to the target database and run XPLAN_ASH
--
--               - PuTTy and most other terminal emulators don't offer horizontal scrolling, so under Unix/Linux things are bit more complicated
--
--                 - Again under Windows you could use Cygwin (32bit) and run the "Bash shell" under the CMD.EXE interface, so you can follow above "Properties" settings and you should be fine.
--                   You could use then command line SSH instead of PuTTy to benefit from that interface on remote SSH sessions
--
--                 - "Terminator" (https://code.google.com/p/jessies/wiki/Terminator) is one of the few terminal emulators that offers horizontal scrolling. Since it offers some other cool features and is free, why not give it a try?
--
--                 - If you need to handle long lines when using a terminal emulator/interface not capable of horizontal scrolling, you can make use of the following tips:
--
--                   - Since version 4 of XPLAN_ASH you can spool the output to a file using the SQLPLUS SPOOL command. Starting with version 4.1 XPLAN_ASH itself does a SET TRIMSPOOL ON, in version 4.0(1) you should do that yourself, although not required
--                     The spooled file can the be transferred to a machine where you can handle long lines, or be opened with some text editor capable of handling long lines on the target machine
--
--                   - If the Unix LESS command is available - use LESS -S to handle long lines. You can use the cursor keys to scroll to left / right in that mode
--
--                   - You could also do some fancy Unix stuff, for example copy the SQLPLUS terminal output via TEE to a file, and open the file using LESS -S +F in another session.
--                     Running LESS in that mode allows switching between scroll right/left mode using cursor keys and tailing the file via Control+C / Shift+F
--
--               This tool is free but comes with no warranty at all - use at your own risk
--
--               The official blog post for version 1.0 of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2012/08/parallel-execution-analysis-using-ash.html
--
--               It contains a complete description along with the command line reference, notes and examples
--
--               The official blog post for version 2.0 of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2012/10/new-version-of-xplanash-utility.html
--
--               It explains all the new sections and features of 2.0
--
--               The official blog post for version 3.0 of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2013/05/new-version-of-xplanash-tool-video.html
--
--               It includes links to a multi-part video tutorial explaining version 3.0
--
--               The official blog post for version 4.0 of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2013/12/new-version-of-xplanash-utility.html
--
--               It includes a link to a video tutorial explaining the new features of version 4.0
--
--               You can find all related posts following this link:
--               http://oracle-randolf.blogspot.com/search/label/XPLAN_ASH
--
--               The latest version can be downloaded here:
--               https://github.com/randolfgeist/oracle_scripts/raw/master/xplan_ash.sql
--
-- Experimental: There is a global switch _EXPERIMENTAL at the beginning of the configuration section below.
--               By default this is disabled because the stuff shown could be called "unreliable" and potentially "misleading" information.
--
--               From version 3.0 on this can be now controlled via an additional command line parameter specifying one of (ON, TRUE, YES) should do the job of enabling it
--
--               If you enable it (either by setting the configuration switch to an empty string or via command line), the I/O figures from the ASH data (only from 11.2+ on)
--               will be shown at various places of the report. Note that this data is unreliable and usually falls short of
--               the actual activity (I've never seen it reporting more than the actual activities). Since sometimes unreliable
--               figures can be much better than nothing at all you can enable it that in cases where you want for example get an
--               idea if the I/O was in the range of MBs or GBs - this is something you should be able to tell from the ASH data.
--
--               Note that from version 11.2.0.3 on the I/O figures are shown by default since it looks like the data got more reliable with that release
--               You'll still see missing data for short running queries but for longer running queries the data seems to be pretty accurate
--
--               Likewise the average and median wait times from ASH will be shown at different places of the report if experimental is turned on.
--               It is important to understand what these wait times are: These are waits that were "in-flight", not completed when the sampling took place.
--               Doing statistical analysis based on such sampled, in-flight wait times is sometimes called "Bad ASH math", but again, if you know what you are doing
--               and keep telling yourself what you're looking at, there might be cases where this information could be useful, for example, if you see that
--               hundreds or thousands of those "in-flight" waits were sampled with a typical wait time of 0.5 secs where you expect a typical wait time of 0.005 secs.
--               This might be a good indication that something was broken or went wrong and could be worth further investigation.
--
-- Change Log:
--
--               4.1:  June 2014
--                    - GV$SQL_MONITOR and GV$SQL_PLAN_MONITOR can now be customized in the settings as table names in case you want to use your own custom monitoring repository that copies data
--                      from GV$SQL_MONITOR and GV$SQL_PLAN_MONITOR in order to keep/persist monitoring data. The tables need to have at least those columns that are used by XPLAN_ASH from the original views
--
--                    - The "Activity Timeline based on ASH" for RAC Cross Instance Parallel Execution shows an additional line break for the GLOBAL summary
--
--                    - Fixed various bugs related to some figures when analyzing Cross Instance RAC Parallel Execution
--
--                    - The new "GLOBAL" aggregation level for Cross Instance RAC Parallel Execution (see version 4.0 change log below) is now also shown in the "Information on Parallel Degree based on ASH" section
--
--                    - The "Parallel Distribution ASH" column on execution plan line level now can show process information taken from Real-Time SQL Monitoring for those processes that are not found in ASH samples
--                      This effectively means that with monitoring information available for every plan line every involved process will now be shown along with its ASH sample count and rows produced
--                      So some processes will show up now with a sample count of 0.
--                      The idea behind this is to provide more information about row distribution even for those lines/processes that are not covered in the ASH samples
--                      Previously the rowcount produced was only shown for those processes covered in ASH samples
--                      See above section "Row distribution for Parallel Execution" for more details
--
--                      The new behaviour is default - if you find the output messy you can return to previous behaviour (show only rowcounts for processes found in ASH samples) by setting the new configuration switch
--                      "show_monitor_rowcount" to any other value than the default of "YES"
--
--                    - The "Real-Time SQL Monitoring" information on execution plan line level now includes the read and write request information ("ReadReq", "WriteReq")
--
--                    - The I/O figures based on ASH now include the new "DELTA_READ_MEM_BYTES" information that was added in 12c. This applies to the following sections:
--                      - SQL Statement I/O Summary based on ASH
--                      - Parallel Worker activity overview based on ASH
--                      - Activity Timeline based on ASH
--
--                      The "Read Mem Bytes" seems to correspond to the "logical read bytes from cache" statistics, so any direct path reads are not covered by this value
--
--                    - Added some more verbose description above in the "Note" sections how to handle long lines. XPLAN_ASH now does a SET TRIMSPOOL ON if you want to spool the output to a file
--
--                    - Whenever the output referred to DFOs this was changed to "DFO TREE", which is the correct term
--
--                    - The "Parallel Worker activity overview based on ASH" section now shows a blank line between the sections which should make this section more readable
--
--                    - Adaptive plans are now supported by XPLAN_ASH
--
--                      Note they don't work well with previous versions, the formatting of the inactive lines breaks and the overall information can
--                      be misleading if you don't add manually the "ADAPTIVE" formatting option
--
--                      If XPLAN_ASH detects an adaptive plan, it will always force the ADAPTIVE formatting option
--                      This also means that Adaptive plans for the time being won't work with SASH as SASH doesn't collect the OTHER_XML column from GV$SQL_PLAN
--                      You could manually add that column to SASH_SQLPLANS and add the column to the "sash_pkg.get_sqlplans" procedure - this is a CLOB column, but INSERT / SELECT should work I think
--                      The view SASH_PLAN_TABLE needs also to be modified to select the OTHER_XML column instead of a dummy NULL
--
--                      Although this output is less readable than the "faked" output that shows only the plan operations that are actually in use,
--                      it is the only simple way how ASH/MONITOR data can be related to execution plan lines, as these hold the information with the actual plan line
--                      not the one that is made up by DBMS_XPLAN.DISPLAY* based on the DISPLAY_MAP information in the OTHER_XML column
--
--                      Hence I decided for the time being to use the same approach as 12c Real-Time SQL Monitoring and always show the full/adaptive shape of the plan
--
--                      Another challenge for XPLAN_ASH with adaptive plans is the possibly changing PLAN_HASH_VALUE during execution
--
--                      XPLAN_ASH extracts the PLAN_HASH_VALUE from ASH/MONITOR when trying to get the plan from DBA_HIST_SQL_PLAN
--
--                      Hence XPLAN_ASH now needs to take care to extract the most recent PLAN_HASH_VALUE, previously it didn't matter as it wasn't supposed to change during execution
--                      This seems to work based on my tests, but it's something to keep in mind
--
--                    - The new "gather stats on load" 12c feature implies for INSERT...SELECT statements that the cursor will immediately be invalidated/removed from the Library Cache
--                      after (successful) execution. So now such INSERT...SELECT behave like CTAS which also gets removed immediately. This is a pity as you won't be able to pick up
--                      the plan from the Library Cache after the execution completes using XPLAN_ASH (or any other tool using DBMS_XPLAN.DISPLAY*).
--
--                      Although V$SQL_PLAN_MONITOR might keep plan for some time after the execution, it can't be used as input to DBMS_XPLAN.DISPLAY*, hence this isn't a viable workaround
--                      In principle however this isn't a good thing as the SQL and plan information might be missing from AWR / STATSPACK reports due to the immediate invalidation/removal
--
--                      At the time being the only viable workaround known to me for this is to prevent the "gather stats on load" feature either via parameter "_optimizer_gather_stats_on_load"
--                      or hint "no_gather_optimizer_statistics", or via using pre-12c optimizer feature settings which implicitly disables the feature
--                      which is of course not really a good workaround as the feature itself might be rather desirable
--
--
--               4.01: March 2014
--                    - More info for RAC Cross Instance Parallel Execution: Many sections now show a GLOBAL aggregate info in addition to instance-specific data
--
--                    - The Parallel Execution Server Set detection and ASSUMED_DEGREE info now makes use of the undocumented PX_STEP_ID and PX_STEPS_ARG info (bit mask part of the PX_FLAGS column)
--                      on 11.2.0.2+
--
--                    - Since version 4.0 added from 11.2.0.2 on the PX *MAX* DOP in the "SQL statement execution ASH Summary" based on new PX_FLAGS column of ASH
--                      it makes sense to add a PX *MIN* DOP in the summary to see at one glance if different DOPs were used or not
--
--                    - The "Active DOPs" column in the "Activity Timeline based on ASH" was extended/modified: The number in parantheses is no longer the simple count of samples
--                      but the Average Active Sessions (AAS) per DFO / bucket. From 11.2.0.2 it now shows also the DOP of the DFO in brackets, so the output could look now like this:
--
--                      1[16] (14.5)
--
--                      which means DFO 1 at a DOP of 16 had an AAS value of 14.5 for this time bucket. If there are multiple DFOs active in the time bucket, they are separated by commas:
--
--
--                      1[16] (3.5),2[4] (1.5)
--
--                      which means DFO 1 at a DOP of 16 had an AAS value of 3.5 and DFO 2 at a DOP of 4 had an AAS value of 1.5 for this time bucket
--
--                    - The "Real-Time SQL Monitoring Execution Summary" section now shows a PX *MIN* DOP information, too, based on the monitoring information.
--                      Note that from version 11.2 on there is a column PX_MAXDOP, but no PX_MINDOP column. So from version 11.2 on for PX_MAXDOP the column value will be used.
--                      For pre-11.2 versions the PX_MAXDOP is calculated using an analytic function on the monitoring data
--                      In the same way the PX_MINDOP information is now calculated in all versions that support monitoring
--
--                      Please note that both PX_MAXDOP and PX_MINDOP can be unreliable in 11.1 when the execution plan consists of multiple DFOs
--                      I just realized that my wording might be misleading - "DFOs" are probably better called "DFO trees" - so please consider "DFO trees" whenever reading "DFOs" here
--
--               4.0:  December 2013
--                    - New MIN/MAX figures when showing I/O related analysis. Useful if you want to see peak throughput information (e.g. Exadata)
--
--                    - Determining the start time of the script execution was changed. The previous implementation lead to misleading results when the execution of the initialization steps
--                      took extraordinarily long
--
--                    - The version specific code switches were actually not working correctly with version 12. This is fixed now
--
--                    - The different DISTRIB* parameters are all now deprecated. There is a common handling of the Parallel Distribution Graph based on the former DISTRIB_TIM option
--                      The Graph now is turned into a simple "indicator" that hopefully gives a reasonable indication how much that execution plan line is affected by skew of any kind
--                      Note that this now includes temporal skew - you no longer need to check the Average/Median Active Sessions on execution plan line level for that
--
--                      For the same reason the column on execution plan line level is now called "Parallel Execution Skew ASH" instead of "Parallel Distribution Graph ASH"
--
--                    - The command line parameters were reordered: All ASH related parameters come now first, all Rowsource Statistics related come last
--
--                    - The default formatting for DBMS_XPLAN was changed to "TYPICAL +OUTLINE +ALIAS +PEEKED_BINDS"
--
--                    - The default date formatting mask was changed to have no spaces so that the date literals can be typed at the command line without the need to add double quotes around
--
--                    - New ASH sections for activities of the current session that are not related to the SQL_ID analyzed but happen during first sample to last sample of the given SQL_ID
--                      - Summary of this session's other activity
--                      - Other activity details
--                      This should cover recursive SQL activity (typically issued by user-defined PL/SQL functions called as part of SQL execution, but could also be SYS recursive stuff)
--                      But could also be caused by multiple open cursors of the session, executing/fetching from one or the other
--
--                    - New "Top N SQL_IDs" ASH section for concurrent activity
--
--                      This section shows the SQL text (if available) along with some more details about the top N SQL_IDs found (according to sample count)
--
--                      The N can be configured in the configuration section: "topn_sqlid"
--
--                      This section requires to query either GV$SQLSTATS resp. DBA_HIST_SQLTEXT to obtain the SQL text
--
--                    - The Median Active Sessions is now available in addition to the Average (Mean) Active Sessions indicator
--                      If these two differ significantly then you should carefully check the analysis as it might indicate that the Mean is misleading
--                      Note that there are still cases where both don't clearly indicate a problem with Parallel Execution Skew
--
--                      Median usually shows the "typical" active sessions and therefore is often more useful than the arithmetic Mean
--
--                    - There are new columns available in the ASH sections that report the percentage of Ys in the following columns of ASH data (only available from 11g on):
--                      IS_SQLID_CURRENT      Only available from 11.2 on. Can be used as an additional indicator how much activity was caused by some action not related to the current SQL_ID. See also new "other activity" sections
--
--                      IN_CONNECTION_MGMT    These columns can be used as some kind of TIME_MODEL information, however they don't need to add up to 100%
--                      IN_PARSE              Each of them could theoretically reach 100%
--                      IN_HARD_PARSE
--                      IN_SQL_EXECUTION
--                      IN_PLSQL_EXECUTION
--                      IN_PLSQL_RPC
--                      IN_PLSQL_COMPILATION
--                      IN_JAVA_EXECUTION
--                      IN_BIND
--                      IN_CURSOR_CLOSE
--                      IN_SEQUENCE_LOAD      This column is only available from 11.2 on
--
--                    - The "Information on Parallel Degree based on ASH" section now tries to group the processes by DFO and SET_ID (from 11g on if execution plan is available)
--                      Since the SET_ID information is not directly available from ASH data it is a rather obscure way of determining the sets and therefore can be wrong.
--                      If XPLAN_ASH identifies more than two sets in the ASH data (which isn't possible) those samples will show up in the *NULL* SET_ID section.
--
--                      Furthermore if ASH samples do not contain a relation an execution plan line ID, they will be shown as separate group with NULL DFO / SET_ID
--
--                      This feature can be disabled via the switch "show_px_sets" in the configuration section
--
--                    - Some columns that have been added, particularly the MEDIAN Active Sessions related info, is hidden since it only adds value at some places
--
--                      If you want to have them shown, you can change the configuration switch "show_median" to blank "", the default is "NO" and is used as a NOPRINT column formatting
--
--                    - The default column shown on execution plan line level are no longer "all columns" for the same reason -
--                      the average active sessions (active), average active sessions (total) and median active sessions columns are not shown by default
--
--                      The reason for that is that the new logic to calculate the "Parallel Distribution Graph ASH" should now cover all "skew" cases, data distribution and temporal skew
--                      Hence these columns should no longer be required to troubleshoot temporal skew (which was their main purpose in the past)
--
--                      There is therefore a new option to the column list parameter: column names can be preceded with a + sign, which means that these columns will be shown
--                      in addition to the default column list, for example "+MAS_GRF" would show the median active sessions column in addition to the default columns on execution plan line level
--
--                    - For some parameters abbreviations are now supported, for example instead of typing HIST at the ASH SOURCE parameter, just "h" is sufficient
--
--                      This appplies to Parameters 4 (ASH SOURCE), 5 (Experimental), 6 (Search last exec) and 7 (ASH Options)
--
--                    - The ASH Source parameter now supports an AUTO option. This automatically deteremines whether to use the current ASH or historic ASH configuration
--                      Note that this only works when Parameter 2 (SQL_EXEC_START) is explicitly specified, otherwise AUTO is the same as CURR, so the last execution
--                      will be searched by default using the CURRent ASH configuration set. The default can be changed in the script configuration using the "default_ash" parameter
--                      (if you for example have added another configuration set that should be used by default), and when explicitly specifying a configuration set
--                      then the AUTO selection doesn't apply.
--
--                      AUTO queries V$ASH_INFO (available from 11.2 on) or the local V$ACTIVE_SESSION_HISTORY (more costly) for the oldest sample available and compares that to the SQL_EXEC_START specified
--
--                    - Finally Real-Time SQL Monitoring info on execution plan line level is now supported. There are seven new columns that are taken from the monitoring info:
--
--                      Execs (number of executions of that plan line), A-Rows (Actual output rows, cardinality), CellO% (Cell Offload Percentage if applicable) PGA, TEMP, Reads and Writes. The latter four are in bytes
--
--                      The column "Parallel Distribution ASH" will have also the Rowcount per Parallel Execution Server added if monitoring info gets used and is available.
--                      The Rowcount is added in square brackets to the process, after the number of samples in paranthesis, something like this:
--
--                      P012(44)[183K]
--
--                      This means process P012 was sampled 44 times for this execution plan line and produced 183K rows according to Real-Time SQL Monitoring
--
--                      Note that this information is crucial in understanding Data Distribution Skew and not available from the official Real-Time SQL Monitoring report up to 11.2
--                      12c SQL Monitoring allows to extract this information via the report
--
--                      Whether monitoring info will be shown depends obviously on the version (from 11g on) and availability of such information.
--                      Furthermore this can be controlled via the ASH options - the MONITOR keyword enables this features
--                      Finally as usual the columns shown on execution plan line level can be configured via the columns configuration
--
--                    - XPLAN_ASH now tries different optional date masks for SQL_EXEC_START / END if the default mask doesn't work, this is just to simplify copy&pasting of dates
--                      The list of optional date masks can be found in the configuration parameters "dm_opt1" and "dm_opt2". Feel free to add your favorite date masks there
--
--                    - If SQL_EXEC_START was specified but SQL_EXEC_ID is left blank and version is 11g+, then a default SQL_EXEC_ID of 16777216 will be used
--                      This default SQL_EXEC_ID can be changed - if you have a RAC environment with multiple instances this might make sense to change (configuration parameter "default_sql_exec_id")
--
--                    - The queries now make use of the (up to 11.2 undocumented, from 12c on documented) LATERAL views - this is to get rid of the inefficient range joins that could cause some of the
--                      queries to run for minutes if larger time frames are observed
--                      The downside of this is that it now makes use of (yet another) undocumented feature
--
--                      The script automatically detects if the session lacks the ALTER SESSION privilege and falls back to a different code path.
--                      This is because LATERAL views require to enable an undocumented event.
--                      This code path is now optimized, too, and no longer uses the inefficient joins used in version 3.
--                      It uses now a MERGE JOIN that performs an efficient index-like lookup into the second row source.
--                      It performs probably worse than the LATERAL view variant but should still be much more efficient than before
--
--                    - There is a new option LIMITED_ASH that skips the two ASH related sections that can take very long when analyzing long running queries
--                      When the LATERAL query variant can be used (ALTER SESSION privilege) this is usually not required
--
--                    - A "Real-Time SQL Monitoring Execution Summary" section was added that shows a summary similar to the header of the official reports
--
--                      This shows only up if that information is requested, available and version 11g+
--
--                    - Another new section has been added: "Actual bind values from Real-Time SQL Monitoring"
--                      This only available if:
--
--                      * Real-Time SQL Monitoring info is available
--                      * Real-Time SQL Monitoring info requested (ASH options includes MONITOR)
--                      * 11.2+
--
--                      These are the bind variable values used for this particular execution - not to confuse with the "Peeked Binds" that are shown by DBMS_XPLAN and are those bind variables values
--                      the optimizer peeked at / saw when generating the execution plan
--
--                    - In 11g the wait event "PX Deq Credit: send blkd" was turned into an "idle" wait event, which isn't entirely true. But for consistency purposes from version 4.0
--                      in 10g this wait event is handled as "idle" event, too. This can be configured using the "ignore_PX_credit_blkd_10g" configuration switch
--
--                    - In the special case of executing the same SQL_ID multiple times and having multiple of these executions active in turns (e.g. fetching from multiple open cursors by the same session)
--                      the implementation now correctly distinguishes between these different executions - these other executions should now show up in the "Other" activity sections
--                      This is only possible from 11g on with the help of SQL_EXEC_START / SQL_EXEC_ID
--
--                    - The calculation of the so called "virtual timeline" is now simplified and gives more consistent results for sample frequencies > 1s (e.g. DBA_HIST_ACTIVE_SESS_HISTORY)
--                      With the prior implementation it could happen that for example a spurious "last bucket" with no related activity showed up in the "Activity Timeline"
--
--                    - There was an inconsistency with how the different sample times in RAC environments were handled which could lead to incorrect results for some of the measures.
--                      This was only relevant with sample frequencies > 1s (e.g. DBA_HIST_ACTIVE_SESS_HISTORY). This is now fixed and handled consistently.
--
--                    - In the SQL Execution Summary there are four new columns related to PX SEND / RECEIVE activity - only available from 11g on with Diagnostics Pack license.
--                      The idea of these columns is to give an idea how much database time and CPU time went into the overhead of re-distributing the data with Parallel Execution
--                      When having many joins and re-distributions the overhead can become significant. Note that in the special case of applying CPU intensive expressions / functions
--                      to the columns/expressions used for re-distributing the evaluation of those expressions/functions will take place at the corresponding PX SEND operation (except for BROADCAST distributions).
--                      This means that you'll very likely end up with a lot of CPU activity shown with these PX SEND operations, but this isn't really overhead, as serial execution
--                      would have to evaluate the same CPU intensive expressions as part of serial operation
--
--                      These columns are called
--                        "PX SEND/RECEIVE COUNT"       The number of samples related to PX SEND/RECEIVE operations
--                        "PX SEND/RECEIVE PERCENT"     The same as percentage of the total number of samples
--                        "PX SEND/RECEIVE CPU COUNT"   The number of samples related to PX SEND/RECEIVE operations that were on CPU
--                        "PX SEND/RECEIVE CPU PERCENT" The same as percentage of the total number of *CPU* samples
--
--                    - There are now two columns "PX WORKER COUNT" and "PX WORKER UNIQUE COUNT": The first (PX WORKER COUNT) is the number of different Parallel Execution Server (Pxxx) processes found in the ASH samples
--                      The second one (PX WORKER UNIQUE COUNT) combines the process identifier (Pxxx) with the SESSION_ID and SESSION_SERIAL# - if DFOs are started multiple times, the PX Servers are re-acquired / re-initialized each time
--                      This can be seen from getting different SESSION identifiers for the same Pxxx processes, and allows getting an idea about the frequency of those re-acquisitions
--                      For DFOs started only once, PX WORKER UNIQUE COUNT should be equal to the PX WORKER COUNT
--
--                      The columns PROCESS COUNT and PROCESS UNIQUE COUNT are pretty much the same, but may include the Query Coordinator process, hence they are not called PX WORKER only
--
--                    - The columns DURATION_SECS_T / DURATION_T / DURATION_SECS / DURATION / AVERAGE_AS_T / AVERAGE_AS now have more meaningful headings
--                         "DURATION SECS TOTAL"
--                         "DURATION TOTAL"
--                         "DURATION SECS ACTIVE"
--                         "DURATION ACTIVE"
--                         "AVERAGE AS TOTAL"
--                         "AVERAGE AS ACTIVE"
--
--                    - From 11g on the TOP_LEVEL_SQL_ID will be shown at different places: In the "SQL Execution Summary", the "Other activities details" and the "Concurrent activity top SQL_IDs"
--
--                    - For those interested the Standard Deviation for the Average Active Sessions calculation is also shown as STDDEV_AS at various places
--
--                    - From 11.2.0.2 on the PX *MAX* DOP will be shown in the "SQL statement execution ASH Summary" as found in the new PX_FLAGS column of ASH
--
--                    - If Parallel Execution is detected and an execution plan can be found the "Activity Timeline based on ASH" shows an additional "Active DFO(s)" column
--                      so that you can follow the activity of DFOs - in particular helpful for parallel execution plans with multiple DFOs
--
--                    - The internal queries are now by default all set to "quiet" mode so that the output of XPLAN_ASH can be spooled to a file
--                      You will still see some spurious blank lines but the output is much more useful than in previous releases
--                      Use the settings "debug_internalp" and "debug_internalf" to control the output of the internal queries for debugging
--
--
--               3.01: May 2013
--                    - Some column widths increased and cosmetics changed for some recently renamed headers
--
--               3.0: March 2013
--                    - The "Active" plan lines indicator sometimes was missing for still running statements (same problem as for the "ACTIVE"/"INACTIVE" indicator fixed in 2.02)
--                    - The PGA/TEMP figures (available from 11.2 on) in the "Activity Timeline" are now "smoothened" for Parallel Execution using some artificially generated rows
--                      (based on the new DELTA_TIME column) for missing samples of PX Workers
--                    - All byte related numbers are now formatted using KiB/MiB etc. (base of 2) rather than to the base of 10, so 1M bytes correspond now to 1048576 bytes etc.
--                    - Average Active Sessions calculations are now based on MIN(SAMPLE_TIME) instead of SQL_EXEC_START for those cases where execution start is prior to first ASH sample
--                    - The "Activity Timeline" query now uses a common approach for historic and current ASH data, also an inconsistency how data was grouped by buckets was addressed
--                      These changes were required due to the introduction of the artificial PGA/TEMP rows as mentioned above
--                    - The "SQL statement execution ASH Summary" now includes the MACHINE (from 11.2 on) and (Coordinator) session / instance identified
--                    - The Graphs used for Extended Rowsource Statistics (A-Time Self Graph, LIO Self Graph, Reads Self Graph and Writes Self Graph) also scale now relative to the MAXimum
--                      rather than the total which makes the graph hopefully a bit more useful (can be configured via "ext_rowsource_graphs_maxrel" in configuration section)
--                    - Initial support for S-ASH (tested with version 2.3, but this requires some minor modifications to the current S-ASH 2.3 version, modifications can be provided on request)
--                      The script automatically detects if it is executed in the S-ASH repository owner by checking for a configured target in the SASH_TARGET table
--                    - The Extended Rowsource Statistics now get also pulled from the correct (remote) node in case of RAC and 11.2.0.2+
--                    - Improved "Average Active Sessions" calculation - the graph is now scaled if AAS is larger than the defined size
--                    - Improved "Parallel Distribution Graph" calculation, new option DISTRIB_TIM hopefully now reflects properly the relevance of skewed work distribution per execution plan line
--                    - From 11.2 on MAX PGA/TEMP usage on different summary levels (Global/Instance/Concurrent activity)
--                    - Improved "Time Active Graph" calculation on DFO and execution plan line level
--                    - New "Average Active Sessions Graph" on execution plan line level that should make it more obvious which execution plan lines are affected by Parallel Execution distribution skew
--                      This should now also allow to identify temporal skew where only a few Parallel Workers are active at the same time but at the end do a similar amount of work
--                    - Experimental stuff can be controlled via the command line
--                    - The graphs now consistently indicate CPU, non-CPU and general activity, and a corresponding legend was added to the header output
--                    - The good, old Rowsource statistics have been polished to have now percentages shown, too
--                    - The "Ord" column on execution plan line level (Order of execution) by default will not be shown when Parallel Execution gets detected.
--                      This is because it will be wrong in many cases except for the most trivial Parallel Execution execution plans.
--                      I haven't found the time yet to come up with a more sensible implementation that:
--                      - Covers the special cases (the "Ord" column can also be wrong for serial execution if these special cases apply)
--                      - Covers the case of Parallel Execution where the order of execution usually doesn't correspond to the serial execution order
--                        Hint: Follow the TQ entries in increasing order
--
--                        I've decided to keep it for serial execution as it is correct there for the majority of cases (but watch out for those special cases)
--                        Hiding it when Parallel Execution is detected can be controlled via the configuration switch "no_ord_on_px"
--
--                    - The logic how the script gathers information if no SQL_ID is specified as first argument is now more consistent when using the ASH based options. Instead of getting the SQL_ID information from GV$SESSION
--                      for the current or explicitly given SID, it queries now either Active Session History (ASH option) or Real-Time SQL Monitoring (MONITOR option) for the last SQL_ID mentioned there
--                      for that session.
--                      This probably makes more sense as it automatically selects those queries that are available from ASH/MONITORing and hence worth to analyze rather than taking strictly the most recent execution
--                      from GV$SESSION.
--                      It also means that the ASH/MONITOR parameter acts now consistently for all possible inputs for the first parameter (SQL_ID, SID, nothing at all).
--                      Prior to this change that ASH/MONITOR option was only relevant when specifying a SQL_ID without SQL_EXEC_START / SQL_EXEC_ID
--
--                      Note that if no ASH options are selected (specifying NONE at the ASH,DISTRIB,TIMELINE default parameter) then the SQL_ID related information is still taken from GV$SESSION
--
--                      - There are now two Average Active Sessions figures, AVERAGE_AS and AVERAGE_AS_T.
--                        AVERAGE_AS is the Average Active Sessions across all ASH samples where there was at least one sample
--                        AVERAGE_AS_T is the Average Active Sessions across the time the corresponding part was active (from first sample to last sample on statement level, instance level, DFO level, execution plan line level)
--                        If AVERAGE_AS_T is significantly lower than AVERAGE_AS this means that the affected part was idle for a significant amount of time during execution
--                        AVERAGE_AS_T should never be higher than AVERAGE_AS
--
--                      - Likewise there is now also a DURATION_SECS and DURATION_SECS_T
--                        DURATION_SECS is the number of seconds actually active
--                        DURATION_SECS_T is the number of seconds from first sample (SQL_EXEC_START) to last sample
--                        If there is a significant difference then there was some idle time in between
--
--                      - The DURATION_SECS and DURATION_SECS_T are now also displayed as INTERVAL for better human readability in case of long running queries
--
--                      - For the special Rowsource Statistics mode 3 ("_rowsource_statistics_sampfreq" = 3) where only actual cardinalities are measured, XPLAN_ASH from version 3.0 on supports a special FORMAT option "AROWS".
--                        This adds a column "A-Rows" (similar to what DISPLAY_CURSOR does when using the *STATS formatting option) since DISPLAY_CURSOR doesn't support this mode properly
--                        - it doesn't show the A-Rows in that case although the columns are populated in GV$SQL_PLAN_STATISTICS_ALL
--                        Note that you usually want to use "AROWS LAST" similar to "ALLSTATS LAST" if you want to see the actual cardinalities of the last execution
--
--               2.03: January 2013
--                    - The Activity Graph in "Parallel Worker Activity" now differentiates between "CPU" and "Other" activity
--                      Furthermore it is scaled now relative to the MAXimum count rather than relative to total activity so that differences in sample count show up more clearly
--                    - The "Top N Activity ASH" Activity Graph on execution plan line level is now also relative to the MAX activity, no longer relative to the total activity, for the same reason
--                    - Some inconsistencies in ASHs SQL_EXEC_START column addressed - It no longer uses simply the MIN SQL_EXEC_START found but the most occurring one among the set identified
--                      There were some inconsistent entries encountered in 11.2.0.x ASH data
--
--               2.02: October 2012
--                    - Running the script on 10g is more sensitive how the session information is populated in the ASH data
--                      Therefore the query to define the session predicates was modified
--                    - The INACTIVE / ACTIVE indicator in the "Global ASH summary" was sometimes incorrectly showing "INACTIVE" status although the statement was still running
--
--               2.01: October 2012
--                    - The NONE option did not populate a substitution variable properly that is required from 11.2.0.2 on
--                      for running the DBMS_XPLAN function on the target node via the GV$() function
--
--               2.0: October 2012
--                    - Access check
--                    - Conditional compilation for different database versions
--                    - Additional activity summary (when enabling "experimenal" including average and median wait times)
--                    - Concurrent activity information (what is going on at the same time as this SQL statement executes)
--                    - Experimental stuff: Additional I/O summary
--                    - More pretty printing
--                    - Experimental stuff: I/O added to Average Active Session Graph (renamed to Activity Timeline)
--                    - Top Execution Plan Lines and Top Activities added to Activity Timeline
--                    - Activity Timeline is now also shown for serial execution when TIMELINE option is specified
--                    - From 11.2.0.2 on: We get the ACTUAL DOP from the undocumented PX_FLAGS column added to ASH
--                    - All relevant XPLAN_ASH queries are now decorated so it should be easy to identify them in the Library Cache
--                    - More samples are now covered and a kind of "read consistency" across queries on ASH is introduced
--                    - From 11.2.0.2 on: Executions plans are now pulled from the remote RAC instance Library Cache if necessary
--                    - Separate Parallel Worker activity overview
--                    - Limited support for Oracle 10.2 ASH
--
--               1.0: August 2012
--                    Initial release
--
-- Ideas:        - Include GV$SESSION_LONGOPS information
--
#

col plan_table_output format a700
col plan_table_count noprint new_value pc

set linesize 700 pagesize 0 tab off feedback off sqlterminator on underline on

-----------------------------------
-- Configuration, default values --
-----------------------------------

/* Configure EXPERIMENTAL stuff (currently I/O summary and figures added to Activity Timeline as well as average / median wait times for Activity Summaries) */
/* Set this to "" for enabling experimental stuff */
/* Set this to "--" for disabling experimental stuff */
define _EXPERIMENTAL = "--"

/* The graph character used for CPU in the graphs */
define gc = "@"

/* The graph character used for non-CPU in the graphs */
define gc2 = "*"

/* The graph character used for graphs that don't differentiate between CPU and non-CPU */
define gc3 = "#"

/* Threshold for rounding averages */
define rnd_thr = "10"

/* By default don't show the "Ord" (order of execution) column in the execution plan when Parallel Execution is detected */
/* Set to YES for hiding it with Parallel Execution */
/* Set to NO or anything != YES for showing it */
define no_ord_on_px = "YES"

/* In pre-11g there is no SQL_EXEC_START information available. By default the script now searches within the given timeframe (between SQL_EXEC_START and SQL_EXEC_END)
   for the mininum sample time of the identified SQL_ID. If this switch is set to anything != YES then the given SQL_EXEC_START is used as is.
   This default behaviour allows to specify some rough start / end dates and the script takes care of finding the actual start in ASH data.
   Note that this means that multiple executions could be mixed up if you don't carefully define the SQL_EXEC_START date */
define find_min_sample_10g = "YES"

/* In 11g Oracle made the "PX Deq Credit: send blkd" wait event idle, by default do the same to 10g */
/* If you want to see the event as it is recorded in 10g, set this to "--" */
define ignore_PX_credit_blkd_10g = ""

/* Some medians usually don't add much value to the already available averages, therefore they are not shown by default */
/* If you want to have them shown, change this to "" */
define show_median = "NO"

/* The Top N SQL_IDs of concurrent activity */
define topn_sqlid = "5"

/* In the "Parallel Worker activity overview based on ASH" section the PX Execution Server Set information can be shown from 11g on */
/* Since it is derived information it can be wrong and misleading, therefore this switch can be set to anything != YES to hide this info */
define show_px_sets = "YES"

/* By default supress output of internal queries */
/* Set this to "" for seeing the output */
define debug_internalp = "no"

/* Set this to "on" to get feedback on for internal queries */
define debug_internalf = "off"

/* The Top N Processes */
define topnp = "5"

/* The Top N Activities */
define topnw = "5"

/* The Top N Plan lines in the Activity Timeline */
define topnl = "3"

/* The Top N Activities in the Activity Timeline */
define topna = "3"

/* The Parallel Distribution Graph Size */
define pgs = "32"

/* The Average Active Sessions Graph Size */
define aas = "20"

/* The Activities Graph Size */
define wgs = "20"

/* The Time Active Graph Size */
define tgs = "20"

/* The number of seconds for the last active plan lines from ASH */
define las = "10"

/* The characters used for the last active plan lines from ASH */
define active_ind = "==>"

/* Number of rows / buckets used in the Average Active Session Graph */
define avg_as_bkts = "100"

/* TYPICAL +OUTLINE +ALIAS +PEEKED_BINDS is assumed as the default formatting option for DBMS_XPLAN.DISPLAY_CURSOR */
define default_fo = "TYPICAL +OUTLINE +ALIAS +PEEKED_BINDS"

/* Get the info about last execution by default from ASH, alternative is Real-Time SQL Monitoring */
define default_source = "ASH"

/* Determine the ASH source automatically if an SQL_EXEC_START is explicitly provided */
/* If SQL_EXEC_START is not specified then get the ASH info from current ASH, alternative is historic ASH */
define default_ash = "AUTO"

/* Default operation is to show all, Activity, Parallel Distribution and Timeline info based on ASH */
/* Possible values are: [ASH][,][DISTRIB][,][MONITOR][,][TIMELINE]|[NONE]*/
define default_operation = "ASH,DISTRIB,MONITOR,TIMELINE"

/* The default SQL_EXEC_ID if a SQL_EXEC_START is specified but SQL_EXEC_ID is left blank */
define default_sql_exec_id = "16777216"

/* The ASH sample count threshold for the LIMITED_ASH warning message */
define ash_sample_count_threshold = 100000

/* Date mask */
define dm = "YYYY-MM-DD-HH24:MI:SS"

/* Optional date masks to try */
/* Due to the 240 chars limit of SQL*Plus defines this is split into multiple defines */
define dm_opt1 = "'FX&dm.','DD.MM.RR HH24:MI:SS','DD-MON-RR HH:MI:SS PM','DD-MON-RR HH24:MI:SS','MM/DD/RR HH24:MI:SS','DD.MM.YYYY HH24:MI:SS','MM/DD/YYYY HH24:MI:SS','DD-MON-YYYY HH24:MI:SS','DD.MM.YYYY HH:MI:SS PM',"
define dm_opt2 = "'MM/DD/YYYY HH:MI:SS PM', '&dm'"

/* Extended Rowsource Statistics Graphs (A-Time Self Graph, LIO Self Graph, Reads Self Graph and Writes Self Graph) relative to MAX or TOTAL */
/* Default is relative to MAXimum (YES), set to anything else for relative to TOTAL */
define ext_rowsource_graphs_maxrel = "YES"

/* By default show on execution plan line level in the column "Parallel Distribution ASH" processes from monitoring along with rowcounts that are not showing up in ASH samples */
/* Set this to anything else than YES to return to previous behaviour where only processes will be shown that are sampled in ASH */
define show_monitor_rowcount = "YES"

/* List of all available columns */
/* Note that you cannot change the column order (yet), only which columns to show */
/* Keep this list unchanged for reference, change default below */
define all_cols = "pid,ord,act,a_time,lio,reads,writes,a_time_grf,lio_grf,rea_grf,wri_grf,lio_ratio,tcf_grf,e_rows_t,start,dur_t,dur,time_act_grf,procs,procs_grf,act_grf,act,aas_t_grf,aas_grf,mas_grf,execs,a_rows_m,pga,temp,io_read,io_write,co,io_rreq,io_wreq"

/* Default columns to show */
/* Specify here your custom configuration */
define default_cols = "pid,ord,act,a_time,lio,reads,writes,a_time_grf,lio_grf,rea_grf,wri_grf,lio_ratio,tcf_grf,e_rows_t,start,dur_t,dur,time_act_grf,procs,procs_grf,act_grf,act,execs,a_rows_m,pga,temp,io_read,io_write,co,io_rreq,io_wreq"

/* ASH configuration */

/* Configuration for recent ASH */

/* ASH repository */
define curr_global_ash = "gv$active_session_history"

/* Instance identifier */
define curr_inst_id = "inst_id"

/* Plan tables */
define curr_plan_table = "gv$sql_plan"

define curr_plan_table_stats = "gv$sql_plan_statistics_all"

/* Plan table second identifier */
define curr_second_id = "child_number"

/* Real-Time SQL Monitor second identifier */
define curr_second_id_monitor = "child_address"

/* Sample frequency of ASH, 1 second for recent */
define curr_sample_freq = "1"

/* Where to get the formatted plan output from */
define curr_plan_function = "dbms_xplan.display_cursor"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
define curr_par_fil = ""

/* For current ASH we need the instance_id in addition for remote instance executions */
define curr_third_id = "''''p.inst_id = '''' || :inst_id"

/* For current ASH we take SQL text from GV$SQLSTATS */
define curr_sqltext = "gv$sqlstats"

/* For GV$SQLSTATS we need to join on instance_id in addition */
define curr_sqltext_join = "a.min_instance_id = sql.inst_id (+)"

/* For GV$SQLSTATS we need to join on instance_id in addition */
define curr_sqltext_join_col = "inst_id"

/* Real-Time SQL Monitoring views - customize if you want to use your own repository */
define curr_sql_monitor = "gv$sql_monitor"

define curr_sql_plan_monitor = "gv$sql_plan_monitor"

/* Configuration for historical ASH */

/* Global ASH repository */
define hist_global_ash = "(select ash.* from dba_hist_active_sess_history ash, v$database db where db.dbid = ash.dbid)"

/* Instance identifier */
define hist_inst_id = "instance_number"

/* Plan tables */
define hist_plan_table = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

define hist_plan_table_stats = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

/* Plan table second identifier */
define hist_second_id = "plan_hash_value"

/* Real-Time SQL Monitor second identifier */
define hist_second_id_monitor = "plan_hash_value"

/* Sample frequency of ASH, 10 seconds for retained history */
define hist_sample_freq = "10"

/* Where to get the formatted plan output from */
define hist_plan_function = "dbms_xplan.display_awr"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
/* DISPLAY_AWR has an additional parameter DB_ID */
define hist_par_fil = "null,"

/* For historic ASH we don't need the instance_id in addition for remote instance executions */
define hist_third_id = "''''1 = 1 --'''' || :inst_id"

/* For historic ASH we take SQL text from DBA_HIST_SQLTEXT */
define hist_sqltext = "(select t.* from dba_hist_sqltext t, v$database db where t.dbid = db.dbid)"

/* For DBA_HIST_SQL_TEXT we don't need to join on instance_id in addition */
define hist_sqltext_join = "1 = 1"

/* For DBA_HIST_SQL_TEXT we don't need to join on instance_id in addition */
define hist_sqltext_join_col = "1 as inst_id"

/* Real-Time SQL Monitoring views - customize if you want to use your own repository */
define hist_sql_monitor = "gv$sql_monitor"

define hist_sql_plan_monitor = "gv$sql_plan_monitor"

/* Configuration for mixed execution plan from AWR but data from recent ASH / */

/* ASH repository */
define mixed_global_ash = "gv$active_session_history"

/* Instance identifier */
define mixed_inst_id = "inst_id"

/* Plan tables */
define mixed_plan_table = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

define mixed_plan_table_stats = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

/* Plan table second identifier */
define mixed_second_id = "plan_hash_value"

/* Real-Time SQL Monitor second identifier */
define mixed_second_id_monitor = "plan_hash_value"

/* Sample frequency of ASH, 1 second for recent */
define mixed_sample_freq = "1"

/* Where to get the formatted plan output from */
define mixed_plan_function = "dbms_xplan.display_awr"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
define mixed_par_fil = "null,"

/* For mixed ASH we don't need the instance_id in addition for remote instance executions */
define mixed_third_id = "''''1 = 1 --'''' || :inst_id"

/* For mixed ASH we take SQL text from DBA_HIST_SQLTEXT */
define mixed_sqltext = "(select t.* from dba_hist_sqltext t, v$database db where t.dbid = db.dbid)"

/* For DBA_HIST_SQL_TEXT we don't need to join on instance_id in addition */
define mixed_sqltext_join = "1 = 1"

/* For DBA_HIST_SQL_TEXT we don't need to join on instance_id in addition */
define mixed_sqltext_join_col = "1 as inst_id"

/* Real-Time SQL Monitoring views - customize if you want to use your own repository */
define mixed_sql_monitor = "gv$sql_monitor"

define mixed_sql_plan_monitor = "gv$sql_plan_monitor"

/* Configuration for S-ASH / */

/* ASH repository */
define sash_global_ash = "v$active_session_history"

/* Instance identifier */
define sash_inst_id = "inst_id"

/* Plan tables */
define sash_plan_table = "v$sql_plan"

define sash_plan_table_stats = "v$sql_plan"

/* Plan table second identifier */
define sash_second_id = "plan_hash_value"

/* Real-Time SQL Monitor second identifier */
define sash_second_id_monitor = "plan_hash_value"

/* Sample frequency of S-ASH, 1 second default */
define sash_sample_freq = "1"

/* Where to get the formatted plan output from */
define sash_plan_function = "sash_xplan.display"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
define sash_par_fil = ""

/* For S-ASH we don't need the instance_id */
define sash_third_id = "''''1 = 1 --'''' || :inst_id"

/* For mixed ASH we take SQL text from SASH_SQLTXT */
define sash_sqltext = "sash_sqltxt"

/* For SASH_SQL_TXT we don't need to join on instance_id in addition */
define sash_sqltext_join = "1 = 1"

/* For SASH_SQL_TXT we don't need to join on instance_id in addition */
define sash_sqltext_join_col = "1 as inst_id"

/* Real-Time SQL Monitoring views - customize if you want to use your own repository */
define sash_sql_monitor = "gv$sql_monitor"

define sash_sql_plan_monitor = "gv$sql_plan_monitor"

-----------------------
-- Preparation steps --
-----------------------

column prev_sql_id         new_value prev_sql_id          &debug_internalp.print
column prev_child_number   new_value prev_cn              &debug_internalp.print
column prev_sql_exec_start new_value prev_sql_exec_start  &debug_internalp.print
column prev_sql_exec_id    new_value prev_sql_exec_id     &debug_internalp.print
column dt_now              new_value dt_now               &debug_internalp.print

variable prev_sql_id         varchar2(20)
variable prev_child_number   number
variable prev_sql_exec_start varchar2(50)
variable prev_sql_exec_id    number
variable dt_now              varchar2(21)

/* Get the previous command as default
   if no SQL_ID / CHILD_NUMBER is passed */
begin
  $IF DBMS_DB_VERSION.VERSION < 11 $THEN
  execute immediate '
  select
          prev_sql_id
        , prev_child_number
        , to_char(to_date(''01.01.1970'', ''DD.MM.YYYY''), ''&dm'') as prev_sql_exec_start
        , 0                                                         as prev_sql_exec_id
        , to_char(sysdate, ''YYYY-MM-DD HH24:MI:SS'')               as dt_now
  from
          v$session
  where
          sid = userenv(''sid'')'
  $ELSE
  execute immediate '
  select
          prev_sql_id
        , prev_child_number
        , to_char(prev_exec_start, ''&dm'')           as prev_sql_exec_start
        , prev_exec_id                                as prev_sql_exec_id
        , to_char(sysdate, ''YYYY-MM-DD HH24:MI:SS'') as dt_now
  from
          v$session
  where
          sid = userenv(''sid'')'
  $END
  into :prev_sql_id, :prev_child_number, :prev_sql_exec_start, :prev_sql_exec_id, :dt_now;
end;
/

select
        :prev_sql_id                      as prev_sql_id
      , to_char(:prev_child_number, 'TM') as prev_child_number
      , :prev_sql_exec_start              as prev_sql_exec_start
      , to_char(:prev_sql_exec_id, 'TM')  as prev_sql_exec_id
/* Remember the time when searching ASH for recent execution of this particular session (avoid that activity of XPLAN_ASH leads to wrong results) */
      , :dt_now                           as dt_now
from
         dual
;

column prev_sql_id         clear
column prev_child_number   clear
column prev_sql_exec_start clear
column prev_sql_exec_id    clear
column dt_now              clear

/* Is this a S-ASH repository? */
variable is_sash_repo varchar2(1)
variable sash_db_version varchar2(20)

begin
  execute immediate '
  select
          ''Y'' as is_sash_repo
        , version as sash_db_version
  from
          sash_target a
        , sash_targets b
  where
          a.dbid = b.dbid'
  into :is_sash_repo, :sash_db_version;
exception
when others then
  :is_sash_repo := null;
  :sash_db_version := null;
end;
/

column is_sash_repo    new_value _IS_SASH_REPO   &debug_internalp.print
column sash_db_version new_value SASH_DB_VERSION &debug_internalp.print

select
        :is_sash_repo     as is_sash_repo
      , :sash_db_version  as sash_db_version
from
         dual
;

column is_sash_repo    clear
column sash_db_version clear

/* Perform an access check on all objects that might be used and cause a failure */
variable access_check varchar2(4000)

declare
  type t_check_list is table of varchar2(30);
  $IF '&_IS_SASH_REPO' IS NOT NULL $THEN
  a_check_list t_check_list := t_check_list('DUAL', 'V$ACTIVE_SESSION_HISTORY', 'V$SQL_PLAN', 'V$VERSION', 'V$SQL', 'GV$SQL_PLAN_STATISTICS_ALL', 'GV$SQL_MONITOR', 'SASH_SQLTXT');
  $ELSIF DBMS_DB_VERSION.VERSION < 11 $THEN
  a_check_list t_check_list := t_check_list('DUAL', 'V$SESSION', 'GV$SESSION', 'V$DATABASE', 'GV$ACTIVE_SESSION_HISTORY', 'GV$SQL_PLAN', 'GV$SQL_PLAN_STATISTICS_ALL', 'V$VERSION', 'GV$SQL', 'DBA_HIST_ACTIVE_SESS_HISTORY', 'DBA_HIST_SQL_PLAN', 'GV$SQLSTATS', 'DBA_HIST_SQLTEXT');
  $ELSE
  a_check_list t_check_list := t_check_list('DUAL', 'V$SESSION', 'GV$SESSION', 'V$DATABASE', 'GV$ACTIVE_SESSION_HISTORY', 'GV$SQL_PLAN', 'GV$SQL_PLAN_STATISTICS_ALL', 'V$VERSION', 'GV$SQL_MONITOR', 'GV$SQL', 'DBA_HIST_ACTIVE_SESS_HISTORY', 'DBA_HIST_SQL_PLAN', 'GV$SQLSTATS', 'DBA_HIST_SQLTEXT', 'GV$SQL_PLAN_MONITOR');
  $END
  s_dummy varchar2(1);
  s_result varchar2(4000);
begin
  for i in a_check_list.first..a_check_list.last loop
    begin
      execute immediate 'select to_char(null) as dummy from ' || a_check_list(i) || ' where 1 = 2' into s_dummy;
    exception
    when NO_DATA_FOUND then
      null;
    when others then
      s_result := s_result || chr(10) || 'Error ORA' || to_char(SQLCODE, '00000') || ' when accessing ' || a_check_list(i);
    end;
  end loop;
  s_result := ltrim(s_result, chr(10));
  :access_check := s_result;
end;
/

set termout on

set heading off feedback off

column message format a100

select
        '----------------------------------------------------------------------------------------------' as message
from
        dual
where
        :access_check is not null
---------
union all
---------
select
        '!!Access Check failed!!'
from
        dual
where
        :access_check is not null
---------
union all
---------
select
        '----------------------------------------------------------------------------------------------'
from
        dual
where
        :access_check is not null
---------
union all
---------
select
        :access_check
from
        dual
where
        :access_check is not null
;

column message clear

set heading on feedback &debug_internalf

set termout off

-- Default some defines that cause the script appear to "hang" in case of missing privileges
-- This is just to avoid the "hang" (waiting for input with termout off) -
-- these will be populated when operating with proper privileges
define last_exec_second_id = ""
define last_exec_start = ""
define sid_sql_id = ""
define sid_child_no = ""
define sid_sql_exec_start = ""
define child_ad = ""
define sid_sql_exec_id = ""
define last_exec_id = ""
define slave_count = ""
define ic = ""
define ds = ""
define plan_exists = ""
define plan_inst_id = ""
define ash_pred1 = "1 = "
define ash_pred2 = "2"
define ash_ln_pred1 = "1 = "
define ash_ln_pred2 = "2"
define ash_min_sample_time = ""
define ash_max_sample_time = ""
define ash_current_time = ""
define ca_sc = ""
define duplicator = "0"
define dist_sample_count = "0"
define pc = "0"
define sid_child_no_ = ""
define last_exec_second_id_ = ""
define has_binds_xml = ""
define use_monitor = "--"
define use_no_monitor = ""
define is_adaptive_plan = ""
define ash_sample_count = ""

-- The following is a hack to use default
-- values for defines
column 1 new_value 1    &debug_internalp.print
column 2 new_value 2    &debug_internalp.print
column 3 new_value 3    &debug_internalp.print
column 4 new_value 4    &debug_internalp.print
column 5 new_value 5    &debug_internalp.print
column 6 new_value 6    &debug_internalp.print
column 7 new_value 7    &debug_internalp.print
column 8 new_value 8    &debug_internalp.print
column 9 new_value 9    &debug_internalp.print
column 10 new_value 10  &debug_internalp.print

select
        '' as "1"
      , '' as "2"
      , '' as "3"
      , '' as "4"
      , '' as "5"
      , '' as "6"
      , '' as "7"
      , '' as "8"
      , '' as "9"
      , '' as "10"
from
        dual
where
        rownum = 0
;

-- Some version dependent code switches
col ora11_higher    new_value _IF_ORA11_OR_HIGHER     &debug_internalp.print
col ora11_lower     new_value _IF_LOWER_THAN_ORA11    &debug_internalp.print
col ora112_higher   new_value _IF_ORA112_OR_HIGHER    &debug_internalp.print
col ora112_lower    new_value _IF_LOWER_THAN_ORA112   &debug_internalp.print
col ora11202_higher new_value _IF_ORA11202_OR_HIGHER  &debug_internalp.print
col ora11202_lower  new_value _IF_LOWER_THAN_ORA11202 &debug_internalp.print
col ora11203_higher new_value _IF_ORA11203_OR_HIGHER  &debug_internalp.print
col ora11203_lower  new_value _IF_LOWER_THAN_ORA11203 &debug_internalp.print
col ora12_higher    new_value _IF_ORA12_OR_HIGHER     &debug_internalp.print
col ora12_lower     new_value _IF_LOWER_THAN_ORA12    &debug_internalp.print

select
        case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11' then '' else '--'       end as ora11_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11' then '--' else ''       end as ora11_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '' else '--'     end as ora112_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '--' else ''     end as ora112_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.2' then '' else '--' end as ora11202_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.2' then '--' else '' end as ora11202_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.3' then '' else '--' end as ora11203_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.3' then '--' else '' end as ora11203_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '12' then '' else '--'       end as ora12_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '12' then '--' else ''       end as ora12_lower
from
        (select coalesce(case when '&SASH_DB_VERSION' is not null then 'Release &SASH_DB_VERSION ' end, banner) as banner from v$version)
where
        rownum = 1
;

column is_ora11202_or_higher new_value _IF_ORA11202_OR_HIGHERP &debug_internalp.print
column is_ora112_or_higher   new_value _IF_ORA112_OR_HIGHERP   &debug_internalp.print
column is_ora11_or_higher    new_value _IF_ORA11_OR_HIGHERP    &debug_internalp.print
column is_ora12_or_higher    new_value _IF_ORA12_OR_HIGHERP    &debug_internalp.print

select
        case when '&_IF_ORA11202_OR_HIGHER' is null then '' else 'no' end as is_ora11202_or_higher
      , case when '&_IF_ORA112_OR_HIGHER'   is null then '' else 'no' end as is_ora112_or_higher
      , case when '&_IF_ORA11_OR_HIGHER'    is null then '' else 'no' end as is_ora11_or_higher
      , case when '&_IF_ORA12_OR_HIGHER'    is null then '' else 'no' end as is_ora12_or_higher
from
        dual
;

column is_ora11202_or_higher clear
column is_ora112_or_higher   clear
column is_ora11_or_higher    clear
column is_ora12_or_higher    clear

/* For versions prior to 11g there is no concept of SQL_EXEC_START / SQL_EXEC_ID */
/* Hence we require the user to enter simply a start and end date for the ASH samples to use */
column sql_exec2 new_value _SQL_EXEC2                &debug_internalp.print
column experimental_mode new_value experimental_mode &debug_internalp.print

select
&_IF_LOWER_THAN_ORA11         'SQL_EXEC_END (format "&dm")'                as sql_exec2
&_IF_ORA11_OR_HIGHER          'SQL_EXEC_ID (default &default_sql_exec_id)' as sql_exec2
      , case when '&_EXPERIMENTAL' is null then 'YES' else 'NO' end as experimental_mode
from
        dual;

column sql_exec2 clear
column experimental_mode clear

/* If you prefer to be prompted for the various options, activate this code block */
/* --- START --- */
--set doc off
--doc
/* Anything you pass on the command line will be used as default here, so you can simply add/amend/overwrite the option you like at the prompts */

set termout on

prompt
prompt Anything you pass on the command line will be used as default here
prompt
prompt Command-line parameter value: &1
accept 1 default '&1' prompt 'SQL_ID (or SID=<nnn>[@<inst_id>]): '
prompt Command-line parameter value: &2
accept 2 default '&2' prompt 'SQL_EXEC_START (format "&dm"): '
prompt Command-line parameter value: &3
accept 3 default '&3' prompt '&_SQL_EXEC2: '
prompt Command-line parameter value: &4
accept 4 default '&4' prompt 'ASH source (CURR|HIST|MIXED, default &default_ash): '
prompt Command-line parameter value: &5
accept 5 default '&5' prompt 'Enable EXPERIMENTAL mode (YES|NO, default &experimental_mode): '
prompt Command-line parameter value: &6
accept 6 default '&6' prompt 'Source for last exec search (MONITOR/ASH, default &default_source): '
prompt Command-line parameter value: &7
accept 7 default '&7' prompt 'ASH options (default &default_operation): '
prompt Command-line parameter value: &8
accept 8 default '&8' prompt 'CHILD_NUMBER (or PLAN_HASH_VALUE): '
prompt Command-line parameter value: &9
accept 9 default '&9' prompt 'DBMS_XPLAN.DISPLAY* format option (default &default_fo): '
prompt Command-line parameter value: &10
accept 10 default '&10' prompt 'Comma separated list of columns to show/hide (default show all configured columns): '

-- If you need to debug, comment the following line
set termout off

/* If you prefer to be prompted for the various options, activate this code block */
/* --- END --- */
--#

set termout on

prompt
prompt
prompt XPLAN_ASH V4.1 (C) 2012-2014 Randolf Geist
prompt http://oracle-randolf.blogspot.com
prompt
prompt Legend for graphs:
prompt &gc: CPU
prompt &gc2: Non-CPU
prompt &gc3: General activity indicator
prompt
prompt Initializing...
prompt ------------------------------------------------

-- If you need to debug, comment the following line
set termout off

-- Enable LATERAL views - required for being able to use the LATERAL view syntax
variable no_alter_session_priv varchar2(1)

exec :no_alter_session_priv := null

declare
  e_insuff_priv exception;
  pragma exception_init(e_insuff_priv, -1031);
begin
  execute immediate 'alter session set events ''22829 trace name context forever''';
exception
when e_insuff_priv then
  :no_alter_session_priv := 'Y';
end;
/

column use_lateral    new_value use_lateral    &debug_internalp.print
column use_no_lateral new_value use_no_lateral &debug_internalp.print

select
        case when :no_alter_session_priv is     null then '' else '--' end as use_lateral
      , case when :no_alter_session_priv is not null then '' else '--' end as use_no_lateral
from
        dual
;

column use_lateral    clear
column use_no_lateral clear

-- If SQL_EXEC_ID is left blank and SQL_EXEC_START is not null and we have 11g or later, then use the default SQL_EXEC_ID
select
        coalesce('&3', '&default_sql_exec_id') as "3"
from
        dual
where
        '&_IF_ORA11_OR_HIGHER' is null and '&2' is not null;

-- Evaluate optional date masks for SQL_EXEC_START
variable sql_exec_start_format varchar2(100)

exec :sql_exec_start_format := null

declare
  type t_varchar2_list is table of varchar2(100);
  a_date_format t_varchar2_list := t_varchar2_list(&dm_opt1.&dm_opt2);
begin
  for i in a_date_format.first..a_date_format.last loop
    begin
    :sql_exec_start_format := to_char(to_date('&2', a_date_format(i)), '&dm');
    exception
    when others then
      --dbms_output.put_line('Mask failed: ' || a_date_format(i));
      null;
    end;
    if :sql_exec_start_format is not null then
      --dbms_output.put_line('Mask used: ' || a_date_format(i));
      exit;
    end if;
  end loop;
end;
/

select
        :sql_exec_start_format as "2"
from
        dual
where
        '&2' is not null;

-- If SQL_EXEC_END gets used in 10g, apply the same optional date masks here, too
exec :sql_exec_start_format := null

declare
  type t_varchar2_list is table of varchar2(100);
  a_date_format t_varchar2_list := t_varchar2_list(&dm_opt1.&dm_opt2);
begin
  if '&_IF_LOWER_THAN_ORA11' is null then
    for i in a_date_format.first..a_date_format.last loop
      begin
      :sql_exec_start_format := to_char(to_date('&3', a_date_format(i)), '&dm');
      exception
      when others then
        --dbms_output.put_line('Mask failed: ' || a_date_format(i));
        null;
      end;
      if :sql_exec_start_format is not null then
        --dbms_output.put_line('Mask used: ' || a_date_format(i));
        exit;
      end if;
    end loop;
  end if;
end;
/

select
        :sql_exec_start_format as "3"
from
        dual
where
        '&3' is not null and '&_IF_LOWER_THAN_ORA11' is null;

-- If SQL_EXEC_START is specified and ASH source is AUTO then determine CURR / HIST automatically
variable ash_min_sample_time varchar2(17)

declare
  e_table_or_view_not_exists exception;
  pragma exception_init(e_table_or_view_not_exists, -942);
begin
  execute immediate '
  select
          to_char(oldest_sample_time, ''YYYYMMDD HH24:MI:SS'')
  from
          v$ash_info
  where
          ''&_IS_SASH_REPO'' is null
  and coalesce(case when substr(''AUTO'' , 1, length(''&4'')) = upper(''&4'') then ''AUTO'' else ''&4'' end, ''&default_ash'') = ''AUTO'''
  into
          :ash_min_sample_time;
exception
when e_table_or_view_not_exists then
  begin
    execute immediate '
    select
            to_char(min(sample_time), ''YYYYMMDD HH24:MI:SS'')
    from
            gv$active_session_history
    where
            ''&_IS_SASH_REPO'' is null
    and     inst_id = USERENV(''INSTANCE'')
    and     coalesce(case when substr(''AUTO'' , 1, length(''&4'')) = upper(''&4'') then ''AUTO'' else ''&4'' end, ''&default_ash'') = ''AUTO'''
    into
            :ash_min_sample_time;
  exception
  when e_table_or_view_not_exists then
    :ash_min_sample_time := null;
  when NO_DATA_FOUND then
    :ash_min_sample_time := null;
  end;
when NO_DATA_FOUND then
  :ash_min_sample_time := null;
end;
/

select
       case
       when :ash_min_sample_time is null or '&2' is null then 'CURR'
       when to_date(:ash_min_sample_time, 'YYYYMMDD HH24:MI:SS') <= to_date('&2', '&dm') then 'CURR'
       else 'HIST'
       end
       as "4"
from
       dual
where
       coalesce(case when substr('AUTO' , 1, length('&4')) = upper('&4') then 'AUTO' else '&4' end, '&default_ash') = 'AUTO'
;

-- Allow and evaluate shortcuts for some of the parameters
with
a as
(
  select
          ',' || replace(ltrim(upper(nvl('&7', '&default_operation')), ' ,'), ' ', '') as par7
  from dual
),
b as
(
  select
          a.*
        , instr(par7, ',A') as a_start_
        , instr(par7, ',D') as d_start_
        , instr(par7, ',M') as m_start_
        , instr(par7, ',T') as t_start_
        , instr(par7, ',N') as n_start_
        , instr(par7, ',L') as l_start_
  from
          a
),
c as
(
  select
          b.*
        , length(par7) as last_char
        , instr(par7, ',', a_start_ + 1) as a_end_
        , instr(par7, ',', d_start_ + 1) as d_end_
        , instr(par7, ',', m_start_ + 1) as m_end_
        , instr(par7, ',', t_start_ + 1) as t_end_
        , instr(par7, ',', n_start_ + 1) as n_end_
        , instr(par7, ',', l_start_ + 1) as l_end_
  from
          b
),
d as
(
  select
          par7
        , case when a_start_ > 0 then a_start_ + 1 else 0 end as a_start
        , case when d_start_ > 0 then d_start_ + 1 else 0 end as d_start
        , case when m_start_ > 0 then m_start_ + 1 else 0 end as m_start
        , case when t_start_ > 0 then t_start_ + 1 else 0 end as t_start
        , case when n_start_ > 0 then n_start_ + 1 else 0 end as n_start
        , case when l_start_ > 0 then l_start_ + 1 else 0 end as l_start
        , case when a_start_ > 0 then case a_end_ when 0 then last_char else a_end_ - 1 end else 0 end as a_end
        , case when d_start_ > 0 then case d_end_ when 0 then last_char else d_end_ - 1 end else 0 end as d_end
        , case when m_start_ > 0 then case m_end_ when 0 then last_char else m_end_ - 1 end else 0 end as m_end
        , case when t_start_ > 0 then case t_end_ when 0 then last_char else t_end_ - 1 end else 0 end as t_end
        , case when n_start_ > 0 then case n_end_ when 0 then last_char else n_end_ - 1 end else 0 end as n_end
        , case when l_start_ > 0 then case l_end_ when 0 then last_char else l_end_ - 1 end else 0 end as l_end
  from
          c
),
e as
(
  select
          a_start
        , d_start
        , m_start
        , t_start
        , n_start
        , l_start
        , a_end
        , d_end
        , m_end
        , t_end
        , n_end
        , l_end
        , par7
        , case when a_start > 0 then a_end - a_start + 1 else 0 end as a_length
        , case when d_start > 0 then d_end - d_start + 1 else 0 end as d_length
        , case when m_start > 0 then m_end - m_start + 1 else 0 end as m_length
        , case when t_start > 0 then t_end - t_start + 1 else 0 end as t_length
        , case when n_start > 0 then n_end - n_start + 1 else 0 end as n_length
        , case when l_start > 0 then l_end - l_start + 1 else 0 end as l_length
  from
          d
),
f as
(
  select
          e.*
        , case when a_start > 0 then case when substr(par7, a_start, a_length) = substr('ASH', 1, a_length) then 'ASH' else substr(par7, a_start, a_length) end else '' end as a_opt
  from
          e
),
g as
(
  select
          f.*
        , case when d_start > 0 then case when substr(par7, d_start, d_length) = substr('DISTRIB', 1, d_length) then 'DISTRIB' else substr(par7, d_start, d_length) end else '' end as d_opt
  from
          f
),
h as
(
  select
          g.*
        , case when t_start > 0 then case when substr(par7, t_start, t_length) = substr('TIMELINE', 1, t_length) then 'TIMELINE' else substr(par7, t_start, t_length) end else '' end as t_opt
  from
          g
),
i as
(
  select
          h.*
        , case when m_start > 0 then case when substr(par7, m_start, m_length) = substr('MONITOR', 1, m_length) then 'MONITOR' else substr(par7, m_start, m_length) end else '' end as m_opt
  from
          h
),
j as
(
  select
          i.*
        , case when n_start > 0 then case when substr(par7, n_start, n_length) = substr('NONE', 1, n_length) then 'NONE' else substr(par7, n_start, n_length) end else '' end as n_opt
  from
          i
),
k as
(
  select
          j.*
        , case when l_start > 0 then case when substr(par7, l_start, l_length) = substr('LIMITED_ASH', 1, l_length) then 'LIMITED_ASH' else substr(par7, l_start, l_length) end else '' end as l_opt
  from
          j
)
select
        case
        when substr('CURR' , 1, length('&4')) = upper('&4') then 'CURR'
        when substr('HIST' , 1, length('&4')) = upper('&4') then 'HIST'
        when substr('MIXED', 1, length('&4')) = upper('&4') then 'MIXED'
        else '&4'
        end as "4"
      , case
        when substr('YES'  , 1, length('&5')) = upper('&5') then 'YES'
        when substr('NO'   , 1, length('&5')) = upper('&5') then 'NO'
        when substr('TRUE' , 1, length('&5')) = upper('&5') then 'TRUE'
        when substr('FALSE', 1, length('&5')) = upper('&5') then 'FALSE'
        else '&5'
        end as "5"
      , case
        when substr('MONITOR', 1, length('&6')) = upper('&6') then 'MONITOR'
        when substr('ASH'    , 1, length('&6')) = upper('&6') then 'ASH'
        else '&6'
        end as "6"
      , ltrim(a_opt || case when l_opt is not null then ',' end || l_opt || case when d_opt is not null then ',' end || d_opt || case when m_opt is not null then ',' end || m_opt || case when t_opt is not null then ',' end || t_opt || case when n_opt is not null then ',' end || n_opt, ',') as "7"
from
        k;

column fo new_value fo                       &debug_internalp.print
column so new_value so                       &debug_internalp.print
column op new_value op                       &debug_internalp.print
column ah new_value ah                       &debug_internalp.print
column co new_value co                       &debug_internalp.print
column EXPERIMENTAL new_value _EXPERIMENTAL  &debug_internalp.print

/* Use passed parameters else use defaults */
select
        upper(nvl('&9', '&default_fo'))                                                                                      as fo
      , upper(nvl(case when upper('&6') in ('MONITOR', 'ASH') then '&6' end, '&default_source'))                             as so
      , upper(nvl('&7', '&default_operation'))                                                                               as op
      , upper(nvl(case when '&_IS_SASH_REPO' is not null then 'SASH' else case when upper('&4') in ('CURR', 'HIST', 'MIXED') then '&4' end end, '&default_ash'))                         as ah
      , ',' || upper(trim(both ',' from nvl('&10', '&default_cols'))) || ','                                                 as co
      , case when upper(nvl('&5', '&experimental_mode')) in ('ON', 'TRUE', 'YES') then '' else '--' end                      as EXPERIMENTAL
from
        dual
;

column EXPERIMENTAL clear
undefine experimental_mode

/* Determine ASH source */

column global_ash        new_value global_ash         &debug_internalp.print
column inst_id           new_value inst_id            &debug_internalp.print
column plan_table        new_value plan_table         &debug_internalp.print
column plan_table_stats  new_value plan_table_stats   &debug_internalp.print
column second_id         new_value second_id          &debug_internalp.print
column second_id_monitor new_value second_id_monitor  &debug_internalp.print
column sample_freq       new_value sample_freq        &debug_internalp.print
column plan_function     new_value plan_function      &debug_internalp.print
column par_fil           new_value par_fil            &debug_internalp.print
column third_id          new_value third_id           &debug_internalp.print
column sqltext           new_value sqltext            &debug_internalp.print
column sqltext_join      new_value sqltext_join       &debug_internalp.print
column sqltext_join_col  new_value sqltext_join_col   &debug_internalp.print
column sql_monitor       new_value sql_monitor        &debug_internalp.print
column sql_plan_monitor  new_value sql_plan_monitor   &debug_internalp.print

select
        '&curr_global_ash'        as global_ash
      , '&curr_inst_id'           as inst_id
      , '&curr_plan_table'        as plan_table
      , '&curr_plan_table_stats'  as plan_table_stats
      , '&curr_second_id'         as second_id
      , '&curr_second_id_monitor' as second_id_monitor
      , '&curr_sample_freq'       as sample_freq
      , '&curr_plan_function'     as plan_function
      , '&curr_par_fil'           as par_fil
      , '&curr_third_id'          as third_id
      , '&curr_sqltext'           as sqltext
      , '&curr_sqltext_join'      as sqltext_join
      , '&curr_sqltext_join_col'  as sqltext_join_col
      , '&curr_sql_monitor'       as sql_monitor
      , '&curr_sql_plan_monitor'  as sql_plan_monitor
from
        dual
where
        '&ah' = 'CURR'
---------
union all
---------
select
        '&hist_global_ash'        as global_ash
      , '&hist_inst_id'           as inst_id
      , '&hist_plan_table'        as plan_table
      , '&hist_plan_table_stats'  as plan_table_stats
      , '&hist_second_id'         as second_id
      , '&hist_second_id_monitor' as second_id_monitor
      , '&hist_sample_freq'       as sample_freq
      , '&hist_plan_function'     as plan_function
      , '&hist_par_fil'           as par_fil
      , '&hist_third_id'          as third_id
      , '&hist_sqltext'           as sqltext
      , '&hist_sqltext_join'      as sqltext_join
      , '&hist_sqltext_join_col'  as sqltext_join_col
      , '&hist_sql_monitor'       as sql_monitor
      , '&hist_sql_plan_monitor'  as sql_plan_monitor
from
        dual
where
        '&ah' = 'HIST'
---------
union all
---------
select
        '&mixed_global_ash'        as global_ash
      , '&mixed_inst_id'           as inst_id
      , '&mixed_plan_table'        as plan_table
      , '&mixed_plan_table_stats'  as plan_table_stats
      , '&mixed_second_id'         as second_id
      , '&mixed_second_id_monitor' as second_id_monitor
      , '&mixed_sample_freq'       as sample_freq
      , '&mixed_plan_function'     as plan_function
      , '&mixed_par_fil'           as par_fil
      , '&mixed_third_id'          as third_id
      , '&mixed_sqltext'           as sqltext
      , '&mixed_sqltext_join'      as sqltext_join
      , '&mixed_sqltext_join_col'  as sqltext_join_col
      , '&mixed_sql_monitor'       as sql_monitor
      , '&mixed_sql_plan_monitor'  as sql_plan_monitor
from
        dual
where
        '&ah' = 'MIXED'
---------
union all
---------
select
        '&sash_global_ash'        as global_ash
      , '&sash_inst_id'           as inst_id
      , '&sash_plan_table'        as plan_table
      , '&sash_plan_table_stats'  as plan_table_stats
      , '&sash_second_id'         as second_id
      , '&sash_second_id_monitor' as second_id_monitor
      , '&sash_sample_freq'       as sample_freq
      , '&sash_plan_function'     as plan_function
      , '&sash_par_fil'           as par_fil
      , '&sash_third_id'          as third_id
      , '&sash_sqltext'           as sqltext
      , '&sash_sqltext_join'      as sqltext_join
      , '&sash_sqltext_join_col'  as sqltext_join_col
      , '&sash_sql_monitor'       as sql_monitor
      , '&sash_sql_plan_monitor'  as sql_plan_monitor
from
        dual
where
        '&ah' = 'SASH'
;

/* Search for SQL_ID and related information in either ASH or Real-Time SQL Monitoring
   for either this session (no SQL_ID specified) or a specified SID if a SID was specified */

/* One of the following statements will be short-circuited by the optimizer if the ASH / MONITOR condition is not true */
/* So effectively only one of them will run, the other will not return any data (due to the GROUP BY clause) */

column sid_sql_id         new_value sid_sql_id         &debug_internalp.print
column sid_child_no       new_value sid_child_no       &debug_internalp.print
column sid_sql_exec_start new_value sid_sql_exec_start &debug_internalp.print
column sid_sql_exec_id    new_value sid_sql_exec_id    &debug_internalp.print

select /* XPLAN_ASH GET_SESSION_SQL */
&_IF_ORA11_OR_HIGHER          max(sql_id) keep (dense_rank last order by last_refresh_time, sql_exec_start, sql_exec_id nulls first)                                       as sid_sql_id
&_IF_LOWER_THAN_ORA11         '0' as sid_sql_id
&_IF_ORA11_OR_HIGHER        , cast(max(sql_&second_id_monitor) keep (dense_rank last order by last_refresh_time, sql_exec_start, sql_exec_id nulls first) as varchar2(30)) as sid_child_no
&_IF_LOWER_THAN_ORA11       , '0' as sid_child_no
&_IF_ORA11_OR_HIGHER        , max(to_char(sql_exec_start, '&dm')) keep (dense_rank last order by last_refresh_time, sql_exec_start, sql_exec_id nulls first)               as sid_sql_exec_start
&_IF_LOWER_THAN_ORA11       , ''  as sid_sql_exec_start
&_IF_ORA11_OR_HIGHER        , max(to_char(sql_exec_id, 'TM')) keep (dense_rank last order by last_refresh_time, sql_exec_start, sql_exec_id nulls first)                   as sid_sql_exec_id
&_IF_LOWER_THAN_ORA11       , to_char(null, 'TM') as sid_sql_exec_id
from
&_IF_ORA11_OR_HIGHER          &sql_monitor
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
&_IF_ORA11_OR_HIGHER          sid = coalesce(to_number(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), to_number(USERENV('SID')))
&_IF_ORA11_OR_HIGHER  and     inst_id = case when instr('&1', '@') > 0 then to_number(substr('&1', instr('&1', '@') + 1)) else userenv('instance') end
&_IF_ORA11_OR_HIGHER  and     px_qcsid is null
&_IF_ORA11_OR_HIGHER  and     '&so' = 'MONITOR'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     ('&1' is null
&_IF_ORA11_OR_HIGHER  or      upper(substr('&1', 1, 4)) = 'SID=')
&_IF_ORA11_OR_HIGHER  and     last_refresh_time <= to_date('&dt_now', 'YYYY-MM-DD HH24:MI:SS')
group by
        1
---------
union all
---------
select
        max(sql_id) keep (dense_rank last order by sample_time nulls first)                                       as sid_sql_id
      , to_char(max(sql_&second_id) keep (dense_rank last order by sample_time nulls first), 'TM')                as sid_child_no
&_IF_ORA11_OR_HIGHER        , max(to_char(sql_exec_start, '&dm')) keep (dense_rank last order by sample_time nulls first)               as sid_sql_exec_start
&_IF_LOWER_THAN_ORA11       , ''  as sid_sql_exec_start
&_IF_ORA11_OR_HIGHER        , max(to_char(sql_exec_id, 'TM')) keep (dense_rank last order by sample_time nulls first)                   as sid_sql_exec_id
&_IF_LOWER_THAN_ORA11       , to_char(null, 'TM') as sid_sql_exec_id
from
        &global_ash
where
        ((session_id = coalesce(to_number(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), to_number(userenv('sid')))
and     &inst_id = case when instr('&1', '@') > 0 then to_number(substr('&1', instr('&1', '@') + 1)) else userenv('instance') end
and     qc_session_id is null)
--and     regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') != 1)
or      (qc_session_id = coalesce(to_number(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), to_number(userenv('sid')))
and     qc_instance_id = case when instr('&1', '@') > 0 then to_number(substr('&1', instr('&1', '@') + 1)) else userenv('instance') end))
--and     regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') = 1))
and     '&so' = 'ASH'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     ('&1' is null
or      upper(substr('&1', 1, 4)) = 'SID=')
and     sample_time <= to_date('&dt_now', 'YYYY-MM-DD HH24:MI:SS')
and     sql_id is not null
&_IF_ORA11_OR_HIGHER  and     sql_exec_start is not null
&_IF_ORA11_OR_HIGHER  and     sql_exec_id is not null
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g and     (event is null or event != 'PX Deq Credit: send blkd')
group by
        1
;

undefine dt_now

column sid_child_no_ new_value sid_child_no_ &debug_internalp.print

select  /* XPLAN_ASH CHILD_ADDRESS_TO_CHILD_NUMBER */
        to_char(child_number, 'TM') as sid_child_no_
from
        gv$sql
where
        sql_id = '&sid_sql_id'
and     child_address = hextoraw('&sid_child_no')
and     inst_id = case when instr('&1', '@') > 0 then to_number(substr('&1', instr('&1', '@') + 1)) else userenv('instance') end
and     '&so' = 'MONITOR'
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     ('&1' is null
or      upper(substr('&1', 1, 4)) = 'SID=')
and     '&_IF_ORA11_OR_HIGHER' is null
;

column sid_child_no_ clear

-- In case nothing could be found in GV$SQL assign default child number as it doesn't matter anyway
select
        coalesce('&sid_child_no_', '-1') as sid_child_no
from
        dual
where
        '&so' = 'MONITOR'
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     ('&1' is null
or      upper(substr('&1', 1, 4)) = 'SID=')
and     '&_IF_ORA11_OR_HIGHER' is null
;

undefine sid_child_no_

--column sid_sql_id         new_value sid_sql_id
--column sid_child_no       new_value sid_child_no
--column sid_sql_exec_start new_value sid_sql_exec_start
--column sid_sql_exec_id    new_value sid_sql_exec_id

/* Get SQL details from GV$SESSION if a SID is specified */
select /* XPLAN_ASH GET_SESSION_DETAILS */
&_IF_ORA11_OR_HIGHER          nvl2(sql_exec_start, sql_id, prev_sql_id)                                as sid_sql_id
&_IF_LOWER_THAN_ORA11         nvl2(sql_id, sql_id, prev_sql_id)                                        as sid_sql_id
&_IF_ORA11_OR_HIGHER        , to_char(nvl2(sql_exec_start, sql_child_number, prev_child_number), 'TM') as sid_child_no
&_IF_LOWER_THAN_ORA11       , to_char(nvl2(sql_id, sql_child_number, prev_child_number), 'TM')         as sid_child_no
&_IF_ORA11_OR_HIGHER        , to_char(nvl2(sql_exec_start, sql_exec_start, prev_exec_start), '&dm')    as sid_sql_exec_start
&_IF_LOWER_THAN_ORA11       , ''                                                                       as sid_sql_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(nvl2(sql_exec_start, sql_exec_id, prev_exec_id), 'TM')           as sid_sql_exec_id
&_IF_LOWER_THAN_ORA11       , to_char(null, 'TM')                                                      as sid_sql_exec_id
from
       gv$session
where
       upper(substr('&1', 1, 4)) = 'SID='
/*
and    sid = to_number(substr('&1', case when instr('&1', ',') > 0 then instr('&1', ',') + 1 else 5 end))
and    regexp_like(trim(substr('&1', case when instr('&1', ',') > 0 then instr('&1', ',') + 1 else 5 end)), '^\d+$')
and    inst_id = case when instr('&1', ',') > 0 then to_number(substr('&1', 5, instr('&1', ',') - 5)) else userenv('instance') end
and    (instr('&1', ',') < 1 or regexp_like(trim(substr('&1', 5, instr('&1', ',') - 5)), '^\d+$'))
*/
and    sid = to_number(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end))
and    regexp_like(trim(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), '^\d+$')
and    inst_id = case when instr('&1', '@') > 0 then to_number(substr('&1', instr('&1', '@') + 1)) else userenv('instance') end
and    (instr('&1', '@') < 1 or regexp_like(trim(substr('&1', instr('&1', '@') + 1)), '^\d+$'))
-- Only run this if ASH options are not specified
and    not (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
;

column last_exec_second_id new_value last_exec_second_id &debug_internalp.print
column instance_id         new_value plan_inst_id        &debug_internalp.print

/* Identify the CHILD_NUMBER / PLAN_HASH_VALUE if first parameter identifies a SQL_ID and second parameter is null and ASH / Real-Time SQL Monitoring should be queried */

/* One of the following statements will be short-circuited by the optimizer if the ASH / MONITOR condition is not true */
/* So effectively only one of them will run, the other will not return any data (due to the GROUP BY clause) */

select /* XPLAN_ASH IDENTIFY_SECOND_ID */
&_IF_ORA11_OR_HIGHER          cast(max(sql_&second_id_monitor) keep (dense_rank last order by sql_exec_start, sql_exec_id nulls first) as varchar2(30)) as last_exec_second_id
&_IF_LOWER_THAN_ORA11         '0' as last_exec_second_id
&_IF_ORA11_OR_HIGHER        , to_char(cast(max(inst_id) keep (dense_rank last order by sql_exec_start, sql_exec_id nulls first) as varchar2(30)), 'TM') as instance_id
&_IF_LOWER_THAN_ORA11       , '0' as instance_id
from
&_IF_ORA11_OR_HIGHER          &sql_monitor
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
&_IF_ORA11_OR_HIGHER          sql_id = '&1'
&_IF_ORA11_OR_HIGHER  and     px_qcsid is null
&_IF_ORA11_OR_HIGHER  and     '&so' = 'MONITOR'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     sql_exec_start = nvl(to_date('&2', '&dm'), sql_exec_start)
&_IF_ORA11_OR_HIGHER  and     sql_exec_id = nvl(trim('&3'), sql_exec_id)
&_IF_ORA11_OR_HIGHER  and     '&1' is not null
&_IF_ORA11_OR_HIGHER  and     upper(substr('&1', 1, 4)) != 'SID='
&_IF_ORA11_OR_HIGHER  and     '&8' is null
group by
        1
---------
union all
---------
select
&_IF_ORA11_OR_HIGHER          to_char(max(sql_&second_id) keep (dense_rank last order by sql_exec_start, sql_exec_id, sample_time nulls first), 'TM')                as last_exec_second_id
&_IF_LOWER_THAN_ORA11         to_char(max(sql_&second_id) keep (dense_rank first order by sample_time - to_timestamp('&2 ', '&dm') nulls last), 'TM')   as last_exec_second_id
&_IF_ORA11_OR_HIGHER        , to_char(cast(max(case when qc_instance_id is not null then qc_instance_id else &inst_id end) keep (dense_rank last order by sql_exec_start, sql_exec_id, sample_time nulls first) as varchar2(30)), 'TM')              as instance_id
&_IF_LOWER_THAN_ORA11       , to_char(cast(max(case when qc_instance_id is not null then qc_instance_id else &inst_id end) keep (dense_rank first order by sample_time - to_timestamp('&2 ', '&dm') nulls last) as varchar2(30)), 'TM') as instance_id
from
        &global_ash
where
        sql_id = '&1'
and     '&so' = 'ASH'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     sql_exec_start = nvl(to_date('&2', '&dm'), sql_exec_start)
&_IF_ORA11_OR_HIGHER  and     sql_exec_id = nvl(trim('&3'), sql_exec_id)
&_IF_LOWER_THAN_ORA11 and     sample_time between to_timestamp('&2', '&dm') and to_timestamp('&3', '&dm') + interval '1' second
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g and     (event is null or event != 'PX Deq Credit: send blkd')
and     '&1' is not null
and     upper(substr('&1', 1, 4)) != 'SID='
and     '&8' is null
group by
        1
;

select
        nvl('&plan_inst_id', sys_context('USERENV', 'INSTANCE')) as instance_id
from
        dual;

column instance_id     clear

/* Turn the Real-Time SQL Monitoring CHILD_ADDRESS into a CHILD_NUMBER */

column last_exec_second_id_ new_value last_exec_second_id_ &debug_internalp.print

select  /* XPLAN_ASH CHILD_ADDRESS_TO_CHILD_NUMBER */
        to_char(child_number, 'TM') as last_exec_second_id_
from
        gv$sql
where
        sql_id = '&1'
and     child_address = hextoraw('&last_exec_second_id')
and     inst_id = &plan_inst_id
and     '&so' = 'MONITOR'
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     '&1' is not null
and     upper(substr('&1', 1, 4)) != 'SID='
and     '&8' is null
and     '&_IF_ORA11_OR_HIGHER' is null
;

column last_exec_second_id_ clear

-- In case nothing could be found in GV$SQL assign default child number as it doesn't matter anyway
select
        coalesce('&last_exec_second_id_', '-1') as last_exec_second_id
from
        dual
where
        '&so' = 'MONITOR'
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     '&1' is not null
and     upper(substr('&1', 1, 4)) != 'SID='
and     '&8' is null
and     '&_IF_ORA11_OR_HIGHER' is null
;

undefine last_exec_second_id_

column si new_value si &debug_internalp.print
column cn new_value cn &debug_internalp.print

/* Use passed parameters else refer to previous SQL_ID / CHILD_NUMBER or SQL details of given SID */
select
        coalesce('&sid_sql_id', '&1', '&prev_sql_id')                                                                        as si
      , coalesce('&sid_child_no', nvl2('&1', coalesce('&8', '&last_exec_second_id', '0'), coalesce('&8', '&prev_cn', '0')))  as cn
from
        dual
;

--select
--        coalesce('&sid_sql_id', '&1')                                                                            as si
--      , coalesce('&sid_child_no', nvl2('&1', coalesce('&8', '&last_exec_second_id', '0'), coalesce('&8', '0')))  as cn
--from
--        dual
--;

column c_pid                new_value c_pid                  &debug_internalp.print
column c_ord                new_value c_ord                  &debug_internalp.print
column c_act                new_value c_act                  &debug_internalp.print
column c_a_time_self        new_value c_a_time_self          &debug_internalp.print
column c_lio_self           new_value c_lio_self             &debug_internalp.print
column c_reads_self         new_value c_reads_self           &debug_internalp.print
column c_writes_self        new_value c_writes_self          &debug_internalp.print
column c_a_time_self_graph  new_value c_a_time_self_graph    &debug_internalp.print
column c_lio_self_graph     new_value c_lio_self_graph       &debug_internalp.print
column c_reads_self_graph   new_value c_reads_self_graph     &debug_internalp.print
column c_writes_self_graph  new_value c_writes_self_graph    &debug_internalp.print
column c_lio_ratio          new_value c_lio_ratio            &debug_internalp.print
column c_tcf_graph          new_value c_tcf_graph            &debug_internalp.print
column c_e_rows_times_start new_value c_e_rows_times_start   &debug_internalp.print
column c_start_active       new_value c_start_active         &debug_internalp.print
column c_duration_secs      new_value c_duration_secs        &debug_internalp.print
column c_duration_secs_t    new_value c_duration_secs_t      &debug_internalp.print
column c_time_active_graph  new_value c_time_active_graph    &debug_internalp.print
column c_procs              new_value c_procs                &debug_internalp.print
column c_procs_graph        new_value c_procs_graph          &debug_internalp.print
column c_activity_graph     new_value c_activity_graph       &debug_internalp.print
column c_activity           new_value c_activity             &debug_internalp.print
column c_average_as_graph   new_value c_average_as_graph     &debug_internalp.print
column c_median_as_graph    new_value c_median_as_graph      &debug_internalp.print
column c_average_as_t_graph new_value c_average_as_t_graph   &debug_internalp.print
column c_execs              new_value c_execs                &debug_internalp.print
column c_a_rows_m           new_value c_a_rows_m             &debug_internalp.print
column c_pga                new_value c_pga                  &debug_internalp.print
column c_temp               new_value c_temp                 &debug_internalp.print
column c_io_read            new_value c_io_read              &debug_internalp.print
column c_io_write           new_value c_io_write             &debug_internalp.print
column c_co                 new_value c_co                   &debug_internalp.print
column c_io_read_req        new_value c_io_read_req          &debug_internalp.print
column c_io_write_req       new_value c_io_write_req         &debug_internalp.print

-- Determine which columns to hide
-- if the column string contains a minus
select
        case when instr(col_list, ',PID,') > 0          or instr(defcol_list, ',PID,') < 1 then null else '1' end                as c_pid
      , case when instr(col_list, ',ORD,') > 0          or instr(defcol_list, ',ORD,') < 1 then null else '1' end                as c_ord
      , case when instr(col_list, ',ACT,') > 0          or instr(defcol_list, ',ACT,') < 1 then null else '1' end                as c_act
      , case when instr(col_list, ',A_TIME,') > 0       or instr(defcol_list, ',A_TIME,') < 1 then null else '1' end             as c_a_time_self
      , case when instr(col_list, ',LIO,') > 0          or instr(defcol_list, ',LIO,') < 1 then null else '1' end                as c_lio_self
      , case when instr(col_list, ',READS,') > 0        or instr(defcol_list, ',READS,') < 1 then null else '1' end              as c_reads_self
      , case when instr(col_list, ',WRITES,') > 0       or instr(defcol_list, ',WRITES,') < 1 then null else '1' end             as c_writes_self
      , case when instr(col_list, ',A_TIME_GRF,') > 0   or instr(defcol_list, ',A_TIME_GRF,') < 1 then null else '1' end         as c_a_time_self_graph
      , case when instr(col_list, ',LIO_GRF,') > 0      or instr(defcol_list, ',LIO_GRF,') < 1 then null else '1' end            as c_lio_self_graph
      , case when instr(col_list, ',REA_GRF,') > 0      or instr(defcol_list, ',REA_GRF,') < 1 then null else '1' end            as c_reads_self_graph
      , case when instr(col_list, ',WRI_GRF,') > 0      or instr(defcol_list, ',WRI_GRF,') < 1 then null else '1' end            as c_writes_self_graph
      , case when instr(col_list, ',LIO_RATIO,') > 0    or instr(defcol_list, ',LIO_RATIO,') < 1 then null else '1' end          as c_lio_ratio
      , case when instr(col_list, ',TCF_GRF,') > 0      or instr(defcol_list, ',TCF_GRF,') < 1 then null else '1' end            as c_tcf_graph
      , case when instr(col_list, ',E_ROWS_T,') > 0     or instr(defcol_list, ',E_ROWS_T,') < 1 then null else '1' end           as c_e_rows_times_start
      , case when instr(col_list, ',START,') > 0        or instr(defcol_list, ',START,') < 1 then null else '1' end              as c_start_active
      , case when instr(col_list, ',DUR,') > 0          or instr(defcol_list, ',DUR,') < 1 then null else '1' end                as c_duration_secs
      , case when instr(col_list, ',DUR_T,') > 0        or instr(defcol_list, ',DUR_T,') < 1 then null else '1' end              as c_duration_secs_t
      , case when instr(col_list, ',TIME_ACT_GRF,') > 0 or instr(defcol_list, ',TIME_ACT_GRF,') < 1 then null else '1' end       as c_time_active_graph
      , case when instr(col_list, ',PROCS,') > 0        or instr(defcol_list, ',PROCS,') < 1 then null else '1' end              as c_procs
      , case when instr(col_list, ',PROCS_GRF,') > 0    or instr(defcol_list, ',PROCS_GRF,') < 1 then null else '1' end          as c_procs_graph
      , case when instr(col_list, ',ACT_GRF,') > 0      or instr(defcol_list, ',ACT_GRF,') < 1 then null else '1' end            as c_activity_graph
      , case when instr(col_list, ',ACT,') > 0          or instr(defcol_list, ',ACT,') < 1 then null else '1' end                as c_activity
      , case when instr(col_list, ',AAS_GRF,') > 0      or instr(defcol_list, ',AAS_GRF,') < 1 then null else '1' end            as c_average_as_graph
      , case when instr(col_list, ',MAS_GRF,') > 0      or instr(defcol_list, ',MAS_GRF,') < 1 then null else '1' end            as c_median_as_graph
      , case when instr(col_list, ',AAS_T_GRF,') > 0    or instr(defcol_list, ',AAS_T_GRF,') < 1 then null else '1' end          as c_average_as_t_graph
      , case when instr(col_list, ',EXECS,') > 0        or instr(defcol_list, ',EXECS,') < 1 then null else '1' end              as c_execs
      , case when instr(col_list, ',A_ROWS_M,') > 0     or instr(defcol_list, ',A_ROWS_M,') < 1 then null else '1' end           as c_a_rows_m
      , case when instr(col_list, ',PGA,') > 0          or instr(defcol_list, ',PGA,') < 1 then null else '1' end                as c_pga
      , case when instr(col_list, ',TEMP,') > 0         or instr(defcol_list, ',TEMP,') < 1 then null else '1' end               as c_temp
      , case when instr(col_list, ',IO_READ,') > 0      or instr(defcol_list, ',IO_READ,') < 1 then null else '1' end            as c_io_read
      , case when instr(col_list, ',IO_WRITE,') > 0     or instr(defcol_list, ',IO_WRITE,') < 1 then null else '1' end           as c_io_write
      , case when instr(col_list, ',CO,') > 0           or instr(defcol_list, ',CO,') < 1 then null else '1' end                 as c_co
      , case when instr(col_list, ',IO_RREQ,') > 0      or instr(defcol_list, ',IO_RREQ,') < 1 then null else '1' end            as c_io_read_req
      , case when instr(col_list, ',IO_WREQ,') > 0      or instr(defcol_list, ',IO_WREQ,') < 1 then null else '1' end            as c_io_write_req
from
        (
          select
                  replace('&co', '-', '') as col_list, ',' || upper(trim(both ',' from '&default_cols')) || ',' as defcol_list
          from
                  dual
        )
where
        instr('&co', '-') > 0
and     instr('&co', '+') < 1
---------
union all
---------
-- Determine columns to show
select
        case when instr('&co', ',PID,') > 0 then '1' end                as c_pid
      , case when instr('&co', ',ORD,') > 0 then '1' end                as c_ord
      , case when instr('&co', ',ACT,') > 0 then '1' end                as c_act
      , case when instr('&co', ',A_TIME,') > 0 then '1' end             as c_a_time_self
      , case when instr('&co', ',LIO,') > 0 then '1' end                as c_lio_self
      , case when instr('&co', ',READS,') > 0 then '1' end              as c_reads_self
      , case when instr('&co', ',WRITES,') > 0 then '1' end             as c_writes_self
      , case when instr('&co', ',A_TIME_GRF,') > 0 then '1' end         as c_a_time_self_graph
      , case when instr('&co', ',LIO_GRF,') > 0 then '1' end            as c_lio_self_graph
      , case when instr('&co', ',REA_GRF,') > 0 then '1' end            as c_reads_self_graph
      , case when instr('&co', ',WRI_GRF,') > 0 then '1' end            as c_writes_self_graph
      , case when instr('&co', ',LIO_RATIO,') > 0 then '1' end          as c_lio_ratio
      , case when instr('&co', ',TCF_GRF,') > 0 then '1' end            as c_tcf_graph
      , case when instr('&co', ',E_ROWS_T,') > 0 then '1' end           as c_e_rows_times_start
      , case when instr('&co', ',START,') > 0 then '1' end              as c_start_active
      , case when instr('&co', ',DUR,') > 0 then '1' end                as c_duration_secs
      , case when instr('&co', ',DUR_T,') > 0 then '1' end              as c_duration_secs_t
      , case when instr('&co', ',TIME_ACT_GRF,') > 0 then '1' end       as c_time_active_graph
      , case when instr('&co', ',PROCS,') > 0 then '1' end              as c_procs
      , case when instr('&co', ',PROCS_GRF,') > 0 then '1' end          as c_procs_graph
      , case when instr('&co', ',ACT_GRF,') > 0 then '1' end            as c_activity_graph
      , case when instr('&co', ',ACT,') > 0 then '1' end                as c_activity
      , case when instr('&co', ',AAS_GRF,') > 0 then '1' end            as c_average_as_graph
      , case when instr('&co', ',MAS_GRF,') > 0 then '1' end            as c_median_as_graph
      , case when instr('&co', ',AAS_T_GRF,') > 0 then '1' end          as c_average_as_t_graph
      , case when instr('&co', ',EXECS,') > 0 then '1' end              as c_execs
      , case when instr('&co', ',A_ROWS_M,') > 0 then '1' end           as c_a_rows_m
      , case when instr('&co', ',PGA,') > 0 then '1' end                as c_pga
      , case when instr('&co', ',TEMP,') > 0 then '1' end               as c_temp
      , case when instr('&co', ',IO_READ,') > 0 then '1' end            as c_io_read
      , case when instr('&co', ',IO_WRITE,') > 0 then '1' end           as c_io_write
      , case when instr('&co', ',CO,') > 0 then '1' end                 as c_co
      , case when instr('&co', ',IO_RREQ,') > 0 then '1' end            as c_io_read_req
      , case when instr('&co', ',IO_WREQ,') > 0 then '1' end            as c_io_write_req
from
        dual
where
        instr('&co', '-') < 1
and     instr('&co', '+') < 1
---------
union all
---------
-- Determine columns to show
select
        case when instr(col_list, ',PID,') > 0 then '1' end                as c_pid
      , case when instr(col_list, ',ORD,') > 0 then '1' end                as c_ord
      , case when instr(col_list, ',ACT,') > 0 then '1' end                as c_act
      , case when instr(col_list, ',A_TIME,') > 0 then '1' end             as c_a_time_self
      , case when instr(col_list, ',LIO,') > 0 then '1' end                as c_lio_self
      , case when instr(col_list, ',READS,') > 0 then '1' end              as c_reads_self
      , case when instr(col_list, ',WRITES,') > 0 then '1' end             as c_writes_self
      , case when instr(col_list, ',A_TIME_GRF,') > 0 then '1' end         as c_a_time_self_graph
      , case when instr(col_list, ',LIO_GRF,') > 0 then '1' end            as c_lio_self_graph
      , case when instr(col_list, ',REA_GRF,') > 0 then '1' end            as c_reads_self_graph
      , case when instr(col_list, ',WRI_GRF,') > 0 then '1' end            as c_writes_self_graph
      , case when instr(col_list, ',LIO_RATIO,') > 0 then '1' end          as c_lio_ratio
      , case when instr(col_list, ',TCF_GRF,') > 0 then '1' end            as c_tcf_graph
      , case when instr(col_list, ',E_ROWS_T,') > 0 then '1' end           as c_e_rows_times_start
      , case when instr(col_list, ',START,') > 0 then '1' end              as c_start_active
      , case when instr(col_list, ',DUR,') > 0 then '1' end                as c_duration_secs
      , case when instr(col_list, ',DUR_T,') > 0 then '1' end              as c_duration_secs_t
      , case when instr(col_list, ',TIME_ACT_GRF,') > 0 then '1' end       as c_time_active_graph
      , case when instr(col_list, ',PROCS,') > 0 then '1' end              as c_procs
      , case when instr(col_list, ',PROCS_GRF,') > 0 then '1' end          as c_procs_graph
      , case when instr(col_list, ',ACT_GRF,') > 0 then '1' end            as c_activity_graph
      , case when instr(col_list, ',ACT,') > 0 then '1' end                as c_activity
      , case when instr(col_list, ',AAS_GRF,') > 0 then '1' end            as c_average_as_graph
      , case when instr(col_list, ',MAS_GRF,') > 0 then '1' end            as c_median_as_graph
      , case when instr(col_list, ',AAS_T_GRF,') > 0 then '1' end          as c_average_as_t_graph
      , case when instr(col_list, ',EXECS,') > 0 then '1' end              as c_execs
      , case when instr(col_list, ',A_ROWS_M,') > 0 then '1' end           as c_a_rows_m
      , case when instr(col_list, ',PGA,') > 0 then '1' end                as c_pga
      , case when instr(col_list, ',TEMP,') > 0 then '1' end               as c_temp
      , case when instr(col_list, ',IO_READ,') > 0 then '1' end            as c_io_read
      , case when instr(col_list, ',IO_WRITE,') > 0 then '1' end           as c_io_write
      , case when instr(col_list, ',CO,') > 0 then '1' end                 as c_co
      , case when instr(col_list, ',IO_RREQ,') > 0 then '1' end            as c_io_read_req
      , case when instr(col_list, ',IO_WREQ,') > 0 then '1' end            as c_io_write_req
from
        (
          select
                  ',' || upper(trim(both ',' from '&default_cols')) || replace('&co', '+', '') as col_list
          from
                  dual
        )
where
        instr('&co', '-') < 1
and     instr('&co', '+') > 0
;

column last new_value last &debug_internalp.print

/* Last or all execution for Rowsource execution statistics */
select
        case
        when instr('&fo', 'LAST') > 0
        then 'last_'
        end  as last
from
        dual
;

column plan_table_name new_value plan_table_name &debug_internalp.print

/* Get plan info from GV$SQL_PLAN_STATISTICS_ALL or GV$SQL_PLAN */
select
        case
        when instr('&fo', 'STATS') > 0
        then '&plan_table_stats'
        else '&plan_table'
        end  as plan_table_name
from
        dual
;

column child_ad new_value child_ad &debug_internalp.print

-- Get child address for querying GV$SQL_MONITOR
select  /* XPLAN_ASH CHILD_NUMBER_TO_CHILD_ADDRESS */
        rawtohex(child_address) as child_ad
from
        gv$sql
where
        sql_id = '&si'
and     child_number = &cn
and     inst_id = &plan_inst_id
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     coalesce('&sid_sql_exec_start', '&2') is null and '&1' is not null
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
;

column last_exec_start new_value last_exec_start &debug_internalp.print
column last_exec_id new_value last_exec_id       &debug_internalp.print

/* Search for the last execution of the statement if no SQL_EXEC_START is specified and no other option provides the information */

/* One of the following statements will be short-circuited by the optimizer if the ASH / MONITOR condition is not true */
/* So effectively only one of them will run, the other will not return any data (due to the GROUP BY clause) */

/* This statement is effectively turned into a NOOP in versions below 11g */
select /* XPLAN_ASH SEARCH_LAST_EXECUTION */
&_IF_ORA11_OR_HIGHER          to_char(max(sql_exec_start), '&dm')                                                        as last_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(max(sql_exec_id) keep (dense_rank last order by sql_exec_start nulls first), 'TM') as last_exec_id
&_IF_LOWER_THAN_ORA11         ''   as last_exec_start
&_IF_LOWER_THAN_ORA11       , '0'  as last_exec_id
from
&_IF_ORA11_OR_HIGHER          &sql_monitor
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
&_IF_ORA11_OR_HIGHER          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_&second_id_monitor = case when upper('&second_id_monitor') = 'CHILD_ADDRESS' then '&child_ad' else '&cn' end
&_IF_ORA11_OR_HIGHER  and     px_qcsid is null
&_IF_ORA11_OR_HIGHER  and     '&so' = 'MONITOR'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     coalesce('&sid_sql_exec_start', '&2') is null and '&1' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
group by
        1
---------
union all
---------
select
&_IF_ORA11_OR_HIGHER          to_char(max(sql_exec_start), '&dm')                                                        as last_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(max(sql_exec_id) keep (dense_rank last order by sql_exec_start nulls first), 'TM') as last_exec_id
&_IF_LOWER_THAN_ORA11         ''  as last_exec_start
&_IF_LOWER_THAN_ORA11       , '0' as last_exec_id
from
&_IF_ORA11_OR_HIGHER          &global_ash ash
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
&_IF_ORA11_OR_HIGHER          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_&second_id = &cn
&_IF_ORA11_OR_HIGHER  and     '&so' = 'ASH'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     coalesce('&sid_sql_exec_start', '&2') is null and '&1' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
group by
        1
;

column ls new_value ls &debug_internalp.print
column li new_value li &debug_internalp.print

/* Use passed parameters else refer to last execution found / SQL details of given SID */
select
        coalesce('&sid_sql_exec_start', '&2', case when '&1' is null then '&prev_sql_exec_start' end, '&last_exec_start') as ls
        -- , coalesce('&sid_sql_exec_id', '&3', '&last_exec_id', '-1') as li
      , case
        when '&sid_sql_exec_start' is not null
        then '&sid_sql_exec_id'
        when '&2' is not null
        then nvl(trim('&3'), '-1')
        when '&1' is null
        then '&prev_sql_exec_id'
        else coalesce('&last_exec_id', '-1')
        end                                                                                                               as li
from
        dual
;

--select
--        coalesce('&sid_sql_exec_start', '&2', '&last_exec_start') as ls
--        -- , coalesce('&sid_sql_exec_id', '&3', '&last_exec_id', '-1') as li
--      , case
--        when '&sid_sql_exec_start' is not null
--        then '&sid_sql_exec_id'
--        when '&2' is not null
--        then nvl(trim('&3'), '-1')
--        else coalesce('&last_exec_id', '-1')
--        end                                                                                                               as li
--from
--        dual
--;

/* Determine any additional filters on the SQL_TEXT views for remote RAC executions */
variable out_third_id varchar2(100)

exec execute immediate 'select &third_id as add_filter from dual' into :out_third_id using '&plan_inst_id'

column third_id_sqltext new_value third_id_sqltext &debug_internalp.print

select
        :out_third_id as third_id_sqltext
from
        dual;

column third_id_sqltext clear

/* Define the actual query on ASH for samples */
/* Not all samples for a SQL execution are marked with SQL_EXEC_START / SQL_EXEC_ID */
/* So in order to include those samples a little bit of logic is required */
/* This logic here is inspired by Real-Time SQL Monitoring */
/* In order to support other ASH sources this query needs to be adjusted along with
   the parameters that define the valid ASH samples */
/* This query here restricts the ASH data to the session information identified */
/* The actual ASH queries will use the clauses determined here along with the SQL_ID plus start / end sample time */
column pred1           new_value ash_pred1            &debug_internalp.print
column pred2           new_value ash_pred2            &debug_internalp.print
column ln_pred1        new_value ash_ln_pred1         &debug_internalp.print
column ln_pred2        new_value ash_ln_pred2         &debug_internalp.print
column instance_id     new_value plan_inst_id         &debug_internalp.print
column min_sample_time new_value ash_min_sample_time  &debug_internalp.print
column max_sample_time new_value ash_max_sample_time  &debug_internalp.print
column current_time    new_value ash_current_time     &debug_internalp.print

select  /* XPLAN_ASH DEFINE_ASH_SAMPLES */
        pred1
      , pred2
      , ln_pred1
      , ln_pred2
      , instance_id
      , to_char(sql_exec_start, 'YYYY-MM-DD HH24:MI:SS')  as min_sample_time
      , to_char(max_sample_time, 'YYYY-MM-DD HH24:MI:SS') as max_sample_time
      , to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS')         as current_time
from
        (
          select
                  max_sample_time
                  /* For versions that support the GV$() special table function we can actually refer to the instance where the execution was started */
                  /* For prior versions this is deliberately limited to the current instance to get at least a consistent behaviour */
                  /* Although this might mean either getting no plan at all or in worst case getting a wrong plan from the local Library Cache */
&_IF_ORA11202_OR_HIGHER                 , to_char(case when qc_instance_id is not null then qc_instance_id else instance_id end, 'TM')                                                                       as instance_id
&_IF_LOWER_THAN_ORA11202                , sys_context('USERENV', 'INSTANCE')                                                                                                                                 as instance_id
                , '((ash.&inst_id = '           || to_char(nvl(case when qc_instance_id is not null then qc_instance_id else instance_id end, 0), 'TM') ||
                  ' and ash.session_id = '      || to_char(nvl(case when qc_instance_id is not null then qc_session_id else session_id end, -1), 'TM') ||
&_IF_ORA11_OR_HIGHER                    case when (qc_instance_id is not null and qc_session_serial# is not null) or (qc_instance_id is null and session_serial# is not null) then ' and ash.session_serial# = ' || to_char(case when qc_instance_id is not null then qc_session_serial# else session_serial# end, 'TM') end ||
                  ')'                                                                                                                                                                                        as pred1
                , 'or (ash.qc_instance_id = ' || to_char(nvl(case when qc_instance_id is not null then qc_instance_id else instance_id end, 0), 'TM') ||
                  ' and ash.qc_session_id = ' || to_char(nvl(case when qc_instance_id is not null then qc_session_id else session_id end, -1), 'TM') ||
&_IF_ORA11_OR_HIGHER                    case when qc_instance_id is not null and qc_session_serial# is not null then ' and ash.qc_session_serial# = ' || to_char(case when qc_instance_id is not null then qc_session_serial# else session_serial# end, 'TM') end ||
                  '))'                                                                                                                                                                                       as pred2
                , '((lnnvl(ash.&inst_id = '          || to_char(nvl(case when qc_instance_id is not null then qc_instance_id else instance_id end, 0), 'TM') || ')' ||
                  ' or lnnvl(ash.session_id = '      || to_char(nvl(case when qc_instance_id is not null then qc_session_id else session_id end, -1), 'TM') || ')' ||
&_IF_ORA11_OR_HIGHER                    case when (qc_instance_id is not null and qc_session_serial# is not null) or (qc_instance_id is null and session_serial# is not null) then ' or lnnvl(ash.session_serial# = ' || to_char(case when qc_instance_id is not null then qc_session_serial# else session_serial# end, 'TM') || ')' end ||
                  ')'                                                                                                                                                                                       as ln_pred1
                , 'and (lnnvl(ash.qc_instance_id = ' || to_char(nvl(case when qc_instance_id is not null then qc_instance_id else instance_id end, 0), 'TM') || ')' ||
                  ' or lnnvl(ash.qc_session_id = ' || to_char(nvl(case when qc_instance_id is not null then qc_session_id else session_id end, -1), 'TM') || ')' ||
&_IF_ORA11_OR_HIGHER                    case when qc_instance_id is not null and qc_session_serial# is not null then ' or lnnvl(ash.qc_session_serial# = ' || to_char(case when qc_instance_id is not null then qc_session_serial# else session_serial# end, 'TM') || ')' end ||
                  '))'                                                                                                                                                                                       as ln_pred2
                , sql_exec_start
          from
                  (
                    select
                            min(sql_exec_start)                                                                     as sql_exec_start
                          , max(cast(sample_time as date))                                                          as max_sample_time
&_IF_ORA11_OR_HIGHER                            , max(instance_id) keep (dense_rank last order by cnt, sample_time nulls first)           as instance_id
&_IF_LOWER_THAN_ORA11                           , max(instance_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)         as instance_id
&_IF_ORA11_OR_HIGHER                            , max(session_id) keep (dense_rank last order by cnt, sample_time nulls first)         as session_id
&_IF_LOWER_THAN_ORA11                           , max(session_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)       as session_id
&_IF_ORA11_OR_HIGHER                            , max(session_serial#) keep (dense_rank last order by cnt, sample_time nulls first)    as session_serial#
&_IF_LOWER_THAN_ORA11                           , max(session_serial#) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)  as session_serial#
&_IF_ORA11_OR_HIGHER                            , max(qc_instance_id) keep (dense_rank last order by cnt, sample_time nulls first)     as qc_instance_id
&_IF_LOWER_THAN_ORA11                           , max(qc_instance_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)   as qc_instance_id
&_IF_ORA11_OR_HIGHER                            , max(qc_session_id) keep (dense_rank last order by cnt, sample_time nulls first)      as qc_session_id
&_IF_LOWER_THAN_ORA11                           , max(qc_session_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)    as qc_session_id
&_IF_ORA11_OR_HIGHER                            , max(qc_session_serial#) keep (dense_rank last order by cnt, sample_time nulls first) as qc_session_serial#
&_IF_LOWER_THAN_ORA11                           , null                                                                                 as qc_session_serial#
                    from
                            (
                              select
&_IF_ORA11_OR_HIGHER                                        sql_exec_start
&_IF_LOWER_THAN_ORA11                                       case when coalesce('&find_min_sample_10g', 'NO') = 'YES' then cast(sample_time as date) else to_date('&ls', '&dm') end  as sql_exec_start
                                    , sample_time
                                    , &inst_id                as instance_id
                                    , session_id
                                    , session_serial#
                                    , qc_instance_id
                                    , qc_session_id
&_IF_ORA11_OR_HIGHER                                      , qc_session_serial#
                                    /* There seem to be sometimes inconsistencies in the ASH data (spurious serial#) therefore with 11g versions the "most occuring" session data will be used */
                                    , count(*) over (partition by
                                                     case when qc_instance_id is not null
                                                     then qc_instance_id || ',' || qc_session_id
&_IF_ORA11_OR_HIGHER                                                       || ',' || qc_session_serial#
                                                     else &inst_id || ',' || session_id || ',' || session_serial# end)         as cnt
                              from
                                      &global_ash ash
                              where
                                      sql_id = '&si'
&_IF_ORA11_OR_HIGHER                               and     sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER                               and     sql_exec_id = &li
&_IF_LOWER_THAN_ORA11                              and     sample_time >= to_timestamp('&ls', '&dm') and sample_time < to_timestamp('&li', '&dm') + interval '1' second
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g                             and     (event is null or event != 'PX Deq Credit: send blkd')
                            )
                  )
        )
;

select
        nvl('&plan_inst_id', sys_context('USERENV', 'INSTANCE')) as instance_id
from
        dual;

column pred1           clear
column pred2           clear
column ln_pred1        clear
column ln_pred2        clear
column instance_id     clear
column min_sample_time clear
column max_sample_time clear
column current_time    clear

/* In case of pre-11g use the min sample time found as SQL_EXEC_START from here on */
/* See the description of "find_min_sample_10g" in the configuration section for more info */

select
        to_char(to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'), '&dm') as ls
from
        dual
where
        coalesce('&find_min_sample_10g', 'NO') = 'YES'
and     '&_IF_LOWER_THAN_ORA11' is null;

/* Determine any additional filters on the plan tables for remote RAC executions */
variable out_third_id varchar2(100)

exec execute immediate 'select &third_id as add_filter from dual' into :out_third_id using '&plan_inst_id'

column third_id new_value third_id &debug_internalp.print

select
        :out_third_id as third_id
from
        dual;

column third_id clear

/* Check if a plan can be found */
column plan_exists new_value plan_exists &debug_internalp.print

select
        max(sql_id) as plan_exists
from
        &plan_table p
where
        p.sql_id = '&si'
and     p.&second_id = &cn
and     &third_id
and     rownum <= 1
;

-------------------------------
-- Actual output starts here --
-------------------------------

set termout on pagesize 49999 heading on feedback off newpage 1 numwidth 10 numformat "" null "" colsep "|" headsep "|"

set heading off

column message format a50

/* Just a quick notice if we could not find anything for a given SID */
select
        'No SQL information for &1 found!' as message
from
        dual
where
       upper(substr('&1', 1, 4)) = 'SID='
/*
and    regexp_like(trim(substr('&1', case when instr('&1', ',') > 0 then instr('&1', ',') + 1 else 5 end)), '^\d+$')
and    (instr('&1', ',') < 1 or regexp_like(trim(substr('&1', 5, instr('&1', ',') - 5)), '^\d+$'))
*/
and    regexp_like(trim(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), '^\d+$')
and    (instr('&1', '@') < 1 or regexp_like(trim(substr('&1', instr('&1', '@') + 1)), '^\d+$'))
and    '&sid_sql_id' is null
;

column message clear

set heading on

prompt
prompt
prompt General information
prompt ------------------------------------------------

column sql_id           format a13
column sql_exec_start   format a19
column sql_exec_end     format a19
column format_option    format a40
column last_exec_source format a20
column ash_options      format a40
column ash_source       format a10

select
        '&si' as sql_id
      , &cn   as &second_id
      , '&ls' as sql_exec_start
&_IF_ORA11_OR_HIGHER        , &li   as sql_exec_id
&_IF_LOWER_THAN_ORA11       , case when coalesce('&find_min_sample_10g', 'NO') = 'YES' then '&ash_max_sample_time' else '&li' end  as sql_exec_end
      , '&fo' as format_option
      , case
        when '&sid_sql_id' is not null and '&1' is not null
        then upper('&1') || case when instr('&op', 'NONE') = 0 then ' (&so)' end
&_IF_ORA11_OR_HIGHER          when '&1' is null and '&2' is null
&_IF_LOWER_THAN_ORA11         when '&1' is null
        then 'PREV_SQL' || case when instr('&op', 'NONE') = 0 then ' (&so)' end
        when '&2' is not null or instr('&op', 'NONE') > 0
        then 'N/A'
        else '&so'
        end   as last_exec_source
      , '&op' as ash_options
      , case when instr('&op', 'NONE') > 0 then 'N/A' else '&ah' end as ash_source
from
        dual
;

column sql_id           clear
column sql_exec_start   clear
column sql_exec_end     clear
column format_option    clear
column last_exec_source clear
column ash_options      clear
column ash_source       clear

set heading off

set termout off

-- If this is S-ASH, from here on only 10g features/columns will be used
col ora11_higher    new_value _IF_ORA11_OR_HIGHER     &debug_internalp.print
col ora11_lower     new_value _IF_LOWER_THAN_ORA11    &debug_internalp.print
col ora112_higher   new_value _IF_ORA112_OR_HIGHER    &debug_internalp.print
col ora112_lower    new_value _IF_LOWER_THAN_ORA112   &debug_internalp.print
col ora11202_higher new_value _IF_ORA11202_OR_HIGHER  &debug_internalp.print
col ora11202_lower  new_value _IF_LOWER_THAN_ORA11202 &debug_internalp.print
col ora11203_higher new_value _IF_ORA11203_OR_HIGHER  &debug_internalp.print
col ora11203_lower  new_value _IF_LOWER_THAN_ORA11203 &debug_internalp.print
col ora12_higher    new_value _IF_ORA12_OR_HIGHER     &debug_internalp.print
col ora12_lower     new_value _IF_LOWER_THAN_ORA12    &debug_internalp.print

select
        case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11' then '' else '--'       end as ora11_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11' then '--' else ''       end as ora11_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '' else '--'     end as ora112_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '--' else ''     end as ora112_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.2' then '' else '--' end as ora11202_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.2' then '--' else '' end as ora11202_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.3' then '' else '--' end as ora11203_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.3' then '--' else '' end as ora11203_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '12' then '' else '--'       end as ora12_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '12' then '--' else ''       end as ora12_lower
from
        (select coalesce(case when '&SASH_DB_VERSION' is not null then 'Release 10.2.0.4 ' end, banner) as banner from v$version)
where
        rownum = 1
;

column is_ora11202_or_higher new_value _IF_ORA11202_OR_HIGHERP &debug_internalp.print
column is_ora112_or_higher   new_value _IF_ORA112_OR_HIGHERP   &debug_internalp.print
column is_ora11_or_higher    new_value _IF_ORA11_OR_HIGHERP    &debug_internalp.print
column is_ora12_or_higher    new_value _IF_ORA12_OR_HIGHERP    &debug_internalp.print

select
        case when '&_IF_ORA11202_OR_HIGHER' is null then '' else 'no' end as is_ora11202_or_higher
      , case when '&_IF_ORA112_OR_HIGHER'   is null then '' else 'no' end as is_ora112_or_higher
      , case when '&_IF_ORA11_OR_HIGHER'    is null then '' else 'no' end as is_ora11_or_higher
      , case when '&_IF_ORA12_OR_HIGHER'    is null then '' else 'no' end as is_ora12_or_higher
from
        dual
;

column is_ora11202_or_higher clear
column is_ora112_or_higher   clear
column is_ora11_or_higher    clear
column is_ora12_or_higher    clear

/* Check for the ASH sample count threshold if: */
/* - ASH option is specified */
/* - LIMITED_ASH option is not specified */

column ash_sample_count new_value ash_sample_count &debug_internalp.print

select
        to_char(count(*), 'TM') as ash_sample_count
from
        &global_ash
where
        1 = 1 --'&_IF_ORA112_OR_HIGHER' is null
and     instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
;

column ash_sample_count clear

set termout on

set heading off feedback off

column message format a80

select
        chr(10) || chr(10) ||
        '------------------------------------------------------------' || chr(10) ||
        'Note: The ASH sample count warning threshold (&ash_sample_count_threshold) is' || chr(10) ||
        'exceeded. Some XPLAN_ASH queries can take longer with that'   || chr(10) ||
        'amount of ASH data. Use the LIMITED_ASH option to skip the '  || chr(10) ||
        'usually longest running XPLAN_ASH queries.'                   || chr(10) ||
        '------------------------------------------------------------'
from
        dual
where
        1 = 1 --'&_IF_ORA112_OR_HIGHER' is null
and     instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     to_number(trim('&ash_sample_count')) > &ash_sample_count_threshold
;

set heading on

column message clear

undefine ash_sample_count

-- If you need to debug, comment the following line
set termout off

set termout on

set heading off feedback off

column message format a80

select
        chr(10) || chr(10) ||
        '------------------------------------------------------------' || chr(10) ||
        'Note: This session lacks the ALTER SESSION privilege'         || chr(10) ||
        'XPLAN_ASH will use a different code path that can be slower'  || chr(10) ||
        'when analyzing longer running statements. To skip the       ' || chr(10) ||
        'usually longest running queries use the LIMITED_ASH option'   || chr(10) ||
        '------------------------------------------------------------'
from
        dual
where
        :no_alter_session_priv = 'Y'
--and     '&_IF_ORA112_OR_HIGHER' is null
and     instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
;

set heading on

column message clear

-- If you need to debug, comment the following line
set termout off

/* Check if Real-Time SQL Monitoring info should be used or not */
column use_monitor new_value use_monitor       &debug_internalp.print
column use_no_monitor new_value use_no_monitor &debug_internalp.print

select
        case
        when '&_IF_ORA11_OR_HIGHER' is null
             and instr('&op', 'MONITOR') > 0
&_IF_ORA11_OR_HIGHER             and exists (select null from &sql_monitor where sql_id = '&si' and sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li and px_qcsid is null)
        then ''
        else '--' end as use_monitor
      , case
        when '&_IF_ORA11_OR_HIGHER' is not null
             or instr('&op', 'MONITOR') <= 0
&_IF_ORA11_OR_HIGHER             or not exists (select null from &sql_monitor where sql_id = '&si' and sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li and px_qcsid is null)
        then ''
        else '--' end as use_no_monitor
from
        dual
;

column use_monitor    clear
column use_no_monitor clear

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        '&use_monitor' is null
---------
union all
---------
select
        'Real-Time SQL Monitoring Execution Summary' as message
from
        dual
where
        '&use_monitor' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        '&use_monitor' is null
;

column message clear

set heading on

column status                                                                                         null "UNAVAILABLE"
column username                                                            &_IF_ORA112_OR_HIGHERP.print
column px_is_cross_instance  heading "PX IS|CROSS|INST"     format a5      &_IF_ORA112_OR_HIGHERP.print null "N/A"
column px_mindop             heading "PX|MIN|DOP"           just left                                   null "N/A"
column px_maxdop             heading "PX|MAX|DOP"           just left                                   null "N/A"
column px_instances          heading "PX|INSTANCES"         just left      &_IF_ORA112_OR_HIGHERP.print null "N/A"
column px_servers_requested  heading "PX|SERVERS|REQUESTED" just left      &_IF_ORA112_OR_HIGHERP.print null "N/A"
column px_servers_allocated  heading "PX|SERVERS|ALLOCATED" just left      &_IF_ORA112_OR_HIGHERP.print null "N/A"
column time_graph            heading "DURATION AND|DATABASE TIME|GRAPH" format a&wgs
column duration                                                                                       null "UNAVAILABLE"
column elapsed_time          heading "DATABASE|TIME"
column cpu_time              heading "CPU|TIME"
column user_io_wait_time     heading "IO|WAIT|TIME"
column concurrency_wait_time heading "CONCURRENY|WAIT|TIME"
column cluster_wait_time     heading "CLUSTER|WAIT|TIME"
column application_wait_time heading "APPLICATION|WAIT|TIME"
column queuing_time          heading "QUEUING|TIME"                      &_IF_ORA112_OR_HIGHERP.print
column plsql_java_time       heading "PLSQL|JAVA|TIME"
column other_time            heading "OTHER|TIME"
column buffer_gets_format    heading "BUFFER|GETS"           format a8
column read_reqs_format      heading "READ|REQ"              format a8
column read_bytes_format     heading "READ|BYTES"            format a8   &_IF_ORA112_OR_HIGHERP.print
column write_reqs_format     heading "WRITE|REQ"             format a8
column write_bytes_format    heading "WRITE|BYTES"           format a8   &_IF_ORA112_OR_HIGHERP.print
column cell_offload_percent  heading "CELL|OFFL|PERC"        format a6   &_IF_ORA112_OR_HIGHERP.print
column service_name          heading "SERVICE"               format a30  &_IF_ORA112_OR_HIGHERP.print
column program                                               format a50  &_IF_ORA112_OR_HIGHERP.print
column error_message         heading "ERROR|MESSAGE"         format a128 &_IF_ORA112_OR_HIGHERP.print

with /* XPLAN_ASH SQL_STATEMENT_EXECUTION_RTSM_SUMMARY SQL_ID: &si */
monitor_info1 as
(
  select
&use_monitor                max(case when px_qcsid is null then status end)                                                            as status
&use_no_monitor             cast(NULL as varchar2(30)) as status
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then username end)                                     as username
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as varchar2(30))                                                            as username
&use_no_monitor           , cast(NULL as varchar2(30)) as username
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then service_name end)                                 as service_name
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as varchar2(30))                                                            as service_name
&use_no_monitor           , cast(NULL as varchar2(30)) as service_name
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then coalesce(program, 'NULL') end)                    as program
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as varchar2(30))                                                            as program
&use_no_monitor           , cast(NULL as varchar2(30)) as program
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then px_is_cross_instance end)                         as px_is_cross_instance
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as varchar2(1))                                                             as px_is_cross_instance
&use_no_monitor           , cast(NULL as varchar2(1))  as px_is_cross_instance
&use_monitor              , min(case when px_qcsid is not null then cnt_px_server end)                                                 as px_mindop
&use_no_monitor           , cast(NULL as number)       as px_mindop
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then px_maxdop end)                                    as px_maxdop
&use_monitor &_IF_LOWER_THAN_ORA112            , max(case when px_qcsid is not null then cnt_px_server end)                            as px_maxdop
&use_no_monitor           , cast(NULL as number)       as px_maxdop
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then px_maxdop_instances end)                          as px_instances
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as px_instances
&use_no_monitor           , cast(NULL as number)       as px_instances
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then px_servers_requested end)                         as px_servers_requested
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as px_servers_requested
&use_no_monitor           , cast(NULL as number)       as px_servers_requested
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then px_servers_allocated end)                         as px_servers_allocated
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as px_servers_allocated
&use_no_monitor           , cast(NULL as number)       as px_servers_allocated
&use_monitor              , round((max(case when px_qcsid is null then case when status = 'EXECUTING' then sysdate else last_refresh_time end end) - max(sql_exec_start)) * 86400)          as duration
&use_no_monitor           , cast(NULL as number)       as duration
&use_monitor              , round(sum(elapsed_time) / 1e6)                                                                             as elapsed_time
&use_no_monitor           , cast(NULL as number)       as elapsed_time
&use_monitor              , round(sum(cpu_time) / 1e6)                                                                                 as cpu_time
&use_no_monitor           , cast(NULL as number)       as cpu_time
&use_monitor              , round(sum(user_io_wait_time) / 1e6)                                                                        as user_io_wait_time
&use_no_monitor           , cast(NULL as number)       as user_io_wait_time
&use_monitor              , round(sum(concurrency_wait_time) / 1e6)                                                                    as concurrency_wait_time
&use_no_monitor           , cast(NULL as number)       as concurrency_wait_time
&use_monitor              , round(sum(cluster_wait_time) / 1e6)                                                                        as cluster_wait_time
&use_no_monitor           , cast(NULL as number)       as cluster_wait_time
&use_monitor              , round(sum(application_wait_time) / 1e6)                                                                    as application_wait_time
&use_no_monitor           , cast(NULL as number)       as application_wait_time
&use_monitor &_IF_ORA112_OR_HIGHER             , round(sum(queuing_time) / 1e6)                                                        as queuing_time
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as queuing_time
&use_no_monitor           , cast(NULL as number)       as queuing_time
&use_monitor              , round(sum(plsql_exec_time + java_exec_time) / 1e6)                                                         as plsql_java_time
&use_no_monitor           , cast(NULL as number)       as plsql_java_time
&use_monitor              , sum(buffer_gets)                                                                                           as buffer_gets
&use_no_monitor           , cast(NULL as number)       as buffer_gets
&use_monitor &_IF_ORA112_OR_HIGHER             , sum(physical_read_requests)                                                           as read_reqs
&use_monitor &_IF_LOWER_THAN_ORA112            , sum(disk_reads)                                                                       as read_reqs
&use_no_monitor           , cast(NULL as number)       as read_reqs
&use_monitor &_IF_ORA112_OR_HIGHER             , sum(physical_read_bytes)                                                              as read_bytes
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as read_bytes
&use_no_monitor           , cast(NULL as number)       as read_bytes
&use_monitor &_IF_ORA112_OR_HIGHER             , sum(physical_write_requests)                                                          as write_reqs
&use_monitor &_IF_LOWER_THAN_ORA112            , sum(direct_writes)                                                                    as write_reqs
&use_no_monitor           , cast(NULL as number)       as write_reqs
&use_monitor &_IF_ORA112_OR_HIGHER             , sum(physical_write_bytes)                                                             as write_bytes
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as write_bytes
&use_no_monitor           , cast(NULL as number)       as write_bytes
&use_monitor &_IF_ORA112_OR_HIGHER             , 100 - round(sum(io_interconnect_bytes) / nullif(sum(physical_read_bytes + physical_write_bytes), 0) * 100) as cell_offload_percent
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as number)                                                                  as cell_offload_percent
&use_no_monitor           , cast(NULL as number)       as cell_offload_percent
&use_monitor &_IF_ORA112_OR_HIGHER             , max(case when px_qcsid is null then error_message end)                                as error_message
&use_monitor &_IF_LOWER_THAN_ORA112            , cast(NULL as varchar2(30))                                                            as error_message
&use_no_monitor           , cast(NULL as varchar2(30)) as error_message
  from
&use_monitor                (select count(*) over (partition by px_server_group, px_server_set) as cnt_px_server, a.* from &sql_monitor a
&use_no_monitor             dual
  where
&use_no_monitor             1 = 2
&use_monitor                1 = 1
&use_monitor        and     sql_id = '&si'
&use_monitor        and     sql_exec_start = to_date('&ls', '&dm')
&use_monitor        and     sql_exec_id = &li)
),
monitor_info2 as
(
  select
          status
        , username
        , service_name
        , program
        , px_is_cross_instance
        , px_mindop
        , px_maxdop
        , px_instances
        , px_servers_requested
        , px_servers_allocated
        , duration
        , greatest(elapsed_time, cpu_time + user_io_wait_time + concurrency_wait_time + cluster_wait_time + application_wait_time + coalesce(queuing_time, 0)) as elapsed_time
        , cpu_time
        , user_io_wait_time
        , concurrency_wait_time
        , cluster_wait_time
        , application_wait_time
        , queuing_time
        , plsql_java_time
        , greatest(elapsed_time - (cpu_time + user_io_wait_time + concurrency_wait_time + cluster_wait_time + application_wait_time + coalesce(queuing_time, 0)), 0) as other_time
        , buffer_gets
        , read_reqs
        , read_bytes
        , write_reqs
        , write_bytes
        , cell_offload_percent
        , error_message
  from
          monitor_info1
),
monitor_info3 as
(
  select
          status
        , username
        , service_name
        , program
        , px_is_cross_instance
        , px_mindop
        , px_maxdop
        , px_instances
        , px_servers_requested
        , px_servers_allocated
        , rpad('&gc3', round(greatest(case when duration < elapsed_time then duration / elapsed_time else 1 end * (&wgs - 1), 1)), '&gc3') || chr(10) ||
          rpad('&gc', round((cpu_time / elapsed_time) * case when elapsed_time < duration then elapsed_time / duration else 1 end * (&wgs - 1)), '&gc') ||
          rpad('&gc2', round(((user_io_wait_time + concurrency_wait_time + cluster_wait_time + application_wait_time + coalesce(queuing_time, 0)) / elapsed_time) * case when elapsed_time < duration then elapsed_time / duration else 1 end * (&wgs - 1)), '&gc2') ||
          rpad('&gc3', round((other_time / elapsed_time) * case when elapsed_time < duration then elapsed_time / duration else 1 end * (&wgs - 1)), '&gc3')
          as time_graph
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(elapsed_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(elapsed_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as elapsed_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(cpu_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(cpu_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as cpu_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(user_io_wait_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(user_io_wait_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as user_io_wait_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(concurrency_wait_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(concurrency_wait_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as concurrency_wait_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(cluster_wait_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(cluster_wait_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as cluster_wait_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(application_wait_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(application_wait_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as application_wait_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(queuing_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(queuing_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as queuing_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(plsql_java_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(plsql_java_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as plsql_java_time
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(other_time, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(other_time, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as other_time
        , buffer_gets
        , trunc(log(10, abs(case buffer_gets when 0 then 1 else buffer_gets end)))                         as power_10_buffer_gets
        , trunc(mod(log(10, abs(case buffer_gets when 0 then 1 else buffer_gets end)), 3))                 as power_10_buffer_gets_mod_3
        , read_reqs
        , trunc(log(10, abs(case read_reqs when 0 then 1 else read_reqs end)))                             as power_10_read_reqs
        , trunc(mod(log(10, abs(case read_reqs when 0 then 1 else read_reqs end)), 3))                     as power_10_read_reqs_mod_3
        , read_bytes
        , trunc(log(2, abs(case read_bytes when 0 then 1 else read_bytes end)))                            as power_2_read_bytes
        , trunc(mod(log(2, abs(case read_bytes when 0 then 1 else read_bytes end)) ,10))                   as power_2_read_bytes_mod_10
        , write_reqs
        , trunc(log(10, abs(case write_reqs when 0 then 1 else write_reqs end)))                           as power_10_write_reqs
        , trunc(mod(log(10, abs(case write_reqs when 0 then 1 else write_reqs end)), 3))                   as power_10_write_reqs_mod_3
        , write_bytes
        , trunc(log(2, abs(case write_bytes when 0 then 1 else write_bytes end)))                          as power_2_write_bytes
        , trunc(mod(log(2, abs(case write_bytes when 0 then 1 else write_bytes end)) ,10))                 as power_2_write_bytes_mod_10
        , cell_offload_percent
        , error_message
  from
          monitor_info2
)
select
        status
      , username
      , px_is_cross_instance
      , px_mindop
      , px_maxdop
      , px_instances
      , px_servers_requested
      , px_servers_allocated
      , time_graph
      , duration
      , elapsed_time
      , cpu_time
      , user_io_wait_time
      , concurrency_wait_time
      , cluster_wait_time
      , application_wait_time
      , queuing_time
      , plsql_java_time
      , other_time
      , lpad(to_char(round(buffer_gets / power(10, power_10_buffer_gets - case when power_10_buffer_gets > 0 and power_10_buffer_gets_mod_3 = 0 then 3 else power_10_buffer_gets_mod_3 end)), 'FM99999'), 6) ||
        case power_10_buffer_gets - case when power_10_buffer_gets > 0 and power_10_buffer_gets_mod_3 = 0 then 3 else power_10_buffer_gets_mod_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
              when buffer_gets is null
              then null
              else '*10^'||to_char(power_10_buffer_gets - case when power_10_buffer_gets > 0 and power_10_buffer_gets_mod_3 = 0 then 3 else power_10_buffer_gets_mod_3 end)
              end
        end      as buffer_gets_format
      , lpad(to_char(round(read_reqs / power(10, power_10_read_reqs - case when power_10_read_reqs > 0 and power_10_read_reqs_mod_3 = 0 then 3 else power_10_read_reqs_mod_3 end)), 'FM99999'), 6) ||
        case power_10_read_reqs - case when power_10_read_reqs > 0 and power_10_read_reqs_mod_3 = 0 then 3 else power_10_read_reqs_mod_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
              when read_reqs is null
              then null
              else '*10^'||to_char(power_10_read_reqs - case when power_10_read_reqs > 0 and power_10_read_reqs_mod_3 = 0 then 3 else power_10_read_reqs_mod_3 end)
              end
        end      as read_reqs_format
      , lpad(to_char(round(read_bytes / power(2, power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end)), 'FM99999'), 6) ||
        case power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
              when read_bytes is null
              then null
              else '*2^'||to_char(power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end)
              end
        end      as read_bytes_format
      , lpad(to_char(round(write_reqs / power(10, power_10_write_reqs - case when power_10_write_reqs > 0 and power_10_write_reqs_mod_3 = 0 then 3 else power_10_write_reqs_mod_3 end)), 'FM99999'), 6) ||
        case power_10_write_reqs - case when power_10_write_reqs > 0 and power_10_write_reqs_mod_3 = 0 then 3 else power_10_write_reqs_mod_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
              when write_reqs is null
              then null
              else '*10^'||to_char(power_10_write_reqs - case when power_10_write_reqs > 0 and power_10_write_reqs_mod_3 = 0 then 3 else power_10_write_reqs_mod_3 end)
              end
        end      as write_reqs_format
      , lpad(to_char(round(write_bytes / power(2, power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end)), 'FM99999'), 6) ||
        case power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
              when write_bytes is null
              then null
              else '*2^'||to_char(power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end)
              end
        end      as write_bytes_format
      , case when cell_offload_percent is not null then lpad(cell_offload_percent, 4) || '%' end as cell_offload_percent
      , service_name
      , program
      , error_message
from
        monitor_info3
;

column status                clear
column username              clear
column px_is_cross_instance  clear
column px_mindop             clear
column px_maxdop             clear
column px_instances          clear
column px_servers_requested  clear
column px_servers_allocated  clear
column time_graph            clear
column duration              clear
column elapsed_time          clear
column cpu_time              clear
column user_io_wait_time     clear
column concurrency_wait_time clear
column cluster_wait_time     clear
column application_wait_time clear
column queuing_time          clear
column plsql_java_time       clear
column other_time            clear
column buffer_gets_format    clear
column read_reqs_format      clear
column read_bytes_format     clear
column write_reqs_format     clear
column write_bytes_format    clear
column cell_offload_percent  clear
column service_name          clear
column program               clear
column error_message         clear

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        'SQL statement execution ASH Summary' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
;

column message clear

set heading on

/* Summary information based on ASH */

column inst_count             new_value ic noprint
column duration_secs_covered  new_value ds noprint

column first_sample          format a19
column last_sample           format a19
column status                format a8
column duration_secs_t                  heading "DURATION SECS|TOTAL"
column duration_t                       heading "DURATION|TOTAL"
column duration_secs                    heading "DURATION SECS|ACTIVE"
column duration                         heading "DURATION|ACTIVE"
column average_as_t                     heading "AVERAGE AS|TOTAL"
column average_as                       heading "AVERAGE AS|ACTIVE"
column px_maxdop             heading "PX MAX|DOP"                   null "N/A" &_IF_ORA11202_OR_HIGHERP.print
column px_mindop             heading "PX MIN|DOP"                   null "N/A" &_IF_ORA11202_OR_HIGHERP.print
column px_worker_count new_value slave_count heading "PX WORKER|COUNT"
column px_worker_unique_count           heading "PX WORKER|UNIQUE COUNT"
column top_level_sql_id      format a16 heading "TOP_LEVEL_SQL_ID"             &_IF_ORA11_OR_HIGHERP.print
column pga                   format a10 heading "MAX_PGA"                      &_IF_ORA112_OR_HIGHERP.print
column temp                  format a10 heading "MAX_TEMP"                     &_IF_ORA112_OR_HIGHERP.print
column px_send_rec_count                heading "PX SEND/RECEIVE|COUNT"        &_IF_ORA11_OR_HIGHERP.print
column perc_px_send_rec                 heading "PX SEND/RECEIVE|PERCENT"      &_IF_ORA11_OR_HIGHERP.print
column px_send_rec_cpu_count            heading "PX SEND/RECEIVE|CPU COUNT"    &_IF_ORA11_OR_HIGHERP.print
column perc_px_send_rec_cpu             heading "PX SEND/RECEIVE|CPU PERCENT"  &_IF_ORA11_OR_HIGHERP.print
column is_sqlid_current      format a7  heading "IS|SQLID|CURRENT"             &_IF_ORA112_OR_HIGHERP.print
column in_connection_mgmt    format a7  heading "IN|CONNECT|MGMT"              &_IF_ORA11_OR_HIGHERP.print
column in_parse              format a7  heading "IN|PARSE"                     &_IF_ORA11_OR_HIGHERP.print
column in_hard_parse         format a7  heading "IN|HARD|PARSE"                &_IF_ORA11_OR_HIGHERP.print
column in_sql_execution      format a7  heading "IN|SQL|EXECUTE"               &_IF_ORA11_OR_HIGHERP.print
column in_plsql_execution    format a7  heading "IN|PLSQL|EXECUTE"             &_IF_ORA11_OR_HIGHERP.print
column in_plsql_rpc          format a7  heading "IN|PLSQL|RPC"                 &_IF_ORA11_OR_HIGHERP.print
column in_plsql_compilation  format a7  heading "IN|PLSQL|COMP"                &_IF_ORA11_OR_HIGHERP.print
column in_java_execution     format a7  heading "IN|JAVA|EXECUTE"              &_IF_ORA11_OR_HIGHERP.print
column in_bind               format a7  heading "IN|BIND"                      &_IF_ORA11_OR_HIGHERP.print
column in_cursor_close       format a7  heading "IN|CURSOR|CLOSE"              &_IF_ORA11_OR_HIGHERP.print
column in_sequence_load      format a7  heading "IN|SEQ|LOAD"                  &_IF_ORA112_OR_HIGHERP.print

with /* XPLAN_ASH SQL_STATEMENT_EXECUTION_ASH_SUMMARY SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                  as instance_id
        , cast(sample_time as date)                                                                 as sample_time
        , sql_id
        , case
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- when regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1) is null
          when regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') != 1
          then null
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- else &inst_id || '-' || regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1)
          else &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')
          end                                                                                       as process
        , case when session_state = 'ON CPU' then 1 else 0 end                                      as is_on_cpu
        , module
        , action
&_IF_ORA112_OR_HIGHER    , machine
        , session_id
&_IF_ORA11_OR_HIGHER     , top_level_sql_id
        , session_serial#
        , user_id
&_IF_ORA11202_OR_HIGHER       , px_flags
&_IF_LOWER_THAN_ORA11202      , null as px_flags
        , qc_session_id
        , qc_instance_id
&_IF_ORA11_OR_HIGHER          , case when sql_plan_operation in ('PX SEND', 'PX RECEIVE') then 1 else 0 end as px_send_receive
&_IF_LOWER_THAN_ORA11         , 0                                                                   as px_send_receive
&_IF_ORA112_OR_HIGHER         , case when is_sqlid_current = 'Y' then 1 else 0 end                  as is_sqlid_current
&_IF_LOWER_THAN_ORA112        , 0                                                                   as is_sqlid_current
&_IF_ORA11_OR_HIGHER          , case when in_connection_mgmt = 'Y' then 1 else 0 end                as in_connection_mgmt
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_connection_mgmt
&_IF_ORA11_OR_HIGHER          , case when in_parse = 'Y' then 1 else 0 end                          as in_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_parse
&_IF_ORA11_OR_HIGHER          , case when in_hard_parse = 'Y' then 1 else 0 end                     as in_hard_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_hard_parse
&_IF_ORA11_OR_HIGHER          , case when in_sql_execution = 'Y' then 1 else 0 end                  as in_sql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_sql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_execution = 'Y' then 1 else 0 end                as in_plsql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_plsql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_rpc = 'Y' then 1 else 0 end                      as in_plsql_rpc
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_plsql_rpc
&_IF_ORA11_OR_HIGHER          , case when in_plsql_compilation = 'Y' then 1 else 0 end              as in_plsql_compilation
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_plsql_compilation
&_IF_ORA11_OR_HIGHER          , case when in_java_execution = 'Y' then 1 else 0 end                 as in_java_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_java_execution
&_IF_ORA11_OR_HIGHER          , case when in_bind = 'Y' then 1 else 0 end                           as in_bind
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_bind
&_IF_ORA11_OR_HIGHER          , case when in_cursor_close = 'Y' then 1 else 0 end                   as in_cursor_close
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_cursor_close
&_IF_ORA112_OR_HIGHER         , case when in_sequence_load = 'Y' then 1 else 0 end                  as in_sequence_load
&_IF_LOWER_THAN_ORA112        , 0                                                                   as in_sequence_load
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                         as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                  as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq                                                                        as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_exec_id
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
driver as
(
  select
          b.instance_id
        , b.sample_time as timeline
        , b.bucket
  from
          timeline_inst b
),
--base_data as
--(
--  select
--          count(a.sample_time) as active_sessions
--        , driver.timeline
--        , driver.instance_id
--  from
--          driver
--        , ash_base a
--  where
--          a.ash_bucket (+) = driver.bucket
--  and     a.instance_id (+) = driver.instance_id
--  group by
--          driver.instance_id
--        , driver.timeline
--  --order by
--  --        driver.instance_id
--  --      , driver.timeline
--),
base_data_g as
(
  select
          count(a.sample_time) as active_sessions
        , driver.timeline
  from
          driver
        , ash_base a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.instance_id (+) = driver.instance_id
  group by
          driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.timeline
),
median_as as
(
  select
          median(active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
  from
          base_data_g
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into two parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , ash_base ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , ash.instance_id
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    ash_base ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_pga_temp1 as
(
  select
          sum(pga_allocated) as pga_per_bucket
        , sum(temp_space_allocated) as temp_per_bucket
        , bucket
  from
          ash_data
  group by
          bucket
),
ash_pga_temp as
(
  select
          max(pga_per_bucket) as pga_mem
        , max(temp_per_bucket) as temp_space
  from
          ash_pga_temp1
),
ash_pga_temp_prefmt as
(
  select
          pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                     as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                            as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                               as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                      as power_2_temp_space_mod_10
  from
          ash_pga_temp
),
ash_pga_temp_fmt as
(
  select
          to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
  from
          ash_pga_temp_prefmt
)
select  /* XPLAN_ASH SQL_STATEMENT_EXECUTION_ASH_SUMMARY SQL_ID: &si */
        instance_count
      , inst_count
      , session_id
      , a.instance_id
      , user_id
&_IF_ORA11_OR_HIGHER        , top_level_sql_id
      , first_sample
      , last_sample
      , duration_secs_t
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
      , duration_secs
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
      , duration_secs_covered
      , status
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / nullif(sample_count, 0) * 100)                     as percentage_cpu
      , px_send_receive_count                                                       as px_send_rec_count
      , round(px_send_receive_count / nullif(sample_count, 0) * 100)                as perc_px_send_rec
      , px_send_receive_on_cpu_count                                                as px_send_rec_cpu_count
      , round(px_send_receive_on_cpu_count / nullif(cpu_sample_count, 0) * 100)     as perc_px_send_rec_cpu
      , case when min_actual_degree <= 1 then null else min_actual_degree end       as px_mindop
      , case when actual_degree <= 1 then null else actual_degree end               as px_maxdop
      , slave_count                                                                 as px_worker_count
      , slave_unique_count                                                          as px_worker_unique_count
      , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end as average_as_t
      , case when average_as >= &rnd_thr then round(average_as) else average_as end as average_as
      , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end as median_as
      , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end as stddev_as
      , lpad(ash_pga_temp_fmt.pga_mem_format, 10)                                   as pga
      , lpad(ash_pga_temp_fmt.temp_space_format, 10)                                as temp
      , module
      , action
&_IF_ORA112_OR_HIGHER       , machine
      , lpad(to_char(round(is_sqlid_current / sample_count * 100), 'TM'), 6) || '%'      as is_sqlid_current
      , lpad(to_char(round(in_connection_mgmt / sample_count * 100), 'TM'), 6) || '%'    as in_connection_mgmt
      , lpad(to_char(round(in_parse / sample_count * 100), 'TM'), 6) || '%'              as in_parse
      , lpad(to_char(round(in_hard_parse / sample_count * 100), 'TM'), 6) || '%'         as in_hard_parse
      , lpad(to_char(round(in_sql_execution / sample_count * 100), 'TM'), 6) || '%'      as in_sql_execution
      , lpad(to_char(round(in_plsql_execution / sample_count * 100), 'TM'), 6) || '%'    as in_plsql_execution
      , lpad(to_char(round(in_plsql_rpc / sample_count * 100), 'TM'), 6) || '%'          as in_plsql_rpc
      , lpad(to_char(round(in_plsql_compilation / sample_count * 100), 'TM'), 6) || '%'  as in_plsql_compilation
      , lpad(to_char(round(in_java_execution / sample_count * 100), 'TM'), 6) || '%'     as in_java_execution
      , lpad(to_char(round(in_bind / sample_count * 100), 'TM'), 6) || '%'               as in_bind
      , lpad(to_char(round(in_cursor_close / sample_count * 100), 'TM'), 6) || '%'       as in_cursor_close
      , lpad(to_char(round(in_sequence_load / sample_count * 100), 'TM'), 6) || '%'      as in_sequence_load
from
        (
          select
                  to_char(count(distinct instance_id), 'TM')                                                              as inst_count
                , count(distinct instance_id)                                                                             as instance_count
                , to_char(min(sample_time), '&dm')                                                                        as first_sample
                , to_char(max(sample_time), '&dm')                                                                        as last_sample
                , round(((max(sample_time) - min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first)) * 86400)) + &sample_freq as duration_secs_t
                , round(max(ash_bucket) - min(ash_bucket) + &sample_freq)                                                 as duration_secs_covered
                , count(distinct ash_bucket) * &sample_freq                                                               as duration_secs
                , case
                  when max(sample_time) >= to_date('&ash_current_time', 'YYYY-MM-DD HH24:MI:SS') - 2 * &sample_freq / 86400
                  then 'ACTIVE'
                  else 'INACTIVE'
                  end                                                                                                     as status
                , count(*)                                                                                                as sample_count
                , sum(is_on_cpu)                                                                                          as cpu_sample_count
                , max(trunc(px_flags / 2097152))                                                                          as actual_degree
                , min(nullif(trunc(px_flags / 2097152), 0))                                                               as min_actual_degree
                , count(distinct process)                                                                                 as slave_count
                , count(distinct case when process is not null then process || '-' || session_id || '-' || session_serial# end) as slave_unique_count
                , nvl(max(module), 'NULL')                                                                                as module
                , nvl(max(action), 'NULL')                                                                                as action
                , max(user_id)                                                                                            as user_id
&_IF_ORA112_OR_HIGHER                 , nvl(max(machine), 'NULL')                                                                             as machine
&_IF_ORA11_OR_HIGHER                  , nvl(max(top_level_sql_id), 'NULL')                                                                    as top_level_sql_id
                , sum(px_send_receive)                                                                                    as px_send_receive_count
                , sum(case when px_send_receive = 1 and is_on_cpu = 1 then 1 else 0 end)                                  as px_send_receive_on_cpu_count
                , sum(is_sqlid_current)                                                                                   as is_sqlid_current
                , sum(in_connection_mgmt)                                                                                 as in_connection_mgmt
                , sum(in_parse)                                                                                           as in_parse
                , sum(in_hard_parse)                                                                                      as in_hard_parse
                , sum(in_sql_execution)                                                                                   as in_sql_execution
                , sum(in_plsql_execution)                                                                                 as in_plsql_execution
                , sum(in_plsql_rpc)                                                                                       as in_plsql_rpc
                , sum(in_plsql_compilation)                                                                               as in_plsql_compilation
                , sum(in_java_execution)                                                                                  as in_java_execution
                , sum(in_bind)                                                                                            as in_bind
                , sum(in_cursor_close)                                                                                    as in_cursor_close
                , sum(in_sequence_load)                                                                                   as in_sequence_load
                , coalesce(max(qc_session_id), max(session_id))                                                           as session_id
                , coalesce(max(qc_instance_id), max(instance_id))                                                         as instance_id
                , round(count(*) / nullif((max(ash_bucket) - min(ash_bucket) + &sample_freq) / &sample_freq, 0), 1)       as average_as_t
                , round(count(*) / nullif(count(distinct ash_bucket), 0), 1)                                              as average_as
          from
                  ash_base
          where
                  (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
          -- This prevents the aggregate functions to produce a single row
          -- in case of no rows generated to aggregate
          group by
                  1
        ) a
      , ash_pga_temp_fmt
      , median_as m
;

column duration_secs_t       clear
column duration_t            clear
column duration_secs         clear
column duration              clear
column average_as_t          clear
column average_as            clear
column top_level_sql_id      clear
column px_send_rec_count     clear
column perc_px_send_rec      clear
column px_send_rec_cpu_count clear
column perc_px_send_rec_cpu  clear

column is_sqlid_current      clear
column in_connection_mgmt    clear
column in_parse              clear
column in_hard_parse         clear
column in_sql_execution      clear
column in_plsql_execution    clear
column in_plsql_rpc          clear
column in_plsql_compilation  clear
column in_java_execution     clear
column in_bind               clear
column in_cursor_close       clear
column in_sequence_load      clear

column px_maxdop             clear
column px_mindop             clear
column px_worker_count       clear
column px_worker_unique_count clear

-- If you need to debug, comment the following line
set termout off

column slave_count new_value slave_count &debug_internalp.print

select
        case when to_number('&slave_count') = 0 then '' else trim('&slave_count') end as slave_count
from
        dual
;

column slave_count clear

column duration_secs_covered clear

column first_sample clear
column last_sample  clear
column status       clear
column pga          clear
column temp         clear

column is_cross_instance_p new_value _IF_CROSS_INSTANCE    &debug_internalp.print
column is_cross_instance   new_value _IS_CROSS_INSTANCE    &debug_internalp.print
column is_single_instance  new_value _IS_SINGL_INSTANCE    &debug_internalp.print

select
        case when to_number(nvl('&ic', '0')) > 1 then '' else 'no' end  as is_cross_instance_p
      , case when to_number(nvl('&ic', '0')) > 1 then '' else '--' end  as is_cross_instance
      , case when to_number(nvl('&ic', '0')) > 1 then '--' else '' end  as is_single_instance
from
        dual
;

column is_cross_instance_p clear
column is_cross_instance   clear
column is_single_instance  clear

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'SQL statement execution ASH Summary per Instance' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

-- If you need to debug, comment the following line
set termout off

/* The following query is only run separately as integrating it into other queries leads to ORA-03113 core dumps during optimization at least on 11.2.0.1 versions */
/* It determines two important figures used later on:
   1. A scaling factor for the TIME_ACTIVE_GRAPH if there are less sample points than the defined size of such a graph
   2. The number of distinct sample points for determining the Average Active Sessions information */
/* Had to revert to 11.1 optimizer features anyway since this query now also causes an ORA-03113 on 11.2.0.1, so it could be re-integrated but kept it separate */

column duplicator new_value duplicator               &debug_internalp.print
column dist_sample_count new_value dist_sample_count &debug_internalp.print

with /* XPLAN_ASH DETERMINE_DUPLICATOR SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                  as instance_id
        , cast(sample_time as date)                                                                 as sample_time
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq    as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , min(ash_bucket)     as min_ash_bucket
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
dist_count as
(
  select
          count(*) as dist_sample_count
  from
          timeline t
        , dates d
  where
          t.bucket >= d.min_ash_bucket
),
duplicator as
(
  select
          coalesce(ceil(&tgs / nullif(count(*), 0)), 0) as duplicator
        --, coalesce(count(distinct timeline), 0)                         as dist_sample_count
  from
          timeline
)
select  /*+ optimizer_features_enable('11.1.0.7') */
        duplicator
      , dist_sample_count
from
        dist_count
      , duplicator
;

column duplicator clear
column dist_sample_count clear

set termout on

set heading on

/* Summary information per RAC instance based on ASH (for cross-instance SQL execution) */

column first_sample         format a19
column last_sample          format a19
column time_active_graph    format a&tgs
column duration_secs_t                   heading "DURATION SECS|TOTAL"
column duration_t                        heading "DURATION|TOTAL"
column duration_secs                     heading "DURATION SECS|ACTIVE"
column duration                          heading "DURATION|ACTIVE"
column average_as_t                      heading "AVERAGE AS|TOTAL"
column average_as                        heading "AVERAGE AS|ACTIVE"
column pga                  format a10   heading "MAX_PGA"                      &_IF_ORA112_OR_HIGHERP.print
column temp                 format a10   heading "MAX_TEMP"                     &_IF_ORA112_OR_HIGHERP.print
column px_send_rec_count                 heading "PX SEND/RECEIVE|COUNT"        &_IF_ORA11_OR_HIGHERP.print
column perc_px_send_rec                  heading "PX SEND/RECEIVE|PERCENT"      &_IF_ORA11_OR_HIGHERP.print
column px_send_rec_cpu_count             heading "PX SEND/RECEIVE|CPU COUNT"    &_IF_ORA11_OR_HIGHERP.print
column perc_px_send_rec_cpu              heading "PX SEND/RECEIVE|CPU PERCENT"  &_IF_ORA11_OR_HIGHERP.print
column px_worker_count                   heading "PX WORKER|COUNT"
column px_worker_unique_count            heading "PX WORKER|UNIQUE COUNT"
column is_sqlid_current     format a7    heading "IS|SQLID|CURRENT"             &_IF_ORA112_OR_HIGHERP.print
column in_connection_mgmt   format a7    heading "IN|CONNECT|MGMT"              &_IF_ORA11_OR_HIGHERP.print
column in_parse             format a7    heading "IN|PARSE"                     &_IF_ORA11_OR_HIGHERP.print
column in_hard_parse        format a7    heading "IN|HARD|PARSE"                &_IF_ORA11_OR_HIGHERP.print
column in_sql_execution     format a7    heading "IN|SQL|EXECUTE"               &_IF_ORA11_OR_HIGHERP.print
column in_plsql_execution   format a7    heading "IN|PLSQL|EXECUTE"             &_IF_ORA11_OR_HIGHERP.print
column in_plsql_rpc         format a7    heading "IN|PLSQL|RPC"                 &_IF_ORA11_OR_HIGHERP.print
column in_plsql_compilation format a7    heading "IN|PLSQL|COMP"                &_IF_ORA11_OR_HIGHERP.print
column in_java_execution    format a7    heading "IN|JAVA|EXECUTE"              &_IF_ORA11_OR_HIGHERP.print
column in_bind              format a7    heading "IN|BIND"                      &_IF_ORA11_OR_HIGHERP.print
column in_cursor_close      format a7    heading "IN|CURSOR|CLOSE"              &_IF_ORA11_OR_HIGHERP.print
column in_sequence_load     format a7    heading "IN|SEQ|LOAD"                  &_IF_ORA112_OR_HIGHERP.print

with /* XPLAN_ASH SQL_STATEMENT_EXECUTION_ASH_SUMMARY_CROSS_INSTANCE SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                  as instance_id
        , cast(sample_time as date)                                                                 as sample_time
        , regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c') as process
        , sql_id
        , case when session_state = 'ON CPU' then 1 else 0 end                                      as is_on_cpu
&_IF_ORA11_OR_HIGHER          , case when sql_plan_operation in ('PX SEND', 'PX RECEIVE') then 1 else 0 end as px_send_receive
&_IF_LOWER_THAN_ORA11         , 0                                                                   as px_send_receive
&_IF_ORA112_OR_HIGHER         , case when is_sqlid_current = 'Y' then 1 else 0 end                  as is_sqlid_current
&_IF_LOWER_THAN_ORA112        , 0                                                                   as is_sqlid_current
&_IF_ORA11_OR_HIGHER          , case when in_connection_mgmt = 'Y' then 1 else 0 end                as in_connection_mgmt
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_connection_mgmt
&_IF_ORA11_OR_HIGHER          , case when in_parse = 'Y' then 1 else 0 end                          as in_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_parse
&_IF_ORA11_OR_HIGHER          , case when in_hard_parse = 'Y' then 1 else 0 end                     as in_hard_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_hard_parse
&_IF_ORA11_OR_HIGHER          , case when in_sql_execution = 'Y' then 1 else 0 end                  as in_sql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_sql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_execution = 'Y' then 1 else 0 end                as in_plsql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_plsql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_rpc = 'Y' then 1 else 0 end                      as in_plsql_rpc
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_plsql_rpc
&_IF_ORA11_OR_HIGHER          , case when in_plsql_compilation = 'Y' then 1 else 0 end              as in_plsql_compilation
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_plsql_compilation
&_IF_ORA11_OR_HIGHER          , case when in_java_execution = 'Y' then 1 else 0 end                 as in_java_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_java_execution
&_IF_ORA11_OR_HIGHER          , case when in_bind = 'Y' then 1 else 0 end                           as in_bind
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_bind
&_IF_ORA11_OR_HIGHER          , case when in_cursor_close = 'Y' then 1 else 0 end                   as in_cursor_close
&_IF_LOWER_THAN_ORA11         , 0                                                                   as in_cursor_close
&_IF_ORA112_OR_HIGHER         , case when in_sequence_load = 'Y' then 1 else 0 end                  as in_sequence_load
&_IF_LOWER_THAN_ORA112        , 0                                                                   as in_sequence_load
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                         as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                  as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq    as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_exec_id
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
  and     to_number(nvl('&ic', '0')) > 1
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
driver as
(
  select
          b.instance_id
        , b.sample_time as timeline
        , b.bucket
  from
          timeline_inst b
),
base_data as
(
  select
          case when count(a.sample_time) > 0 then '&gc3' else ' ' end as act_ind
        , count(a.sample_time) as active_sessions
        , driver.timeline
        , driver.instance_id
  from
          driver
        , ash_base a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.instance_id (+) = driver.instance_id
  group by
          driver.instance_id
        , driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.timeline
),
median_as as
(
  select
          instance_id
        , median(active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
  from
          base_data
  group by
          instance_id
),
bucket_data as
(
  select
          ntile(&tgs) over (partition by instance_id order by timeline) as bucket
        , x.*
  from
          base_data x
          -- In case we have less sample times as size of the Time Active Graph
          -- this here will duplicate the data accordingly
        , (select /*+ cardinality(&duplicator) */ null from dual connect by level <= to_number(trim('&duplicator'))) dups
),
grouped_buckets as
(
  select
          max(act_ind) as act_ind
        , bucket
        , instance_id
  from
          bucket_data
  group by
          instance_id
        , bucket
--  order by
--          instance_id
--        , bucket
),
time_active_graph as
(
  select
          instance_id
&_IF_ORA112_OR_HIGHER         , listagg(act_ind) within group (order by bucket)                        as time_active_graph
          /* leading spaces are trimmed by the XML operation, hence we need to temporarily replace them with something else */
&_IF_LOWER_THAN_ORA112        , replace(extract(xmlagg(xmlelement("V", replace(act_ind, ' ', '?')) order by bucket), '/V/text()').getstringval(), '?', ' ') as time_active_graph
  from
          grouped_buckets
  group by
          instance_id
--  order by
--          instance_id
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into two parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , ash_base ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , ash.instance_id
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    ash_base ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_pga_temp1 as
(
  select
          sum(pga_allocated) as pga_per_bucket
        , sum(temp_space_allocated) as temp_per_bucket
        , bucket
        , instance_id
  from
          ash_data
  group by
          instance_id
        , bucket
),
ash_pga_temp as
(
  select
          max(pga_per_bucket) as pga_mem
        , max(temp_per_bucket) as temp_space
        , instance_id
  from
          ash_pga_temp1
  group by
          instance_id
),
ash_pga_temp_prefmt as
(
  select
          pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                     as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                            as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                               as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                      as power_2_temp_space_mod_10
        , instance_id
  from
          ash_pga_temp
),
ash_pga_temp_fmt as
(
  select
          to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , instance_id
  from
          ash_pga_temp_prefmt
)
select  /* XPLAN_ASH SQL_STATEMENT_EXECUTION_ASH_SUMMARY_CROSS_INSTANCE SQL_ID: &si */
        a.instance_id
      , first_sample
      , last_sample
      , start_active
      , duration_secs_t
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
      , duration_secs
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
      , sample_count
      , process_count
      , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end                                                               as average_as_t
      , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
      , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end                                                              as median_as
      , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end                                                              as stddev_as
      , lpad(pt.pga_mem_format, 10)                                                                                                                     as pga
      , lpad(pt.temp_space_format, 10)                                                                                                                  as temp
      , px_send_receive_count                                                                                                                           as px_send_rec_count
      , round(px_send_receive_count / nullif(sample_count, 0) * 100)                                                                                    as perc_px_send_rec
      , px_send_receive_on_cpu_count                                                                                                                    as px_send_rec_cpu_count
      , round(px_send_receive_on_cpu_count / nullif(cpu_sample_count, 0) * 100)                                                                         as perc_px_send_rec_cpu
      --, substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc3', round(duration_secs / to_number('&ds') * &tgs), '&gc3'), 1, &tgs) as time_active_graph
      , t.time_active_graph
      , lpad(to_char(round(is_sqlid_current / sample_count * 100), 'TM'), 6) || '%'                                                                     as is_sqlid_current
      , lpad(to_char(round(in_connection_mgmt / sample_count * 100), 'TM'), 6) || '%'                                                                   as in_connection_mgmt
      , lpad(to_char(round(in_parse / sample_count * 100), 'TM'), 6) || '%'                                                                             as in_parse
      , lpad(to_char(round(in_hard_parse / sample_count * 100), 'TM'), 6) || '%'                                                                        as in_hard_parse
      , lpad(to_char(round(in_sql_execution / sample_count * 100), 'TM'), 6) || '%'                                                                     as in_sql_execution
      , lpad(to_char(round(in_plsql_execution / sample_count * 100), 'TM'), 6) || '%'                                                                   as in_plsql_execution
      , lpad(to_char(round(in_plsql_rpc / sample_count * 100), 'TM'), 6) || '%'                                                                         as in_plsql_rpc
      , lpad(to_char(round(in_plsql_compilation / sample_count * 100), 'TM'), 6) || '%'                                                                 as in_plsql_compilation
      , lpad(to_char(round(in_java_execution / sample_count * 100), 'TM'), 6) || '%'                                                                    as in_java_execution
      , lpad(to_char(round(in_bind / sample_count * 100), 'TM'), 6) || '%'                                                                              as in_bind
      , lpad(to_char(round(in_cursor_close / sample_count * 100), 'TM'), 6) || '%'                                                                      as in_cursor_close
      , lpad(to_char(round(in_sequence_load / sample_count * 100), 'TM'), 6) || '%'                                                                     as in_sequence_load
from
        (
          select
                  instance_id
                , to_char(min(sample_time), '&dm')                                                                     as first_sample
                , to_char(max(sample_time), '&dm')                                                                     as last_sample
                , min(ash_bucket) + &sample_freq                                                                       as start_active
                , round(max(ash_bucket) - min(ash_bucket) + &sample_freq)                                              as duration_secs_t
                , count(distinct ash_bucket) * &sample_freq                                                            as duration_secs
                , count(*)                                                                                             as sample_count
                , count(distinct process)                                                                              as process_count
                , round(count(*) / nullif((max(ash_bucket) - min(ash_bucket) + &sample_freq) / &sample_freq, 0), 1)    as average_as_t
                , round(count(*) / nullif(count(distinct ash_bucket), 0), 1)                                           as average_as
                , sum(is_on_cpu)                                                                                       as cpu_sample_count
                , sum(px_send_receive)                                                                                 as px_send_receive_count
                , sum(case when px_send_receive = 1 and is_on_cpu = 1 then 1 else 0 end)                               as px_send_receive_on_cpu_count
                , sum(is_sqlid_current)                                                                                as is_sqlid_current
                , sum(in_connection_mgmt)                                                                              as in_connection_mgmt
                , sum(in_parse)                                                                                        as in_parse
                , sum(in_hard_parse)                                                                                   as in_hard_parse
                , sum(in_sql_execution)                                                                                as in_sql_execution
                , sum(in_plsql_execution)                                                                              as in_plsql_execution
                , sum(in_plsql_rpc)                                                                                    as in_plsql_rpc
                , sum(in_plsql_compilation)                                                                            as in_plsql_compilation
                , sum(in_java_execution)                                                                               as in_java_execution
                , sum(in_bind)                                                                                         as in_bind
                , sum(in_cursor_close)                                                                                 as in_cursor_close
                , sum(in_sequence_load)                                                                                as in_sequence_load
          from
                  (
                    select
                           a.*
                         , min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) over () as min_sql_exec_start
                    from
                           ash_base a
                  )
          where
                  (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
          and     to_number(nvl('&ic', '0')) > 1
          group by
                  instance_id
                , min_sql_exec_start
        ) a
      , ash_pga_temp_fmt pt
      , time_active_graph t
      , median_as m
where
        a.instance_id = pt.instance_id
and     a.instance_id = t.instance_id
and     a.instance_id = m.instance_id
order by
        a.instance_id
;

column first_sample          clear
column last_sample           clear
column time_active_graph     clear
column pga                   clear
column temp                  clear
column duration_secs_t       clear
column duration_t            clear
column duration_secs         clear
column duration              clear
column average_as_t          clear
column average_as            clear
column px_send_rec_count     clear
column perc_px_send_rec      clear
column px_send_rec_cpu_count clear
column perc_px_send_rec_cpu  clear

column is_sqlid_current      clear
column in_connection_mgmt    clear
column in_parse              clear
column in_hard_parse         clear
column in_sql_execution      clear
column in_plsql_execution    clear
column in_plsql_rpc          clear
column in_plsql_compilation  clear
column in_java_execution     clear
column in_bind               clear
column in_cursor_close       clear
column in_sequence_load      clear

column px_worker_count       clear
column px_worker_unique_count clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Summary of this sessions'' other activity' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

/* Summary information of other activity for the same session (e.g. recursive SQL, other cursors) during execution of main SQL based on ASH */

column instance_id &_IF_CROSS_INSTANCE.print null "GLOBAL"
column sample_count new_value ca_sc
column duration_secs_t                heading "DURATION SECS|TOTAL"
column duration_t                     heading "DURATION|TOTAL"
column duration_secs                  heading "DURATION SECS|ACTIVE"
column duration                       heading "DURATION|ACTIVE"
column average_as_t                   heading "AVERAGE AS|TOTAL"
column average_as                     heading "AVERAGE AS|ACTIVE"
--column pga               format a10 heading "MAX_PGA"  &_IF_ORA112_OR_HIGHERP.print
--column temp              format a10 heading "MAX_TEMP" &_IF_ORA112_OR_HIGHERP.print
-- For the time being, do not print PGA/TEMP as it is more confusing that helpful if you don't know on what it is based
column pga               format a10   heading "MAX_PGA"  noprint
column temp              format a10   heading "MAX_TEMP" noprint
column px_worker_count                heading "PX WORKER|COUNT"
column px_worker_unique_count         heading "PX WORKER|UNIQUE COUNT"
column is_sqlid_current     format a7 heading "IS|SQLID|CURRENT" &_IF_ORA112_OR_HIGHERP.print
column in_connection_mgmt   format a7 heading "IN|CONNECT|MGMT"  &_IF_ORA11_OR_HIGHERP.print
column in_parse             format a7 heading "IN|PARSE"         &_IF_ORA11_OR_HIGHERP.print
column in_hard_parse        format a7 heading "IN|HARD|PARSE"    &_IF_ORA11_OR_HIGHERP.print
column in_sql_execution     format a7 heading "IN|SQL|EXECUTE"   &_IF_ORA11_OR_HIGHERP.print
column in_plsql_execution   format a7 heading "IN|PLSQL|EXECUTE" &_IF_ORA11_OR_HIGHERP.print
column in_plsql_rpc         format a7 heading "IN|PLSQL|RPC"     &_IF_ORA11_OR_HIGHERP.print
column in_plsql_compilation format a7 heading "IN|PLSQL|COMP"    &_IF_ORA11_OR_HIGHERP.print
column in_java_execution    format a7 heading "IN|JAVA|EXECUTE"  &_IF_ORA11_OR_HIGHERP.print
column in_bind              format a7 heading "IN|BIND"          &_IF_ORA11_OR_HIGHERP.print
column in_cursor_close      format a7 heading "IN|CURSOR|CLOSE"  &_IF_ORA11_OR_HIGHERP.print
column in_sequence_load     format a7 heading "IN|SEQ|LOAD"      &_IF_ORA112_OR_HIGHERP.print

with /* XPLAN_ASH ASH_SESSION_SUMMARY_OTHER_ACTIVITY SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                 as instance_id
        , cast(sample_time as date)                                                                as sample_time
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
ash_base_other as
(
  select
          &inst_id as instance_id
        , cast(sample_time as date)                                                                 as sample_time
        , sql_id
        , case
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- when regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1) is null
          when regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') != 1
          then null
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- else &inst_id || '-' || regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1)
          else &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')
          end                                                                                       as process
        , case when session_state = 'ON CPU' then 1 else 0 end                                      as is_on_cpu
        , coalesce(program, 'NULL')                                                                 as program
        , session_id
        , session_serial#
        , xid
&_IF_ORA11_OR_HIGHER          , sql_id || '|' || to_char(ash.sql_exec_start, 'DD.MM.YYYY HH24:MI:SS') || '|' || to_char(sql_exec_id, 'TM') as sql_exec_unique
        , module
        , action
&_IF_ORA112_OR_HIGHER         , case when is_sqlid_current = 'Y' then 1 else 0 end                                                                               as is_sqlid_current
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as is_sqlid_current
&_IF_ORA11_OR_HIGHER          , case when in_connection_mgmt = 'Y' then 1 else 0 end                                                                             as in_connection_mgmt
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_connection_mgmt
&_IF_ORA11_OR_HIGHER          , case when in_parse = 'Y' then 1 else 0 end                                                                                       as in_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_parse
&_IF_ORA11_OR_HIGHER          , case when in_hard_parse = 'Y' then 1 else 0 end                                                                                  as in_hard_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_hard_parse
&_IF_ORA11_OR_HIGHER          , case when in_sql_execution = 'Y' then 1 else 0 end                                                                               as in_sql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_sql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_execution = 'Y' then 1 else 0 end                                                                             as in_plsql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_rpc = 'Y' then 1 else 0 end                                                                                   as in_plsql_rpc
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_rpc
&_IF_ORA11_OR_HIGHER          , case when in_plsql_compilation = 'Y' then 1 else 0 end                                                                           as in_plsql_compilation
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_compilation
&_IF_ORA11_OR_HIGHER          , case when in_java_execution = 'Y' then 1 else 0 end                                                                              as in_java_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_java_execution
&_IF_ORA11_OR_HIGHER          , case when in_bind = 'Y' then 1 else 0 end                                                                                        as in_bind
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_bind
&_IF_ORA11_OR_HIGHER          , case when in_cursor_close = 'Y' then 1 else 0 end                                                                                as in_cursor_close
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_cursor_close
&_IF_ORA112_OR_HIGHER         , case when in_sequence_load = 'Y' then 1 else 0 end                                                                               as in_sequence_load
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as in_sequence_load
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                         as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                  as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                           as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                                                                  as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , ash.sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_exec_id
  from
          &global_ash ash
        , dates
  where
          (lnnvl(sql_id = '&si') and &ash_pred1 &ash_pred2)
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
  and     &inst_id in
          (
            select
                    distinct
                    &inst_id
            from
                    &global_ash ash
            where
                    sql_id = '&si'
&_IF_ORA11_OR_HIGHER                      and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
            and     &ash_pred1 &ash_pred2
            and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g            and     (event is null or event != 'PX Deq Credit: send blkd')
          )
),
driver as
(
  select
          b.instance_id
        , b.sample_time as timeline
        , b.bucket
  from
          timeline_inst b
),
base_data as
(
  select
          count(a.sample_time) as active_sessions
        , driver.timeline
        , decode(grouping(driver.instance_id), 1, -1, driver.instance_id) as instance_id
  from
          driver
        , ash_base_other a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.instance_id (+) = driver.instance_id
  group by
&_IS_SINGL_INSTANCE          driver.instance_id
&_IS_CROSS_INSTANCE          grouping sets(driver.instance_id, ())
        , driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.timeline
),
median_as as
(
  select
          instance_id
        , median(active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
  from
          base_data
  group by
          instance_id
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into two parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , ash_base_other ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , ash.instance_id
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    ash_base_other ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_pga_temp1 as
(
  select
          sum(pga_allocated) as pga_per_bucket
        , sum(temp_space_allocated) as temp_per_bucket
        , bucket
        , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
  from
          ash_data
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , bucket
),
ash_pga_temp as
(
  select
          max(pga_per_bucket) as pga_mem
        , max(temp_per_bucket) as temp_space
        , instance_id
  from
          ash_pga_temp1
  group by
          instance_id
),
ash_pga_temp_prefmt as
(
  select
          pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                     as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                            as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                               as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                      as power_2_temp_space_mod_10
        , instance_id
  from
          ash_pga_temp
),
ash_pga_temp_fmt as
(
  select
          to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , instance_id
  from
          ash_pga_temp_prefmt
)
select  /* XPLAN_ASH ASH_SESSION_SUMMARY_OTHER_ACTIVITY SQL_ID: &si */
        nullif(a.instance_id, -1) as instance_id
      , duration_secs_t
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
      , duration_secs
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / sample_count * 100)                                      as percentage_cpu
      , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end as average_as_t
      , case when average_as >= &rnd_thr then round(average_as) else average_as end       as average_as
      , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end as median_as
      , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end as stddev_as
      , lpad(ash_pga_temp_fmt.pga_mem_format, 10)                                         as pga
      , lpad(ash_pga_temp_fmt.temp_space_format, 10)                                      as temp
      , slave_count                                                                       as px_worker_count
      , slave_unique_count                                                                as px_worker_unique_count
      , process_count
      , transact_count
      , sql_id_count
&_IF_ORA11_OR_HIGHER        , sql_execution_count
      , module_count
      , action_count
      , lpad(to_char(round(is_sqlid_current / sample_count * 100), 'TM'), 6) || '%'       as is_sqlid_current
      , lpad(to_char(round(in_connection_mgmt / sample_count * 100), 'TM'), 6) || '%'     as in_connection_mgmt
      , lpad(to_char(round(in_parse / sample_count * 100), 'TM'), 6) || '%'               as in_parse
      , lpad(to_char(round(in_hard_parse / sample_count * 100), 'TM'), 6) || '%'          as in_hard_parse
      , lpad(to_char(round(in_sql_execution / sample_count * 100), 'TM'), 6) || '%'       as in_sql_execution
      , lpad(to_char(round(in_plsql_execution / sample_count * 100), 'TM'), 6) || '%'     as in_plsql_execution
      , lpad(to_char(round(in_plsql_rpc / sample_count * 100), 'TM'), 6) || '%'           as in_plsql_rpc
      , lpad(to_char(round(in_plsql_compilation / sample_count * 100), 'TM'), 6) || '%'   as in_plsql_compilation
      , lpad(to_char(round(in_java_execution / sample_count * 100), 'TM'), 6) || '%'      as in_java_execution
      , lpad(to_char(round(in_bind / sample_count * 100), 'TM'), 6) || '%'                as in_bind
      , lpad(to_char(round(in_cursor_close / sample_count * 100), 'TM'), 6) || '%'        as in_cursor_close
      , lpad(to_char(round(in_sequence_load / sample_count * 100), 'TM'), 6) || '%'       as in_sequence_load
from
        (
          select
                  decode(grouping(a.instance_id), 1, -1, a.instance_id)                                                as instance_id
                , count(*)                                                                                             as sample_count
                , round(max(ash_bucket) - min(ash_bucket) + &sample_freq)                                              as duration_secs_t
                , count(distinct ash_bucket) * &sample_freq                                                            as duration_secs
                , round(count(*) / nullif(cast(to_number('&ds') as number), 0) * &sample_freq, 1)                      as average_as_t
                --, count(*) / (((b.max_sample_time - b.min_sample_time) * 86400) + &sample_freq) * &sample_freq as average_as
                --, round(count(*) / nullif(coalesce(to_number(trim('&dist_sample_count')), 0), 0), 1) as average_as
                , round(count(*) / nullif(count(distinct ash_bucket), 0), 1)                                           as average_as
                -- This can be used if getting dist_sample_count causes problems on 11.2.0.1 above
                --, round(count(*) / nullif(round(cast(to_number('&ds') as number) / &sample_freq), 0), 1) as average_as
                , sum(is_on_cpu)                                                                                       as cpu_sample_count
                , count(distinct process)                                                                              as slave_count
                , count(distinct case when process is not null then process || '-' || session_id || '-' || session_serial# end) as slave_unique_count
                , count(distinct program)                                                                              as process_count
                , count(distinct xid)                                                                                  as transact_count
                , count(distinct coalesce(sql_id, 'NULL'))                                                           as sql_id_count
&_IF_ORA11_OR_HIGHER                  , count(distinct sql_exec_unique)                                                                      as sql_execution_count
                , count(distinct module)                                                                               as module_count
                , count(distinct action)                                                                               as action_count
                , sum(is_sqlid_current)                                                                                as is_sqlid_current
                , sum(in_connection_mgmt)                                                                              as in_connection_mgmt
                , sum(in_parse)                                                                                        as in_parse
                , sum(in_hard_parse)                                                                                   as in_hard_parse
                , sum(in_sql_execution)                                                                                as in_sql_execution
                , sum(in_plsql_execution)                                                                              as in_plsql_execution
                , sum(in_plsql_rpc)                                                                                    as in_plsql_rpc
                , sum(in_plsql_compilation)                                                                            as in_plsql_compilation
                , sum(in_java_execution)                                                                               as in_java_execution
                , sum(in_bind)                                                                                         as in_bind
                , sum(in_cursor_close)                                                                                 as in_cursor_close
                , sum(in_sequence_load)                                                                                as in_sequence_load
          from
                  ash_base_other a
          where
                  instr('&op', 'ASH') > 0
          -- This prevents the aggregate functions to produce a single row
          -- in case of no rows generated to aggregate
          group by
&_IS_SINGL_INSTANCE          a.instance_id
&_IS_CROSS_INSTANCE          grouping sets(a.instance_id, ())
        ) a
      , ash_pga_temp_fmt
      , median_as m
where
        a.instance_id = ash_pga_temp_fmt.instance_id
and     a.instance_id = m.instance_id
order by
        instance_id nulls first
;

column instance_id          clear
column sample_count         clear
column pga                  clear
column temp                 clear

column duration_secs_t      clear
column duration_t           clear
column duration_secs        clear
column duration             clear
column average_as_t         clear
column average_as           clear

column is_sqlid_current     clear
column in_connection_mgmt   clear
column in_parse             clear
column in_hard_parse        clear
column in_sql_execution     clear
column in_plsql_execution   clear
column in_plsql_rpc         clear
column in_plsql_compilation clear
column in_java_execution    clear
column in_bind              clear
column in_cursor_close      clear
column in_sequence_load     clear

column px_worker_count      clear
column px_worker_unique_count clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is null
---------
union all
---------
select
        'No other activity detected' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is null
;

column message clear

set heading on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is not null
---------
union all
---------
select
        'Other activity details' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is not null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is not null
;

column message clear

set heading on

/* Detailed information on this session's other activity based on ASH */

column first_sample      format a19
column last_sample       format a19
column time_active_graph format a&tgs
column duration_secs_t                heading "DURATION SECS|TOTAL"
column duration_t                     heading "DURATION|TOTAL"
column duration_secs                  heading "DURATION SECS|ACTIVE"
column duration                       heading "DURATION|ACTIVE"
column average_as_t                   heading "AVERAGE AS|TOTAL"
column average_as                     heading "AVERAGE AS|ACTIVE"
--column pga               format a10 heading "MAX_PGA"  &_IF_ORA112_OR_HIGHERP.print
--column temp              format a10 heading "MAX_TEMP" &_IF_ORA112_OR_HIGHERP.print
-- For the time being, do not print PGA/TEMP as it is more confusing that helpful if you don't know what it is based on
column pga               format a10   heading "MAX_PGA"  noprint
column temp              format a10   heading "MAX_TEMP" noprint
column px_worker_count                heading "PX WORKER|COUNT"
column px_worker_unique_count         heading "PX WORKER|UNIQUE COUNT"
column instance_id       &_IF_CROSS_INSTANCE.print null "GLOBAL"
column is_sqlid_current     format a7 heading "IS|SQLID|CURRENT" &_IF_ORA112_OR_HIGHERP.print
column in_connection_mgmt   format a7 heading "IN|CONNECT|MGMT"  &_IF_ORA11_OR_HIGHERP.print
column in_parse             format a7 heading "IN|PARSE"         &_IF_ORA11_OR_HIGHERP.print
column in_hard_parse        format a7 heading "IN|HARD|PARSE"    &_IF_ORA11_OR_HIGHERP.print
column in_sql_execution     format a7 heading "IN|SQL|EXECUTE"   &_IF_ORA11_OR_HIGHERP.print
column in_plsql_execution   format a7 heading "IN|PLSQL|EXECUTE" &_IF_ORA11_OR_HIGHERP.print
column in_plsql_rpc         format a7 heading "IN|PLSQL|RPC"     &_IF_ORA11_OR_HIGHERP.print
column in_plsql_compilation format a7 heading "IN|PLSQL|COMP"    &_IF_ORA11_OR_HIGHERP.print
column in_java_execution    format a7 heading "IN|JAVA|EXECUTE"  &_IF_ORA11_OR_HIGHERP.print
column in_bind              format a7 heading "IN|BIND"          &_IF_ORA11_OR_HIGHERP.print
column in_cursor_close      format a7 heading "IN|CURSOR|CLOSE"  &_IF_ORA11_OR_HIGHERP.print
column in_sequence_load     format a7 heading "IN|SEQ|LOAD"      &_IF_ORA112_OR_HIGHERP.print
column top_level_sql_id     format a16 heading "TOP_LEVEL_SQL_ID" &_IF_ORA11_OR_HIGHERP.print

break on instance_id

with /* XPLAN_ASH ASH_SESSION_DETAILS_OTHER_ACTIVITY SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                 as instance_id
        , cast(sample_time as date)                                                                as sample_time
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     '&ca_sc' is not null
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
ash_base_other as
(
  select
          &inst_id as instance_id
        , cast(sample_time as date)                                                                                                                               as sample_time
        , coalesce(sql_id, 'NULL')                                                                                                                              as sql_id
        , case
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- when regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1) is null
          when regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') != 1
          then null
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- else &inst_id || '-' || regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1)
          else &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')
          end                                                                                                                                                    as process
        , session_id
        , session_serial#
        , case when session_state = 'ON CPU' then 1 else 0 end                                                                                                   as is_on_cpu
&_IF_ORA11_OR_HIGHER          , top_level_sql_id
&_IF_ORA112_OR_HIGHER         , case when is_sqlid_current = 'Y' then 1 else 0 end                                                                               as is_sqlid_current
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as is_sqlid_current
&_IF_ORA11_OR_HIGHER          , case when in_connection_mgmt = 'Y' then 1 else 0 end                                                                             as in_connection_mgmt
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_connection_mgmt
&_IF_ORA11_OR_HIGHER          , case when in_parse = 'Y' then 1 else 0 end                                                                                       as in_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_parse
&_IF_ORA11_OR_HIGHER          , case when in_hard_parse = 'Y' then 1 else 0 end                                                                                  as in_hard_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_hard_parse
&_IF_ORA11_OR_HIGHER          , case when in_sql_execution = 'Y' then 1 else 0 end                                                                               as in_sql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_sql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_execution = 'Y' then 1 else 0 end                                                                             as in_plsql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_rpc = 'Y' then 1 else 0 end                                                                                   as in_plsql_rpc
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_rpc
&_IF_ORA11_OR_HIGHER          , case when in_plsql_compilation = 'Y' then 1 else 0 end                                                                           as in_plsql_compilation
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_compilation
&_IF_ORA11_OR_HIGHER          , case when in_java_execution = 'Y' then 1 else 0 end                                                                              as in_java_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_java_execution
&_IF_ORA11_OR_HIGHER          , case when in_bind = 'Y' then 1 else 0 end                                                                                        as in_bind
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_bind
&_IF_ORA11_OR_HIGHER          , case when in_cursor_close = 'Y' then 1 else 0 end                                                                                as in_cursor_close
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_cursor_close
&_IF_ORA112_OR_HIGHER         , case when in_sequence_load = 'Y' then 1 else 0 end                                                                               as in_sequence_load
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as in_sequence_load
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                         as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null)                                                                                                                  as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                  as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null)                                                                                                                  as temp_space_allocated
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                           as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                                                                  as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , ash.sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_exec_id
  from
          &global_ash ash
        , dates
  where
          (lnnvl(sql_id = '&si') and &ash_pred1 &ash_pred2)
  and     '&ca_sc' is not null
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
  and     &inst_id in
          (
            select
                    distinct
                    &inst_id
            from
                    &global_ash ash
            where
                    sql_id = '&si'
&_IF_ORA11_OR_HIGHER                      and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
            and     &ash_pred1 &ash_pred2
            and     '&ca_sc' is not null
            and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g            and     (event is null or event != 'PX Deq Credit: send blkd')
          )
),
driver as
(
  select
          b.instance_id
        , ash_sql_ids.sql_id
        , b.sample_time as timeline
        , b.bucket
  from
          timeline_inst b, (select distinct sql_id from ash_base_other) ash_sql_ids
),
base_data as
(
  select
          case when count(a.sample_time) > 0 then '&gc3' else ' ' end as act_ind
        , count(a.sample_time) as active_sessions
        , driver.sql_id
        , driver.timeline
        , decode(grouping(driver.instance_id), 1, -1, driver.instance_id) as instance_id
  from
          driver
        , ash_base_other a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.instance_id (+) = driver.instance_id
  and     a.sql_id (+) = driver.sql_id
  group by
&_IS_SINGL_INSTANCE          driver.instance_id
&_IS_CROSS_INSTANCE          grouping sets(driver.instance_id, ())
        , driver.sql_id
        , driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.timeline
),
bucket_data as
(
  select
          ntile(&tgs) over (partition by instance_id, sql_id order by timeline) as bucket
        , x.*
  from
          base_data x
          -- In case we have less sample times as size of the Time Active Graph
          -- this here will duplicate the data accordingly
        , (select /*+ cardinality(&duplicator) */ null from dual connect by level <= to_number(trim('&duplicator'))) dups
),
grouped_buckets as
(
  select
          max(act_ind) as act_ind
        , bucket
        , instance_id
        , sql_id
  from
          bucket_data
  group by
          instance_id
        , sql_id
        , bucket
--  order by
--          instance_id
--        , bucket
),
time_active_graph as
(
  select
          instance_id
        , sql_id
&_IF_ORA112_OR_HIGHER         , listagg(act_ind) within group (order by bucket)                        as time_active_graph
          /* leading spaces are trimmed by the XML operation, hence we need to temporarily replace them with something else */
&_IF_LOWER_THAN_ORA112        , replace(extract(xmlagg(xmlelement("V", replace(act_ind, ' ', '?')) order by bucket), '/V/text()').getstringval(), '?', ' ') as time_active_graph
  from
          grouped_buckets
  group by
          instance_id
        , sql_id
--  order by
--          instance_id
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into two parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.sql_id
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , ash_base_other ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.sql_id
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , ash.instance_id
                  , ash.sql_id
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    ash_base_other ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_pga_temp1 as
(
  select
          sum(pga_allocated) as pga_per_bucket
        , sum(temp_space_allocated) as temp_per_bucket
        , bucket
        , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
        , sql_id
  from
          ash_data
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , sql_id
        , bucket
),
ash_pga_temp as
(
  select
          max(pga_per_bucket) as pga_mem
        , max(temp_per_bucket) as temp_space
        , instance_id
        , sql_id
  from
          ash_pga_temp1
  group by
          instance_id
        , sql_id
),
ash_pga_temp_prefmt as
(
  select
          pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                     as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                            as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                               as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                      as power_2_temp_space_mod_10
        , instance_id
        , sql_id
  from
          ash_pga_temp
),
ash_pga_temp_fmt as
(
  select
          to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , instance_id
        , sql_id
  from
          ash_pga_temp_prefmt
),
median_as as
(
  select
          instance_id
        , sql_id
        , median(active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
  from
          (
            select
                    sample_time
                  , sql_id
                  , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
                  , count(*) as active_sessions
            from
                    ash_base_other
            group by
                    sample_time
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
                  , sql_id
          )
  group by
          instance_id
        , sql_id
)
select  /* XPLAN_ASH ASH_SESSION_DETAILS_OTHER_ACTIVITY SQL_ID: &si */
        nullif(a.instance_id, -1)                                                                                                                       as instance_id
      , a.sql_id
      , coalesce(sql.sql_text, '<No SQL TEXT found>')                                                                                                   as sql_text
&_IF_ORA11_OR_HIGHER                  , a.top_level_sql_id
      , first_sample
      , last_sample
      , start_active
      , duration_secs_t
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
      , duration_secs
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / sample_count * 100)                                                                                                    as percentage_cpu
      , slave_count                                                                                                                                     as px_worker_count
      , slave_unique_count                                                                                                                              as px_worker_unique_count
      , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end                                                               as average_as_t
      , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
      , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end                                                              as median_as
      , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end                                                              as stddev_as
      , lpad(pt.pga_mem_format, 10)                                                                                                                     as pga
      , lpad(pt.temp_space_format, 10)                                                                                                                  as temp
      --, substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc3', round(duration_secs / to_number('&ds') * &tgs), '&gc3'), 1, &tgs) as time_active_graph
      , t.time_active_graph
      , lpad(to_char(round(is_sqlid_current / sample_count * 100), 'TM'), 6) || '%'                                                                     as is_sqlid_current
      , lpad(to_char(round(in_connection_mgmt / sample_count * 100), 'TM'), 6) || '%'                                                                   as in_connection_mgmt
      , lpad(to_char(round(in_parse / sample_count * 100), 'TM'), 6) || '%'                                                                             as in_parse
      , lpad(to_char(round(in_hard_parse / sample_count * 100), 'TM'), 6) || '%'                                                                        as in_hard_parse
      , lpad(to_char(round(in_sql_execution / sample_count * 100), 'TM'), 6) || '%'                                                                     as in_sql_execution
      , lpad(to_char(round(in_plsql_execution / sample_count * 100), 'TM'), 6) || '%'                                                                   as in_plsql_execution
      , lpad(to_char(round(in_plsql_rpc / sample_count * 100), 'TM'), 6) || '%'                                                                         as in_plsql_rpc
      , lpad(to_char(round(in_plsql_compilation / sample_count * 100), 'TM'), 6) || '%'                                                                 as in_plsql_compilation
      , lpad(to_char(round(in_java_execution / sample_count * 100), 'TM'), 6) || '%'                                                                    as in_java_execution
      , lpad(to_char(round(in_bind / sample_count * 100), 'TM'), 6) || '%'                                                                              as in_bind
      , lpad(to_char(round(in_cursor_close / sample_count * 100), 'TM'), 6) || '%'                                                                      as in_cursor_close
      , lpad(to_char(round(in_sequence_load / sample_count * 100), 'TM'), 6) || '%'                                                                     as in_sequence_load
from
        (
          select
                  decode(grouping(instance_id), 1, -1, instance_id)                                                    as instance_id
                , min(instance_id)                                                                                     as min_instance_id
                , sql_id
                , to_char(min(sample_time), '&dm')                                                                     as first_sample
                , to_char(max(sample_time), '&dm')                                                                     as last_sample
                , round(min(ash_bucket) + &sample_freq)                                                                as start_active
                , round(max(ash_bucket) - min(ash_bucket) + &sample_freq)                                              as duration_secs_t
                , count(distinct ash_bucket) * &sample_freq                                                            as duration_secs
                , count(*)                                                                                             as sample_count
                , count(distinct process)                                                                              as slave_count
                , count(distinct case when process is not null then process || '-' || session_id || '-' || session_serial# end) as slave_unique_count
                , sum(is_on_cpu)                                                                                       as cpu_sample_count
                , round(count(*) / nullif((max(ash_bucket) - min(ash_bucket) + &sample_freq) / &sample_freq, 0), 1)    as average_as_t
                , round(count(*) / nullif(count(distinct ash_bucket), 0), 1)                                           as average_as
&_IF_ORA11_OR_HIGHER                  , nvl(max(top_level_sql_id), 'NULL')                                                                    as top_level_sql_id
                , sum(is_sqlid_current)                                                                                as is_sqlid_current
                , sum(in_connection_mgmt)                                                                              as in_connection_mgmt
                , sum(in_parse)                                                                                        as in_parse
                , sum(in_hard_parse)                                                                                   as in_hard_parse
                , sum(in_sql_execution)                                                                                as in_sql_execution
                , sum(in_plsql_execution)                                                                              as in_plsql_execution
                , sum(in_plsql_rpc)                                                                                    as in_plsql_rpc
                , sum(in_plsql_compilation)                                                                            as in_plsql_compilation
                , sum(in_java_execution)                                                                               as in_java_execution
                , sum(in_bind)                                                                                         as in_bind
                , sum(in_cursor_close)                                                                                 as in_cursor_close
                , sum(in_sequence_load)                                                                                as in_sequence_load
          from
                  ash_base_other a
                , dates
          where
                  (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
          and     '&ca_sc' is not null
          group by
&_IS_SINGL_INSTANCE                  instance_id
&_IS_CROSS_INSTANCE                  grouping sets(instance_id, ())
                , sql_id
                , dates.sql_exec_start
        ) a
      , ash_pga_temp_fmt pt
      , time_active_graph t
      , median_as m
      , (
          select
                  sql_id
                , &sqltext_join_col
                , cast(substr(sql_text, 1, 80) as varchar2(80)) as sql_text
          from
                  &sqltext p
          --where
          --        &third_id_sqltext
        ) sql
where
        a.sql_id = pt.sql_id
and     a.instance_id = pt.instance_id
and     a.sql_id = t.sql_id
and     a.instance_id = t.instance_id
and     a.sql_id = m.sql_id
and     a.instance_id = m.instance_id
and     a.sql_id = sql.sql_id (+)
and     &sqltext_join
order by
        instance_id nulls first
      , a.sample_count desc
;

column first_sample         clear
column last_sample          clear
column time_active_graph    clear
column pga                  clear
column temp                 clear
column instance_id          clear

column duration_secs_t      clear
column duration_t           clear
column duration_secs        clear
column duration             clear
column average_as_t         clear
column average_as           clear

column is_sqlid_current     clear
column in_connection_mgmt   clear
column in_parse             clear
column in_hard_parse        clear
column in_sql_execution     clear
column in_plsql_execution   clear
column in_plsql_rpc         clear
column in_plsql_compilation clear
column in_java_execution    clear
column in_bind              clear
column in_cursor_close      clear
column in_sequence_load     clear

column px_worker_count      clear
column px_worker_unique_count clear
column top_level_sql_id     clear

clear breaks

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
---------
union all
---------
select
        'Global ASH Summary for concurrent activity' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
;

column message clear

set heading on

/* Summary information for concurrent activity based on ASH */

define ca_sc = ""

column instance_id &_IF_CROSS_INSTANCE.print null "GLOBAL"
column sample_count new_value ca_sc
column average_as_t                    heading "AVERAGE AS|TOTAL"
column average_as                      heading "AVERAGE AS|ACTIVE"
column px_worker_count                 heading "PX WORKER|COUNT"
column px_worker_unique_count          heading "PX WORKER|UNIQUE COUNT"
column pga                  format a10 heading "MAX_PGA"          &_IF_ORA112_OR_HIGHERP.print
column temp                 format a10 heading "MAX_TEMP"         &_IF_ORA112_OR_HIGHERP.print
column is_sqlid_current     format a7  heading "IS|SQLID|CURRENT" &_IF_ORA112_OR_HIGHERP.print
column in_connection_mgmt   format a7  heading "IN|CONNECT|MGMT"  &_IF_ORA11_OR_HIGHERP.print
column in_parse             format a7  heading "IN|PARSE"         &_IF_ORA11_OR_HIGHERP.print
column in_hard_parse        format a7  heading "IN|HARD|PARSE"    &_IF_ORA11_OR_HIGHERP.print
column in_sql_execution     format a7  heading "IN|SQL|EXECUTE"   &_IF_ORA11_OR_HIGHERP.print
column in_plsql_execution   format a7  heading "IN|PLSQL|EXECUTE" &_IF_ORA11_OR_HIGHERP.print
column in_plsql_rpc         format a7  heading "IN|PLSQL|RPC"     &_IF_ORA11_OR_HIGHERP.print
column in_plsql_compilation format a7  heading "IN|PLSQL|COMP"    &_IF_ORA11_OR_HIGHERP.print
column in_java_execution    format a7  heading "IN|JAVA|EXECUTE"  &_IF_ORA11_OR_HIGHERP.print
column in_bind              format a7  heading "IN|BIND"          &_IF_ORA11_OR_HIGHERP.print
column in_cursor_close      format a7  heading "IN|CURSOR|CLOSE"  &_IF_ORA11_OR_HIGHERP.print
column in_sequence_load     format a7  heading "IN|SEQ|LOAD"      &_IF_ORA112_OR_HIGHERP.print

with /* XPLAN_ASH GLOBAL_ASH_SUMMARY_CONCURRENT_EXECUTION SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                 as instance_id
        , cast(sample_time as date)                                                                as sample_time
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     instr('&op', 'ASH') > 0
  and     instr('&op', 'LIMITED_ASH') = 0
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
ash_base_conc as
(
  select
          &inst_id as instance_id
        , cast(sample_time as date)                                                                                                              as sample_time
        , sql_id
        , case
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- when regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1) is null
          when regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') != 1 or session_type != 'FOREGROUND' or program is null
          then null
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- else &inst_id || '-' || regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1)
          else &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')
          end                                                                                                                                                    as process
        , session_id
        , session_serial#
        , case when session_state = 'ON CPU' then 1 else 0 end                                                                                                   as is_on_cpu
        , case when session_type = 'FOREGROUND' then 1 else null end                                                                                             as is_foreground
        , case when session_type = 'BACKGROUND' then 1 else null end                                                                                             as is_background
&_IF_ORA112_OR_HIGHER         , case when is_sqlid_current = 'Y' then 1 else 0 end                                                                               as is_sqlid_current
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as is_sqlid_current
&_IF_ORA11_OR_HIGHER          , case when in_connection_mgmt = 'Y' then 1 else 0 end                                                                             as in_connection_mgmt
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_connection_mgmt
&_IF_ORA11_OR_HIGHER          , case when in_parse = 'Y' then 1 else 0 end                                                                                       as in_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_parse
&_IF_ORA11_OR_HIGHER          , case when in_hard_parse = 'Y' then 1 else 0 end                                                                                  as in_hard_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_hard_parse
&_IF_ORA11_OR_HIGHER          , case when in_sql_execution = 'Y' then 1 else 0 end                                                                               as in_sql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_sql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_execution = 'Y' then 1 else 0 end                                                                             as in_plsql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_rpc = 'Y' then 1 else 0 end                                                                                   as in_plsql_rpc
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_rpc
&_IF_ORA11_OR_HIGHER          , case when in_plsql_compilation = 'Y' then 1 else 0 end                                                                           as in_plsql_compilation
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_compilation
&_IF_ORA11_OR_HIGHER          , case when in_java_execution = 'Y' then 1 else 0 end                                                                              as in_java_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_java_execution
&_IF_ORA11_OR_HIGHER          , case when in_bind = 'Y' then 1 else 0 end                                                                                        as in_bind
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_bind
&_IF_ORA11_OR_HIGHER          , case when in_cursor_close = 'Y' then 1 else 0 end                                                                                as in_cursor_close
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_cursor_close
&_IF_ORA112_OR_HIGHER         , case when in_sequence_load = 'Y' then 1 else 0 end                                                                               as in_sequence_load
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as in_sequence_load
&_IF_ORA112_OR_HIGHER         , machine
        , coalesce(program, 'NULL')                                                                                                                              as program
        , xid
&_IF_ORA11_OR_HIGHER          , sql_id || '|' || to_char(ash.sql_exec_start, 'DD.MM.YYYY HH24:MI:SS') || '|' || to_char(sql_exec_id, 'TM')                       as sql_exec_unique
        , module
        , action
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                         as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null)                                                                                                                  as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                  as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null)                                                                                                                  as temp_space_allocated
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                           as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                                                                  as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , ash.sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_exec_id
  from
          &global_ash ash
        , dates
  where
          (&ash_ln_pred1 &ash_ln_pred2)
  and     instr('&op', 'ASH') > 0
  and     instr('&op', 'LIMITED_ASH') = 0
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
  and     &inst_id in
          (
            select
                    distinct
                    &inst_id
            from
                    &global_ash ash
            where
                    sql_id = '&si'
&_IF_ORA11_OR_HIGHER                      and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
            and     &ash_pred1 &ash_pred2
            and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g            and     (event is null or event != 'PX Deq Credit: send blkd')
          )
),
driver as
(
  select
          b.instance_id
        , b.sample_time as timeline
        , b.bucket
  from
          timeline_inst b
),
base_data as
(
  select
          count(a.sample_time) as active_sessions
        , driver.timeline
        , decode(grouping(driver.instance_id), 1, -1, driver.instance_id) as instance_id
  from
          driver
        , ash_base_conc a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.instance_id (+) = driver.instance_id
  group by
&_IS_SINGL_INSTANCE          driver.instance_id
&_IS_CROSS_INSTANCE          grouping sets(driver.instance_id, ())
        , driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.timeline
),
median_as as
(
  select
          instance_id
        , median(active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
  from
          base_data
  group by
          instance_id
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into two parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , ash_base_conc ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , ash.instance_id
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    ash_base_conc ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_pga_temp1 as
(
  select
          sum(pga_allocated) as pga_per_bucket
        , sum(temp_space_allocated) as temp_per_bucket
        , bucket
        , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
  from
          ash_data
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , bucket
),
ash_pga_temp as
(
  select
          max(pga_per_bucket) as pga_mem
        , max(temp_per_bucket) as temp_space
        , instance_id
  from
          ash_pga_temp1
  group by
          instance_id
),
ash_pga_temp_prefmt as
(
  select
          pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                     as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                            as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                               as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                      as power_2_temp_space_mod_10
        , instance_id
  from
          ash_pga_temp
),
ash_pga_temp_fmt as
(
  select
          to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , instance_id
  from
          ash_pga_temp_prefmt
)
select  /* XPLAN_ASH GLOBAL_ASH_SUMMARY_CONCURRENT_EXECUTION SQL_ID: &si */
        nullif(a.instance_id, -1)                                                         as instance_id
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / sample_count * 100)                                      as percentage_cpu
      , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end as average_as_t
      , case when average_as >= &rnd_thr then round(average_as) else average_as end       as average_as
      , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end as median_as
      , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end as stddev_as
      , lpad(ash_pga_temp_fmt.pga_mem_format, 10)                                         as pga
      , lpad(ash_pga_temp_fmt.temp_space_format, 10)                                      as temp
      , foreground_count
      , background_count
      , slave_count                                                                       as px_worker_count
      , slave_unique_count                                                                as px_worker_unique_count
&_IF_ORA112_OR_HIGHER       , client_count
      , process_count
      , transact_count
      , sql_id_count
&_IF_ORA11_OR_HIGHER        , sql_execution_count
      , module_count
      , action_count
      , lpad(to_char(round(is_sqlid_current / sample_count * 100), 'TM'), 6) || '%'       as is_sqlid_current
      , lpad(to_char(round(in_connection_mgmt / sample_count * 100), 'TM'), 6) || '%'     as in_connection_mgmt
      , lpad(to_char(round(in_parse / sample_count * 100), 'TM'), 6) || '%'               as in_parse
      , lpad(to_char(round(in_hard_parse / sample_count * 100), 'TM'), 6) || '%'          as in_hard_parse
      , lpad(to_char(round(in_sql_execution / sample_count * 100), 'TM'), 6) || '%'       as in_sql_execution
      , lpad(to_char(round(in_plsql_execution / sample_count * 100), 'TM'), 6) || '%'     as in_plsql_execution
      , lpad(to_char(round(in_plsql_rpc / sample_count * 100), 'TM'), 6) || '%'           as in_plsql_rpc
      , lpad(to_char(round(in_plsql_compilation / sample_count * 100), 'TM'), 6) || '%'   as in_plsql_compilation
      , lpad(to_char(round(in_java_execution / sample_count * 100), 'TM'), 6) || '%'      as in_java_execution
      , lpad(to_char(round(in_bind / sample_count * 100), 'TM'), 6) || '%'                as in_bind
      , lpad(to_char(round(in_cursor_close / sample_count * 100), 'TM'), 6) || '%'        as in_cursor_close
      , lpad(to_char(round(in_sequence_load / sample_count * 100), 'TM'), 6) || '%'       as in_sequence_load
from
        (
          select
                  decode(grouping(instance_id), 1, -1, instance_id)    as instance_id
                , count(*)                                             as sample_count
                , round(count(*) / nullif(cast(to_number('&ds') as number), 0) * &sample_freq, 1) as average_as_t
                --, count(*) / (((b.max_sample_time - b.min_sample_time) * 86400) + &sample_freq) * &sample_freq as average_as
                , round(count(*) / nullif(coalesce(to_number(trim('&dist_sample_count')), 0), 0), 1) as average_as
                -- This can be used if getting dist_sample_count causes problems on 11.2.0.1 above
                --, round(count(*) / nullif(round(cast(to_number('&ds') as number) / &sample_freq), 0), 1) as average_as
                , sum(is_on_cpu)                                       as cpu_sample_count
                , count(distinct process)                              as slave_count
                , count(distinct case when process is not null then process || '-' || session_id || '-' || session_serial# end) as slave_unique_count
                , count(is_foreground)                                 as foreground_count
                , count(is_background)                                 as background_count
&_IF_ORA112_OR_HIGHER                 , count(distinct machine)                              as client_count
                , count(distinct program)                              as process_count
                , count(distinct xid)                                  as transact_count
                , count(distinct sql_id)                               as sql_id_count
&_IF_ORA11_OR_HIGHER                  , count(distinct sql_exec_unique)                      as sql_execution_count
                , count(distinct module)                               as module_count
                , count(distinct action)                               as action_count
                , sum(is_sqlid_current)                                as is_sqlid_current
                , sum(in_connection_mgmt)                              as in_connection_mgmt
                , sum(in_parse)                                        as in_parse
                , sum(in_hard_parse)                                   as in_hard_parse
                , sum(in_sql_execution)                                as in_sql_execution
                , sum(in_plsql_execution)                              as in_plsql_execution
                , sum(in_plsql_rpc)                                    as in_plsql_rpc
                , sum(in_plsql_compilation)                            as in_plsql_compilation
                , sum(in_java_execution)                               as in_java_execution
                , sum(in_bind)                                         as in_bind
                , sum(in_cursor_close)                                 as in_cursor_close
                , sum(in_sequence_load)                                as in_sequence_load
          from
                  ash_base_conc a
          where
                  instr('&op', 'ASH') > 0
          and     instr('&op', 'LIMITED_ASH') = 0
          -- This prevents the aggregate functions to produce a single row
          -- in case of no rows generated to aggregate
          group by
&_IS_SINGL_INSTANCE                  a.instance_id
&_IS_CROSS_INSTANCE                  grouping sets(a.instance_id, ())
        ) a
      , ash_pga_temp_fmt
      , median_as m
where
        a.instance_id = ash_pga_temp_fmt.instance_id
and     a.instance_id  = m.instance_id
order by
        instance_id nulls first
;

column instance_id          clear
column sample_count         clear
column average_as_t         clear
column average_as           clear
column pga                  clear
column temp                 clear

column is_sqlid_current     clear
column in_connection_mgmt   clear
column in_parse             clear
column in_hard_parse        clear
column in_sql_execution     clear
column in_plsql_execution   clear
column in_plsql_rpc         clear
column in_plsql_compilation clear
column in_java_execution    clear
column in_bind              clear
column in_cursor_close      clear
column in_sequence_load     clear

column px_worker_count      clear
column px_worker_unique_count clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     '&ca_sc' is null
---------
union all
---------
select
        'No concurrent activity detected' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     '&ca_sc' is null
;

column message clear

set heading on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is not null
---------
union all
---------
select
        'Concurrent Activity Summary (not this execution)' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is not null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is not null
;

column message clear

set heading on

-- If you need to debug, comment the following line
set termout off

/* Determine if wait times should be shown or not (Bad ASH math, so don't show that by default) */

column show_wait_times new_value _SHOW_WAIT_TIMES &debug_internalp.print

select
        case when '&_EXPERIMENTAL' is null then '' else 'no' end as show_wait_times
from
        dual
;

column show_wait_times clear

set termout on

column instance_id &_IF_CROSS_INSTANCE.print null "GLOBAL"
column activity format a50
column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
break on instance_id

select  /* XPLAN_ASH CONCURRENT_ACTIVITY_CONCURRENT_EXECUTION SQL_ID: &si */
        instance_id
      , activity
      , activity_class
      , round(avg(time_waited) / 1000, 1)                                           as avg_tim_wait_ms
      , round(median(time_waited) / 1000, 1)                                        as med_tim_wait_ms
      , count(*)                                                                    as sample_count
      , round(count(*) / total_cnt * 100)                                           as percentage
      , rpad('&gc3', nvl(round(count(*) / nullif(total_cnt, 0) * &wgs), 0), '&gc3') as activity_graph
from
        (
                    select
                            &inst_id as instance_id
                          , case when session_state = 'WAITING' then nvl(wait_class, '<Wait Class Is Null>') else session_state end as activity_class
                          , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end      as activity
                          , case when session_state = 'WAITING' then nullif(time_waited, 0) else null end                           as time_waited
                          , count(*) over ()                                                                                        as total_cnt
                    from
                            &global_ash ash
                    where
                            (&ash_ln_pred1 &ash_ln_pred2)
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g                    and     (event is null or event != 'PX Deq Credit: send blkd')
                    and     &inst_id in
                            (
                              select
                                      distinct
                                      &inst_id
                              from
                                      &global_ash ash
                              where
                                      sql_id = '&si'
&_IF_ORA11_OR_HIGHER                                        and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
                              and     &ash_pred1 &ash_pred2
                              and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g                              and     (event is null or event != 'PX Deq Credit: send blkd')
                            )
                    and     instr('&op', 'ASH') > 0
                    and     '&ca_sc' is not null
        )
group by
&_IS_SINGL_INSTANCE        instance_id
&_IS_CROSS_INSTANCE        grouping sets(instance_id, ())
      , activity
      , activity_class
      , total_cnt
order by
        instance_id nulls first
      , sample_count desc
;

column instance_id clear
column activity clear
column activity_class clear
column activity_graph clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

clear breaks

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     '&ca_sc' is not null
---------
union all
---------
select
        'Concurrent activity top SQL_IDs' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     '&ca_sc' is not null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     instr('&op', 'LIMITED_ASH') = 0
and     '&ca_sc' is not null
;

column message clear

set heading on

/* Information about the top SQL_IDs of concurrent activity based on ASH */

column first_sample      format a19
column last_sample       format a19
column time_active_graph format a&tgs
column duration_secs_t                heading "DURATION SECS|TOTAL"
column duration_t                     heading "DURATION|TOTAL"
column duration_secs                  heading "DURATION SECS|ACTIVE"
column duration                       heading "DURATION|ACTIVE"
column average_as_t                   heading "AVERAGE AS|TOTAL"
column average_as                     heading "AVERAGE AS|ACTIVE"
column px_worker_count                heading "PX WORKER|COUNT"
column px_worker_unique_count         heading "PX WORKER|UNIQUE COUNT"
column pga               format a10   heading "MAX_PGA"  &_IF_ORA112_OR_HIGHERP.print
column temp              format a10   heading "MAX_TEMP" &_IF_ORA112_OR_HIGHERP.print
-- For the time being, do not print PGA/TEMP as it is more confusing that helpful if you don't know what it is based on
--column pga               format a10 heading "MAX_PGA"  noprint
--column temp              format a10 heading "MAX_TEMP" noprint
column instance_id       &_IF_CROSS_INSTANCE.print null "GLOBAL"
column is_sqlid_current     format a7 heading "IS|SQLID|CURRENT" &_IF_ORA112_OR_HIGHERP.print
column in_connection_mgmt   format a7 heading "IN|CONNECT|MGMT"  &_IF_ORA11_OR_HIGHERP.print
column in_parse             format a7 heading "IN|PARSE"         &_IF_ORA11_OR_HIGHERP.print
column in_hard_parse        format a7 heading "IN|HARD|PARSE"    &_IF_ORA11_OR_HIGHERP.print
column in_sql_execution     format a7 heading "IN|SQL|EXECUTE"   &_IF_ORA11_OR_HIGHERP.print
column in_plsql_execution   format a7 heading "IN|PLSQL|EXECUTE" &_IF_ORA11_OR_HIGHERP.print
column in_plsql_rpc         format a7 heading "IN|PLSQL|RPC"     &_IF_ORA11_OR_HIGHERP.print
column in_plsql_compilation format a7 heading "IN|PLSQL|COMP"    &_IF_ORA11_OR_HIGHERP.print
column in_java_execution    format a7 heading "IN|JAVA|EXECUTE"  &_IF_ORA11_OR_HIGHERP.print
column in_bind              format a7 heading "IN|BIND"          &_IF_ORA11_OR_HIGHERP.print
column in_cursor_close      format a7 heading "IN|CURSOR|CLOSE"  &_IF_ORA11_OR_HIGHERP.print
column in_sequence_load     format a7 heading "IN|SEQ|LOAD"      &_IF_ORA112_OR_HIGHERP.print
column top_level_sql_id     format a16 heading "TOP_LEVEL_SQL_ID" &_IF_ORA11_OR_HIGHERP.print

break on instance_id

with /* XPLAN_ASH ASH_SQLID_DETAILS_CONCURRENT_ACTIVITY SQL_ID: &si */
ash_base as
(
  select
          &inst_id                                                                                 as instance_id
        , cast(sample_time as date)                                                                as sample_time
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     '&ca_sc' is not null
  and     instr('&op', 'ASH') > 0
  and     instr('&op', 'LIMITED_ASH') = 0
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
ash_base_conc as
(
  select
          &inst_id as instance_id
        , cast(sample_time as date)                                                                                                                              as sample_time
        , coalesce(sql_id, 'NULL')                                                                                                                             as sql_id
        , case
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- when regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1) is null
          when regexp_instr(regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') != 1 or session_type != 'FOREGROUND' or program is null
          then null
          -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
          -- else &inst_id || '-' || regexp_substr(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', 1, 1, 'c', 1)
          else &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')
          end                                                                                                                                                    as process
        , session_id
        , session_serial#
&_IF_ORA11_OR_HIGHER          , nvl(top_level_sql_id, 'NULL')                                                                                                    as top_level_sql_id
        , case when session_state = 'ON CPU' then 1 else 0 end                                                                                                   as is_on_cpu
        , case when session_type = 'FOREGROUND' then 1 else null end                                                                                             as is_foreground
        , case when session_type = 'BACKGROUND' then 1 else null end                                                                                             as is_background
&_IF_ORA112_OR_HIGHER         , case when is_sqlid_current = 'Y' then 1 else 0 end                                                                               as is_sqlid_current
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as is_sqlid_current
&_IF_ORA11_OR_HIGHER          , case when in_connection_mgmt = 'Y' then 1 else 0 end                                                                             as in_connection_mgmt
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_connection_mgmt
&_IF_ORA11_OR_HIGHER          , case when in_parse = 'Y' then 1 else 0 end                                                                                       as in_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_parse
&_IF_ORA11_OR_HIGHER          , case when in_hard_parse = 'Y' then 1 else 0 end                                                                                  as in_hard_parse
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_hard_parse
&_IF_ORA11_OR_HIGHER          , case when in_sql_execution = 'Y' then 1 else 0 end                                                                               as in_sql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_sql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_execution = 'Y' then 1 else 0 end                                                                             as in_plsql_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_execution
&_IF_ORA11_OR_HIGHER          , case when in_plsql_rpc = 'Y' then 1 else 0 end                                                                                   as in_plsql_rpc
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_rpc
&_IF_ORA11_OR_HIGHER          , case when in_plsql_compilation = 'Y' then 1 else 0 end                                                                           as in_plsql_compilation
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_plsql_compilation
&_IF_ORA11_OR_HIGHER          , case when in_java_execution = 'Y' then 1 else 0 end                                                                              as in_java_execution
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_java_execution
&_IF_ORA11_OR_HIGHER          , case when in_bind = 'Y' then 1 else 0 end                                                                                        as in_bind
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_bind
&_IF_ORA11_OR_HIGHER          , case when in_cursor_close = 'Y' then 1 else 0 end                                                                                as in_cursor_close
&_IF_LOWER_THAN_ORA11         , 0                                                                                                                                as in_cursor_close
&_IF_ORA112_OR_HIGHER         , case when in_sequence_load = 'Y' then 1 else 0 end                                                                               as in_sequence_load
&_IF_LOWER_THAN_ORA112        , 0                                                                                                                                as in_sequence_load
&_IF_ORA112_OR_HIGHER         , machine
        , coalesce(program, 'NULL')                                                                                                                              as program
        , xid
&_IF_ORA11_OR_HIGHER          , sql_id || '|' || to_char(ash.sql_exec_start, 'DD.MM.YYYY HH24:MI:SS') || '|' || to_char(sql_exec_id, 'TM')                       as sql_exec_unique
        , module
        , action
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                         as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null)                                                                                                                  as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                  as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null)                                                                                                                  as temp_space_allocated
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                           as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - dates.sql_exec_start) * 86400) / &sample_freq) * &sample_freq                                                                  as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , ash.sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_exec_id
  from
          &global_ash ash
        , dates
  where
          (&ash_ln_pred1 &ash_ln_pred2)
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  and     instr('&op', 'ASH') > 0
  and     instr('&op', 'LIMITED_ASH') = 0
  and     '&ca_sc' is not null
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
  and     &inst_id in
          (
            select
                    distinct
                    &inst_id
            from
                    &global_ash ash
            where
                    sql_id = '&si'
&_IF_ORA11_OR_HIGHER                     and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
            and     &ash_pred1 &ash_pred2
            and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g            and     (event is null or event != 'PX Deq Credit: send blkd')
          )
),
top_sqlid1 as
(
  select
          sql_id
        , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
        , count(*) as cnt
  from
          ash_base_conc
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , sql_id
),
top_sqlid as
(
  select
          sql_id
        , instance_id
  from
          (
            select
                    sql_id
                  , instance_id
                  , row_number() over (partition by instance_id order by cnt desc) as rn
            from
                    top_sqlid1
          )
  where
          rn <= &topn_sqlid
),
driver as
(
  select  /*+ cardinality(1000) */
          b.instance_id
        , ash_sql_ids.sql_id
        , b.sample_time as timeline
        , b.bucket
  from
          timeline_inst b, (select /*+ cardinality(&topn_sqlid) */ sql_id, instance_id from top_sqlid) ash_sql_ids
  where
          b.instance_id = ash_sql_ids.instance_id
),
base_data as
(
  select  /*+ cardinality(1000) */
          case when count(a.sample_time) > 0 then '&gc3' else ' ' end as act_ind
        , count(a.sample_time) as active_sessions
        , driver.sql_id
        , driver.timeline
        , decode(grouping(driver.instance_id), 1, -1, driver.instance_id) as instance_id
  from
          driver
        , ash_base_conc a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.instance_id (+) = driver.instance_id
  and     a.sql_id (+) = driver.sql_id
  group by
&_IS_SINGL_INSTANCE          driver.instance_id
&_IS_CROSS_INSTANCE          grouping sets(driver.instance_id, ())
        , driver.sql_id
        , driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.timeline
),
bucket_data as
(
  select
          ntile(&tgs) over (partition by instance_id, sql_id order by timeline) as bucket
        , x.*
  from
          base_data x
          -- In case we have less sample times as size of the Time Active Graph
          -- this here will duplicate the data accordingly
        , (select /*+ cardinality(&duplicator) */ null from dual connect by level <= to_number(trim('&duplicator'))) dups
),
grouped_buckets as
(
  select
          max(act_ind) as act_ind
        , bucket
        , instance_id
        , sql_id
  from
          bucket_data
  group by
          instance_id
        , sql_id
        , bucket
--  order by
--          instance_id
--        , bucket
),
time_active_graph as
(
  select
          instance_id
        , sql_id
&_IF_ORA112_OR_HIGHER         , listagg(act_ind) within group (order by bucket)                        as time_active_graph
          /* leading spaces are trimmed by the XML operation, hence we need to temporarily replace them with something else */
&_IF_LOWER_THAN_ORA112        , replace(extract(xmlagg(xmlelement("V", replace(act_ind, ' ', '?')) order by bucket), '/V/text()').getstringval(), '?', ' ') as time_active_graph
  from
          grouped_buckets
  group by
          instance_id
        , sql_id
--  order by
--          instance_id
),
topn_ash_base_conc as
(
  select  /*+ cardinality(s &topn_sqlid) no_merge */
          a.*
  from
          ash_base_conc a
        , top_sqlid s
  where
          a.sql_id = s.sql_id
  and     a.instance_id = s.instance_id
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into two parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.sql_id
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , topn_ash_base_conc ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.sql_exec_start
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.sql_id
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , ash.instance_id
                  , ash.sql_id
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    topn_ash_base_conc ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_pga_temp1 as
(
  select
          sum(pga_allocated) as pga_per_bucket
        , sum(temp_space_allocated) as temp_per_bucket
        , bucket
        , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
        , sql_id
  from
          ash_data
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , sql_id
        , bucket
),
ash_pga_temp as
(
  select
          max(pga_per_bucket) as pga_mem
        , max(temp_per_bucket) as temp_space
        , instance_id
        , sql_id
  from
          ash_pga_temp1
  group by
          instance_id
        , sql_id
),
ash_pga_temp_prefmt as
(
  select
          pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                     as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                            as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                               as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                      as power_2_temp_space_mod_10
        , instance_id
        , sql_id
  from
          ash_pga_temp
),
ash_pga_temp_fmt as
(
  select
          to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , instance_id
        , sql_id
  from
          ash_pga_temp_prefmt
),
median_as as
(
  select
          instance_id
        , sql_id
        , median(active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
from
          (
            select
                    sample_time
                  , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
                  , sql_id
                  , count(*) as active_sessions
            from
                    topn_ash_base_conc
            group by
                    sample_time
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
                  , sql_id
          )
  group by
          instance_id
        , sql_id
),
sql_details1 as
(
  select
          decode(grouping(instance_id), 1, -1, instance_id)                                                    as instance_id
        , min(instance_id)                                                                                     as min_instance_id
        , sql_id
        , to_char(min(sample_time), '&dm')                                                                     as first_sample
        , to_char(max(sample_time), '&dm')                                                                     as last_sample
        , round(min(ash_bucket) + &sample_freq)                                                                as start_active
        , round(max(ash_bucket) - min(ash_bucket) + &sample_freq)                                              as duration_secs_t
        , count(distinct ash_bucket) * &sample_freq                                                            as duration_secs
&_IF_ORA11_OR_HIGHER         , max(top_level_sql_id)                                                           as top_level_sql_id
        , count(*)                                                                                             as sample_count
        , count(distinct process)                                                                              as slave_count
        , count(distinct case when process is not null then process || '-' || session_id || '-' || session_serial# end) as slave_unique_count
        , sum(is_on_cpu)                                                                                       as cpu_sample_count
        , round(count(*) / nullif((max(ash_bucket) - min(ash_bucket) + &sample_freq) / &sample_freq, 0), 1)    as average_as_t
        , round(count(*) / nullif(count(distinct ash_bucket), 0), 1)                                           as average_as
        , sum(is_sqlid_current)                                                                                as is_sqlid_current
        , sum(in_connection_mgmt)                                                                              as in_connection_mgmt
        , sum(in_parse)                                                                                        as in_parse
        , sum(in_hard_parse)                                                                                   as in_hard_parse
        , sum(in_sql_execution)                                                                                as in_sql_execution
        , sum(in_plsql_execution)                                                                              as in_plsql_execution
        , sum(in_plsql_rpc)                                                                                    as in_plsql_rpc
        , sum(in_plsql_compilation)                                                                            as in_plsql_compilation
        , sum(in_java_execution)                                                                               as in_java_execution
        , sum(in_bind)                                                                                         as in_bind
        , sum(in_cursor_close)                                                                                 as in_cursor_close
        , sum(in_sequence_load)                                                                                as in_sequence_load
  from
          topn_ash_base_conc a
        , dates
  where
          instr('&op', 'ASH') > 0
  and     instr('&op', 'LIMITED_ASH') = 0
  and     '&ca_sc' is not null
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , sql_id
        , dates.sql_exec_start
),
sql_details as
(
  select
          nullif(a.instance_id, -1)                                                                                                                       as instance_id
        , a.sql_id
&_IF_ORA11_OR_HIGHER         , top_level_sql_id
        , row_number() over (partition by a.instance_id order by sample_count desc)                                                                       as rn
        , coalesce(sql.sql_text, '<No SQL TEXT found>')                                                                                                   as sql_text
        , first_sample
        , last_sample
        , start_active
        , duration_secs_t
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
        , duration_secs
        , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
        , sample_count
        , cpu_sample_count
        , round(cpu_sample_count / sample_count * 100)                                                                                                    as percentage_cpu
        , slave_count                                                                                                                                     as px_worker_count
        , slave_unique_count                                                                                                                              as px_worker_unique_count
        , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end                                                               as average_as_t
        , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
        , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end                                                              as median_as
        , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end                                                              as stddev_as
        , lpad(pt.pga_mem_format, 10)                                                                                                                     as pga
        , lpad(pt.temp_space_format, 10)                                                                                                                  as temp
        --, substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc3', round(duration_secs / to_number('&ds') * &tgs), '&gc3'), 1, &tgs) as time_active_graph
        , t.time_active_graph
        , lpad(to_char(round(is_sqlid_current / sample_count * 100), 'TM'), 6) || '%'                                                                     as is_sqlid_current
        , lpad(to_char(round(in_connection_mgmt / sample_count * 100), 'TM'), 6) || '%'                                                                   as in_connection_mgmt
        , lpad(to_char(round(in_parse / sample_count * 100), 'TM'), 6) || '%'                                                                             as in_parse
        , lpad(to_char(round(in_hard_parse / sample_count * 100), 'TM'), 6) || '%'                                                                        as in_hard_parse
        , lpad(to_char(round(in_sql_execution / sample_count * 100), 'TM'), 6) || '%'                                                                     as in_sql_execution
        , lpad(to_char(round(in_plsql_execution / sample_count * 100), 'TM'), 6) || '%'                                                                   as in_plsql_execution
        , lpad(to_char(round(in_plsql_rpc / sample_count * 100), 'TM'), 6) || '%'                                                                         as in_plsql_rpc
        , lpad(to_char(round(in_plsql_compilation / sample_count * 100), 'TM'), 6) || '%'                                                                 as in_plsql_compilation
        , lpad(to_char(round(in_java_execution / sample_count * 100), 'TM'), 6) || '%'                                                                    as in_java_execution
        , lpad(to_char(round(in_bind / sample_count * 100), 'TM'), 6) || '%'                                                                              as in_bind
        , lpad(to_char(round(in_cursor_close / sample_count * 100), 'TM'), 6) || '%'                                                                      as in_cursor_close
        , lpad(to_char(round(in_sequence_load / sample_count * 100), 'TM'), 6) || '%'                                                                     as in_sequence_load
  from
          sql_details1 a
        , ash_pga_temp_fmt pt
        , time_active_graph t
        , median_as m
        , (
            select
                    sql_id
                  , &sqltext_join_col
                  , cast(substr(sql_text, 1, 80) as varchar2(80)) as sql_text
            from
                    &sqltext p
            --where
            --        &third_id_sqltext
          ) sql
  where
          a.sql_id = pt.sql_id
  and     a.instance_id = pt.instance_id
  and     a.sql_id = t.sql_id
  and     a.instance_id = t.instance_id
  and     a.sql_id = m.sql_id
  and     a.instance_id = m.instance_id
  and     a.sql_id = sql.sql_id (+)
  and     &sqltext_join
)
select  /* XPLAN_ASH ASH_SQLID_DETAILS_CONCURRENT_ACTIVITY SQL_ID: &si */
        instance_id
      , sql_id
      , sql_text
&_IF_ORA11_OR_HIGHER       , top_level_sql_id
      , first_sample
      , last_sample
      , start_active
      , duration_secs_t
      , duration_t
      , duration_secs
      , duration
      , sample_count
      , cpu_sample_count
      , percentage_cpu
      , px_worker_count
      , px_worker_unique_count
      , average_as_t
      , average_as
      , median_as
      , stddev_as
      , pga
      , temp
      , time_active_graph
      , is_sqlid_current
      , in_connection_mgmt
      , in_parse
      , in_hard_parse
      , in_sql_execution
      , in_plsql_execution
      , in_plsql_rpc
      , in_plsql_compilation
      , in_java_execution
      , in_bind
      , in_cursor_close
      , in_sequence_load
from
        sql_details
--where
--        rn <= &topn_sqlid
order by
        instance_id nulls first
      , sample_count desc
;

column first_sample         clear
column last_sample          clear
column time_active_graph    clear
column pga                  clear
column temp                 clear
column instance_id          clear

column duration_secs_t      clear
column duration_t           clear
column duration_secs        clear
column duration             clear
column average_as_t         clear
column average_as           clear

column is_sqlid_current     clear
column in_connection_mgmt   clear
column in_parse             clear
column in_hard_parse        clear
column in_sql_execution     clear
column in_plsql_execution   clear
column in_plsql_rpc         clear
column in_plsql_compilation clear
column in_java_execution    clear
column in_bind              clear
column in_cursor_close      clear
column in_sequence_load     clear

column px_worker_count      clear
column px_worker_unique_count clear
column top_level_sql_id     clear

clear breaks

/* I/O Summary information based on ASH */

/* The following query will be used multiple times with different parameters and therefore written to a temporary file */

select  /* XPLAN_ASH IO_SUMMARY SQL_ID: &si */
        instance_id
      , duration_secs_t
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
      , lpad(to_char(round(total_read_io_req / power(10, power_10_total_read_io_req - case when power_10_total_read_io_req > 0 and power_10_total_read_io_req_3 = 0 then 3 else power_10_total_read_io_req_3 end)), 'FM99999'), 5) ||
        case power_10_total_read_io_req - case when power_10_total_read_io_req > 0 and power_10_total_read_io_req_3 = 0 then 3 else power_10_total_read_io_req_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_read_io_req is null
             then null
             else '*10^'||to_char(power_10_total_read_io_req - case when power_10_total_read_io_req > 0 and power_10_total_read_io_req_3 = 0 then 3 else power_10_total_read_io_req_3 end)
             end
        end      as total_read_io_req
      , lpad(to_char(round(total_write_io_req / power(10, power_10_total_write_io_req - case when power_10_total_write_io_req > 0 and power_10_total_write_io_req_3 = 0 then 3 else power_10_total_write_io_req_3 end)), 'FM99999'), 5) ||
        case power_10_total_write_io_req - case when power_10_total_write_io_req > 0 and power_10_total_write_io_req_3 = 0 then 3 else power_10_total_write_io_req_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_write_io_req is null
             then null
             else '*10^'||to_char(power_10_total_write_io_req - case when power_10_total_write_io_req > 0 and power_10_total_write_io_req_3 = 0 then 3 else power_10_total_write_io_req_3 end)
             end
        end      as total_write_io_req
      , lpad(to_char(round(read_io_req_per_sec / power(10, power_10_read_io_req_per_sec - case when power_10_read_io_req_per_sec > 0 and power_10_read_io_req_per_sec_3 = 0 then 3 else power_10_read_io_req_per_sec_3 end)), 'FM99999'), 5) ||
        case power_10_read_io_req_per_sec - case when power_10_read_io_req_per_sec > 0 and power_10_read_io_req_per_sec_3 = 0 then 3 else power_10_read_io_req_per_sec_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when read_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_read_io_req_per_sec - case when power_10_read_io_req_per_sec > 0 and power_10_read_io_req_per_sec_3 = 0 then 3 else power_10_read_io_req_per_sec_3 end)
             end
        end      as read_io_req_per_sec
      , lpad(to_char(round(write_io_req_per_sec / power(10, power_10_write_io_req_per_sec - case when power_10_write_io_req_per_sec > 0 and power_10_write_io_req_persec_3 = 0 then 3 else power_10_write_io_req_persec_3 end)), 'FM99999'), 5) ||
        case power_10_write_io_req_per_sec - case when power_10_write_io_req_per_sec > 0 and power_10_write_io_req_persec_3 = 0 then 3 else power_10_write_io_req_persec_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when write_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_write_io_req_per_sec - case when power_10_write_io_req_per_sec > 0 and power_10_write_io_req_persec_3 = 0 then 3 else power_10_write_io_req_persec_3 end)
             end
        end      as write_io_req_per_sec
      , lpad(to_char(round(total_read_io_bytes / power(2, power_2_t_read_io_bytes - case when power_2_t_read_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_read_io_bytes))),3)) = 0 then power_2_t_read_io_bytes_10 + 10 else power_2_t_read_io_bytes_10 end)), 'FM99999'), 5) ||
        case power_2_t_read_io_bytes - case when power_2_t_read_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_read_io_bytes))),3)) = 0 then power_2_t_read_io_bytes_10 + 10 else power_2_t_read_io_bytes_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when total_read_io_bytes is null
             then null
             else '*2^'||to_char(power_2_t_read_io_bytes - case when power_2_t_read_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_read_io_bytes))),3)) = 0 then power_2_t_read_io_bytes_10 + 10 else power_2_t_read_io_bytes_10 end)
             end
        end      as total_read_io_bytes
      , lpad(to_char(round(total_write_io_bytes / power(2, power_2_t_write_io_bytes - case when power_2_t_write_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_write_io_bytes))),3)) = 0 then power_2_t_write_io_bytes_10 + 10 else power_2_t_write_io_bytes_10 end)), 'FM99999'), 5) ||
        case power_2_t_write_io_bytes - case when power_2_t_write_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_write_io_bytes))),3)) = 0 then power_2_t_write_io_bytes_10 + 10 else power_2_t_write_io_bytes_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when total_write_io_bytes is null
             then null
             else '*2^'||to_char(power_2_t_write_io_bytes - case when power_2_t_write_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_write_io_bytes))),3)) = 0 then power_2_t_write_io_bytes_10 + 10 else power_2_t_write_io_bytes_10 end)
             end
        end      as total_write_io_bytes
      , lpad(to_char(round(total_intercon_io_bytes / power(2, power_2_t_intcon_io_bytes - case when power_2_t_intcon_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_intcon_io_bytes))),3)) = 0 then power_2_t_intcon_io_bytes_10 + 10 else power_2_t_intcon_io_bytes_10 end)), 'FM99999'), 5) ||
        case power_2_t_intcon_io_bytes - case when power_2_t_intcon_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_intcon_io_bytes))),3)) = 0 then power_2_t_intcon_io_bytes_10 + 10 else power_2_t_intcon_io_bytes_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when total_intercon_io_bytes is null
             then null
             else '*2^'||to_char(power_2_t_intcon_io_bytes - case when power_2_t_intcon_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_intcon_io_bytes))),3)) = 0 then power_2_t_intcon_io_bytes_10 + 10 else power_2_t_intcon_io_bytes_10 end)
             end
        end      as total_intercon_io_bytes
      , lpad(to_char(round(total_read_mem_bytes / power(2, power_2_t_read_mem_bytes - case when power_2_t_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_read_mem_bytes))),3)) = 0 then power_2_t_read_mem_bytes_10 + 10 else power_2_t_read_mem_bytes_10 end)), 'FM99999'), 5) ||
        case power_2_t_read_mem_bytes - case when power_2_t_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_read_mem_bytes))),3)) = 0 then power_2_t_read_mem_bytes_10 + 10 else power_2_t_read_mem_bytes_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when total_read_mem_bytes is null
             then null
             else '*2^'||to_char(power_2_t_read_mem_bytes - case when power_2_t_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_t_read_mem_bytes))),3)) = 0 then power_2_t_read_mem_bytes_10 + 10 else power_2_t_read_mem_bytes_10 end)
             end
        end      as total_read_mem_bytes
      , lpad(to_char(round(read_io_bytes_per_sec / power(2, power_2_read_io_bytes_ps - case when power_2_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_io_bytes_ps))),3)) = 0 then power_2_read_io_bytes_ps_10 + 10 else power_2_read_io_bytes_ps_10 end)), 'FM99999'), 5) ||
        case power_2_read_io_bytes_ps - case when power_2_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_io_bytes_ps))),3)) = 0 then power_2_read_io_bytes_ps_10 + 10 else power_2_read_io_bytes_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when read_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_read_io_bytes_ps - case when power_2_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_io_bytes_ps))),3)) = 0 then power_2_read_io_bytes_ps_10 + 10 else power_2_read_io_bytes_ps_10 end)
             end
        end      as read_io_bytes_per_sec
      , lpad(to_char(round(write_io_bytes_per_sec / power(2, power_2_write_io_bytes_ps - case when power_2_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_io_bytes_ps))),3)) = 0 then power_2_write_io_bytes_ps_10 + 10 else power_2_write_io_bytes_ps_10 end)), 'FM99999'), 5) ||
        case power_2_write_io_bytes_ps - case when power_2_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_io_bytes_ps))),3)) = 0 then power_2_write_io_bytes_ps_10 + 10 else power_2_write_io_bytes_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when write_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_write_io_bytes_ps - case when power_2_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_io_bytes_ps))),3)) = 0 then power_2_write_io_bytes_ps_10 + 10 else power_2_write_io_bytes_ps_10 end)
             end
        end      as write_io_bytes_per_sec
      , lpad(to_char(round(intercon_io_bytes_per_sec / power(2, power_2_intercon_io_bytes_ps - case when power_2_intercon_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_intercon_io_bytes_ps))),3)) = 0 then power_2_intercon_io_byte_ps_10 + 10 else power_2_intercon_io_byte_ps_10 end)), 'FM99999'), 5) ||
        case power_2_intercon_io_bytes_ps - case when power_2_intercon_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_intercon_io_bytes_ps))),3)) = 0 then power_2_intercon_io_byte_ps_10 + 10 else power_2_intercon_io_byte_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when intercon_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_intercon_io_bytes_ps - case when power_2_intercon_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_intercon_io_bytes_ps))),3)) = 0 then power_2_intercon_io_byte_ps_10 + 10 else power_2_intercon_io_byte_ps_10 end)
             end
        end      as intercon_io_bytes_per_sec
      , lpad(to_char(round(read_mem_bytes_per_sec / power(2, power_2_read_mem_bytes_ps - case when power_2_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_ps))),3)) = 0 then power_2_read_mem_bytes_ps_10 + 10 else power_2_read_mem_bytes_ps_10 end)), 'FM99999'), 5) ||
        case power_2_read_mem_bytes_ps - case when power_2_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_ps))),3)) = 0 then power_2_read_mem_bytes_ps_10 + 10 else power_2_read_mem_bytes_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when read_mem_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_read_mem_bytes_ps - case when power_2_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_ps))),3)) = 0 then power_2_read_mem_bytes_ps_10 + 10 else power_2_read_mem_bytes_ps_10 end)
             end
        end      as read_mem_bytes_per_sec
      , lpad(to_char(round(avg_read_req_size / power(2, power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end)), 'FM99999'), 5) ||
        case power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when avg_read_req_size is null
             then null
             else '*2^'||to_char(power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end)
             end
        end      as avg_read_req_size
      , lpad(to_char(round(med_read_req_size / power(2, power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end)), 'FM99999'), 5) ||
        case power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when med_read_req_size is null
             then null
             else '*2^'||to_char(power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end)
             end
        end      as med_read_req_size
      , lpad(to_char(round(avg_write_req_size / power(2, power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end)), 'FM99999'), 5) ||
        case power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when avg_write_req_size is null
             then null
             else '*2^'||to_char(power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end)
             end
        end      as avg_write_req_size
      , lpad(to_char(round(med_write_req_size / power(2, power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end)), 'FM99999'), 5) ||
        case power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when med_write_req_size is null
             then null
             else '*2^'||to_char(power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end)
             end
        end      as med_write_req_size
      , lpad(to_char(round(max_read_io_req_per_sec / power(10, power_10_max_read_io_req_ps - case when power_10_max_read_io_req_ps > 0 and power_10_max_read_io_req_ps_3 = 0 then 3 else power_10_max_read_io_req_ps_3 end)), 'FM99999'), 5) ||
        case power_10_max_read_io_req_ps - case when power_10_max_read_io_req_ps > 0 and power_10_max_read_io_req_ps_3 = 0 then 3 else power_10_max_read_io_req_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when max_read_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_max_read_io_req_ps - case when power_10_max_read_io_req_ps > 0 and power_10_max_read_io_req_ps_3 = 0 then 3 else power_10_max_read_io_req_ps_3 end)
             end
        end      as max_read_io_req_per_sec
      , lpad(to_char(round(min_read_io_req_per_sec / power(10, power_10_min_read_io_req_ps - case when power_10_min_read_io_req_ps > 0 and power_10_min_read_io_req_ps_3 = 0 then 3 else power_10_min_read_io_req_ps_3 end)), 'FM99999'), 5) ||
        case power_10_min_read_io_req_ps - case when power_10_min_read_io_req_ps > 0 and power_10_min_read_io_req_ps_3 = 0 then 3 else power_10_min_read_io_req_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when min_read_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_min_read_io_req_ps - case when power_10_min_read_io_req_ps > 0 and power_10_min_read_io_req_ps_3 = 0 then 3 else power_10_min_read_io_req_ps_3 end)
             end
        end      as min_read_io_req_per_sec
      , lpad(to_char(round(max_write_io_req_per_sec / power(10, power_10_max_write_io_req_ps - case when power_10_max_write_io_req_ps > 0 and power_10_max_write_io_req_ps_3 = 0 then 3 else power_10_max_write_io_req_ps_3 end)), 'FM99999'), 5) ||
        case power_10_max_write_io_req_ps - case when power_10_max_write_io_req_ps > 0 and power_10_max_write_io_req_ps_3 = 0 then 3 else power_10_max_write_io_req_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when max_write_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_max_write_io_req_ps - case when power_10_max_write_io_req_ps > 0 and power_10_max_write_io_req_ps_3 = 0 then 3 else power_10_max_write_io_req_ps_3 end)
             end
        end      as max_write_io_req_per_sec
      , lpad(to_char(round(min_write_io_req_per_sec / power(10, power_10_min_write_io_req_ps - case when power_10_min_write_io_req_ps > 0 and power_10_min_write_io_req_ps_3 = 0 then 3 else power_10_min_write_io_req_ps_3 end)), 'FM99999'), 5) ||
        case power_10_min_write_io_req_ps - case when power_10_min_write_io_req_ps > 0 and power_10_min_write_io_req_ps_3 = 0 then 3 else power_10_min_write_io_req_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when min_write_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_min_write_io_req_ps - case when power_10_min_write_io_req_ps > 0 and power_10_min_write_io_req_ps_3 = 0 then 3 else power_10_min_write_io_req_ps_3 end)
             end
        end      as min_write_io_req_per_sec
      , lpad(to_char(round(max_read_io_bytes_per_sec / power(2, power_2_max_read_io_bytes_ps - case when power_2_max_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_read_io_bytes_ps))),3)) = 0 then power_2_max_read_io_byte_ps_10 + 10 else power_2_max_read_io_byte_ps_10 end)), 'FM99999'), 5) ||
        case power_2_max_read_io_bytes_ps - case when power_2_max_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_read_io_bytes_ps))),3)) = 0 then power_2_max_read_io_byte_ps_10 + 10 else power_2_max_read_io_byte_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when max_read_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_max_read_io_bytes_ps - case when power_2_max_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_read_io_bytes_ps))),3)) = 0 then power_2_max_read_io_byte_ps_10 + 10 else power_2_max_read_io_byte_ps_10 end)
             end
        end      as max_read_io_bytes_per_sec
      , lpad(to_char(round(min_read_io_bytes_per_sec / power(2, power_2_min_read_io_bytes_ps - case when power_2_min_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_read_io_bytes_ps))),3)) = 0 then power_2_min_read_io_byte_ps_10 + 10 else power_2_min_read_io_byte_ps_10 end)), 'FM99999'), 5) ||
        case power_2_min_read_io_bytes_ps - case when power_2_min_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_read_io_bytes_ps))),3)) = 0 then power_2_min_read_io_byte_ps_10 + 10 else power_2_min_read_io_byte_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when min_read_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_min_read_io_bytes_ps - case when power_2_min_read_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_read_io_bytes_ps))),3)) = 0 then power_2_min_read_io_byte_ps_10 + 10 else power_2_min_read_io_byte_ps_10 end)
             end
        end      as min_read_io_bytes_per_sec
      , lpad(to_char(round(max_write_io_bytes_per_sec / power(2, power_2_max_write_io_bytes_ps - case when power_2_max_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_write_io_bytes_ps))),3)) = 0 then power_2_max_write_io_byt_ps_10 + 10 else power_2_max_write_io_byt_ps_10 end)), 'FM99999'), 5) ||
        case power_2_max_write_io_bytes_ps - case when power_2_max_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_write_io_bytes_ps))),3)) = 0 then power_2_max_write_io_byt_ps_10 + 10 else power_2_max_write_io_byt_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when max_write_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_max_write_io_bytes_ps - case when power_2_max_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_write_io_bytes_ps))),3)) = 0 then power_2_max_write_io_byt_ps_10 + 10 else power_2_max_write_io_byt_ps_10 end)
             end
        end      as max_write_io_bytes_per_sec
      , lpad(to_char(round(min_write_io_bytes_per_sec / power(2, power_2_min_write_io_bytes_ps - case when power_2_min_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_write_io_bytes_ps))),3)) = 0 then power_2_min_write_io_byt_ps_10 + 10 else power_2_min_write_io_byt_ps_10 end)), 'FM99999'), 5) ||
        case power_2_min_write_io_bytes_ps - case when power_2_min_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_write_io_bytes_ps))),3)) = 0 then power_2_min_write_io_byt_ps_10 + 10 else power_2_min_write_io_byt_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when min_write_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_min_write_io_bytes_ps - case when power_2_min_write_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_write_io_bytes_ps))),3)) = 0 then power_2_min_write_io_byt_ps_10 + 10 else power_2_min_write_io_byt_ps_10 end)
             end
        end      as min_write_io_bytes_per_sec
      , lpad(to_char(round(max_intercon_io_bytes_per_sec / power(2, power_2_max_inter_io_bytes_ps - case when power_2_max_inter_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_inter_io_bytes_ps))),3)) = 0 then power_2_max_inter_io_byt_ps_10 + 10 else power_2_max_inter_io_byt_ps_10 end)), 'FM99999'), 5) ||
        case power_2_max_inter_io_bytes_ps - case when power_2_max_inter_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_inter_io_bytes_ps))),3)) = 0 then power_2_max_inter_io_byt_ps_10 + 10 else power_2_max_inter_io_byt_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when max_intercon_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_max_inter_io_bytes_ps - case when power_2_max_inter_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_inter_io_bytes_ps))),3)) = 0 then power_2_max_inter_io_byt_ps_10 + 10 else power_2_max_inter_io_byt_ps_10 end)
             end
        end      as max_intercon_io_bytes_per_sec
      , lpad(to_char(round(min_intercon_io_bytes_per_sec / power(2, power_2_min_inter_io_bytes_ps - case when power_2_min_inter_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_inter_io_bytes_ps))),3)) = 0 then power_2_min_inter_io_byt_ps_10 + 10 else power_2_min_inter_io_byt_ps_10 end)), 'FM99999'), 5) ||
        case power_2_min_inter_io_bytes_ps - case when power_2_min_inter_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_inter_io_bytes_ps))),3)) = 0 then power_2_min_inter_io_byt_ps_10 + 10 else power_2_min_inter_io_byt_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when min_intercon_io_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_min_inter_io_bytes_ps - case when power_2_min_inter_io_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_inter_io_bytes_ps))),3)) = 0 then power_2_min_inter_io_byt_ps_10 + 10 else power_2_min_inter_io_byt_ps_10 end)
             end
        end      as min_intercon_io_bytes_per_sec
      , lpad(to_char(round(max_read_mem_bytes_per_sec / power(2, power_2_max_read_mem_bytes_ps - case when power_2_max_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_read_mem_bytes_ps))),3)) = 0 then power_2_max_read_mem_byt_ps_10 + 10 else power_2_max_read_mem_byt_ps_10 end)), 'FM99999'), 5) ||
        case power_2_max_read_mem_bytes_ps - case when power_2_max_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_read_mem_bytes_ps))),3)) = 0 then power_2_max_read_mem_byt_ps_10 + 10 else power_2_max_read_mem_byt_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when max_read_mem_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_max_read_mem_bytes_ps - case when power_2_max_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_max_read_mem_bytes_ps))),3)) = 0 then power_2_max_read_mem_byt_ps_10 + 10 else power_2_max_read_mem_byt_ps_10 end)
             end
        end      as max_read_mem_bytes_per_sec
      , lpad(to_char(round(min_read_mem_bytes_per_sec / power(2, power_2_min_read_mem_bytes_ps - case when power_2_min_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_read_mem_bytes_ps))),3)) = 0 then power_2_min_read_mem_byt_ps_10 + 10 else power_2_min_read_mem_byt_ps_10 end)), 'FM99999'), 5) ||
        case power_2_min_read_mem_bytes_ps - case when power_2_min_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_read_mem_bytes_ps))),3)) = 0 then power_2_min_read_mem_byt_ps_10 + 10 else power_2_min_read_mem_byt_ps_10 end
        when 0            then ' '
        when 1            then ' '
        when 10*1         then 'K'
        when 10*2         then 'M'
        when 10*3         then 'G'
        when 10*4         then 'T'
        when 10*5         then 'P'
        when 10*6         then 'E'
        else case
             when min_read_mem_bytes_per_sec is null
             then null
             else '*2^'||to_char(power_2_min_read_mem_bytes_ps - case when power_2_min_read_mem_bytes_ps >= 10 and trunc(mod(log(10,abs(power(2, power_2_min_read_mem_bytes_ps))),3)) = 0 then power_2_min_read_mem_byt_ps_10 + 10 else power_2_min_read_mem_byt_ps_10 end)
             end
        end      as min_read_mem_bytes_per_sec
      , to_char(nvl(cell_offload_efficiency, 0), '999') || '%' as cell_offload_efficiency
from
        (
          select
                  instance_id
                , duration_secs_t
                , total_read_io_req
                , total_write_io_req
                , read_io_req_per_sec
                , write_io_req_per_sec
                , min_read_io_req_per_sec
                , min_write_io_req_per_sec
                , max_read_io_req_per_sec
                , max_write_io_req_per_sec
                , total_read_mem_bytes
                , total_read_io_bytes
                , total_write_io_bytes
                , total_intercon_io_bytes
                , avg_read_req_size
                , med_read_req_size
                , avg_write_req_size
                , med_write_req_size
                , 100 - round(total_intercon_io_bytes / nullif((total_read_io_bytes + total_write_io_bytes), 0) * 100) as cell_offload_efficiency
                , read_mem_bytes_per_sec
                , read_io_bytes_per_sec
                , write_io_bytes_per_sec
                , intercon_io_bytes_per_sec
                , min_read_mem_bytes_per_sec
                , min_read_io_bytes_per_sec
                , min_write_io_bytes_per_sec
                , min_intercon_io_bytes_per_sec
                , max_read_mem_bytes_per_sec
                , max_read_io_bytes_per_sec
                , max_write_io_bytes_per_sec
                , max_intercon_io_bytes_per_sec
                , trunc(log(2, abs(case total_read_mem_bytes when 0 then 1 else total_read_mem_bytes end)))                    as power_2_t_read_mem_bytes
                , trunc(mod(log(2, abs(case total_read_mem_bytes when 0 then 1 else total_read_mem_bytes end)), 10))           as power_2_t_read_mem_bytes_10
                , trunc(log(2, abs(case total_read_io_bytes when 0 then 1 else total_read_io_bytes end)))                      as power_2_t_read_io_bytes
                , trunc(mod(log(2, abs(case total_read_io_bytes when 0 then 1 else total_read_io_bytes end)), 10))             as power_2_t_read_io_bytes_10
                , trunc(log(2, abs(case total_write_io_bytes when 0 then 1 else total_write_io_bytes end)))                    as power_2_t_write_io_bytes
                , trunc(mod(log(2, abs(case total_write_io_bytes when 0 then 1 else total_write_io_bytes end)), 10))           as power_2_t_write_io_bytes_10
                , trunc(log(10, abs(case total_read_io_req when 0 then 1 else total_read_io_req end)))                         as power_10_total_read_io_req
                , trunc(mod(log(10, abs(case total_read_io_req when 0 then 1 else total_read_io_req end)), 3))                 as power_10_total_read_io_req_3
                , trunc(log(10, abs(case total_write_io_req when 0 then 1 else total_write_io_req end)))                       as power_10_total_write_io_req
                , trunc(mod(log(10, abs(case total_write_io_req when 0 then 1 else total_write_io_req end)), 3))               as power_10_total_write_io_req_3
                , trunc(log(10, abs(case read_io_req_per_sec when 0 then 1 else read_io_req_per_sec end)))                     as power_10_read_io_req_per_sec
                , trunc(mod(log(10, abs(case read_io_req_per_sec when 0 then 1 else read_io_req_per_sec end)), 3))             as power_10_read_io_req_per_sec_3
                , trunc(log(10, abs(case write_io_req_per_sec when 0 then 1 else write_io_req_per_sec end)))                   as power_10_write_io_req_per_sec
                , trunc(mod(log(10, abs(case write_io_req_per_sec when 0 then 1 else write_io_req_per_sec end)), 3))           as power_10_write_io_req_persec_3
                --
                , trunc(log(10, abs(case max_read_io_req_per_sec when 0 then 1 else max_read_io_req_per_sec end)))             as power_10_max_read_io_req_ps
                , trunc(mod(log(10, abs(case max_read_io_req_per_sec when 0 then 1 else max_read_io_req_per_sec end)), 3))     as power_10_max_read_io_req_ps_3
                , trunc(log(10, abs(case max_write_io_req_per_sec when 0 then 1 else max_write_io_req_per_sec end)))           as power_10_max_write_io_req_ps
                , trunc(mod(log(10, abs(case max_write_io_req_per_sec when 0 then 1 else max_write_io_req_per_sec end)), 3))   as power_10_max_write_io_req_ps_3
                , trunc(log(10, abs(case min_read_io_req_per_sec when 0 then 1 else min_read_io_req_per_sec end)))             as power_10_min_read_io_req_ps
                , trunc(mod(log(10, abs(case min_read_io_req_per_sec when 0 then 1 else min_read_io_req_per_sec end)), 3))     as power_10_min_read_io_req_ps_3
                , trunc(log(10, abs(case min_write_io_req_per_sec when 0 then 1 else min_write_io_req_per_sec end)))           as power_10_min_write_io_req_ps
                , trunc(mod(log(10, abs(case min_write_io_req_per_sec when 0 then 1 else min_write_io_req_per_sec end)), 3))   as power_10_min_write_io_req_ps_3
                --
                , trunc(log(2, abs(case total_intercon_io_bytes when 0 then 1 else total_intercon_io_bytes end)))              as power_2_t_intcon_io_bytes
                , trunc(mod(log(2, abs(case total_intercon_io_bytes when 0 then 1 else total_intercon_io_bytes end)), 10))     as power_2_t_intcon_io_bytes_10
                , trunc(log(2, abs(case read_mem_bytes_per_sec when 0 then 1 else read_mem_bytes_per_sec end)))                as power_2_read_mem_bytes_ps
                , trunc(mod(log(2, abs(case read_mem_bytes_per_sec when 0 then 1 else read_mem_bytes_per_sec end)), 10))       as power_2_read_mem_bytes_ps_10
                , trunc(log(2, abs(case read_io_bytes_per_sec when 0 then 1 else read_io_bytes_per_sec end)))                  as power_2_read_io_bytes_ps
                , trunc(mod(log(2, abs(case read_io_bytes_per_sec when 0 then 1 else read_io_bytes_per_sec end)), 10))         as power_2_read_io_bytes_ps_10
                , trunc(log(2, abs(case write_io_bytes_per_sec when 0 then 1 else write_io_bytes_per_sec end)))                as power_2_write_io_bytes_ps
                , trunc(mod(log(2, abs(case write_io_bytes_per_sec when 0 then 1 else write_io_bytes_per_sec end)), 10))       as power_2_write_io_bytes_ps_10
                , trunc(log(2, abs(case intercon_io_bytes_per_sec when 0 then 1 else intercon_io_bytes_per_sec end)))          as power_2_intercon_io_bytes_ps
                , trunc(mod(log(2, abs(case intercon_io_bytes_per_sec when 0 then 1 else intercon_io_bytes_per_sec end)), 10)) as power_2_intercon_io_byte_ps_10
                --
                , trunc(log(2, abs(case max_read_mem_bytes_per_sec when 0 then 1 else max_read_mem_bytes_per_sec end)))                as power_2_max_read_mem_bytes_ps
                , trunc(mod(log(2, abs(case max_read_mem_bytes_per_sec when 0 then 1 else max_read_mem_bytes_per_sec end)), 10))       as power_2_max_read_mem_byt_ps_10
                , trunc(log(2, abs(case max_read_io_bytes_per_sec when 0 then 1 else max_read_io_bytes_per_sec end)))                  as power_2_max_read_io_bytes_ps
                , trunc(mod(log(2, abs(case max_read_io_bytes_per_sec when 0 then 1 else max_read_io_bytes_per_sec end)), 10))         as power_2_max_read_io_byte_ps_10
                , trunc(log(2, abs(case max_write_io_bytes_per_sec when 0 then 1 else max_write_io_bytes_per_sec end)))                as power_2_max_write_io_bytes_ps
                , trunc(mod(log(2, abs(case max_write_io_bytes_per_sec when 0 then 1 else max_write_io_bytes_per_sec end)), 10))       as power_2_max_write_io_byt_ps_10
                , trunc(log(2, abs(case max_intercon_io_bytes_per_sec when 0 then 1 else max_intercon_io_bytes_per_sec end)))          as power_2_max_inter_io_bytes_ps
                , trunc(mod(log(2, abs(case max_intercon_io_bytes_per_sec when 0 then 1 else max_intercon_io_bytes_per_sec end)), 10)) as power_2_max_inter_io_byt_ps_10
                , trunc(log(2, abs(case min_read_mem_bytes_per_sec when 0 then 1 else min_read_mem_bytes_per_sec end)))                as power_2_min_read_mem_bytes_ps
                , trunc(mod(log(2, abs(case min_read_mem_bytes_per_sec when 0 then 1 else min_read_mem_bytes_per_sec end)), 10))       as power_2_min_read_mem_byt_ps_10
                , trunc(log(2, abs(case min_read_io_bytes_per_sec when 0 then 1 else min_read_io_bytes_per_sec end)))                  as power_2_min_read_io_bytes_ps
                , trunc(mod(log(2, abs(case min_read_io_bytes_per_sec when 0 then 1 else min_read_io_bytes_per_sec end)), 10))         as power_2_min_read_io_byte_ps_10
                , trunc(log(2, abs(case min_write_io_bytes_per_sec when 0 then 1 else min_write_io_bytes_per_sec end)))                as power_2_min_write_io_bytes_ps
                , trunc(mod(log(2, abs(case min_write_io_bytes_per_sec when 0 then 1 else min_write_io_bytes_per_sec end)), 10))       as power_2_min_write_io_byt_ps_10
                , trunc(log(2, abs(case min_intercon_io_bytes_per_sec when 0 then 1 else min_intercon_io_bytes_per_sec end)))          as power_2_min_inter_io_bytes_ps
                , trunc(mod(log(2, abs(case min_intercon_io_bytes_per_sec when 0 then 1 else min_intercon_io_bytes_per_sec end)), 10)) as power_2_min_inter_io_byt_ps_10
                --
                , trunc(log(2, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)))                          as power_2_avg_read_req_size
                , trunc(mod(log(2, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)), 10))                 as power_2_avg_read_req_size_10
                , trunc(log(2, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)))                          as power_2_med_read_req_size
                , trunc(mod(log(2, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)), 10))                 as power_2_med_read_req_size_10
                , trunc(log(2, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)))                        as power_2_avg_write_req_size
                , trunc(mod(log(2, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)), 10))               as power_2_avg_write_req_size_10
                , trunc(log(2, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)))                        as power_2_med_write_req_size
                , trunc(mod(log(2, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)), 10))               as power_2_med_write_req_size_10
          from
                  (
                    select
                            instance_id
                          , duration_secs_t
                          , sum_delta_read_io_req                                               as total_read_io_req
                          , sum_delta_write_io_req                                              as total_write_io_req
                          , sum_delta_read_io_bytes                                             as total_read_io_bytes
                          , sum_delta_read_mem_bytes                                            as total_read_mem_bytes
                          , sum_delta_write_io_bytes                                            as total_write_io_bytes
                          , sum_delta_interc_io_bytes                                           as total_intercon_io_bytes
                          , round(avg_delta_read_req_size)                                      as avg_read_req_size
                          , round(med_delta_read_req_size)                                      as med_read_req_size
                          , round(avg_delta_write_req_size)                                     as avg_write_req_size
                          , round(med_delta_write_req_size)                                     as med_write_req_size
                          , round(sum_delta_read_io_req / duration_secs_t)                      as read_io_req_per_sec
                          , round(sum_delta_write_io_req / duration_secs_t)                     as write_io_req_per_sec
                          , round(sum_delta_read_mem_bytes / duration_secs_t)                   as read_mem_bytes_per_sec
                          , round(sum_delta_read_io_bytes / duration_secs_t)                    as read_io_bytes_per_sec
                          , round(sum_delta_write_io_bytes / duration_secs_t)                   as write_io_bytes_per_sec
                          , round(sum_delta_interc_io_bytes / duration_secs_t)                  as intercon_io_bytes_per_sec
                          , round(max_delta_read_io_req_p_s)                                    as max_read_io_req_per_sec
                          , round(max_delta_write_io_req_p_s)                                   as max_write_io_req_per_sec
                          , round(max_delta_read_mem_bytes_p_s)                                 as max_read_mem_bytes_per_sec
                          , round(max_delta_read_io_bytes_p_s)                                  as max_read_io_bytes_per_sec
                          , round(max_delta_write_io_bytes_p_s)                                 as max_write_io_bytes_per_sec
                          , round(max_delta_interc_io_bytes_p_s)                                as max_intercon_io_bytes_per_sec
                          , round(min_delta_read_io_req_p_s)                                    as min_read_io_req_per_sec
                          , round(min_delta_write_io_req_p_s)                                   as min_write_io_req_per_sec
                          , round(min_delta_read_mem_bytes_p_s)                                 as min_read_mem_bytes_per_sec
                          , round(min_delta_read_io_bytes_p_s)                                  as min_read_io_bytes_per_sec
                          , round(min_delta_write_io_bytes_p_s)                                 as min_write_io_bytes_per_sec
                          , round(min_delta_interc_io_bytes_p_s)                                as min_intercon_io_bytes_per_sec
                    from
                            (
                              select
                                     &GROUP_CROSS_INSTANCE                                                     as instance_id
                                     /* Should this be the actual duration from start of execution to last sample or the duration according to the distinct number of sample times */
                                   --, count(distinct sample_time) * &sample_freq                                as duration_secs
                                   , round(((max(sample_time) - min_sql_exec_start) * 86400)) + &sample_freq   as duration_secs_t
                                   , sum(delta_read_io_requests)                                               as sum_delta_read_io_req
                                   , sum(delta_write_io_requests)                                              as sum_delta_write_io_req
                                   , sum(delta_read_io_bytes)                                                  as sum_delta_read_io_bytes
                                   , sum(delta_read_mem_bytes)                                                 as sum_delta_read_mem_bytes
                                   , sum(delta_write_io_bytes)                                                 as sum_delta_write_io_bytes
                                   , sum(delta_interconnect_io_bytes)                                          as sum_delta_interc_io_bytes
                                   , max(sum_delta_read_io_requests_sp)                                        as max_delta_read_io_req_p_s
                                   , max(sum_delta_write_io_requests_sp)                                       as max_delta_write_io_req_p_s
                                   , max(sum_delta_read_mem_bytes_sp)                                          as max_delta_read_mem_bytes_p_s
                                   , max(sum_delta_read_io_bytes_sp)                                           as max_delta_read_io_bytes_p_s
                                   , max(sum_delta_write_io_bytes_sp)                                          as max_delta_write_io_bytes_p_s
                                   , max(sum_delta_interct_io_bytes_sp)                                        as max_delta_interc_io_bytes_p_s
                                   , min(sum_delta_read_io_requests_sp)                                        as min_delta_read_io_req_p_s
                                   , min(sum_delta_write_io_requests_sp)                                       as min_delta_write_io_req_p_s
                                   , min(sum_delta_read_mem_bytes_sp)                                          as min_delta_read_mem_bytes_p_s
                                   , min(sum_delta_read_io_bytes_sp)                                           as min_delta_read_io_bytes_p_s
                                   , min(sum_delta_write_io_bytes_sp)                                          as min_delta_write_io_bytes_p_s
                                   , min(sum_delta_interct_io_bytes_sp)                                        as min_delta_interc_io_bytes_p_s
                                   , avg(delta_read_request_size)                                              as avg_delta_read_req_size
                                   , median(delta_read_request_size)                                           as med_delta_read_req_size
                                   , avg(delta_write_request_size)                                             as avg_delta_write_req_size
                                   , median(delta_write_request_size)                                          as med_delta_write_req_size
                              from
                                     (
                                       select
                                              a.*
                                            , min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) over () as min_sql_exec_start
                                            , sum(delta_read_io_requests / delta_time * 1000000) over (partition by &GROUP_CROSS_INSTANCE, ash_bucket) as sum_delta_read_io_requests_sp
                                            , sum(delta_write_io_requests / delta_time * 1000000) over (partition by &GROUP_CROSS_INSTANCE, ash_bucket) as sum_delta_write_io_requests_sp
                                            , sum(delta_read_mem_bytes / delta_time * 1000000) over (partition by &GROUP_CROSS_INSTANCE, ash_bucket) as sum_delta_read_mem_bytes_sp
                                            , sum(delta_read_io_bytes / delta_time * 1000000) over (partition by &GROUP_CROSS_INSTANCE, ash_bucket) as sum_delta_read_io_bytes_sp
                                            , sum(delta_write_io_bytes / delta_time * 1000000) over (partition by &GROUP_CROSS_INSTANCE, ash_bucket) as sum_delta_write_io_bytes_sp
                                            , sum(delta_interconnect_io_bytes / delta_time * 1000000) over (partition by &GROUP_CROSS_INSTANCE, ash_bucket) as sum_delta_interct_io_bytes_sp
                                       from
                                              (
                                                select
                                                       &inst_id                  as instance_id
                                                     , sql_id
                                                     , cast(sample_time as date) as sample_time
&_IF_ORA112_OR_HIGHER                                                      , delta_time
&_IF_LOWER_THAN_ORA112                                                     , null as delta_time
&_IF_ORA112_OR_HIGHER                                                      , delta_read_io_requests
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_read_io_requests
&_IF_ORA112_OR_HIGHER                                                      , delta_write_io_requests
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_write_io_requests
&_IF_ORA112_OR_HIGHER                                                      , delta_read_io_bytes
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_read_io_bytes
&_IF_ORA112_OR_HIGHER                                                      , delta_write_io_bytes
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_write_io_bytes
&_IF_ORA112_OR_HIGHER                                                      , delta_read_io_bytes / nullif(delta_read_io_requests, 0) as delta_read_request_size
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_read_request_size
&_IF_ORA112_OR_HIGHER                                                      , delta_write_io_bytes / nullif(delta_write_io_requests, 0) as delta_write_request_size
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_write_request_size
&_IF_ORA112_OR_HIGHER                                                      , delta_interconnect_io_bytes
&_IF_LOWER_THAN_ORA112                                                     , 0 as delta_interconnect_io_bytes
&_IF_ORA12_OR_HIGHER                                                       , delta_read_mem_bytes
&_IF_LOWER_THAN_ORA12                                                      , 0 as delta_read_mem_bytes
&_IF_ORA11_OR_HIGHER                                                       , sql_exec_start
&_IF_LOWER_THAN_ORA11                                                      , to_date('01.01.1970', 'DD.MM.YYYY') as sql_exec_start
&_IF_ORA11_OR_HIGHER                                                       , count(sql_exec_start) over (partition by sql_exec_start) as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11                                                      , 1 as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER                                                       , sql_exec_id
                                                                           , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq as ash_bucket
                                                from
                                                        &global_ash ash
                                                where
                                                        sql_id = '&si'
&_IF_ORA11_OR_HIGHER                                                          and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
                                                and     &ash_pred1 &ash_pred2
                                                and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g                                                and     (event is null or event != 'PX Deq Credit: send blkd')
                                              ) a
                                      ) ash
                              where
                              -- only include samples that cover a time period within the execution time period of the SQL statement
&_IF_ORA112_OR_HIGHER                                       ash.sample_time - round(ash.delta_time / 1000000) / 86400 >= ash.sql_exec_start - &sample_freq / 86400
&_IF_LOWER_THAN_ORA112                                      1 = 1
                              and     instr('&op', 'ASH') > 0
                              and     (('&_IF_ORA112_OR_HIGHER' is null
                              and     '&_EXPERIMENTAL' is null) or '&_IF_ORA11203_OR_HIGHER' is null)
                              and     to_number(nvl('&ic', '0')) > &INSTANCE_THRESHOLD
                              -- This prevents the aggregate functions to produce a single row
                              -- in case of no rows generated to aggregate
                              group by
                                      &GROUP_CROSS_INSTANCE
                                    , min_sql_exec_start
                            )
                  )
        )
order by
        instance_id
.

-- If you need to debug, comment the following line
set termout off

save .xplan_ash_temp replace

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     (('&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null)
or      '&_IF_ORA11203_OR_HIGHER' is null)
---------
union all
---------
select
        'SQL Statement I/O Summary based on ASH' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     (('&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null)
or      '&_IF_ORA11203_OR_HIGHER' is null)
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     (('&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null)
or      '&_IF_ORA11203_OR_HIGHER' is null)
;

column message clear

set heading on

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp nolist

set termout on

column instance_id noprint

column duration_secs_t                         heading 'DURATION SECS|TOTAL'
column duration_t                              heading 'DURATION|TOTAL'
column total_read_io_req             format a6 heading 'TOTAL|READ|IO|REQS'        justify left
column total_write_io_req            format a6 heading 'TOTAL|WRITE|IO|REQS'       justify left
column read_io_req_per_sec           format a6 heading 'AVG|READ|IO|REQS|PERSEC'   justify left
column write_io_req_per_sec          format a6 heading 'AVG|WRITE|IO|REQS|PERSEC'  justify left
column min_read_io_req_per_sec       format a6 heading 'MIN|READ|IO|REQS|PERSEC'   justify left
column min_write_io_req_per_sec      format a6 heading 'MIN|WRITE|IO|REQS|PERSEC'  justify left
column max_read_io_req_per_sec       format a6 heading 'MAX|READ|IO|REQS|PERSEC'   justify left
column max_write_io_req_per_sec      format a6 heading 'MAX|WRITE|IO|REQS|PERSEC'  justify left
column total_read_io_bytes           format a6 heading 'TOTAL|READ|IO|BYTES'       justify left
column total_write_io_bytes          format a6 heading 'TOTAL|WRITE|IO|BYTES'      justify left
column avg_read_req_size             format a6 heading 'AVG|READ|REQ|SIZE'         justify left
column med_read_req_size             format a6 heading 'MEDIAN|READ|REQ|SIZE'      justify left
column avg_write_req_size            format a6 heading 'AVG|WRITE|REQ|SIZE'        justify left
column med_write_req_size            format a6 heading 'MEDIAN|WRITE|REQ|SIZE'     justify left
column total_intercon_io_bytes       format a6 heading 'TOTAL|IO|LAYER|BYTES'      justify left
column cell_offload_efficiency       format a5 heading 'CELL|OFFL|EFF'             justify left
column read_io_bytes_per_sec         format a6 heading 'AVG|READ|IO|BYTES|PERSEC'  justify left
column write_io_bytes_per_sec        format a6 heading 'AVG|WRITE|IO|BYTES|PERSEC' justify left
column intercon_io_bytes_per_sec     format a6 heading 'AVG|IO|LAYER|BYTES|PERSEC' justify left
column min_read_io_bytes_per_sec     format a6 heading 'MIN|READ|IO|BYTES|PERSEC'  justify left
column min_write_io_bytes_per_sec    format a6 heading 'MIN|WRITE|IO|BYTES|PERSEC' justify left
column min_intercon_io_bytes_per_sec format a6 heading 'MIN|IO|LAYER|BYTES|PERSEC' justify left
column max_read_io_bytes_per_sec     format a6 heading 'MAX|READ|IO|BYTES|PERSEC'  justify left
column max_write_io_bytes_per_sec    format a6 heading 'MAX|WRITE|IO|BYTES|PERSEC' justify left
column max_intercon_io_bytes_per_sec format a6 heading 'MAX|IO|LAYER|BYTES|PERSEC' justify left
-- Read Mem Bytes was added in 12c to ASH
column read_mem_bytes_per_sec        format a6 heading 'AVG|READ|MEM|BYTES|PERSEC' justify left &_IF_ORA12_OR_HIGHERP.print
column min_read_mem_bytes_per_sec    format a6 heading 'MIN|READ|MEM|BYTES|PERSEC' justify left &_IF_ORA12_OR_HIGHERP.print
column max_read_mem_bytes_per_sec    format a6 heading 'MAX|READ|MEM|BYTES|PERSEC' justify left &_IF_ORA12_OR_HIGHERP.print
column total_read_mem_bytes          format a6 heading 'TOTAL|READ|MEM|BYTES'      justify left &_IF_ORA12_OR_HIGHERP.print

define INSTANCE_THRESHOLD = "0"
define GROUP_CROSS_INSTANCE = "1"

/

set heading off

column message format a52

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     (('&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null)
or      '&_IF_ORA11203_OR_HIGHER' is null)
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'SQL Statement I/O Summary per Instance based on ASH' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     (('&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null)
or      '&_IF_ORA11203_OR_HIGHER' is null)
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '----------------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     (('&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null)
or      '&_IF_ORA11203_OR_HIGHER' is null)
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

set termout off

get .xplan_ash_temp nolist

set termout on

column instance_id print

define INSTANCE_THRESHOLD = "1"
define GROUP_CROSS_INSTANCE = "instance_id"

/

undefine INSTANCE_THRESHOLD
undefine GROUP_CROSS_INSTANCE

column duration_secs_t               clear
column duration_t                    clear
column total_read_io_req             clear
column total_write_io_req            clear
column read_io_req_per_sec           clear
column write_io_req_per_sec          clear
column total_read_io_bytes           clear
column total_write_io_bytes          clear
column avg_read_req_size             clear
column med_read_req_size             clear
column avg_write_req_size            clear
column med_write_req_size            clear
column total_intercon_io_bytes       clear
column cell_offload_efficiency       clear
column read_io_bytes_per_sec         clear
column write_io_bytes_per_sec        clear
column intercon_io_bytes_per_sec     clear
column min_read_io_req_per_sec       clear
column min_write_io_req_per_sec      clear
column max_read_io_req_per_sec       clear
column max_write_io_req_per_sec      clear
column min_read_io_bytes_per_sec     clear
column min_write_io_bytes_per_sec    clear
column min_intercon_io_bytes_per_sec clear
column max_read_io_bytes_per_sec     clear
column max_write_io_bytes_per_sec    clear
column max_intercon_io_bytes_per_sec clear
column read_mem_bytes_per_sec        clear
column min_read_mem_bytes_per_sec    clear
column max_read_mem_bytes_per_sec    clear
column total_read_mem_bytes          clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        'Information on Parallel Degree based on ASH' as message
from
        dual
where
        instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
;

column message clear

set heading on

/* Provide summary info on Instance / DFO level if a plan is available */

column dfo                     heading "DFO|TREE"
column time_active_graph format a&tgs
column instance_id       &_IF_CROSS_INSTANCE.print null "GLOBAL"
column duration_secs_t         heading "DURATION SECS|TOTAL"
column duration_t              heading "DURATION|TOTAL"
column duration_secs           heading "DURATION SECS|ACTIVE"
column duration                heading "DURATION|ACTIVE"
column average_as_t            heading "AVERAGE AS|TOTAL"
column average_as              heading "AVERAGE AS|ACTIVE"
column process_count           heading "PROCESS|COUNT"
column process_unique_count    heading "PROCESS|UNIQUE COUNT"

break on dfo on set_count on assumed_degree on actual_degree

/* This statement is effectively turned into a NOOP in versions below 11g */
with /* XPLAN_ASH PARALLEL_DEGREE_INFO SQL_ID: &si */
set_count
as
(
  select
          dfo
        , max(set_count) as set_count
  from
          (
            select
                    to_number(cast(substr(p.object_node, 3, length(p.object_node) - 5) as varchar2(6)))  as dfo
                  , case when p.operation = 'PX RECEIVE' then 2 else 1 end                               as set_count
            from
                    &plan_table p
            where
                    p.sql_id = '&si'
            and     p.&second_id = &cn
            and     &third_id
            and     p.object_node like ':Q%'
            and     instr('&op', 'DISTRIB') > 0
            and     '&plan_exists' is not null
            and     '&_IF_ORA11_OR_HIGHER' is null
          )
  group by
          dfo
),
ash_base as
(
  select  /*+ cardinality(1000) cardinality(ash 100) use_hash(ash p) no_merge(p) */
          ash.&inst_id                                                                                                                                           as instance_id
        , cast(ash.sample_time as date)                                                                                                                          as sample_time
        , ash.&inst_id || '-' || regexp_replace(coalesce(ash.program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')                  as process
        , session_id
        , session_serial#
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq    as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11202_OR_HIGHER       , px_flags
&_IF_LOWER_THAN_ORA11202      , null as px_flags
&_IF_ORA11202_OR_HIGHER       , trunc(mod(px_flags/65536, 32)) as px_step_id
&_IF_LOWER_THAN_ORA11202      , null as px_step_id
&_IF_ORA11202_OR_HIGHER       , mod(px_flags, 65536) as px_step_arg
&_IF_LOWER_THAN_ORA11202      , null as px_step_arg
&_IF_ORA11_OR_HIGHER          , ash.sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(*) over (partition by ash.sql_exec_start)                        as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('01.01.1970', 'DD.MM.YYYY')                                    as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1                                                                      as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , null as sql_plan_line_id
  from
          &global_ash ash
  where
          ash.sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(ash.sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  -- and     regexp_like(coalesce(ash.program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$')
  and     instr('&op', 'DISTRIB') > 0
  and     '&plan_exists' is not null
  and     '&_IF_ORA11_OR_HIGHER' is null
),
dfo_info as
(
  select
          to_number(cast(substr(p.object_node, 3, length(p.object_node) - 5) as varchar2(6)))                     as dfo
        , to_number(substr(p.object_node, 3 + length(p.object_node) - 5))                                         as tq_id
        , id
  from
          &plan_table p
  where   p.sql_id = '&si'
  and     p.&second_id = &cn
  and     &third_id
  and     p.object_node like ':Q%'
  and     '&plan_exists' is not null
  and     '&_IF_ORA11_OR_HIGHER' is null
),
/* Parallel Degree DOP info taken from Real-Time SQL Monitoring if available / requested (only from 11.2 on reliable) */
monitor_dop_info as
(
  select
&use_monitor &_IF_ORA112_OR_HIGHER              inst_id
&use_monitor &_IF_LOWER_THAN_ORA112             0 as inst_id
&use_no_monitor           0 as inst_id
&use_monitor &_IF_ORA112_OR_HIGHER            , sid
&use_monitor &_IF_LOWER_THAN_ORA112           , 0 as sid
&use_no_monitor         , 0 as sid
&use_monitor &_IF_ORA112_OR_HIGHER            , session_serial#
&use_monitor &_IF_LOWER_THAN_ORA112           , 0 as session_serial#
&use_no_monitor         , 0 as session_serial#
&use_monitor &_IF_ORA112_OR_HIGHER            , count(*) over (partition by px_server_group, px_server_set) as monitor_dop
&use_monitor &_IF_LOWER_THAN_ORA112           , 0  as monitor_dop
&use_no_monitor         , 0  as monitor_dop
  from
&use_monitor &_IF_ORA112_OR_HIGHER              &sql_monitor m
&use_monitor &_IF_LOWER_THAN_ORA112             dual
&use_no_monitor           dual
  where
&use_monitor &_IF_ORA112_OR_HIGHER              1 = 1
&use_monitor &_IF_LOWER_THAN_ORA112             1 = 2
&use_no_monitor           1 = 2
&use_monitor &_IF_ORA112_OR_HIGHER      and     m.sql_id = '&si'
&use_monitor &_IF_ORA112_OR_HIGHER      and     m.sql_exec_start = to_date('&ls', '&dm')
&use_monitor &_IF_ORA112_OR_HIGHER      and     m.sql_exec_id = &li
&use_monitor &_IF_ORA112_OR_HIGHER      and     m.px_qcsid is not null
),
ash_dfo as
(
  select
          instance_id
        , sample_time
        , process
        , session_id
        , ash.session_serial#
        , px_flags
        , sql_exec_start
        , ash_bucket
        , cnt_sql_exec_start
        , min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) over () as min_sql_exec_start
        , p.dfo
&_IF_LOWER_THAN_ORA11202        , count(distinct instance_id || '-' || process) over (partition by p.dfo, p.tq_id) as cnt_process
&_IF_ORA11202_OR_HIGHER         , count(distinct instance_id || '-' || process) over (partition by p.dfo, ash.px_step_id, ash.px_step_arg) as cnt_process
        , m.monitor_dop
  from
          ash_base ash
        , dfo_info p
        , monitor_dop_info m
  where
          p.id = ash.sql_plan_line_id
  and     ash.instance_id = m.inst_id (+)
  and     ash.session_id = m.sid (+)
  and     ash.session_serial# = m.session_serial# (+)
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
driver as
(
  select
          b.instance_id
        , b.sample_time as timeline
        , b.bucket
        , ash_dfo.dfo
  from
          timeline_inst b, (select distinct instance_id, dfo from ash_dfo) ash_dfo
  where
          b.instance_id = ash_dfo.instance_id
),
base_data as
(
  select
          case when count(a.dfo) > 0 then '&gc3' else ' ' end as act_ind
        , count(a.dfo) as active_sessions
        , driver.dfo
        , driver.timeline
        , decode(grouping(driver.instance_id), 1, -1, driver.instance_id) as instance_id
        , driver.bucket as d_bucket
  from
          driver
        , ash_dfo a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.dfo (+) = driver.dfo
  and     a.instance_id (+) = driver.instance_id
  group by
&_IS_SINGL_INSTANCE          driver.instance_id
&_IS_CROSS_INSTANCE          grouping sets(driver.instance_id, ())
        , driver.dfo
        , driver.bucket
        , driver.timeline
  --order by
  --        driver.instance_id
  --      , driver.dfo
  --      , driver.timeline
),
dfo_activity
as
(
  select  /*+ no_merge */
          min(ash_bucket) as min_bucket
        , max(ash_bucket) as max_bucket
        , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
        , dfo
  from
          ash_dfo
  group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
        , dfo
),
median_as as
(
  select
          b.instance_id
        , b.dfo
        , median(b.active_sessions) as median_as
        , stddev_samp(active_sessions) as stddev_as
  from
          base_data b
        , dfo_activity a
  where
          a.instance_id = b.instance_id
  and     a.dfo = b.dfo
  and     b.d_bucket between a.min_bucket and a.max_bucket
  group by
          b.instance_id
        , b.dfo
),
bucket_data as
(
  select
          ntile(&tgs) over (partition by instance_id, dfo order by timeline) as bucket
        , x.*
  from
          base_data x
          -- In case we have less sample times as size of the Time Active Graph
          -- this here will duplicate the data accordingly
        , (select /*+ cardinality(&duplicator) */ null from dual connect by level <= to_number(trim('&duplicator'))) dups
),
grouped_buckets as
(
  select
          max(act_ind) as act_ind
        , bucket
        , dfo
        , instance_id
  from
          bucket_data
  group by
          instance_id
        , dfo
        , bucket
--  order by
--          instance_id
--        , dfo
--        , bucket
),
time_active_graph as
(
  select
          instance_id
        , dfo
&_IF_ORA112_OR_HIGHER         , listagg(act_ind) within group (order by bucket)                        as time_active_graph
          /* leading spaces are trimmed by the XML operation, hence we need to temporarily replace them with something else */
&_IF_LOWER_THAN_ORA112        , replace(extract(xmlagg(xmlelement("V", replace(act_ind, ' ', '?')) order by bucket), '/V/text()').getstringval(), '?', ' ') as time_active_graph
  from
          grouped_buckets
  group by
          instance_id
        , dfo
--  order by
--          instance_id
--        , dfo
)
select  /* XPLAN_ASH PARALLEL_DEGREE_INFO SQL_ID: &si */
        nullif(a.instance_id, -1) as instance_id
      , a.dfo
      , start_active
      , duration_secs_t
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs_t, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs_t, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration_t
      , duration_secs
      , cast(nullif('+' || to_char(extract(day from numtodsinterval(duration_secs, 'SECOND')), 'TM') || ' ' || substr(to_char(numtodsinterval(duration_secs, 'SECOND')), 12, 8), '+ ') as varchar2(12)) as duration
      , sample_count
      , process_count
      , process_unique_count
      , set_count
      , assumed_degree
&_IF_ORA11202_OR_HIGHER      , actual_degree /* / to_number('&ic') */ as actual_degree
      , case when average_as_t >= &rnd_thr then round(average_as_t) else average_as_t end                                                               as average_as_t
      , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
      , case when median_as >= &rnd_thr then round(median_as) else round(median_as, 1) end                                                              as median_as
      , case when stddev_as >= &rnd_thr then round(stddev_as) else round(stddev_as, 1) end                                                              as stddev_as
      --, substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc3', round(duration_secs / to_number('&ds') * &tgs), '&gc3'), 1, &tgs) as time_active_graph
      , t.time_active_graph
from
        (
          select  /*+ cardinality(100) */
                  decode(grouping(instance_id), 1, -1, instance_id) as instance_id
                , sc.dfo
&_IF_ORA11_OR_HIGHER                  , round(min(ash_bucket) + &sample_freq)                                                                   as start_active
&_IF_LOWER_THAN_ORA11                 , 0                                                                                                       as start_active
                , round(max(ash_bucket) - min(ash_bucket) + &sample_freq)                                                 as duration_secs_t
                , count(distinct ash_bucket) * &sample_freq                                                               as duration_secs
                , count(process)                                                                                          as sample_count
                , count(distinct process)                                                                                 as process_count
                , count(distinct case when process is not null then process || '-' || session_id || '-' || session_serial# end) as process_unique_count
                , sc.set_count                                                                                            as set_count
                --, ceil(count(distinct process) / sc.set_count)                                                            as assumed_degree
                , max(coalesce(monitor_dop, cnt_process))                                                                 as assumed_degree
&_IF_ORA11202_OR_HIGHER               , max(trunc(px_flags / 2097152))                                                                          as actual_degree
                , round(count(*) / nullif((max(ash_bucket) - min(ash_bucket) + &sample_freq) / &sample_freq, 0), 1)       as average_as_t
                , round(count(*) / nullif(count(distinct ash_bucket), 0), 1)                                              as average_as
          from
                  ash_dfo pr
                , set_count sc
          where
                  sc.dfo = pr.dfo (+)
          group by
&_IS_SINGL_INSTANCE          instance_id
&_IS_CROSS_INSTANCE          grouping sets(instance_id, ())
                , sc.dfo
                , sc.set_count
                , min_sql_exec_start
        ) a
      , time_active_graph t
      , median_as m
where
        t.instance_id (+) = a.instance_id
and     t.dfo (+) = a.dfo
and     m.instance_id (+) = a.instance_id
and     m.dfo (+) = a.dfo
order by
        a.dfo --to_number(substr(a.dfo, 2))
      , coalesce(a.instance_id, -1)
;

column dfo                   clear
column time_active_graph     clear
column instance_id           clear
column duration_secs_t       clear
column duration_t            clear
column duration_secs         clear
column duration              clear
column average_as_t          clear
column average_as            clear
column process_count         clear
column process_unique_count  clear

clear breaks

/* If DISTRIB option was used and Parallel Execution was expected
   show a message here that no Parallel Execution activity could be found in ASH */

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        '&slave_count' is null and instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        'No Parallel Worker activity found in ASH!' as message
from
        dual
where
        '&slave_count' is null and instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null;

column message clear

set heading on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
---------
union all
---------
select
        'Parallel Worker activity overview based on ASH' as message
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
;

column message clear

set heading on

-- If you need to debug, comment the following line
set termout off

-- Check if this an adaptive plan or not
-- If this is an adaptive plan, always force ADAPTIVE as format option
column is_adaptive_plan new_value is_adaptive_plan &debug_internalp.print
-- This is still set
--column fo               new_value fo               &debug_internalp.print

select
        case when instr(other_xml, 'adaptive_plan') > 0 then 'YES' else 'NO' end       as is_adaptive_plan
      , '&fo' || case when instr(other_xml, 'adaptive_plan') > 0 then ' +ADAPTIVE' end as fo
from
        &plan_table_name p
where
        sql_id = '&si'
and     &second_id = &cn
and     &third_id
and     id = 1
;

column is_adaptive_plan clear

/* Determine if I/O figures / DFO / SET_ID info should be shown or not */
/* Also determines if the ORD(er of execution) column should be shown or not */
/* If we have Parallel Execution and option "no_ord_on_px" set to "YES" (default) or an adaptive plan (12xc) then don't show the ORD column */

column show_io_cols     new_value _SHOW_IO_COLS     &debug_internalp.print
column show_12c_io_cols new_value _SHOW_12C_IO_COLS &debug_internalp.print
column show_set_id      new_value _SHOW_SET_ID      &debug_internalp.print
column show_dfo         new_value _SHOW_DFO         &debug_internalp.print
-- Column C_ORD should still be declared
-- column c_ord        new_value c_ord         noprint

select
        case when (('&_EXPERIMENTAL' is null and '&_IF_ORA112_OR_HIGHER' is null) or '&_IF_ORA11203_OR_HIGHER' is null) then '' else 'no' end         as show_io_cols
      , case when '&_IF_ORA12_OR_HIGHER' is null                                                                        then '' else 'no' end         as show_12c_io_cols
      , case when ('&slave_count' is not null and coalesce('&no_ord_on_px', 'NO') = 'YES') or '&is_adaptive_plan' = 'YES' then null else '&c_ord' end as c_ord
      , case when '&plan_exists' is not null and '&_IF_ORA11_OR_HIGHER' is null and coalesce('&show_px_sets', 'NO') = 'YES' then '' else 'no' end     as show_set_id
      , case when '&plan_exists' is not null and '&_IF_ORA11_OR_HIGHER' is null and coalesce('&show_px_sets', 'NO') = 'YES' then '' else 'no' end     as show_dfo
from
        dual
;

column show_io_cols     clear
column show_12c_io_cols clear
column show_set_id      clear
column show_dfo         clear
-- Column C_ORD will be cleared at the end
-- column c_ord            clear

set termout on

column instance_id &_IF_CROSS_INSTANCE.print
break on instance_id on dfo on set_id skip 1

column process format a64
column dfo heading 'DFO|TREE' &_SHOW_DFO.print null NULL
column set_id &_SHOW_SET_ID.print null NULL
column cnt heading 'SAMPLE|COUNT'
column cnt_cpu heading 'SAMPLE|COUNT|CPU'
column cnt_other heading 'SAMPLE|COUNT|OTHER'
column percentage_cpu heading 'PERCENT|CPU'
column pga  format a6 heading 'MAX|PGA'  &_IF_ORA112_OR_HIGHERP.print
column temp format a6 heading 'MAX|TEMP' &_IF_ORA112_OR_HIGHERP.print
column rd_req format a6 heading 'READ|REQS'             &_SHOW_IO_COLS.print
column wr_req format a6 heading 'WRITE|REQS'            &_SHOW_IO_COLS.print
column rd_byt format a6 heading 'READ|BYTES'            &_SHOW_IO_COLS.print
column wr_byt format a6 heading 'WRITE|BYTES'           &_SHOW_IO_COLS.print
column io_byt format a6 heading 'IO|LAYER|BYTES'        &_SHOW_IO_COLS.print
column rm_byt format a6 heading 'READ|MEM|BYTES'        &_SHOW_12C_IO_COLS.print
column rd_r_s format a6 heading 'READ|REQ|PERSEC'       &_SHOW_IO_COLS.print
column wr_r_s format a6 heading 'WRITE|REQ|PERSEC'      &_SHOW_IO_COLS.print
column rd_b_s format a6 heading 'READ|BYTES|PERSEC'     &_SHOW_IO_COLS.print
column wr_b_s format a6 heading 'WRITE|BYTES|PERSEC'    &_SHOW_IO_COLS.print
column io_b_s format a6 heading 'IO_LAY|BYTES|PERSEC'   &_SHOW_IO_COLS.print
column rm_b_s format a6 heading 'READ|MEM|BYTES|PERSEC' &_SHOW_12C_IO_COLS.print
column a_rr_s format a6 heading 'AVG|RE_REQ|SIZE'       &_SHOW_IO_COLS.print
column m_rr_s format a6 heading 'MEDIAN|RE_REQ|SIZE'    &_SHOW_IO_COLS.print
column a_wr_s format a6 heading 'AVG|WR_REQ|SIZE'       &_SHOW_IO_COLS.print
column m_wr_s format a6 heading 'MEDIAN|WR_REQ|SIZE'    &_SHOW_IO_COLS.print
column plan_lines format a40 heading 'TOP|ACTIVE|PLAN LINES' &_IF_ORA11_OR_HIGHERP.print
column activities format a120 heading 'TOP|ACTIVITIES'
column activity_graph format a&wgs

with /* XPLAN_ASH PARALLEL_SLAVE_ACTIVITY SQL_ID: &si */
/* Base ASH data */
ash_base as
(
  select  /*+ materialize */
          &inst_id                                                                                                                                                      as instance_id
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm')                                                                                                                                         as sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , 0 as sql_plan_line_id
&_IF_ORA11202_OR_HIGHER       , trunc(mod(px_flags/65536, 32)) as px_step_id
&_IF_LOWER_THAN_ORA11202      , null as px_step_id
&_IF_ORA11202_OR_HIGHER       , mod(px_flags, 65536) as px_step_arg
&_IF_LOWER_THAN_ORA11202      , null as px_step_arg
        , cast(sample_time as date)                                                                                                                                     as sample_time
        , session_state
        , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end                                                            as activity
        , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c') as process
        , count(*) over ()                                                                                                                                              as total_cnt
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0) as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0) as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
&_IF_ORA112_OR_HIGHER         , delta_time
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_time
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_io_requests else null end                                    as delta_read_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_requests
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_write_io_requests else null end                                   as delta_write_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_requests
&_IF_ORA12_OR_HIGHER          , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_mem_bytes else null end                                      as delta_read_mem_bytes
&_IF_LOWER_THAN_ORA12         , to_number(null) as delta_read_mem_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_io_bytes else null end                                       as delta_read_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_write_io_bytes else null end                                      as delta_write_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_io_bytes / nullif(delta_read_io_requests, 0) else null end   as delta_read_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_write_io_bytes / nullif(delta_write_io_requests, 0) else null end as delta_write_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_interconnect_io_bytes else null end                               as delta_interconnect_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_interconnect_io_bytes
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
  and     '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
),
set_count as
(
  select
          dfo
        , max(set_count) as set_count
  from
          (
            select
                    to_number(cast(substr(p.object_node, 3, length(p.object_node) - 5) as varchar2(6)))  as dfo
                  , case when p.operation = 'PX RECEIVE' then 2 else 1 end                               as set_count
            from
                    &plan_table p
            where
                    p.sql_id = '&si'
            and     p.&second_id = &cn
            and     &third_id
            and     p.object_node like ':Q%'
            and     instr('&op', 'DISTRIB') > 0
            and     '&plan_exists' is not null
            and     coalesce('&show_px_sets', 'NO') = 'YES'
            and     '&_IF_ORA11_OR_HIGHER' is null
          )
  group by
          dfo
),
dfo_info as
(
  select
          to_number(cast(substr(coalesce(p.object_node, p.next_object_node), 3, length(coalesce(p.object_node, p.next_object_node)) - 5) as varchar2(6))) as dfo
          --to_number(cast(substr(p.object_node, 3, length(p.object_node) - 5) as varchar2(6)))  as dfo
        , to_number(substr(p.object_node, 3 + length(p.object_node) - 5))                      as tq_id
        , id
  from
          (
            select
                    p.*
                  , lead(object_node) over (order by id) as next_object_node
            from
                    &plan_table p
            where
                    p.sql_id = '&si'
            and     p.&second_id = &cn
            and     &third_id
            and     (p.object_node like ':Q%' or p.operation = 'PX COORDINATOR')
            and     instr('&op', 'DISTRIB') > 0
            and     '&plan_exists' is not null
            and     coalesce('&show_px_sets', 'NO') = 'YES'
            and     '&_IF_ORA11_OR_HIGHER' is null
          ) p
),
ash_dfo1 as
(
  select
          ash.*
        , p.dfo
        , p.tq_id
        , sc.set_count
  from
          ash_base ash
        , dfo_info p
        , set_count sc
  where
          p.id   (+) = ash.sql_plan_line_id
  and     sc.dfo (+) = p.dfo
),
ash_dfo2 as
(
  select
          distinct
          instance_id
        , dfo
        , process
        , px_step_id
        , px_step_arg
        , tq_id
        , set_count
  from
          ash_dfo1
  where
          (regexp_like(process, '^P[[:alnum:]][[:alnum:]][[:alnum:]]$') or regexp_like(process, '^[[:digit:]]+-P[[:alnum:]][[:alnum:]][[:alnum:]]$'))
  and     dfo is not null
  and     tq_id is not null
),
px_sets1 as
(
  -- Take advantage of the knowledge about the number of sets per DFO
  -- If we have two sets, we need a more complex logic to arrive at the Slaves per set
  select
          min(process) as min_process
        , max(process) as max_process
        , count(distinct process) as cnt_proc
        , instance_id
        , dfo
        --, tq_id
        --, px_step_id
        --, px_step_arg
  from
          ash_dfo2
  --where
  --        set_count > 1
  group by
          instance_id
        , dfo
&_IF_LOWER_THAN_ORA11202        , tq_id
&_IF_ORA11202_OR_HIGHER         , px_step_id
&_IF_ORA11202_OR_HIGHER         , px_step_arg
--  ---------
--  union all
--  ---------
--  -- If we have just one set, we can simplify the whole logic a lot
--  select
--          min(process) as min_process
--        , max(process) as max_process
--        , count(distinct process) as cnt_proc
--        , instance_id
--        , dfo
--        , tq_id
--        , null as px_step_id
--        , null as px_step_arg
--  from
--          ash_dfo2
--  where
--          set_count = 1
--  group by
--          instance_id
--        , dfo
),
-- Let's jump through hoops to extract set info...
-- First: Let's eliminate any similar sets that are contained in other sets
px_sets2 as
(
  select  distinct
          min_process
        , max_process
        , cnt_proc
        , instance_id
        , dfo
  from
          px_sets1 a
  where
          not exists
          (
            select
                    null
            from
                    px_sets1 b
            where
                    b.instance_id  = a.instance_id
            and     b.dfo          = a.dfo
            and     b.cnt_proc     > a.cnt_proc
            and     b.min_process <= a.min_process
            and     b.max_process >= a.max_process
          )
),
-- Second: Merge sets that overlap by identifying previous max_process
px_sets3 as
(
  select
          lag(max_process, 1, case when to_number(nvl('&ic', '0')) > 1 then '0' else 'P' end) over (partition by instance_id, dfo order by max_process) as prev_max_process
        , a.*
  from
          px_sets2 a
  order by
          instance_id
        , dfo
        , prev_max_process
),
-- and check if current min is larger than previous max, if yes, mark as new set
px_sets4 as
(
  select
          case when prev_max_process < min_process then rownum end as set_indicator1
        , a.*
  from
          px_sets3 a
),
-- Fill in the NULL markers in between for all members of the identified sets
px_sets5 as
(
  select
          last_value(set_indicator1 ignore nulls) over (partition by instance_id, dfo order by prev_max_process, max_process) as set_indicator
        , a.*
  from
          px_sets4 a
),
-- The actual merge of the identified sets
px_sets6 as
(
  select
          min(min_process) as min_process
        , max(max_process) as max_process
        , set_indicator
        , instance_id
        , dfo
  from
          px_sets5
  group by
          instance_id
        , dfo
        , set_indicator
),
-- Turn the set indicator into a number starting at 1 increasing by 1
px_sets7 as
(
  select
          min_process
        , max_process
        , row_number() over (partition by instance_id, dfo order by set_indicator) as set_id
        , instance_id
        , dfo
  from
          px_sets6
),
-- Final Sanity check
-- Discard set info for a DFO if we arrive anywhere at more than two sets
--
-- This can happen if we end up with non overlapping min/max processes per PX step for the same sets
px_sets as
(
  select
          *
  from
          px_sets7 a
  where
          set_id < 3
--          not exists
--          (
--            select
--                    null
--            from
--                    px_sets7 b
--            where
--                    a.dfo = b.dfo
--            and     a.instance_id = b.instance_id
--            and     b.set_id > 2
--          )
),
ash_dfo as
(
  select
          ash_dfo1.*
        , case when ash_dfo1.tq_id is not null then px_sets.set_id end as set_id
  from
          ash_dfo1
        , px_sets
  where
          ash_dfo1.instance_id = px_sets.instance_id (+)
  and     ash_dfo1.dfo = px_sets.dfo (+)
  and     ash_dfo1.process between px_sets.min_process (+) and px_sets.max_process (+)
),
/* The most active plan lines */
/* Count occurrence per process and execution plan line */
ash_plan_lines as
(
  select
          cnt
        , instance_id
        , dfo
        , set_id
        , process
        , sql_plan_line_id
  from
          (
            select
                    count(*) as cnt
                  , instance_id
                  , dfo
                  , set_id
                  , process
                  , sql_plan_line_id
            from
                    ash_dfo
            group by
                    instance_id
                  , dfo
                  , set_id
                  , process
                  , sql_plan_line_id
          )
),
/* The Top N execution plan lines */
ash_plan_lines_rn as
(
  select
          cnt
        , sql_plan_line_id
        , instance_id
        , dfo
        , set_id
        , process
        , row_number() over (partition by instance_id, dfo, set_id, process order by cnt desc, sql_plan_line_id) as rn
  from
          ash_plan_lines
),
/* Aggregate the Top N execution plan lines */
/* This will be joined later to the remaining data */
ash_plan_lines_agg as
(
  select
          instance_id
        , process
        , dfo
        , set_id
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topnl + 1 then null when rn = &topnl + 1 then '...' else coalesce(to_char(sql_plan_line_id), 'NULL') || '(' || cnt || ')' end, ',') within group (order by rn) as plan_lines
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnl + 1 then null when rn = &topnl + 1 then ',' || '...' else ',' || coalesce(to_char(sql_plan_line_id), 'NULL') || '(' || cnt || ')' end) order by rn), '/V/text()'), ',') as plan_lines
  from
          ash_plan_lines_rn
  group by
          instance_id
        , dfo
        , set_id
        , process
),
/* Count occurrence per process and ASH activity */
ash_activity as
(
  select
          cnt
        , activity
        , instance_id
        , dfo
        , set_id
        , process
  from
          (
            select
                    instance_id
                  , dfo
                  , set_id
                  , process
                  , count(*) as cnt
                  , activity
            from
                    ash_dfo
            group by
                    instance_id
                  , dfo
                  , set_id
                  , process
                  , activity
          )
),
/* The Top N activities per bucket */
ash_activity_rn as
(
  select
          cnt
        , activity
        , instance_id
        , dfo
        , set_id
        , process
        , row_number() over (partition by instance_id, dfo, set_id, process order by cnt desc, activity) as rn
  from
          ash_activity
),
/* Aggregate the Top N activity */
/* This will be joined later to the remaining data */
ash_activity_agg as
(
  select
          instance_id
        , dfo
        , set_id
        , process
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topna + 1 then null when rn = &topna + 1 then '...' else case when activity is null then null else activity || '(' || cnt || ')' end end, ',') within group (order by rn) as activities
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topna + 1 then null when rn = &topna + 1 then ',' || '...' else case when activity is null then null else ',' || activity || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as activities
  from
          ash_activity_rn
  group by
          instance_id
        , dfo
        , set_id
        , process
),
/* Group the ASH data by process */
ash_process as
(
  select
          instance_id
        , process
        , total_cnt
        , set_id
        , dfo
        , cnt
        , max(cnt) over () as max_cnt
        , cnt_cpu
        , cnt_other
        , pga_mem
        , temp_space
        , read_req
        , write_req
        , read_mem_bytes
        , read_bytes
        , write_bytes
        , total_io_bytes
        , read_req_per_sec
        , write_req_per_sec
        , read_mem_bytes_per_sec
        , read_bytes_per_sec
        , write_bytes_per_sec
        , tot_io_bytes_per_sec
        , avg_read_req_size
        , med_read_req_size
        , avg_write_req_size
        , med_write_req_size
  from    (
            select
                    process
                  , count(session_state)                                                          as cnt
                  , count(case when session_state = 'ON CPU' then 1 end)                          as cnt_cpu
                  , count(case when session_state != 'ON CPU' then 1 end)                         as cnt_other
                  , max(pga_allocated)                                                            as pga_mem
                  , max(temp_space_allocated)                                                     as temp_space
                  , sum(delta_read_io_requests)                                                   as read_req
                  , sum(delta_write_io_requests)                                                  as write_req
                  , sum(delta_read_mem_bytes)                                                     as read_mem_bytes
                  , sum(delta_read_io_bytes)                                                      as read_bytes
                  , sum(delta_write_io_bytes)                                                     as write_bytes
                  , sum(delta_interconnect_io_bytes)                                              as total_io_bytes
--                  , round(sum(delta_read_io_requests) / &sample_freq  / count(session_state))     as read_req_per_sec
--                  , round(sum(delta_write_io_requests) / &sample_freq / count(session_state))     as write_req_per_sec
--                  , round(sum(delta_read_io_bytes) / &sample_freq / count(session_state))         as read_bytes_per_sec
--                  , round(sum(delta_write_io_bytes) / &sample_freq / count(session_state))        as write_bytes_per_sec
--                  , round(sum(delta_interconnect_io_bytes) / &sample_freq / count(session_state)) as tot_io_bytes_per_sec
                  , round(avg(delta_read_io_requests / delta_time * 1000000))                     as read_req_per_sec
                  , round(avg(delta_write_io_requests / delta_time * 1000000))                    as write_req_per_sec
                  , round(avg(delta_read_mem_bytes / delta_time * 1000000))                       as read_mem_bytes_per_sec
                  , round(avg(delta_read_io_bytes / delta_time * 1000000))                        as read_bytes_per_sec
                  , round(avg(delta_write_io_bytes / delta_time * 1000000))                       as write_bytes_per_sec
                  , round(avg(delta_interconnect_io_bytes / delta_time * 1000000))                as tot_io_bytes_per_sec
                  , round(avg(delta_read_request_size))                                           as avg_read_req_size
                  , round(median(delta_read_request_size))                                        as med_read_req_size
                  , round(avg(delta_write_request_size))                                          as avg_write_req_size
                  , round(median(delta_write_request_size))                                       as med_write_req_size
                  , instance_id
                  , total_cnt
                  , set_id
                  , dfo
            from
                    ash_dfo
            group by
                    instance_id
                  , dfo
                  , set_id
                  , process
                  , total_cnt
          )
),
/* We need some log based data for formatting the figures */
ash_process_prefmt as
(
  select
          instance_id
        , process
        , pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                        as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                               as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                                  as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                         as power_2_temp_space_mod_10
        , read_req
        , trunc(log(10, abs(case read_req when 0 then 1 else read_req end)))                                     as power_10_read_req
        , trunc(mod(log(10, abs(case read_req when 0 then 1 else read_req end)), 3))                             as power_10_read_req_mod_3
        , write_req
        , trunc(log(10, abs(case write_req when 0 then 1 else write_req end)))                                   as power_10_write_req
        , trunc(mod(log(10, abs(case write_req when 0 then 1 else write_req end)), 3))                           as power_10_write_req_mod_3
        , avg_read_req_size
        , trunc(log(2, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)))                    as power_2_avg_read_req_size
        , trunc(mod(log(2, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)), 10))           as power_2_avg_read_req_size_10
        , med_read_req_size
        , trunc(log(2, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)))                    as power_2_med_read_req_size
        , trunc(mod(log(2, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)), 10))           as power_2_med_read_req_size_10
        , avg_write_req_size
        , trunc(log(2, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)))                  as power_2_avg_write_req_size
        , trunc(mod(log(2, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)), 10))         as power_2_avg_write_req_size_10
        , med_write_req_size
        , trunc(log(2, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)))                  as power_2_med_write_req_size
        , trunc(mod(log(2, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)), 10))         as power_2_med_write_req_size_10
        , read_mem_bytes
        , trunc(log(2, abs(case read_mem_bytes when 0 then 1 else read_mem_bytes end)))                          as power_2_read_mem_bytes
        , trunc(mod(log(2, abs(case read_mem_bytes when 0 then 1 else read_mem_bytes end)), 10))                 as power_2_read_mem_bytes_mod_10
        , read_bytes
        , trunc(log(2, abs(case read_bytes when 0 then 1 else read_bytes end)))                                  as power_2_read_bytes
        , trunc(mod(log(2, abs(case read_bytes when 0 then 1 else read_bytes end)), 10))                         as power_2_read_bytes_mod_10
        , write_bytes
        , trunc(log(2, abs(case write_bytes when 0 then 1 else write_bytes end)))                                as power_2_write_bytes
        , trunc(mod(log(2, abs(case write_bytes when 0 then 1 else write_bytes end)), 10))                       as power_2_write_bytes_mod_10
        , total_io_bytes
        , trunc(log(2, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)))                          as power_2_total_io_bytes
        , trunc(mod(log(2, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)), 10))                 as power_2_total_io_bytes_mod_10
        , read_req_per_sec
        , trunc(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)))                     as power_10_read_req_per_sec
        , trunc(mod(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)), 3))             as power_10_read_req_ps_mod_3
        , write_req_per_sec
        , trunc(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)))                   as power_10_write_req_per_sec
        , trunc(mod(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)), 3))           as power_10_write_req_ps_mod_3
        , read_mem_bytes_per_sec
        , trunc(log(2, abs(case read_mem_bytes_per_sec when 0 then 1 else read_mem_bytes_per_sec end)))          as power_2_read_mem_bytes_per_sec
        , trunc(mod(log(2, abs(case read_mem_bytes_per_sec when 0 then 1 else read_mem_bytes_per_sec end)), 10)) as power_2_read_mem_byt_ps_mod_10
        , read_bytes_per_sec
        , trunc(log(2, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)))                  as power_2_read_bytes_per_sec
        , trunc(mod(log(2, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)), 10))         as power_2_read_bytes_ps_mod_10
        , write_bytes_per_sec
        , trunc(log(2, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)))                as power_2_write_bytes_per_sec
        , trunc(mod(log(2, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)), 10))       as power_2_write_bytes_ps_mod_10
        , tot_io_bytes_per_sec
        , trunc(log(2, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)))              as power_2_tot_io_bytes_per_sec
        , trunc(mod(log(2, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)), 10))     as power_2_tot_io_bytes_ps_mod_10
        , cnt
        , cnt_cpu
        , cnt_other
        , total_cnt
        , max_cnt
        , set_id
        , dfo
        , round(cnt_cpu / cnt * 100)                                                                          as percentage_cpu
  from
          ash_process
),
/* Format the figures */
ash_process_fmt as
(
  select
          instance_id
        , process
        , to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , to_char(round(read_req / power(10, power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)), 'FM99999') ||
          case power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req is null
               then null
               else '*10^'||to_char(power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)
               end
          end      as read_req
        , to_char(round(avg_read_req_size / power(2, power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end)), 'FM99999') ||
          case power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when avg_read_req_size is null
               then null
               else '*2^'||to_char(power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end)
               end
          end      as avg_read_req_size
        , to_char(round(med_read_req_size / power(2, power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end)), 'FM99999') ||
          case power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when med_read_req_size is null
               then null
               else '*2^'||to_char(power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end)
               end
          end      as med_read_req_size
        , to_char(round(avg_write_req_size / power(2, power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end)), 'FM99999') ||
          case power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when avg_write_req_size is null
               then null
               else '*2^'||to_char(power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end)
               end
          end      as avg_write_req_size
        , to_char(round(med_write_req_size / power(2, power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end)), 'FM99999') ||
          case power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when med_write_req_size is null
               then null
               else '*2^'||to_char(power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end)
               end
          end      as med_write_req_size
        , to_char(round(write_req / power(10, power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)), 'FM99999') ||
          case power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req is null
               then null
               else '*10^'||to_char(power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)
               end
          end      as write_req
        , to_char(round(read_mem_bytes / power(2, power_2_read_mem_bytes - case when power_2_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes))),3)) = 0 then power_2_read_mem_bytes_mod_10 + 10 else power_2_read_mem_bytes_mod_10 end)), 'FM99999') ||
          case power_2_read_mem_bytes - case when power_2_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes))),3)) = 0 then power_2_read_mem_bytes_mod_10 + 10 else power_2_read_mem_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_mem_bytes is null
               then null
               else '*2^'||to_char(power_2_read_mem_bytes - case when power_2_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes))),3)) = 0 then power_2_read_mem_bytes_mod_10 + 10 else power_2_read_mem_bytes_mod_10 end)
               end
          end      as read_mem_bytes
        , to_char(round(read_bytes / power(2, power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end)), 'FM99999') ||
          case power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_bytes is null
               then null
               else '*2^'||to_char(power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end)
               end
          end      as read_bytes
        , to_char(round(write_bytes / power(2, power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end)), 'FM99999') ||
          case power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when write_bytes is null
               then null
               else '*2^'||to_char(power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end)
               end
          end      as write_bytes
        , to_char(round(total_io_bytes / power(2, power_2_total_io_bytes - case when power_2_total_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_total_io_bytes))),3)) = 0 then power_2_total_io_bytes_mod_10 + 10 else power_2_total_io_bytes_mod_10 end)), 'FM99999') ||
          case power_2_total_io_bytes - case when power_2_total_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_total_io_bytes))),3)) = 0 then power_2_total_io_bytes_mod_10 + 10 else power_2_total_io_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when total_io_bytes is null
               then null
               else '*2^'||to_char(power_2_total_io_bytes - case when power_2_total_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_total_io_bytes))),3)) = 0 then power_2_total_io_bytes_mod_10 + 10 else power_2_total_io_bytes_mod_10 end)
               end
          end      as total_io_bytes
        , to_char(round(read_req_per_sec / power(10, power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)
               end
          end      as read_req_per_sec
        , to_char(round(write_req_per_sec / power(10, power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)
               end
          end      as write_req_per_sec
        , to_char(round(read_mem_bytes_per_sec / power(2, power_2_read_mem_bytes_per_sec - case when power_2_read_mem_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_per_sec))),3)) = 0 then power_2_read_mem_byt_ps_mod_10 + 10 else power_2_read_mem_byt_ps_mod_10 end)), 'FM99999') ||
          case power_2_read_mem_bytes_per_sec - case when power_2_read_mem_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_per_sec))),3)) = 0 then power_2_read_mem_byt_ps_mod_10 + 10 else power_2_read_mem_byt_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_mem_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_read_mem_bytes_per_sec - case when power_2_read_mem_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_per_sec))),3)) = 0 then power_2_read_mem_byt_ps_mod_10 + 10 else power_2_read_mem_byt_ps_mod_10 end)
               end
          end      as read_mem_bytes_per_sec
        , to_char(round(read_bytes_per_sec / power(2, power_2_read_bytes_per_sec - case when power_2_read_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes_per_sec))),3)) = 0 then power_2_read_bytes_ps_mod_10 + 10 else power_2_read_bytes_ps_mod_10 end)), 'FM99999') ||
          case power_2_read_bytes_per_sec - case when power_2_read_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes_per_sec))),3)) = 0 then power_2_read_bytes_ps_mod_10 + 10 else power_2_read_bytes_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_read_bytes_per_sec - case when power_2_read_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes_per_sec))),3)) = 0 then power_2_read_bytes_ps_mod_10 + 10 else power_2_read_bytes_ps_mod_10 end)
               end
          end      as read_bytes_per_sec
        , to_char(round(write_bytes_per_sec / power(2, power_2_write_bytes_per_sec - case when power_2_write_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes_per_sec))),3)) = 0 then power_2_write_bytes_ps_mod_10 + 10 else power_2_write_bytes_ps_mod_10 end)), 'FM99999') ||
          case power_2_write_bytes_per_sec - case when power_2_write_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes_per_sec))),3)) = 0 then power_2_write_bytes_ps_mod_10 + 10 else power_2_write_bytes_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when write_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_write_bytes_per_sec - case when power_2_write_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes_per_sec))),3)) = 0 then power_2_write_bytes_ps_mod_10 + 10 else power_2_write_bytes_ps_mod_10 end)
               end
          end      as write_bytes_per_sec
        , to_char(round(tot_io_bytes_per_sec / power(2, power_2_tot_io_bytes_per_sec - case when power_2_tot_io_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_tot_io_bytes_per_sec))),3)) = 0 then power_2_tot_io_bytes_ps_mod_10 + 10 else power_2_tot_io_bytes_ps_mod_10 end)), 'FM99999') ||
          case power_2_tot_io_bytes_per_sec - case when power_2_tot_io_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_tot_io_bytes_per_sec))),3)) = 0 then power_2_tot_io_bytes_ps_mod_10 + 10 else power_2_tot_io_bytes_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when tot_io_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_tot_io_bytes_per_sec - case when power_2_tot_io_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_tot_io_bytes_per_sec))),3)) = 0 then power_2_tot_io_bytes_ps_mod_10 + 10 else power_2_tot_io_bytes_ps_mod_10 end)
               end
          end      as tot_io_bytes_per_sec
        , cnt
        , cnt_cpu
        , cnt_other
        , percentage_cpu
        , set_id
        , dfo
        , substr(rpad('&gc', nvl(round(cnt_cpu / nullif(max_cnt, 0) * &wgs), 0), '&gc') || rpad('&gc2', nvl(round(cnt_other / nullif(max_cnt, 0) * &wgs), 0), '&gc2'), 1, &wgs) as activity_graph
  from
          ash_process_prefmt
)
/* The final set including the Top N plan lines and Top N activities */
select  /* XPLAN_ASH PARALLEL_SLAVE_ACTIVITY SQL_ID: &si */
        /* 11.2.0.1 again generates a ORA-03113 during parse due to the COUNT(DISTINCT...), so falling back to 11.1.0.7 optimizer features */
        /*+ optimizer_features_enable('11.1.0.7') */
        a.instance_id
      , a.dfo
      , a.set_id
      , a.process
      , cnt
      , activity_graph
      , cnt_cpu
      , cnt_other
      , percentage_cpu
      , lpad(pga_mem_format, 6)         as pga
      , lpad(temp_space_format, 6)      as temp
      , b.plan_lines
      , c.activities
      , lpad(read_req, 6)               as rd_req
      , lpad(write_req, 6)              as wr_req
      , lpad(read_req_per_sec, 6)       as rd_r_s
      , lpad(write_req_per_sec, 6)      as wr_r_s
      , lpad(read_bytes, 6)             as rd_byt
      , lpad(write_bytes, 6)            as wr_byt
      , lpad(total_io_bytes, 6)         as io_byt
      , lpad(read_mem_bytes, 6)         as rm_byt
      , lpad(read_bytes_per_sec, 6)     as rd_b_s
      , lpad(write_bytes_per_sec, 6)    as wr_b_s
      , lpad(tot_io_bytes_per_sec, 6)   as io_b_s
      , lpad(read_mem_bytes_per_sec, 6) as rm_b_s
      , lpad(avg_read_req_size, 6)      as a_rr_s
      , lpad(med_read_req_size, 6)      as m_rr_s
      , lpad(avg_write_req_size, 6)     as a_wr_s
      , lpad(med_write_req_size, 6)     as m_wr_s
from
        ash_process_fmt a
      , ash_plan_lines_agg b
      , ash_activity_agg c
where
        a.instance_id = b.instance_id (+)
and     coalesce(a.dfo, -1) = coalesce(b.dfo (+), -1)
and     coalesce(a.set_id, -1) = coalesce(b.set_id (+), -1)
and     a.process = b.process (+)
and     a.instance_id = c.instance_id (+)
and     coalesce(a.dfo, -1) = coalesce(c.dfo (+), -1)
and     coalesce(a.set_id, -1) = coalesce(c.set_id (+), -1)
and     a.process = c.process (+)
order by
        a.dfo --coalesce(to_number(substr(a.dfo, 2)), -1)
      , coalesce(set_id, -1)
      , coalesce(a.instance_id, -1)
      , process
;

column process clear
column cnt clear
column cnt_cpu clear
column cnt_other clear
column percentage_cpu clear
column pga  clear
column temp clear
column rd_req clear
column wr_req clear
column rm_byt clear
column rd_byt clear
column wr_byt clear
column io_byt clear
column rd_r_s clear
column wr_r_s clear
column rm_b_s clear
column rd_b_s clear
column wr_b_s clear
column io_b_s clear
column a_rr_s clear
column m_rr_s clear
column a_wr_s clear
column m_wr_s clear
column plan_lines clear
column activities clear
column instance_id    clear
column activity_graph clear
column set_id clear
column dfo clear

clear breaks

undefine _SHOW_12C_IO_COLS
undefine _SHOW_IO_COLS
undefine _SHOW_SET_ID
undefine _SHOW_DFO

set heading on

/* Various activity summaries */

/* The following query will be used multiple times with different parameters and therefore written to a temporary file */

select  /* XPLAN_ASH ACTIVITY_SUMMARY SQL_ID: &si */
        &GROUP_CROSS_INSTANCE as instance_id
&INCLUDE_ACTIVITY      , activity
      , activity_class
      , round(avg(time_waited) / 1000, 1)                                           as avg_tim_wait_ms
      , round(median(time_waited) / 1000, 1)                                        as med_tim_wait_ms
      , count(*)                                                                    as sample_count
      , round(count(*) / total_cnt * 100)                                           as percentage
      , rpad('&gc3', nvl(round(count(*) / nullif(total_cnt, 0) * &wgs), 0), '&gc3') as activity_graph
from
        (
                    select
                            &inst_id as instance_id
                          , case when session_state = 'WAITING' then nvl(wait_class, '<Wait Class Is Null>') else session_state end as activity_class
                          , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end      as activity
                          , case when session_state = 'WAITING' then nullif(time_waited, 0) else null end                           as time_waited
                          , count(*) over ()                                                                                        as total_cnt
                    from
                            &global_ash ash
                    where
                            sql_id = '&si'
&_IF_ORA11_OR_HIGHER                              and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
                    and     &ash_pred1 &ash_pred2
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g                    and     (event is null or event != 'PX Deq Credit: send blkd')
                    and     instr('&op', 'ASH') > 0
                    and     to_number(nvl('&ic', '0')) > &INSTANCE_THRESHOLD
        )
group by
        &GROUP_CROSS_INSTANCE
&INCLUDE_ACTIVITY      , activity
      , activity_class
      , total_cnt
order by
        &GROUP_CROSS_INSTANCE
      , sample_count desc
.

-- If you need to debug, comment the following line
set termout off

save .xplan_ash_temp replace

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Activity Class Summary' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

column activity_class format a20
column activity_graph format a&wgs
column instance_id noprint
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp nolist

set termout on

define INSTANCE_THRESHOLD = "0"
define GROUP_CROSS_INSTANCE = "1"
define INCLUDE_ACTIVITY = "--"

/

column activity_class clear
column activity_graph clear
column instance_id clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'Activity Class Summary per Instance' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
break on instance_id

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp nolist

set termout on

define INSTANCE_THRESHOLD = "1"
define GROUP_CROSS_INSTANCE = "instance_id"
define INCLUDE_ACTIVITY = "--"

/

column activity_class clear
column activity_graph clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

clear breaks

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Activity Summary' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

column activity format a50
column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
column instance_id noprint

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp nolist

set termout on

define INSTANCE_THRESHOLD = "0"
define GROUP_CROSS_INSTANCE = "1"
define INCLUDE_ACTIVITY = ""

/

column activity clear
column activity_class clear
column activity_graph clear
column instance_id clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'Activity Summary per Instance' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

column activity format a50
column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
break on instance_id

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp nolist

set termout on

define INSTANCE_THRESHOLD = "1"
define GROUP_CROSS_INSTANCE = "instance_id"
define INCLUDE_ACTIVITY = ""

/

column activity clear
column activity_class clear
column activity_graph clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

clear breaks

undefine INSTANCE_THRESHOLD
undefine GROUP_CROSS_INSTANCE
undefine INCLUDE_ACTIVITY
undefine _SHOW_WAIT_TIMES

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        'Activity Timeline based on ASH' as message
from
        dual
where
        (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
;

column message clear

set heading on

/* Activity Timeline */

-- If you need to debug, comment the following line
set termout off

/* Determine if I/O figures should be shown or not */

column show_12c_io_cols new_value _SHOW_12C_IO_COLS &debug_internalp.print
column show_io_cols new_value _SHOW_IO_COLS         &debug_internalp.print
column aas_size new_value aas_size                  &debug_internalp.print
column show_dfo_col new_value _SHOW_DFO_COL         &debug_internalp.print
column dop_header new_value _DOP_HEADER             &debug_internalp.print
column break_cross_instance new_value _BREAK_CI     &debug_internalp.print

select
        case when (('&_EXPERIMENTAL' is null and '&_IF_ORA112_OR_HIGHER' is null) or '&_IF_ORA11203_OR_HIGHER' is null) then '' else 'no' end as show_io_cols
      , case when '&_IF_ORA12_OR_HIGHER' is null                                                                        then '' else 'no' end as show_12c_io_cols
      , to_char(&aas + 8, 'TM') as aas_size
      , case when '&slave_count' is not null and '&plan_exists' is not null and '&_IF_ORA11_OR_HIGHER' is null then '' else 'no' end as show_dfo_col
      , case when '&_IF_ORA11202_OR_HIGHER' is null then ' [DOP]' else '' end as dop_header
      , case when '&_IF_CROSS_INSTANCE' is null then 'on break_instance_id skip 1' else '' end as break_cross_instance
from
        dual
;

column show_12c_io_cols clear
column show_io_cols clear
column aas_size clear
column show_dfo_col clear
column dop_header clear
column break_cross_instance clear

set termout on

column average_as_graph format a&aas_size heading 'AVERAGE|ACTIVE SESSIONS|GRAPH'
-- Hide this column as it usually doesn't add much value
column median_as_graph format a&aas_size heading 'MEDIAN|ACTIVE SESSIONS|GRAPH' &show_median.print
column instance_id &_IF_CROSS_INSTANCE.print null "GLOBAL"

column pga  format a6 &_IF_ORA112_OR_HIGHERP.print
column temp format a6 &_IF_ORA112_OR_HIGHERP.print
column rd_req format a6 heading 'READ|REQS'             &_SHOW_IO_COLS.print
column wr_req format a6 heading 'WRITE|REQS'            &_SHOW_IO_COLS.print
column rd_byt format a6 heading 'READ|BYTES'            &_SHOW_IO_COLS.print
column wr_byt format a6 heading 'WRITE|BYTES'           &_SHOW_IO_COLS.print
column io_byt format a6 heading 'IO|LAYER|BYTES'        &_SHOW_IO_COLS.print
column rm_byt format a6 heading 'READ|MEM|BYTES'        &_SHOW_12C_IO_COLS.print
column rd_r_s format a6 heading 'READ|REQ|PERSEC'       &_SHOW_IO_COLS.print
column wr_r_s format a6 heading 'WRITE|REQ|PERSEC'      &_SHOW_IO_COLS.print
column rd_b_s format a6 heading 'READ|BYTES|PERSEC'     &_SHOW_IO_COLS.print
column wr_b_s format a6 heading 'WRITE|BYTES|PERSEC'    &_SHOW_IO_COLS.print
column io_b_s format a6 heading 'IO_LAY|BYTES|PERSEC'   &_SHOW_IO_COLS.print
column rm_b_s format a6 heading 'READ|MEM|BYTES|PERSEC' &_SHOW_12C_IO_COLS.print
column a_rr_s format a6 heading 'AVG|RE_REQ|SIZE'       &_SHOW_IO_COLS.print
column m_rr_s format a6 heading 'MEDIAN|RE_REQ|SIZE'    &_SHOW_IO_COLS.print
column a_wr_s format a6 heading 'AVG|WR_REQ|SIZE'       &_SHOW_IO_COLS.print
column m_wr_s format a6 heading 'MEDIAN|WR_REQ|SIZE'    &_SHOW_IO_COLS.print
column plan_lines format a40 heading 'TOP|ACTIVE|PLAN LINES' &_IF_ORA11_OR_HIGHERP.print
column dfo_active format a25 heading 'ACTIVE|DFO|TREES&_DOP_HEADER (AAS)' &_SHOW_DFO_COL.print
column activities format a120 heading 'TOP|ACTIVITIES'
column processes  format a85 heading 'TOP|PROCESSES'
column average_as heading 'AVERAGE|ACTIVE|SESSIONS'
column median_as  heading 'MEDIAN|ACTIVE|SESSIONS'
column stddev_as  heading 'STDDEV|ACTIVE|SESSIONS'
-- Hide this column as it usually doesn't add much value
column cpu_median &show_median.print
-- Hide this column as it usually doesn't add much value
column other_median &show_median.print
column break_instance_id noprint
break on duration_secs &_BREAK_CI

with /* XPLAN_ASH ACTIVITY_TIMELINE SQL_ID: &si */
/* Base ASH data */
ash_base as
(
  select  /*+ materialize */
          &inst_id                  as instance_id
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start)    as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm')                                       as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1                                                           as cnt_sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , 0                                                           as sql_plan_line_id
        , cast(sample_time as date)                                   as sample_time
        , session_state
        , session_id
        , session_serial#
        -- According to DELTA_TIME the time the previous sample took place
        -- DELTA_TIME is only available from 11.2 on
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                                                                                        as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                                                                                as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq                            as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                                                                                         as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq                                                                   as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                                                                  as ash_prev_bucket
        , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end                                                                                              as activity
        , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')                 as process
&_IF_ORA112_OR_HIGHER         , delta_time
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_time
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0)                                                                                                                                                                        as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0)                                                                                                                                                                 as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_io_requests else null end                                    as delta_read_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_requests
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_write_io_requests else null end                                   as delta_write_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_requests
&_IF_ORA12_OR_HIGHER          , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_mem_bytes else null end                                      as delta_read_mem_bytes
&_IF_LOWER_THAN_ORA12         , to_number(null) as delta_read_mem_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_io_bytes else null end                                       as delta_read_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_write_io_bytes else null end                                      as delta_write_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_read_io_bytes / nullif(delta_read_io_requests, 0) else null end   as delta_read_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_write_io_bytes / nullif(delta_write_io_requests, 0) else null end as delta_write_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS')) - &sample_freq / 86400 then delta_interconnect_io_bytes else null end                               as delta_interconnect_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_interconnect_io_bytes
&_IF_ORA11202_OR_HIGHER       , trunc(px_flags / 2097152) as actual_degree
&_IF_LOWER_THAN_ORA11202      , to_number(null) as actual_degree
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
-- For versions before 11g, consider the event "PX Deq Credit: send blkd" to be idle (as it is done from 11g on)
&_IF_LOWER_THAN_ORA11 &ignore_PX_credit_blkd_10g  and     (event is null or event != 'PX Deq Credit: send blkd')
  and     (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
        -- Buckets of the official timeline
        , bucket
        , duration_secs
--        , trunc(round((t.timeline - t.sql_exec_start) * 86400) / &sample_freq) * &sample_freq as bucket
--        , round((t.timeline - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
  from
          timeline t
        , instance_data i
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data1 as
(
  /* The 11.2 ASH data has a DELTA_TIME indicator that allows telling how long the previous sample of that particular session was ago */
  /* This is expressed in the PREV_SAMPLE_TIME information calculated based on SAMPLE_TIME and DELTA_TIME */
  /* So for PGA/TEMP figures we can produce "artificial" rows for those sample_times where no actual sampling of that particular session took place */
  /* But according to DELTA_TIME that particular sample was still "valid" in the past */
  /* The purpose of this is to get a "smoother" picture of PGA/TEMP allocation for Parallel Execution where not every sample time */
  /* all involved Parallel Workers will be sampled */
  /* Since this results in a poorly performing outer range join, this is now divided into three parts */
  --
  /* Part one: The data that covers exactly one bucket can be equi-joined, no artificial rows here */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        , t.duration_secs
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.session_state
        , ash.activity
        , ash.process
        , ash.sql_plan_line_id
        , ash.delta_time
        , ash.delta_read_io_requests
        , ash.delta_write_io_requests
        , ash.delta_read_mem_bytes
        , ash.delta_read_io_bytes
        , ash.delta_write_io_bytes
        , ash.delta_read_request_size
        , ash.delta_write_request_size
        , ash.delta_interconnect_io_bytes
        , ash.actual_degree
        , cast(to_char(null) as varchar2(1)) as artificial_indicator
  from
          timeline_inst t
        , ash_base ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
  -- Rows that at most cover one bucket (or even fall within the same bucket)
  and     ash.ash_prev_bucket >= ash.ash_bucket - &sample_freq
  ---------
  union all
  ---------
  /* Part two: The data spanning more than a bucket needs to be range joined */
  /* But we can dramatically lower the size of the row source to join by restricting to those spanning more than a single bucket */
  /* Here the artificial rows will be generated */
  select
          t.sample_time
        , t.bucket
        , ash.sample_time as ash_sample_time
        , ash.ash_bucket
        , ash.prev_sample_time
        , ash.ash_prev_bucket
        , t.instance_id
        /* Only use remaining fields for those non-artificial rows (see below for an explanation) */
        , t.duration_secs
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.session_state
        , ash.activity
        , ash.process
        , ash.sql_plan_line_id
        , ash.delta_time
        , ash.delta_read_io_requests
        , ash.delta_write_io_requests
        , ash.delta_read_mem_bytes
        , ash.delta_read_io_bytes
        , ash.delta_write_io_bytes
        , ash.delta_read_request_size
        , ash.delta_write_request_size
        , ash.delta_interconnect_io_bytes
        , ash.actual_degree
        , ash.artificial_indicator
  from
          timeline_inst t
        , (
&use_no_lateral            select  /*+ use_merge(ash dup) no_merge */
&use_lateral               select  /*+ no_merge */
                    ash.sample_time
                  , ash_bucket - lvl + &sample_freq as ash_bucket
                  , ash.instance_id
                  , ash.prev_sample_time
                  , ash.ash_prev_bucket
                  , ash.pga_allocated
                  , ash.temp_space_allocated
                  , case when lvl = &sample_freq then ash.session_state end as session_state
                  , case when lvl = &sample_freq then ash.activity end as activity
                  , case when lvl = &sample_freq then ash.process end as process
                  , case when lvl = &sample_freq then ash.sql_plan_line_id end as sql_plan_line_id
                  , case when lvl = &sample_freq then ash.delta_time end as delta_time
                  , case when lvl = &sample_freq then ash.delta_read_io_requests end as delta_read_io_requests
                  , case when lvl = &sample_freq then ash.delta_write_io_requests end as delta_write_io_requests
                  , case when lvl = &sample_freq then ash.delta_read_mem_bytes end as delta_read_mem_bytes
                  , case when lvl = &sample_freq then ash.delta_read_io_bytes end as delta_read_io_bytes
                  , case when lvl = &sample_freq then ash.delta_write_io_bytes end as delta_write_io_bytes
                  , case when lvl = &sample_freq then ash.delta_read_request_size end as delta_read_request_size
                  , case when lvl = &sample_freq then ash.delta_write_request_size end as delta_write_request_size
                  , case when lvl = &sample_freq then ash.delta_interconnect_io_bytes end as delta_interconnect_io_bytes
                  , case when lvl = &sample_freq then ash.actual_degree end as actual_degree
                  , case when lvl > &sample_freq then 'Y' else null end as artificial_indicator
            from
                    ash_base ash
&use_lateral                     , lateral(select level * &sample_freq as lvl from dual connect by level <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq)
&use_no_lateral                  , (select /*+ cardinality(1e5) */ level * &sample_freq as lvl from dual connect by level <= 1e5) dup
            where
                    ash.ash_prev_bucket < ash.ash_bucket - &sample_freq
&use_no_lateral            and     dup.lvl <= (ash.ash_bucket - greatest(ash.ash_prev_bucket, -&sample_freq)) / &sample_freq
            --and     ash_bucket - lvl + &sample_freq >= 0
          )  ash
  where
          1 = 1
  and     ash.ash_bucket = t.bucket
  and     ash.instance_id = t.instance_id
),
ash_data as
(
  /* Part one and two from prior subquery expression */
  select
          *
  from
          ash_data1
  ---------
  union all
  ---------
  /* Part three: The rows from the driving row source that don't have a match in the previous data set (The outer join part) */
  select
          t.sample_time
        , t.bucket
        , null as ash_sample_time
        , null as ash_bucket
        , null as prev_sample_time
        , null as ash_prev_bucket
        , t.instance_id
        , t.duration_secs
        , t.sql_exec_start
        , null as pga_allocated
        , null as temp_space_allocated
        , null as session_state
        , null as activity
        , null as process
        , null as sql_plan_line_id
        , null as delta_time
        , null as delta_read_io_requests
        , null as delta_write_io_requests
        , null as delta_read_mem_bytes
        , null as delta_read_io_bytes
        , null as delta_write_io_bytes
        , null as delta_read_request_size
        , null as delta_write_request_size
        , null as delta_interconnect_io_bytes
        , null as actual_degree
        , null as artificial_indicator
  from
          timeline_inst t
  where
          not exists
          (
            select
                    null
            from
                    ash_data1 x
            where
                    t.instance_id = x.instance_id
            and     t.bucket = x.bucket
          )
)
,
/* Define the target buckets */
ash_bkts1 as
(
  select
          instance_id
        , duration_secs
        , ntile(&avg_as_bkts) over (partition by instance_id order by duration_secs) as bkt
  from
          (
            select
                    distinct
                    instance_id
                  , duration_secs
            from
                    ash_data
          )
),
ash_bkts as
(
  select
          decode(grouping(instance_id), 1, -1, instance_id) as instance_id
        , duration_secs
        , bkt
  from
          ash_bkts1
  group by
          duration_secs
&_IS_SINGL_INSTANCE        , instance_id
&_IS_CROSS_INSTANCE        , grouping sets(instance_id, ())
        , bkt
),
/* The most active plan lines */
/* Count occurrence per sample_time and execution plan line */
ash_plan_lines as
(
  select
          cnt
        , sql_plan_line_id
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , case when session_state is null then null else nvl(to_char(sql_plan_line_id, 'TM'), 'NULL') end as sql_plan_line_id
                  , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
            from
                    ash_data
            /* Ignore PGA/TEMP artificial rows here */
            where
                    artificial_indicator is null
            group by
                    duration_secs
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
                  , case when session_state is null then null else nvl(to_char(sql_plan_line_id, 'TM'), 'NULL') end
          )
),
/* Group by bucket and execution plan line */
ash_plan_lines_bkts as
(
  select
          sum(a.cnt) as cnt
--        , max(a.duration_secs) as duration_secs
        , a.sql_plan_line_id
        , a.instance_id
        , b.bkt
  from
          ash_plan_lines a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.sql_plan_line_id
        , a.instance_id
        , b.bkt
),
/* The Top N execution plan lines per bucket */
ash_plan_lines_bkts_rn as
(
  select
          cnt
        , sql_plan_line_id
        , instance_id
        , bkt
--        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, sql_plan_line_id) as rn
  from
          ash_plan_lines_bkts
),
/* Aggregate per bucket the Top N execution plan lines */
/* This will be joined later to the remaining bucket data */
ash_plan_lines_bkts_agg as
(
  select
          instance_id
--        , max(duration_secs) as duration_secs
        , bkt
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topnl + 1 then null when rn = &topnl + 1 then '...' else case when sql_plan_line_id is null then null else sql_plan_line_id || '(' || cnt || ')' end end, ',') within group (order by rn) as plan_lines
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnl + 1 then null when rn = &topnl + 1 then ',' || '...' else case when sql_plan_line_id is null then null else ',' || sql_plan_line_id || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as plan_lines
  from
          ash_plan_lines_bkts_rn
  group by
          instance_id
        , bkt
),
/* Count occurrence per sample_time and ASH activity */
ash_activity as
(
  select
          cnt
        , activity
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , case when session_state is null then null else activity end as activity
                  , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
            from
                    ash_data
            /* Ignore PGA/TEMP artificial rows here */
            where
                    artificial_indicator is null
            group by
                    duration_secs
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
                  , case when session_state is null then null else activity end
          )
),
/* Group by bucket and activity */
ash_activity_bkts as
(
  select
          sum(a.cnt) as cnt
--        , max(a.duration_secs) as duration_secs
        , a.activity
        , a.instance_id
        , b.bkt
  from
          ash_activity a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.activity
        , a.instance_id
        , b.bkt
),
/* The Top N activities per bucket */
ash_activity_bkts_rn as
(
  select
          cnt
        , activity
        , instance_id
        , bkt
--        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, activity) as rn
  from
          ash_activity_bkts
),
/* Aggregate per bucket the Top N activity */
/* This will be joined later to the remaining bucket data */
ash_activity_bkts_agg as
(
  select
          instance_id
--        , max(duration_secs) as duration_secs
        , bkt
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topna + 1 then null when rn = &topna + 1 then '...' else case when activity is null then null else activity || '(' || cnt || ')' end end, ',') within group (order by rn) as activities
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topna + 1 then null when rn = &topna + 1 then ',' || '...' else case when activity is null then null else ',' || activity || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as activities
  from
          ash_activity_bkts_rn
  group by
          instance_id
        , bkt
),
/* Count occurrence per sample_time and ASH process */
ash_process as
(
  select
          cnt
        , process
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , case when session_state is null then null else process end as process
                  , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
            from
                    ash_data
            /* Ignore PGA/TEMP artificial rows here */
            where
                    artificial_indicator is null
            group by
                    duration_secs
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
                  , case when session_state is null then null else process end
          )
),
/* Group by bucket and process */
ash_process_bkts as
(
  select
          sum(a.cnt) as cnt
--        , max(a.duration_secs) as duration_secs
        , a.process
        , a.instance_id
        , b.bkt
  from
          ash_process a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.process
        , a.instance_id
        , b.bkt
),
/* The Top N processes per bucket */
ash_process_bkts_rn as
(
  select
          cnt
        , process
        , instance_id
        , bkt
--        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, process) as rn
  from
          ash_process_bkts
),
/* Aggregate per bucket the Top N processes */
/* This will be joined later to the remaining bucket data */
ash_process_bkts_agg as
(
  select
          instance_id
--        , max(duration_secs) as duration_secs
        , bkt
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topnp + 1 then null when rn = &topnp + 1 then '...' else case when process is null then null else process || '(' || cnt || ')' end end, ',') within group (order by rn) as processes
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnp + 1 then null when rn = &topnp + 1 then ',' || '...' else case when process is null then null else ',' || process || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as processes
  from
          ash_process_bkts_rn
  group by
          instance_id
        , bkt
),
dfo_info as
(
  select
          to_number(cast(substr(coalesce(p.object_node, p.next_object_node), 3, length(coalesce(p.object_node, p.next_object_node)) - 5) as varchar2(6))) as dfo
          --to_number(cast(substr(p.object_node, 3, length(p.object_node) - 5) as varchar2(6)))  as dfo
        , to_number(substr(p.object_node, 3 + length(p.object_node) - 5))                      as tq_id
        , id
  from
          (
            select
                    p.*
                  , lead(object_node) over (order by id) as next_object_node
            from
                    &plan_table p
            where
                    p.sql_id = '&si'
            and     p.&second_id = &cn
            and     &third_id
            and     (p.object_node like ':Q%' or p.operation = 'PX COORDINATOR')
            and     '&plan_exists' is not null
            and     '&_IF_ORA11_OR_HIGHER' is null
            and     (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
          ) p
),
ash_dfo1 as
(
  select
          ash.*
        , p.dfo
  from
          ash_data ash
        , dfo_info p
  where
          p.id   = ash.sql_plan_line_id
),
/* Group the active DFOs */
ash_dfo2 as
(
  select
          cnt
        , dop
        , dfo
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , max(actual_degree) as dop
                  , dfo
                  , decode(grouping(instance_id), 1, -1, instance_id) as instance_id
            from
                    ash_dfo1
            /* Ignore PGA/TEMP artificial rows here */
            where
                    artificial_indicator is null
            group by
                    duration_secs
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
                  , dfo
          )
),
/* Group by bucket and dfo */
ash_dfo_bkts as
(
  select
          avg(a.cnt) as cnt
        , max(a.dop) as dop
--        , max(a.duration_secs) as duration_secs
        , a.dfo
        , a.instance_id
        , b.bkt
  from
          ash_dfo2 a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.dfo
        , a.instance_id
        , b.bkt
),
/* The Top dfos per bucket */
ash_dfo_bkts_rn as
(
  select
          cnt
        , dop
        , dfo
        , instance_id
        , bkt
--        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, dfo) as rn
  from
          ash_dfo_bkts
),
/* Aggregate per bucket the DFOs */
/* This will be joined later to the remaining bucket data */
ash_dfo_bkts_agg as
(
  select
          instance_id
--        , max(duration_secs) as duration_secs
        , bkt
&_IF_ORA112_OR_HIGHER           , listagg(dfo || case when dop is not null then '[' || dop || '] ' end || '(' || case when cnt >= &rnd_thr then round(cnt) else round(cnt, 1) end || ')', ',') within group (order by rn) as dfo_active
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", ',' || dfo || '(' || case when cnt >= &rnd_thr then round(cnt) else round(cnt, 1) end || ')') order by rn), '/V/text()'), ',') as dfo_active
  from
          ash_dfo_bkts_rn
  group by
          instance_id
        , bkt
),
/* Group the ASH data by sample_time */
ash_distrib as
(
  select
          instance_id
        , duration_secs
        , cnt
        , cnt_cpu
        , cnt_other
        , pga_mem
        , temp_space_alloc
        , read_req
        , write_req
        , read_mem_bytes
        , read_bytes
        , write_bytes
        , total_io_bytes
        , read_req_per_sec
        , write_req_per_sec
        , read_mem_bytes_per_sec
        , read_bytes_per_sec
        , write_bytes_per_sec
        , tot_io_bytes_per_sec
/*
        , avg_read_request_size
        , med_read_request_size
        , avg_write_request_size
        , med_write_request_size
*/
        , ntile(&avg_as_bkts) over (partition by instance_id order by duration_secs) as bkt
  from    (
            select
                    duration_secs
                  , count(session_state)                                          as cnt
                  , count(case when session_state = 'ON CPU' then 1 end)          as cnt_cpu
                  , count(case when session_state != 'ON CPU' then 1 end)         as cnt_other
                  , sum(pga_allocated)                                            as pga_mem
                  , sum(temp_space_allocated)                                     as temp_space_alloc
                  , sum(delta_read_io_requests)                                   as read_req
                  , sum(delta_write_io_requests)                                  as write_req
                  , sum(delta_read_mem_bytes)                                     as read_mem_bytes
                  , sum(delta_read_io_bytes)                                      as read_bytes
                  , sum(delta_write_io_bytes)                                     as write_bytes
                  , sum(delta_interconnect_io_bytes)                              as total_io_bytes
                  , sum(delta_read_io_requests / delta_time * 1000000)            as read_req_per_sec
                  , sum(delta_write_io_requests / delta_time * 1000000)           as write_req_per_sec
                  , sum(delta_read_mem_bytes / delta_time * 1000000)              as read_mem_bytes_per_sec
                  , sum(delta_read_io_bytes / delta_time * 1000000)               as read_bytes_per_sec
                  , sum(delta_write_io_bytes / delta_time * 1000000)              as write_bytes_per_sec
                  , sum(delta_interconnect_io_bytes / delta_time * 1000000)       as tot_io_bytes_per_sec
/*
                  , avg(delta_read_request_size)                                  as avg_read_req_size
                  , median(delta_read_request_size)                               as med_read_req_size
                  , avg(delta_write_request_size)                                 as avg_write_req_size
                  , median(delta_write_request_size)                              as med_write_req_size
*/
                  , decode(grouping(instance_id), 1, -1, instance_id)             as instance_id
            from
                    ash_data
            group by
                    duration_secs
&_IS_SINGL_INSTANCE                  , instance_id
&_IS_CROSS_INSTANCE                  , grouping sets(instance_id, ())
          )
),
/* and compress into the target number of buckets */
ash_distrib_bkts1 as
(
  select
          instance_id
--        , max(duration_secs)                                                                                            as duration_secs
        , bkt
        , round(avg(pga_mem))                                                                                           as pga_mem
        , round(avg(temp_space_alloc))                                                                                  as temp_space
        , round(sum(read_req))                                                                                          as read_req
        , round(sum(write_req))                                                                                         as write_req
        , round(sum(read_mem_bytes))                                                                                    as read_mem_bytes
        , round(sum(read_bytes))                                                                                        as read_bytes
        , round(sum(write_bytes))                                                                                       as write_bytes
        , round(sum(total_io_bytes))                                                                                    as total_io_bytes
        , round(avg(read_req_per_sec))                                                                                  as read_req_per_sec
        , round(avg(write_req_per_sec))                                                                                 as write_req_per_sec
        , round(avg(read_mem_bytes_per_sec))                                                                            as read_mem_bytes_per_sec
        , round(avg(read_bytes_per_sec))                                                                                as read_bytes_per_sec
        , round(avg(write_bytes_per_sec))                                                                               as write_bytes_per_sec
        , round(avg(tot_io_bytes_per_sec))                                                                              as tot_io_bytes_per_sec
/*
        , round(avg(avg_read_req_size))                                                                                 as avg_read_req_size
        , round(median(avg_read_req_size))                                                                              as med_read_req_size
        , round(avg(avg_write_req_size))                                                                                as avg_write_req_size
        , round(median(avg_write_req_size))                                                                             as med_write_req_size
*/
        , round(avg(cnt_cpu), 1)                                                                                        as cpu
        , round(avg(cnt_other), 1)                                                                                      as other
        , round(avg(cnt), 1)                                                                                            as average_as
        , round(median(cnt_cpu), 1)                                                                                     as cpu_median
        , round(median(cnt_other), 1)                                                                                   as other_median
        , round(median(cnt), 1)                                                                                         as median_as
        , round(stddev_samp(cnt), 1)                                                                                    as stddev_as
        --, substr(cast(rpad('&gc', round(avg(cnt_cpu)), '&gc') || rpad('&gc2', round(avg(cnt_other)), '&gc2') as varchar2(256)), 1, &wgs) as average_as_graph
  from
          ash_distrib
  group by
          bkt
        , instance_id
  -- order by
  --         bkt
  --       , instance_id
),
max_aas as
(
  select
          round(max(average_as) over ()) as max_aas
        , round(max(median_as) over ()) as max_mas
        , a.*
  from
          ash_distrib_bkts1 a
),
ash_distrib_bkts as
(
  select
          cast(rpad(coalesce(substr(cast(rpad('&gc', round(cpu * case when max_aas > &aas then &aas / max_aas else 1 end), '&gc') || rpad('&gc2', round(other * case when max_aas > &aas then &aas / max_aas else 1 end), '&gc2') as varchar2(&aas)), 1, round(average_as * case when max_aas > &aas then &aas / max_aas else 1 end)), ' '), least(&aas, max_aas)) || ' (' || case when average_as >= &rnd_thr then round(average_as) else average_as end || ')' as varchar2(&aas_size)) as average_as_graph
        , cast(rpad(coalesce(substr(cast(rpad('&gc', round(cpu_median * case when max_mas > &aas then &aas / max_mas else 1 end), '&gc') || rpad('&gc2', round(other_median * case when max_mas > &aas then &aas / max_mas else 1 end), '&gc2') as varchar2(&aas)), 1, round(median_as * case when max_aas > &aas then &aas / max_aas else 1 end)), ' '), least(&aas, max_mas)) || ' (' || case when median_as >= &rnd_thr then round(median_as) else median_as end || ')' as varchar2(&aas_size)) as median_as_graph
        , a.*
  from
          max_aas a
),
/* Some data can be directly averaged on the buckets for higher precision results */
ash_distrib_per_bkt as
(
  select
          decode(grouping(a.instance_id), 1, -1, a.instance_id)         as instance_id
        , b.bkt
        , max(a.duration_secs)                                          as duration_secs
        , round(avg(delta_read_request_size))                           as avg_read_req_size
        , round(median(delta_read_request_size))                        as med_read_req_size
        , round(avg(delta_write_request_size))                          as avg_write_req_size
        , round(median(delta_write_request_size))                       as med_write_req_size
  from
          ash_data a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
&_IS_SINGL_INSTANCE          a.instance_id
&_IS_CROSS_INSTANCE          grouping sets(a.instance_id, ())
        , b.bkt
),
/* We need some log based data for formatting the figures */
ash_distrib_bkts_prefmt as
(
  select
          a.instance_id
        , b.duration_secs
        , a.bkt
        , pga_mem
        , trunc(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)))                                        as power_2_pga_mem
        , trunc(mod(log(2, abs(case pga_mem when 0 then 1 else pga_mem end)) ,10))                               as power_2_pga_mem_mod_10
        , temp_space
        , trunc(log(2, abs(case temp_space when 0 then 1 else temp_space end)))                                  as power_2_temp_space
        , trunc(mod(log(2, abs(case temp_space when 0 then 1 else temp_space end)), 10))                         as power_2_temp_space_mod_10
        , read_req
        , trunc(log(10, abs(case read_req when 0 then 1 else read_req end)))                                     as power_10_read_req
        , trunc(mod(log(10, abs(case read_req when 0 then 1 else read_req end)), 3))                             as power_10_read_req_mod_3
        , write_req
        , trunc(log(10, abs(case write_req when 0 then 1 else write_req end)))                                   as power_10_write_req
        , trunc(mod(log(10, abs(case write_req when 0 then 1 else write_req end)), 3))                           as power_10_write_req_mod_3
        , avg_read_req_size
        , trunc(log(2, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)))                    as power_2_avg_read_req_size
        , trunc(mod(log(2, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)), 10))           as power_2_avg_read_req_size_10
        , med_read_req_size
        , trunc(log(2, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)))                    as power_2_med_read_req_size
        , trunc(mod(log(2, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)), 10))           as power_2_med_read_req_size_10
        , avg_write_req_size
        , trunc(log(2, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)))                  as power_2_avg_write_req_size
        , trunc(mod(log(2, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)), 10))         as power_2_avg_write_req_size_10
        , med_write_req_size
        , trunc(log(2, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)))                  as power_2_med_write_req_size
        , trunc(mod(log(2, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)), 10))         as power_2_med_write_req_size_10
        , read_bytes
        , trunc(log(2, abs(case read_bytes when 0 then 1 else read_bytes end)))                                  as power_2_read_bytes
        , trunc(mod(log(2, abs(case read_bytes when 0 then 1 else read_bytes end)), 10))                         as power_2_read_bytes_mod_10
        , read_mem_bytes
        , trunc(log(2, abs(case read_mem_bytes when 0 then 1 else read_mem_bytes end)))                          as power_2_read_mem_bytes
        , trunc(mod(log(2, abs(case read_mem_bytes when 0 then 1 else read_mem_bytes end)), 10))                 as power_2_read_mem_bytes_mod_10
        , write_bytes
        , trunc(log(2, abs(case write_bytes when 0 then 1 else write_bytes end)))                                as power_2_write_bytes
        , trunc(mod(log(2, abs(case write_bytes when 0 then 1 else write_bytes end)), 10))                       as power_2_write_bytes_mod_10
        , total_io_bytes
        , trunc(log(2, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)))                          as power_2_total_io_bytes
        , trunc(mod(log(2, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)), 10))                 as power_2_total_io_bytes_mod_10
        , read_req_per_sec
        , trunc(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)))                     as power_10_read_req_per_sec
        , trunc(mod(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)), 3))             as power_10_read_req_ps_mod_3
        , write_req_per_sec
        , trunc(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)))                   as power_10_write_req_per_sec
        , trunc(mod(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)), 3))           as power_10_write_req_ps_mod_3
        , read_mem_bytes_per_sec
        , trunc(log(2, abs(case read_mem_bytes_per_sec when 0 then 1 else read_mem_bytes_per_sec end)))          as power_2_read_mem_bytes_per_sec
        , trunc(mod(log(2, abs(case read_mem_bytes_per_sec when 0 then 1 else read_mem_bytes_per_sec end)), 10)) as power_2_read_mem_byt_ps_mod_10
        , read_bytes_per_sec
        , trunc(log(2, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)))                  as power_2_read_bytes_per_sec
        , trunc(mod(log(2, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)), 10))         as power_2_read_bytes_ps_mod_10
        , write_bytes_per_sec
        , trunc(log(2, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)))                as power_2_write_bytes_per_sec
        , trunc(mod(log(2, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)), 10))       as power_2_write_bytes_ps_mod_10
        , tot_io_bytes_per_sec
        , trunc(log(2, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)))              as power_2_tot_io_bytes_per_sec
        , trunc(mod(log(2, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)), 10))     as power_2_tot_io_bytes_ps_mod_10
        , case when cpu >= &rnd_thr then round(cpu) else cpu end                                                 as cpu
        , case when other >= &rnd_thr then round(other) else other end                                           as other
        , case when average_as >= &rnd_thr then round(average_as) else average_as end                            as average_as
        , case when cpu_median >= &rnd_thr then round(cpu_median) else cpu end                                   as cpu_median
        , case when other_median >= &rnd_thr then round(other_median) else other end                             as other_median
        , case when median_as >= &rnd_thr then round(median_as) else median_as end                               as median_as
        , case when stddev_as >= &rnd_thr then round(stddev_as) else stddev_as end                               as stddev_as
        , average_as_graph
        , median_as_graph
  from
          ash_distrib_bkts a
        , ash_distrib_per_bkt b
  where
          a.instance_id = b.instance_id
  and     a.bkt = b.bkt
),
/* Format the figures */
ash_distrib_bkts_fmt as
(
  select
          instance_id
        , duration_secs
        , bkt
        , to_char(round(pga_mem / power(2, power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)), 'FM99999') ||
          case power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga_mem is null
               then null
               else '*2^'||to_char(power_2_pga_mem - case when power_2_pga_mem >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga_mem))),3)) = 0 then power_2_pga_mem_mod_10 + 10 else power_2_pga_mem_mod_10 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(2, power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)), 'FM99999') ||
          case power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp_space is null
               then null
               else '*2^'||to_char(power_2_temp_space - case when power_2_temp_space >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp_space))),3)) = 0 then power_2_temp_space_mod_10 + 10 else power_2_temp_space_mod_10 end)
               end
          end      as temp_space_format
        , to_char(round(read_req / power(10, power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)), 'FM99999') ||
          case power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req is null
               then null
               else '*10^'||to_char(power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)
               end
          end      as read_req
        , to_char(round(avg_read_req_size / power(2, power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end)), 'FM99999') ||
          case power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when avg_read_req_size is null
               then null
               else '*2^'||to_char(power_2_avg_read_req_size - case when power_2_avg_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_read_req_size))),3)) = 0 then power_2_avg_read_req_size_10 + 10 else power_2_avg_read_req_size_10 end)
               end
          end      as avg_read_req_size
        , to_char(round(med_read_req_size / power(2, power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end)), 'FM99999') ||
          case power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when med_read_req_size is null
               then null
               else '*2^'||to_char(power_2_med_read_req_size - case when power_2_med_read_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_read_req_size))),3)) = 0 then power_2_med_read_req_size_10 + 10 else power_2_med_read_req_size_10 end)
               end
          end      as med_read_req_size
        , to_char(round(avg_write_req_size / power(2, power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end)), 'FM99999') ||
          case power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when avg_write_req_size is null
               then null
               else '*2^'||to_char(power_2_avg_write_req_size - case when power_2_avg_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_avg_write_req_size))),3)) = 0 then power_2_avg_write_req_size_10 + 10 else power_2_avg_write_req_size_10 end)
               end
          end      as avg_write_req_size
        , to_char(round(med_write_req_size / power(2, power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end)), 'FM99999') ||
          case power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when med_write_req_size is null
               then null
               else '*2^'||to_char(power_2_med_write_req_size - case when power_2_med_write_req_size >= 10 and trunc(mod(log(10,abs(power(2, power_2_med_write_req_size))),3)) = 0 then power_2_med_write_req_size_10 + 10 else power_2_med_write_req_size_10 end)
               end
          end      as med_write_req_size
        , to_char(round(write_req / power(10, power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)), 'FM99999') ||
          case power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req is null
               then null
               else '*10^'||to_char(power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)
               end
          end      as write_req
        , to_char(round(read_mem_bytes / power(2, power_2_read_mem_bytes - case when power_2_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes))),3)) = 0 then power_2_read_mem_bytes_mod_10 + 10 else power_2_read_mem_bytes_mod_10 end)), 'FM99999') ||
          case power_2_read_mem_bytes - case when power_2_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes))),3)) = 0 then power_2_read_mem_bytes_mod_10 + 10 else power_2_read_mem_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_mem_bytes is null
               then null
               else '*2^'||to_char(power_2_read_mem_bytes - case when power_2_read_mem_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes))),3)) = 0 then power_2_read_mem_bytes_mod_10 + 10 else power_2_read_mem_bytes_mod_10 end)
               end
          end      as read_mem_bytes
        , to_char(round(read_bytes / power(2, power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end)), 'FM99999') ||
          case power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_bytes is null
               then null
               else '*2^'||to_char(power_2_read_bytes - case when power_2_read_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes))),3)) = 0 then power_2_read_bytes_mod_10 + 10 else power_2_read_bytes_mod_10 end)
               end
          end      as read_bytes
        , to_char(round(write_bytes / power(2, power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end)), 'FM99999') ||
          case power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when write_bytes is null
               then null
               else '*2^'||to_char(power_2_write_bytes - case when power_2_write_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes))),3)) = 0 then power_2_write_bytes_mod_10 + 10 else power_2_write_bytes_mod_10 end)
               end
          end      as write_bytes
        , to_char(round(total_io_bytes / power(2, power_2_total_io_bytes - case when power_2_total_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_total_io_bytes))),3)) = 0 then power_2_total_io_bytes_mod_10 + 10 else power_2_total_io_bytes_mod_10 end)), 'FM99999') ||
          case power_2_total_io_bytes - case when power_2_total_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_total_io_bytes))),3)) = 0 then power_2_total_io_bytes_mod_10 + 10 else power_2_total_io_bytes_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when total_io_bytes is null
               then null
               else '*2^'||to_char(power_2_total_io_bytes - case when power_2_total_io_bytes >= 10 and trunc(mod(log(10,abs(power(2, power_2_total_io_bytes))),3)) = 0 then power_2_total_io_bytes_mod_10 + 10 else power_2_total_io_bytes_mod_10 end)
               end
          end      as total_io_bytes
        , to_char(round(read_req_per_sec / power(10, power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)
               end
          end      as read_req_per_sec
        , to_char(round(write_req_per_sec / power(10, power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)
               end
          end      as write_req_per_sec
        , to_char(round(read_mem_bytes_per_sec / power(2, power_2_read_mem_bytes_per_sec - case when power_2_read_mem_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_per_sec))),3)) = 0 then power_2_read_mem_byt_ps_mod_10 + 10 else power_2_read_mem_byt_ps_mod_10 end)), 'FM99999') ||
          case power_2_read_mem_bytes_per_sec - case when power_2_read_mem_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_per_sec))),3)) = 0 then power_2_read_mem_byt_ps_mod_10 + 10 else power_2_read_mem_byt_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_mem_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_read_mem_bytes_per_sec - case when power_2_read_mem_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_mem_bytes_per_sec))),3)) = 0 then power_2_read_mem_byt_ps_mod_10 + 10 else power_2_read_mem_byt_ps_mod_10 end)
               end
          end      as read_mem_bytes_per_sec
        , to_char(round(read_bytes_per_sec / power(2, power_2_read_bytes_per_sec - case when power_2_read_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes_per_sec))),3)) = 0 then power_2_read_bytes_ps_mod_10 + 10 else power_2_read_bytes_ps_mod_10 end)), 'FM99999') ||
          case power_2_read_bytes_per_sec - case when power_2_read_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes_per_sec))),3)) = 0 then power_2_read_bytes_ps_mod_10 + 10 else power_2_read_bytes_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when read_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_read_bytes_per_sec - case when power_2_read_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_read_bytes_per_sec))),3)) = 0 then power_2_read_bytes_ps_mod_10 + 10 else power_2_read_bytes_ps_mod_10 end)
               end
          end      as read_bytes_per_sec
        , to_char(round(write_bytes_per_sec / power(2, power_2_write_bytes_per_sec - case when power_2_write_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes_per_sec))),3)) = 0 then power_2_write_bytes_ps_mod_10 + 10 else power_2_write_bytes_ps_mod_10 end)), 'FM99999') ||
          case power_2_write_bytes_per_sec - case when power_2_write_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes_per_sec))),3)) = 0 then power_2_write_bytes_ps_mod_10 + 10 else power_2_write_bytes_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when write_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_write_bytes_per_sec - case when power_2_write_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_write_bytes_per_sec))),3)) = 0 then power_2_write_bytes_ps_mod_10 + 10 else power_2_write_bytes_ps_mod_10 end)
               end
          end      as write_bytes_per_sec
        , to_char(round(tot_io_bytes_per_sec / power(2, power_2_tot_io_bytes_per_sec - case when power_2_tot_io_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_tot_io_bytes_per_sec))),3)) = 0 then power_2_tot_io_bytes_ps_mod_10 + 10 else power_2_tot_io_bytes_ps_mod_10 end)), 'FM99999') ||
          case power_2_tot_io_bytes_per_sec - case when power_2_tot_io_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_tot_io_bytes_per_sec))),3)) = 0 then power_2_tot_io_bytes_ps_mod_10 + 10 else power_2_tot_io_bytes_ps_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when tot_io_bytes_per_sec is null
               then null
               else '*2^'||to_char(power_2_tot_io_bytes_per_sec - case when power_2_tot_io_bytes_per_sec >= 10 and trunc(mod(log(10,abs(power(2, power_2_tot_io_bytes_per_sec))),3)) = 0 then power_2_tot_io_bytes_ps_mod_10 + 10 else power_2_tot_io_bytes_ps_mod_10 end)
               end
          end      as tot_io_bytes_per_sec
        , cpu
        , other
        , cpu_median
        , other_median
        , median_as
        , stddev_as
        , average_as
        , average_as_graph
        , median_as_graph
  from
          ash_distrib_bkts_prefmt
)
/* The final set including the Top N plan lines and Top N activities */
select  /* XPLAN_ASH ACTIVITY_TIMELINE SQL_ID: &si */
        /* Very long hard parse times with 11.2.0.1 optimizer features and S-ASH views */
        /* Therefore falling back to 11.1.0.7 optimizer features */
        /*+ optimizer_features_enable('11.1.0.7') */
        nullif(a.instance_id, -1)    as instance_id
      , case when a.instance_id = -1 then 1 else 0 end as break_instance_id
      , a.duration_secs
      , lpad(pga_mem_format, 6)      as pga
      , lpad(temp_space_format, 6)   as temp
      , cpu
      , other
      , average_as
      , average_as_graph
      , cpu_median
      , other_median
      , median_as
      , stddev_as
      , median_as_graph
      , b.plan_lines
      , e.dfo_active
      , c.activities
      , d.processes
      , lpad(read_req, 6)               as rd_req
      , lpad(write_req, 6)              as wr_req
      , lpad(read_req_per_sec, 6)       as rd_r_s
      , lpad(write_req_per_sec, 6)      as wr_r_s
      , lpad(read_bytes, 6)             as rd_byt
      , lpad(write_bytes, 6)            as wr_byt
      , lpad(total_io_bytes, 6)         as io_byt
      , lpad(read_mem_bytes, 6)         as rm_byt
      , lpad(read_bytes_per_sec, 6)     as rd_b_s
      , lpad(write_bytes_per_sec, 6)    as wr_b_s
      , lpad(tot_io_bytes_per_sec, 6)   as io_b_s
      , lpad(read_mem_bytes_per_sec, 6) as rm_b_s
      , lpad(avg_read_req_size, 6)      as a_rr_s
      , lpad(med_read_req_size, 6)      as m_rr_s
      , lpad(avg_write_req_size, 6)     as a_wr_s
      , lpad(med_write_req_size, 6)     as m_wr_s
from
        ash_distrib_bkts_fmt a
      , ash_plan_lines_bkts_agg b
      , ash_activity_bkts_agg c
      , ash_process_bkts_agg d
      , ash_dfo_bkts_agg e
where
        a.instance_id = b.instance_id (+)
and     a.bkt = b.bkt (+)
and     a.instance_id = c.instance_id (+)
and     a.bkt = c.bkt (+)
and     a.instance_id = d.instance_id (+)
and     a.bkt = d.bkt (+)
and     a.instance_id = e.instance_id (+)
and     a.bkt = e.bkt (+)
order by
        duration_secs
      , instance_id nulls first
;

column pga  clear
column temp clear
column rd_req clear
column wr_req clear
column rm_byt clear
column rd_byt clear
column wr_byt clear
column io_byt clear
column rd_r_s clear
column wr_r_s clear
column rm_b_s clear
column rd_b_s clear
column wr_b_s clear
column io_b_s clear
column a_rr_s clear
column m_rr_s clear
column a_wr_s clear
column m_wr_s clear
column plan_lines clear
column dfo_active clear
column activities clear
column processes clear
column average_as clear
column median_as clear
column stddev_as clear
column average_as_graph clear
column median_as_graph  clear
column instance_id      clear
column break_instance_id clear
column cpu_median clear
column other_median clear

clear breaks

undefine _SHOW_12C_IO_COLS
undefine _SHOW_IO_COLS
undefine aas_size
undefine _SHOW_DFO_COL
undefine _DOP_HEADER
undefine _BREAK_CI

-- If you need to debug, comment the following line
set termout off

column has_binds_xml new_value has_binds_xml &debug_internalp.print

select
&use_monitor &_IF_ORA112_OR_HIGHER         nvl2(binds_xml, 'Y', null) as has_binds_xml
&use_monitor &_IF_LOWER_THAN_ORA112        cast(null as varchar2(1)) as has_binds_xml
&use_no_monitor        cast(null as varchar2(1)) as has_binds_xml
from
&use_monitor        &sql_monitor
&use_no_monitor     dual
&use_monitor        where
&use_monitor                px_qcsid is null
&use_monitor        and     sql_id = '&si'
&use_monitor        and     sql_exec_start = to_date('&ls', '&dm')
&use_monitor        and     sql_exec_id = &li
;

column has_binds_xml clear

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        '&has_binds_xml' = 'Y'
---------
union all
---------
select
        'Actual bind values from Real-Time SQL Monitoring' as message
from
        dual
where
        '&has_binds_xml' = 'Y'
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        '&has_binds_xml' = 'Y'
;

column message clear

set heading on

column name     format a30
column datatype format a30
column value    format a100

select
        x.*
from
&use_monitor        &sql_monitor
&use_no_monitor     dual x
&use_monitor      , xmltable
&use_monitor        (
&use_monitor          '//bind'
&use_monitor &_IF_ORA112_OR_HIGHER                   passing xmltype(binds_xml)
&use_monitor &_IF_LOWER_THAN_ORA112                  passing xmltype('<bla></bla>')
&use_monitor          columns
&use_monitor          "POSITION" integer path '/bind/@pos',
&use_monitor          "NAME" varchar2(128) path '/bind/@name',
&use_monitor          "DATATYPE" varchar2(30) path '/bind/@dtystr',
&use_monitor          "VALUE" varchar2(4000) path '/bind'
&use_monitor        ) x
where
&use_no_monitor     1 = 2
&use_monitor                px_qcsid is null
&use_monitor        and     sql_id = '&si'
&use_monitor        and     sql_exec_start = to_date('&ls', '&dm')
&use_monitor        and     sql_exec_id = &li
&use_monitor        and     '&has_binds_xml' = 'Y'
&use_monitor order by position
;

column name     clear
column datatype clear
column value    clear

undefine has_binds_xml

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0 or instr('&op', 'NONE') > 0 or instr('&op', 'MONITOR') > 0)
---------
union all
---------
select
        'Activity on execution plan line level' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0 or instr('&op', 'NONE') > 0 or instr('&op', 'MONITOR') > 0)
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        'Execution plan details' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0 or instr('&op', 'NONE') > 0 or instr('&op', 'MONITOR') > 0)
and     '&_IF_LOWER_THAN_ORA11' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0 or instr('&op', 'NONE') > 0 or instr('&op', 'MONITOR') > 0)
;

column message clear

set heading on

set pagesize 0 feedback on

/* The following code snippet represents the core ASH based information for the plan line related ASH info */
/* It will be re-used if no execution plan could be found */
/* Therefore it will be saved to a file and re-loaded into the SQL buffer after execution of this statement */

/* Activity details on execution plan line level */

/* No read consistency on V$ views, therefore we materialize here the ASH content required */
with /* XPLAN_ASH ACTIVITY_PLAN_LINE SQL_ID: &si */
ash_base as
(
  select  /*+ materialize */
          &inst_id
&_IF_ORA11_OR_HIGHER          , nvl(sql_plan_line_id, 0)                                                                      as sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , 0  as sql_plan_line_id
&_IF_ORA11_OR_HIGHER          , sql_plan_operation || ' ' || sql_plan_options                                                 as plan_operation
&_IF_LOWER_THAN_ORA11         , '' as plan_operation
        , case
          when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end as event
        , coalesce(program, 'NULL')  as program
        , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c') as process
&_IF_ORA11202_OR_HIGHER       , px_flags
&_IF_LOWER_THAN_ORA11202      , null as px_flags
        , session_id
        , session_serial#
        , sql_plan_hash_value
        , sample_time
        , session_state
&_IF_ORA112_OR_HIGHER         , cast(sample_time as date) - delta_time / 1000000 / 86400                                                                         as prev_sample_time
&_IF_LOWER_THAN_ORA112        , cast(sample_time as date) - &sample_freq / 86400                                                                                 as prev_sample_time
        -- Assign the sample to a particular bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date) - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq as ash_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq                          as ash_bucket
        -- Likewise Assign the previous sample to a bucket according to the sample frequency
&_IF_ORA11_OR_HIGHER          , trunc(round((cast(sample_time as date)
&_IF_ORA112_OR_HIGHER           - delta_time / 1000000 / 86400
&_IF_ORA11_OR_HIGHER &_IF_LOWER_THAN_ORA112          - &sample_freq / 86400
&_IF_ORA11_OR_HIGHER            - coalesce(sql_exec_start, to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS'))) * 86400) / &sample_freq) * &sample_freq    as ash_prev_bucket
&_IF_LOWER_THAN_ORA11         , trunc(round((cast(sample_time as date) - &sample_freq / 86400 - to_date('&ls', '&dm')) * 86400) / &sample_freq) * &sample_freq   as ash_prev_bucket
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_ORA11_OR_HIGHER          , count(sql_exec_start) over (partition by sql_exec_start)                        as cnt_sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm')                                                           as sql_exec_start
&_IF_LOWER_THAN_ORA11         , 1                                                                               as cnt_sql_exec_start
  from
          &global_ash ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and ((sql_exec_start = to_date('&ls', '&dm') and sql_exec_id = &li) or (sql_exec_start is null and sql_exec_id is null))
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  and     '&_IF_ORA11_OR_HIGHER' is null
  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
        , max(ash_bucket)     as max_ash_bucket
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  select
          (rownum - 1) * &sample_freq                  as bucket
        , rownum * &sample_freq                        as duration_secs
        , sql_exec_start + (rownum - 1) * &sample_freq as timeline
        , sql_exec_start
  from
          dates
  connect by
          level <= (max_ash_bucket / &sample_freq) + 1
--  /* Calculate backwards from first sample to actual start of execution */
--  select
--          min_sample_time - rownum * &sample_freq / 86400 as timeline
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  connect by
--          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
--  ---------
--  union all
--  ---------
--  /* Calculate forward from first sample to last sample */
--  select
--          min_sample_time + (rownum - 1) * &sample_freq / 86400
--        , sql_exec_start
--  from
--          dates
--  start with
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  connect by
--          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
--  -- order by
--  --        timeline
),
driver as
(
  select
          ash_lines.sql_plan_line_id
        , b.timeline
        , b.bucket
  from
          timeline b, (select distinct sql_plan_line_id from ash_base) ash_lines
),
base_data as
(
  select
          case when count(a.sql_plan_line_id) > 0 then '&gc3' else ' ' end as act_ind
        , count(a.sql_plan_line_id) as active_sessions
        , driver.sql_plan_line_id
        , driver.timeline
        , driver.bucket as d_bucket
  from
          driver
        , ash_base a
  where
          a.ash_bucket (+) = driver.bucket
  and     a.sql_plan_line_id (+) = driver.sql_plan_line_id
  group by
          driver.sql_plan_line_id
        , driver.bucket
        , driver.timeline
--  order by
--          driver.sql_plan_line_id
--        , driver.timeline
),
plan_line_activity
as
(
  select  /*+ no_merge */
          min(ash_bucket) as min_bucket
        , max(ash_bucket) as max_bucket
        , sql_plan_line_id
  from
          ash_base
  group by
          sql_plan_line_id
),
median_as as
(
  select
          b.sql_plan_line_id
        , median(b.active_sessions) as median_as
  from
          base_data b
        , plan_line_activity a
  where
          a.sql_plan_line_id = b.sql_plan_line_id
  and     b.d_bucket between a.min_bucket and a.max_bucket
  group by
          b.sql_plan_line_id
),
bucket_data as
(
  select
          ntile(&tgs) over (partition by sql_plan_line_id order by timeline) as bucket
        , x.*
  from
          base_data x
          -- In case we have less sample times as size of the Time Active Graph
          -- this here will duplicate the data accordingly
        , (select /*+ cardinality(&duplicator) */ null from dual connect by level <= to_number(trim('&duplicator'))) dups
),
grouped_buckets as
(
  select
          max(act_ind) as act_ind
        , bucket
        , sql_plan_line_id
  from
          bucket_data
  group by
          sql_plan_line_id
        , bucket
--  order by
--          sql_plan_line_id
--        , bucket
),
time_active_graph as
(
  select
          sql_plan_line_id
&_IF_ORA112_OR_HIGHER         , listagg(act_ind) within group (order by bucket)                        as time_active_graph
          /* leading spaces are trimmed by the XML operation, hence we need to temporarily replace them with something else */
&_IF_LOWER_THAN_ORA112        , replace(extract(xmlagg(xmlelement("V", replace(act_ind, ' ', '?')) order by bucket), '/V/text()').getstringval(), '?', ' ') as time_active_graph
  from
          grouped_buckets
  group by
          sql_plan_line_id
--  order by
--          sql_plan_line_id
),
/* Row distribution per process / plan_line taken from Real-Time SQL Monitoring - fed into parallel procs info following */
row_distrib_info0 as
(
  select
&use_monitor &_IF_ORA112_OR_HIGHER              case when to_number(nvl('&ic', '0')) > 1 then p_m.inst_id || '-' end || coalesce(m.program, case when upper(p_m.process_name) = 'ORA' then 'QC' else upper(p_m.process_name) end) as process
&use_monitor &_IF_LOWER_THAN_ORA112             case when to_number(nvl('&ic', '0')) > 1 then p_m.inst_id || '-' end || case when upper(p_m.process_name) = 'ORA' then 'QC' else upper(p_m.process_name) end as process
&use_no_monitor           '' as process
&use_monitor            , case when to_number(nvl('&ic', '0')) > 1 then p_m.inst_id || '-' end || p_m.sid as sess_id
&use_no_monitor         , '' as sess_id
&use_monitor            , plan_line_id
&use_no_monitor         , 0 as plan_line_id
&use_monitor            , output_rows as a_rows
&use_no_monitor         , 0 as a_rows
  from
&use_monitor              &sql_plan_monitor p_m
&use_monitor            , &sql_monitor m
&use_no_monitor           dual
  where
&use_monitor              1 = 1
&use_no_monitor           1 = 2
&use_monitor      and     m.sql_id = '&si'
&use_monitor      and     m.sql_exec_start = to_date('&ls', '&dm')
&use_monitor      and     m.sql_exec_id = &li
&use_monitor      and     p_m.sql_id = '&si'
&use_monitor      and     p_m.sql_exec_start = to_date('&ls', '&dm')
&use_monitor      and     p_m.sql_exec_id = &li
&use_monitor      and     p_m.inst_id = m.inst_id
&use_monitor      and     p_m.sid = m.sid
),
/* If a query has multiple DFO Trees, above query will return duplicates - not really monitoring bug but due to the multiple child cursors generated per DFO Tree typically */
row_distrib_info1 as
(
  select
          max(a_rows) as a_rows
        , plan_line_id
        , sess_id
        , process
  from
          row_distrib_info0
  group by
          plan_line_id
        , sess_id
        , process
),
row_distrib_prefmt as
(
  select
          process as m_process
        , sess_id
        , plan_line_id
        , a_rows
        , trunc(log(10, abs(case a_rows when 0 then 1 else a_rows end)))                                  as power_10_a_rows
        , trunc(mod(log(10, abs(case a_rows when 0 then 1 else a_rows end)), 3))                          as power_10_a_rows_mod_3
  from
          row_distrib_info1
),
row_distrib_fmt as
(
  select
          m_process
        , sess_id
        , plan_line_id
        , a_rows
        , to_char(round(a_rows / power(10, power_10_a_rows - case when power_10_a_rows > 0 and power_10_a_rows_mod_3 = 0 then 3 else power_10_a_rows_mod_3 end)), 'FM99999') ||
          case power_10_a_rows - case when power_10_a_rows > 0 and power_10_a_rows_mod_3 = 0 then 3 else power_10_a_rows_mod_3 end
          when 0            then ''
          when 1            then ''
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when a_rows is null
               then null
               else '*10^'||to_char(power_10_a_rows - case when power_10_a_rows > 0 and power_10_a_rows_mod_3 = 0 then 3 else power_10_a_rows_mod_3 end)
               end
          end      as a_rows_format
  from
          row_distrib_prefmt
),
dfo_info as
(
  select
          to_number(cast(substr(p.object_node, 3, length(p.object_node) - 5) as varchar2(6)))                     as dfo
        , to_number(substr(p.object_node, 3 + length(p.object_node) - 5))                                         as tq_id
        , id
  from
          &plan_table p
  where   p.sql_id = '&si'
  and     p.&second_id = &cn
  and     &third_id
  and     p.object_node like ':Q%'
  and     '&plan_exists' is not null
  and     '&_IF_ORA11_OR_HIGHER' is null
),
ash_dfo1 as
(
  select
          ash.*
        , case when p.id is not null then count(distinct process) over (partition by p.dfo, p.tq_id) end as cnt_process
        , trunc(px_flags / 2097152) as actual_degree
        , p.dfo
  from
          ash_base ash
        , dfo_info p
  where
          p.id (+) = ash.sql_plan_line_id
),
/* Parallel Degree DOP info taken from Real-Time SQL Monitoring if available / requested */
monitor_dop_info as
(
  select
&use_monitor              inst_id
&use_no_monitor           0 as inst_id
&use_monitor            , sid
&use_no_monitor         , 0 as sid
&use_monitor            , session_serial#
&use_no_monitor         , 0 as session_serial#
&use_monitor            , count(*) over (partition by px_server_group, px_server_set) as monitor_dop
&use_no_monitor         , 0  as monitor_dop
  from
&use_monitor              &sql_monitor m
&use_no_monitor           dual
  where
&use_monitor              1 = 1
&use_no_monitor           1 = 2
&use_monitor      and     m.sql_id = '&si'
&use_monitor      and     m.sql_exec_start = to_date('&ls', '&dm')
&use_monitor      and     m.sql_exec_id = &li
&use_monitor      and     m.px_qcsid is not null
),
ash_dfo as
(
  select
          ash.*
        , max(cnt_process) over (partition by dfo) as assumed_degree
        , m.monitor_dop
  from
          ash_dfo1 ash
        , monitor_dop_info m
  where
          ash.&inst_id = m.inst_id (+)
  and     ash.session_id = m.sid (+)
  and     ash.session_serial# = m.session_serial# (+)
),
plan_line_skew1 as (
  select
          count(*) over (partition by ash_bucket, dfo) as active_sessions
        --, greatest(coalesce(actual_degree, 0), coalesce(monitor_dop, 0), coalesce(assumed_degree, 0)) as dop
        --, coalesce(actual_degree, monitor_dop, assumed_degree, 1) as dop
        , coalesce(actual_degree, greatest(coalesce(monitor_dop, 0), coalesce(assumed_degree, 0)), 1) as dop
        , a.*
  from
          ash_dfo a
),
plan_line_skew2 as (
  select
          max(active_sessions)       as active_sessions
        , max(dop - active_sessions) as diff_aas
        , count(*)                   as plan_line_cnt
        , max(dop)                   as dop
        , sql_plan_line_id
        , ash_bucket
  from
          plan_line_skew1
  group by
          ash_bucket
        , sql_plan_line_id
  --order by ash_bucket, sql_plan_line_id
),
plan_line_skew as
(
  select
          sql_plan_line_id
        --, round(greatest(sum(diff_aas / (active_sessions / plan_line_cnt)), 0)) as skew_plan_line
        , greatest(sum(case when diff_aas > 0 then 1 when diff_aas < 0 then -1 else 0 end), 0) as skew_plan_line
        --, min(dop) as dop
        , max(dop) as dop
        , count(distinct dop) as dist_dop
  from
          plan_line_skew2
  group by
          sql_plan_line_id
  --order by skew_plan_line desc
),
/* Distribution of Parallel Slaves (including QC) based on ASH */
/* This statement is effectively turned into a NOOP in versions below 11g */
parallel_procs1 as
(
  select
          distinct
          sql_plan_line_id                                                                                                                           as plan_line
        --, case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c') as process
        , process
        , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || session_id                                                            as ash_sess_id
        , count(*) over (partition by sql_plan_line_id, &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c'))    as cnt
        , count(distinct &inst_id || '-' || regexp_replace(coalesce(program, 'NULL'), '^.*\((P[[:alnum:]][[:alnum:]][[:alnum:]])\)$', '\1', 1, 1, 'c')) over (partition by sql_plan_line_id)    as proc_cnt
        --, count(*) over (partition by sql_plan_line_id)                                                                                              as total_cnt_plan_line
        --, count(*) over ()                                                                                                                           as total_cnt
        , count(distinct ash_bucket) over (partition by sql_plan_line_id)                                                                            as samples_active
        , count(distinct ash_bucket) over ()                                                                                                         as total_samples_active
        , min(ash_bucket) over (partition by sql_plan_line_id)                                                                                       as min_sample_time
        , max(ash_bucket) over (partition by sql_plan_line_id)                                                                                       as max_sample_time
  from
          ash_base
  where   '&_IF_ORA11_OR_HIGHER' is null
  and     instr('&op', 'DISTRIB') > 0
),
parallel_procs1a as
(
  select
          plan_line
        , process
        , ash_sess_id
        , cnt
        , proc_cnt
        , samples_active
        , total_samples_active
        , min_sample_time
        , max_sample_time
        , b.a_rows_format
        , b.a_rows
  from
          parallel_procs1 a
        , row_distrib_fmt b
  where
          a.plan_line = b.plan_line_id (+)
  -- and     a.process = b.m_process (+)
  and     a.ash_sess_id = b.sess_id (+)
  union all
  select
          plan_line_id as plan_line
        , m_process as process
        , sess_id as ash_sess_id
        , 0 as cnt
        , 0 as proc_cnt
        , 0 as samples_active
        , 0 as total_samples_active
        , cast(null as number) as min_sample_time
        , cast(null as number) as max_sample_time
        , a_rows_format
        , a_rows
  from
          row_distrib_fmt a
  where
          not exists
          (
            select
                    null
            from
                    parallel_procs1 b
            where
                    a.sess_id = b.ash_sess_id
            and     a.plan_line_id = b.plan_line
          )
  and     coalesce('&show_monitor_rowcount', 'NO') = 'YES'
),
parallel_procs2 as
(
  select
          plan_line
        , process
        , proc_cnt
        , cnt
        --, avg(cnt) over (partition by plan_line) as avg_cnt
        --, cnt / nullif(case when instr('&op', 'DISTRIB_TOT') > 0 then total_cnt when instr('&op', 'DISTRIB_REL') > 0 then max(total_cnt_plan_line) over () when instr('&op', 'DISTRIB_TIM') > 0 then total_cnt_plan_line / (samples_active / total_samples_active) else total_cnt_plan_line end, 0) as ratio
        --, cnt / nullif(total_cnt_plan_line / (samples_active / total_samples_active), 0) as ratio
        , cnt / nullif(samples_active, 0) as average_as
        , cnt / nullif((max_sample_time - min_sample_time + &sample_freq) / &sample_freq, 0) as average_as_t
        --, cnt / nullif((((max_sample_time - min_sample_time) * 86400) + &sample_freq), 0) * &sample_freq as average_as_t
        , row_number() over (partition by plan_line order by cnt desc, a_rows desc, process) as rn
        --, avg(cnt / nullif(total_cnt_plan_line / (samples_active / total_samples_active), 0)) over (partition by plan_line) as avg_ratio
        , a_rows_format
        , row_number() over (partition by plan_line order by cnt desc) as rnk
        , cnt - lag(cnt, 1, case when proc_cnt = 1 then 0 else cnt end) over (partition by plan_line order by cnt) as diff
        , samples_active
        , total_samples_active
  from
          parallel_procs1a
),
/* Use LISTAGG() from 11.2 on, in 11.1 use XMLAGG() instead for string aggregation */
parallel_procs3 as
(
  select
          plan_line
&_IF_ORA112_OR_HIGHER            , lpad(to_char(max(proc_cnt), 'TM'), 3) || ':' || listagg(case when rn > &topnp + 1 then null when rn = &topnp + 1 then '...' else process || '(' || cnt || ')' || case when a_rows_format is not null then '[' || a_rows_format || ']' end end, ',') within group (order by rn)                                                                                                                                                                          as procs
&_IF_LOWER_THAN_ORA112           , lpad(to_char(max(proc_cnt), 'TM'), 3) || ':' || ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnp + 1 then null when rn = &topnp + 1 then ',' || '...' else ',' || process || '(' || cnt || ')' || case when a_rows_format is not null then '[' || a_rows_format || ']' end end) order by rn), '/V/text()'), ',')                                                                                                                                                                 as procs
--&_IF_ORA112_OR_HIGHER            , listagg(rpad(case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end, /*case when round(ratio * &pgs) < 1 then 1 else*/ round(ratio * &pgs) /*end*/, case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end)) within group (order by rn) as procs_graph
--&_IF_LOWER_THAN_ORA112           , ltrim(extract(xmlagg(xmlelement("V", rpad(case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end, /*case when round(ratio * &pgs) < 1 then 1 else*/ round(ratio * &pgs) /*end*/, case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end)) order by rn), '/V/text()'), ',') as procs_graph
--&_IF_ORA112_OR_HIGHER            , listagg(rpad('&gc3', case when proc_cnt = 1 or cnt > avg_cnt + avg_cnt / 10 then round((ratio - case when proc_cnt = 1 then 0 else /*avg_ratio*/ 0 end) * &pgs) end, '&gc3')) within group (order by rn) as procs_graph
--&_IF_LOWER_THAN_ORA112           , ltrim(extract(xmlagg(xmlelement("V", rpad('&gc3', case when proc_cnt = 1 or ratio > avg_ratio + avg_ratio / 10 then round((ratio - case when proc_cnt = 1 then 0 else /*avg_ratio*/ 0 end) * &pgs) end, '&gc3')) order by rn), '/V/text()'), ',') as procs_graph
          --, rpad('&gc3', sum(case when proc_cnt = 1 or ratio > avg_ratio + avg_ratio / 10 /*or ratio < avg_ratio + avg_ratio / 10*/ then (ratio - case when proc_cnt = 1 then 0 else /*avg_ratio*/ 0 end) * &pgs end), '&gc3') as procs_graph
          --, rpad('&gc3', least(sum(diff / rnk / nullif(samples_active, 0) * (samples_active / nullif(total_samples_active, 0))), 1) * &pgs, '&gc3') as procs_graph
          --, rpad('&gc3', least(max(skew_plan_line / nullif(total_samples_active, 0)), 1) * &pgs, '&gc3') as procs_graph
          --, rpad('&gc3', greatest(coalesce(least(max(skew_plan_line / nullif(total_samples_active, 0)), 1), -1), least(sum(diff / rnk / nullif(samples_active, 0) * (samples_active / nullif(total_samples_active, 0))), 1)) * &pgs, '&gc3') as procs_graph
          --, rpad('&gc3', round(case when coalesce(max(dop), 1) > 1 then least(max(least(skew_plan_line, samples_active) / nullif(total_samples_active, 0)), 1) else least(sum(diff / rnk / nullif(samples_active, 0) * (samples_active / nullif(total_samples_active, 0))), 1) end * &pgs), '&gc3') as procs_graph
          --, rpad('&gc3', round(greatest(least(max(least(skew_plan_line, samples_active) / nullif(total_samples_active, 0)), 1), least(sum(diff / rnk / nullif(samples_active, 0) * (samples_active / nullif(total_samples_active, 0))), 1)) * &pgs), '&gc3') as procs_graph
          , rpad('&gc3', round(case when coalesce(max(dist_dop), 1) > 1 or coalesce(max(dop), 1) <= 1 then greatest(least(max(least(skew_plan_line, samples_active) / nullif(total_samples_active, 0)), 1), least(sum(diff / rnk / nullif(samples_active, 0) * (samples_active / nullif(total_samples_active, 0))), 1)) else least(max(least(skew_plan_line, samples_active) / nullif(total_samples_active, 0)), 1) end * &pgs), '&gc3') as procs_graph
          , case when sum(average_as) >= &rnd_thr then round(sum(average_as)) else round(sum(average_as), 1) end as average_as
          , case when sum(average_as_t) >= &rnd_thr then round(sum(average_as_t)) else round(sum(average_as_t), 1) end as average_as_t
  from
          parallel_procs2 a
        , plan_line_skew b
  where
          a.plan_line = b.sql_plan_line_id (+)
  --where
  --        rn <= &pgs + 1
  group by
          plan_line
),
parallel_procs4 as
(
  select
          plan_line
        , procs
        , average_as_t
        , average_as
        , case when length(procs_graph) > &pgs then substr(procs_graph, 1, &pgs) || '...' else procs_graph end as procs_graph
  from
          parallel_procs3
),
max_aas as
(
  select
          round(max(average_as) over ()) as max_aas
        , round(max(average_as_t) over ()) as max_aas_t
        , p.*
  from
          parallel_procs4 p
),
max_mas as
(
  select
          round(max(median_as) over ()) as max_mas
        , m.*
  from
          median_as m
),
parallel_procs as
(
  select
          plan_line
        , procs
        , procs_graph
        , rpad(coalesce(rpad('&gc3', round(average_as * &aas / nullif(max_aas, 0)), '&gc3'), ' '), &aas) || ' (' || lpad(to_char(average_as, 'TM'), 3) || ')'           as average_as_graph
        , rpad(coalesce(rpad('&gc3', round(average_as_t * &aas / nullif(max_aas_t, 0)), '&gc3'), ' '), &aas) || ' (' || lpad(to_char(average_as_t, 'TM'), 3) || ')' as average_as_t_graph
        , rpad(coalesce(rpad('&gc3', round(median_as * &aas / nullif(max_mas, 0)), '&gc3'), ' '), &aas) || ' (' || lpad(to_char(median_as, 'TM'), 3) || ')'             as median_as_graph
--        , rpad(coalesce(rpad('&gc3', round(average_as * case when max_aas > &aas then &aas / max_aas else 1 end), '&gc3'), ' '), least(&aas, max_aas)) || ' (' || lpad(to_char(average_as, 'TM'), 3) || ')'           as average_as_graph
--        , rpad(coalesce(rpad('&gc3', round(average_as_t * case when max_aas_t > &aas then &aas / max_aas_t else 1 end), '&gc3'), ' '), least(&aas, max_aas_t)) || ' (' || lpad(to_char(average_as_t, 'TM'), 3) || ')' as average_as_t_graph
--        , rpad(coalesce(rpad('&gc3', round(median_as * case when max_mas > &aas then &aas / max_mas else 1 end), '&gc3'), ' '), least(&aas, max_mas)) || ' (' || lpad(to_char(median_as, 'TM'), 3) || ')'             as median_as_graph
  from
          max_aas
        , max_mas
  where
          max_aas.plan_line = max_mas.sql_plan_line_id (+)
),
/* Activity from ASH */
ash as
(
  select
          plan_line
&_IF_ORA112_OR_HIGHER          , listagg(case when rn > &topnw + 1 then null when rn = &topnw + 1 then '...' else event || '(' || cnt || ')' end, ',') within group (order by rn) as activity
&_IF_LOWER_THAN_ORA112         , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnw + 1 then null when rn = &topnw + 1 then ',' || '...' else ',' || event || '(' || cnt || ')' end) order by rn), '/V/text()'), ',') as activity
        --, rpad(' ', nvl(round(sum_cnt / nullif(max(sum_cnt) over (), 0) * &wgs), 0) + 1, '&gc3')                                                                       as activity_graph
        , rpad(coalesce(rpad('&gc', nvl(round(sum_cnt_cpu / nullif(max(sum_cnt) over (), 0) * &wgs), 0), '&gc') || rpad('&gc2', nvl(round(sum_cnt_other / nullif(max(sum_cnt) over (), 0) * &wgs), 0), '&gc2'), ' '), &wgs) || ' (' || lpad(case when sum_cnt / nullif(total_cnt, 0) * 100 < 10 then round(sum_cnt / nullif(total_cnt, 0) * 100, 1) else round(sum_cnt / nullif(total_cnt, 0) * 100) end, 3) || '%)' as activity_graph
  from    (
            select
                    plan_line
                  , event
                  , cnt
                  , total_cnt
                  , row_number() over (partition by plan_line order by cnt desc, event) as rn
                  , sum(cnt) over (partition by plan_line)                              as sum_cnt
                  , sum(cnt_cpu) over (partition by plan_line)                          as sum_cnt_cpu
                  , sum(cnt_other) over (partition by plan_line)                        as sum_cnt_other
            from    (
                      select
                              distinct
                              sql_plan_line_id                                                                                    as plan_line
                            , event
                            , count(*) over (partition by sql_plan_line_id, event)                                                as cnt
                            , count(case when session_state = 'ON CPU' then 1 end) over (partition by sql_plan_line_id, event)    as cnt_cpu
                            , count(case when session_state != 'ON CPU' then 1 end) over (partition by sql_plan_line_id, event)   as cnt_other
                            , count(*) over ()                                                                                    as total_cnt
                      from
                              ash_base
                      where   '&_IF_ORA11_OR_HIGHER' is null
                      and     instr('&op', 'ASH') > 0
                    )
          )
  where
          rn <= &topnw + 1
  group by
          plan_line
        , total_cnt
        , sum_cnt_cpu
        , sum_cnt_other
        , sum_cnt
),
/* The last active plan lines from ASH, if SQL is currently executing */
active_plan_lines as
(
  select
          distinct
          sql_plan_line_id as plan_line
  from
          ash_base
  where   sample_time >= to_date('&ash_current_time', 'YYYY-MM-DD HH24:MI:SS') - &las / 86400
  and     '&_IF_ORA11_OR_HIGHER' is null
  and     instr('&op', 'ASH') > 0
),
/* Activity time line per SQL plan line */
plan_line_timelines as
(
  /* This query causes a wrong ORA-00979 error on 11.2.0.1, or even a core dump on parse therefore falling back to 11.1.0.7 optimizer features */
  select  /*+ optimizer_features_enable('11.1.0.7') */
          -- '+' || to_char(start_active, 'TM')                                                                                                                as start_active
          to_char(start_active, 'TM')                                                                                                                       as start_active
        , to_char(duration_secs, 'TM')                                                                                                                      as duration_secs
        , to_char(duration_secs_t, 'TM')                                                                                                                    as duration_secs_t
        , plan_line
        --, substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc3', round(duration_secs / to_number('&ds') * &tgs), '&gc3'), 1, &tgs) as time_active_graph
        , t.time_active_graph
  from
          (
            select
                    min(ash_bucket) + &sample_freq                                        as start_active
                  , max(ash_bucket) - min(ash_bucket) + &sample_freq                      as duration_secs_t
                  , count(distinct ash_bucket) * &sample_freq                             as duration_secs
                  , sql_plan_line_id                                                      as plan_line
            from
                    (
                      select
                              --cast(sample_time as date) as sample_time
                              ash_bucket
                            --, sql_exec_start
                            --, cnt_sql_exec_start
                            , sql_plan_line_id
                            --, min(sql_exec_start) keep (dense_rank last order by cnt_sql_exec_start nulls first) over () as min_sql_exec_start
                      from
                              ash_base
                      where   '&_IF_ORA11_OR_HIGHER' is null
                      and     instr('&op', 'TIMELINE') > 0
                    )
            group by
                    sql_plan_line_id
                  --, min_sql_exec_start
          ) a
        , time_active_graph t
  where
          a.plan_line = t.sql_plan_line_id
),
monitor_info1 as
(
  select
&use_monitor              plan_line_id
&use_no_monitor           0 as plan_line_id
&use_monitor            , sum(starts)               as execs
&use_no_monitor         , 0 as execs
&use_monitor            , sum(output_rows)          as a_rows
&use_no_monitor         , 0 as a_rows
&use_monitor            , sum(workarea_max_mem)     as pga
&use_no_monitor         , 0 as pga
&use_monitor            , sum(workarea_max_tempseg) as temp
&use_no_monitor         , 0 as temp
&use_monitor &_IF_ORA112_OR_HIGHER            , nullif(sum(physical_read_bytes), 0)  as io_read
&use_monitor &_IF_LOWER_THAN_ORA112           , cast(null as number)      as io_read
&use_no_monitor         , 0 as io_read
&use_monitor &_IF_ORA112_OR_HIGHER            , nullif(sum(physical_write_bytes), 0) as io_write
&use_monitor &_IF_LOWER_THAN_ORA112           , cast(null as number)      as io_write
&use_no_monitor         , 0 as io_write
&use_monitor &_IF_ORA112_OR_HIGHER            , nullif(100 - round(sum(io_interconnect_bytes) / nullif(sum(physical_read_bytes) + sum(physical_write_bytes), 0) * 100), 0) as co_percent
&use_monitor &_IF_LOWER_THAN_ORA112           , cast(null as number)      as co_percent
&use_no_monitor         , 0 as co_percent
&use_monitor &_IF_ORA112_OR_HIGHER            , nullif(sum(physical_read_requests), 0)  as io_read_req
&use_monitor &_IF_LOWER_THAN_ORA112           , cast(null as number)      as io_read_req
&use_no_monitor         , 0 as io_read_req
&use_monitor &_IF_ORA112_OR_HIGHER            , nullif(sum(physical_write_requests), 0) as io_write_req
&use_monitor &_IF_LOWER_THAN_ORA112           , cast(null as number)      as io_write_req
&use_no_monitor         , 0 as io_write_req
  from
&use_monitor              &sql_plan_monitor
&use_no_monitor           dual
  where
&use_no_monitor           1 = 2
&use_monitor              sql_id = '&si'
&use_monitor      and     sql_exec_start = to_date('&ls', '&dm')
&use_monitor      and     sql_exec_id = &li
&use_monitor      group by
&use_monitor              plan_line_id
),
monitor_info_prefmt as
(
  select
          plan_line_id
        , pga
        , trunc(log(2, abs(case pga when 0 then 1 else pga end)))                                         as power_2_pga
        , trunc(mod(log(2, abs(case pga when 0 then 1 else pga end)), 10))                                as power_2_pga_mod_10
        , temp
        , trunc(log(2, abs(case temp when 0 then 1 else temp end)))                                       as power_2_temp
        , trunc(mod(log(2, abs(case temp when 0 then 1 else temp end)), 10))                              as power_2_temp_mod_10
        , io_read
        , trunc(log(2, abs(case io_read when 0 then 1 else io_read end)))                                 as power_2_io_read
        , trunc(mod(log(2, abs(case io_read when 0 then 1 else io_read end)), 10))                        as power_2_io_read_mod_10
        , io_write
        , trunc(log(2, abs(case io_write when 0 then 1 else io_write end)))                               as power_2_io_write
        , trunc(mod(log(2, abs(case io_write when 0 then 1 else io_write end)), 10))                      as power_2_io_write_mod_10
        , execs
        , trunc(log(10, abs(case execs when 0 then 1 else execs end)))                                    as power_10_execs
        , trunc(mod(log(10, abs(case execs when 0 then 1 else execs end)), 3))                            as power_10_execs_mod_3
        , a_rows
        , trunc(log(10, abs(case a_rows when 0 then 1 else a_rows end)))                                  as power_10_a_rows
        , trunc(mod(log(10, abs(case a_rows when 0 then 1 else a_rows end)), 3))                          as power_10_a_rows_mod_3
        , io_read_req
        , trunc(log(10, abs(case io_read_req when 0 then 1 else io_read_req end)))                        as power_10_io_read_req
        , trunc(mod(log(10, abs(case io_read_req when 0 then 1 else io_read_req end)), 3))                as power_10_io_read_req_mod_3
        , io_write_req
        , trunc(log(10, abs(case io_write_req when 0 then 1 else io_write_req end)))                      as power_10_io_write_req
        , trunc(mod(log(10, abs(case io_write_req when 0 then 1 else io_write_req end)), 3))              as power_10_io_write_req_mod_3
        , case when co_percent is not null then co_percent || '%' end                                     as co_percent
  from
          monitor_info1
),
monitor_info_fmt as
(
  select
          plan_line_id
        , to_char(round(pga / power(2, power_2_pga - case when power_2_pga >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga))),3)) = 0 then power_2_pga_mod_10 + 10 else power_2_pga_mod_10 end)), 'FM99999') ||
          case power_2_pga - case when power_2_pga >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga))),3)) = 0 then power_2_pga_mod_10 + 10 else power_2_pga_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when pga is null
               then null
               else '*2^'||to_char(power_2_pga - case when power_2_pga >= 10 and trunc(mod(log(10,abs(power(2, power_2_pga))),3)) = 0 then power_2_pga_mod_10 + 10 else power_2_pga_mod_10 end)
               end
          end      as pga_format
        , to_char(round(temp / power(2, power_2_temp - case when power_2_temp >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp))),3)) = 0 then power_2_temp_mod_10 + 10 else power_2_temp_mod_10 end)), 'FM99999') ||
          case power_2_temp - case when power_2_temp >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp))),3)) = 0 then power_2_temp_mod_10 + 10 else power_2_temp_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when temp is null
               then null
               else '*2^'||to_char(power_2_temp - case when power_2_temp >= 10 and trunc(mod(log(10,abs(power(2, power_2_temp))),3)) = 0 then power_2_temp_mod_10 + 10 else power_2_temp_mod_10 end)
               end
          end      as temp_format
        , to_char(round(io_read / power(2, power_2_io_read - case when power_2_io_read >= 10 and trunc(mod(log(10,abs(power(2, power_2_io_read))),3)) = 0 then power_2_io_read_mod_10 + 10 else power_2_io_read_mod_10 end)), 'FM99999') ||
          case power_2_io_read - case when power_2_io_read >= 10 and trunc(mod(log(10,abs(power(2, power_2_io_read))),3)) = 0 then power_2_io_read_mod_10 + 10 else power_2_io_read_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when io_read is null
               then null
               else '*2^'||to_char(power_2_io_read - case when power_2_io_read >= 10 and trunc(mod(log(10,abs(power(2, power_2_io_read))),3)) = 0 then power_2_io_read_mod_10 + 10 else power_2_io_read_mod_10 end)
               end
          end      as io_read_format
        , to_char(round(io_write / power(2, power_2_io_write - case when power_2_io_write >= 10 and trunc(mod(log(10,abs(power(2, power_2_io_write))),3)) = 0 then power_2_io_write_mod_10 + 10 else power_2_io_write_mod_10 end)), 'FM99999') ||
          case power_2_io_write - case when power_2_io_write >= 10 and trunc(mod(log(10,abs(power(2, power_2_io_write))),3)) = 0 then power_2_io_write_mod_10 + 10 else power_2_io_write_mod_10 end
          when 0            then ' '
          when 1            then ' '
          when 10*1         then 'K'
          when 10*2         then 'M'
          when 10*3         then 'G'
          when 10*4         then 'T'
          when 10*5         then 'P'
          when 10*6         then 'E'
          else case
               when io_write is null
               then null
               else '*2^'||to_char(power_2_io_write - case when power_2_io_write >= 10 and trunc(mod(log(10,abs(power(2, power_2_io_write))),3)) = 0 then power_2_io_write_mod_10 + 10 else power_2_io_write_mod_10 end)
               end
          end      as io_write_format
        , to_char(round(execs / power(10, power_10_execs - case when power_10_execs > 0 and power_10_execs_mod_3 = 0 then 3 else power_10_execs_mod_3 end)), 'FM99999') ||
          case power_10_execs - case when power_10_execs > 0 and power_10_execs_mod_3 = 0 then 3 else power_10_execs_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when execs is null
               then null
               else '*10^'||to_char(power_10_execs - case when power_10_execs > 0 and power_10_execs_mod_3 = 0 then 3 else power_10_execs_mod_3 end)
               end
          end      as execs_format
        , to_char(round(a_rows / power(10, power_10_a_rows - case when power_10_a_rows > 0 and power_10_a_rows_mod_3 = 0 then 3 else power_10_a_rows_mod_3 end)), 'FM99999') ||
          case power_10_a_rows - case when power_10_a_rows > 0 and power_10_a_rows_mod_3 = 0 then 3 else power_10_a_rows_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when a_rows is null
               then null
               else '*10^'||to_char(power_10_a_rows - case when power_10_a_rows > 0 and power_10_a_rows_mod_3 = 0 then 3 else power_10_a_rows_mod_3 end)
               end
          end      as a_rows_format
        , to_char(round(io_read_req / power(10, power_10_io_read_req - case when power_10_io_read_req > 0 and power_10_io_read_req_mod_3 = 0 then 3 else power_10_io_read_req_mod_3 end)), 'FM99999') ||
          case power_10_io_read_req - case when power_10_io_read_req > 0 and power_10_io_read_req_mod_3 = 0 then 3 else power_10_io_read_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when io_read_req is null
               then null
               else '*10^'||to_char(power_10_io_read_req - case when power_10_io_read_req > 0 and power_10_io_read_req_mod_3 = 0 then 3 else power_10_io_read_req_mod_3 end)
               end
          end      as io_read_req_format
        , to_char(round(io_write_req / power(10, power_10_io_write_req - case when power_10_io_write_req > 0 and power_10_io_write_req_mod_3 = 0 then 3 else power_10_io_write_req_mod_3 end)), 'FM99999') ||
          case power_10_io_write_req - case when power_10_io_write_req > 0 and power_10_io_write_req_mod_3 = 0 then 3 else power_10_io_write_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when io_write_req is null
               then null
               else '*10^'||to_char(power_10_io_write_req - case when power_10_io_write_req > 0 and power_10_io_write_req_mod_3 = 0 then 3 else power_10_io_write_req_mod_3 end)
               end
          end      as io_write_req_format
        , co_percent
  from
          monitor_info_prefmt
),
.

-- If you need to debug, comment the following line
-- set termout off

save .xplan_ash_temp replace

-- set termout on

i
-- The next three queries are based on the original XPLAN wrapper by Adrian Billington
-- to determine the PID and ORD information, only slightly modified to deal with
-- the 10g special case that V$SQL_PLAN_STATISTICS_ALL doesn't include the ID = 0 operation
-- and starts with 1 instead for Rowsource Statistics
sql_plan_data as
(
  select
          id
        , parent_id
  from
          &plan_table_name p
  where
          sql_id = '&si'
  and     &second_id = &cn
  and     &third_id
),
hierarchy_data as
(
  select
          id
        , parent_id
  from
          sql_plan_data
  start with
          id in
          (
            select
                    id
            from
                    sql_plan_data p1
            where
                    not exists
                    (
                      select
                              null
                      from
                              sql_plan_data p2
                      where
                              p2.id = p1.parent_id
                    )
          )
  connect by
          prior id = parent_id
  order siblings by
          id desc
),
ordered_hierarchy_data as
(
  select
          id
        , parent_id                                as pid
        , row_number() over (order by rownum desc) as oid
        , max(id) over ()                          as maxid
        , min(id) over ()                          as minid
  from
          hierarchy_data
),
-- The following query uses the MAX values
-- rather than taking the values of PLAN OPERATION_ID = 0 (or 1 for 10g V$SQL_PLAN_STATISTICS_ALL)
-- for determining the grand totals
--
-- This is because queries that get cancelled do not
-- necessarily have yet sensible values in the root plan operation
--
-- Furthermore with Parallel Execution the elapsed time accumulated
-- with the ALLSTATS option for operations performed in parallel
-- will be greater than the wallclock elapsed time shown for the Query Coordinator
--
-- Note that if you use GATHER_PLAN_STATISTICS with the default
-- row sampling frequency the (LAST_)ELAPSED_TIME will be very likely
-- wrong and hence the time-based graphs and self-statistics will be misleading
--
-- Similar things might happen when cancelling queries
--
-- For queries running with STATISTICS_LEVEL = ALL (or sample frequency set to 1)
-- the A-TIME is pretty reliable
totals as
(
  select
          max(&last.cu_buffer_gets + &last.cr_buffer_gets) as total_lio
        , max(&last.elapsed_time)                          as total_elapsed
        , max(&last.disk_reads)                            as total_reads
        , max(&last.disk_writes)                           as total_writes
  from
          gv$sql_plan_statistics_all
  where
          sql_id = '&si'
  and     child_number = &cn
  and     inst_id = &plan_inst_id
  and     (instr('&fo', 'STATS') > 0 or instr('&fo', 'AROWS') > 0)
  group by
          1
),
-- The totals for the direct descendants of an operation
-- These are required for calculating the work performed
-- by a (parent) operation itself
-- Basically this is the SUM grouped by PARENT_ID
direct_desc_totals as
(
  select
          sum(&last.cu_buffer_gets + &last.cr_buffer_gets) as lio
        , sum(&last.elapsed_time)                          as elapsed
        , sum(&last.disk_reads)                            as reads
        , sum(&last.disk_writes)                           as writes
        , parent_id
  from
          gv$sql_plan_statistics_all
  where
          sql_id = '&si'
  and     child_number = &cn
  and     inst_id = &plan_inst_id
  and     (instr('&fo', 'STATS') > 0 or instr('&fo', 'AROWS') > 0)
  group by
          parent_id
),
-- Putting the three together
-- The statistics, direct descendant totals plus totals
extended_stats as
(
  select
          stats.id
        , stats.parent_id
        , stats.&last.elapsed_time                                  as elapsed
        , (stats.&last.cu_buffer_gets + stats.&last.cr_buffer_gets) as lio
        , stats.&last.starts                                        as starts
        , stats.&last.output_rows                                   as a_rows
        , stats.cardinality                                         as e_rows
        , stats.&last.disk_reads                                    as reads
        , stats.&last.disk_writes                                   as writes
        , ddt.elapsed                                               as ddt_elapsed
        , ddt.lio                                                   as ddt_lio
        , ddt.reads                                                 as ddt_reads
        , ddt.writes                                                as ddt_writes
        , t.total_elapsed
        , t.total_lio
        , t.total_reads
        , t.total_writes
  from
          gv$sql_plan_statistics_all stats
        , direct_desc_totals ddt
        , totals t
  where
          stats.sql_id='&si'
  and     stats.child_number = &cn
  and     stats.inst_id = &plan_inst_id
  and     ddt.parent_id (+) = stats.id
  and     (instr('&fo', 'STATS') > 0 or instr('&fo', 'AROWS') > 0)
),
-- Further information derived from above
derived_stats1 as
(
  select
          id
        , greatest(elapsed - nvl(ddt_elapsed , 0), 0)                              as elapsed_self
        , greatest(lio - nvl(ddt_lio, 0), 0)                                       as lio_self
        , trunc((greatest(lio - nvl(ddt_lio, 0), 0)) / nullif(a_rows, 0))          as lio_ratio
        , greatest(reads - nvl(ddt_reads, 0), 0)                                   as reads_self
        , greatest(writes - nvl(ddt_writes,0) ,0)                                  as writes_self
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , a_rows
        , trunc(log(10, nullif(starts * e_rows / nullif(a_rows, 0), 0)))           as tcf_ratio
        , starts * e_rows                                                          as e_rows_times_start
  from
          extended_stats
),
-- Add the analytic MAX() function
derived_stats as
(
  select
          id
        , elapsed_self
        , lio_self
        , lio_ratio
        , reads_self
        , writes_self
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , a_rows
        , max(elapsed_self) over () as max_elapsed_self
        , max(lio_self)     over () as max_lio_self
        , max(reads_self)   over () as max_reads_self
        , max(writes_self)  over () as max_writes_self
        , tcf_ratio
        , e_rows_times_start
  from
          derived_stats1
),
/* Format the data as required */
formatted_data1 as
(
  select
          id
        , lio_ratio
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , a_rows
        , to_char(numtodsinterval(round(elapsed_self / 10000) * 10000 / 1000000, 'SECOND'))                         as e_time_interval
          /* Imitate the DBMS_XPLAN number formatting */
        , case
          when lio_self >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when lio_self >= 10000000000000000000 then to_char(lio_self/1000000000000000000, 'FM99999') || 'E'
          when lio_self >= 10000000000000000 then to_char(lio_self/1000000000000000, 'FM99999') || 'P'
          when lio_self >= 10000000000000 then to_char(lio_self/1000000000000, 'FM99999') || 'T'
          when lio_self >= 10000000000 then to_char(lio_self/1000000000, 'FM99999') || 'G'
          when lio_self >= 10000000 then to_char(lio_self/1000000, 'FM99999') || 'M'
          when lio_self >= 100000 then to_char(lio_self/1000, 'FM99999') || 'K'
          else to_char(lio_self, 'FM99999') || ' '
          end                                                                                                       as lio_self_format
        , case
          when reads_self >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when reads_self >= 10000000000000000000 then to_char(reads_self/1000000000000000000, 'FM99999') || 'E'
          when reads_self >= 10000000000000000 then to_char(reads_self/1000000000000000, 'FM99999') || 'P'
          when reads_self >= 10000000000000 then to_char(reads_self/1000000000000, 'FM99999') || 'T'
          when reads_self >= 10000000000 then to_char(reads_self/1000000000, 'FM99999') || 'G'
          when reads_self >= 10000000 then to_char(reads_self/1000000, 'FM99999') || 'M'
          when reads_self >= 100000 then to_char(reads_self/1000, 'FM99999') || 'K'
          else to_char(reads_self, 'FM99999') || ' '
          end                                                                                                       as reads_self_format
        , case
          when writes_self >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when writes_self >= 10000000000000000000 then to_char(writes_self/1000000000000000000, 'FM99999') || 'E'
          when writes_self >= 10000000000000000 then to_char(writes_self/1000000000000000, 'FM99999') || 'P'
          when writes_self >= 10000000000000 then to_char(writes_self/1000000000000, 'FM99999') || 'T'
          when writes_self >= 10000000000 then to_char(writes_self/1000000000, 'FM99999') || 'G'
          when writes_self >= 10000000 then to_char(writes_self/1000000, 'FM99999') || 'M'
          when writes_self >= 100000 then to_char(writes_self/1000, 'FM99999') || 'K'
          else to_char(writes_self, 'FM99999') || ' '
          end                                                                                                       as writes_self_format
        , case
          when e_rows_times_start >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when e_rows_times_start >= 10000000000000000000 then to_char(e_rows_times_start/1000000000000000000, 'FM99999') || 'E'
          when e_rows_times_start >= 10000000000000000 then to_char(e_rows_times_start/1000000000000000, 'FM99999') || 'P'
          when e_rows_times_start >= 10000000000000 then to_char(e_rows_times_start/1000000000000, 'FM99999') || 'T'
          when e_rows_times_start >= 10000000000 then to_char(e_rows_times_start/1000000000, 'FM99999') || 'G'
          when e_rows_times_start >= 10000000 then to_char(e_rows_times_start/1000000, 'FM99999') || 'M'
          when e_rows_times_start >= 100000 then to_char(e_rows_times_start/1000, 'FM99999') || 'K'
          else to_char(e_rows_times_start, 'FM99999') || ' '
          end                                                                                                       as e_rows_times_start_format
        , case
          when a_rows >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when a_rows >= 10000000000000000000 then to_char(a_rows/1000000000000000000, 'FM99999') || 'E'
          when a_rows >= 10000000000000000 then to_char(a_rows/1000000000000000, 'FM99999') || 'P'
          when a_rows >= 10000000000000 then to_char(a_rows/1000000000000, 'FM99999') || 'T'
          when a_rows >= 10000000000 then to_char(a_rows/1000000000, 'FM99999') || 'G'
          when a_rows >= 10000000 then to_char(a_rows/1000000, 'FM99999') || 'M'
          when a_rows >= 100000 then to_char(a_rows/1000, 'FM99999') || 'K'
          else to_char(a_rows, 'FM99999') || ' '
          end                                                                                                       as a_rows_format
        , rpad(coalesce(rpad(' ', nvl(round(elapsed_self / nullif(case when '&ext_rowsource_graphs_maxrel' = 'YES' then max_elapsed_self else total_elapsed end, 0) * 12), 0) + 1, '&gc3'), ' '), 12) || case when elapsed_self > 0 then ' (' || lpad(round(elapsed_self / nullif(total_elapsed, 0) * 100), 3) || '%)' end as elapsed_self_graph
        , rpad(coalesce(rpad(' ', nvl(round(lio_self / nullif(case when '&ext_rowsource_graphs_maxrel' = 'YES' then max_lio_self else total_lio end, 0) * 12), 0) + 1, '&gc3'), ' '), 12) || case when lio_self > 0 then ' (' || lpad(round(lio_self / nullif(total_lio, 0) * 100), 3) || '%)' end                         as lio_self_graph
        , rpad(coalesce(rpad(' ', nvl(round(reads_self / nullif(case when '&ext_rowsource_graphs_maxrel' = 'YES' then max_reads_self else total_reads end, 0) * 12), 0) + 1, '&gc3'), ' '), 12) || case when reads_self > 0 then ' (' || lpad(round(reads_self / nullif(total_reads, 0) * 100), 3) || '%)' end             as reads_self_graph
        , rpad(coalesce(rpad(' ', nvl(round(writes_self / nullif(case when '&ext_rowsource_graphs_maxrel' = 'YES' then max_writes_self else total_writes end, 0) * 12), 0) + 1, '&gc3'), ' '), 12) || case when writes_self > 0 then ' (' || lpad(round(writes_self / nullif(total_writes, 0) * 100), 3) || '%)' end       as writes_self_graph
        , ' ' ||
          case
          when tcf_ratio > 0
          then rpad('-', tcf_ratio, '-')
          else rpad('+', tcf_ratio * -1, '+')
          end                                                                                                       as tcf_graph
  from
          derived_stats
),
/* The final formatted data */
formatted_data as
(
  select
          /*+ Convert the INTERVAL representation to the A-TIME representation used by DBMS_XPLAN
              by turning the days into hours */
          to_char(to_number(substr(e_time_interval, 2, 9)) * 24 + to_number(substr(e_time_interval, 12, 2)), 'FM900') ||
          substr(e_time_interval, 14, 9)
          as a_time_self
        , a.*
  from
          formatted_data1 a
),
/* Combine the information with the original DBMS_XPLAN output */
xplan_data as (
  select
          x.plan_table_output
        , o.id
        , o.pid
        , o.oid
        , o.maxid
        , o.minid
        , a.a_time_self
        , a.lio_self_format
        , a.reads_self_format
        , a.writes_self_format
        , a.a_rows_format
        , cast(a.elapsed_self_graph as varchar2(20))               as elapsed_self_graph
        , cast(a.lio_self_graph as varchar2(20))                   as lio_self_graph
        , cast(a.reads_self_graph as varchar2(20))                 as reads_self_graph
        , cast(a.writes_self_graph as varchar2(20))                as writes_self_graph
        , a.lio_ratio
        , cast(a.tcf_graph as varchar2(20))                        as tcf_graph
        , a.total_elapsed
        , a.total_lio
        , a.total_reads
        , a.total_writes
        , a.a_rows
        , a.e_rows_times_start_format
        , cast(p.procs as varchar2(200))                           as procs
        , cast(p.procs_graph as varchar2(100))                     as procs_graph
        , cast(p.average_as_graph as varchar2(100))                as average_as_graph
        , cast(p.average_as_t_graph as varchar2(100))              as average_as_t_graph
        , cast(p.median_as_graph as varchar2(100))                 as median_as_graph
        , cast(w.activity as varchar2(200))                        as activity
        , cast(w.activity_graph as varchar2(100))                  as activity_graph
        , case when l.plan_line is not null then '&active_ind' end as line_active
        , t.start_active
        , t.duration_secs
        , t.duration_secs_t
        , cast(t.time_active_graph as varchar2(100))               as time_active_graph
        , cast(m.pga_format as varchar2(10))                       as pga
        , cast(m.temp_format as varchar2(10))                      as temp
        , cast(m.io_read_format as varchar2(10))                   as io_read
        , cast(m.io_write_format as varchar2(10))                  as io_write
        , cast(m.io_read_req_format as varchar2(10))               as io_read_req
        , cast(m.io_write_req_format as varchar2(10))              as io_write_req
        , cast(m.execs_format as varchar2(10))                     as execs
        , cast(m.a_rows_format as varchar2(10))                    as a_rows_m
        , cast(m.co_percent as varchar2(5))                        as co
        , x.rn
  from
          (
            select  /* Take advantage of 11g table function dynamic sampling */
                    /*+ dynamic_sampling(dc, 2) */
                    /* This ROWNUM determines the order of the output/processing */
                    rownum as rn
                  , plan_table_output
            from
                    /* From 11.2.0.2 on this will execute the given cursor on all RAC instances but effectively only on that instance where the plan should reside */
                    /* The GV$ table function is undocumented but used for a similar purpose by 11.2.0.2+ Real-Time SQL Monitoring */
&_IF_ORA11202_OR_HIGHER                   table(gv$(cursor(select * from table(&plan_function('&si',&cn, &par_fil.replace('&fo', 'AROWS', ''))) where USERENV('INSTANCE') = &plan_inst_id))) dc
                    /* Prior to 11.2.0.2 this problem is not solved yet as GV$() is not supported and DBMS_XPLAN.DISPLAY cannot show Rowsource statistics and would require a different parameter set to call */
&_IF_LOWER_THAN_ORA11202                  table(&plan_function('&si',&cn, &par_fil.replace('&fo', 'AROWS', ''))) dc
          ) x
        , ordered_hierarchy_data o
        , formatted_data a
        , parallel_procs p
        , ash w
        , active_plan_lines l
        , plan_line_timelines t
        , monitor_info_fmt m
  where
          o.id (+) = case
                     when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                     then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                     end
  and     a.id (+) = case
                     when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                     then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                     end
  and     p.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     w.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     l.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     t.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     m.plan_line_id (+) = case
                            when regexp_like(x.plan_table_output, '^\|-?[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
)
/* Inject the additional data into the original DBMS_XPLAN output
   by using the MODEL clause */
select  /* XPLAN_ASH ACTIVITY_PLAN_LINE SQL_ID: &si */
        plan_table_output
      , plan_table_count
from
        xplan_data
model
        dimension by (rn as r)
        measures
        (
          cast(plan_table_output as varchar2(1000))                                                                      as plan_table_output
        , id
        , maxid
        , minid
        , pid
        , oid
        , a_time_self
        , lio_self_format
        , reads_self_format
        , writes_self_format
        , e_rows_times_start_format
        , a_rows_format
        , elapsed_self_graph
        , lio_self_graph
        , reads_self_graph
        , writes_self_graph
        , lio_ratio
        , tcf_graph
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , a_rows
        , a_rows_m
        , execs
        , pga
        , temp
        , io_read
        , io_write
        , io_read_req
        , io_write_req
        , co
        , greatest(max(length(maxid)) over () + 3, 6)                                                                    as csize
        , cast(null as varchar2(200))                                                                                    as inject
        , cast(null as varchar2(300))                                                                                    as inject2
        , cast(null as varchar2(500))                                                                                    as inject3
        , greatest(max(length(a_rows_m)) over () + 3, 8)                                                                 as a_rows_m_size
        , greatest(max(length(execs)) over () + 3, 8)                                                                    as execs_size
        , greatest(max(length(pga)) over () + 3, 8)                                                                      as pga_size
        , greatest(max(length(temp)) over () + 3, 8)                                                                     as temp_size
        , greatest(max(length(io_read)) over () + 3, 8)                                                                  as io_read_size
        , greatest(max(length(io_write)) over () + 3, 8)                                                                 as io_write_size
        , greatest(max(length(io_read_req)) over () + 3, 10)                                                             as io_read_req_size
        , greatest(max(length(io_write_req)) over () + 3, 10)                                                            as io_write_req_size
        , greatest(max(length(co)) over () + 3, 7)                                                                       as co_size
        , greatest(max(length(procs)) over () + 3, 28)                                                                   as procs_size
        , greatest(max(length(procs_graph)) over () + 3, 29)                                                             as procs_graph_size
        , greatest(max(length(average_as_graph)) over () + 3, 28)                                                        as average_as_graph_size
        , greatest(max(length(average_as_t_graph)) over () + 3, 28)                                                      as average_as_t_graph_size
        , greatest(max(length(median_as_graph)) over () + 3, 24)                                                         as median_as_graph_size
        , greatest(max(length(activity)) over () + 3, 22)                                                                as activity_size
        , greatest(max(length(activity_graph)) over () + 3, 22)                                                          as activity_graph_size
        , greatest(max(length(line_active)) over () + 3, 6)                                                              as line_active_size
        , greatest(max(length(start_active)) over () + 3, 8)                                                             as start_active_size
        , greatest(max(length(duration_secs)) over () + 3, 8)                                                            as duration_secs_size
        , greatest(max(length(duration_secs_t)) over () + 3, 8)                                                          as duration_secs_t_size
        , greatest(max(length(time_active_graph)) over () + 3, 20)                                                       as time_active_graph_size
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(procs)) over () end       as procs_is_not_null
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(procs_graph)) over () end as procs_graph_is_not_null
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(average_as_graph)) over () end as average_as_graph_is_not_null
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(average_as_t_graph)) over () end as average_as_t_graph_is_not_null
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(median_as_graph)) over () end as median_as_graph_is_not_null
        , case when instr('&op', 'ASH') > 0 then max(length(activity)) over () end                                       as activity_is_not_null
        , case when instr('&op', 'ASH') > 0 then max(length(activity_graph)) over () end                                 as activity_graph_is_not_null
        , case when instr('&op', 'ASH') > 0 then max(length(line_active)) over () end                                    as line_active_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(start_active)) over () end                              as start_active_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(duration_secs)) over () end                             as duration_secs_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(duration_secs_t)) over () end                           as duration_secs_t_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(time_active_graph)) over () end                         as time_active_graph_is_not_null
        , case when instr('&fo', 'AROWS') > 0 then max(length(a_rows_format)) over () end                                as a_rows_format_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(a_rows_m)) over () end                                   as a_rows_m_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(execs)) over () end                                      as execs_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(pga)) over () end                                        as pga_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(temp)) over () end                                       as temp_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(io_read)) over () end                                    as io_read_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(io_write)) over () end                                   as io_write_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(io_read_req)) over () end                                as io_read_req_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(io_write_req)) over () end                               as io_write_req_is_not_null
        , case when instr('&op', 'MONITOR') > 0 then max(length(co)) over () end                                         as co_is_not_null
        , procs
        , procs_graph
        , average_as_graph
        , average_as_t_graph
        , median_as_graph
        , activity
        , activity_graph
        , line_active
        , start_active
        , duration_secs
        , duration_secs_t
        , time_active_graph
        , count(*) over () as plan_table_count
        )
        rules sequential order
        (
          /* Prepare the injection of the OID / PID / ACT info */
          inject[r]  = case
                               /* MINID/MAXID are the same for all rows
                                  so it doesn't really matter
                                  which offset we refer to */
                       when    id[cv(r)+1] = minid[cv(r)+1]
                            or id[cv(r)+3] = minid[cv(r)+3]
                            or id[cv(r)-1] = maxid[cv(r)-1]
                       then rpad('-', case when '&c_pid' is not null then csize[cv()] else 0 end + case when '&c_ord' is not null then csize[cv()] else 0 end + case when line_active_is_not_null[cv()] is not null and '&c_act' is not null then line_active_size[cv()] else 0 end, '-')
                       when id[cv(r)+2] = minid[cv(r)+2]
                       then '|' || case when '&c_pid' is not null then lpad('Pid |', csize[cv()]) end || case when '&c_ord' is not null then lpad('Ord |', csize[cv()]) end || case when line_active_is_not_null[cv()] is not null and '&c_act' is not null then lpad('Act |', line_active_size[cv()]) end
                       when id[cv()] is not null
                       then '|' || case when '&c_pid' is not null then lpad(pid[cv()] || ' |', csize[cv()]) end || case when '&c_ord' is not null then lpad(oid[cv()] || ' |', csize[cv()]) end || case when line_active_is_not_null[cv()] is not null and '&c_act' is not null then lpad(line_active[cv()] || ' |', line_active_size[cv()]) end
                       end
          /* Prepare the injection of the remaining info */
        , inject2[r] = case
                       when    id[cv(r)+1] = minid[cv(r)+1]
                            or id[cv(r)+3] = minid[cv(r)+3]
                            or id[cv(r)-1] = maxid[cv(r)-1]
                       -- Determine the line width for the three rows where we have horizontal lines
                       then rpad('-',
                            case when coalesce(a_rows_format_is_not_null[cv(r)+1], a_rows_format_is_not_null[cv(r)+3], a_rows_format_is_not_null[cv(r)-1]) is not null then
                            9  else 0 end /* A_ROWS */            +
                            case when coalesce(total_elapsed[cv(r)+1], total_elapsed[cv(r)+3], total_elapsed[cv(r)-1]) > 0 and '&c_a_time_self' is not null then
                            14 else 0 end /* A_TIME_SELF */       +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_lio_self' is not null then
                            11 else 0 end /* LIO_SELF */          +
                            case when coalesce(total_reads[cv(r)+1], total_reads[cv(r)+3], total_reads[cv(r)-1]) > 0 and '&c_reads_self' is not null then
                            11 else 0 end /* READS_SELF */        +
                            case when coalesce(total_writes[cv(r)+1], total_writes[cv(r)+3], total_writes[cv(r)-1]) > 0 and '&c_writes_self' is not null then
                            11 else 0 end /* WRITES_SELF */       +
                            case when coalesce(total_elapsed[cv(r)+1], total_elapsed[cv(r)+3], total_elapsed[cv(r)-1]) > 0 and '&c_a_time_self_graph' is not null then
                            21 else 0 end /* A_TIME_SELF_GRAPH */ +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_lio_self_graph' is not null then
                            21 else 0 end /* LIO_SELF_GRAPH */    +
                            case when coalesce(total_reads[cv(r)+1], total_reads[cv(r)+3], total_reads[cv(r)-1]) > 0 and '&c_reads_self_graph' is not null then
                            21 else 0 end /* READS_SELF_GRAPH */  +
                            case when coalesce(total_writes[cv(r)+1], total_writes[cv(r)+3], total_writes[cv(r)-1]) > 0 and '&c_writes_self_graph' is not null then
                            21 else 0 end /* WRITES_SELF_GRAPH */ +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_lio_ratio' is not null then
                            11 else 0 end /* LIO_RATIO */         +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_tcf_graph' is not null then
                            11 else 0 end /* TCF_GRAPH */         +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_e_rows_times_start' is not null then
                            11 else 0 end /* E_ROWS_TIMES_START */
                            , '-')
                       -- The additional headings
                       when id[cv(r)+2] = minid[cv(r)+2]
                       then
                            case when a_rows_format_is_not_null[cv(r)+2] is not null then
                            lpad('A-Rows |'      , 9)  end ||
                            case when total_elapsed[cv(r)+2] > 0 and '&c_a_time_self' is not null then
                            lpad('A-Time Self |' , 14) end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_lio_self' is not null then
                            lpad('Bufs Self |'   , 11) end ||
                            case when total_reads[cv(r)+2] > 0 and '&c_reads_self' is not null then
                            lpad('Reads Self|'   , 11) end ||
                            case when total_writes[cv(r)+2] > 0 and '&c_writes_self' is not null then
                            lpad('Write Self|'   , 11) end ||
                            case when total_elapsed[cv(r)+2] > 0 and '&c_a_time_self_graph' is not null then
                            rpad(' A-Ti S-Graph', 20) || '|' end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_lio_self_graph' is not null then
                            rpad(' Bufs S-Graph', 20) || '|' end ||
                            case when total_reads[cv(r)+2] > 0 and '&c_reads_self_graph' is not null then
                            rpad(' Reads S-Graph', 20) || '|' end ||
                            case when total_writes[cv(r)+2] > 0 and '&c_writes_self_graph' is not null then
                            rpad(' Write S-Graph', 20) || '|' end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_lio_ratio' is not null then
                            lpad('LIO Ratio |'   , 11) end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_tcf_graph' is not null then
                            lpad('TCF Graph |'   , 11) end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_e_rows_times_start' is not null then
                            lpad('E-Rows*Sta|'   , 11) end
                       -- The actual data
                       when id[cv()] is not null
                       then
                            case when a_rows_format_is_not_null[cv()] is not null then
                            lpad(a_rows_format[cv()]             ||  '|', 9)  end ||
                            case when total_elapsed[cv()] > 0 and '&c_a_time_self' is not null then
                            lpad(a_time_self[cv()]               || ' |', 14) end ||
                            case when total_lio[cv()] > 0 and '&c_lio_self' is not null then
                            lpad(lio_self_format[cv()]           ||  '|', 11) end ||
                            case when total_reads[cv()] > 0 and '&c_reads_self' is not null then
                            lpad(reads_self_format[cv()]         ||  '|', 11) end ||
                            case when total_writes[cv()] > 0 and '&c_writes_self' is not null then
                            lpad(writes_self_format[cv()]        ||  '|', 11) end ||
                            case when total_elapsed[cv()] > 0 and '&c_a_time_self_graph' is not null then
                            rpad(elapsed_self_graph[cv()], 20)   ||  '|'      end ||
                            case when total_lio[cv()] > 0 and '&c_lio_self_graph' is not null then
                            rpad(lio_self_graph[cv()], 20)       ||  '|'      end ||
                            case when total_reads[cv()] > 0 and '&c_reads_self_graph' is not null then
                            rpad(reads_self_graph[cv()], 20)     ||  '|'      end ||
                            case when total_writes[cv()] > 0 and '&c_writes_self_graph' is not null then
                            rpad(writes_self_graph[cv()], 20)    ||  '|'      end ||
                            case when total_lio[cv()] > 0 and '&c_lio_ratio' is not null then
                            lpad(lio_ratio[cv()]                 || ' |', 11) end ||
                            case when total_lio[cv()] > 0 and '&c_tcf_graph' is not null then
                            rpad(tcf_graph[cv()], 9)             || ' |'      end ||
                            case when total_lio[cv()] > 0 and '&c_e_rows_times_start' is not null then
                            lpad(e_rows_times_start_format[cv()] ||  '|', 11) end
                       end
        /* The additional ASH / Real-Time SQL Monitoring based info (except Active which is part of inject) */
        , inject3[r] = case
                       when    id[cv(r)+1] = minid[cv(r)+1]
                            or id[cv(r)+3] = minid[cv(r)+3]
                            or id[cv(r)-1] = maxid[cv(r)-1]
                       -- Determine the line width for the three rows where we have horizontal lines
                       then rpad('-',
                            case when coalesce(execs_is_not_null[cv(r)+1], execs_is_not_null[cv(r)+3], execs_is_not_null[cv(r)-1]) is not null and '&c_execs' is not null then
                            execs_size[cv(r)+1] else 0 end              /* EXECS */              +
                            case when coalesce(a_rows_m_is_not_null[cv(r)+1], a_rows_m_is_not_null[cv(r)+3], a_rows_m_is_not_null[cv(r)-1]) is not null and '&c_a_rows_m' is not null then
                            a_rows_m_size[cv(r)+1] else 0 end           /* A_ROWS_M */           +
                            case when coalesce(pga_is_not_null[cv(r)+1], pga_is_not_null[cv(r)+3], pga_is_not_null[cv(r)-1]) is not null and '&c_pga' is not null then
                            pga_size[cv(r)+1] else 0 end                /* PGA */                +
                            case when coalesce(temp_is_not_null[cv(r)+1], temp_is_not_null[cv(r)+3], temp_is_not_null[cv(r)-1]) is not null and '&c_temp' is not null then
                            temp_size[cv(r)+1] else 0 end               /* TEMP */               +
                            case when coalesce(io_read_is_not_null[cv(r)+1], io_read_is_not_null[cv(r)+3], io_read_is_not_null[cv(r)-1]) is not null and '&c_io_read' is not null then
                            io_read_size[cv(r)+1] else 0 end            /* IO_READ */            +
                            case when coalesce(io_write_is_not_null[cv(r)+1], io_write_is_not_null[cv(r)+3], io_write_is_not_null[cv(r)-1]) is not null and '&c_io_write' is not null then
                            io_write_size[cv(r)+1] else 0 end           /* IO_WRITE */           +
                            case when coalesce(co_is_not_null[cv(r)+1], co_is_not_null[cv(r)+3], co_is_not_null[cv(r)-1]) is not null and '&c_co' is not null then
                            co_size[cv(r)+1] else 0 end                 /* CO */                 +
                            case when coalesce(io_read_req_is_not_null[cv(r)+1], io_read_req_is_not_null[cv(r)+3], io_read_req_is_not_null[cv(r)-1]) is not null and '&c_io_read_req' is not null then
                            io_read_req_size[cv(r)+1] else 0 end        /* IO_READ_REQ */            +
                            case when coalesce(io_write_req_is_not_null[cv(r)+1], io_write_req_is_not_null[cv(r)+3], io_write_req_is_not_null[cv(r)-1]) is not null and '&c_io_write_req' is not null then
                            io_write_req_size[cv(r)+1] else 0 end       /* IO_WRITE_REQ */           +
                            case when coalesce(start_active_is_not_null[cv(r)+1], start_active_is_not_null[cv(r)+3], start_active_is_not_null[cv(r)-1]) is not null and '&c_start_active' is not null then
                            start_active_size[cv(r)+1] else 0 end       /* START_ACTIVE */       +
                            case when coalesce(duration_secs_t_is_not_null[cv(r)+1], duration_secs_t_is_not_null[cv(r)+3], duration_secs_t_is_not_null[cv(r)-1]) is not null and '&c_duration_secs_t' is not null then
                            duration_secs_t_size[cv(r)+1] else 0 end    /* DURATION_SECS_T */    +
                            case when coalesce(duration_secs_is_not_null[cv(r)+1], duration_secs_is_not_null[cv(r)+3], duration_secs_is_not_null[cv(r)-1]) is not null and '&c_duration_secs' is not null then
                            duration_secs_size[cv(r)+1] else 0 end      /* DURATION_SECS */      +
                            case when coalesce(time_active_graph_is_not_null[cv(r)+1], time_active_graph_is_not_null[cv(r)+3], time_active_graph_is_not_null[cv(r)-1]) is not null and '&c_time_active_graph' is not null then
                            time_active_graph_size[cv(r)+1] else 0 end  /* TIME_ACTIVE_GRAPH */  +
                            case when coalesce(procs_is_not_null[cv(r)+1], procs_is_not_null[cv(r)+3], procs_is_not_null[cv(r)-1]) is not null and '&c_procs' is not null then
                            procs_size[cv(r)+1] else 0 end              /* PROCS */              +
                            case when coalesce(procs_graph_is_not_null[cv(r)+1], procs_graph_is_not_null[cv(r)+3], procs_graph_is_not_null[cv(r)-1]) is not null and '&c_procs_graph' is not null then
                            procs_graph_size[cv(r)+1] else 0 end        /* PROCS_GRAPH */        +
                            case when coalesce(average_as_t_graph_is_not_null[cv(r)+1], average_as_t_graph_is_not_null[cv(r)+3], average_as_t_graph_is_not_null[cv(r)-1]) is not null and '&c_average_as_t_graph' is not null then
                            average_as_t_graph_size[cv(r)+1] else 0 end /* AVERAGE_AS_T_GRAPH */ +
                            case when coalesce(average_as_graph_is_not_null[cv(r)+1], average_as_graph_is_not_null[cv(r)+3], average_as_graph_is_not_null[cv(r)-1]) is not null and '&c_average_as_graph' is not null then
                            average_as_graph_size[cv(r)+1] else 0 end   /* AVERAGE_AS_GRAPH */   +
                            case when coalesce(median_as_graph_is_not_null[cv(r)+1], median_as_graph_is_not_null[cv(r)+3], median_as_graph_is_not_null[cv(r)-1]) is not null and '&c_median_as_graph' is not null then
                            median_as_graph_size[cv(r)+1] else 0 end    /* MEDIAN_AS_GRAPH */    +
                            case when coalesce(activity_graph_is_not_null[cv(r)+1], activity_graph_is_not_null[cv(r)+3], activity_graph_is_not_null[cv(r)-1]) is not null and '&c_activity_graph' is not null then
                            activity_graph_size[cv(r)+1] else 0 end     /* ACTIVITY_GRAPH */     +
                            case when coalesce(activity_is_not_null[cv(r)+1], activity_is_not_null[cv(r)+3], activity_is_not_null[cv(r)-1]) is not null and '&c_activity' is not null then
                            activity_size[cv(r)+1] else 0 end           /* ACTIVITY */
                            , '-')
                       -- The additional headings
                       when id[cv(r)+2] = minid[cv(r)+2]
                       then
                            case when execs_is_not_null[cv(r)+2] is not null and '&c_execs' is not null then
                            rpad(' Execs', execs_size[cv(r)+2] - 1)                                    || '|' end ||
                            case when a_rows_m_is_not_null[cv(r)+2] is not null and '&c_a_rows_m' is not null then
                            rpad(' A-Rows', a_rows_m_size[cv(r)+2] - 1)                                || '|' end ||
                            case when pga_is_not_null[cv(r)+2] is not null and '&c_pga' is not null then
                            rpad(' PGA', pga_size[cv(r)+2] - 1)                                        || '|' end ||
                            case when temp_is_not_null[cv(r)+2] is not null and '&c_temp' is not null then
                            rpad(' Temp', temp_size[cv(r)+2] - 1)                                      || '|' end ||
                            case when io_read_is_not_null[cv(r)+2] is not null and '&c_io_read' is not null then
                            rpad(' Reads', io_read_size[cv(r)+2] - 1)                                  || '|' end ||
                            case when io_write_is_not_null[cv(r)+2] is not null and '&c_io_write' is not null then
                            rpad(' Writes', io_write_size[cv(r)+2] - 1)                                || '|' end ||
                            case when co_is_not_null[cv(r)+2] is not null and '&c_co' is not null then
                            rpad(' CellO%', co_size[cv(r)+2] - 1)                                      || '|' end ||
                            case when io_read_is_not_null[cv(r)+2] is not null and '&c_io_read_req' is not null then
                            rpad(' ReadReq', io_read_req_size[cv(r)+2] - 1)                            || '|' end ||
                            case when io_write_is_not_null[cv(r)+2] is not null and '&c_io_write_req' is not null then
                            rpad(' WriteReq', io_write_req_size[cv(r)+2] - 1)                          || '|' end ||
                            case when start_active_is_not_null[cv(r)+2] is not null and '&c_start_active' is not null then
                            rpad(' Start', start_active_size[cv(r)+2] - 1)                             || '|' end ||
                            case when duration_secs_t_is_not_null[cv(r)+2] is not null and '&c_duration_secs_t' is not null then
                            rpad(' Dur(T)', duration_secs_t_size[cv(r)+2] - 1)                         || '|' end ||
                            case when duration_secs_is_not_null[cv(r)+2] is not null and '&c_duration_secs' is not null then
                            rpad(' Dur(A)', duration_secs_size[cv(r)+2] - 1)                           || '|' end ||
                            case when time_active_graph_is_not_null[cv(r)+2] is not null and '&c_time_active_graph' is not null then
                            rpad(' Time Active Graph', time_active_graph_size[cv(r)+2] - 1)            || '|' end ||
                            case when procs_is_not_null[cv(r)+2] is not null and '&c_procs' is not null then
                            rpad(' Parallel Distribution ASH', procs_size[cv(r)+2] - 1)                || '|' end ||
                            case when procs_graph_is_not_null[cv(r)+2] is not null and '&c_procs_graph' is not null then
                            rpad(' Parallel Execution Skew ASH', procs_graph_size[cv(r)+2] - 1)        || '|' end ||
                            case when average_as_t_graph_is_not_null[cv(r)+2] is not null and '&c_average_as_t_graph' is not null then
                            rpad(' Avg Act Sess Graph (T) ASH', average_as_t_graph_size[cv(r)+2] - 1)  || '|' end ||
                            case when average_as_graph_is_not_null[cv(r)+2] is not null and '&c_average_as_graph' is not null then
                            rpad(' Avg Act Sess Graph (A) ASH', average_as_graph_size[cv(r)+2] - 1)    || '|' end ||
                            case when median_as_graph_is_not_null[cv(r)+2] is not null and '&c_median_as_graph' is not null then
                            rpad(' Med Act Sess Graph ASH', median_as_graph_size[cv(r)+2] - 1)         || '|' end ||
                            case when activity_graph_is_not_null[cv(r)+2] is not null and '&c_activity_graph' is not null then
                            rpad(' Activity Graph ASH', activity_graph_size[cv(r)+2] - 1)              || '|' end ||
                            case when activity_is_not_null[cv(r)+2] is not null and '&c_activity' is not null then
                            rpad(' Top &topnw Activity ASH', activity_size[cv(r)+2] - 1)               || '|' end
                       -- The actual data
                       when id[cv()] is not null
                       then
                            case when execs_is_not_null[cv()] is not null and '&c_execs' is not null then
                            lpad(execs[cv()]           ||  ' |', execs_size[cv()])                             end ||
                            case when a_rows_m_is_not_null[cv()] is not null and '&c_a_rows_m' is not null then
                            lpad(a_rows_m[cv()]           ||  ' |', a_rows_m_size[cv()])                       end ||
                            case when pga_is_not_null[cv()] is not null and '&c_pga' is not null then
                            lpad(pga[cv()]           ||  ' |', pga_size[cv()])                                 end ||
                            case when temp_is_not_null[cv()] is not null and '&c_temp' is not null then
                            lpad(temp[cv()]           ||  ' |', temp_size[cv()])                               end ||
                            case when io_read_is_not_null[cv()] is not null and '&c_io_read' is not null then
                            lpad(io_read[cv()]           ||  ' |', io_read_size[cv()])                         end ||
                            case when io_write_is_not_null[cv()] is not null and '&c_io_write' is not null then
                            lpad(io_write[cv()]           ||  ' |', io_write_size[cv()])                       end ||
                            case when co_is_not_null[cv()] is not null and '&c_co' is not null then
                            lpad(co[cv()]           ||  ' |', co_size[cv()])                                   end ||
                            case when io_read_req_is_not_null[cv()] is not null and '&c_io_read_req' is not null then
                            lpad(io_read_req[cv()]           ||  ' |', io_read_req_size[cv()])                 end ||
                            case when io_write_req_is_not_null[cv()] is not null and '&c_io_write_req' is not null then
                            lpad(io_write_req[cv()]           ||  ' |', io_write_req_size[cv()])               end ||
                            case when start_active_is_not_null[cv()] is not null and '&c_start_active' is not null then
                            lpad(start_active[cv()]           ||  ' |', start_active_size[cv()])               end ||
                            case when duration_secs_t_is_not_null[cv()] is not null and '&c_duration_secs_t' is not null then
                            lpad(duration_secs_t[cv()]        ||  ' |', duration_secs_t_size[cv()])            end ||
                            case when duration_secs_is_not_null[cv()] is not null and '&c_duration_secs' is not null then
                            lpad(duration_secs[cv()]          ||  ' |', duration_secs_size[cv()])              end ||
                            case when time_active_graph_is_not_null[cv()] is not null and '&c_time_active_graph' is not null then
                            rpad(' ' || time_active_graph[cv()], time_active_graph_size[cv()] - 1)      || '|' end ||
                            case when procs_is_not_null[cv()] is not null and '&c_procs' is not null then
                            rpad(' ' || procs[cv()], procs_size[cv()] - 1)                              || '|' end ||
                            case when procs_graph_is_not_null[cv()] is not null and '&c_procs_graph' is not null then
                            rpad(' ' || procs_graph[cv()], procs_graph_size[cv()] - 1)                  || '|' end ||
                            case when average_as_t_graph_is_not_null[cv()] is not null and '&c_average_as_t_graph' is not null then
                            rpad(' ' || average_as_t_graph[cv()], average_as_t_graph_size[cv()] - 1)    || '|' end ||
                            case when average_as_graph_is_not_null[cv()] is not null and '&c_average_as_graph' is not null then
                            rpad(' ' || average_as_graph[cv()], average_as_graph_size[cv()] - 1)        || '|' end ||
                            case when median_as_graph_is_not_null[cv()] is not null and '&c_median_as_graph' is not null then
                            rpad(' ' || median_as_graph[cv()], median_as_graph_size[cv()] - 1)          || '|' end ||
                            case when activity_graph_is_not_null[cv()] is not null and '&c_activity_graph' is not null then
                            rpad(' ' || substr(activity_graph[cv()], 2), activity_graph_size[cv()] - 1) || '|' end ||
                            case when activity_is_not_null[cv()] is not null and '&c_activity' is not null then
                            rpad(' ' || activity[cv()], activity_size[cv()] - 1)                        || '|' end
                       end
          /* Putting it all together */
        , plan_table_output[r] = case
                                 when inject[cv()] like '---%'
                                 then inject[cv()] || plan_table_output[cv()] || inject2[cv()] || inject3[cv()]
                                 when inject[cv()] is present
                                 then regexp_replace(plan_table_output[cv()], '\|', inject[cv()], 1, 2) || inject2[cv()] || inject3[cv()]
                                 else plan_table_output[cv()]
                                 end
        )
order by
        r
;

set heading on pagesize 49999 feedback off

-- If you need to debug, comment the following line
set termout off

/* Determine which columns to show in the output following */

column show_line_active        new_value _SHOW_LINE_ACTIVE        &debug_internalp.print
column show_procs              new_value _SHOW_PROCS              &debug_internalp.print
column show_procs_graph        new_value _SHOW_PROCS_GRAPH        &debug_internalp.print
column show_average_as_graph   new_value _SHOW_AVERAGE_AS_GRAPH   &debug_internalp.print
column show_average_as_t_graph new_value _SHOW_AVERAGE_AS_T_GRAPH &debug_internalp.print
column show_median_as_graph    new_value _SHOW_MEDIAN_AS_GRAPH    &debug_internalp.print
column show_activity           new_value _SHOW_ACTIVITY           &debug_internalp.print
column show_activity_graph     new_value _SHOW_ACTIVITY_GRAPH     &debug_internalp.print
column show_start_active       new_value _SHOW_START_ACTIVE       &debug_internalp.print
column show_duration_secs      new_value _SHOW_DURATION_SECS      &debug_internalp.print
column show_duration_secs_t    new_value _SHOW_DURATION_SECS_T    &debug_internalp.print
column show_time_active_graph  new_value _SHOW_TIME_ACTIVE_GRAPH  &debug_internalp.print
column show_execs              new_value _SHOW_EXECS              &debug_internalp.print
column show_a_rows_m           new_value _SHOW_A_ROWS_M           &debug_internalp.print
column show_pga                new_value _SHOW_PGA                &debug_internalp.print
column show_temp               new_value _SHOW_TEMP               &debug_internalp.print
column show_io_read            new_value _SHOW_IO_READ            &debug_internalp.print
column show_io_write           new_value _SHOW_IO_WRITE           &debug_internalp.print
column show_io_read_req        new_value _SHOW_IO_READ_REQ        &debug_internalp.print
column show_io_write_req       new_value _SHOW_IO_WRITE_REQ       &debug_internalp.print
column show_co                 new_value _SHOW_CO                 &debug_internalp.print
column pgs_size                new_value pgs_size                 &debug_internalp.print
column aas_size                new_value aas_size                 &debug_internalp.print
column wgs_size                new_value wgs_size                 &debug_internalp.print
column tgs_size                new_value tgs_size                 &debug_internalp.print

select
        case when '&c_act' is not null and instr('&op', 'ASH') > 0 then '' else 'no' end                    as show_line_active
      , case when '&c_procs' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end              as show_procs
      , case when '&c_procs_graph' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end        as show_procs_graph
      , to_char(&pgs + 8, 'TM') as pgs_size
      , case when '&c_average_as_graph' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end   as show_average_as_graph
      , case when '&c_average_as_t_graph' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end as show_average_as_t_graph
      , case when '&c_median_as_graph' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end    as show_median_as_graph
      , to_char(&aas + 8, 'TM') as aas_size
      , case when '&c_activity' is not null and instr('&op', 'ASH') > 0 then '' else 'no' end               as show_activity
      , case when '&c_activity_graph' is not null and instr('&op', 'ASH') > 0 then '' else 'no' end         as show_activity_graph
      , to_char(&wgs + 8, 'TM') as wgs_size
      , case when '&c_start_active' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end      as show_start_active
      , case when '&c_duration_secs' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end     as show_duration_secs
      , case when '&c_duration_secs_t' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end   as show_duration_secs_t
      , case when '&c_time_active_graph' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end as show_time_active_graph
      , to_char(&tgs + 8, 'TM') as tgs_size
      , case when '&c_execs' is not null and '&use_monitor' is null then '' else 'no' end              as show_execs
      , case when '&c_a_rows_m' is not null and '&use_monitor' is null then '' else 'no' end           as show_a_rows_m
      , case when '&c_pga' is not null and '&use_monitor' is null then '' else 'no' end                as show_pga
      , case when '&c_temp' is not null and '&use_monitor' is null then '' else 'no' end               as show_temp
      , case when '&c_io_read' is not null and '&use_monitor' is null then '' else 'no' end            as show_io_read
      , case when '&c_io_write' is not null and '&use_monitor' is null then '' else 'no' end           as show_io_write
      , case when '&c_co' is not null and '&use_monitor' is null then '' else 'no' end                 as show_co
      , case when '&c_io_read_req' is not null and '&use_monitor' is null then '' else 'no' end        as show_io_read_req
      , case when '&c_io_write_req' is not null and '&use_monitor' is null then '' else 'no' end       as show_io_write_req
from
        dual
;

column show_line_active        clear
column show_procs              clear
column show_procs_graph        clear
column show_average_as_graph   clear
column show_average_as_t_graph clear
column show_median_as_graph    clear
column show_activity           clear
column show_activity_graph     clear
column show_start_active       clear
column show_duration_secs      clear
column show_duration_secs_t    clear
column show_time_active_graph  clear
column pgs_size                clear
column aas_size                clear
column wgs_size                clear
column tgs_size                clear
column show_execs              clear
column show_a_rows_m           clear
column show_pga                clear
column show_temp               clear
column show_io_read            clear
column show_io_write           clear
column show_co                 clear
column show_io_read_req        clear
column show_io_write_req       clear

set termout on

column plan_operation     format a35
column line_active        format a5         heading "Act"                             &_SHOW_LINE_ACTIVE.print
column execs              format a8         heading "Execs"                           &_SHOW_EXECS.print
column a_rows_m           format a8         heading "A-Rows"                          &_SHOW_A_ROWS_M.print
column pga                format a8         heading "PGA"                             &_SHOW_PGA.print
column temp               format a8         heading "Temp"                            &_SHOW_TEMP.print
column io_read            format a8         heading "Reads"                           &_SHOW_IO_READ.print
column io_write           format a8         heading "Writes"                          &_SHOW_IO_WRITE.print
column co_percent         format a7         heading "CellO%"                          &_SHOW_CO.print
column io_read_req        format a9         heading "ReadReq"                         &_SHOW_IO_READ_REQ.print
column io_write_req       format a9         heading "WriteReq"                        &_SHOW_IO_WRITE_REQ.print
column procs              format a90        heading "Parallel Distribution ASH"       &_SHOW_PROCS.print
column procs_graph        format a&pgs_size heading "Parallel Execution Skew ASH"     &_SHOW_PROCS_GRAPH.print
column average_as_graph   format a&aas_size heading "Avg Act Sess Graph (A) ASH"      &_SHOW_AVERAGE_AS_GRAPH.print
column average_as_t_graph format a&aas_size heading "Avg Act Sess Graph (T) ASH"      &_SHOW_AVERAGE_AS_T_GRAPH.print
column median_as_graph    format a&aas_size heading "Med Act Sess Graph ASH"          &_SHOW_MEDIAN_AS_GRAPH.print
column activity           format a90        heading "Top &topnw Activity ASH"         &_SHOW_ACTIVITY.print
column activity_graph     format a&wgs_size heading "Activity Graph ASH"              &_SHOW_ACTIVITY_GRAPH.print
column start_active       format a15        heading "Start"                           &_SHOW_START_ACTIVE.print
column duration_secs      format a15        heading "Dur (Active)"                    &_SHOW_DURATION_SECS.print
column duration_secs_t    format a15        heading "Dur (Total)"                     &_SHOW_DURATION_SECS_T.print
column time_active_graph  format a&tgs_size heading "Time Active Graph"               &_SHOW_TIME_ACTIVE_GRAPH.print

undefine pgs_size
undefine aas_size
undefine wgs_size
undefine tgs_size

/* If no plan could be found, provide mininum information based on ASH about plan line activity */

/* Get the previously saved buffer contents */

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp nolist

set termout on

i
/* Info about the plan operation from ASH */
plan_operations as
(
  select
          distinct
          sql_plan_line_id    as plan_line
        , sql_plan_hash_value as plan_hash_value
        , plan_operation
  from
          ash_base
  where
          '&_IF_ORA11_OR_HIGHER' is null
  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
)
select  /* XPLAN_ASH ACTIVITY_PLAN_LINE SQL_ID: &si */
        o.plan_hash_value
      , o.plan_line
      , o.plan_operation
      , case when l.plan_line is not null then '&active_ind' end as line_active
      , lpad(cast(m.execs_format as varchar2(10)), 7)            as execs
      , lpad(cast(m.a_rows_format as varchar2(10)), 7)           as a_rows_m
      , lpad(cast(m.pga_format as varchar2(10)), 7)              as pga
      , lpad(cast(m.temp_format as varchar2(10)), 7)             as temp
      , lpad(cast(m.io_read_format as varchar2(10)), 7)          as io_read
      , lpad(cast(m.io_write_format as varchar2(10)), 7)         as io_write
      , lpad(cast(m.co_percent as varchar2(10)), 7)              as co_percent
      , lpad(cast(m.io_read_req_format as varchar2(10)), 8)      as io_read_req
      , lpad(cast(m.io_write_req_format as varchar2(10)), 8)     as io_write_req
      , t.start_active
      , t.duration_secs_t
      , t.duration_secs
      , t.time_active_graph
      , p.procs
      , p.procs_graph
      , p.average_as_t_graph
      , p.average_as_graph
      , p.median_as_graph
      , a.activity_graph
      , a.activity
from
        plan_operations o
      , parallel_procs p
      , ash a
      , plan_line_timelines t
      , active_plan_lines l
      , monitor_info_fmt m
where
        o.plan_line = p.plan_line (+)
and     o.plan_line = a.plan_line (+)
and     o.plan_line = t.plan_line (+)
and     o.plan_line = l.plan_line (+)
and     o.plan_line = m.plan_line_id (+)
and     '&_IF_ORA11_OR_HIGHER' is null
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0  or instr('&op', 'TIMELINE') > 0)
and     ('&plan_exists' is null or coalesce(to_number('&pc'), 0) = 0)
order by
        plan_line
;

column plan_operation clear
column line_active clear
column procs clear
column procs_graph clear
column average_as_t_graph clear
column average_as_graph clear
column median_as_graph clear
column activity clear
column activity_graph clear
column start_active clear
column duration_secs_t clear
column duration_secs clear
column time_active_graph clear
column execs clear
column a_rows_m clear
column pga clear
column temp clear
column io_read clear
column io_write clear
column co_percent clear
column io_read_req clear
column io_write_req clear

-----------------------------------
-- Clean up SQL*Plus environment --
-----------------------------------

undefine _EXPERIMENTAL
undefine duplicator
undefine dist_sample_count
undefine default_fo
undefine default_source
undefine default_operation
undefine default_ash
undefine prev_sql_id
undefine prev_cn
undefine prev_sql_exec_start
undefine prev_sql_exec_id
undefine last_exec_start
undefine last_exec_id
undefine last_exec_second_id
undefine last
undefine child_ad
undefine slave_count
undefine topnp
undefine topnw
undefine topnl
undefine topna
undefine pgs
undefine aas
undefine wgs
undefine si
undefine cn
undefine fo
undefine so
undefine ls
undefine li
undefine op
undefine ah
undefine co
undefine gc
undefine gc2
undefine gc3
undefine 1
undefine 2
undefine 3
undefine 4
undefine 5
undefine 6
undefine 7
undefine 8
undefine 9
undefine 10
undefine sid_sql_id
undefine sid_child_no
undefine sid_sql_exec_start
undefine sid_sql_exec_id
undefine _IF_ORA11_OR_HIGHER
undefine _IF_LOWER_THAN_ORA11
undefine _IF_ORA112_OR_HIGHER
undefine _IF_LOWER_THAN_ORA112
undefine _IF_ORA11202_OR_HIGHER
undefine _IF_LOWER_THAN_ORA11202
undefine _IF_ORA11203_OR_HIGHER
undefine _IF_LOWER_THAN_ORA11203
undefine _IF_ORA12_OR_HIGHER
undefine _IF_LOWER_THAN_ORA12
undefine _IF_ORA11202_OR_HIGHERP
undefine _IF_ORA112_OR_HIGHERP
undefine _IF_ORA11_OR_HIGHERP
undefine _IF_ORA12_OR_HIGHERP
undefine _IF_CROSS_INSTANCE
undefine _IS_CROSS_INSTANCE
undefine _IS_SINGL_INSTANCE
undefine _SQL_EXEC2
undefine plan_table_name
undefine las
undefine active_ind
undefine ic
undefine dm
undefine all_cols
undefine default_cols
undefine curr_global_ash
undefine curr_inst_id
undefine curr_plan_table
undefine curr_plan_table_stats
undefine curr_second_id
undefine curr_second_id_monitor
undefine curr_sample_freq
undefine curr_plan_function
undefine curr_par_fil
undefine curr_third_id
undefine curr_sqltext
undefine curr_sqltext_join
undefine curr_sqltext_join_col
undefine curr_sql_monitor
undefine curr_sql_plan_monitor
undefine hist_global_ash
undefine hist_inst_id
undefine hist_plan_table
undefine hist_plan_table_stats
undefine hist_second_id
undefine hist_second_id_monitor
undefine hist_sample_freq
undefine hist_plan_function
undefine hist_par_fil
undefine hist_third_id
undefine hist_sqltext
undefine hist_sqltext_join
undefine hist_sqltext_join_col
undefine hist_sql_monitor
undefine hist_sql_plan_monitor
undefine mixed_global_ash
undefine mixed_inst_id
undefine mixed_plan_table
undefine mixed_plan_table_stats
undefine mixed_second_id
undefine mixed_second_id_monitor
undefine mixed_sample_freq
undefine mixed_plan_function
undefine mixed_par_fil
undefine mixed_third_id
undefine mixed_sqltext
undefine mixed_sqltext_join
undefine mixed_sqltext_join_col
undefine mixed_sql_monitor
undefine mixed_sql_plan_monitor
undefine sash_global_ash
undefine sash_inst_id
undefine sash_plan_table
undefine sash_plan_table_stats
undefine sash_second_id
undefine sash_second_id_monitor
undefine sash_sample_freq
undefine sash_plan_function
undefine sash_par_fil
undefine sash_third_id
undefine sash_sqltext
undefine sash_sqltext_join
undefine sash_sqltext_join_col
undefine sash_sql_monitor
undefine sash_sql_plan_monitor
undefine _IS_SASH_REPO
undefine SASH_DB_VERSION
undefine global_ash
undefine inst_id
undefine plan_table
undefine plan_table_stats
undefine second_id
undefine second_id_monitor
undefine sample_freq
undefine plan_function
undefine par_fil
undefine third_id
undefine sqltext
undefine sqltext_join
undefine sqltext_join_col
undefine sql_monitor
undefine sql_plan_monitor
undefine third_id_sqltext
undefine c_pid
undefine c_ord
undefine c_act
undefine c_a_time_self
undefine c_lio_self
undefine c_reads_self
undefine c_writes_self
undefine c_a_time_self_graph
undefine c_lio_self_graph
undefine c_reads_self_graph
undefine c_writes_self_graph
undefine c_lio_ratio
undefine c_tcf_graph
undefine c_e_rows_times_start
undefine c_start_active
undefine c_duration_secs
undefine c_duration_secs_t
undefine c_time_active_graph
undefine c_procs
undefine c_procs_graph
undefine c_average_as_graph
undefine c_median_as_graph
undefine c_average_as_t_graph
undefine c_activity_graph
undefine c_activity
undefine c_execs
undefine c_a_rows_m
undefine c_pga
undefine c_temp
undefine c_io_read
undefine c_io_write
undefine c_co
undefine c_io_read_req
undefine c_io_write_req
undefine ds
undefine tgs
undefine avg_as_bkts
undefine rnd_thr
undefine no_ord_on_px
undefine find_min_sample_10g
undefine pc
undefine plan_exists
undefine _SHOW_LINE_ACTIVE
undefine _SHOW_PROCS
undefine _SHOW_PROCS_GRAPH
undefine _SHOW_AVERAGE_AS_GRAPH
undefine _SHOW_MEDIAN_AS_GRAPH
undefine _SHOW_AVERAGE_AS_T_GRAPH
undefine _SHOW_ACTIVITY
undefine _SHOW_ACTIVITY_GRAPH
undefine _SHOW_START_ACTIVE
undefine _SHOW_DURATION_SECS
undefine _SHOW_DURATION_SECS_T
undefine _SHOW_TIME_ACTIVE_GRAPH
undefine _SHOW_EXECS
undefine _SHOW_A_ROWS_M
undefine _SHOW_PGA
undefine _SHOW_TEMP
undefine _SHOW_IO_READ
undefine _SHOW_IO_WRITE
undefine _SHOW_CO
undefine _SHOW_IO_READ_REQ
undefine _SHOW_IO_WRITE_REQ
undefine ash_pred1
undefine ash_pred2
undefine ash_ln_pred1
undefine ash_ln_pred2
undefine ash_min_sample_time
undefine ash_max_sample_time
undefine ash_current_time
undefine ext_rowsource_graphs_maxrel
undefine show_monitor_rowcount
undefine ca_sc
undefine plan_inst_id
undefine ignore_PX_credit_blkd_10g
undefine show_median
undefine topn_sqlid
undefine show_px_sets
undefine use_monitor
undefine use_no_monitor
undefine dm_opt1
undefine dm_opt2
undefine default_sql_exec_id
undefine use_lateral
undefine use_no_lateral
undefine ash_sample_count_threshold
undefine debug_internalp
undefine debug_internalf
undefine is_adaptive_plan

col plan_table_output clear
col last_exec_start clear
col last_exec_id clear
col last_exec_second_id clear
col si clear
col cn clear
col fo clear
col so clear
col op clear
col ah clear
col co clear
col last clear
col li clear
col ls clear
col child_ad clear
col 1 clear
col 2 clear
col 3 clear
col 4 clear
col 5 clear
col 6 clear
col 7 clear
col 8 clear
col 9 clear
col 10 clear
col sid_sql_id         clear
col sid_child_no       clear
col sid_sql_exec_start clear
col sid_sql_exec_id    clear
col ora11_higher  clear
col ora11_lower   clear
col ora112_higher clear
col ora112_lower  clear
col ora11202_higher clear
col ora11202_lower  clear
col ora11203_higher clear
col ora11203_lower  clear
col ora12_higher    clear
col ora12_lower     clear
col global_ash clear
col inst_id clear
col plan_table clear
col plan_table_stats clear
col second_id clear
col second_id_monitor clear
col sample_freq clear
col plan_function clear
col par_fil clear
col sqltext clear
col sqltext_join clear
col sqltext_join_col clear
col sql_monitor clear
col sql_plan_monitor clear
col plan_table_name clear
col inst_count clear
col c_pid clear
col c_ord clear
col c_act clear
col c_a_time_self clear
col c_lio_self clear
col c_reads_self clear
col c_writes_self clear
col c_a_time_self_graph clear
col c_lio_self_graph clear
col c_reads_self_graph clear
col c_writes_self_graph clear
col c_lio_ratio clear
col c_tcf_graph clear
col c_e_rows_times_start clear
col c_start_active clear
col c_duration_secs clear
col c_duration_secs_t clear
col c_time_active_graph clear
col c_procs clear
col c_procs_graph clear
col c_average_as_graph clear
col c_median_as_graph clear
col c_average_as_t_graph clear
col c_activity_graph clear
col c_activity clear
col c_execs clear
col c_a_rows_m clear
col c_pga clear
col c_temp clear
col c_io_read clear
col c_io_write clear
col c_co clear
col c_io_read_req clear
col c_io_write_req clear
col plan_table_count clear
col plan_exists clear

-- Disable LATERAL views
begin
  execute immediate 'alter session set events ''22829 trace name context off''';
exception
when others then
  null;
end;
/

-- Restore previous SQL*Plus environment
@.xplan_settings