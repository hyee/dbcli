/*[[Get resource usage from SQL monitor. Usage: sqlm <sql_id> [A|A1|B [,<sid>]]  
    @CHECK_VERSION: 11.0={1}
]]*/

set feed off
var c cursor
BEGIN
    IF :V1 IS NOT NULL THEN
        OPEN :c FOR
            SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => decode(upper(:V2),
                                                                           'A1',
                                                                           'ALL',
                                                                           'A',
                                                                           'ALL-SESSIONS',
                                                                           'BASIC+PLAN'),
                                                    TYPE         => 'TEXT',
                                                    sql_id       => :V1,
                                                    session_id   => :V3) AS report
            FROM   dual;
    ELSE
        OPEN :c FOR
            SELECT *
            FROM   (SELECT /*+no_expand*/
                      a.sql_id, a.inst_id, a.SID, to_char(a.last_refresh_time, 'MMDD-HH24:MI:SS') tim,
                      -- NVL(floor(a.elapsed_time/(a.last_refresh_time-a.sql_exec_start)/(86400*1e6)),0) PX,
                      ROUND((a.last_refresh_time - a.sql_exec_start) * 1440, 2) ela,
                      substr(regexp_replace(regexp_replace(b.sql_text,
                                                            '^\s+|[' || CHR(10) || CHR(13) || ']'),
                                             '\s{2,}',
                                             ' '),
                              1,
                              200) sql_text
                     FROM   gv$sql_monitor a, gv$sqlarea b
                     WHERE  a.inst_id = b.inst_id
                     AND    a.sql_id = b.sql_id
                     AND    NOT regexp_like(a.process_name, '^p\d+$')
                     AND    b.SQL_TEXT NOT LIKE 'DECLARE job BINARY_INTEGER%'
                     AND    a.sql_id || lower(b.sql_text) LIKE '%' || lower(:V2) || '%'
                     ORDER  BY tim DESC)
            WHERE  ROWNUM <= 100
            ORDER  BY tim, ela;
    END IF;
END;
/