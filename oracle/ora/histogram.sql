/*[[
    Show/change column histogram. Usage: @@NAME {<table_name>[.<partition_name>] <column_name>} {<test_value> | <min_v> <max_v> | <value> <buckets> [<card>]} [-test|-real] [-tab"<stats_tab>"]
    Options:
        *  -test: use "EXPLAIN PLAN" to test the cardinality of each EP value. In case of setting histograms, this option will skip the changes
        *  -real: use "SELECT COUNT(1)" to test the real count of each EP value
        *  -tab : use stats table as the data source/target

    Examples:
        *  List the histogram: @@NAME SYS.OBJ$ NAME
        *  List the histogram from the stats table: @@NAME SYS.OBJ$ NAME -tab"system.stattab"
        *  List the histogram and test the est cardinality of scalar value : @@NAME SYS.OBJ$ NAME "obj$"
        *  List the histogram and test the est cardinality of bind variable: @@NAME SYS.OBJ$ NAME :1
        *  List the histogram and test the est cardinality of each EP value: @@NAME SYS.OBJ$ NAME -test
        *  List the histogram and test the act cardinality of each EP value: @@NAME SYS.OBJ$ NAME -real
        *  Change the low/high value of "NONE" histogram:  @@NAME sys.obj$ stime "1990-08-26 11:25:01" "2018-08-12 02:50:00"
        *  Set number of buckets of "FREQUENCY" histogam: @@NAME sys.obj$ owner# 89 5
        *  Remove an EP from histogam: @@NAME sys.obj$ owner# 89 0
        *  Set number of buckets and repeats of "HYBRID" histogam: @@NAME obj object_name sun/misc/Lock 295 10

    Notes: if input data type is not string/number/raw, the value should follow below format:
        *  DATE                    : YYYY-MM-DD HH24:MI:SS
        *  TIMESTAMP               : YYYY-MM-DD HH24:MI:SSxFF
        *  TIMESTAMP WITH TIMEZONE : YYYY-MM-DD HH24:MI:SSxFF TZH:TZM
    --[[
        &test  : default={0} test={1} real={2}
        &tab   : default={} tab={&0}
        @CHECK_ACCESS_DBA: DBA_TAB_COLS/DBA_PART_COL_STATISTICS={DBA_} DEFAULT={ALL_}
    --]]
]]*/
SET FEED OFF SERVEROUTPUT ON VERIFY OFF
var stats_owner varchar2
var stats_tab   varchar2
var script_text CLOB; --The variable to store the SQL*Plus script
ora _find_object "&tab" 1
BEGIN
    IF :tab IS NOT NULL AND :object_name IS NULL THEN
        raise_application_error(-20001,'Cannot access target stats table "&tab" !');
    END IF;
    :stats_owner := :object_owner;
    :stats_tab   := :object_name;
END;
/

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
    is_test   PLS_INTEGER   := :test;
    oname     VARCHAR2(128) := :object_owner;
    tab       VARCHAR2(128) := :object_name;
    part      VARCHAR2(128) := :object_subname;
    ttype     VARCHAR2(60)  := :object_type;
    statown   VARCHAR2(30)  := :stats_owner;
    stattab   VARCHAR2(30)  := :stats_tab;
    col       VARCHAR2(128) := upper(:V2);
    input     VARCHAR2(128) := :V3;
    max_v     VARCHAR2(128) := :V4;
    card_adj  NUMBER        := regexp_substr(:V5, '^\d+$');
    bk_adj    NUMBER        := regexp_substr(max_v, '^\d+$');
    other_adj NUMBER        := 0;
    datefmt   VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SS';
    tstampfmt VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SSxff';
    tztampfmt VARCHAR2(32)  := tstampfmt || ' TZH:TZM';
    rawfmt    VARCHAR2(32)  := 'fm' || lpad('x', 30, 'x');
    min_v     VARCHAR2(128);
    restoret  VARCHAR2(128);
    rawinput  RAW(128);
    rawval    RAW(2000);
    srec      dbms_stats.StatRec;
    nrec      dbms_stats.StatRec;
    orec      dbms_stats.StatRec;
    distcnt   NUMBER;
    density   NUMBER;
    densityn  NUMBER;
    nullcnt   NUMBER;
    avgclen   NUMBER;
    numrows   NUMBER;
    numblks   NUMBER;
    numbcks   NUMBER;
    notnulls  NUMBER;
    avgrlen   NUMBER;
    samples   NUMBER;
    rpcnt     NUMBER;
    numval    NUMBER;
    dateval   DATE;
    analyzed  DATE;
    tstamp    TIMESTAMP;
    fmt       VARCHAR2(64)  := ' %s  %s  %s  %s  %s %s %s';
    histogram VARCHAR2(80);
    dtype     VARCHAR2(128);
    dtypefull VARCHAR2(128);
    txn_id    VARCHAR2(128) := dbms_transaction.local_transaction_id;
    stmt_id   VARCHAR2(128) := 'TEST_CARD_' || dbms_random.string('X', 16);
    test_stmt VARCHAR2(512);
    cep       VARCHAR2(128);
    pep       VARCHAR2(128) := lpad(' ', 32);
    gstats    VARCHAR2(3);
    ustats    VARCHAR2(3);
    flags     PLS_INTEGER;
    dlen      PLS_INTEGER;
    buckets   PLS_INTEGER;
    prevb     PLS_INTEGER   := 0;
    prevv     PLS_INTEGER   := 0;
    cnt       PLS_INTEGER   := 0;
    pops      PLS_INTEGER   := 0;
    pop_based NUMBER        := 0;

    --convert all_tab_histograms.enpoint_value as varchar2
    --refer to https://mwidlake.wordpress.com/2009/08/11/decrypting-histogram-data/
    FUNCTION hist_numtochar(p_num NUMBER, p_trunc VARCHAR2 := 'Y') RETURN VARCHAR2 IS
        m_vc   VARCHAR2(15);
        m_n1   NUMBER;
        m_n    NUMBER := 0;
        m_loop NUMBER := 7;
    BEGIN
        m_n := p_num;
        IF length(to_char(m_n)) < 36 THEN
            m_vc := 'num format err';
        ELSE
            IF p_trunc != 'Y' THEN
                m_loop := 15;
            END IF;
            FOR i IN 1 .. m_loop LOOP
                m_n1 := trunc(m_n / (power(256, 15 - i)));
                IF m_n1 != 0 THEN
                    m_vc := m_vc || chr(m_n1);
                END IF;
                m_n := m_n - (m_n1 * power(256, 15 - i));
            END LOOP;
        END IF;
        RETURN m_vc;
    END;

    --onvert all_tab_histograms.enpoint_value that defined in srec as varchar2
    FUNCTION conv(idx PLS_INTEGER, num NUMBER := NULL) RETURN VARCHAR2 IS
        rtn NUMBER := nvl(NUM, CASE WHEN idx IS NOT NULL THEN srec.novals(idx) END);
        eva RAW(128);
    BEGIN
        $IF dbms_db_version.version > 11 $THEN
            IF idx IS NOT NULL THEN
                eva := srec.eavals(idx);
            END IF;
        $END
        CASE
            WHEN idx IS NOT NULL AND srec.chvals.exists(idx) AND srec.chvals(idx) IS NOT NULL THEN
                RETURN RTRIM(srec.chvals(idx));
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'ROWID', 'UROWID') THEN
                RETURN nvl(utl_raw.cast_to_varchar2(eva), hist_numtochar(rtn));
            WHEN dtype IN ('NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                RETURN nvl(utl_raw.cast_to_nvarchar2(eva), hist_numtochar(rtn));
            WHEN dtype = 'BINARY_DOUBLE' THEN
                RETURN TO_CHAR(TO_BINARY_DOUBLE(rtn), 'TM');
            WHEN dtype = 'BINARY_FLOAT' THEN
                RETURN TO_CHAR(TO_BINARY_FLOAT(rtn), 'TM');
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                RETURN to_char(rtn, 'TM');
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                tstamp := to_timestamp('' || TRUNC(rtn), 'J');
                IF MOD(rtn, 1) = 0 THEN
                    RETURN to_char(tstamp, substr(datefmt, 1, 10));
                END IF;
                IF dtype = 'DATE' THEN
                    RETURN to_char(tstamp + MOD(rtn, 1), datefmt);
                ELSE
                    RETURN TRIM(trailing '0' FROM to_char(tstamp + NUMTODSINTERVAL(MOD(rtn, 1) * 86400, 'SECOND'), tstampfmt));
                END IF;
            ELSE
                RETURN substr(to_char(rtn, rawfmt), 1, 16);
        END CASE;
    END;

    --convert the value in srec into raw value
    FUNCTION conr(idx PLS_INTEGER, num NUMBER := NULL) RETURN RAW IS
        rtn VARCHAR2(128) := conv(idx, num);
        d   TIMESTAMP;
    BEGIN
        CASE
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'ROWID', 'UROWID', 'NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                RETURN utl_raw.cast_to_raw(rtn);
            WHEN dtype = 'BINARY_DOUBLE' THEN
                RETURN utl_raw.cast_from_binary_double(to_binary_double(rtn));
            WHEN dtype = 'BINARY_FLOAT' THEN
                RETURN utl_raw.cast_from_binary_float(to_binary_float(rtn));
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                RETURN utl_raw.cast_from_number(to_number(rtn));
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                d   := to_timestamp(rtn, tstampfmt);
                rtn := lpad(to_char(substr(extract(YEAR FROM d), 1, 2) + 100, 'fmxx'), 2, 0) ||
                       lpad(to_char(substr(extract(YEAR FROM d), 3, 2) + 100, 'fmxx'), 2, 0) ||
                       lpad(to_char(extract(MONTH FROM d), 'fmxx'), 2, 0) ||
                       lpad(to_char(extract(DAY FROM d), 'fmxx'), 2, 0) ||
                       lpad(to_char(extract(HOUR FROM d) + 1, 'fmxx'), 2, 0) ||
                       lpad(to_char(extract(MINUTE FROM d) + 1, 'fmxx'), 2, 0) ||
                       lpad(to_char(extract(SECOND FROM d) + 1, 'fmxx'), 2, 0);
                IF dtype != 'DATE' THEN
                    rtn := rtn || lpad(to_char(0 + to_char(d, 'ff9'), 'fmxxxxxxxx'), 8, 0);
                END IF;
                RETURN hextoraw(rtn);
            ELSE
                RETURN hextoraw(rtn);
        END CASE;
    END;

    PROCEDURE pr(msg VARCHAR2) IS
    BEGIN
        dbms_output.put_line(msg);
    END;

    PROCEDURE pr(v1 VARCHAR2, v2 VARCHAR2, v3 VARCHAR2, v4 VARCHAR2, v5 VARCHAR2, v6 VARCHAR2, v7 VARCHAR2) IS
        x7 VARCHAR2(128) := v7;
    BEGIN
        IF is_test = 0 THEN
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

    --convert low_value/high_value in dba_tab_cols into varchar2
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

    --convert the value into endpoint_value
    FUNCTION toNum(input VARCHAR2) RETURN NUMBER IS
    BEGIN
        CASE
            WHEN dtype IN ('NUMBER', 'INTEGER', 'FLOAT', 'BINARY_FLOAT', 'BINARY_DOUBLE') THEN
                RETURN to_number(input);
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'NVARCHAR2', 'NCHAR', 'NCLOB', 'ROWID', 'UROWID') THEN
                --numval := to_number(utl_raw.cast_to_raw(rpad(input),15,0),rawfmt);
                RETURN NULL;
            WHEN dtype = 'DATE' THEN
                dateval := to_date(input, datefmt);
                RETURN to_char(dateval, 'J') +(dateval - trunc(dateval));
            WHEN dtype = 'TIMESTAMP' THEN
                tstamp := to_timestamp(input, tstampfmt);
                RETURN to_char(tstamp, 'J') +(tstamp + 0 - trunc(tstamp + 0)) + to_char(tstamp, '"0"xff') / 86400;
            ELSE
                raise_application_error(-20001, 'Unsupported data type: ' || dtype);
        END CASE;
    EXCEPTION
        WHEN OTHERS THEN
            raise_application_error(-20001, 'Conversion error from value "' || input || '" to the "' || dtype || '" data type!');
    END;

    --get the cardinality of a specific predicate
    FUNCTION get_card(val VARCHAR2) RETURN VARCHAR2 IS
        val1     VARCHAR2(128) := rtrim(val);
        str      VARCHAR2(128) := CASE WHEN val1 LIKE ':%' THEN val1 ELSE '''' || val1 || '''' END;
        target   VARCHAR2(500);
        test_val VARCHAR2(128);
        rtn      NUMBER;
    BEGIN
        IF test_stmt IS NULL THEN
            target := '"' || oname || '"."' || tab || '"';
            IF ttype LIKE '% SUBPARTITION' THEN
                target := target || 'SUBPARTITION(' || part || ')';
            ELSIF ttype LIKE '% PARTITION' THEN
                target := target || 'PARTITION(' || part || ')';
            END IF;
            IF is_test = 2 THEN
                test_stmt := 'select /*+parallel(a 8)*/ count(1)';
            ELSE
                test_stmt := 'explain plan set statement_id=''' || stmt_id || ''' for select /*+no_parallel(a) cursor_sharing_exact no_index(a) full(a)*/ *';
            END IF;
            test_stmt := test_stmt || ' from ' || target || ' a where "' || col || '"=';
        END IF;
    
        CASE
            WHEN dtype = 'BINARY_DOUBLE' THEN
                test_val := 'TO_BINARY_DOUBLE(' || str || ')';
            WHEN dtype = 'BINARY_FLOAT' THEN
                test_val := 'TO_BINARY_FLOAT(' || str || ')';
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                test_val := 'TO_NUMBER(' || str || ')';
            WHEN dtype = 'DATE' THEN
                test_val := 'to_date(' || str || ',''' || datefmt || ''')';
            WHEN dtype = 'TIMESTAMP' THEN
                test_val := 'to_timestamp(' || str || ',''' || tstampfmt || ''')';
            ELSE
                test_val := str;
        END CASE;
    
        IF is_test = 2 THEN
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
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE IN (-942, -1031) THEN
                raise_application_error(-20001, 'You dont have the access to "' || oname || '"."' || tab || '"!');
            ELSE
                target := SQLERRM || ': ' || test_stmt || test_val;
                raise_application_error(-20001, target);
            END IF;
    END;

    PROCEDURE init IS
        ex_array1 EXCEPTION;
        ex_array2 EXCEPTION;
        PRAGMA EXCEPTION_INIT(ex_array1, -6532);
        PRAGMA EXCEPTION_INIT(ex_array2, -6533);
    BEGIN
        IF nrec.epc = 0 THEN
            nrec.eavs   := srec.eavs;
            nrec.bkvals := dbms_stats.numarray();
            nrec.novals := dbms_stats.numarray();
            nrec.chvals := dbms_stats.chararray();
            $IF dbms_db_version.version > 11 $THEN
                nrec.eavals := dbms_stats.rawarray();
                nrec.rpcnts := dbms_stats.numarray();
            $END
        END IF;
    
        nrec.bkvals.extend;
        nrec.novals.extend;
        nrec.chvals.extend;
        nrec.epc := nrec.epc + 1;
        $IF dbms_db_version.version > 11 $THEN
            nrec.eavals.extend;
            nrec.rpcnts.extend;
            nrec.rpcnts(nrec.epc) := 0;
        $END
    EXCEPTION
        WHEN ex_array1 OR ex_array2 THEN
            raise_application_error(-20001, 'Cannot extend histogram whose size > ' || nrec.epc || '!');
    END;

    PROCEDURE add_rec(chval VARCHAR2, noval NUMBER, buckets PLS_INTEGER, rpcnt PLS_INTEGER, eaval RAW := NULL) IS
        steps PLS_INTEGER := CASE WHEN histogram = 'HEIGHT BALANCED' THEN buckets ELSE 1 END;
        incr PLS_INTEGER := CASE WHEN histogram = 'HYBRID' THEN prevv ELSE 0 END;
    BEGIN
        IF nvl(buckets, 0) < 1 AND nrec.epc > 0 THEN
            raise_application_error(-20001, 'buckets(' || buckets || ') of #' || (nrec.epc + 1) || ' must > 0!');
        END IF;
    
        FOR i IN 1 .. steps LOOP
            init;
            nrec.chvals(nrec.epc) := chval;
            nrec.novals(nrec.epc) := noval;
            nrec.bkvals(nrec.epc) := buckets / steps + incr;
            $IF dbms_db_version.version > 11 $THEN
                nrec.eavals(nrec.epc) := eaval;
                IF histogram = 'HYBRID' THEN
                    IF nvl(rpcnt, 0) < 1 THEN
                        raise_application_error(-20001, 'rpcnts(' || rpcnt || ') of #' || nrec.epc || ' must > 0!');
                    END IF;
                    nrec.rpcnts(nrec.epc) := buckets + incr;
                    nrec.bkvals(nrec.epc) := rpcnt;
                END IF;
            $END
        END LOOP;
        prevv := prevv + buckets;
    END;

    FUNCTION to_header(title VARCHAR2, VALUE VARCHAR2, sep VARCHAR2 := '    ') RETURN VARCHAR2 IS
    BEGIN
        RETURN sep || rpad(title, 11) || ': ' || rpad(VALUE, 10);
    END;

    --compute the NewDensity
    PROCEDURE calc_density IS
    BEGIN
        /*  EP         = EndPoint
            NewDensity = (1-PopBktCnt/BktCnt)/(NDV-PopValCnt)
            BktCnt     = MAX(EP_number)
            PopBktCnt  = SUM(<number of popular buckets>)
            PopValCnt  = Count(<number of popular buckets>)
            Buckets    = current_EP_number - previous_EP_number
            Popular EP values:
                HEIGHT BALANCED: The EP whose buckets > 1
                HYBRID         : The EP whose buckets > BktCnt/NUM_BUCKETS
        
        */
        numbcks := srec.bkvals(srec.epc);
        numrows := greatest(numrows, 1);
        samples := nvl(NULLIF(samples, 0), numrows);
        numbcks := NULLIF(numbcks, 0);
        cnt     := 0;
        pops    := 0;
        dlen    := 16;
    
        CASE histogram
            WHEN 'HYBRID' THEN
                pop_based := numbcks / srec.epc;
            WHEN 'HEIGHT BALANCED' THEN
                pop_based := 1;
            ELSE
                pop_based := NULL;
        END CASE;
    
        FOR i IN 1 .. srec.epc LOOP
            buckets := srec.bkvals(i) - prevb;
            srec.chvals(i) := rtrim(conv(i));
            dlen := greatest(dlen, lengthb(srec.chvals(i)));
            $IF dbms_db_version.version>11 $THEN
                buckets := nvl(nullif(srec.rpcnts(i), 0), buckets);
            $END
            IF buckets > pop_based THEN
                cnt  := cnt + 1;
                pops := pops + buckets;
            END IF;
            prevb := srec.bkvals(i);
        END LOOP;
    
        densityn := coalesce((1 - pops / numbcks) / nullif(distcnt - cnt, 0), density);
    END;

    PROCEDURE reset_Rec(rec IN OUT NOCOPY DBMS_STATS.STATREC) IS
    BEGIN
        IF rec.chvals IS NULL THEN
            rec.chvals := dbms_stats.chararray();
        END IF;
        rec.chvals.extend(rec.epc - rec.chvals.count);
    
        $IF dbms_db_version.version > 11 $THEN
            IF rec.eavals IS NULL THEN
                rec.eavals := dbms_stats.rawarray();
            END IF;
            IF rec.rpcnts IS NULL THEN
                rec.rpcnts := dbms_stats.numarray();
            END IF;
            rec.eavals.extend(rec.epc - rec.eavals.count);
            rec.rpcnts.extend(rec.epc - rec.rpcnts.count);
        $END
    END;

    --load table and column statistics
    PROCEDURE load_stats(rec IN OUT NOCOPY DBMS_STATS.STATREC) IS
        msg VARCHAR2(2000);
        cnt PLS_INTEGER;
    BEGIN
        BEGIN
            SELECT column_name,data_type 
            INTO   col,dtypefull
            FROM   &CHECK_ACCESS_DBA.tab_cols b
            WHERE  b.owner = oname
            AND    b.table_name = tab
            AND    upper(b.column_name) = col;

            SELECT a.*
            INTO   histogram, samples, analyzed, gstats, ustats
            FROM   (SELECT histogram,
                           nvl2(num_buckets, nvl(sample_size, 0), NULL) samples,
                           last_analyzed,
                           global_stats,
                           user_stats
                    FROM   &CHECK_ACCESS_DBA.part_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    b.partition_name = part
                    AND    ttype='TABLE PARTITION'
                    UNION ALL
                    SELECT histogram,
                           nvl2(num_buckets, nvl(sample_size, 0), NULL) samples,
                           last_analyzed,
                           global_stats,
                           user_stats
                    FROM   &CHECK_ACCESS_DBA.subpart_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    b.subpartition_name = part
                    AND    ttype='TABLE SUBPARTITION'
                    UNION ALL
                    SELECT histogram,
                           nvl2(num_buckets, nvl(sample_size, 0), NULL) samples,
                           last_analyzed,
                           global_stats,
                           user_stats
                    FROM   &CHECK_ACCESS_DBA.tab_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    ttype='TABLE') a;
            
            dtype := regexp_substr(dtypefull, '^\w+');
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'No such column or column is not analyzed: ' || col);
        END;
        
        IF stattab IS NOT NULL THEN
            BEGIN
                EXECUTE IMMEDIATE 'select max(d1),max(nvl(n4,0)),count(1) from "' || statown || '"."' || stattab ||
                                  '" WHERE c5=:1 and c1=:2 and c4=:3 and (coalesce(:4,c2,c3) is null or :4 in(c2,c3))'
                    INTO analyzed, samples, cnt
                    USING oname, tab, col, part, part;
                IF cnt = 0 THEN
                    dbms_stats.export_column_stats(oname,tab,col,part,statown=>statown,stattab=>stattab);
                    load_stats(rec);
                    return;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                IF SQLCODE IN (-942, -1031) THEN
                    raise_application_error(-20001, 'You dont have the access to "' || statown || '"."' || stattab || '"!');
                ELSE
                    raise;
                END IF;
            END;
        END IF;
    
        IF histogram IS NULL OR samples IS NULL THEN
            raise_application_error(-20001, 'Target column on the ' || lower(ttype) || ' is not analyzed!');
        END IF;

        CASE 
            WHEN histogram ='FREQUENCY' AND dbms_db_version.version>11 THEN flags := 4096;
            WHEN histogram ='TOP-FREQUENCY' THEN flags := 8192;
            ELSE flags := 0;
        END CASE;
    
        BEGIN
            DBMS_STATS.GET_TABLE_STATS(ownname  => oname,
                                       tabname  => tab,
                                       partname => part,
                                       numrows  => numrows,
                                       numblks  => numblks,
                                       avgrlen  => avgrlen,
                                       statown  => statown,
                                       stattab  => stattab);
        
            DBMS_STATS.GET_COLUMN_STATS(ownname  => oname,
                                        tabname  => tab,
                                        partname => part,
                                        colname  => col,
                                        distcnt  => distcnt,
                                        density  => density,
                                        nullcnt  => nullcnt,
                                        srec     => rec,
                                        avgclen  => avgclen,
                                        statown  => statown,
                                        stattab  => stattab);
            notnulls := numrows - nullcnt;

            IF flags > 0 AND bitand(srec.eavs,flags) = 0 THEN
                srec.eavs := srec.eavs + flags;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                msg := TRIM('Unable to get table/column stats due to ' || SQLERRM);
                raise_application_error(-20001, msg);
        END;
        
        reset_Rec(rec);
    END;

    --generate the sql*plus script to update the histogram
    PROCEDURE to_script(rec in out nocopy dbms_stats.StatRec) IS
        buff VARCHAR2(32767);
        c    CLOB;
        PROCEDURE append(idx PLS_INTEGER, name VARCHAR2, val VARCHAR2) IS
            elem VARCHAR2(2000) := CASE WHEN NAME IN('chvals','eavals','minval','maxval') THEN ''''||val||'''' ELSE val END;
        BEGIN
            IF val IS NULL THEN
                RETURN; 
            END IF;
            buff := buff || chr(10) || lpad(' ',4)||utl_lms.format_message('srec.%s%s := %s;',name,nullif('('||idx||')','()'),elem);
            IF lengthb(buff)>28000 THEN
                dbms_lob.writeAppend(c,length(buff),buff);
                buff := '';
            END IF;
        END;
    BEGIN
        buff := replace(replace(q'[
            DECLARE
                srec dbms_stats.StatRec;
            BEGIN
                srec.epc    := :epc;
                srec.bkvals := dbms_stats.numarray();
                srec.novals := dbms_stats.numarray();
                srec.chvals := dbms_stats.chararray();
                srec.bkvals.extend(srec.epc);
                srec.novals.extend(srec.epc);
                srec.chvals.extend(srec.epc);
                $IF dbms_db_version.version > 11 $THEN
                    srec.eavals := dbms_stats.rawarray();
                    srec.rpcnts := dbms_stats.numarray();
                    srec.eavals.extend(srec.epc);
                    srec.rpcnts.extend(srec.epc);
                $END]',':epc',rec.epc),lpad(' ',12));
        dbms_lob.createTemporary(c,true);
        reset_Rec(rec);

        buff := buff||chr(10);
        append(null,'eavs',rec.eavs);
        append(null,'minval',rec.minval);
        append(null,'maxval',rec.maxval);

        FOR i in 1..rec.epc LOOP
            buff := buff||chr(10);
            append(i,'novals',to_char(rec.novals(i),'tm'));
            append(i,'bkvals',rec.bkvals(i));
            append(i,'chvals',rec.chvals(i));
            $IF dbms_db_version.version > 11 $THEN
                append(i,'eavals',rec.eavals(i));
                append(i,'rpcnts',rec.rpcnts(i));
            $END
        END LOOP;

        buff := buff||chr(10)||regexp_replace(
            utl_lms.format_message(q'[
                dbms_stats.set_column_stats(srec          => srec,
                                            ownname       => '%s',
                                            tabname       => '%s',
                                            partname      => '%s',
                                            colname       => '%s',
                                            distcnt       => %s,
                                            density       => %s,
                                            nullcnt       => %s,
                                            avgclen       => %s,
                                            no_invalidate => false,
                                            force         => true);
            END;
            /]',oname,tab,part,col,''||distcnt,to_char(densityn,'tm'),''||nullcnt,''||avgclen),
            '('||chr(10)||chr(13)||'?) {12}','\1');

        dbms_lob.writeAppend(c,length(buff),buff);
        :script_text := c;
    END;

    --compare pre-change and post-change
    PROCEDURE diff IS
        counter PLS_INTEGER := 0;
        fmt     VARCHAR2(100) := '%s  %s  %s  %s';
        PROCEDURE p(v1 VARCHAR2,V2 VARCHAR2,V3 VARCHAR2,V4 VARCHAR2) IS
        BEGIN
            pr(utl_lms.format_message(fmt,v1,v2,v3,v4));
        END;

        PROCEDURE d(idx PLS_INTEGER, NAME VARCHAR2, val1 VARCHAR2, val2 VARCHAR2) IS
        BEGIN
            IF nvl(val1, chr(1)) = nvl(val2, chr(1)) THEN
                RETURN;
            END IF;
        
            counter := counter + 1;
            IF counter = 1 THEN
                pr(rpad('=', 48, '=') || ' Statistics Differences ' || rpad('=', 48, '='));
                p(lpad('#', 4),rpad('Item', 7),rpad('Pre-Change', 50),rpad('Post-Change', 50));
                p(lpad('-', 4, '-'),rpad('-', 7, '-'),rpad('-', 50, '-'),rpad('-', 50, '-'));
            END IF;
            p(lpad(idx, 4),rpad(NAME, 7),rpad(nvl(val1, 'N/A'), 50),rpad(nvl(val2, 'N/A'), 50));
        END;
    BEGIN
        d(0, 'epc', orec.epc, srec.epc);
        d(0, 'eavs', orec.eavs, srec.eavs);
        d(0, 'min', orec.minval, srec.minval);
        d(0, 'max', orec.maxval, srec.maxval);
        
        FOR i IN 1 .. greatest(orec.epc,srec.epc) LOOP
            d(i, 'bkvals', case when orec.bkvals.exists(i) then orec.bkvals(i) end, case when srec.bkvals.exists(i) then srec.bkvals(i) end);
            d(i, 'novals', case when orec.novals.exists(i) then orec.novals(i) end, case when srec.novals.exists(i) then srec.novals(i) end);
            d(i, 'chvals', case when orec.chvals.exists(i) then orec.chvals(i) end, case when srec.chvals.exists(i) then srec.chvals(i) end);
            $IF dbms_db_version.version > 11 $THEN
                d(i, 'eavals', case when orec.eavals.exists(i) then orec.eavals(i) end, case when srec.eavals.exists(i) then srec.eavals(i) end);
                d(i, 'rpcnts', case when orec.rpcnts.exists(i) then orec.rpcnts(i) end, case when srec.rpcnts.exists(i) then srec.rpcnts(i) end);
            $END
        END LOOP;
    
        IF counter > 0 THEN
            pr(chr(10));
        END IF;
    END;
BEGIN
    dbms_output.enable(NULL);
    load_stats(srec);
    --Modify column stats, following fields to be updated: EPC,BKVALS,NOVALS,EAVALS,MINVAL,MAXVAL
    IF input IS NOT NULL AND max_v IS NOT NULL THEN
        min_v := TRIM(input);
        IF dtype IN ('CHAR', 'NCHAR') THEN
            IF LENGTH(min_v) < 15 THEN
                min_v := rpad(min_v, 15);
            END IF;
            IF LENGTH(max_v) < 15 THEN
                max_v := rpad(max_v, 15);
            END IF;
        END IF;
        numval   := toNum(min_v);
        nrec.epc := 0;
        rawinput := CASE WHEN numval IS NULL THEN utl_raw.cast_to_raw(min_v) ELSE conr(NULL, numval) END;
        --For "NONE" histogram, support adjusting the low/high value
        IF histogram = 'NONE' THEN
            add_rec(min_v, numval, srec.bkvals(1), NULL, rawinput);
            numval := toNum(max_v);
            IF numval <= nrec.novals(1) THEN
                raise_application_error(-20001, 'High value "' || max_v || '" must be larger than low value "' || min_v || '"');
            END IF;
            rawinput := CASE WHEN numval IS NULL THEN utl_raw.cast_to_raw(max_v) ELSE conr(NULL, numval) END;
            add_rec(max_v, numval, srec.bkvals(2) - srec.bkvals(1), NULL, rawinput);
        ELSE
            IF bk_adj IS NULL THEN
                raise_application_error(-20001, 'Please input the 4th parameter as the buckets!');
            ELSIF histogram = 'HYBRID' AND bk_adj > 0 AND card_adj IS NULL THEN
                raise_application_error(-20001, 'Please input the 5th parameter as the repeat number!');
            END IF;
            IF srec.chvals IS NULL THEN
                srec.chvals := dbms_stats.chararray();
            END IF;
        
            other_adj := 0;
            prevb     := 0;
            FOR i IN 1 .. srec.epc LOOP
                buckets := srec.bkvals(i) - prevb;
                rpcnt   := 0;
                rawval  := NULL;
                max_v   := srec.chvals(i);
            
                $IF dbms_db_version.version > 11 $THEN
                    rpcnt  := srec.rpcnts(i);
                    rawval := srec.eavals(i);
                    max_v  := nvl(max_v, getv(rawval));
                $END
            
                IF dtype IN ('NUMBER', 'INTEGER', 'FLOAT', 'BINARY_FLOAT', 'BINARY_DOUBLE') THEN
                    max_v := NULL;
                END IF;
            
                IF other_adj = 0 AND bk_adj > 0 AND (min_v < TRIM(max_v) OR numval < srec.novals(i)) THEN
                    add_rec(min_v, numval, bk_adj, card_adj, rawinput);
                    other_adj := bk_adj;
                    add_rec(nvl(srec.chvals(i), max_v), srec.novals(i), buckets, rpcnt, rawval);
                ELSIF min_v = TRIM(max_v) OR numval = srec.novals(i) THEN
                    IF bk_adj = 0 THEN
                        --remove entry
                        other_adj := -buckets;
                    ELSE
                        add_rec(nvl(srec.chvals(i), max_v),
                                srec.novals(i),
                                bk_adj,
                                coalesce(card_adj, rpcnt, 1),
                                rawval);
                        other_adj := nullif(bk_adj - buckets, 0);
                    END IF;
                ELSE
                    add_rec(nvl(srec.chvals(i), max_v), srec.novals(i), greatest(buckets, 1), rpcnt, rawval);
                END IF;
                prevb := srec.bkvals(i);
            END LOOP;
            --in case of input > high_value
            IF nrec.epc > 0 AND other_adj = 0 AND bk_adj > 0 THEN
                add_rec(min_v, numval, bk_adj, card_adj, rawinput);
            END IF;
        END IF;
    
        /* PREPARE_COLUMN_VALUES:
                1) epc(=input_array.count) must > 1
                2) bkvals are delta values except "HYBRID"
           * HEIGHT BALANCED: bkvals is null + duplicate EPs(novals/chvals/eavals) as popular EP
           * HYBRID         : bkvals is not null + unique EP values + all values of rptcnts > 0, rptcnts(1) = bkvals(1), exchange rpcnts and  bkvals
           * FREQUENCY      : bkvals is not null + unique EP values + rptcnts is null or rptcnts(1)=0
           * TOP-FREQUENCY  : bkvals is not null + unique EP values + rptcnts is null or rptcnts(1)=0
           * NONE           : epc = 2, bkvals(1) = 0, bkvals(1) = 1
        
           SET_COLUMN_STATS:
                1) All EPs(novals/chvals/bkvals/etc) are unique
                2) bkvals are incremental values
                3) novals.count=epc
                4) evas=4 means also refer to the values of eavals(specially for string data type)
           * HYBRID         : all values inside rptcnts > 0, bkvals(epc)=sample_size, rptcnts(1) = bkvals(1)
           * Others         : rptcnts is null or all values inside rptcnts = 0
                * HEIGHT BALANCED : bkvals(1) = 0, bkvals(1) > 1
                * FREQUENCY       : bkvals(1) > 0
                * TOP-FREQUENCY   : bkvals(1) > 0, BITAND(srec.eavs,dbms_stats_internal.DSC_HIST_TOPFREQ)>0
                * NONE            : epc = 2, bkvals(1) = 0, bkvals(1) = 1
        
        */
        IF nrec.epc > 1 THEN
            load_stats(orec);
            srec.epc    := nrec.epc;
            srec.bkvals := nrec.bkvals;
            CASE HISTOGRAM
                WHEN 'HYBRID' THEN
                    NULL;
                WHEN 'HEIGHT BALANCED' THEN
                    srec.bkvals := NULL;
                ELSE
                    NULL;
            END CASE;
        
            $IF dbms_db_version.version > 11 $THEN
                srec.rpcnts := nrec.rpcnts;
                srec.eavals := nrec.eavals;
            $END
        
            IF dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'NVARCHAR2', 'NCHAR', 'NCLOB', 'ROWID', 'UROWID') THEN
                srec.eavs := 4; --DBMS_STATS_INTERNAL.DSC_EAVS
                dbms_stats.prepare_column_values(srec, nrec.chvals);
            ELSE
                dbms_stats.prepare_column_values(srec, nrec.novals);
            
                $IF dbms_db_version.version > 11 $THEN
                    srec.eavals := nrec.eavals;
                $END
                srec.minval := conr(1);
                srec.maxval := conr(srec.epc);
                --srec.eavs   := null;
            END IF;
            
            calc_density;
            diff;
            IF is_test =1 THEN
                to_script(srec);
                RETURN;
            END IF;

            srec.eavs := nrec.eavs;
            
            --set stats for restoration
            restoret := TO_CHAR(systimestamp - numtodsinterval(1, 'second'), tztampfmt);

            --calc the density of "HEIGHT BALANCED" since newDensity(10053) is not used after setting
            
            DBMS_STATS.SET_COLUMN_STATS(ownname       => oname,
                                        tabname       => tab,
                                        partname      => part,
                                        colname       => col,
                                        srec          => srec,
                                        density       => densityn, 
                                        no_invalidate => FALSE,
                                        force         => TRUE,
                                        statown       => statown,
                                        stattab       => stattab);
            load_stats(srec);
        
            IF is_test = 0 THEN
                is_test := 1;
            END IF;
        ELSIF nrec.epc > 0 AND nrec.epc < 2 THEN
            raise_application_error(-20001, 'Cannot set the histogram as only having one EP value!');
        END IF;
    END IF;

    calc_density;

    pr(rpad('=', 120, '='));
    pr('Column-Name: ' || col || '   Data-Type: ' || dtypefull || '   Analyzed: ' || nvl(to_char(analyzed, datefmt),'N/A') || '   Global-Stats: ' || gstats || '   User-Stats: ' || ustats);
    pr(utl_lms.format_message('Histogram  : "%s"   Low-Value: "%s"   High-Value: "%s"', histogram, TRIM(getv(srec.minval)), TRIM(getv(srec.maxval))));
    pr(to_header('Rows', getNum(numrows), '') || to_header('Samples', getNum(samples)) ||
       to_header('Nulls', getNum(nullcnt)) || to_header('Distincts', getNum(distcnt)) ||
       
       to_header('Blocks', getNum(numblks), chr(10)) || to_header('Buckets', getNum(numbcks)) ||
       to_header('Avg Row Len', avgrlen) || to_header('Avg Col Len', avgclen) ||
       
       to_header('Rows/Block', ROUND(numrows / NULLIF(numblks, 0), 2), chr(10)) ||
       to_header('Density', to_char(density * 100, 'fm99990.09999') || '%') ||
       to_header('New-Density', to_char(densityn * 100, 'fm99990.09999') || '%') ||
       to_header('Cardinality', getNum(ROUND(notnulls * densityn, 2))));
    pr(rpad('=', 120, '='));

    pr(rpad(' ', 74));
    pr('    #','Bucket#',rpad('Prev EP Value', dlen),rpad('Current EP Value', dlen),lpad('Buckets', 10),lpad('Card', 8),lpad(CASE WHEN is_test = 2 THEN 'Real' ELSE 'RealCard' END, 8));
    pr('-----',rpad('-', 7, '-'),rpad('-', dlen, '-'),rpad('-', dlen, '-'),rpad('-', 10, '-'),rpad('-', 8, '-'),rpad('-', 8, '-'));

    prevb := 0;
    --compute estimated cardinality
    FOR i IN 1 .. srec.epc LOOP
        buckets := greatest(srec.bkvals(i) - prevb, 1);
        max_v   := '';
        CASE histogram
            WHEN 'HEIGHT BALANCED' THEN
                IF buckets > pop_based THEN
                    --popular value
                    IF i != srec.epc THEN
                        rpcnt := notnulls * buckets / numbcks;
                    ELSE
                        rpcnt := notnulls * (buckets - 0.5) / numbcks;
                    END IF;
                ELSE
                    --un-popular value
                    rpcnt := notnulls * densityn;
                END IF;
            WHEN 'HYBRID' THEN
                NULL;
                $IF dbms_db_version.version>11 $THEN
                    max_v  := nullif('(' || nullif(srec.rpcnts(i), 0) || ')', '()');
                    bk_adj := nullif(srec.rpcnts(i), 0) * notnulls / samples; --sample_size has excluded null values
                    IF srec.rpcnts(i) < pop_based THEN
                        bk_adj := greatest(bk_adj, notnulls * densityn);
                    END IF;
                    rpcnt := nvl(bk_adj, rpcnt);
                $END
            WHEN 'NONE' THEN
                rpcnt := densityn * notnulls;
            WHEN 'FREQUENCY' THEN
                 /*
                    NewDensity with the "half the least popular" rule active
                    NewDensity is set to
                    NewDensity = 0.5 * bkt(least_popular_value) / num_rows
                    and hence, for non-existent values:
                    E[card] = (0.5 * bkt(least_popular_value) / num_rows) * num_rows = 0.5 * bkt(least_popular_value)
                */
                IF i != srec.epc THEN
                    rpcnt := buckets * notnulls / samples;
                ELSE
                    rpcnt := (buckets - 0.5) * notnulls / samples;
                END IF;
            ELSE
                rpcnt := buckets * notnulls / samples;
        END CASE;
    
        cep := srec.chvals(i);
        pr(lpad(i, 5),
           lpad(srec.bkvals(i), 7),
           rpad(pep, dlen),
           rpad(cep, dlen),
           lpad(buckets || max_v, 10),
           lpad(NVL('' || getNum(rpcnt), ' '), 8),
           lpad(CASE WHEN is_test > 0 THEN getNum(get_card(cep)) END, 8));
        pep   := cep;
        prevb := srec.bkvals(i);
    END LOOP;
    pr(chr(10));

    to_script(srec);

    IF stattab IS NOT NULL THEN
        pr('  * Note:  The values of field "Card" are based on the statistics of the input stats table.');
        IF is_test = 1 THEN
            pr('  * Note:  The values of field "RealCard" are based on the statistics of target table, not the input stats table!');
        END IF;
    END IF;

    IF input IS NOT NULL THEN
        pr('  * Note:  Cardinality of input predicate "' || input || '" is ' || get_card(input)||'.');
        IF stattab IS NOT NULL THEN
            pr('           This estimation is based on the statistics on the table, not the input stats table!');
        END IF;
    END IF;

    IF restoret IS NOT NULL THEN
        IF stattab IS NULL THEN
            pr('  * Note:  The original statistics can be restored by:');
            pr('               DECLARE');
            pr('                   t VARCHAR2(64) := ''' || restoret || ''';');
            pr('                   f VARCHAR2(64) := ''' || tztampfmt || ''';');
            pr('               BEGIN');
            pr(utl_lms.format_message(q'[                   dbms_stats.restore_table_stats('%s','%s',to_timestamp_tz(t,f),force=>true,no_invalidate=>false);]',oname,tab));
            pr('               END;');
            IF ttype='TABLE' THEN
                pr(utl_lms.format_message(q'[           Or consider locking the statistics by: exec dbms_stats.lock_table_stats('%s','%s');]',oname, tab));
            ELSE
                pr(utl_lms.format_message(q'[           Or consider locking the statistics by: exec dbms_stats.lock_partition_stats('%s','%s','%s');]',oname, tab,part));
            END IF;
        ELSE
            pr('  * Note:  The statistics have been updated into "'||statown||'"."'||stattab||'", can take affect into the target table by:');
            pr(utl_lms.format_message(q'[               exec dbms_stats.import_column_stats('%s','%s','%s','%s',statown=>'%s',stattab=>'%s');]',oname,tab,col,part,statown,stattab));
        END IF;
    END IF;
END;
/

pro 
save script_text &V1..&V2..sql