/*[[
Show/change column histogram. Usage: @@NAME {<table_name>[.<partition_name>] <column_name>} {<test_value> | <min_v> <max_v> | <value> <buckets> [<card>]} [-test|-real] [-tab"<stats_tab>"]
Options:
    -test: use "EXPLAIN PLAN" to test the cardinality of each EP value. In case of setting histograms, this option will skip the changes
    -real: use "SELECT COUNT(1)" to test the real count of each EP value
    -tab : use stats table as the data source/target

Examples:
    *  List the histogram: @@NAME SYS.OBJ$ NAME
    *  List the histogram from the stats table: @@NAME SYS.OBJ$ NAME -tab"system.stattab"
    *  List the histogram and test the est cardinality of scalar value : @@NAME SYS.OBJ$ NAME "obj$"
    *  List histogram and test est cardinality of customized filter: @@NAME SYS.OBJ$ NAME "> 'obj$'" (space after operator is required)
    *  List the histogram and test the est cardinality of bind variable: @@NAME SYS.OBJ$ NAME :1
    *  List the histogram and test the est cardinality of each EP value: @@NAME SYS.OBJ$ NAME -test
    *  List the histogram and test the act cardinality of each EP value: @@NAME SYS.OBJ$ NAME -real
    *  Change the low/high value of "NONE" histogram:  @@NAME sys.obj$ stime "1990-08-26 11:25:01" "2018-08-12 02:50:00"
    *  Set number of buckets of "FREQUENCY" histogram: @@NAME sys.obj$ owner# 89 5
    *  Remove an EP from histogram: @@NAME sys.obj$ owner# 89 0
    *  Set number of buckets and repeats of "HYBRID" histogram: @@NAME obj$ NAME sun/misc/Lock 295 10

Notes: if input data type is not string/number/raw, the value should follow below format:
    *  DATE                    : YYYY-MM-DD HH24:MI:SS
    *  TIMESTAMP               : YYYY-MM-DD HH24:MI:SSxFF
    *  TIMESTAMP WITH TIME ZONE: display only, it cannot be used as an input value

Sample Output:
==============
ORCL> ora histogram sys.obj$ OWNER#                                                                                         
    Histogram of TABLE SYS.OBJ$[OWNER#]                                                                                     
    ========================================================================================================================
    Column-Name: OWNER#   Data-Type: NUMBER   Analyzed: 2015-07-20 22:05:00   Global-Stats: YES   User-Stats: NO            
    Histogram  : "FREQUENCY"   Low-Value: "0"   High-Value: "88"                                                            
    Rows       : 537K          Samples    : 5809          Nulls      : 0             Distincts  : 27                        
    Blocks     : 7192          Buckets    : 5809          Avg Row Len: 91            Avg Col Len: 3                         
    Rows/Block : 74.77         Density    : 0.00009%      New-Density: 3.7037%       Cardinality: 19916                     
    ========================================================================================================================
                                                                                                                            
         #  Bucket#  Prev EP Value     Current EP Value     Buckets     Card                                                
     -----  -------  ----------------  ----------------  ---------- --------                                                
         1      104                    0                        104  9627.33                                                
         2      156  0                 1                         52  4813.67                                                
         3      160  1                 5                          4   370.28                                                
         4      165  5                 32                         5   462.85                                                
         5      175  32                34                        10    925.7                                                
         6      191  34                42                        16  1481.13                                                
      .....                                              
                                                                                                                            
    Data saved to D:\dbcli\cache\orcl\sys.obj$.OWNER#.sql                                                                   

    --[[
        &test  : default={0} test={1} real={2}
        &name  : default={card2} test={RealCard} real={RealCount}
        &tab   : default={} tab={&0}
        @CHECK_ACCESS_DBA: DBA_TAB_COLS/DBA_PART_COL_STATISTICS={DBA_} DEFAULT={ALL_}
        @ARGS: 2
    --]]
]]*/
SET FEED OFF SERVEROUTPUT ON VERIFY OFF
var stats_owner varchar2
var stats_tab   varchar2
var script_text CLOB; --The variable to store the SQL*Plus script
var result      REFCURSOR
var outs        VARCHAR2
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
    ttype     VARCHAR2(128) := :object_type;
    statown   VARCHAR2(128) := :stats_owner;
    stattab   VARCHAR2(128) := :stats_tab;
    col       VARCHAR2(128) := upper(:V2);
    input     VARCHAR2(128) := :V3;
    max_v     VARCHAR2(4000) := :V4;
    card_adj  NUMBER        := regexp_substr(:V5, '^\d+$');
    bk_adj    NUMBER        := regexp_substr(max_v, '^\d+$');
    other_adj NUMBER        := 0;
    datefmt   VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SS';
    tstampfmt VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SSxff';
    tztampfmt VARCHAR2(32)  := tstampfmt || ' TZH:TZM';
    rawfmt    VARCHAR2(32)  := 'fm' || lpad('x', 30, 'x');
    min_v     VARCHAR2(128);
    restoret  VARCHAR2(128);
    outs      VARCHAR2(32767);
    rawinput  RAW(2000);
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
    adjnnull  NUMBER;
    avgrlen   NUMBER;
    samples   NUMBER;
    rpcnt     NUMBER;
    adjcnt    NUMBER;
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
    test_stmt VARCHAR2(1000);
    cep       VARCHAR2(4000);
    pep       VARCHAR2(4000) := lpad(' ', 32);
    gstats    VARCHAR2(3);
    ustats    VARCHAR2(3);
    flags     PLS_INTEGER;
    dlen      PLS_INTEGER;
    buckets   NUMBER;
    minb      NUMBER;
    prevb     NUMBER   := 0;
    prevv     NUMBER   := 0;
    cnt       PLS_INTEGER   := 0;
    pops      PLS_INTEGER   := 0;
    pop_based NUMBER        := 0;
    result    XMLTYPE       := XMLTYPE('<RESULT/>');
    --convert all_tab_histograms.enpoint_value as varchar2
    --refer to https://mwidlake.wordpress.com/2009/08/11/decrypting-histogram-data/
    FUNCTION hist_numtochar(p_num NUMBER, p_trunc VARCHAR2 := 'Y',p_len INT:=NULL) RETURN VARCHAR2 IS
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
                m_n1 := trunc(m_n / power(256, 15 - i));
                IF m_n1 != 0 THEN
                    BEGIN
                        m_vc := m_vc || chr(m_n1);
                    EXCEPTION WHEN OTHERS THEN
                        NULL;
                    END;
                END IF;
                m_n := m_n - (m_n1 * power(256, 15 - i));
            END LOOP;
        END IF;
        IF p_len IS NOT NULL THEN
            RETURN substr(m_vc,1,p_len);
        END IF;
        RETURN m_vc;
    END;

    --BINARY_FLOAT/DOUBLE raws inside histgrm$/statrec are not plain IEEE bytes but the
    --sortable T-map of them: sign-clear x -> x XOR 0x8000..0, sign-set x -> NOT x. The
    --map is its own inverse, and dbms_stats.convert_raw_value already applies it when
    --decoding, so restore scripts and conr() must re-encode with it: set_column_stats
    --stores srec raws byte for byte, a plain IEEE literal would corrupt the histogram.
    FUNCTION bfraw(b binary_float) RETURN RAW IS
        h VARCHAR2(16) := rawtohex(utl_raw.cast_from_binary_float(b));
    BEGIN
        IF substr(h, 1, 1) >= '8' THEN
            RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('FFFFFFFF'));
        END IF;
        RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('80000000'));
    END;

    FUNCTION bdraw(b binary_double) RETURN RAW IS
        h VARCHAR2(32) := rawtohex(utl_raw.cast_from_binary_double(b));
    BEGIN
        IF substr(h, 1, 1) >= '8' THEN
            RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('FFFFFFFFFFFFFFFF'));
        END IF;
        RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('8000000000000000'));
    END;

    --readable text of a float: to_char with TM turns NaN/Infinity into '####', so name
    --the specials (exponent all ones) explicitly; the spellings parse back via
    --to_binary_float/to_binary_double and re-encode byte for byte (canonical forms)
    FUNCTION bf2txt(b binary_float) RETURN VARCHAR2 IS
        x RAW(4) := utl_raw.cast_from_binary_float(b);
        h VARCHAR2(16) := rawtohex(x);
    BEGIN
        IF utl_raw.bit_and(x, hextoraw('7F800000')) = hextoraw('7F800000') THEN
            IF utl_raw.bit_and(x, hextoraw('007FFFFF')) = hextoraw('00000000') THEN
                RETURN CASE WHEN substr(h, 1, 1) >= '8' THEN '-Infinity' ELSE 'Infinity' END;
            END IF;
            RETURN 'NaN';
        END IF;
        RETURN to_char(b, 'TM');
    END;

    FUNCTION bd2txt(b binary_double) RETURN VARCHAR2 IS
        x RAW(8) := utl_raw.cast_from_binary_double(b);
        h VARCHAR2(32) := rawtohex(x);
    BEGIN
        IF utl_raw.bit_and(x, hextoraw('7FF0000000000000')) = hextoraw('7FF0000000000000') THEN
            IF utl_raw.bit_and(x, hextoraw('000FFFFFFFFFFFFF')) = hextoraw('0000000000000000') THEN
                RETURN CASE WHEN substr(h, 1, 1) >= '8' THEN '-Infinity' ELSE 'Infinity' END;
            END IF;
            RETURN 'NaN';
        END IF;
        RETURN to_char(b, 'TM');
    END;

    --onvert all_tab_histograms.enpoint_value that defined in srec as varchar2
    FUNCTION conv(idx PLS_INTEGER, num NUMBER := NULL,p_len INT:=NULL) RETURN VARCHAR2 IS
        rtn NUMBER := nvl(NUM, CASE WHEN idx IS NOT NULL THEN srec.novals(idx) END);
        eva RAW(2000);
        res VARCHAR2(4000);
        bf  binary_float;
        bd  binary_double;
    BEGIN
        $IF dbms_db_version.version > 11 $THEN
            IF idx IS NOT NULL THEN
                eva := srec.eavals(idx);
            END IF;
        $END
        CASE
            WHEN idx IS NOT NULL AND srec.chvals.exists(idx) AND srec.chvals(idx) IS NOT NULL THEN
                res := RTRIM(srec.chvals(idx));
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'ROWID', 'UROWID') THEN
                res := nvl(utl_raw.cast_to_varchar2(eva), hist_numtochar(rtn,'Y',p_len));
            WHEN dtype IN ('NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                res := nvl(utl_raw.cast_to_nvarchar2(eva), hist_numtochar(rtn,'Y',p_len));
            WHEN dtype = 'BINARY_DOUBLE' THEN
                --eavals keeps the true value while novals collapses Infinity/NaN to the
                --number range, so decode the raw when there is one
                IF eva IS NOT NULL THEN
                    dbms_stats.convert_raw_value(eva, bd);
                    res := bd2txt(bd);
                ELSE
                    res := TO_CHAR(TO_BINARY_DOUBLE(rtn), 'TM');
                END IF;
            WHEN dtype = 'BINARY_FLOAT' THEN
                IF eva IS NOT NULL THEN
                    dbms_stats.convert_raw_value(eva, bf);
                    res := bf2txt(bf);
                ELSE
                    res := TO_CHAR(TO_BINARY_FLOAT(rtn), 'TM');
                END IF;
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                res := to_char(rtn, 'TM');
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                tstamp := to_timestamp('' || TRUNC(rtn), 'J');
                IF MOD(rtn, 1) = 0 THEN
                    RETURN to_char(tstamp, substr(datefmt, 1, 10));
                END IF;
                IF dtype = 'DATE' THEN
                    res := to_char(tstamp + MOD(rtn, 1), datefmt);
                ELSE
                    res := TRIM(trailing '0' FROM to_char(tstamp + NUMTODSINTERVAL(MOD(rtn, 1) * 86400, 'SECOND'), tstampfmt));
                END IF;
            ELSE
                res := substr(to_char(rtn, rawfmt), 1, 16);
        END CASE;
        RETURN REGEXP_REPLACE(res, '[^[:print:]]', '');
    END;

    --convert the value in srec into raw value
    FUNCTION conr(idx PLS_INTEGER, num NUMBER := NULL,p_len INT:=NULL) RETURN RAW IS
        rtn VARCHAR2(4000) := conv(idx, num,p_len);
        d   TIMESTAMP;
        ns  NUMBER;
    BEGIN
        CASE
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'ROWID', 'UROWID', 'NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                RETURN utl_raw.cast_to_raw(rtn);
            WHEN dtype = 'BINARY_DOUBLE' THEN
                RETURN bdraw(to_binary_double(rtn));
            WHEN dtype = 'BINARY_FLOAT' THEN
                RETURN bfraw(to_binary_float(rtn));
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                RETURN utl_raw.cast_from_number(to_number(rtn));
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                d   := to_timestamp(rtn, tstampfmt);
                ns  := to_number(to_char(d, 'ff9'));
                --extract(second) carries the fraction and to_char(number,'xx') rounds it,
                --so take the already truncated parts from the format elements instead
                rtn := lpad(to_char(floor(to_number(to_char(d, 'SYYYY')) / 100) + 100, 'fmxx'), 2, '0') ||
                       lpad(to_char(mod(to_number(to_char(d, 'SYYYY')), 100) + 100, 'fmxx'), 2, '0') ||
                       lpad(to_char(to_number(to_char(d, 'MM')), 'fmxx'), 2, '0') ||
                       lpad(to_char(to_number(to_char(d, 'DD')), 'fmxx'), 2, '0') ||
                       lpad(to_char(to_number(to_char(d, 'HH24')) + 1, 'fmxx'), 2, '0') ||
                       lpad(to_char(to_number(to_char(d, 'MI')) + 1, 'fmxx'), 2, '0') ||
                       lpad(to_char(to_number(to_char(d, 'SS')) + 1, 'fmxx'), 2, '0');
                IF dtype != 'DATE' AND ns != 0 THEN
                    --Oracle omits the 4 nanosecond bytes entirely when the fraction is zero
                    rtn := rtn || lpad(to_char(ns, 'fmxxxxxxxx'), 8, '0');
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

    PROCEDURE wr(msg VARCHAR2) IS
    BEGIN
        outs := outs || msg || chr(10);
    END;

    PROCEDURE pr(v1 VARCHAR2, v2 VARCHAR2, v3 VARCHAR2, v4 VARCHAR2, v5 VARCHAR2, v6 VARCHAR2, v7 VARCHAR2, v8 VARCHAR2) IS
        x7 VARCHAR2(128) := v7;
        elem XMLTYPE;
    BEGIN
        /*
        IF is_test = 0 THEN
            x7 := '';
        END IF;*/

        SELECT XMLELEMENT("BUCKET",
                      XMLELEMENT("seq", v1),
                      XMLELEMENT("bno", v2),
                      XMLELEMENT("prev", v3),
                      XMLELEMENT("curr", v4),
                      XMLELEMENT("buckets", v5),
                      XMLELEMENT("card", v6),
                      XMLELEMENT("adj", v7),
                      XMLELEMENT("card2", v8))
            INTO   ELEM
            FROM   DUAL;

        result := result.APPENDCHILDXML('/*', ELEM);
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
        n    NUMBER;
        c    VARCHAR2(4000);
        nc   NVARCHAR2(2000);
        bf   binary_float;
        bd   binary_double;
        d    DATE;
        ts   TIMESTAMP;
        r    ROWID;
        ofs  NUMBER;
        hex  VARCHAR2(4000) := rawtohex(val);
        frac VARCHAR2(20);
    BEGIN
        IF val IS NULL THEN
            RETURN NULL;
        END IF;
        CASE
            WHEN dtype IN ('NUMBER', 'INTEGER', 'FLOAT') THEN
                dbms_stats.convert_raw_value(val, n);
                RETURN to_char(n, 'tm');
            WHEN dtype = 'BINARY_FLOAT' THEN
                dbms_stats.convert_raw_value(val, bf);
                RETURN bf2txt(bf);
            WHEN dtype = 'BINARY_DOUBLE' THEN
                dbms_stats.convert_raw_value(val, bd);
                RETURN bd2txt(bd);
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB') THEN
                dbms_stats.convert_raw_value(val, c);
                RETURN c;
            WHEN dtype IN ('NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                dbms_stats.convert_raw_value_nvarchar(val, nc);
                RETURN nc;
            WHEN dtype IN ('ROWID', 'UROWID') THEN
                dbms_stats.convert_raw_value_rowid(val, r);
                RETURN r;
            WHEN dtype = 'DATE' THEN
                dbms_stats.convert_raw_value(val, d);
                RETURN to_char(d, datefmt);
            WHEN dtype = 'TIMESTAMP' THEN
                --dbms_stats has no timestamp overload, and convert_raw_value(val, DATE)
                --truncates the fractional seconds, so decode the trailing bytes here
                dbms_stats.convert_raw_value(utl_raw.substr(val, 1, 7), d);
                frac := nullif('.' || rtrim(substr(lpad(to_number(substr(hex, 15, 8), 'xxxxxxxx'), 9, '0'), 1, 9), '0'), '.');
                IF dtypefull LIKE '%TIME ZONE' AND dtypefull NOT LIKE '%LOCAL%' THEN
                    --WITH TIME ZONE stores the 7 date bytes in UTC and the zone offset in
                    --the last 2 bytes as (hour + 20, minute + 60)
                    ofs := (to_number(substr(hex, 23, 2), 'xx') - 20) * 60 + to_number(substr(hex, 25, 2), 'xx') - 60;
                    ts  := to_timestamp(to_char(d, datefmt), datefmt) + numtodsinterval(ofs, 'MINUTE');
                    RETURN to_char(ts, datefmt) || frac || ' ' || CASE WHEN ofs < 0 THEN '-' ELSE '+' END ||
                           to_char(trunc(abs(ofs) / 60), 'fm00') || ':' || to_char(mod(abs(ofs), 60), 'fm00');
                END IF;
                RETURN to_char(d, datefmt) || frac;
            ELSE
                RETURN hex;
        END CASE;
    END;

    --convert the value into endpoint_value
    FUNCTION toNum(input VARCHAR2) RETURN NUMBER IS
    BEGIN
        CASE
            WHEN dtype IN ('NUMBER', 'INTEGER', 'FLOAT', 'BINARY_FLOAT', 'BINARY_DOUBLE') THEN
                RETURN to_number(input);
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'NVARCHAR2', 'NCHAR', 'NCLOB', 'ROWID', 'UROWID') THEN
                RETURN NULL;
            WHEN dtype = 'DATE' THEN
                dateval := to_date(input, datefmt);
                RETURN to_char(dateval, 'J') +(dateval - trunc(dateval));
            WHEN dtype = 'TIMESTAMP' AND dtypefull NOT LIKE '%TIME ZONE' THEN
                tstamp := to_timestamp(input, tstampfmt);
                RETURN to_char(tstamp, 'J') +(tstamp + 0 - trunc(tstamp + 0)) + to_char(tstamp, '"0"xff') / 86400;
            ELSE
                raise_application_error(-20001, 'Unsupported data type: ' || dtypefull);
        END CASE;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                RAISE;
            END IF;
            raise_application_error(-20001, 'Conversion error from value "' || input || '" to the "' || dtypefull || '" data type!');
    END;

    --get the cardinality of a specific predicate
    FUNCTION get_card(val VARCHAR2) RETURN VARCHAR2 IS
        val1     VARCHAR2(4000)   := rtrim(val);
        str      VARCHAR2(4002)   := CASE WHEN val1 LIKE ':%' THEN val1 ELSE '''' || val1 || '''' END;
        target   VARCHAR2(32767);
        test_val VARCHAR2(32767);
        stmt     VARCHAR2(32767);
        rtn      NUMBER;
        pred     VARCHAR2(2000);
    BEGIN
        IF test_stmt IS NULL THEN
            target := '"' || oname || '"."' || tab || '"';
            IF ttype LIKE '% SUBPARTITION' THEN
                target := target || ' SUBPARTITION(' || part || ')';
            ELSIF ttype LIKE '% PARTITION' THEN
                target := target || ' PARTITION(' || part || ')';
            END IF;
            IF is_test = 2 THEN
                test_stmt := 'select /*+parallel(a 8)*/ count(1)';
            ELSE
                test_stmt := 'explain plan set statement_id=''' || stmt_id || ''' INTO SYS.PLAN_TABLE$ for select /*+no_parallel(a) cursor_sharing_exact no_index(a) full(a)*/ *';
            END IF;
            test_stmt := test_stmt || ' from ' || target || ' a where "' || col || '"';
        END IF;
        stmt := test_stmt;
        
        pred := nvl(upper(regexp_substr(val1,'^\s*(\S+)',1,1)),'x');
        IF pred NOT IN('BETWEEN','IN','EXISTS','NOT','>','<','=','>=','<=','!=','<>') THEN
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
            test_val :=  '='|| test_val;
        ELSE
            --a custom predicate, append it to a copy so the cached prefix stays reusable
            stmt := stmt || val1;
        END IF;
    
        IF is_test = 2 THEN
            EXECUTE IMMEDIATE stmt || test_val INTO rtn;
        ELSE
            SAVEPOINT test_card;
            DELETE SYS.PLAN_TABLE$ a WHERE a.statement_id = stmt_id;
            EXECUTE IMMEDIATE stmt || test_val;
            --id=0 is the root line and holds the estimate for the whole statement;
            --ROWNUM<2 would take whichever line happened to come back first
            SELECT MAX(a.cardinality)
            INTO   rtn
            FROM   SYS.PLAN_TABLE$ a
            WHERE  a.statement_id = stmt_id
            AND    a.id = 0;
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
                raise_application_error(-20001, 'You don''t have access to "' || oname || '"."' || tab || '"!');
            ELSE
                --raise_application_error caps its message at 2048 bytes
                raise_application_error(-20001, substr(SQLERRM || ': ' || stmt || test_val, 1, 2000));
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
            BktCnt     = MAX(EP_number)
            Buckets    = current_EP_number - previous_EP_number, but on a HYBRID it is
                         the EP's repeat count, which does not add up to BktCnt
            NewDensity (the density the optimizer really applies) per histogram type:
                HEIGHT BALANCED: (1-PopBktCnt/BktCnt)/(NDV-PopValCnt), a popular EP is one
                                 whose Buckets > 1
                HYBRID         : (1-PopBktCnt/BktCnt)/(NDV-PopValCnt), a popular EP is one
                                 whose Buckets > BktCnt/#EPs
                FREQUENCY      : 0.5 * MIN(Buckets) / BktCnt, the "half the least popular
                                 value" rule
                TOP-FREQUENCY  : (NumRows-BktCnt)/((NDV-#EPs)*NumRows), the rows the
                                 histogram does not account for spread over the values it
                                 did not capture
                NONE           : 1/NDV
        
        */
        numbcks := srec.bkvals(srec.epc);
        numrows := greatest(numrows, 1);
        samples := nvl(NULLIF(samples, 0), numrows);
        numbcks := NULLIF(numbcks, 0);
        cnt     := 0;
        pops    := 0;
        minb    := NULL;
        prevb   := 0;
        dlen    := 16;

        CASE histogram
            WHEN 'HEIGHT BALANCED' THEN
                pop_based := 1;
            WHEN 'HYBRID' THEN
                pop_based := numbcks / srec.epc;
            ELSE
                pop_based := NULL;
        END CASE;
    
        FOR i IN 1 .. srec.epc LOOP
            --fill_arrays always starts a non-FREQUENCY array at bkvals(1)=0, so the raw
            --delta of EP#1 is 0; clamp it like the display loop does or a zero leaks into
            --minb and zeroes out the FREQUENCY NewDensity
            buckets := greatest(srec.bkvals(i) - prevb, 1);
            srec.chvals(i) := rtrim(conv(i));
            dlen := greatest(dlen, length(srec.chvals(i)));
            $IF dbms_db_version.version>11 $THEN
                IF histogram = 'HYBRID' THEN
                    buckets := nvl(srec.rpcnts(i), 0);
                END IF;
            $END
            minb := least(nvl(minb, buckets), buckets);
            IF buckets > pop_based THEN
                cnt  := cnt + 1;
                pops := pops + buckets;
            END IF;
            prevb := srec.bkvals(i);
        END LOOP;
    
        IF histogram = 'TOP-FREQUENCY' THEN
            densityn := coalesce((numrows - numbcks) / nullif((distcnt - srec.epc) * numrows, 0), density);
        ELSIF histogram = 'FREQUENCY' THEN
            densityn := coalesce(0.5 * minb / numbcks, density);
        ELSE
            densityn := coalesce((1 - pops / numbcks) / nullif(distcnt - cnt, 0), density);
        END IF;
    END;

    PROCEDURE reset_Rec(rec IN OUT NOCOPY DBMS_STATS.STATREC) IS
    BEGIN
        IF rec.chvals IS NULL THEN
            rec.chvals := dbms_stats.chararray();
        END IF;
        --epc moves in both directions: it grows when an EP is added and shrinks when
        --prepare_column_values merges duplicates through RESIZE_ARRAYS
        rec.chvals.extend(greatest(rec.epc - rec.chvals.count, 0));
        rec.chvals.trim(greatest(rec.chvals.count - rec.epc, 0));
    
        $IF dbms_db_version.version > 11 $THEN
            IF rec.eavals IS NULL THEN
                rec.eavals := dbms_stats.rawarray();
            END IF;
            IF rec.rpcnts IS NULL THEN
                rec.rpcnts := dbms_stats.numarray();
            END IF;
            rec.eavals.extend(greatest(rec.epc - rec.eavals.count, 0));
            rec.rpcnts.extend(greatest(rec.epc - rec.rpcnts.count, 0));
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

            SELECT max(nvl(histogram,'NONE')),sum(samples),max(last_analyzed),max(gstats),max(ustats)
            INTO   histogram, samples, analyzed, gstats, ustats
            FROM   (SELECT histogram,
                           nvl2(num_buckets, nvl(sample_size, 0), NULL) samples,
                           last_analyzed,
                           global_stats gstats,
                           user_stats   ustats
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
                           global_stats gstats,
                           user_stats   ustats
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
                           global_stats gstats,
                           user_stats   ustats
                    FROM   &CHECK_ACCESS_DBA.tab_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    ttype='TABLE'
                    ORDER  BY 1 NULLS LAST) a
            WHERE ROWNUM<2;
            
            dtype    := regexp_substr(dtypefull, '^\w+');
            adjnnull := nvl(samples,0);
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
                    raise_application_error(-20001, 'You don''t have access to "' || statown || '"."' || stattab || '"!');
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

            IF notnulls-distcnt<0 THEN
                dbms_output.put_line('Note: The result could be incorrect due to '||lower(ttype)||'(num_rows) < column(num_null + num_distinct).');
            END IF;

            IF adjnnull > 0 and adjnnull != notnulls and adjnnull>=distcnt THEN
                IF adjnnull < notnulls THEN
                    --scale the sampled non-null rows up to the whole table
                    adjnnull := adjnnull*numrows/(adjnnull+nullcnt);
                END IF;
            ELSE
                adjnnull :=null;
            END IF;

            IF flags > 0 AND bitand(rec.eavs,flags) = 0 THEN
                rec.eavs := rec.eavs + flags;
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
        aw   PLS_INTEGER;
        --to_char's nlsparam argument is unusable for numbers in PL/SQL, so sniff the session
        --decimal separator and normalize it: TM never emits a group separator
        dec  VARCHAR2(1) := substr(to_char(1.5, 'tm'), 2, 1);
        --novals round-trip verification scratch space; declared before the first subprogram
        --because item declarations cannot follow a subprogram declaration
        cfmt VARCHAR2(30);
        dfmt VARCHAR2(30);
        expr VARCHAR2(2000);
        dtmp DATE;
        --full fractional-second precision: the default TIMESTAMP(6) truncates the
        --nanosecond bytes when re-emitting the decoded text, silently corrupting the raw
        ts   TIMESTAMP(9);
        tstz TIMESTAMP(9) WITH TIME ZONE;

        PROCEDURE flush(minfree PLS_INTEGER) IS
        BEGIN
            IF buff IS NOT NULL AND lengthb(buff) + minfree > 28000 THEN
                dbms_lob.writeAppend(c, length(buff), buff);
                buff := '';
            END IF;
        END;

        PROCEDURE line(txt VARCHAR2) IS
        BEGIN
            flush(lengthb(txt) + 1);
            buff := buff || chr(10) || txt;
        END;

        --a single quoted PL/SQL literal, embedded quotes doubled
        FUNCTION lit(v VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN CASE WHEN v IS NULL THEN NULL ELSE '''' || replace(v, '''', '''''') || '''' END;
        END;

        --a numeric literal that stays compilable regardless of the session NLS settings
        FUNCTION num(v NUMBER) RETURN VARCHAR2 IS
        BEGIN
            RETURN replace(to_char(v, 'tm'), dec, '.');
        END;

        FUNCTION is_text(v VARCHAR2) RETURN BOOLEAN IS
        BEGIN
            RETURN v IS NOT NULL AND v = regexp_replace(v, '[^[:print:]]', '');
        END;

        --the DSC_* bits this script itself sets or reads, see SYS.DBMS_STATS_INTERNAL
        FUNCTION eavscmt(v NUMBER) RETURN VARCHAR2 IS
            r VARCHAR2(200);
        BEGIN
            IF bitand(v, 4) > 0 THEN r    := r || 'DSC_EAVS(4) + ';          END IF;
            IF bitand(v, 32) > 0 THEN r   := r || 'DSC_CHR(32) + ';          END IF;
            IF bitand(v, 4096) > 0 THEN r := r || 'DSC_HIST_FREQ(4096) + ';  END IF;
            IF bitand(v, 8192) > 0 THEN r := r || 'DSC_HIST_TOPFREQ(8192) + '; END IF;
            RETURN rtrim(r, ' +');
        END;

        PROCEDURE assign(name VARCHAR2, idx PLS_INTEGER, val VARCHAR2, cmt VARCHAR2 := NULL) IS
            lhs VARCHAR2(128) := 'srec.' || name || nullif('(' || idx || ')', '()');
        BEGIN
            IF val IS NULL THEN
                RETURN;
            END IF;
            IF cmt IS NOT NULL THEN
                line('    --' || cmt);
            END IF;
            line('    ' || rpad(lhs, aw) || ' := ' || val || ';');
        END;

        --An expression evaluating to exactly r. A readable spelling is used only when it
        --converts back to the stored raw byte for byte, otherwise fall back to raw hex and
        --say what it decodes to, so that the statistics are never silently rewritten.
        PROCEDURE assign_raw(name VARCHAR2, idx PLS_INTEGER, r RAW) IS
            hex    VARCHAR2(4000) := rawtohex(r);
            v      VARCHAR2(4000);
            n      NUMBER;
            bf     binary_float;
            bd     binary_double;
            d      DATE;
            --full fractional-second precision: the default TIMESTAMP(6) truncates the
            --nanosecond bytes when re-emitting the decoded text, silently corrupting the raw
            ts     TIMESTAMP(9);
            tstz   TIMESTAMP(9) WITH TIME ZONE;
            ns     NUMBER;
            ns_utc NUMBER;
            ofs    NUMBER;
            val    VARCHAR2(32767);
        BEGIN
            IF r IS NULL THEN
                RETURN;
            END IF;
            CASE
                WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB', 'ROWID', 'UROWID') THEN
                    v := utl_raw.cast_to_varchar2(r);
                    IF is_text(v) AND rawtohex(utl_raw.cast_to_raw(v)) = hex THEN
                        val := 'utl_raw.cast_to_raw(' || lit(v) || ')';
                    END IF;
                WHEN dtype IN ('NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                    v := utl_raw.cast_to_nvarchar2(r);
                    --the n'' literal also has to survive the database character set round trip
                    IF is_text(v) AND rawtohex(utl_raw.cast_to_raw(to_nchar(v))) = hex THEN
                        val := 'utl_raw.cast_to_raw(n' || lit(v) || ')';
                    END IF;
                WHEN dtype IN ('NUMBER', 'INTEGER', 'FLOAT') THEN
                    dbms_stats.convert_raw_value(r, n);
                    IF rawtohex(utl_raw.cast_from_number(n)) = hex THEN
                        val := 'utl_raw.cast_from_number(' || num(n) || ')';
                    END IF;
                WHEN dtype = 'BINARY_FLOAT' THEN
                    dbms_stats.convert_raw_value(r, bf);
                    v := bf2txt(bf);
                    IF rawtohex(bfraw(to_binary_float(v))) = hex THEN
                        val := 'bf2raw(to_binary_float(' || lit(v) || '))';
                    END IF;
                WHEN dtype = 'BINARY_DOUBLE' THEN
                    dbms_stats.convert_raw_value(r, bd);
                    v := bd2txt(bd);
                    IF rawtohex(bdraw(to_binary_double(v))) = hex THEN
                        val := 'bd2raw(to_binary_double(' || lit(v) || '))';
                    END IF;
                WHEN dtype = 'DATE' THEN
                    dbms_stats.convert_raw_value(r, d);
                    --verify round-trip using the same formula as conr/date2raw
                    v := lpad(to_char(floor(to_number(to_char(d, 'SYYYY')) / 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(mod(to_number(to_char(d, 'SYYYY')), 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'MM')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'DD')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'HH24')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'MI')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'SS')) + 1, 'fmxx'), 2, '0');
                    IF rawtohex(hextoraw(v)) = hex THEN
                        val := 'date2raw(to_date(''' || to_char(d, datefmt) || ''',''' || datefmt || '''))';
                    END IF;
                WHEN dtype = 'TIMESTAMP' AND dtypefull NOT LIKE '%TIME ZONE' THEN
                    dbms_stats.convert_raw_value(utl_raw.substr(r, 1, 7), d);
                    ts := to_timestamp(to_char(d, datefmt), datefmt);
                    ns := 0;
                    IF length(r) > 7 THEN
                        ns := to_number(substr(hex, 15, 8), 'xxxxxxxx');
                        ts := ts + numtodsinterval(ns / 1000000000, 'SECOND');
                    END IF;
                    --verify round-trip using the same formula as conr/timestamp2raw
                    v := lpad(to_char(floor(to_number(to_char(ts, 'SYYYY')) / 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(mod(to_number(to_char(ts, 'SYYYY')), 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'MM')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'DD')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'HH24')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'MI')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'SS')) + 1, 'fmxx'), 2, '0');
                    IF ns != 0 THEN
                        v := v || lpad(to_char(ns, 'fmxxxxxxxx'), 8, '0');
                    END IF;
                    IF rawtohex(hextoraw(v)) = hex THEN
                        val := 'timestamp2raw(to_timestamp(''' || to_char(ts, tstampfmt) || ''',''' || tstampfmt || '''))';
                    END IF;
                WHEN dtypefull LIKE '%WITH TIME ZONE' AND dtypefull NOT LIKE '%LOCAL%' THEN
                    dbms_stats.convert_raw_value(utl_raw.substr(r, 1, 7), d);
                    ofs := (to_number(substr(hex, 23, 2), 'xx') - 20) * 60 + to_number(substr(hex, 25, 2), 'xx') - 60;
                    ts := to_timestamp(to_char(d, datefmt), datefmt) + numtodsinterval(ofs, 'MINUTE');
                    ns := 0;
                    IF length(r) > 9 THEN
                        ns := to_number(substr(hex, 15, 8), 'xxxxxxxx');
                        ts := ts + numtodsinterval(ns / 1000000000, 'SECOND');
                    END IF;
                    tstz := from_tz(ts, to_char(trunc(ofs/60),'fm00')||':'||to_char(mod(abs(ofs),60),'fm00'));
                    --verify round-trip using the same formula as conr/timestamptz2raw
                    d := CAST(tstz AT TIME ZONE 'UTC' AS DATE);
                    v := lpad(to_char(floor(to_number(to_char(d, 'SYYYY')) / 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(mod(to_number(to_char(d, 'SYYYY')), 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'MM')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'DD')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'HH24')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'MI')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(d, 'SS')) + 1, 'fmxx'), 2, '0');
                    ns_utc := to_number(to_char(tstz AT TIME ZONE 'UTC', 'ff9'));
                    IF ns_utc != 0 THEN
                        v := v || lpad(to_char(ns_utc, 'fmxxxxxxxx'), 8, '0');
                    END IF;
                    v := v || lpad(to_char(extract(timezone_hour FROM tstz) + 20, 'fmxx'), 2, '0') ||
                             lpad(to_char(extract(timezone_minute FROM tstz) + 60, 'fmxx'), 2, '0');
                    IF rawtohex(hextoraw(v)) = hex THEN
                        val := 'timestamptz2raw(from_tz(to_timestamp(''' || to_char(ts, tstampfmt) || ''',''' || tstampfmt || '''),''' || to_char(trunc(ofs/60),'fm00')||':'||to_char(mod(abs(ofs),60),'fm00') || '''))';
                    END IF;
                WHEN dtypefull LIKE '%WITH LOCAL TIME ZONE' THEN
                    dbms_stats.convert_raw_value(utl_raw.substr(r, 1, 7), d);
                    ts := to_timestamp(to_char(d, datefmt), datefmt);
                    ns := 0;
                    IF length(r) > 7 THEN
                        ns := to_number(substr(hex, 15, 8), 'xxxxxxxx');
                        ts := ts + numtodsinterval(ns / 1000000000, 'SECOND');
                    END IF;
                    --verify round-trip using the same formula as conr/timestampltz2raw
                    v := lpad(to_char(floor(to_number(to_char(ts, 'SYYYY')) / 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(mod(to_number(to_char(ts, 'SYYYY')), 100) + 100, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'MM')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'DD')), 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'HH24')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'MI')) + 1, 'fmxx'), 2, '0') ||
                         lpad(to_char(to_number(to_char(ts, 'SS')) + 1, 'fmxx'), 2, '0');
                    IF ns != 0 THEN
                        v := v || lpad(to_char(ns, 'fmxxxxxxxx'), 8, '0');
                    END IF;
                    IF rawtohex(hextoraw(v)) = hex THEN
                        val := 'timestampltz2raw(to_timestamp(''' || to_char(ts, tstampfmt) || ''',''' || tstampfmt || '''))';
                    END IF;
                ELSE
                    NULL;
            END CASE;
            IF val IS NOT NULL THEN
                assign(name, idx, val);
                RETURN;
            END IF;
            IF v IS NULL THEN
                v := getv(r);
            END IF;
            v := regexp_replace(v, '[^[:print:]]', '');
            assign(name, idx, 'hextoraw(''' || hex || ''')', CASE WHEN v IS NULL THEN NULL ELSE dtypefull || ': ' || v END);
        END;
    BEGIN
        dbms_lob.createTemporary(c, true);
        reset_Rec(rec);
        aw := greatest(11, 13 + length(to_char(greatest(rec.epc, 1))));

        line('--Histogram of ' || oname || '.' || tab || CASE WHEN part IS NULL THEN NULL ELSE '[' || part || ']' END || ' column ' || col);
        line('--Data type ' || dtypefull || ', histogram "' || histogram || '", ' || rec.epc || ' endpoints');
        line('--Snapshot taken by "ora histogram" on ' || to_char(systimestamp, datefmt) || '. Run this script to');
        line('--write the statistics back with dbms_stats.set_column_stats.');
        line('--');
        line('--chvals(i) is the readable value of endpoint i and is documentation only: dbms_stats never');
        line('--reads StatRec.chvals. The optimizer uses novals(i), the internal endpoint_value, plus');
        line('--eavals(i) for character and BINARY_FLOAT/DOUBLE columns. A readable expression is emitted');
        line('--wherever it converts back');
        line('--to the stored raw byte for byte, otherwise the raw hex is emitted with the decoded value in');
        line('--the comment above it. novals(i) is what Oracle stores and cannot be recomputed from the');
        line('--text, so leave it alone unless you know exactly what you are doing.');

        buff := buff || replace(replace(q'[
            DECLARE
                srec dbms_stats.StatRec;]',':epc',rec.epc),lpad(' ',12));

        --emit helper functions for raw re-encoding in the DECLARE section (before BEGIN):
        --date/timestamp types rebuild the internal bytes from readable text, while float
        --types must apply the sortable T-map that histgrm$/statrec store instead of IEEE
        IF dtype = 'BINARY_FLOAT' THEN
            buff := buff || q'[
                FUNCTION bf2raw(b binary_float) RETURN RAW IS
                    h VARCHAR2(16) := rawtohex(utl_raw.cast_from_binary_float(b));
                BEGIN
                    IF substr(h, 1, 1) >= '8' THEN
                        RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('FFFFFFFF'));
                    END IF;
                    RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('80000000'));
                END;]';
        ELSIF dtype = 'BINARY_DOUBLE' THEN
            buff := buff || q'[
                FUNCTION bd2raw(b binary_double) RETURN RAW IS
                    h VARCHAR2(32) := rawtohex(utl_raw.cast_from_binary_double(b));
                BEGIN
                    IF substr(h, 1, 1) >= '8' THEN
                        RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('FFFFFFFFFFFFFFFF'));
                    END IF;
                    RETURN utl_raw.bit_xor(hextoraw(h), hextoraw('8000000000000000'));
                END;]';
        ELSIF dtype IN ('DATE', 'TIMESTAMP') OR dtypefull LIKE '%TIME ZONE' THEN
            --subtypes must precede every subprogram: after the first function
            --declaration only further functions are allowed in the DECLARE part
            IF dtype = 'TIMESTAMP' AND dtypefull NOT LIKE '%TIME ZONE' THEN
                buff := buff || q'[
                SUBTYPE ts9 IS TIMESTAMP(9);]';
            ELSIF dtypefull LIKE '%WITH TIME ZONE' AND dtypefull NOT LIKE '%LOCAL%' THEN
                buff := buff || q'[
                SUBTYPE tstz9 IS TIMESTAMP(9) WITH TIME ZONE;]';
            ELSIF dtypefull LIKE '%WITH LOCAL TIME ZONE' THEN
                buff := buff || q'[
                SUBTYPE tsl9 IS TIMESTAMP(9) WITH LOCAL TIME ZONE;]';
            END IF;
            buff := buff || q'[
                FUNCTION date2raw(d DATE) RETURN RAW IS
                BEGIN
                    RETURN lpad(to_char(floor(to_number(to_char(d, 'SYYYY')) / 100) + 100, 'fmxx'), 2, '0') ||
                           lpad(to_char(mod(to_number(to_char(d, 'SYYYY')), 100) + 100, 'fmxx'), 2, '0') ||
                           lpad(to_char(to_number(to_char(d, 'MM')), 'fmxx'), 2, '0') ||
                           lpad(to_char(to_number(to_char(d, 'DD')), 'fmxx'), 2, '0') ||
                           lpad(to_char(to_number(to_char(d, 'HH24')) + 1, 'fmxx'), 2, '0') ||
                           lpad(to_char(to_number(to_char(d, 'MI')) + 1, 'fmxx'), 2, '0') ||
                           lpad(to_char(to_number(to_char(d, 'SS')) + 1, 'fmxx'), 2, '0');
                END;]';
            IF dtype = 'TIMESTAMP' AND dtypefull NOT LIKE '%TIME ZONE' THEN
                buff := buff || q'[
                FUNCTION timestamp2raw(ts ts9) RETURN RAW IS
                    ns NUMBER := to_number(to_char(ts, 'ff9'));
                    r  RAW(20) := date2raw(CAST(ts AS DATE));
                BEGIN
                    IF ns != 0 THEN
                        r := r || lpad(to_char(ns, 'fmxxxxxxxx'), 8, '0');
                    END IF;
                    RETURN r;
                END;]';
            ELSIF dtypefull LIKE '%WITH TIME ZONE' AND dtypefull NOT LIKE '%LOCAL%' THEN
                buff := buff || q'[
                FUNCTION timestamptz2raw(ts tstz9) RETURN RAW IS
                    ns  NUMBER := to_number(to_char(ts AT TIME ZONE 'UTC', 'ff9'));
                    d   DATE   := CAST(ts AT TIME ZONE 'UTC' AS DATE);
                    r   RAW(20) := date2raw(d);
                BEGIN
                    IF ns != 0 THEN
                        r := r || lpad(to_char(ns, 'fmxxxxxxxx'), 8, '0');
                    END IF;
                    r := r || lpad(to_char(extract(timezone_hour FROM ts) + 20, 'fmxx'), 2, '0') ||
                             lpad(to_char(extract(timezone_minute FROM ts) + 60, 'fmxx'), 2, '0');
                    RETURN r;
                END;]';
            ELSIF dtypefull LIKE '%WITH LOCAL TIME ZONE' THEN
                buff := buff || q'[
                FUNCTION timestampltz2raw(ts tsl9) RETURN RAW IS
                    ns NUMBER := to_number(to_char(ts, 'ff9'));
                    r  RAW(20) := date2raw(CAST(ts AS DATE));
                BEGIN
                    IF ns != 0 THEN
                        r := r || lpad(to_char(ns, 'fmxxxxxxxx'), 8, '0');
                    END IF;
                    RETURN r;
                END;]';
            END IF;
            --also emit num conversion functions for readable novals
            buff := buff || q'[
                FUNCTION date2num(d DATE) RETURN NUMBER IS
                BEGIN
                    --DATE endpoint numbers are the day fraction rounded onto the
                    --1e-8-day grid (measured on 19c); reproduce that rounding here
                    RETURN to_number(to_char(d, 'J')) + round((d - trunc(d)) * 1e8) / 1e8;
                END;]';
            IF dtype = 'TIMESTAMP' AND dtypefull NOT LIKE '%TIME ZONE' THEN
                buff := buff || q'[
                FUNCTION timestamp2num(ts ts9) RETURN NUMBER IS
                BEGIN
                    RETURN to_number(to_char(ts, 'J')) + (ts + 0 - trunc(ts + 0)) + to_number(to_char(ts, 'xff')) / 86400;
                END;]';
            ELSIF dtypefull LIKE '%WITH TIME ZONE' AND dtypefull NOT LIKE '%LOCAL%' THEN
                buff := buff || q'[
                FUNCTION timestamptz2num(ts tstz9) RETURN NUMBER IS
                BEGIN
                    RETURN to_number(to_char(ts AT TIME ZONE 'UTC', 'J')) + (ts AT TIME ZONE 'UTC' + 0 - trunc(ts AT TIME ZONE 'UTC' + 0)) + to_number(to_char(ts AT TIME ZONE 'UTC', 'xff')) / 86400;
                END;]';
            ELSIF dtypefull LIKE '%WITH LOCAL TIME ZONE' THEN
                buff := buff || q'[
                FUNCTION timestampltz2num(ts tsl9) RETURN NUMBER IS
                BEGIN
                    RETURN to_number(to_char(ts, 'J')) + (ts + 0 - trunc(ts + 0)) + to_number(to_char(ts, 'xff')) / 86400;
                END;]';
            END IF;
        END IF;

        buff := buff || replace(q'[
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
                $END]',':epc',rec.epc);
        buff := regexp_replace(buff,'('||chr(10)||chr(13)||'?) {12}','\1');

        line('');
        assign('eavs', null, num(rec.eavs), eavscmt(rec.eavs));
        assign_raw('minval', null, rec.minval);
        assign_raw('maxval', null, rec.maxval);

        FOR i in 1..rec.epc LOOP
            line('');
            assign('chvals', i, lit(rec.chvals(i)));
            $IF dbms_db_version.version > 11 $THEN
                assign_raw('eavals', i, rec.eavals(i));
            $END
            --novals are numbers that cannot always be recomputed from the text (DATE
            --endpoints are day fractions rounded onto the 1e-8-day grid), so emit a
            --readable conversion only when it is verified to reproduce the stored
            --value exactly, otherwise fall back to the bare number
            expr := NULL;
            IF (dtype = 'DATE' OR dtype = 'TIMESTAMP' OR dtypefull LIKE '%TIME ZONE')
               AND rec.chvals.exists(i) AND rec.chvals(i) IS NOT NULL THEN
                IF dtype = 'DATE' THEN
                    dfmt := CASE WHEN length(rec.chvals(i)) <= 10 THEN substr(datefmt, 1, 10) ELSE datefmt END;
                    dtmp := to_date(rec.chvals(i), dfmt);
                    IF to_number(to_char(dtmp, 'J')) + round((dtmp - trunc(dtmp)) * 1e8) / 1e8 = rec.novals(i) THEN
                        expr := 'date2num(to_date(' || lit(rec.chvals(i)) || ',''' || dfmt || '''))';
                    END IF;
                ELSIF dtypefull LIKE '%WITH TIME ZONE' AND dtypefull NOT LIKE '%LOCAL%' THEN
                    --endpoints of a WITH TIME ZONE column live on the UTC clock (measured
                    --on 19c), so pin the literal to UTC instead of inheriting the session zone
                    cfmt := CASE WHEN length(rec.chvals(i)) <= 10 THEN substr(tstampfmt, 1, 10) ELSE tstampfmt END;
                    tstz := from_tz(to_timestamp(rec.chvals(i), cfmt), '+00:00');
                    IF to_number(to_char(tstz AT TIME ZONE 'UTC', 'J'))
                         + (tstz AT TIME ZONE 'UTC' + 0 - trunc(tstz AT TIME ZONE 'UTC' + 0))
                         + to_number(to_char(tstz AT TIME ZONE 'UTC', 'xff')) / 86400 = rec.novals(i) THEN
                        expr := 'timestamptz2num(from_tz(to_timestamp(' || lit(rec.chvals(i)) || ',''' || cfmt || '''),''+00:00''))';
                    END IF;
                ELSIF dtypefull LIKE '%WITH LOCAL TIME ZONE' THEN
                    cfmt := CASE WHEN length(rec.chvals(i)) <= 10 THEN substr(tstampfmt, 1, 10) ELSE tstampfmt END;
                    ts := to_timestamp(rec.chvals(i), cfmt);
                    IF to_number(to_char(ts, 'J')) + (ts + 0 - trunc(ts + 0)) + to_number(to_char(ts, 'xff')) / 86400 = rec.novals(i) THEN
                        expr := 'timestampltz2num(to_timestamp(' || lit(rec.chvals(i)) || ',''' || cfmt || '''))';
                    END IF;
                ELSE
                    cfmt := CASE WHEN length(rec.chvals(i)) <= 10 THEN substr(tstampfmt, 1, 10) ELSE tstampfmt END;
                    ts := to_timestamp(rec.chvals(i), cfmt);
                    IF to_number(to_char(ts, 'J')) + (ts + 0 - trunc(ts + 0)) + to_number(to_char(ts, 'xff')) / 86400 = rec.novals(i) THEN
                        expr := 'timestamp2num(to_timestamp(' || lit(rec.chvals(i)) || ',''' || cfmt || '''))';
                    END IF;
                END IF;
            END IF;
            IF expr IS NOT NULL THEN
                assign('novals', i, expr);
            ELSE
                assign('novals', i, num(rec.novals(i)));
            END IF;
            assign('bkvals', i, num(rec.bkvals(i)));
            $IF dbms_db_version.version > 11 $THEN
                assign('rpcnts', i, num(rec.rpcnts(i)));
            $END
        END LOOP;

        line('');
        flush(1000);
        buff := buff||regexp_replace(
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
            /]',oname,tab,part,col,nvl(num(distcnt),'null'),nvl(num(densityn),'null'),nvl(num(nullcnt),'null'),nvl(num(avgclen),'null')),
            '('||chr(10)||chr(13)||'?) {12}','\1');

        flush(0);
        IF buff IS NOT NULL THEN
            dbms_lob.writeAppend(c,length(buff),buff);
        END IF;
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
                --rpcnts is either null or all-zero unless the histogram is HYBRID, and reset_Rec
                --extends with nulls while prepare_column_values writes real zeros, so compare
                --them as numbers or every EP is reported as changed
                d(i, 'rpcnts', nvl(case when orec.rpcnts.exists(i) then orec.rpcnts(i) end, 0), nvl(case when srec.rpcnts.exists(i) then srec.rpcnts(i) end, 0));
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
            --get_column_stats never fills StatRec.chvals, so derive the readable pre-change
            --values here (srec still holds the original stats) or diff flags every EP as changed
            FOR i IN 1 .. orec.epc LOOP
                orec.chvals(i) := rtrim(conv(i));
            END LOOP;
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
                dbms_stats.prepare_column_values(srec, nrec.chvals);
            ELSE
                dbms_stats.prepare_column_values(srec, nrec.novals);
                $IF dbms_db_version.version > 11 $THEN
                    --prepare_column_values encodes every noval as a NUMBER raw and collapses the
                    --duplicate EPs that add_rec expanded, so nrec.eavals is both the wrong
                    --encoding and the wrong length: rebuild it from the merged novals instead
                    IF bitand(nrec.eavs, 4) > 0 THEN
                        FOR i IN 1 .. srec.epc LOOP
                            srec.eavals(i) := conr(NULL, srec.novals(i));
                        END LOOP;
                    ELSE
                        --DSC_EAVS is off for DATE/TIMESTAMP, which store no epvalue_raw at all
                        srec.eavals := dbms_stats.rawarray();
                        srec.eavals.extend(srec.epc);
                    END IF;
                $END
                srec.minval := conr(1);
                srec.maxval := conr(srec.epc);
            END IF;
            --prepare_column_values resets eavs to DSC_NONE, restore it before diff/to_script
            --so that the "-test" preview shows exactly what would be written
            srec.eavs := nrec.eavs;
            --prepare_column_values resizes every array except chvals, which dbms_stats does not
            --read, so realign it to the new epc before calc_density and to_script index into it
            reset_Rec(srec);
            
            calc_density;
            diff;
            IF is_test =1 THEN
                to_script(srec);
                RETURN;
            END IF;

            
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
                adjcnt := rpcnt*adjnnull/notnulls;
            WHEN 'HYBRID' THEN
                $IF dbms_db_version.version>11 $THEN
                    max_v  := nullif('(' || nullif(srec.rpcnts(i), 0) || ')', '()');
                    -- repeat count scaled cardinality, sample_size has excluded null values
                    bk_adj := nullif(srec.rpcnts(i), 0) * notnulls / nullif(numbcks, 0);
                    rpcnt  := nvl(bk_adj, notnulls * densityn);
                    adjcnt := rpcnt * adjnnull / notnulls;
                $ELSE
                    -- Compatible with older versions, use density-based calculation
                    rpcnt := notnulls * densityn;
                    adjcnt := rpcnt * adjnnull / notnulls;
                $END
            WHEN 'NONE' THEN
                rpcnt := densityn * notnulls;
                adjcnt:= densityn * adjnnull;
            WHEN 'FREQUENCY' THEN

                 /*
                    NewDensity with the "half the least popular" rule active
                    NewDensity is set to
                    NewDensity = 0.5 * bkt(least_popular_value) / num_rows
                    and hence, for non-existent values:
                    E[card] = (0.5 * bkt(least_popular_value) / num_rows) * num_rows = 0.5 * bkt(least_popular_value)
                */
                IF i != srec.epc THEN
                    rpcnt := buckets * notnulls / nullif(numbcks,0);
                ELSE
                    rpcnt := (buckets - 0.5) * notnulls / nullif(numbcks,0);
                END IF;
                adjcnt := rpcnt*adjnnull/notnulls;
                --rpcnt := buckets;
            WHEN 'TOP-FREQUENCY' THEN
                --a top-frequency histogram is built from a full scan, so every EP already
                --holds an exact row count and the optimizer uses it as is
                rpcnt := buckets;
                adjcnt:= rpcnt*adjnnull/notnulls;
            ELSE
                rpcnt := buckets * notnulls / nullif(numbcks,0);
                adjcnt:= buckets * adjnnull / nullif(numbcks,0);
        END CASE;
    
        cep := srec.chvals(i);
        --dbms_output.put_line(i||':'||srec.novals  (i));
        pr(lpad(i, 5),
           lpad(srec.bkvals(i), 7),
           rpad(pep, dlen),
           rpad(cep, dlen),
           lpad(buckets || max_v, 10),
           lpad(NVL('' || getNum(rpcnt), ' '), 8),
           lpad(NVL('' || getNum(adjcnt), ' '), 8),
           lpad(CASE WHEN is_test > 0 THEN getNum(get_card(cep)) END, 8));
        pep   := cep;
        prevb := srec.bkvals(i);
    END LOOP;

    to_script(srec);

    IF stattab IS NOT NULL THEN
        wr('  * Note:  The values of field "Card" are based on the statistics of the input stats table.');
        IF is_test = 1 THEN
            wr('  * Note:  The values of field "RealCard" are based on the statistics of target table, not the input stats table!');
        END IF;
    END IF;

    IF input IS NOT NULL THEN
        wr('  * Note:  Cardinality of input predicate "' || input || '" is ' || get_card(input)||'.');
        IF stattab IS NOT NULL THEN
            wr('           This estimation is based on the statistics on the table, not the input stats table!');
        END IF;
    END IF;

    IF restoret IS NOT NULL THEN
        IF stattab IS NULL THEN
            wr('  * Note:  The original statistics can be restored by:');
            wr('               DECLARE');
            wr('                   t VARCHAR2(64) := ''' || restoret || ''';');
            wr('                   f VARCHAR2(64) := ''' || tztampfmt || ''';');
            wr('               BEGIN');
            wr(utl_lms.format_message(q'[                   dbms_stats.restore_table_stats('%s','%s',to_timestamp_tz(t,f),force=>true,no_invalidate=>false);]',oname,tab));
            wr('               END;');
            IF ttype='TABLE' THEN
                wr(utl_lms.format_message(q'[           Or consider locking the statistics by: exec dbms_stats.lock_table_stats('%s','%s');]',oname, tab));
            ELSE
                wr(utl_lms.format_message(q'[           Or consider locking the statistics by: exec dbms_stats.lock_partition_stats('%s','%s','%s');]',oname, tab,part));
            END IF;
        ELSE
            wr('  * Note:  The statistics have been updated into "'||statown||'"."'||stattab||'", can take affect into the target table by:');
            wr(utl_lms.format_message(q'[               exec dbms_stats.import_column_stats('%s','%s','%s','%s',statown=>'%s',stattab=>'%s');]',oname,tab,col,part,statown,stattab));
        END IF;
    END IF;

    :outs := outs;
    OPEN :result FOR
        SELECT EXTRACTVALUE(COLUMN_VALUE, '//seq') + 0 "#",
               EXTRACTVALUE(COLUMN_VALUE, '//bno') + 0 "Bucket#",
               CAST(EXTRACTVALUE(COLUMN_VALUE, '//prev') AS VARCHAR2(128)) "Prev EP Value",
               EXTRACTVALUE(COLUMN_VALUE, '//curr') "Curr EP Value",
               CAST(EXTRACTVALUE(COLUMN_VALUE, '//buckets') AS VARCHAR2(30)) "Buckets",
               CAST(EXTRACTVALUE(COLUMN_VALUE, '//card') AS VARCHAR2(20)) "Card",
               CAST(EXTRACTVALUE(COLUMN_VALUE, '//adj') AS VARCHAR2(20)) "Adj-Card"
        $IF &test>0 $THEN
               ,CAST(EXTRACTVALUE(COLUMN_VALUE, '//card2') AS VARCHAR2(30)) "&name"
        $END
        FROM   TABLE(XMLSEQUENCE(EXTRACT(result, '/RESULT/BUCKET')));
END;
/

print result
print outs
save script_text &V1..&V2..sql