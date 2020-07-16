/*[[Show system level enabled events.
    Refer to: https://github.com/xtender/xt_scripts/blob/master/events/enabled.sql
]]*/
set feed off
DECLARE
    level# INT;
BEGIN
    FOR event# IN 1 .. 10999 LOOP
        sys.dbms_system.read_ev(event#, level#);
        IF level# != 0 THEN
            dbms_output.put_line('Event #' || event# || ' level:' || level#);
        END IF;
    END LOOP;
    sys.dbms_system.read_ev(10046, level#);
    dbms_output.put_line(level#);
END;
/