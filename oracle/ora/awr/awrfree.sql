WITH qry as(select nvl(upper(:V1),'0') inst from dual )
SELECT d "DATE",
       inst_id||'('||to_char(avg(c),'fm99999')||')' inst_id,
       MAX(DECODE(h, 0, c)) HH00,
       MAX(DECODE(h, 1, c)) HH01,
       MAX(DECODE(h, 2, c)) HH02,
       MAX(DECODE(h, 3, c)) HH03,
       MAX(DECODE(h, 4, c)) HH04,
       MAX(DECODE(h, 5, c)) HH05,
       MAX(DECODE(h, 6, c)) HH06,
       MAX(DECODE(h, 7, c)) HH07,
       MAX(DECODE(h, 8, c)) HH08,
       MAX(DECODE(h, 9, c)) HH09,
       MAX(DECODE(h, 10, c)) HH10,
       MAX(DECODE(h, 11, c)) HH11,
       MAX(DECODE(h, 12, c)) HH12,
       MAX(DECODE(h, 13, c)) HH13,
       MAX(DECODE(h, 14, c)) HH14,
       MAX(DECODE(h, 15, c)) HH15,
       MAX(DECODE(h, 16, c)) HH16,
       MAX(DECODE(h, 17, c)) HH17,
       MAX(DECODE(h, 18, c)) HH18,
       MAX(DECODE(h, 19, c)) HH19,
       MAX(DECODE(h, 20, c)) HH20,
       MAX(DECODE(h, 21, c)) HH21,
       MAX(DECODE(h, 22, c)) HH22,
       MAX(DECODE(h, 23, c)) HH23
FROM   (SELECT inst_id,
               d,
               h,
               snap_time,
               lpad(round(AVG(val)/power(1024,2)),5) c
        FROM   (SELECT to_char(s.begin_interval_time,'mm-dd') d,
                       trunc(s.begin_interval_time) snap_time,
                       0 + to_char(s.begin_interval_time, 'HH24') h,
                       decode(qry.inst,'A','A',''||s.instance_number)  inst_id,
                       sum(hs.bytes) over(partition by s.snap_id,decode(qry.inst,'A','A',''||s.instance_number)) val
                FROM   qry,dba_hist_snapshot s, Dba_Hist_Sgastat hs
                WHERE  s.snap_id = hs.snap_id
                AND    s.instance_number = hs.instance_number
                AND    s.dbid = hs.dbid
                AND    (qry.inst in('A','0') or qry.inst= ''||s.instance_number)
                AND    hs.name like 'free%')
        WHERE val is not null
        GROUP  BY inst_id, d,h,snap_time)
GROUP  BY snap_time,d, inst_id
ORDER by snap_time,2
