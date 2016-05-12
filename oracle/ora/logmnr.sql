/*[[
    Specify the period before querying v$logmnr_contents(default as recent 30 mins). Usage: @@NAME {[YYMMDDHH24MI] [YYMMDDHH24MI]}
    This commands requires the "SELECT ANY TRANSACTION" and the "execute" access right on dbms_logmnr
]]*/

SET FEED OFF
DECLARE
    TYPE t IS TABLE OF VARCHAR2(2000);
    t1 t;
    begin_time DATE:=nvl(to_date(:V1,'YYMMDDHH24MI'),SYSDATE-30/1440);
    end_time   DATE:=nvl(to_date(:V2,'YYMMDDHH24MI'),SYSDATE-30/1440);
BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_DATE_FORMAT=''YYYY-MM-DD HH24:MI:SS''';
    SELECT MAX(MEMBER) BULK COLLECT
    INTO   t1
    FROM   (SELECT group#,
                   MEMBER,
                   first_time,
                   nvl(MIN(first_time - 1e-5)
                       OVER(ORDER BY sequence# RANGE BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING),
                       SYSDATE + 10 / 1440) last_time
            FROM   v$logfile
            JOIN   v$log
            USING  (group#)
            WHERE  TYPE = 'ONLINE')
    WHERE  first_time <=end_time AND last_time>=begin_time
    GROUP  BY GROUP#;

    BEGIN
        sys.dbms_logmnr.end_logmnr;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    FOR i IN 1 .. t1.COUNT LOOP
        sys.dbms_logmnr.add_logfile(t1(i),
                                    CASE
                                        WHEN i = 1 THEN
                                         sys.dbms_logmnr.NEW
                                        ELSE
                                         sys.dbms_logmnr.ADDFILE
                                    END);
    END LOOP;
    sys.dbms_logmnr.start_logmnr(Options => sys.dbms_logmnr.COMMITTED_DATA_ONLY +
                                            sys.dbms_logmnr.DICT_FROM_ONLINE_CATALOG +
                                            sys.DBMS_LOGMNR.SKIP_CORRUPTION);

END;
/