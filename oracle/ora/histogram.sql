/*[[
    Show/change column histogram. Usage: @@NAME {<table_name>[.<partition_name>] <column_name>} {<test_value> | <min_v> <max_v> | <value> <buckets> [<card>]} [-test|-real]
    Examples:
        *  List the histogram: @@NAME SYS.OBJ$ NAME
        *  List the histogram and test the est cardinality of scalar value : @@NAME SYS.OBJ$ NAME "obj$"
        *  List the histogram and test the est cardinality of bind variable: @@NAME SYS.OBJ$ NAME :1
        *  List the histogram and test the est cardinality of each EP value: @@NAME SYS.OBJ$ NAME -test
        *  List the histogram and test the act cardinality of each EP value: @@NAME SYS.OBJ$ NAME -real
        *  Change the low/high value of "NONE" histogram:  @@NAME sys.obj$ stime "1990-08-26 11:25:01" "2018-08-12 02:50:00"
        *  Set number of buckets of "FREQUENCY" histogam: @@NAME sys.obj$ owner# 89 5
        *  Remove an EP from "FREQUENCY" histogam: @@NAME sys.obj$ owner# 89 5
    
    Notes: if input data type is not string/number/raw, the value should follow below format:
        *  DATE                    : YYYY-MM-DD HH24:MI:SS
        *  TIMESTAMP               : YYYY-MM-DD HH24:MI:SSxFF
        *  TIMESTAMP WITH TIMEZONE : YYYY-MM-DD HH24:MI:SSxFF TZH:TZM
    --[[
        &test  : default={0} test={1} real={2}
        @hybrid: 12.1={nullif(a.ENDPOINT_REPEAT_COUNT,0)}, default={null} 
        @CHECK_ACCESS_DBA: DBA_TAB_COLS/DBA_TAB_STATS_HISTORY={DBA_} DEFAULT={ALL_} 
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
    max_v     VARCHAR2(128) := :V4;
    min_v     VARCHAR2(128);
    card_adj  NUMBER        := regexp_substr(:V5,'^\d+$');
    bk_adj    NUMBER        := regexp_substr(max_v,'^\d+$');
    other_adj NUMBER        := 0;
    is_test   PLS_INTEGER   := :test;
    datefmt   VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SS';
    tstampfmt VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SSxff';
    tztampfmt VARCHAR2(32)  := tstampfmt||' TZH:TZM';
    rawfmt    VARCHAR2(32)  := 'fm'||lpad('x',30,'x');
    rawinput  RAW(128);
    restoret  VARCHAR2(128);
    srec      DBMS_STATS.STATREC;
    nrec      DBMS_STATS.STATREC;
    distcnt   NUMBER;
    density   NUMBER;
    densityn  NUMBER;
    nullcnt   NUMBER;
    avgclen   NUMBER;
    numrows   NUMBER;
    numblks   NUMBER;
    numbcks   NUMBER;
    avgrlen   NUMBER;
    samples   NUMBER;
    rpcnt     NUMBER;
    numval    NUMBER;
    dateval   DATE;
    rawval    RAW(2000);
    tstamp    TIMESTAMP;
    fmt       VARCHAR2(64) := ' %s  %s  %s  %s  %s %s %s';
    histogram VARCHAR2(80);
    dtype     VARCHAR2(128);
    dtypefull VARCHAR2(128);
    txn_id    VARCHAR2(128) := dbms_transaction.local_transaction_id;
    stmt_id   VARCHAR2(128) := 'TEST_CARD_' || dbms_random.string('X', 16);
    test_stmt VARCHAR2(512) ;
    prevb     PLS_INTEGER := 0;
    dlen      PLS_INTEGER;
    buckets   PLS_INTEGER;
    pops      PLS_INTEGER := 0;
    pop_based NUMBER      := 0;
    cnt       PLS_INTEGER := 0;
    cep       VARCHAR2(128);
    pep       VARCHAR2(128) := lpad(' ',32);

    FUNCTION hist_numtochar(p_num NUMBER, p_trunc VARCHAR2 := 'Y') RETURN VARCHAR2 IS
        m_vc   VARCHAR2(15);
        m_n    NUMBER := 0;
        m_n1   NUMBER;
        m_loop NUMBER := 7;
    BEGIN
        m_n := p_num;
        IF length(to_char(m_n)) < 36 THEN
            --dbms_output.put_line ('input too short');
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

    FUNCTION conv(idx PLS_INTEGER, num NUMBER := null) RETURN VARCHAR2 IS
        rtn    NUMBER   := nvl(num,case when idx is not null then srec.novals(idx) end);
        eva    RAW(128);
    BEGIN
        $IF dbms_db_version.version > 11 $THEN
            IF idx is not null THEN
                eva := srec.eavals(idx);
            END IF;
        $END
        CASE
            WHEN idx is not null and srec.chvals(idx) IS NOT NULL THEN
                RETURN RTRIM(srec.chvals(idx));
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB','ROWID', 'UROWID') THEN
                RETURN nvl(utl_raw.cast_to_varchar2(eva),hist_numtochar(rtn));
            WHEN dtype IN ('NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                RETURN nvl(utl_raw.cast_to_nvarchar2(eva),hist_numtochar(rtn));
            WHEN dtype = 'BINARY_DOUBLE' THEN
                RETURN TO_CHAR(TO_BINARY_DOUBLE(rtn),'TM');
            WHEN dtype = 'BINARY_FLOAT' THEN
                RETURN TO_CHAR(TO_BINARY_FLOAT(rtn),'TM');
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                RETURN to_char(rtn,'TM');
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                tstamp := to_timestamp('' || TRUNC(rtn), 'J');
                IF MOD(rtn, 1) = 0 THEN
                    RETURN to_char(tstamp, substr(datefmt,1,10));
                END IF;
                IF dtype = 'DATE' THEN
                    RETURN to_char(tstamp + MOD(rtn, 1), datefmt);
                ELSE
                    RETURN trim(trailing '0' from to_char(tstamp + NUMTODSINTERVAL(MOD(rtn, 1)*86400, 'SECOND'), tstampfmt));
                END IF;
            ELSE
                RETURN substr(to_char(rtn, rawfmt),1,16);
        END CASE;
    END;

    FUNCTION conr(idx PLS_INTEGER, num NUMBER := null) RETURN RAW IS
        rtn    VARCHAR2(128) := conv(idx,num);
        d      TIMESTAMP;
    BEGIN
        CASE
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB','ROWID', 'UROWID','NVARCHAR2', 'NCHAR', 'NCLOB') THEN
                return utl_raw.cast_to_raw(rtn);
            WHEN dtype = 'BINARY_DOUBLE' THEN
                return utl_raw.cast_from_binary_double(to_binary_double(rtn));
            WHEN dtype = 'BINARY_FLOAT' THEN
                return utl_raw.cast_from_binary_float(to_binary_float(rtn));
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                return utl_raw.cast_from_number(to_number(rtn));
            WHEN dtype IN ('DATE', 'TIMESTAMP') THEN
                d:=to_timestamp(rtn,tstampfmt);
                rtn := lpad(to_char(substr(extract(YEAR FROM d),1,2)+100,'fmxx'),2,0)||
                       lpad(to_char(substr(extract(YEAR FROM d),3,2)+100,'fmxx'),2,0)||
                       lpad(to_char(extract(MONTH FROM d),'fmxx'),2,0)||
                       lpad(to_char(extract(DAY FROM d),'fmxx'),2,0)||
                       lpad(to_char(extract(HOUR FROM d)+1,'fmxx'),2,0)||
                       lpad(to_char(extract(MINUTE FROM d)+1,'fmxx'),2,0)||
                       lpad(to_char(extract(SECOND FROM d)+1,'fmxx'),2,0);
                IF dtype!='DATE' THEN
                    rtn := rtn || lpad(to_char(0+to_char(d,'ff9'),'fmxxxxxxxx'),8,0);
                END IF;
                return hextoraw(rtn);
            ELSE
                return hextoraw(rtn);
        END CASE;
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

    FUNCTION toNum(input VARCHAR2) RETURN NUMBER IS
    BEGIN
        CASE
            WHEN dtype IN ('NUMBER', 'INTEGER', 'FLOAT','BINARY_FLOAT','BINARY_DOUBLE') THEN
                RETURN to_number(input);
            WHEN dtype IN ('VARCHAR2', 'CHAR', 'CLOB','NVARCHAR2', 'NCHAR', 'NCLOB','ROWID', 'UROWID') THEN
                --numval := to_number(utl_raw.cast_to_raw(rpad(input),15,0),rawfmt);
                RETURN NULL;
            WHEN dtype = 'DATE' THEN
                dateval:= to_date(input,datefmt);
                RETURN to_char(dateval,'J')+(dateval-trunc(dateval));
            WHEN dtype = 'TIMESTAMP' THEN
                tstamp := to_timestamp(input,tstampfmt);
                RETURN to_char(tstamp,'J')+(tstamp+0-trunc(tstamp+0))+to_char(tstamp,'"0"xff')/86400;
            ELSE
                raise_application_error(-20001,'Unsupported data type: '|| dtype);
        END CASE;
    EXCEPTION WHEN OTHERS THEN
        raise_application_error(-20001,'Conversion error from value "'||input||'" to the "'||dtype||'" data type!');
    END;

    FUNCTION get_card(val VARCHAR2) RETURN VARCHAR2 IS
        val1     VARCHAR2(128):=rtrim(val);
        str      VARCHAR2(128):=CASE WHEN val1 like ':%' THEN val1 ELSE ''''||val1||'''' END;
        target   VARCHAR2(500);
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
                          ''' for select /*+no_parallel(a) cursor_sharing_exact no_index(a) full(a)*/ *';
            END IF;
            test_stmt := test_stmt||' from ' || target || ' a where "' || col || '"=';
        END IF;

        CASE
            WHEN dtype ='BINARY_DOUBLE' THEN
                test_val := 'TO_BINARY_DOUBLE('||str||')';
            WHEN dtype ='BINARY_FLOAT' THEN
                test_val := 'TO_BINARY_FLOAT('||str||')';
            WHEN dtype IN ('NUMBER', 'FLOAT', 'INTEGER') THEN
                test_val:= 'TO_NUMBER('||str||')';
            WHEN dtype = 'DATE' THEN
                test_val:= 'to_date(' || str || ','''||datefmt||''')';
            WHEN dtype = 'TIMESTAMP' THEN
                test_val:= 'to_timestamp(' || str || ','''||tstampfmt||''')';
            ELSE
                test_val:= str;
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
            target := sqlerrm||': '||test_stmt || test_val;
            raise_application_error(-20001,target);
        END IF;
    END;

    PROCEDURE init IS
        ex_array EXCEPTION;
        PRAGMA EXCEPTION_INIT(ex_array, -6532);
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
        WHEN ex_array THEN
            raise_application_error(-20001,'Cannot extend histogram whose size > '||nrec.epc||'!');
    END;

    PROCEDURE set_rec(chval VARCHAR2,noval NUMBER,buckets PLS_INTEGER,rpcnt PLS_INTEGER,eaval RAW :=NULL) IS
        steps PLS_INTEGER := CASE WHEN HISTOGRAM='HEIGHT BALANCED' THEN buckets ELSE 1 END;
    BEGIN
        IF nvl(buckets,0) < 1 AND nrec.epc > 0 THEN
            raise_application_error(-20001,'buckets('||buckets||') of #'||(nrec.epc+1)||' must >0 !');
        END IF;

        FOR i IN 1..steps LOOP
            init;
            nrec.chvals(nrec.epc):= chval;
            nrec.novals(nrec.epc):= noval;
            nrec.bkvals(nrec.epc):= buckets/steps;
            $IF dbms_db_version.version > 11 $THEN
                nrec.eavals(nrec.epc):=eaval;
                IF histogram='HYBRID' THEN
                    IF nvl(rpcnt,0) < 1 THEN
                        raise_application_error(-20001,'rpcnt('||rpcnt||') of #'||nrec.epc||' must >0 !');
                    END IF;
                    nrec.rpcnts(nrec.epc) := buckets;
                    nrec.bkvals(nrec.epc) := rpcnt;
                END IF;
            $END
        END LOOP;
    END;

    FUNCTION to_header(title VARCHAR2,value VARCHAR2,sep VARCHAR2:='    ') return varchar2 IS
    BEGIN
        return sep||rpad(title,11)||': '||rpad(value,10);
    END;

    PROCEDURE calc_density IS
    BEGIN
        numbcks  := srec.bkvals(srec.epc);
        numrows  := greatest(numrows,1);
        samples  := nvl(NULLIF(samples, 0),numrows);
        numbcks  := NULLIF(numbcks, 0);
        cnt      := 0;
        pops     := 0;
        dlen     := 16;

        case histogram
            when 'HYBRID' then
                pop_based := numbcks / srec.epc;
            when 'HEIGHT BALANCED' then
                pop_based := 1;
            else
                pop_based := null; 
        end case;

        FOR i IN 1 .. srec.epc LOOP
            buckets := srec.bkvals(i) - prevb;
            srec.chvals(i) :=  rtrim(conv(i));
            dlen := greatest(dlen,lengthb(srec.chvals(i)));
            $IF dbms_db_version.version>11 $THEN
                buckets := nvl(nullif(srec.rpcnts(i),0),buckets);
            $END
            IF buckets > pop_based THEN 
                cnt  := cnt + 1;
                pops := pops + buckets;
            END IF;
            prevb := srec.bkvals(i);
        END LOOP;
        densityn := coalesce((1-pops/numbcks)/nullif(distcnt-cnt*samples/numrows,0), density);
    END;

    PROCEDURE load_stats IS
        msg varchar2(2000);
    BEGIN
        BEGIN
            SELECT regexp_substr(data_type, '\w+'),
                   COALESCE(regexp_substr(data_type, '\d+') + 0, data_scale, 6),
                   histogram,
                   sample_size,
                   data_type
            INTO   dtype, dlen, histogram, samples, dtypefull
            FROM   &CHECK_ACCESS_DBA.tab_cols
            WHERE  owner = oname
            AND    table_name = tab
            AND    column_name = col;
        EXCEPTION 
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001,'No such column: '||col);
        END;

        IF histogram IS NULL THEN
            raise_application_error(-20001,'Target column on the '||lower(ttype)||' is not analyzed!');
        END IF;

        BEGIN
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
        EXCEPTION WHEN OTHERS THEN
            msg := trim('Unable to get table/column stats due to '||sqlerrm);
            raise_application_error(-20001,msg);
        END;
        IF srec.chvals IS NULL THEN
            srec.chvals := dbms_stats.chararray();
        END IF;
        srec.chvals.extend(srec.epc-srec.chvals.count);

        $IF dbms_db_version.version > 11 $THEN
            IF srec.eavals IS NULL THEN
                srec.eavals := dbms_stats.rawarray();
            END IF;
            IF srec.rpcnts IS NULL THEN
                srec.rpcnts := dbms_stats.numarray();
            END IF;
            srec.eavals.extend(srec.epc-srec.eavals.count);
            srec.rpcnts.extend(srec.epc-srec.rpcnts.count);  
        $END
    END;
BEGIN
    dbms_output.enable(NULL);
    load_stats;
    --Modify column stats, following fields to be updated: EPC,BKVALS,NOVALS,EAVALS,MINVAL,MAXVAL
    IF input IS NOT NULL AND max_v IS NOT NULL THEN
        min_v    := trim(input);
        IF dtype IN ('CHAR','NCHAR') THEN
            IF LENGTH(min_v)<15 THEN
                min_v := rpad(min_v,15);
            END IF;
            IF LENGTH(max_v)<15 THEN
                max_v := rpad(max_v,15);
            END IF;    
        END IF;
        numval   := toNum(min_v);
        nrec.epc := 0;
        rawinput := case when numval is null then utl_raw.cast_to_raw(min_v) else conr(null,numval) end;
        --For "NONE" histogram, support adjusting the low/high value
        IF histogram = 'NONE' THEN
            set_rec(min_v,numval,srec.bkvals(1),null,rawinput);
            numval := toNum(max_v);
            IF numval <= nrec.novals(1) THEN
                raise_application_error(-20001,'High value "'||max_v||'" must be larger than low value "'||min_v||'"');
            END IF;
            rawinput := case when numval is null then utl_raw.cast_to_raw(max_v) else conr(null,numval) end;
            set_rec(max_v,numval,srec.bkvals(2)-srec.bkvals(1),null,rawinput);
        ELSE
            IF bk_adj IS NULL THEN
                raise_application_error(-20001,'Please input the 4th parameter as the buckets!');
            ELSIF histogram='HYBRID' AND bk_adj>0 AND card_adj IS NULL THEN
                raise_application_error(-20001,'Please input the 5th parameter as the repeat number!');
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
                    rpcnt := srec.rpcnts(i);
                    rawval:= srec.eavals(i);
                    max_v := nvl(max_v,getv(rawval));
                $END

                IF other_adj = 0 AND bk_adj > 0 AND (min_v < trim(max_v)  OR numval < srec.novals(i)) THEN
                    set_rec(min_v,numval, bk_adj,card_adj,rawinput);
                    other_adj := bk_adj;
                    set_rec(nvl(srec.chvals(i),max_v),srec.novals(i),buckets,rpcnt,rawval);
                ELSIF min_v = trim(max_v) OR numval = srec.novals(i) THEN
                    IF bk_adj = 0 THEN --remove entry
                        other_adj := - buckets;
                    ELSE
                        set_rec(nvl(srec.chvals(i),max_v),srec.novals(i), bk_adj, coalesce(card_adj,rpcnt,1),rawval);
                        other_adj := nullif(bk_adj - buckets,0);
                    END IF;
                ELSE
                    set_rec(nvl(srec.chvals(i),max_v),srec.novals(i),greatest(buckets,1),rpcnt,rawval);
                END IF;
                prevb   := srec.bkvals(i);
            END LOOP;
            --in case of input > high_value
            IF nrec.epc>0 AND other_adj = 0 AND bk_adj>0 THEN
                set_rec(min_v,numval, bk_adj, card_adj, rawinput);
            END IF;
        END IF;

        /* PREPARE_COLUMN_VALUES: 
                1) epc(=input_array.count) must > 1
                2) bkvals is delta values
           * HEIGHT BALANCED: bkvals is null + duplicate EPs(novals/chvals/eavals) as popular EP
           * HYBRID         : bkvals is not null + unique EP values + all values of rptcnts > 0, rptcnts(1) = bkvals(1), exchange rpcnts and  bkvals
           * FREQUENCY      : bkvals is not null + unique EP values + rptcnts is null or rptcnts(1)=0
           * TOP-FREQUENCY  : bkvals is not null + unique EP values
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
                * TOP-FREQUENCY   : bkvals(1) > 0
                * NONE            : epc = 2, bkvals(1) = 0, bkvals(1) = 1

        */
        IF nrec.epc > 1 THEN
            srec.epc    := nrec.epc;
            srec.bkvals:= nrec.bkvals;
            CASE HISTOGRAM
                WHEN 'HYBRID' THEN
                    NULL;
                WHEN 'HEIGHT BALANCED' THEN
                    srec.bkvals := NULL;
                ELSE
                    null;
            END CASE;

            $IF dbms_db_version.version > 11 $THEN
                srec.rpcnts := nrec.rpcnts;
                srec.eavals := nrec.eavals;
            $END

            IF dtype IN ('VARCHAR2', 'CHAR', 'CLOB','NVARCHAR2', 'NCHAR', 'NCLOB','ROWID', 'UROWID') THEN
                srec.eavs   := 4; --DBMS_STATS_INTERNAL.DSC_EAVS
                dbms_stats.prepare_column_values(srec,nrec.chvals);
            /*ELSIF dtype IN ('NUMBER', 'INTEGER', 'FLOAT','BINARY_FLOAT','BINARY_DOUBLE') THEN
                dbms_stats.prepare_column_values(srec,nrec.novals);*/
            ELSE
                dbms_stats.prepare_column_values(srec,nrec.novals);
                
                srec.eavs   := nrec.eavs;
                $IF dbms_db_version.version > 11 $THEN
                    srec.eavals := nrec.eavals;
                $END
                srec.minval := conr(1);
                srec.maxval := conr(srec.epc);
                --srec.eavs   := null;
            END IF;

            /*
            DECLARE
                PROCEDURE compare(idx PLS_INTEGER, NAME, val1 VARCHAR2, val2 VARCHAR2) IS
                BEGIN
                    IF nvl(val1, 'x') != nvl(val2, 'x') THEN
                        pr(NAME || '(' || idx || '):  org="' || val1 || '"  new="' || val2 || '"');
                    END IF;
                END;
            BEGIN
                compare(0, 'epc', trec.maxval, srec.maxval);
                compare(0, 'eavs', trec.eavs, srec.eavs);
                compare(0, 'min', trec.minval, srec.minval);
                compare(0, 'max', trec.maxval, srec.maxval);
                FOR i IN 1 .. srec.epc LOOP
                    compare(i, 'bkvals', trec.bkvals(i), srec.bkvals(i));
                    compare(i, 'novals', trec.novals(i), srec.novals(i));
                    compare(i, 'chvals', trec.chvals(i), srec.chvals(i));
                END LOOP;
                RETURN;
            END;
            */

            --set stats for restoration
            restoret := TO_CHAR(systimestamp-numtodsinterval(1,'second'),tztampfmt);
            calc_density;
            DBMS_STATS.SET_COLUMN_STATS(ownname       => oname,
                                        tabname       => tab,
                                        partname      => part,
                                        colname       => col,
                                        srec          => srec,
                                        density       => densityn, --calc the density since newDensity(10053) is not used after setting
                                        no_invalidate => false,
                                        force         => true);
            load_stats;
        ELSIF nrec.epc > 0 and nrec.epc < 2 THEN
            raise_application_error(-20001,'Cannot set the histogram as only having one EP value!');
        END IF;
    END IF;

    calc_density;

    pr(RPAD('=', 120, '='));
    pr(utl_lms.format_message('Histogram: "%s"   Low-Value: "%s"   High-Value: "%s"',histogram,TRIM(getv(srec.minval)),TRIM(getv(srec.maxval))));
    pr(
       to_header('Rows',getNum(numrows),'')||
       to_header('Samples',getNum(samples))||
       to_header('Nulls',getNum(nullcnt))||
       to_header('Distincts',getNum(distcnt))||
      
       to_header('Blocks',getNum(numblks),chr(10))||
       to_header('Buckets',numbcks)||
       to_header('Row Len',avgrlen)||
       to_header('Col Len',avgclen)||

       to_header('Rows/Block',ROUND(numrows / NULLIF(numblks, 0), 2),chr(10))||
       to_header('Density',to_char(density * 100 , 'fm99990.09999')||'%')||
       to_header('New-Density',to_char(densityn * 100, 'fm99990.09999')||'%')||
       to_header('Cardinality',getNum(ROUND((numrows - nullcnt) * densityn, 2))));
    pr(RPAD('=', 120, '='));

    pr(RPAD(' ', 74));
    pr('    #', 'Bucket#',RPAD('Prev EP Value', dlen), RPAD('Current EP Value', dlen), lpad('Buckets',10), LPAD('Card', 8), LPAD(CASE WHEN is_test=2 THEN 'Real' ELSE 'RealCard' END, 8));
    pr('-----',  RPAD('-', 7, '-'),RPAD('-', dlen, '-'), RPAD('-', dlen, '-'), RPAD('-', 10, '-'), RPAD('-', 8, '-'), RPAD('-', 8, '-'));
    

    prevb := 0;
    FOR i IN 1 .. srec.epc LOOP
        buckets := greatest(srec.bkvals(i) - prevb,1);
        IF histogram = 'HEIGHT BALANCED' THEN
            IF buckets > pop_based THEN  --popular value
                IF i != srec.epc THEN
                    rpcnt := (numrows - nullcnt) * buckets / numbcks;
                ELSE
                    rpcnt := (numrows - nullcnt) * (buckets - 0.5) / numbcks; 
                END IF;
            ELSE --un-popular value
                /*
                NewDensity with the “half the least popular” rule active
                NewDensity is set to
                NewDensity = 0.5 * bkt(least_popular_value) / num_rows
                and hence, for non-existent values:
                E[card] = (0.5 * bkt(least_popular_value) / num_rows) * num_rows = 0.5 * bkt(least_popular_value)
                */
                rpcnt := (numrows - nullcnt) * densityn;
            END IF;
        ELSIF histogram = 'NONE' THEN
            rpcnt := densityn * buckets;
        ELSE
            rpcnt := buckets * (numrows - nullcnt) / samples;
        END IF;
        max_v := '';
        $IF dbms_db_version.version>11 $THEN
            max_v := nullif('('||nullif(srec.rpcnts(i), 0)||')','()');
            bk_adj := nullif(srec.rpcnts(i), 0)*numrows/nullif(samples,0);
            IF srec.rpcnts(i) < pop_based THEN
                bk_adj := greatest(bk_adj,(numrows - nullcnt) * densityn);
            END IF;
            rpcnt := nvl(bk_adj, rpcnt);
        $END

        cep := srec.chvals(i);
        pr(lpad(i, 5),lpad(srec.bkvals(i), 7), rpad(pep,dlen),rpad(cep,dlen),lpad(buckets||max_v, 10),LPAD(NVL('' || getNum(rpcnt), ' '), 8),LPAD(case when is_test > 0  then getNum(get_card(cep)) end,8));
        pep   := cep;
        prevb := srec.bkvals(i);
    END LOOP;
    pr(chr(10));
    IF input IS NOT NULL THEN
        pr('  * Note:  Cardinality of input predicate "' || input || '" is ' || get_card(input));
    END IF;
    IF restoret IS NOT NULL THEN
        pr('  * Note:  The original statistics can be restored by:');
        pr('               DECLARE');
        pr('                   t VARCHAR2(64) := '''||restoret||''';');
        pr('                   f VARCHAR2(64) := '''||tztampfmt||''';');
        pr('               BEGIN');
        pr(utl_lms.format_message(q'[                   dbms_stats.restore_table_stats('%s','%s',to_timestamp_tz(t,f),force=>true,no_invalidate=>false);]',oname,tab));
        pr('               END;');
        pr(utl_lms.format_message(q'[           Or consider locking the statistics by: exec dbms_stats.lock_table_stats('%s','%s');]',oname,tab));
    END IF;
EXCEPTION 
    WHEN NO_DATA_FOUND THEN
        raise_application_error(-20001,'No such column: '||col);
END;
/