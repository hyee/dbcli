WITH qry as(select nvl(upper(:V1),'0') inst,nvl(lower(:V2),'data') typ,nvl(upper(:V3),'RW') rw from dual )
SELECT d "DATE",
       inst_id||'('||to_char(sum(c),'99990')||')' inst_id,
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
               lpad(to_char(sum(decode(rw,'R',r,'W',w,r+w))/1024,'fm9999990.0'),6) c
        FROM   (SELECT to_char(s.begin_interval_time,'mm-dd') d,
                       trunc(s.begin_interval_time) snap_time,
                       qry.rw,
                       0 + to_char(s.begin_interval_time, 'HH24') h,
                       (small_read_megabytes+large_read_megabytes) - lag(small_read_megabytes+large_read_megabytes)
                           over(PARTITION BY s.dbid, s.instance_number,hs.FileType_name ORDER BY s.snap_id) r,
                       (small_write_megabytes+large_write_megabytes) - lag(small_write_megabytes+large_write_megabytes)
                           over(PARTITION BY s.dbid, s.instance_number,hs.FileType_name ORDER BY s.snap_id)  w,
                       decode(qry.inst,'A','A',''||s.instance_number) inst_id
                FROM   qry,dba_hist_snapshot s, Dba_Hist_Iostat_Filetype hs
                WHERE  s.snap_id = hs.snap_id
                AND    s.instance_number = hs.instance_number
                AND    s.dbid = hs.dbid
                AND    (qry.inst in('A','0') or qry.inst= ''||s.instance_number)
                AND    instr(qry.typ,lower(regexp_substr(hs.FileType_name,'\w+')))>0)
        WHERE r+w is not null
        GROUP  BY inst_id, d,h,snap_time)
GROUP  BY snap_time,d, inst_id
ORDER by snap_time,2