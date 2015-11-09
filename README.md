
DBCLI : A CLI utility for DBA (Oracle/DB2)
=====================================================

[![Join the chat at https://gitter.im/hyee/dbcli](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/hyee/dbcli?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](https://en.wikipedia.org/wiki/MIT_License)
[drag]:help.gif
![][drag]


Description
-----------------------

DBCLI is a portable database command line utility, for DBA or application support to easily manage and run their common used scripts, similar to database built-in CLI tools but is more flexible.  

It is developed in Lua language, and bridges to JDBC in order to operate database. <br/> 
It is designed to support multiple databases, and includes 2 types of modules, one is the public module whose functions are visible across all database platforms, 
and another one is the platform-specific module.<br>
Currently only public and Oracle and DB2 functions are developed, and only support windows platform.

It is not aim to support all features of the existing CLI utilities that embedded by the specific database(`Oracle SQL*Plus`, `DB2 CLP`, etc), but to provide the features other than those tools:<br>
* Pretty-print of the select statement and the flexible control of the grid layouts(see set command)
* Automatically generate help documents for customized SQL/shell/etc scripts.
* The `alias` command to reduce the frequent inputs
* The powerful `snap` and `ora` commands as the replacement of the standard CLI scripts, so that DBA is able to quickly define and execute the SQL templates with the smallest input
* Support SSH operations
* Provide the graph charts of the database performance
* Easy to extend, modify or deploy, because most of the source code is not required to compile


Build and Configuration
-----------------------
DBCLI does not require compile or installation, but depends on JRE 1.7+. Click `Download ZIP`, extract and use.<br/> 
Branch `With-JRE` contains the shrinking JRE bundle, if you don't have JRE installed, you may switch to that branch to download. Due to the region and charset differences, this JRE bundle is not guaranteed to work well.<br/>
###Configure terminal window
To avoid the word wrap in the terminal window which affects the print layout, following settings are recommended in Windows command window:<br>
* In the `Layout` tab, set buffer width and buffer height as `500+`
* In the `Font` tab, change the font size as smaller value.

###Configure environment
Before running dbcli, make sure that you have installed JRE 1.7+ in your local PC. If you are using the version of "With-JRE" branch, this step can be skipped.

Create file `init.cfg` under the "data" directory with following content:
   
    SET JRE_HOME=<JRE HOME>
    SET TNS_ADM=<location of tnsnames.ora>
    
Of which `TNS_ADM` is optional unless you need to connect Oracle via tnsnames.ora, or may also refer to `init_sample.cfg` for more settings. An example is:
   
    SET JRE_HOME=d:\soft\java
    SET TNS_ADM=d:\Soft\InstanceClient\network\admin

###Launch DBCLI Console
After the above configurations, you are able to start DBCLI by executing `dbcli.bat` or `bin\ConsoleZ\Console.exe`.

`dbcli.bat` also supports arguments in `"<command>=<args>"` format, all available commands can be found by typing `help` or `help -a`.

For example: `dbcli.bat "connect=tiger/scott@orcl"`<br><br>

###Switch Database Platform
DBCLI supports multiple database platforms(Oracle,db2,etc), default is `Oracle`.<br>
To permanently change the preferred platform other than `Oracle`, run `set -p <platform>` after launching the console. 
For example, `set -p database db2`<br>
Without the `-p` option, the change only takes affect on current console window. 
Type `set database` to see all available options.

Quick Start
-----------------------
Below are some common use of the utility:<br>

    1. "conn" or "connect" to connect to the database with or without installing Oracle client, and "reconn"  to re-connect.
    2. "login" command to connect to the db without password via the account that has been connected before. 
    3. Execute SQL statements which should match the database syntax, similar to SQL*Plus.
    4. "ora","show","sys" commands to execute pre-defined scripts. i.e., ora ashtop, ora actives  
    5. "alias" command which is similar to the Linux command
    6. "set" command to configure the shell environment
    7. 'q' or CTRL + D or CTRL + C to abort running command
    8. "help" or "help -a" to see other available commands.

Command Types
-----------------------
The command rules is similar to SQL*Plus:
* DDL commands that related to source code(`create trigger/package/function/procedure/type`) are cross-line commands and should be end with `/` in a stand-alone line.
* Other DML,DDL,DCL commands are also cross-line commands that end with `;`, or end with `/` in a stand-alone line.
* Apart from the above commands, most of other commands are single line commands and will be executed after the `enter` key is pressed.

Type `help -a` and refer to the `Multi-lines` field for the type of each command. 

References
-----------------------
The project depends on some binary files of open-source projects, the binaries have been included into this project.
Below is the list:<br>
<pre>
JLine2      : (BSD)  https://github.com/jline/jline2
luajit v2.1 : (MIT)  http://luajit.org/
jnlua       : (MIT)  https://github.com/hyee/JNLuaJIT(based on http://jnlua.googlecode.com/)
OpenCSV     : (MIT)  https://github.com/hyee/OpenCSV(based on opencsv.sourceforge.net)
ConsoleZ    : (GNU)  https://github.com/cbucher/console
MessagePack : (MIT)  https://github.com/fperrad/lua-MessagePack (pure lua)
dygraphs    : (MIT)  https://github.com/danvk/dygraphs
JSch        : (BSD)  http://www.jcraft.com/jsch/
ANSICON     : (ZLIB) https://github.com/adoxa/ansicon
PSCP        : (MIT)  http://www.putty.org/
</pre>  

Besides, some SQL scripts are from internet.

About ANSICON
-----------------------
`ANSICON` provides more ANSI escape features than JLine, especially when running bash commands(i.e.: top) via SSH.

If you have concern on `ANSICON`, please remove it from bin, and edit `data\init.cfg` to add line `set ANSICON_CMD=`

About Contribution
-----------------------
Any contribution would be very welcome, I'm only familiar with Oracle database.