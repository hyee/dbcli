itv start 5 Checking Active sessions in interval mode, type 'Ctrl + C' to abort
PRO  
ora actives
PRO determine if need to abort(10%) ...
var next_action varchar2
begin
    if dbms_random.value(0,10)>9 then
       raise_application_error(-20001,'Abort.');
    end if;
end;
/
itv end