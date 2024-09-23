/*[[Test single-thread CPU performance
    --[[
        @check_access_obj: sys.obj$={1} default={0}
        @check_access_ecr: SYS.DBMS_CRYPTO={1} default={0}
    --]]
]]*/
set feed off
PRO Running, it could take 1 minute ...
PRO 
DECLARE
    TYPE t IS TABLE OF sys.tab%ROWTYPE;
    t1    t;
    var   VARCHAR2(255);
    str1  RAW(8192);
    str2  RAW(8192);
    num   NUMBER;
    tim   NUMBER;
    buff  NUMBER;
    recur NUMBER;
    adj   NUMBER := 0;
    encr  INT;
    loops PLS_INTEGER;

    PROCEDURE get_stats(is_init BOOLEAN) IS
        t NUMBER;
        r NUMBER;
        b NUMBER;
    BEGIN
        SELECT MAX(DECODE(sn.name, 'consistent gets', ms.value)),
               nvl(MAX(DECODE(sn.name, 'consistent gets', 0, ms.value)), 0)
        INTO   b, r
        FROM   v$mystat ms, v$statname sn
        WHERE  ms.STATISTIC# = sn.STATISTIC#
        AND    sn.name IN('consistent gets', 'consistent gets pin (fastpath)', 'consistent gets from cache (fastpath)');
        t := to_char(systimestamp, 'sssssff6');
        IF is_init THEN
            tim   := t;
            buff  := b;
            recur := r;
        ELSE
            tim   := t - tim;
            buff  := b - buff;
            recur := r - recur;
        END IF;
    END;

    PROCEDURE title(title VARCHAR2) IS
    BEGIN
        dbms_output.put_line('+'||rpad('-', 80, '-'));
        dbms_output.put_line('| '||title||':');
        dbms_output.put_line('| '||rpad('=',length(title)+1,'='));
    END;

    PROCEDURE pr(NAME VARCHAR2, VALUE NUMBER) IS
    BEGIN
        dbms_output.put_line('| '||rpad(NAME, 32) || ' = ' || round(VALUE, 2));
    END;
BEGIN
    dbms_output.enable(null);
    EXECUTE IMMEDIATE 'ALTER SESSION SET STATISTICS_LEVEL=basic "_rowsource_statistics_sampfreq"=256';
    dbms_random.seed(1);
    title('Tesing Random 255 Chars');
    get_stats(TRUE);
    loops := 5e4;
    FOR i IN 1 .. loops LOOP
        var := dbms_random.string('P', 255);
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)', tim * 1e-6);
    pr('Avg Time(us)', tim / loops);

    EXECUTE IMMEDIATE 'ALTER SESSION SET STATISTICS_LEVEL=basic "_rowsource_statistics_sampfreq"=256';
    title('Testing Random Number');
    get_stats(TRUE);
    loops := 1e6;
    FOR i IN 1 .. loops LOOP
        var := dbms_random.value(0,loops);
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)', tim * 1e-6);
    pr('Avg Time(us)', tim / loops);

    title('Testing MOD + SQRT + LOG');
    get_stats(TRUE);
    num := 0;
    loops := 1e6;
    FOR i IN 1 .. loops LOOP
        num := MOD(num, 999999) + ROUND(SQRT(i) + LOG(10, i), 8);
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)', ROUND(tim * 1e-6, 2));
    pr('Avg Time(us)', ROUND(tim / loops, 2));

    $IF &check_access_ecr=1 $THEN
        encr := SYS.DBMS_CRYPTO.ENCRYPT_AES256  + SYS.DBMS_CRYPTO.CHAIN_CBC+ SYS.DBMS_CRYPTO.PAD_PKCS5;
        str1:=utl_raw.cast_to_raw(dbms_random.string('P',4096));
        title('Testing AES-256 Encrytion');
        get_stats(TRUE);
        num := 0;
        loops := 5e5;
        FOR i IN 1 .. loops LOOP
            str2 := SYS.DBMS_CRYPTO.ENCRYPT(str1,encr,'A1B2C3E4D5F6ABCDA1B2C3E4D5F6ABCDA1B2C3E4D5F6ABCDA1B2C3E4D5F6ABCD');
        END LOOP;
        get_stats(FALSE);
        pr('Time(secs)', ROUND(tim * 1e-6, 2));
        pr('Avg Time(us)', ROUND(tim / loops, 2));

        str1:=utl_raw.cast_to_raw(dbms_random.string('P',4096));
        title('Testing AES-256 Decrytion');
        get_stats(TRUE);
        num := 0;
        loops := 5e5;
        FOR i IN 1 .. loops LOOP
            str1 := SYS.DBMS_CRYPTO.DECRYPT(str2,encr,'A1B2C3E4D5F6ABCDA1B2C3E4D5F6ABCDA1B2C3E4D5F6ABCDA1B2C3E4D5F6ABCD');
        END LOOP;
        get_stats(FALSE);
        pr('Time(secs)', ROUND(tim * 1e-6, 2));
        pr('Avg Time(us)', ROUND(tim / loops, 2));
    $END

    title('Testing Resursive Calls + PLSQL');
    get_stats(TRUE);
    loops := 1e6;
    FOR i IN 1 .. loops LOOP
        execute immediate 'BEGIN :1 := :2;END;' USING OUT num,i;
    END LOOP;
    get_stats(FALSE);
    adj := tim / loops;
    pr('Time(secs)', ROUND(tim * 1e-6, 2));
    pr('Buffer Gets', buff);
    pr('Buffer Gets (fastpath)', recur);
    pr('Avg Time(us)', ROUND(adj, 2));

    title('Testing Resursive Calls + PLSQL + DUAL');
    get_stats(TRUE);
    loops := 1e6;
    FOR i IN 1 .. loops LOOP
        execute immediate 'SELECT count(1) FROM DUAL WHERE ascii(dummy)>0 AND length(dummy)>0' into num;
    END LOOP;
    get_stats(FALSE);
    
    pr('Time(secs)', ROUND(tim * 1e-6, 2));
    pr('Buffer Gets  / Loop', buff/loops);
    pr('Buffer Gets  / Loop (fastpath)', recur/loops);
    pr('Avg Time(us) / Loop', ROUND(tim/loops, 2));
    pr('Avg Time(us) / Buffer', ROUND((tim-adj*loops)/buff, 2));
    adj := tim / loops;

    $IF &check_access_obj=1 $THEN
        title('Testing Buffer gets from sys.obj$');
        get_stats(TRUE);
        loops := 1000;
        FOR i IN 1 .. loops LOOP
            SELECT /*+NO_QUERY_TRANSFORMATION*/
                   COUNT(subname)
            INTO   num
            FROM   sys.obj$
            WHERE  rownum<=50000;
        END LOOP;
        get_stats(FALSE);
        pr('Time(secs)', ROUND((tim - adj*loops) * 1e-6, 2));
        pr('Buffer Gets', buff);
        pr('Buffer Gets (fastpath)', recur);
        pr('Avg Time / Buffer (us)', ROUND((tim - adj*loops) / buff, 2));
    $END

    title('Testing Complex Join from sys.tab');
    get_stats(TRUE);
    loops := 1000;
    FOR i IN 1 .. loops LOOP
        SELECT /*+NO_QUERY_TRANSFORMATION*/*
        BULK   COLLECT
        INTO   t1
        FROM   sys.tab
        WHERE  ROWNUM <= 3000;
    END LOOP;
    get_stats(FALSE);
    pr('Time(secs)', ROUND((tim - adj*loops) * 1e-6, 2));
    pr('Buffer Gets', buff);
    pr('Buffer Gets (fastpath)', recur);
    pr('Avg Time / Buffer (us)', ROUND((tim - adj*loops) / buff, 2));

    dbms_output.put_line('+'||rpad('-', 80, '-'));
    EXECUTE IMMEDIATE 'ALTER SESSION SET STATISTICS_LEVEL=all "_rowsource_statistics_sampfreq"=16';
END;
/