Licence
============
MIT licence

Description
=============

dbcli is a database command line utility that developed with lua language, and bridge JDBC in order to operate database.<br> 
It is designed to be cross-platforms and support multiple databases, and contains 2 type of modules, one is the public functions, and another is the database-specific functions.<br>
Currently only public and Oracle functions are developed, and only support windows platform.<br><br>

For Oracle db, it does not aim to support all functions for SQL*Plus, but to provide the features other than SQL*Plus:<br>
1) Pretty print of the select statement and the flexibility of controlling the grid layout(see set command)<br>
2) The 'alias' command to reduce your frequent inputs<br>
3) The powerful "snap" and "ora" command as the replacement of the complex SQL*Plus script, so that DBA is able to quick define and execute the SQL templates with the smallest input<br>
4) Functions are easy to extend or deploy, because they are all developed with lua language<br>



Installation
============
Before running dbcli, make sure that you have installed JRE 1.6+ in your local PC.<br>
Open dbcli.bat with text editor, then modify the JRE_HOME and ORACLE_HOME as your PC's situation, then run it directly.<br>
It also support command line options with "<command>=<args>" format, all available options can be found in "help" command:<br>


        Name         Value   Default Class    Available Values         Description
        ------------ ------- ------- -------- ------------------------ -----------------------------------------
        HISSIZE      50      50      core     0 - 999                  Max size of historical commands
        PROFILER     "off"   "off"   core     on,off                   Enable jit profiler to monitor the perfor
        PROMPT       "PODPM" "SQL"   core     *                        Define interpreter's command prompt, a sp
        TRACE        "off"   "off"   core     on,off                   Enable trace to monitor the performance.
        AUTOCOMMIT   "off"   "off"   db.core  on,off                   Detemine if auto-commit every db executio
        FEED         "on"    "on"    db.core  on,off                   Detemine if need to print the feedback af
        SAVELOGIN    "on"    "off"   db.core  on,off                   Determine if autosave logins.
        SQLTIMEOUT   600     600     db.core  10-86400                 The max wait time(in second) for a single
        COLSIZE      32767   32767   db.query 5-1073741824             Max column size of a result set
        PRINTSIZE    300     300     db.query 1-3000                   Max rows to be printed for a select state
        COLAUTOSIZE  "auto"  "auto"  grid     head,body,auto           Define the base of calculating column wid
        COLDEL       " "     " "     grid     *                        The delimiter to split the fields when pr
        COLWRAP      0       0       grid     0 - 32767                If the column size is larger than COLDEL,
        DIGITS       21      21      grid     0 - 21                   Define the digits for a number
        HEADDEL      "-"     "-"     grid     *                        The delimiter to devide header and body w
        HEADSTYLE    "none"  "none"  grid     upper,lower,initcap,none Display style of the grid title
        LINESIZE     990     32767   grid     10-32767                 Define the max chars in one line, other o
        MAXCOLS      1024    1024    grid     4-1024                   Define the max columns to be displayed in
        PIVOT        0       0       grid     -30 - +30                Pivot a grid when next print, afterward t
        PIVOTSORT    "on"    "on"    grid     on,off                   To indicate if to sort the titles when pi
        ROWDEL       ""      ""      grid     *                        The delimiter to split the rows when prin
        ROWNUM       "off"   "off"   grid     on,off                   To indicate if need to show the row numbe
        SERVEROUTPUT "on"    "on"    oracle   on,off                   Print Oracle dbms_output after each execu
        SNAPROWS     "50"    "50"    oracle    10 - 3000               Number of max records for the 'snap' comm


For example: dbcli.bat "connect=tigger/scott@orcl"<br><br>

Besides the above commands, all database statements are also supported(i.e select/update/delete)<br><br>


References
============
The project depends on some open-source projects without modifications, below list some of them:<br>
luajit v2.1 : http://luajit.org/<br>
jnlua       : https://code.google.com/p/jnlua/<br>
lpeg        : http://www.inf.puc-rio.br/~roberto/lpeg/<br>
MessagePack : https://github.com/fperrad/lua-MessagePack(pure lua)<br>




