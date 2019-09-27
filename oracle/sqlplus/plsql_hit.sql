REM Test the cache hit ratio of determistic/scalar subquery features
REM  Usage: @plsql_hit [<NDV>] [<value of _query_execution_cache_max_size>] [loops] [random]
REM  Parameters:
REM     ndv                             : number of distinct values, default as 1024
REM     loops                           : default as 1
REM     _query_execution_cache_max_size : default as 128k
REM     random                          : random order, if not specified use sequential ordered
REM  
REM   Hit Ratio = 100 * (num_rows - func_calls)/(num_rows - NDV)

COLUMN 1 NEW_VALUE 1
COLUMN 2 NEW_VALUE 2
COLUMN 3 NEW_VALUE 3
COLUMN 4 NEW_VALUE 4

SET TERMOUT OFF FEED OFF newp none verify off
SELECT  1024 "1",'128K' "2", 1 "3",'' "4" FROM dual WHERE ROWNUM = 0;
SELECT  decode('&4','random','order by dbms_random.value(1,1e20)','') order_by from dual;
SELECT nvl('&1','1024') "1",nvl('&2','128k') "2",nvl('&3','1') "3",decode('&4','random','order by dbms_random.value(1,1e20)','') "4" from dual;
SET TERMOUT ON 

var orgv number;
var newv number;

DECLARE
    ret    NUMBER;
    strval VARCHAR2(300):=replace(upper('&2'),'B');
    newv   NUMBER;
BEGIN
    newv := regexp_substr(strval,'^(\d+)[K|M|G]?$',1,1,'i',1);
    IF newv IS NULL THEN
        raise_application_error(-20001,'Invalid value of _query_execution_cache_max_size: &2');
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
col deterministic_hit_ratio for a23
col SCALARQUERY_HIT_RATIO for a23
col combine_hit_ratio for a23
PRO CASE:  NDV=&1  _query_execution_cache_max_size=&2 loops=&3
PRO ==========================================================
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
r  AS (SELECT ROWNUM r,SYSDATE+ROWNUM d,SYSTIMESTAMP+NUMTODSINTERVAL(dbms_random.value*1e3,'day') ts FROM dual CONNECT BY ROWNUM<=&1),
r1 AS (SELECT /*+materialize ordered use_nl(b)*/ a.* FROM (SELECT * FROM r UNION ALL SELECT * FROM (SELECT * FROM r ORDER BY 1 DESC)) a,(select * from dual connect by rownum<=&3) b &4)
SELECT count(1) rows#,
       COUNT(DISTINCT r) "NDV",
       round(100*(count(1)-COUNT(DISTINCT c1(r,d)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' deterministic_hit_ratio,
       round(100*(count(1)-COUNT(DISTINCT (SELECT c2(r,ts) FROM dual)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' scalarquery_hit_ratio,
       round(100*(count(1)-COUNT(DISTINCT (SELECT c3(r,d,ts) FROM dual)))/ (count(1)-COUNT(DISTINCT r)),3)||'%' combine_hit_ratio
FROM r1
/
PRO  
UNDEF 1
UNDEF 2
UNDEF 3
UNDEF 4
BEGIN
    IF :orgv IS NOT NULL THEN
        EXECUTE IMMEDIATE 'alter session set "_query_execution_cache_max_size"='||:orgv;
    END IF;
END;
/
set feed on newp 1 verify on