/*[[
    Test the cache hit ratio of determistic/scalar subquery features. Usage: @@NAME [<NDV>] [<value of _query_execution_cache_max_size>]
    Parameters:
        ndv                             : Number of distinct values, default as 1024
        _query_execution_cache_max_size : default as 128k

    Hit Ratio = 100 * (num_rows - func_calls)/(num_rows - NDV)
    For the default value of _query_execution_cache_max_size, the determistic function seems to only support less than 1076 ndv.

    Sample Output:
    ==============
    SQL> ora PLSQL_HIT
    DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----------------------- --------------------- -----------------
                     62.988                62.305            63.965

    SQL> ora PLSQL_HIT 2048
    DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----------------------- --------------------- -----------------
                          0                43.213            43.408

    SQL> ora PLSQL_HIT 2048 1M
    DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----------------------- --------------------- -----------------
                     88.721                88.477              89.6

    SQL> ora PLSQL_HIT 16384 1M
    DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----------------------- --------------------- -----------------
                          0                43.335            43.213

    SQL> ora PLSQL_HIT 16384 4M
    DETERMINISTIC_HIT_RATIO SCALARQUERY_HIT_RATIO COMBINE_HIT_RATIO
    ----------------------- --------------------- -----------------
                     63.184                 63.33            63.031
    --[[
        &V1: default={1024}
        &V2: default={128k}
        &V3: default={1}
        @VER: 12.1={}
    --]]
 ]]*/
set feed off verify off
var org number;

DECLARE
    ret    NUMBER;
    strval VARCHAR2(300):=replace(upper(:V2),'B');
    newv   NUMBER;
BEGIN
    newv := regexp_substr(strval,'^(\d+)[K|M|G]?$',1,1,'i',1);
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
                                            intval => :org,
                                            strval => strval,
                                            listno => 1);
    IF newv != :org THEN
        EXECUTE IMMEDIATE 'alter session set "_query_execution_cache_max_size"='||newv;
    ELSE
        :org := null;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        raise_application_error(-20001,'Unable to alter "_query_execution_cache_max_size" due to no access right!');
END;
/
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
r1 AS (SELECT /*+materialize ordered use_nl(b)*/ a.* FROM (SELECT * FROM r UNION ALL SELECT * FROM (SELECT * FROM r ORDER BY 1 DESC)) a)
SELECT count(1) rows#,
       round(count(1)/COUNT(DISTINCT r),2) "Cardinality",
       round(100*(count(1)-COUNT(DISTINCT c1(r,d)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' deterministic_hit_ratio,
       round(100*(count(1)-COUNT(DISTINCT (SELECT c2(r,ts) FROM dual)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' scalarquery_hit_ratio,
       round(100*(count(1)-COUNT(DISTINCT (SELECT c3(r,d,ts) FROM dual)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' combine_hit_ratio
FROM r1
/

BEGIN
    IF :org IS NOT NULL THEN
        EXECUTE IMMEDIATE 'alter session set "_query_execution_cache_max_size"='||:org;
    END IF;
END;
/