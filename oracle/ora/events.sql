/*[[List the available event number that used by 'alter session set events' statement. Usage: events [filter] ]]*/
DECLARE
    err_msg VARCHAR2(120);
    v_filter varchar2(300):= LOWER(:V1);
BEGIN
    IF v_filter IS NULL THEN
        v_filter:='%';
    ELSE
        v_filter:='%'||v_filter||'%';
    END IF;
    dbms_output.enable(1000000);
    FOR err_num IN 10000 .. 10999 LOOP
        err_msg := SQLERRM(-err_num);
        IF err_msg NOT LIKE '%Message ' || err_num || ' not found%' AND lower(err_msg) LIKE v_filter THEN
            dbms_output.put_line(err_msg);
        END IF;
    END LOOP;
END;
/

