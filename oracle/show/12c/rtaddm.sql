/*[[Produces a real-time ADDM report for ADDM-related activity of the last five minutes (12c+ only)
  --[[
    @ver: 12.1={}
  --]]
]]*/

set verify off feed off
var x clob;
BEGIN
    :x := dbms_addm.real_time_addm_report();
END;
/
save x real-time-addm.html