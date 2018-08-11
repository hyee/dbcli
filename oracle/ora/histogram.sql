/*[[Show histogram. Usage: @@NAME {<table_name>[.<partition_name>] <column_name>} [<test_value>|-test|-real]
    Examples:
    *  List histogram: @@NAME SYS.OBJ$ NAME
    *  List histogram and test the cardinality of a value:   @@NAME SYS.OBJ$ NAME "obj$"
    *  List histogram and test the cardinality of each EP value: @@NAME SYS.OBJ$ NAME -test
    *  List histogram and query the table to get the count of for each EP value: @@NAME SYS.OBJ$ NAME -real
    --[[
        &test  : default={0} test={1} real={2}
        @hybrid: 12.1={nullif(a.ENDPOINT_REPEAT_COUNT,0)}, default={null} 
        @CHECK_ACCESS_DBA: DBA_TAB_COLS={DBA_} DEFAULT={ALL_} 
    --]]
]]*/
SET FEED OFF SERVEROUTPUT ON
ora _find_object &V1

BEGIN
    IF nvl(instr(:object_type,'TABLE'),0)!=1 THEN
        raise_application_error(-20001,'Object &OBJECT_OWNER..&OBJECT_NAME[&OBJECT_TYPE] is not a table!');
    END IF;
    IF :V2 IS NULL THEN
        raise_application_error(-20001,'Please specify the column name!');
    END IF;
END;
/
PRO Histogram of &OBJECT_TYPE &OBJECT_OWNER..&OBJECT_NAME[&V2]
DECLARE
    oname     VARCHAR2(128) := :object_owner;
    tab       VARCHAR2(128) := :object_name;
    part      VARCHAR2(128) := :object_subname;
    ttype     VARCHAR2(60)  := :object_type;
    col       VARCHAR2(128) := upper(:V2);
    input     VARCHAR2(128) := :V3;
    is_test   PLS_INTEGER   := :test;
    srec      DBMS_STATS.STATREC;
    distcnt   NUMBER;
    density   NUMBER;
    nullcnt   NUMBER;
    avgclen   NUMBER;
    numrows   NUMBER;
    numblks   NUMBER;
    numbcks   NUMBER;
    avgrlen   NUMBER;
    samples   NUMBER;
    rpcnt     NUMBER;
    fmt       VARCHAR2(64) := ' %s %s %s %s %s %s %s';
    histogram VARCHAR2(80);
    dtype     VARCHAR2(128);
    txn_id    VARCHAR2(128) := dbms_transaction.local_transaction_id;
    stmt_id   VARCHAR2(128) := 'TEST_CARD_' || dbms_random.string('X', 16);
    test_stmt VARCHAR2(512) ;
    prevb     PLS_INTEGER := 0;
    dlen      PLS_INTEGER;
    buckets   PLS_INTEGER;
    pops      PLS_INTEGER := 0;
    cnt       PLS_INTEGER := 0;
    cep       VARCHAR2(128);
    pep       VARCHAR2(128) := lpad(' ',32);
    FUNCTION to_value(val1 NUMBER, val2 VARCHAR2, is_prev BOOLEAN := FALSE) RETURN VARCHAR2 IS
        rtn    VARCHAR2(128) := val1;
        tstamp TIMESTAMP;
        pv     VARCHAR2(2);
    BEGIN
        IF val1 IS NULL THEN
            RETURN NULL;
        END IF;
        CASE
            WHEN val2 IS NOT NULL THEN
                RETURN RTRIM(val2);
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER', 'BINARY_DOUBLE', 'BINARY_FLOAT') THEN
                RETURN val1;
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                tstamp := to_timestamp('' || TRUNC(val1), 'J');
                IF  MOD(val1, 1) = 0 THEN
                    RETURN to_char(tstamp, 'YYYY-MM-DD');
                END IF;
                IF dtype = 'DATE' THEN
                    RETURN to_char(tstamp + MOD(val1, 1), 'YYYY-MM-DD HH24:MI:SS');
                ELSE
                    RETURN to_char(tstamp + NUMTODSINTERVAL(MOD(val1, 1), 'DAY'), 'YYYY-MM-DD HH24:MI:SSxff' || dlen);
                END IF;
            ELSE
                RETURN to_char(val1, 'fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
        END CASE;
    END;

    FUNCTION conv(val1 NUMBER, val2 VARCHAR2, is_prev BOOLEAN := FALSE) RETURN VARCHAR2 IS
    BEGIN
        RETURN RPAD(NVL(to_value(val1, val2, is_prev), ' '), 32);
    END;

    PROCEDURE pr(msg VARCHAR2) IS
    BEGIN
        dbms_output.put_line(msg);
    END;

    PROCEDURE pr(v1 VARCHAR2, v2 VARCHAR2, v3 VARCHAR2, v4 VARCHAR2, v5 VARCHAR2, v6 VARCHAR2, v7 VARCHAR2) IS
        x7 VARCHAR2(128):= v7;
    BEGIN
        IF is_test=0 THEN
            x7 := '';
        END IF;
        pr(utl_lms.format_message(fmt, v1, v2, v3, v4, v5, v6, x7));
    END;

    FUNCTION getNum(val NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF val < 10000 THEN
            RETURN '' || ROUND(VAL, 2);
        ELSE
            RETURN TRIM(dbms_xplan.format_number(val));
        END IF;
    END;

    FUNCTION getv(val RAW) RETURN VARCHAR2 IS
        n  NUMBER;
        c  VARCHAR2(128);
        nc NVARCHAR2(128);
        bf binary_float;
        bd binary_double;
        d  DATE;
        r  ROWID;
    BEGIN
        CASE
            WHEN dtype IN ('NUMBER', 'INTEGER', 'FLOAT') THEN
                dbms_stats.convert_raw_value(val, n);
                RETURN n;
            WHEN dtype = 'BINARY_FLOAT' THEN
                dbms_stats.convert_raw_value(val, bf);
                RETURN bf;
            WHEN dtype = 'BINARY_DOUBLE' THEN
                dbms_stats.convert_raw_value(val, bd);
                RETURN bd;
            WHEN dtype = 'BINARY_DOUBLE' THEN
                dbms_stats.convert_raw_value(val, bd);
                RETURN bd;
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB') THEN
                dbms_stats.convert_raw_value(val, c);
                RETURN c;
            WHEN dtype IN ('NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                dbms_stats.convert_raw_value(val, nc);
                RETURN nc;
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                dbms_stats.convert_raw_value(val, d);
                RETURN d;
            WHEN dtype IN ('ROWID', 'UROWID') THEN
                dbms_stats.convert_raw_value(val, r);
                RETURN r;
            ELSE
                RETURN val;
        END CASE;
    END;

    FUNCTION get_card(val VARCHAR2) RETURN VARCHAR2 IS
        val1     VARCHAR2(128):=rtrim(val);
        target   VARCHAR2(300);
        test_val VARCHAR2(128);
        rtn      NUMBER;
    BEGIN
        IF test_stmt IS NULL THEN
            target := '"'||oname || '"."' || tab || '"';
            IF ttype like '% SUBPARTITION' THEN
                target := target||'SUBPARTITION('||part||')';
            ELSIF ttype like '% PARTITION' THEN
                target := target||'PARTITION('||part||')';
            END IF;
            IF is_test = 2 THEN
                test_stmt:='select /*+parallel(a 8)*/ count(1)';
            ELSE
                test_stmt:='explain plan set statement_id=''' || stmt_id ||
                          ''' for select /*+NO_PARALLEL(a) no_index(a) full(a) no_index_ffs(a)*/ *';
            END IF;
            test_stmt := test_stmt||' from ' || target || ' a where "' || col || '"=';
        END IF;

        CASE
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER', 'BINARY_DOUBLE', 'BINARY_FLOAT') THEN
                test_val:= val1;
            WHEN dtype = 'DATE' THEN
                test_val:= 'to_date(''' || val1 || ''',''YYYY-MM-DD HH24:MI:SS'')';
            WHEN dtype = 'TIMESTAMP' THEN
                test_val:= 'to_timestamp(''' || val1 || ''',''YYYY-MM-DD HH24:MI:SSxff'')';
            ELSE
                test_val:= '''' || val1 || '''';
        END CASE;

        IF is_test=2 THEN
            EXECUTE IMMEDIATE test_stmt || test_val INTO rtn;
        ELSE
            SAVEPOINT test_card;
            DELETE plan_table a WHERE a.statement_id = stmt_id;
            EXECUTE IMMEDIATE test_stmt || test_val;
            SELECT MAX(a.cardinality)
            INTO   rtn
            FROM   plan_table a
            WHERE  a.statement_id = stmt_id
            AND    ROWNUM < 2;
            IF txn_id IS NOT NULL THEN
                ROLLBACK TO SAVEPOINT test_card;
            ELSE
                COMMIT;
            END IF;
        END IF;
        RETURN rtn;
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE IN(-942,-1031) THEN
            raise_application_error(-20001,'You dont have the access to "'||oname||'"."'||tab||'"!');
        ELSE
            raise_application_error(-20001,sqlerrm||': '||test_stmt || test_val);
        END IF;
    END;
BEGIN
    dbms_output.enable(NULL);
    SELECT regexp_substr(data_type, '\w+'),
           COALESCE(regexp_substr(data_type, '\d+') + 0, data_scale, 6),
           histogram,
           sample_size,
           num_buckets
    INTO   dtype, dlen, histogram, samples, numbcks
    FROM   &CHECK_ACCESS_DBA.tab_cols
    WHERE  owner = oname
    AND    table_name = tab
    AND    column_name = col;

    DBMS_STATS.GET_TABLE_STATS(ownname  => oname,
                               tabname  => tab,
                               partname => part,
                               numrows  => numrows,
                               numblks  => numblks,
                               avgrlen  => avgrlen);

    DBMS_STATS.GET_COLUMN_STATS(ownname  => oname,
                                tabname  => tab,
                                partname => part,
                                colname  => col,
                                distcnt  => distcnt,
                                density  => density,
                                nullcnt  => nullcnt,
                                srec     => srec,
                                avgclen  => avgclen);
    pr(RPAD('=', 100, '='));
    pr(utl_lms.format_message('Histogram: "%s"   Rows: %s   Blocks: %s   Rows per Block: %s   Row Len: %s' || CHR(10) ||
                              'Col Len: %s   Density: %s   Cardinality: %s   Distincts: %s   Nulls: %s   Samples: %s' ||
                              CHR(10) || 'Buckets: %s      Low Value: "%s"        High Value: "%s"',
                              histogram,
                              getNum(numrows),
                              getNum(numblks),
                              '' || ROUND(numrows / NULLIF(numblks, 0), 2),
                              '' || avgrlen,
                              '' || avgclen,
                              round(density * 100, 3) || '%',
                              getNum(ROUND((numrows - nullcnt) / GREATEST(1, distcnt), 2)),
                              getNum(distcnt),
                              getNum(nullcnt),
                              getNum(samples),
                              '' || numbcks,
                              TRIM(getv(srec.minval)),
                              TRIM(getv(srec.maxval))));
    pr(RPAD('=', 100, '='));

    pr(RPAD(' ', 74));
    pr('    #', 'Bucket#',RPAD('Previous EP Value', 32), RPAD('Current EP Value', 32), 'Buckets', LPAD('Card', 8), LPAD(CASE WHEN is_test=2 THEN 'Real' ELSE 'RealCard' END, 8));
    pr('-----',  RPAD('-', 7, '-'),RPAD('-', 32, '-'), RPAD('-', 32, '-'), RPAD('-', 7, '-'), RPAD('-', 8, '-'), RPAD('-', 8, '-'));
    samples := NULLIF(samples, 0);
    numbcks := NULLIF(numbcks, 0);
    FOR i IN 1 .. srec.epc LOOP
        buckets := srec.bkvals(i) - prevb;
        IF buckets > 1 THEN
            cnt  := cnt + 1;
            pops := pops + buckets;
        END IF;
        prevb := srec.bkvals(i);
    END LOOP;

    density := NVL((1 - pops / numbcks) / NULLIF(distcnt - cnt, 0), density);

    prevb := 0;
    FOR i IN 1 .. srec.epc LOOP
        buckets := greatest(srec.bkvals(i) - prevb,1);
        IF histogram = 'HEIGHT BALANCED' THEN
            IF buckets > 1 THEN
                rpcnt := (numrows - nullcnt) * buckets / numbcks;
            ELSE
                /*
                NewDensity with the “half the least popular” rule active
                NewDensity is set to
                NewDensity = 0.5 * bkt(least_popular_value) / num_rows
                and hence, for non-existent values:
                E[card] = (0.5 * bkt(least_popular_value) / num_rows) * num_rows = 0.5 * bkt(least_popular_value)
                */
                rpcnt := (numrows - nullcnt) * density;
            END IF;
        ELSIF histogram = 'NONE' THEN
            rpcnt := (numrows - nullcnt) / GREATEST(1, distcnt) * buckets;
        ELSE
            rpcnt := buckets * (numrows - nullcnt) / samples;
        END IF;
    
        $IF dbms_db_version.version>11 $THEN
        rpcnt := nvl(nullif(srec.rpcnts(i), 0), rpcnt);
        $END
        cep := conv(srec.novals(i), case when srec.chvals.exists(i) then srec.chvals(i) end);
        pr(lpad(i, 5),
           lpad(srec.bkvals(i), 7), 
           pep,
           cep,
           lpad(buckets, 7),
           LPAD(NVL('' || getNum(rpcnt), ' '), 8),
           LPAD(case when is_test > 0  then getNum(get_card(cep)) end,8));
        pep   := cep;
        prevb := srec.bkvals(i);
    END LOOP;
    IF input IS NOT NULL THEN
        pr(CHR(10) || '  * Note:  Cardinality of input predicate "' || input || '" is ' || get_card(input));
    END IF;
EXCEPTION 
    WHEN NO_DATA_FOUND THEN
        raise_application_error(-20001,'No such column: '||col);
END;
/