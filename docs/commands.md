DBCLI Command Overview
============================

|Module|Category|Command|Description|
|------|--------|-------|-----------|
| **Public Commands**:<br/>visible in all database platforms |_Instruction_|`help`|Show help information,Use `"help <command>"` to show the detail information of other commands, or `"help help"` to see more usage of the `help` command. <br/>The default database platform is `Oracle`, to switch to other platform, use the `"set [-p] platform"` command
|||`ansi`|Show the usage of console color solution
|||`hotkeys`|Show the available hotkeys in console|
| |_Database_|`connect/conn`|Connect to database, Usage: `"conn user/password@connection-string"`<br/>The connection string can be either the name that pre-defined in `data\jdbc_url.cfg`, or follow the JDBC thin URL format, and for different database platform, the URL format can be different, normally in `host:port/database-or-else` format. But for `Oracle` database, it also supports `TNS-NAME` and `EZConnect`. Type `help connect` for more information
|||`login/logon`|A command set, view or logon to a connection history, when a connection is successfully established, the logon info would be automatially stored in `data\password.dat`, so that user doesn't have to manually input the a/c for each time
|||`disconnect/disc`|Disconnect the current connection|
|||`Commit`| Commit DML changes, only available when autocommit mode is `on`
|||`Rollback`| Rollback DML changes, only available when autocommit mode is `on`
||_Core_|`set`|A command set, show or change all kinds of preferences of console enviroment or other commands. The changed settings can be either permanent or temporary.
|||`alias`|A command set, similar to the Unix `alias` command, mainly used to define the shortcut of other command line, the definition is automatially stored in folder `aliases` for permanent reused|
|||`history/his`|Check or run historical commands, and the historial commands are only kept in memory and available within the current window
|||`r` or `/`|Rerun previous command
|||`sleep`|Sleep for specific seconds, mainly used in script file
|||`repeat/itv`|Periodically run other commands
|||`host` or `!`|Run OS command
|||`reload`|Close all connections and reload the console environment, everything will be reset.
|||`exit`|Close all connections and close the console
||_Screen_|`clear/cls`|Clear screen
|||`spool/spo`|Sync screen output to file, the command name can be different regarding to different db platforms
|||`column/col`|Control the layout format of grid(i.e. query) field
|||`grep`|Similar to the Unix `grep` command but only supports piping from other command
|||`more`|Similar to the Unix `more` command but only supports piping from other command
|||`tee`|Similar to the Unix `tee` command but only supports piping from other command, also can export the screen output into `csv` or `html` format regarding to the file extension, the command name can be different regarding to different db platforms
|||`prompt/pro/echo`|Print text, if the text contains variables, then also convert as the the vairable values, the command name can be different regarding to different db platforms
||_Scripting_||A command set, run customized script file which includes a batch of commands that supported in DBCLI, supports the features of variables, options and pre-compiled conditions. The engine maps the input parameters as `V1 - V20` variables except the parameter in `-<option>` format. This is the interface for some other commands to implement or extend, such as `snap`/`shell`/`ora`/`sys`/`chart`/`sql`/etc, different command owns different folder to store the script files, and those file names are regconized as the sub-command names.
|||`snap`|A command set,used in following scenario: `[capture db pre-stats] => [run other commands / sleep for seconds] => [capture db post-stats] => [generate db delta-stats]`
||_Graphing_|`chart/ch`|A command set, run customized script to generate graph chart from SQL statement
|||`graph/gr`|Generate graph chart from input parameter which is a SQL text or a CSV file
||_Variable_|`define/def`|Define variable with initial value, can be used in either SQL bindings or text substitution in command or script file
|||`variable/var`|Define variable and its data type without value assignment, can be used as the output binding parameter of the SQL statement, mainly used in customized script file
|||`accept/acc`|Assign user-input or file to a new variable
|||`save`|Save a specific variable value into target file
|||`print/pri`|Print target variable 
||_Unloading_|`sql2file`|Generate the result of a query or cursor into SQL file, supports auto-compression regarding to the target file extension
|||`sql2csv`|Generate the result of a query or cursor into CSV file and `sqlldr` control file, supports auto-compression regarding to the target file extension
|||`csv2sql`|Convert CSV file into SQL file and `sqlldr` control file, supports auto-compression regarding to the target file extension
||_Shell_|`ssh`|A command set to communicate between client and SSH server
|||`shell`|A command set, run in remote SSH sever with local shell/python/perl script(to be enhanced), this command is inherited from the scripting modules
||_Internal_|`event`|Show event bindings of the console code
|||`luajit`|Switch into thea `LuaJIT` console
|||`ilua`|Enter into Lua console, can access environment objects
|||`search`|Search the source code
|||`-p`|Test a command and verify its input parameters
|||`help -a` or `set -a`| see where the command/setting is defined
|=========|=========|=========|======================================================|
|**Oracle**|_SQL_|`*`|Supports almost all Oracle database SQL statements
||_Report_|`awrdump`|Generate AWR report regarding to the input time range or snap_id
|||`awrdiff`|Generate AWR diff report regarding to the input time range or snap_id
|||`addmdump`|Generate ADDM report regarding to the input time range or snap_id
|||`ashdump`|Generate ASH report regarding to the input time range or snap_id
||_Extraction_|`loadtrace/dumptrace`|Download the self/alert/other trace file from db server,requires the `create/drop any directory` access rights if unable to access the target OS path with existing Oracle directories
|||`sqlprof`|Generate SQL profile script from sqlarea/awr/spm/profile/plan_table/etc
|||`unwrap`|Extract PL/SQL code or view from database into local file, if the code is encrypted, then auto-decrypt it 
||_Scripting_|`ora`|A command set that implement the scripting engine, to run predefined or customized script that used for DBA or db developer, this command has pre-defined many useful scripts
|||`sys`|A command set that inherited from `ora` and similar to `ora`, except can only used by SYSDBA
|||`show`|A command set that inherited from `ora` and similar to `ora`, except that it doesn't accept input parameters
||_SQL*Plus_|`sqlplus`|Launch `sqlplus` console with the same login in native mode or embbed mode,  plus other input parameters
|||`@` or `sp`|Run sqlplus script in embbed mode with the same login
||_Settings_|`set instance`|Auto-limit the instance regarding to any SQL that references the `gv$/x$/dba_hist` views
|||`set container`|Auto-limit the container ID regarding to any SQL that references the views that have the `con_id` field
|||`set starttime`|Auto-limit the default begin time of the predefined SQLs that specify the time range predicate
|||`set endtime`|Auto-limit the default end time of the predefined SQLs that specify the time range predicate
||_Others_|`describe/desc`|Describe Oracle object, provides more features than that of `sqlplus`
|||`xplan`|Show execution plan for input `SQL text/ID`, as well as downloading the 10053 trace file if specify the `-10053` option
|=========|=========|=========|======================================================|
|**db2**<br/>(to be enhanced)|_SQL_|`*`|Supports almost all DB2 database SQL statements, be noted that all SQL commands should be ended with `;`, or `/` in a new line
||_Scripting_|`sql`|Inherited from the scripting engine, to run scripts which contains a batches of all available commands
||_Admin_|`ADM`|Run db2 `ADMIN_CMD` commands
|=========|=========|=========|======================================================|
|**MySQL**<br/>(to be enhanced)|_SQL_|`*`|Supports almost all MySQL database SQL statements
||_Console_|`mysql`|Switch to `mysql.exe` with same login plus other input parameters
|||`mysqluc`|Switch to `mysqluc.exe` with same login plus other input parameters
|||`source` or `\.` or `ms`|Switch to `mysql.exe` with same login to execute the target script
||_Scripting_|`sql`|Inherited from the scripting engine, to run scripts which contains a batches of all available commands
||_Others_|`show`| A bit different from the native `show`, provides more features such as fuzzy search.
|||`?` or `\?`| A bit different from the native `\?`, provides more features
|||`N/A`| Some commands are similar to the native `mysql` console
|=========|=========|=========|======================================================|
|**PostgreSQL**<br/>(to be enhanced)|_SQL_|`*`|Supports almost all PostgreSQL database SQL statements
||_Console_|`psql`|Switch to `psql.exe` with same login plus other input parameters
|||`file` or `-f`|Switch to `psql.exe` with same login and execute the target script
||_Scripting_|`sql`|Inherited from the scripting engine, to run scripts which contains a batches of all available command
||_Others_|`N/A`| Some commands are similar to the native `psql` console