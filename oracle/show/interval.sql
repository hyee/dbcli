/*[[A test script of command itv begin/end/off]]*/
set printvar off feed off
ITV start 2
var flag varchar2
begin
    --please note that flag is a output parameter, it cannot be referenced as a input variable
    if dbms_random.value(0,10)>9 then
        :flag :='itv off';
        dbms_output.put_line('abort');
    else
        :flag :='itv end';
        dbms_output.put_line('continue');
    end if;
end;
/

&flag