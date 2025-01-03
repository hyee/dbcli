/*[[Show Cell IO Reasons. Usage: @@NAME [<keyword>] {[-r] [-d]} | {<seconds> [-avg]}
    Parameters:
       <keyword> :  case-insensitive expression
       -r        :  the keyword is a Regular expression instead of a LIKE expression
       -d        :  Show IO reason if dba_hist_io_reason instead of v$cell_ioreason
       <seconds> :  take 2 snapshots with the specific seconds, then print the delta stats
       -avg      :  when <seconds> is specified, devide the delta stats with <seconds> instead of the total stats

    --[[
        @check_access_obj: v$cell_ioreason={}
        @CHECK_ACCESS_SL : SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
        &avg             : default={1} avg={&V2}
        &filter          : {
            like={upper(reason_name) LIKE upper('%&V1%')}
            r={regexp_like(reason_name,'&V1','i')}
        }
        &typ             : default={g} d={d}
    --]]
]]*/
col reqs for tmb
col bytes,avg_bytes for kmg
set verify off feed off sep4k on printsize 1000
var cur refcursor
DECLARE
    v_stmt VARCHAR2(32767);
    v     VARCHAR2(300) := :v1;
BEGIN
    IF regexp_like(:V2,'^\d+$') THEN
        v_stmt :=q'[
            WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
                BEGIN
                    IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
                    &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
                    RETURN SYSTIMESTAMP;
                END;
                SELECT reason_name,
                       bytes,
                       reqs,
                       ratio_to_report(reqs) over() "%",
                       round(bytes / nullif(reqs,0), 2) avg_bytes,
                       CASE WHEN bytes / nullif(reqs,0) >= 128 * 1024 THEN 'YES' ELSE 'NO' END large_io
                FROM (
                    SELECT /*+ordered use_nl(timer stat) no_expand outline_leaf*/
                           reason_name,n,
                           SUM(v*DECODE(r, 1, -1, 1))/&AVG v
                    FROM   (SELECT ROWNUM r, sysdate+numtodsinterval(&V2,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                            LATERAL (SELECT  do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                            LATERAL (SELECT  reason_name, metric_name n, metric_value v FROM v$cell_ioreason a WHERE timer.stime IS NOT NULL) stat
                    GROUP  BY reason_name,n
                ) PIVOT(MAX(v) FOR n IN('Per Reason Bytes of IO' bytes, 'Per Reason Number of IOs' reqs))
                WHERE  (:v IS NULL AND bytes > 0 OR :v IS NOT NULL AND (&FILTER)) 
                ORDER  BY reqs DESC]';
        --dbms_output.put_line(v_stmt);
        OPEN :cur FOR v_stmt USING v,v;
    ELSIF :typ='g' THEN
        OPEN :cur FOR
                  SELECT reason_name,
                         bytes,
                         reqs,
                         ratio_to_report(reqs) over() "%",
                         round(bytes / nullif(reqs,0), 2) avg_bytes,
                         CASE WHEN bytes / nullif(reqs,0) >= 128 * 1024 THEN 'YES' ELSE 'NO' END large_io
                  FROM   (SELECT reason_name, nvl(METRIC_TYPE,'reqs') n, SUM(metric_value) v 
                            FROM  (select reason_name,metric_type,metric_value 
                           from   v$cell_ioreason
                           union all
                           select decode(r,1,'Scrub reads','Internal IO'),
                                  metric_type,decode(r,1,-1)*metric_value 
                           from   v$cell_global,
                                  (SELECT 1 R FROM DUAL UNION ALL SELECT 2 FROM DUAL)
                           where  metric_name in('Scrub reads','Scrub read bytes'))
                            WHERE (v IS NULL OR (&FILTER)) 
                            GROUP BY reason_name, METRIC_TYPE
                    HAVING v IS NOT NULL OR sum(metric_value)>0)
                  PIVOT(MAX(v) FOR n IN('bytes' bytes, 'reqs' reqs))
                  ORDER  BY reqs DESC;
    ELSE
        OPEN :cur FOR
            SELECT a.*,
                   ratio_to_report(reqs) over() "%",
                   ROUND(bytes / nullif(reqs, 0)) avg_bytes,
                   CASE
                       WHEN bytes / nullif(reqs, 0) >= 128 * 1024 THEN
                        'YES'
                       ELSE
                        'NO'
                   END large_io
            FROM   (SELECT reason_name, SUM(bytes) bytes, SUM(reqs) reqs
                    FROM   (SELECT cell_hash,
                                   dbid,
                                   con_dbid,
                                   REASON_NAME,
                                   MAX(REQUESTS) KEEP(dense_rank LAST ORDER BY SNAP_ID) - MIN(REQUESTS) KEEP(dense_rank FIRST ORDER BY SNAP_ID) reqs,
                                   MAX(bytes) KEEP(dense_rank LAST ORDER BY SNAP_ID) - MIN(bytes) KEEP(dense_rank FIRST ORDER BY SNAP_ID) bytes
                            FROM   (
                                SELECT con_dbid,dbid,snap_id,cell_hash,INCARNATION_NUM,REASON_NAME,SUM(REQUESTS) REQUESTS,SUM(BYTES) BYTES
                                FROM (
                                   SELECT /*+leading(a.s) full(a.s) no_index(a.s)*/ 
                                          con_dbid,dbid,snap_id,cell_hash,INCARNATION_NUM,REASON_NAME,REQUESTS,BYTES
                                   FROM  DBA_HIST_CELL_IOREASON a
                                   UNION ALL
                                   SELECT con_dbid,dbid,snap_id,cell_hash,INCARNATION_NUM,
                                          decode(r,1,'Scrub reads','Internal IO'),
                                          decode(r,1,1,-1)*max(decode(m,'Scrub reads',v)),
                                          decode(r,1,1,-1)*max(decode(m,'Scrub read bytes',v))
                                   FROM(
                                     SELECT /*+leading(a.s)*/ 
                                           con_dbid,dbid,snap_id,cell_hash,INCARNATION_NUM,metric_name m,metric_value v
                                     FROM  DBA_HIST_CELL_GLOBAL a
                                     WHERE METRIC_ID IN(360,361)
                                   ),(SELECT 1 R FROM DUAL UNION ALL SELECT 2 FROM DUAL)
                                   GROUP BY con_dbid,dbid,snap_id,cell_hash,INCARNATION_NUM,r)
                                GROUP BY con_dbid,dbid,snap_id,cell_hash,INCARNATION_NUM,REASON_NAME)
                            JOIN   dba_hist_snapshot
                            USING  (dbid,snap_id)
                            WHERE  end_interval_time+0 between nvl(to_date(:starttime,'YYMMDDHH24MI'),SYSDATE - 7) AND nvl(to_date(:endtime,'YYMMDDHH24MI'),SYSDATE)
                            AND    dbid=:dbid
                            GROUP  BY cell_hash, REASON_NAME, INCARNATION_NUM, dbid, con_dbid)
                    GROUP  BY dbid, con_dbid, reason_name) a
            WHERE reqs>0
            ORDER  BY reqs DESC;
    END IF;
END;
/
col "%" for pct
print cur