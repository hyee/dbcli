WITH qry AS
 (SELECT nvl(upper(:V1), 'A') inst,
         '%' || nullif(upper(:V2),'a') || '%' filter,
         to_date(nvl(:V3, to_char(SYSDATE - 1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') st,
         to_date(nvl(:V4, to_char(SYSDATE, 'YYMMDDHH24MI')),'YYMMDDHH24MI') ed
  FROM   dual)
SELECT *
FROM   (SELECT rownum "#",
               BF,
               SQL_ID,
               TOP_SQL,
               SOURCE,
               Last_time,
               WAITED,
               CALLS,
               EVENT,
               SUBSTR(OBJS, 1, 120) OBJS
        FROM   (SELECT decode(session_type, 'FOREGROUND', 'FG', 'BG') BF,
                       hs.sql_id,
                       filter,
                       nullif(hs.top_level_sql_id, hs.sql_id) top_sql,
                       MAX((SELECT nvl(MAX(c.object_name),
                                      '' || MAX(HS.plsql_entry_object_id))
                           FROM   DBA_OBJECTS c
                           WHERE  OBJECT_ID = HS.plsql_entry_object_id)) SOURCE,
                       to_char(MAX(sample_time), 'MON-DD-HH24:MI') Last_time,
                       count(distinct trunc(sample_time,'MI')) waited,
                       COUNT(DISTINCT nvl(nullif(SQL_EXEC_ID, 0), SEQ#)) calls,
                       event event,
                       to_char(wmsys.wm_concat(DISTINCT hs.current_obj#)) objs
                FROM   qry, gv$active_session_history hs
                WHERE  hs.sample_time BETWEEN st AND ed
                AND    (qry.inst IN ('A', '0') OR qry.inst = '' || hs.inst_id)
                GROUP  BY event, session_type, filter,hs.sql_id, top_level_sql_id
                ORDER  BY waited DESC)
        WHERE  upper(BF || chr(1) || sql_id || chr(1) || top_sql || chr(1) || SOURCE ||
                     chr(1) || event || chr(1) || objs) LIKE filter)
WHERE  "#" <= 50
ORDER  BY 1
