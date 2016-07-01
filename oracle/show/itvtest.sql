itv start 5 Checking Active sessions in interval mode, type 'Ctrl + C' to abort
set VERIFY on
ora actives
pro
PRO Determine if need to abort(20%) ...
var next_action varchar2
set VERIFY off

begin
    if dbms_random.value(0,10)>8 then
        :next_action := 'off';
    else
        :next_action := 'end';
    end if;
end;
/
pro next_action: itv &next_action
itv &next_action