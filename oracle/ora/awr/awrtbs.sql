WITH qry AS
 (SELECT MIN(begin_interval_time) st, MAX(begin_interval_time) + 1e-4 ed
  FROM   Dba_Hist_Snapshot a
  WHERE  a.begin_interval_time between to_timestamp(nvl(:V1,to_char(sysdate-31,'YYMMDDHH24MI')),'YYMMDDHH24MI')
  AND    to_timestamp(nvl(:V2,to_char(sysdate,'YYMMDDHH24MI')),'YYMMDDHH24MI')+TO_DSINTERVAL('0 0:1:0')),
times AS
 (SELECT /*+materialize*/ ROWNUM r,
         st + (ed - st) / 12 * (ROWNUM - 1) + 0 st,
         st + (ed - st) / 12 * ROWNUM - TO_DSINTERVAL('0 0:0:1') ed
  FROM   qry
  CONNECT BY ROWNUM <= 12)
SELECT NAME,
       lpad(to_char(MAXSIZE, 'fm999990.00'), 8) MAXSIZE,
       lpad(to_char(MAXSIZE - tim12, 'fm999990.00'), 8) Free,
       lpad(to_char((tim12 - tim01) / nullif(days, 0), 'fm999990.00'), 7) Growth,
       lpad(to_char(tim01, 'fm999990.00'), 8) tim01,
       lpad(to_char(tim02, 'fm999990.00'), 8) tim02,
       lpad(to_char(tim03, 'fm999990.00'), 8) tim03,
       lpad(to_char(tim04, 'fm999990.00'), 8) tim04,
       lpad(to_char(tim05, 'fm999990.00'), 8) tim05,
       lpad(to_char(tim06, 'fm999990.00'), 8) tim06,
       lpad(to_char(tim07, 'fm999990.00'), 8) tim07,
       lpad(to_char(tim08, 'fm999990.00'), 8) tim08,
       lpad(to_char(tim09, 'fm999990.00'), 8) tim09,
       lpad(to_char(tim10, 'fm999990.00'), 8) tim10,
       lpad(to_char(tim11, 'fm999990.00'), 8) tim11,
       lpad(to_char(tim12, 'fm999990.00'), 8) tim12
FROM   (SELECT NAME,
               MAX(ed+0) - MIN(st+0) days,
               MAX(maxsize) keep(dense_rank last order by r) MAXSIZE,
               MAX(DECODE(r, 1, used)) tim01,
               MAX(DECODE(r, 2, used)) tim02,
               MAX(DECODE(r, 3, used)) tim03,
               MAX(DECODE(r, 4, used)) tim04,
               MAX(DECODE(r, 5, used)) tim05,
               MAX(DECODE(r, 6, used)) tim06,
               MAX(DECODE(r, 7, used)) tim07,
               MAX(DECODE(r, 8, used)) tim08,
               MAX(DECODE(r, 9, used)) tim09,
               MAX(DECODE(r, 10, used)) tim10,
               MAX(DECODE(r, 11, used)) tim11,
               MAX(DECODE(r, 12, used)) tim12
        FROM   (
               select /*+ordered*/ t.name,r,ed,st,
                      max(tablespace_maxsize) keep(dense_rank last ORDER BY s.snap_id)* 8 / 1024 / 1024 maxsize,
                      max(tablespace_usedsize) keep(dense_rank last ORDER BY s.snap_id)* 8 / 1024 / 1024 used
               FROM   times, dba_hist_snapshot s, dba_hist_tbspc_space_usage hs, v$tablespace t
               WHERE  s.snap_id = hs.snap_id
               AND    s.dbid = hs.dbid
               AND    hs.tablespace_id = t.ts#
               AND    s.begin_interval_time BETWEEN st AND ed
               GROUP  BY t.name,r,ed,st
        )
        GROUP  BY name)
UNION ALL
SELECT NULL,
       NULL,
       NULL,
       'Time-->',
       to_char(MAX(DECODE(r, 1, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 2, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 3, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 4, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 5, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 6, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 7, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 8, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 9, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 10, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 11, ed)), 'MM-DD HH24'),
       to_char(MAX(DECODE(r, 12, ed)), 'MM-DD HH24')
FROM   times
ORDER  BY 1 NULLS FIRST
