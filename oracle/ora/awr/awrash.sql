WITH qry AS
 (SELECT nvl(upper(:V1), 'A') inst,
         '%' || nullif(upper(:V2),'a') || '%' filter,
         to_timestamp(nvl(NVL(:V3,:STARTTIME), to_char(SYSDATE - 7, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') st,
         to_timestamp(coalesce(:V4,:ENDTIME, '' || (:V3 + 1), to_char(SYSDATE, 'YYMMDDHH24MI')),'YYMMDDHH24MI') ed
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
               SESS,
               EVENT,
               SUBSTR(OBJS, 1, 120) OBJS
        FROM   (SELECT /*+ordered use_nl(qry,s,hs,b)*/
                 decode(session_type, 'FOREGROUND', 'FG', 'BG') BF,
                 hs.sql_id,
                 filter,
                 /*nullif(hs.top_level_sql_id, hs.sql_id)*/ null top_sql,
                 MAX((SELECT nvl(MAX(c.object_name), '' ||  MAX(HS.plsql_entry_object_id))
                  FROM   DBA_OBJECTS c
                  WHERE  OBJECT_ID = HS.plsql_entry_object_id)) SOURCE,
                 to_char(MAX(sample_time), 'MON-DD-HH24:MI') Last_time,
                 count(DISTINCT trunc(sample_time,'MI')) waited,
                 COUNT(1) calls,
                 count(DISTINCT session_id) sess,
                 event event,
                 /*to_char(wm_concat(DISTINCT b.object_name))*/ null objs
                FROM   qry,
                       DBA_hist_snapshot            s,
                       DBA_Hist_Active_Sess_History hs,
                       DBA_HIST_SEG_STAT_OBJ        b
                WHERE  s.snap_id = hs.snap_id
                AND    s.instance_number = hs.instance_number
                AND    s.dbid = hs.dbid
                AND    hs.current_obj# = b.obj#(+)
                AND    hs.dbid = b.dbid(+)
                AND    b.object_name(+) NOT LIKE '%UNAVAILABLE%'
                AND    s.begin_interval_time BETWEEN qry.st-1/48 AND ed+1/48
                and    sample_time+0  BETWEEN qry.st AND ed
                AND    (qry.inst IN ('A', '0') OR qry.inst = '' || s.instance_number)
                GROUP  BY event, session_type, filter,hs.sql_id--, top_level_sql_id
                ORDER  BY waited DESC)
        WHERE  upper(BF || chr(1) || sql_id || chr(1) || top_sql || chr(1) || SOURCE ||
                     chr(1) || event || chr(1) || objs) LIKE filter)
WHERE  "#" <= 50
ORDER  BY 1
