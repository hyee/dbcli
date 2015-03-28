/*[[
    perform an initial assessment of a remote system and gives a glance of a database state. Usage edb [ T | D | N ]
    T: Licensed for the Oracle Tuning Pack
    D: Licensed for the Diagnostics Pack
    N: Licensed for None
    
    You'd better make sure tkprof.exe is included in your path
    Refer to https://github.com/carlos-sierra/edb360 for more detail
    --[[
        &V1: default={T}
    --]]
]]*/

HOS mkdir js 
HOS xcopy /S /Y "&&_FILE_DIR_\..\js\*" js
@@edb360.sql &V1