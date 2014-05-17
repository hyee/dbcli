Licence
============
###MIT licence

Description
=============

    dbcli is a database command line utility that developed with lua language, and bridge JDBC in order to operate database. 
    It is designed to be cross-platforms and support multiple databases, and contains 2 type of modules, one is the public functions, and another is the database-specific functions.
    Currently only public and Oracle functions are developed, and only support windows platform.

    For Oracle db, it does not aim to support all functions for SQL*Plus, but to provide the features other than SQL*Plus:
    1) Pretty print of the select statement and the flexibility of controlling the grid layout(see set command)
    2) The 'alias' command to reduce your frequent inputs
    3) The powerful "snap" and "ora" command as the replacement of the complex SQL*Plus script, so that DBA is able to quick define and execute the SQL templates with the smallest input
    4) Functions are easy to extend or deploy, because they are all developed with lua language



Installation
============
    Before running dbcli, make sure that you have installed JRE 1.6+ in your local PC.
    Open dbcli.bat with text editor, then modify the JRE_HOME and ORACLE_HOME as your PC's situation, then run it directly.
    It also support command line options with "<command>=<args>" format, all available options can be found in "help" command:


    Command   Abbr.  Args Decription
    --------- ------ ---- -------------------------------------------------------------------------------
    ALIAS               2 Set an shortcut of other existing commands. Usage: alias [-r | <name> [paramete
    CONNECT   CONN      1 Connect to Oracle database.
    DEFINE    DEF       1 Define input variables, Usage: def <name>=<value>, or def <name> to remove defi
    DESCRIBE  DESC      2 Describe datbase object. Usage desc [<owner>.]<object>[.<partition>]
    HELP                8 Type 'help' to see the available comand list. Usage: help [<command>[,<sub_comm
    HISTORY   HIS       1 Show/run historical commands. Usage: his [index]
    HOST                1 Run OS command. Usage: HOST <command>
    INTERVAL  ITV       1 Run a command with specific interval. Usage: ITV <seconds> <times> <command>;
    LOGIN               2 Login with saved accounts. Usage: login [<account_name>]
    ORA                19 Run SQL script under the "ora" directory. Usage: ora [<script_name>|-r|-p|-h|-s
    PLAN                1 Explain SQL excution plan. Usage: plan <DML statement>
    PROMPT    PRO       1 Prompt messages. Usage: PRO[MPT] <message>
    R         /         1 Rerun the previous command.
    RECONNECT RECONN    1 Re-connect current database
    RELOAD              0 Reload environment, including variables, modules, etc
    SET                98 Set environment parameters. Usage: set <name1> [<value1|DEFAULT|BACK> [name2 ..
    SLEEP               1 Usage: sleep <seconds>
    SNAP                8 Run SQL script under the "snap" directory. Usage: snap <interval> <name1[,name2
    SPOOL     SPO       2 Stores query results in a file. Usage: SPO[OL] [file_name[.ext]] [CRE[ATE]] | A
    SQL                 8 Run SQL script under the "sqlplus" directory with SQL*Plus. Usage: sql <script_
    SQLPLUS             8 Switch to sqlplus with same login, the working folder is 'oracle/sqlplus'. Usag
    TESTER              1 Invoke unit test on existing modules
    VARIABLE  VAR       2 Define output variables for db execution. Usage: "var <name> <data type>", or "
    
    
    For example: dbcli.bat "connect=tigger/scott@orcl"
    
    Besides the above commands, all database statements are also supported(i.e select/update/delete)


References
============
    The project depends on some open-source projects without modifications, below list some of them:
    luajit v2.1         : http://luajit.org/
    jnlua               : https://code.google.com/p/jnlua/
    lpeg                : http://www.inf.puc-rio.br/~roberto/lpeg/
    MessagePack         : https://github.com/fperrad/lua-MessagePack(pure lua)




