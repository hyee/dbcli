/*[[
    SQLd360: Perform an in-depth investigation of a SQL statement. Usage: sqld <SQL_ID> [ T|D|N ] [days]
    T: Licensed for the Oracle Tuning Pack
    D: Licensed for the Diagnostics Pack
    N: Licensed for None
    
    You'd better make sure tkprof.exe is included in your path.
    
    SQLd360 by Mauro Pagano:
    ~~~~~~~~~~~~~~~~~~~~~~~~
        SQLd360 is a "free to use" tool to perform an in-depth investigation of a SQL statement. 
        It collects detailed information around the SQL. It also helps to document any findings.
        SQLd360 installs nothing. For better results execute connected as SYS or DBA.
        It takes a few minutes to execute. Output ZIP file can be large (several MBs), so
        you may want to execute SQLd360 from a system directory with at least 1 GB of free 
        space. 
    Refer to https://github.com/mauropagano/sqld360 for more detail
    --[[
        &V2 : default={T}
        &V3 : default={31}
    --]]
]]*/
HOS mkdir js 
HOS xcopy /S /Y "&&_FILE_DIR_\..\js\*" js

@@sqld360.sql &V1 &V2 &V3