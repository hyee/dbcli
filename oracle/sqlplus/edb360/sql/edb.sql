/*[[
    EDB360: Perform an initial assessment of a remote system and gives a glance of a database state. Usage: edb [ T | D | N ]
    T: Licensed for the Oracle Tuning Pack
    D: Licensed for the Diagnostics Pack
    N: Licensed for None
    
    You'd better make sure tkprof.exe is included in your path.
    
    EDB360 by Carlos Sierra:
    ~~~~~~~~~~~~~~~~~~~~~~~
        EDB360 is a "free to use" tool to perform an initial assessment of a remote system. 
        It gives a glance of a database state. It also helps to document any findings.
        EDB360 installs nothing. For better results execute connected as SYS or DBA.
        It takes around one hour to execute. Output ZIP file can be large (several MBs), so
        you may want to execute EDB360 from a system directory with at least 1 GB of free 
        space. Best time to execute EDB360 is close to the end of a working day.
    Refer to https://github.com/carlos-sierra/edb360 for more detail.
    
    Notes
    ~~~~~
    1. If you need to execute edb360 against all databases in host use then run_db360.sh:

       $ unzip edb360.zip
       $ cd edb360
       $ sh run_db360.sh

       note: this method requires Oracle Tuning pack license in all databases in such host.

    2. If you need to execute only a portion of edb360 (i.e. a column, section or range) use 
       these commands. Notice hidden parameter _o_release can be set to one section (i.e. 3b),
       one column (i.e. 3), a range of sections (i.e. 5c-6b) or range of columns (i.e. 5-7):

       SQL> DEF _o_release = '3b';
       SQL> @edb360.sql T
       
       note: valid column range for hidden parameter _o_release is 1 to 7. 

    3. If you need to generate edb360 for a range of dates other than last 31 days; or change
       default "working hours" between 7:30AM and 7:30PM; or suppress an output format such as
       text or csv; modify then file edb360_00_config.sql (back it up first).
    --[[
        &V1: default={T}
    --]]
]]*/

HOS mkdir js 
HOS xcopy /S /Y "&&_FILE_DIR_\..\js\*" js
@@edb360.sql &V1