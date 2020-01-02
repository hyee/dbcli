/*[[
    Test the cache hit ratio of determistic/scalar subquery features. Usage: @@NAME [<NDV>] [<value of _query_execution_cache_max_size>] [loops] [fetch_size] [-random]
    Parameters:
        ndv                             : number of distinct values, default as 1024
        loops                           : default as 1
        _query_execution_cache_max_size : default as 128k
        -random                         : random order, if not specified use sequential ordered
    Hit Ratio = 100 * (num_rows - func_calls)/(num_rows - NDV)

    With the default value of _query_execution_cache_max_size, the determistic function seems to only support less than 1076 NDV.

    Sample Output:
    ==============
    SQL> ora PLSQL_HIT . . 4
    ROWS#  NDV DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ---- ----------------------- --------------------- -----------------
     8192 1024 61.426%                 94.782%               94.601%

    SQL> ora PLSQL_HIT 2048
    ROWS#  NDV DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ---- ----------------------- --------------------- -----------------
     4096 2048 0%                      43.604%               43.896%

    SQL> ora PLSQL_HIT 2048 1M
    ROWS#  NDV DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ---- ----------------------- --------------------- -----------------
     4096 2048 87.402%                 88.477%               87.354%

    SQL> ora PLSQL_HIT 16384 1M
    ROWS#  NDV  DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ----- ----------------------- --------------------- -----------------
    32768 16384 0%                      43.536%               43.158%

    SQL> ora PLSQL_HIT 16384 16M
    ROWS#  NDV  DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ----- ----------------------- --------------------- -----------------
    32768 16384 63.202%                 62.921%               62.878%

    SQL> ora PLSQL_HIT 16434 16M
    ROWS#  NDV  DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ----- ----------------------- --------------------- -----------------
    32868 16434 .091%                   63.454%               63.083%

    SQL> ora PLSQL_HIT 16434 16M -random
    ROWS#  NDV  DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----- ----- ----------------------- --------------------- -----------------
    32868 16434 63.296%                 63.204%               63.113%

    --[[
        &V1: default={1024}
        &V2: default={128k}
        &V3: default={1}
        &V4: default={100}
        &ran: default={} random={order by dbms_random.value(1,1e20)}
        @VER: 12.1={}
    --]]
 ]]*/
set feed off verify off
var orgv number;
var newv number;

DECLARE
    ret    NUMBER;
    strval VARCHAR2(300):=replace(upper(:V2),'B');
    newv   NUMBER;
BEGIN
    newv := regexp_substr(strval,'^([0-9\.]+)[K|M|G]?$',1,1,'i',1);
    IF newv IS NULL THEN
        raise_application_error(-20001,'Invalid value of _query_execution_cache_max_size: '||:V2);
    END IF;
    CASE regexp_substr(strval,'[K|M|G]?$')
        WHEN 'K' THEN newv := newv*1024;
        WHEN 'M' THEN newv := newv*1024*1024;
        WHEN 'G' THEN newv := newv*1024*1024*1024;
        ELSE NULL;
    END CASE;
    -- Call the function
    ret := dbms_utility.get_parameter_value(parnam => '_query_execution_cache_max_size',
                                            intval => :orgv,
                                            strval => strval,
                                            listno => 1);
    IF newv != :orgv THEN
        EXECUTE IMMEDIATE 'alter session set "_query_execution_cache_max_size"='||newv;
    ELSE
        :orgv := null;
    END IF;
    :newv := newv;
EXCEPTION
    WHEN OTHERS THEN
        raise_application_error(-20001,'Unable to alter "_query_execution_cache_max_size" due to no access right!');
END;
/
PRO **************************************************************************************
PRO *  _query_execution_cache_max_size=&newv  NDV=&1  loops=&v3  fetchSize=&v4  *
PRO **************************************************************************************

PRO
PRO Stats with infinite fetch_size
PRO ==============================
WITH FUNCTION c1 (r INT,d DATE) RETURN NUMBER DETERMINISTIC IS
    PRAGMA UDF;
BEGIN
    RETURN dbms_random.value(1,1e20)+r+(d-SYSDATE);
END;
FUNCTION c2 (r INT,c TIMESTAMP) RETURN NUMBER IS
    PRAGMA UDF;
BEGIN
    RETURN dbms_random.value(1,1e20)+r;
END;
FUNCTION c3 (r INT,d DATE,ts TIMESTAMP) RETURN NUMBER DETERMINISTIC IS
    PRAGMA UDF;
BEGIN
    RETURN dbms_random.value(1,1e20)+r+EXTRACT(SECOND FROM ts)*1e6;
END;
r  AS (SELECT ROWNUM r,SYSDATE+ROWNUM d,SYSTIMESTAMP+NUMTODSINTERVAL(dbms_random.value*1e3,'day') ts FROM dual CONNECT BY ROWNUM<=&V1),
r1 AS (SELECT /*+materialize ordered use_nl(b)*/ a.* FROM (SELECT * FROM r UNION ALL SELECT * FROM (SELECT * FROM r ORDER BY 1 DESC)) a,(select * from dual connect by rownum<=&v3) b &ran)
SELECT /*+param('_query_execution_cache_max_size', &newv)*/ count(1) rows#,
       COUNT(DISTINCT r) "NDV",
       round(100*(count(1)-COUNT(DISTINCT c1(r,d)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' deterministic_hit_ratio,
       round(100*(count(1)-COUNT(DISTINCT (SELECT c2(r,ts) FROM dual)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' scalarquery_hit_ratio,
       round(100*(count(1)-COUNT(DISTINCT (SELECT c3(r,d,ts) FROM dual)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' combine_hit_ratio
FROM r1
/

var c REFCURSOR;
DECLARE
    c SYS_REFCURSOR;
    l PLS_INTEGER := &V4;
    TYPE tr IS TABLE OF VARCHAR2(2000);
    ary  tr;
    data CLOB := '<ROWSET>';
    procedure wr(msg VARCHAR2) IS
    BEGIN
        dbms_lob.writeappend(data,length(msg)+1,chr(10)||msg);
    END;
BEGIN
    OPEN c FOR q'{
        WITH FUNCTION c1 (r INT,d DATE) RETURN NUMBER DETERMINISTIC IS
            PRAGMA UDF;
        BEGIN
            RETURN dbms_random.value(1,1e20)+r+(d-SYSDATE);
        END;
        FUNCTION c2 (r INT,c TIMESTAMP) RETURN NUMBER IS
            PRAGMA UDF;
        BEGIN
            RETURN dbms_random.value(1,1e20)+r;
        END;
        FUNCTION c3 (r INT,d DATE,ts TIMESTAMP) RETURN NUMBER DETERMINISTIC IS
            PRAGMA UDF;
        BEGIN
            RETURN dbms_random.value(1,1e20)+r+EXTRACT(SECOND FROM ts)*1e6;
        END;
        r  AS (SELECT ROWNUM r,SYSDATE+ROWNUM d,SYSTIMESTAMP+NUMTODSINTERVAL(dbms_random.value*1e3,'day') ts FROM dual CONNECT BY ROWNUM<=&V1)
        SELECT /*+param('_query_execution_cache_max_size', &newv) ordered use_nl(b)*/ 
              XMLELEMENT("ROW",XMLFOREST(c1(r,d) AS C1,(SELECT c2(r,ts) FROM dual) AS C2,(SELECT c3(r,d,ts) FROM dual) AS C3,r)).getStringval()
        FROM (SELECT * FROM r UNION ALL SELECT * FROM (SELECT * FROM r ORDER BY 1 DESC)) a,
             (select * from dual connect by rownum<=&v3) b &ran
        }';
    LOOP
        FETCH c BULK COLLECT INTO ary LIMIT l;
        EXIT WHEN c%NOTFOUND;
        FOR i in 1..ary.COUNT LOOP
            wr(ary(i));
        END LOOP;
    END LOOP;
    CLOSE c;
    c := null;
    wr('</ROWSET>');
    OPEN c FOR
        SELECT Count(1) "ROWS#",
               COUNT(DISTINCT r) "NDV",
               round(100*(count(1)-COUNT(DISTINCT c1))/ (count(1)-COUNT(DISTINCT r)),3)||'%' deterministic_hit_ratio,
               round(100*(count(1)-COUNT(DISTINCT c2))/ (count(1)-COUNT(DISTINCT r)),3)||'%' scalarquery_hit_ratio,
               round(100*(count(1)-COUNT(DISTINCT c3))/ (count(1)-COUNT(DISTINCT r)),3)||'%' combine_hit_ratio
        FROM XMLTABLE('/ROWSET/ROW' PASSING xmltype(data) columns
                            c1 number path 'C1',
                            c2 number path 'C2',
                            c3 number path 'C3',
                            r  number path 'R');
    :c := c;
    IF :orgv IS NOT NULL THEN
        EXECUTE IMMEDIATE 'alter session set "_query_execution_cache_max_size"='||:orgv;
    END IF;
END;
/
PRO Stats with fetch_size = &V4
PRO ==============================
print c