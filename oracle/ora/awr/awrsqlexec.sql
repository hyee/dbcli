WITH qry AS
 (SELECT ROWNUM r, nvl(lower(:V2),'mem') typ, nvl(upper(:V1),'A') inst FROM dual CONNECT BY ROWNUM < 3)
SELECT d "DATE",
       inst_id || '(' || to_char(AVG(c), 'fm99000.00') || ')' inst_id,
       grp,
       SUM(DECODE(h, 0, c)) HH00,
       SUM(DECODE(h, 1, c)) HH01,
       SUM(DECODE(h, 2, c)) HH02,
       SUM(DECODE(h, 3, c)) HH03,
       SUM(DECODE(h, 4, c)) HH04,
       SUM(DECODE(h, 5, c)) HH05,
       SUM(DECODE(h, 6, c)) HH06,
       SUM(DECODE(h, 7, c)) HH07,
       SUM(DECODE(h, 8, c)) HH08,
       SUM(DECODE(h, 9, c)) HH09,
       SUM(DECODE(h, 10, c)) HH10,
       SUM(DECODE(h, 11, c)) HH11,
       SUM(DECODE(h, 12, c)) HH12,
       SUM(DECODE(h, 13, c)) HH13,
       SUM(DECODE(h, 14, c)) HH14,
       SUM(DECODE(h, 15, c)) HH15,
       SUM(DECODE(h, 16, c)) HH16,
       SUM(DECODE(h, 17, c)) HH17,
       SUM(DECODE(h, 18, c)) HH18,
       SUM(DECODE(h, 19, c)) HH19,
       SUM(DECODE(h, 20, c)) HH20,
       SUM(DECODE(h, 21, c)) HH21,
       SUM(DECODE(h, 22, c)) HH22,
       SUM(DECODE(h, 23, c)) HH23
FROM   (SELECT to_char(s.begin_interval_time, 'mm-dd') d,
               trunc(s.begin_interval_time) snap_time,
               0 + to_char(s.begin_interval_time, 'HH24') h,
               DECODE(r, 1, '-TOTAL-', 'SINGLE') grp,
               decode(qry.inst, 'A', 'A', '' || s.instance_number) inst_id,
               lpad(DECODE(qry.r || qry.typ,
                           '1mem',
                           to_char(total_sql_mem / 1024 / 1024, 'fm999990.0'),
                           '2mem',
                           to_char(hs.single_use_sql_mem / 1024 / 1024, 'fm999990.0'),
                           '1count',
                           '' || total_sql,
                           '' || single_use_sql),
                    6) c
        FROM   dba_hist_snapshot s, Dba_Hist_Sql_Summary hs, qry
        WHERE  s.snap_id = hs.snap_id
        AND    s.instance_number = hs.instance_number
        AND    s.dbid = hs.dbid
        AND    (qry.inst IN ('A', '0') OR qry.inst = '' || s.instance_number))
GROUP  BY snap_time, d, grp, inst_id
ORDER  BY snap_time, 2, 3
