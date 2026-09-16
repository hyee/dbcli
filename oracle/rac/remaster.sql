/*[[
    Show gc remastering/read-mostly info of the target object
    =========================================================
    Show the DRM(remastering) and read-mostly info of one object, or the top 50 hot objects of the
    instance. Usage: @@NAME [<object_id>|[<owner>.]<object_name>]

    Notes:
    ------
    - the read-mostly decision follows the _gc_policy_minimum / _gc_affinity_ratio /
      _gc_transfer_ratio parameters, and is computed in the stat CTE regardless of the current
      policy; next_read_mostly/next_master show what the policy would decide now
    - the details are only computed for SYSDBA, a normal DBA gets the current
      affinity/read-mostly state from v$gcspfmaster_info instead
    - an object with a data_object_id above 4294950912 is reported as 'USN #<n>', that is the
      rollback segment id
    - the 'Persistent|Read-mostly' column is 'Y' only when the segment flag bit 28 of sys.seg$(or
      sys_dba_segs) is set, which stands for a read-mostly object that was made persistent
    --[[
        @12c: 19={} default={--}
        @CHECK_USER_SYSDBA: SYSDBA={1},default={0}
        @check_access_obj: cdb_objects={cdb_objects} dba_objects={dba_objects} default={all_objects}
        @check_access_seg: sys.sys_dba_segs={(select SEGMENT_OBJD,segment_flags from sys.sys_dba_segs)} default={(select 0+null SEGMENT_OBJD,0+null segment_flags from dual)}
    --]]
]]*/

findobj "&V1" 1 1
SET FEED OFF
VAR cur REFCURSOR
COL "AVG_OP|TIME,REMASTER|TIME,QUIESCE|TIME,FREEZE|TIME,CLEANUP|TIME,REPLAY|TIME,FIXWRITE|TIME,SYNC|TIME" FOR smhd2
VAR CUR1 REFCURSOR "Top Hot Objects"
DECLARE
    c SYS_REFCURSOR;
BEGIN
    IF :object_owner IS NOT NULL THEN
        OPEN :cur FOR
            SELECT object_id,
                   owner,
                   object_name,
                   subobject_name,
                   b.*,
                   '|' "|",
                   c.policy_event,
                   to_date(c.event_date, 'MM/DD/YYYY HH24:MI:SS') event_date,
                   c.target_instance_number target_inst
            FROM   &check_access_obj a, v$gcspfmaster_info b, gv$policy_history c
            WHERE  a.data_object_id = b.data_object_id(+)
            AND    a.data_object_id = c.data_object_id(+)
            AND    a.owner = :object_owner
            AND    a.object_name = :object_name
            AND    nvl2(:object_subname, a.subobject_name, '_') = nvl(:object_subname, '_')
            ORDER  BY event_date DESC NULLS LAST;
    ELSE /*Rules:
          The default for _gc_policy_minimum is 1500 means that once we access blocks in the object 1500 times
          we make a decision on whether to make the object affinity or read mostly.

          switch to read-mostly when
          1) total Sopens are above _gc_policy_minimum,
          2) all nodes have done much more Sopens than Xopens (total Xopens * #inst * 2),
          3) total Sopens * _gc_transfer_ratio is more than total number of transfers(total XFERS),
          4) there are not too many dirty buffers (total dirty < 1% of cache size)

          dissolve read-mostly when
          1) total Sopens and Xopens are above _gc_policy_minimum,
          2) total Sopens are below (total Xopens * #insts * 2)

          Initiate affinity when
          1) the node with the highest number of opens opened more than _gc_policy_minimum,
          2) opened more locks than the amount of locks opened on other nodes * _gc_affinity_ratio (default 50)
        */
        OPEN :cur FOR
            SELECT inst_id "INST",
                   &12c REMASTER_TYPE "REMASTER_TYPE",
                   &12c PERSISTENT_OBJECTS "PERSISTENT|OBJECTS",
                   remaster_ops "REMASTER|OPS",
                   remaster_time / 100 "REMASTER|TIME",
                   round(remaster_time / 100 / nullif(remaster_ops, 0), 2) "AVG_OP|TIME",
                   current_objects "CURRENT|OBJECTS",
                   remastered_objects "REMASTER|OBJECTS",
                   quiesce_time / 100 "QUIESCE|TIME",
                   freeze_time / 100 "FREEZE|TIME",
                   cleanup_time / 100 "CLEANUP|TIME",
                   replay_time / 100 "REPLAY|TIME",
                   fixwrite_time / 100 "FIXWRITE|TIME",
                   sync_time / 100 "SYNC|TIME",
                   resources_cleaned "RESOURCES|CLEANED",
                   replayed_locks_sent "REPLAYED|LOCKS_SENT",
                   replayed_locks_received "REPLAYED|LOCKS_RECEIVED"
                   &12c ,CON_ID
            FROM   gv$dynamic_remaster_stats
            ORDER  BY 1, 2;
        $IF &CHECK_USER_SYSDBA=1 $THEN
        OPEN c FOR
            WITH parms AS
             (SELECT /*+materialize*/
                     max(decode(ksppinm, '_gc_policy_minimum', ksppstvl)) po,
                     max(decode(ksppinm, '_gc_affinity_ratio', ksppstvl / 100)) aff,
                     max(decode(ksppinm, '_gc_transfer_ratio', CASE WHEN ksppstvl > 10 THEN ksppstvl / 100 ELSE 1 / ksppstvl END)) rd
              FROM   sys.x$ksppcv a, sys.x$ksppi b
              WHERE  b.indx = a.indx
              AND    ksppinm IN ('_gc_policy_minimum', '_gc_affinity_ratio', '_gc_transfer_ratio')),
            stat AS
             (SELECT object data_object_id,
                     sum(sopens) sopens,
                     sum(xopens) xopens,
                     sum(xfers) xfers,
                     sum(dirty) dirty,
                     sum(buff) buff,
                     min(CASE
                             WHEN sopens > xopens * insts * 2 AND --
                                  sopens > (SELECT po FROM parms) AND --
                                  sopens * (SELECT rd FROM parms) > xfers AND --
                                  dirty  * 100 < buff THEN
                              'Yes'
                             WHEN sopens + xopens > (SELECT po FROM parms) AND sopens < xopens * insts * 2 THEN
                              'No'
                         END) rd_mostly,
                     max(sopens + xopens) max_opens,
                     max(xopens) KEEP(dense_rank LAST ORDER BY sopens + xopens) max_xopens,
                     max(inst_id) KEEP(dense_rank LAST ORDER BY sopens + xopens) max_open_inst
              FROM   (SELECT a.*, count(DISTINCT inst_id) OVER() insts
                      FROM   TABLE(gv$(CURSOR(
                                SELECT object, inst_id, sum(sopens) sopens, sum(xopens) xopens, sum(xfers) xfers, sum(dirty) dirty,
                                       max(buff) buff
                                FROM   sys.x$object_policy_statistics
                                JOIN   (SELECT obj# object, sum(num_buf) buff FROM sys.x$kcboqh GROUP BY obj#)
                                USING  (object)
                                GROUP  BY object, inst_id))) a) a
              GROUP  BY object),
            drm AS
             (SELECT /*+materialize*/ROWNUM seq, a.*
              FROM   (SELECT data_object_id,
                             sopens,
                             xopens,
                             xfers,
                             buff,
                             dirty,
                             b.aff curr_master,
                             CASE
                                 WHEN max_opens > (SELECT po FROM parms) AND
                                      max_xopens > (xopens - max_xopens) * (SELECT aff FROM parms) THEN
                                   max_open_inst
                                 ELSE
                                   b.aff
                             END next_master,
                             nvl2(b.rd, 'Yes', 'No') curr_read_mostly,
                             nvl(rd_mostly, nvl2(b.rd, 'Yes', 'No')) next_read_mostly,
                             aff_cnt,
                             aff_prev,
                             rd_cnt
                      FROM   stat a
                      FULL   JOIN (SELECT data_object_id,
                                         max(decode(gc_mastering_policy, 'Affinity', current_master)) aff,
                                         max(decode(gc_mastering_policy, 'Affinity', remaster_cnt)) aff_cnt,
                                         max(decode(gc_mastering_policy, 'Affinity', previous_master)) aff_prev,
                                         max(decode(gc_mastering_policy, 'Read mostly', 'Y')) rd,
                                         max(decode(gc_mastering_policy, 'Read mostly', nvl(remaster_cnt, 1))) rd_cnt
                                  FROM   v$gcspfmaster_info b
                                  GROUP  BY data_object_id) b
                      USING  (data_object_id)
                      ORDER  BY nvl(sopens + xopens + xfers, 0) DESC, nvl(aff_cnt, 0) + nvl(rd_cnt, 0) DESC) a
              WHERE  ROWNUM <= 50)
            SELECT seq "#",
                   owner,
                   nvl(object_name, CASE WHEN data_object_id > 4294950912 THEN 'USN #' || (data_object_id - 4294950912) END) object_name,
                   subobject_name,
                   data_object_id dobj#,
                   object_type,
                   sopens,
                   xopens,
                   xfers,
                   buff buffers,
                   dirty,
                   nvl2(b.hwmincr, 'Y', 'N') "Persistent|Read-mostly",
                   rd_cnt "Count|Read-Mostly",
                   curr_read_mostly "Current|Read-Mostly",
                   next_read_mostly "Next|Read-Mostly",
                   aff_cnt "Count|Remaster",
                   aff_prev "Prev|Master",
                   curr_master "Current|Master",
                   next_master "Next|Master"
            FROM   drm a
            LEFT   JOIN &check_access_obj
            USING  (data_object_id)
            LEFT   JOIN sys.seg$ b
            ON     data_object_id = b.hwmincr AND bitand(b.spare1, power(2, 28)) > 0
            ORDER  BY seq;
        $ELSE
        OPEN c FOR
            SELECT seq "#",
                   owner,
                   nvl(object_name, CASE WHEN data_object_id > 4294950912 THEN 'USN #' || (data_object_id - 4294950912) END) object_name,
                   subobject_name,
                   data_object_id dobj#,
                   object_type,
                   nvl2(segment_objd, 'Y', 'N') "Persistent|Read-mostly",
                   aff_cnt "Count|Remaster",
                   aff "Current|Master",
                   aff_prev "Prev|Master",
                   rd "Current|Read-Mostly",
                   rd_cnt "Count|Read-Mostly"
            FROM   (SELECT ROWNUM seq, a.*
                    FROM   (SELECT data_object_id,
                                   max(decode(gc_mastering_policy, 'Affinity', current_master)) aff,
                                   max(decode(gc_mastering_policy, 'Affinity', remaster_cnt)) aff_cnt,
                                   max(decode(gc_mastering_policy, 'Affinity', previous_master)) aff_prev,
                                   max(decode(gc_mastering_policy, 'Read mostly', 'Y')) rd,
                                   max(decode(gc_mastering_policy, 'Read mostly', nvl(remaster_cnt, 1))) rd_cnt
                            FROM   v$gcspfmaster_info b
                            GROUP  BY data_object_id
                            ORDER  BY nvl(aff_cnt, 0) + nvl(rd_cnt, 0) DESC) a
                    WHERE  ROWNUM <= 50)
            LEFT   JOIN &check_access_obj o
            USING  (data_object_id)
            LEFT   JOIN &check_access_seg c
            ON     c.segment_objd = data_object_id AND bitand(c.segment_flags, power(2, 28)) > 0
            ORDER  BY seq;
        $END
        :CUR1 := c;
    END IF;
END;
/
