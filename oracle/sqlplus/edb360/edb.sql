/*[[
    perform an initial assessment of a remote system and gives a glance of a database state. Usage edb [ T | D | N ]
    T: Licensed for the Oracle Tuning Pack
    D: Licensed for the Diagnostics Pack
    N: Licensed for None
    
    Refer to https://github.com/carlos-sierra/edb360 for more detail
    --[[
        &V1: default={T}
    --]]
]]*/

@@sql\edb360.sql &V1