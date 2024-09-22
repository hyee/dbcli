/*[[Test single-thread CPU performance]]*/
set feed off
DECLARE
    TYPE t IS TABLE OF sys.tab%ROWTYPE;
    t1   t;
    var  VARCHAR2(255);
    tim  NUMBER;
    buff NUMBER;
    recur NUMBER;
    adj  NUMBER := 0;

    PROCEDURE get_stats(is_init BOOLEAN) IS
        t NUMBER;
        r NUMBER;
        b NUMBER;
    BEGIN
        SELECT MAX(DECODE(sn.name, 'consistent gets', ms.value)),
               MAX(DECODE(sn.name, 'recursive calls', ms.value))
        INTO   b, r
        FROM   v$mystat ms, v$statname sn
        WHERE  ms.STATISTIC# = sn.STATISTIC#
        AND    sn.name IN ('consistent gets', 'recursive calls');
        t:= to_char(systimestamp,'sssssff6');
        IF is_init THEN
            tim  := t;
            buff := b;
            recur:= r;
        ELSE
            tim  := t - tim;
            buff := b - buff;
            recur:= r - recur;
        END IF;
    END;
    PROCEDURE pr(name VARCHAR2,value number) IS
    BEGIN
        dbms_output.put_line(rpad(name,30)||' = '||round(value,2));
    END;
BEGIN
    dbms_output.put_line('Tesing Random String');
    dbms_output.put_line('====================');
    get_stats(TRUE);
    FOR i IN 1 .. 5e4 LOOP
        var := dbms_random.string('P', 255);
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)',ROUND((tim - adj) * 1e-6, 2));
    pr('Avg Time(us)',ROUND((tim - adj) / 5e4, 2));
    dbms_output.put_line(rpad('.',80,'.'));

    dbms_output.put_line('Tesing Buffer gets');
    dbms_output.put_line('====================');
    get_stats(TRUE);
    FOR i IN 1 .. 300 LOOP
        select /*+NO_QUERY_TRANSFORMATION*/  count(tname)
        into  var
        from   sys.tab;
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)',ROUND((tim - adj) * 1e-6, 2));
    pr('Buffer Gets',buff);
    pr('Recursive Calls per Loop',recur/300);
    pr('Avg Time/ Buffer (us)',ROUND((tim - adj) / buff, 2));
    dbms_output.put_line(rpad('.',80,'.'));

    sys.dbms_lock.sleep(1);
    dbms_output.put_line('Tesing Complex Join');
    dbms_output.put_line('===================');
    get_stats(TRUE);
    FOR i IN 1 .. 1000 LOOP
        SELECT /*+NO_QUERY_TRANSFORMATION*/ * 
        BULK COLLECT INTO t1 
        FROM sys.tab 
        WHERE ROWNUM <= 3000;
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)',ROUND((tim - adj) * 1e-6, 2));
    pr('Buffer Gets',buff);
    pr('Recursive Calls per Loop',recur/1000);
    pr('Avg Time / Buffer (us)',ROUND((tim - adj) / buff, 2));
END;
/