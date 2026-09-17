itv start 5 Checking Active sessions in interval mode, type 'Ctrl + C' to abort
set verify on
ora actives
PRO
PRO Determine if need to abort(20%) ...
var next_action VARCHAR2
set verify off

BEGIN
    IF dbms_random.value(0,10)>8 THEN
        :next_action := 'off';
    ELSE
        :next_action := 'end';
    END IF;
END;
/
PRO next_action: itv &next_action
itv &next_action