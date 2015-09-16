
dbcli : a CLI utility for DBA (Oracle/DB2)
=====================================================

[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](COPYRIGHT)

Description
-----------------------

DBCLI is a database command line utility that developed with LUA language, and bridges to JDBC in order to operate database.<br> 
It is designed to support multiple databases, and includes 2 type of modules, one is the public functions, and another one is the database-specific functions.<br>
Currently only public and Oracle and DB2 functions are developed, and only support windows platform.<br><br>

For Oracle db, it does not aim to support all functions of SQL*Plus, but to provide the features other than SQL*Plus:<br>
* Pretty print of the select statement and the flexible control of the grid layouts(see set command)
* The `alias` command to reduce the frequent inputs
* The powerful `snap` and `ora` commands as the replacement of the SQL*Plus script, so that DBA is able to quickly define and execute the SQL templates with the smallest input
* Functions are easy to extend or deploy, because they are all developed with lua language


Build and Configuration
-----------------------
DBCLI does not require compile before its use, but depends on JRE 1.7+. Directly click `Download ZIP` and extract.<br/> 
Branch `with-JRE` contains the shrinking JRE bundle, if you don't have JRE installed, you may switch to that branch to download. Due to the region and charset differences, this JRE bundle is not guaranteed to work well.<br/>
###Configure terminal window
To avoid the word wrap in the terminal window which affects the print layout, following settings are recommended in Windows command window:<br>
* In the `Layout` tab, set buffer width and buffer height as `500+`
* In the `Font` tab, use Roster font with the size is `6 * 12`

###Configure enviroment
Before running dbcli, make sure that you have installed JRE 1.7+ in your local PC.<br>
Create file `init.cfg` under the "data" directory with following content:
   
    SET JRE_HOME=<JRE HOME>
    SET TNS_ADM=<location of tnsnames.ora>
    
Of which `TNS_ADM` is optional unless you need to connect Oracle via tnsnames.ora, or may also refer to `init_sample.cfg` for more settings. An example is:
   
    SET JRE_HOME=d:\soft\java
    SET TNS_ADM=d:\Soft\InstanceClient\network\admin
    
It also support command line options with `"<command>=<args>"` format, all available options can be found by typing `help`:<br>

[drag]:https://raw.githubusercontent.com/hyee/dbcli/master/help.gif
![][drag]

For example: `dbcli.bat "connect=tiger/scott@orcl"`<br><br>

Besides the above commands, all database statements are also supported(i.e select/update/delete)<br><br>

Quick Start
-----------------------
After the above configurations, you are able to successfully start the dbcli shell by executing `dbcli.bat` or `bin\ConsoleZ\Console.exe`.<br>
Below are some common use of the utility:<br>

    1. "conn" or "connect" to connect to the database with or without installing Oracle client, and "reconn"  to re-connect.
    2. "login" command to connect to the db without password via the account that has been connected before. 
    3. Execute SQL statements which should match the database syntax, similar to SQL*Plus.
    4. "ora" command to execute pre-defined scripts under the "ora" sub-directory. i.e., ora ashtop, ora actives
    5. "alias" command which is similar to the Linux command
    6. "set" command to config the shell enviroment
    7. 'q' or CTRL + D or CTRL + C to abort running SQL
    8. "help" or "help -a" to see other available commands.

References
-----------------------
The project depends on some binary files of open-source projects without modifications, the binaries have been included into this project.
Below is the list:<br>

    luajit v2.1 : (MIT)  http://luajit.org/
    jnlua       : (MIT)  https://code.google.com/p/jnlua/
    JLine2      : (BSD)  https://github.com/jline/jline2
    ConsoleZ    : (GNU)  https://github.com/cbucher/console
    MessagePack : (MIT)  https://github.com/fperrad/lua-MessagePack (pure lua)
    OpenCSV     : (MIT)  https://github.com/hyee/OpenCSV
    dygraphs    : (MIT)  https://github.com/danvk/dygraphs
    JSch        : (BSD)  http://www.jcraft.com/jsch/
    ANSICON     : (ZLIB) https://github.com/adoxa/ansicon
    PSCP        : http://www.putty.org/
    json4lua    : https://github.com/craigmj/json4lua
    

Besides, some SQL scripts are from internet.

About ANSICON
-----------------------
ANSICON provides more ANSI escape features than JLine, especially when running bash commands(i.e.: top) via SSH.<br/>
If you have concern on ANSICON, please remove it from bin, and edit `data\init.cfg` to add line `set ANSICON_CMD=`