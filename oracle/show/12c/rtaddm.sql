/*[[Produces a real-time ADDM report for ADDM-related activity for the last five minutes, 12c+ only
  --[[
    @ver: 12.1={}
  --]]
]]*/

set verify off feed off
var x clob;
begin
    :x := DBMS_ADDM.REAL_TIME_ADDM_REPORT ();
end;
/
save x real-time-addm.html