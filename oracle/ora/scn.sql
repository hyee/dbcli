/*[[
    Show SCN information or compute the time range for a specific SCN. Usage: @@NAME <inst_id>|0|<scn>

    Sample Output:
    ==============
                                                                                        SCN/Sec SCN/Sec SCN/Sec SCN/Sec Head Room
    DBID INST     BEGIN_TIME           END_TIME       DURATION LOGS FIRST_SCN LAST_SCN (kcmgas) ( Min ) ( Max ) ( Avg ) Left days
    ---- ---- ------------------- ------------------- -------- ---- --------- -------- -------- ------- ------- ------- ---------
         A    2019-04-07 07:06:23 2019-04-07 12:48:19    5.70h    1   3320937  3359977        2       2       2       2   11631.5
         A    2019-04-06 11:41:02 2019-04-07 07:06:23   19.42h    1   3271580  3320937        2       1       1       1   11631.3
         A    2019-04-06 07:17:37 2019-04-06 11:41:02    4.39h    1   3138823  3271580        1       8       8       8   11630.5
         A    2019-04-06 00:36:27 2019-04-06 07:17:37    6.69h    1   3098518  3138823        2       2       2       2   11630.3
         A    2019-04-05 16:02:43 2019-04-06 00:36:27    8.56h    1   3053960  3098518        2       1       1       1     11630
         A    2019-04-04 23:11:02 2019-04-05 16:02:43   16.86h    1   3001493  3053960        1       1       1       1   11629.7
         A    2019-04-03 12:58:20 2019-04-04 23:11:02    1.43d    1   2898363  3001493        3       1       1       1     11629
         A    2019-04-03 09:22:49 2019-04-03 12:58:20    3.59h    3   2588444  2898363               16     583      24   11627.5
         A    2019-03-30 03:06:46 2019-04-03 09:22:49    4.26d    1   2470499  2588444                0       0       0   11627.4
         A    2019-03-29 22:00:32 2019-03-30 03:06:46    5.10h    1   2438033  2470499                2       2       2   11623.1
         A    2019-03-29 07:19:08 2019-03-29 22:00:32   14.69h    1   2386060  2438033                1       1       1   11622.9
         A    2019-03-28 10:56:30 2019-03-29 07:19:08   20.38h    1   2283480  2386060                1       1       1   11622.3
         A    2019-03-27 13:11:22 2019-03-28 10:56:30   21.75h    1   2174824  2283480                1       1       1   11621.5
         A    2017-01-22 07:04:07 2019-03-27 13:11:22  794.26d    1   2069701  2174824                0       0       0   11620.5
         A    2017-01-22 00:53:06 2017-01-22 07:04:07    6.18h    2   1921495  2069701                2      29       7   10809.3
         A    2017-01-21 19:42:17 2017-01-22 00:53:06    5.18h    1   1877975  1921495                2       2       2     10809
         A    2017-01-21 15:11:50 2017-01-21 19:42:17    4.51h    1   1835402  1877975                3       3       3   10808.8
         A    2017-01-21 11:01:29 2017-01-21 15:11:50    4.17h    1   1794978  1835402                3       3       3   10808.6
         A    2017-01-21 07:41:04 2017-01-21 11:01:29    3.34h    1   1757231  1794978                3       3       3   10808.5
         A    2017-01-21 06:00:48 2017-01-21 07:41:04    1.67h    1   1706761  1757231                8       8       8   10808.3
         A    2017-01-21 01:37:53 2017-01-21 06:00:48    4.38h    1   1671522  1706761                2       2       2   10808.2
         A    2017-01-21 00:40:55 2017-01-21 01:37:53   56.97m    2   1639377  1671522                9      29       9   10808.1
         A    2017-01-21 00:06:09 2017-01-21 00:40:55   34.77m    3   1401807  1639377               82     235     114     10808


    INST_ID CURRENT_SCN CHECKPOINT_CHANGE# CONTROLFILE_CHANGE# ARCHIVE_CHANGE# RESETLOGS_CHANGE#
    ------- ----------- ------------------ ------------------- --------------- -----------------
          1     3467869            3424487             3467858         3320937           1401807

    --[[
        @check_access_obj: sys.smon_scn_time={&scn} default={}
        &his_log: {
            default={
                select a.*, null dbid
                from   gv$log_history a,(SELECT inst_id, NULLIF(VALUE, '0') val FROM gv$parameter WHERE NAME = 'thread') b
                where  a.thread# = nvl(b.val, a.thread#)
                and    a.inst_id = b.inst_id
            }
            d={(select a.*,INSTANCE_NUMBER inst_id from dba_hist_log a)}
        }
        &scn: default={select -1 grp,0 dbid,0 thread#,t1.scn_wrp * (POWER(2,32)-1) + t1.scn_bas first_scn,t1.time_dp first_time,'sys.smon_scn_time' src from sys.smon_scn_time t1 union all} d={}   
    --]]
]]*/

set feed off verify on
var c1 refcursor;
var c2 refcursor;
col DURATION for smhd2
col "SCN/Sec|(kcmgas),SCN/Sec|( Min ),SCN/Sec|( Max ),SCN/Sec|( Avg )" for k0
DECLARE
    inst VARCHAR2(30) := upper(coalesce(:V1, :instance, 'A'));
    num  INT := nullif(regexp_substr(inst, '\d+'), '0');
    c1   SYS_REFCURSOR;
    c2   SYS_REFCURSOR;
    tim  DATE;
BEGIN
    IF nvl(num, 0) <= 128 THEN
        OPEN c1 FOR
            WITH a AS
             (SELECT /*+materialize*/
                     a.*,
                     LEAD(first_change#) OVER(PARTITION BY a.dbid, a.inst_id, thread# ORDER BY first_time) last_change#,
                     LEAD(first_time) OVER(PARTITION BY a.dbid, a.inst_id, thread# ORDER BY first_time) next_time
              FROM   (&his_log) a),
            stat AS
             (SELECT /*+materialize*/
                     trunc((SYSDATE - (end_interval_time + 0)) * 8) grp,
                     dbid,
                     CASE WHEN inst = 'A' THEN 'A' ELSE '' || instance_number END inst,
                     VALUE - nvl(lag(VALUE) over(PARTITION BY dbid, instance_number, startup_time ORDER BY snap_id), 0) val,
                     86400 *
                     (end_interval_time + 0 -
                     (nvl(lag(end_interval_time) over(PARTITION BY dbid, instance_number, startup_time ORDER BY snap_id),
                     begin_interval_time) + 0)) dur
              FROM   dba_hist_sysstat
              JOIN   dba_hist_snapshot
              USING  (snap_id, dbid, instance_number)
              WHERE  stat_name = 'calls to kcmgas'
              AND    instance_number = nvl(num, instance_number))
            SELECT dbid,
                   inst,
                   MIN(first_time) begin_time,
                   MAX(next_time) end_time,
                   86400 * (MAX(next_time) - MIN(first_time)) duration,
                   COUNT(1) logs,
                   MIN(FIRST_CHANGE#) first_scn,
                   MAX(LAST_CHANGE#) last_scn,
                   (SELECT round(SUM(val) / SUM(dur))
                    FROM   stat b
                    WHERE  b.inst = a.inst
                    AND    b.grp = a.grp
                    AND    b.dbid = nvl(a.dbid, b.dbid)) "SCN/Sec|(kcmgas)",
                   MIN(scn_per_sec) "SCN/Sec|( Min )",
                   MAX(scn_per_sec) "SCN/Sec|( Max )",
                   ROUND((MAX(LAST_CHANGE#) - MIN(FIRST_CHANGE#)) / ((MAX(NEXT_TIME) - MIN(FIRST_TIME)) * 86400)) "SCN/Sec|( Avg )",
                   MAX(room) KEEP(dense_rank LAST ORDER BY first_time) "Head Room|Left days"
            FROM   (SELECT CASE WHEN inst = 'A' THEN 'A' ELSE '' || inst_id END inst,
                           TRUNC((SYSDATE - next_time) * 8) grp,
                           a.*,
                           ROUND((LAST_CHANGE# - FIRST_CHANGE#) / ((NEXT_TIME - FIRST_TIME) * 86400)) scn_per_sec,
                           round(months_between(next_time, DATE '1988-1-1') * 31 - LAST_CHANGE# / 86400 / 16 / 1024, 1) room
                    FROM   a
                    WHERE  next_time > first_time
                    AND    a.inst_id = nvl(num, inst_id)) a
            GROUP  BY dbid, grp, inst
            ORDER  BY begin_time DESC, inst, end_time;
    
        OPEN c2 FOR
            SELECT inst_id, current_scn, CHECKPOINT_CHANGE#, CONTROLFILE_CHANGE#, ARCHIVE_CHANGE#, RESETLOGS_CHANGE#
            FROM   gv$database a
            WHERE  a.inst_id = nvl(num, inst_id)
            ORDER  BY 1;
    ELSE
        BEGIN
            tim := scn_to_timestamp(num);
            OPEN c1 FOR
                SELECT tim "SCN_TO_TIMSTAMP" FROM dual;
        EXCEPTION
            WHEN OTHERS THEN
                OPEN c1 FOR
                    WITH src AS
                     (SELECT a.*,
                             lead(first_scn) over(PARTITION BY dbid, grp, thread# ORDER BY first_time) next_scn,
                             lead(first_time) over(PARTITION BY dbid, grp, thread# ORDER BY first_time) next_time
                      FROM   (&check_access_obj
                              SELECT 0 grp, dbid, thread#, first_change# first_scn, first_time, 'log_history' src
                              FROM   (&his_log)) a
                      ),
                    lg AS
                     (SELECT /*+materialize*/ *
                      FROM   src
                      WHERE  grp = 0
                      AND    next_time > first_time),
                    lg1 AS
                     (SELECT dbid,
                             thread#,
                             MAX(next_time) - MIN(first_time) dur,
                             MAX(next_scn) - MIN(first_scn) scns,
                             ceil(greatest(MIN(first_scn) - num, num - MAX(next_scn)) /
                                  nullif(MAX(next_scn) - MIN(first_scn), 0)) gaps,
                             sign(num - MAX(next_scn)) dir
                      FROM   lg
                      GROUP  BY dbid, thread#)
                    SELECT dbid,
                           first_time +
                           ((num - first_scn) * (next_time - first_time) / nullif(next_scn - first_scn, 0)) est_time,
                           num input_scn,
                           first_scn,
                           next_scn,
                           first_time,
                           next_time,
                           src
                    FROM   (SELECT *
                            FROM   src
                            UNION ALL
                            SELECT -2,
                                   dbid,
                                   thread#,
                                   first_scn + scns * gaps * dir,
                                   first_time + dur * gaps * dir,
                                   '(estimate)' src,
                                   next_scn + scns * gaps * dir,
                                   next_time + dur * gaps * dir
                            FROM   lg
                            JOIN   lg1
                            USING  (dbid, thread#))
                    WHERE  num BETWEEN first_scn AND next_scn
                    AND    rownum < 2;
        END;
    END IF;
    :c1 := c1;
    :c2 := c2;
END;
/
