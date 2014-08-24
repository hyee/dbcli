Licence
============
MIT licence

Description
=============

dbcli is a database command line utility that developed with lua language, and bridge JDBC in order to operate database.<br> 
It is designed to support multiple databases, it includes 2 type of modules, one is the public functions, and another one is the database-specific functions.<br>
Currently only public and Oracle functions are developed, and only support windows platform.<br><br>

For Oracle db, it does not aim to support all functions of SQL*Plus, but to provide the features other than SQL*Plus:<br>
1) Pretty print of the select statement and the flexible controll of the grid layouts(see set command)<br>
2) The 'alias' command to reduce the frequent inputs<br>
3) The powerful "snap" and "ora" commands as the replacement of the SQL*Plus script, so that DBA is able to quick define and execute the SQL templates with the smallest input<br>
4) Functions are easy to extend or deploy, because they are all developed with lua language<br>



Configuration
============
###Configure terminal window
To avoid the word wrap in the terminal window which affects the print layout, following settings are recommended in Windows command window:<br>
1. In the "Layout" tab, set buffer width and buffer height as 500+<br>
2. In the "Font" tab, use Roster font with the size is 6 X 12<br>

###Configure enviroment
Before running dbcli, make sure that you have installed JRE 1.6+ in your local PC.<br>
Open dbcli.bat with text editor, modify the "JRE_HOME" and "ORACLE_HOME" variables as your PC's situation, then click the bat to run.<br>
It also support command line options with "<command>=<args>" format, all available options can be found by typing "help":<br>

[drag]:https://raw.githubusercontent.com/hyee/dbcli/master/help.png
![][drag]

For example: dbcli.bat "connect=tiger/scott@orcl"<br><br>

Besides the above commands, all database statements are also supported(i.e select/update/delete)<br><br>


References
============
The project depends on some open-source projects without modifications, they have been built and copied into this project.
Below is the list:<br>

    luajit v2.1 : http://luajit.org/
    jnlua       : https://code.google.com/p/jnlua/
    jline2      : https://github.com/jline/jline2
    lpeg        : http://www.inf.puc-rio.br/~roberto/lpeg/
    MessagePack : https://github.com/fperrad/lua-MessagePack(pure lua)


Besides, some SQL scripts are from internet.
