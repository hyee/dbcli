/*[[
    perform an in-depth investigation of a SQL statement. Usage sqld <SQL_ID> [ T|D|N ] [days]
    T: Licensed for the Oracle Tuning Pack
    D: Licensed for the Diagnostics Pack
    N: Licensed for None
    
    Refer to https://github.com/mauropagano/sqld360 for more detail
    --[[
        &V2 : default={T}
        &V3 : default={31}
    --]]
]]*/

@@sql/sqld360.sql &V1 &V2 &V3