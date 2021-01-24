/*[[Show gc remastering/read-mostly info of the target object. Usage: @@NAME [<object_id>|[<owner>.]<object_name>]
    --[[
        @12c: 19={} default={--}
        @CHECK_USER_SYSDBA: SYSDBA={1},default={0}
        @check_access_obj: cdb_objects={cdb_objects} dba_objects={dba_objects} default={all_objects}
    --]]
]]*/

findobj "&V1" 1 1
set feed off
VAR cur REFCURSOR
COL "AVG_OP|TIME,REMASTER|TIME,QUIESCE|TIME,FREEZE|TIME,CLEANUP|TIME,REPLAY|TIME,FIXWRITE|TIME,SYNC|TIME" for smhd2
VAR CUR1 REFCURSOR "Top Hot Objects"
DECLARE
    c SYS_REFCURSOR;
BEGIN
    IF :object_owner IS NOT NULL THEN
        OPEN :cur FOR
            SELECT OBJECT_ID,
                   OWNER,OBJECT_NAME,SUBOBJECT_NAME,
                   b.*,
                   '|' "|",
                   c.POLICY_EVENT,
                   TO_DATE(C.EVENT_dATE,'MM/DD/YYYY HH24:MI:SS') EVENT_DATE,
                   C.TARGET_INSTANCE_NUMBER Target_inst
            FROM   &check_access_obj a,v$gcspfmaster_info b,gv$policy_history c
            WHERE  a.data_object_id=b.data_object_id(+)
            AND    a.data_object_id=c.data_object_id(+)
            AND    a.owner=:object_owner
            AND    a.object_name=:object_name
            AND    nvl2(:object_subname,a.subobject_name,'_')=nvl(:object_subname,'_')
            ORDER  BY EVENT_DATE DESC NULLS LAST;
    ELSE/*Rules:
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
            SELECT INST_ID "INST",
                   &12c REMASTER_TYPE "REMASTER_TYPE",
                   &12c PERSISTENT_OBJECTS "PERSISTENT|OBJECTS",
                   REMASTER_OPS "REMASTER|OPS",
                   REMASTER_TIME/100 "REMASTER|TIME",
                   round(REMASTER_TIME/100/nullif(REMASTER_OPS,0),2) "AVG_OP|TIME",
                   CURRENT_OBJECTS "CURRENT|OBJECTS",
                   REMASTERED_OBJECTS "REMASTER|OBJECTS",
                   QUIESCE_TIME/100 "QUIESCE|TIME",
                   FREEZE_TIME/100 "FREEZE|TIME",
                   CLEANUP_TIME/100 "CLEANUP|TIME",
                   REPLAY_TIME/100 "REPLAY|TIME",
                   FIXWRITE_TIME/100 "FIXWRITE|TIME",
                   SYNC_TIME/100 "SYNC|TIME",
                   RESOURCES_CLEANED "RESOURCES|CLEANED",
                   REPLAYED_LOCKS_SENT "REPLAYED|LOCKS_SENT",
                   REPLAYED_LOCKS_RECEIVED "REPLAYED|LOCKS_RECEIVED"
                   &12c ,CON_ID
            FROM   GV$DYNAMIC_REMASTER_STATS
            ORDER  BY 1,2;
        $IF &CHECK_USER_SYSDBA=1 $THEN
        OPEN c FOR
            WITH parms AS
             (SELECT /*+materialize*/
                     MAX(decode(KSPPINM, '_gc_policy_minimum', KSPPSTVL)) po,
                     MAX(decode(KSPPINM, '_gc_affinity_ratio', KSPPSTVL / 100)) aff,
                     MAX(decode(KSPPINM, '_gc_transfer_ratio', CASE WHEN KSPPSTVL>10 THEN KSPPSTVL/100 ELSE 1/KSPPSTVL END)) rd
              FROM   x$ksppcv a, x$ksppi b
              WHERE  b.indx = a.indx
              AND    KSPPINM IN ('_gc_policy_minimum', '_gc_affinity_ratio', '_gc_transfer_ratio')),
            stat AS
             (SELECT OBJECT data_object_id,
                     SUM(SOPENS) SOPENS,
                     SUM(XOPENS) XOPENS,
                     SUM(XFERS) XFERS,
                     SUM(DIRTY) DIRTY,
                     SUM(BUFF) BUFF,
                     MIN(CASE
                             WHEN sopens > xopens * INSTS * 2 AND --
                                  sopens > (SELECT po FROM parms) AND --
                                  sopens * (SELECT rd FROM parms) > xfers AND --
                                  dirty  * 100 < buff THEN
                              'Yes'
                             WHEN sopens + xopens > (SELECT po FROM parms) AND sopens < xopens * INSTS * 2 THEN
                              'No'
                         END) rd_mostly,
                     MAX(SOPENS + XOPENS) MAX_OPENS,
                     MAX(XOPENS) KEEP(dense_rank LAST ORDER BY SOPENS + XOPENS) MAX_XOPENS,
                     MAX(inst_id) KEEP(dense_rank LAST ORDER BY SOPENS + XOPENS) max_open_inst
              FROM   (SELECT A.*, COUNT(DISTINCT INST_ID) OVER() INSTS
                      FROM   TABLE(gv$(CURSOR(
                                SELECT OBJECT,INST_ID,SUM(SOPENS) SOPENS,SUM(XOPENS) XOPENS,SUM(XFERS) XFERS,SUM(DIRTY) DIRTY,
                                       MAX(BUFF) BUFF
                                FROM   x$object_policy_statistics
                                JOIN   (SELECT obj# OBJECT, SUM(num_buf) buff FROM X$KCBOQH GROUP BY obj#)
                                USING  (OBJECT)
                                GROUP  BY OBJECT,INST_ID))) a) A
              GROUP  BY OBJECT),
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
                                 WHEN MAX_OPENS > (SELECT po FROM parms) AND
                                      MAX_XOPENS > (XOPENS - MAX_XOPENS) * (SELECT aff FROM parms) THEN
                                   max_open_inst
                                 ELSE
                                   b.aff
                             END next_master,
                             NVL2(b.rd, 'Yes', 'No') curr_read_mostly,
                             NVL(rd_mostly, NVL2(b.rd, 'Yes', 'No')) next_read_mostly,
                             aff_cnt,
                             rd_cnt
                      FROM   stat a
                      FULL   JOIN (SELECT data_object_id,
                                         MAX(DECODE(GC_MASTERING_POLICY, 'Affinity', CURRENT_MASTER)) aff,
                                         MAX(DECODE(GC_MASTERING_POLICY, 'Affinity', REMASTER_CNT)) aff_cnt,
                                         MAX(DECODE(GC_MASTERING_POLICY, 'Read mostly', 'Y')) rd,
                                         MAX(DECODE(GC_MASTERING_POLICY, 'Read mostly', NVL(REMASTER_CNT,1))) rd_cnt
                                  FROM   v$gcspfmaster_info b
                                  GROUP  BY data_object_id) b
                      USING  (data_object_id)
                      ORDER  BY NVL(sopens + xopens + xfers,0) DESC,NVL(aff_cnt,0)+NVL(rd_cnt,0) DESC) a
              WHERE  ROWNUM <= 50)
            SELECT seq              "#",
                   owner,
                   object_name,
                   subobject_name,
                   data_object_id   dobj#,
                   object_type,
                   sopens,
                   xopens,
                   xfers,
                   buff,
                   dirty,
                   rd_cnt           "Count|Read-Mostly",
                   curr_read_mostly "Current|Read-Mostly",
                   next_read_mostly "Next|Read-Mostly",
                   aff_cnt          "Count|Remaster",
                   curr_master      "Current|Master",
                   next_master      "Next|Master"
            FROM   drm
            JOIN   &check_access_obj
            USING  (data_object_id)
            ORDER  BY seq;
        $ELSE
        OPEN c FOR
            SELECT seq              "#",
                   owner,
                   object_name,
                   subobject_name,
                   data_object_id   dobj#,
                   object_type,
                   aff_cnt          "Count|Remaster",
                   aff              "Current|Master",
                   aff_prev         "Prev|Master",
                   rd               "Current|Read-Mostly",
                   rd_cnt           "Count|Read-Mostly"
            FROM   (SELECT ROWNUM SEQ,A.* 
                    FROM (SELECT data_object_id,
                                 MAX(DECODE(GC_MASTERING_POLICY, 'Affinity', CURRENT_MASTER)) aff,
                                 MAX(DECODE(GC_MASTERING_POLICY, 'Affinity', REMASTER_CNT)) aff_cnt,
                                 MAX(DECODE(GC_MASTERING_POLICY, 'Affinity', PREVIOUS_MASTER)) aff_prev,
                                 MAX(DECODE(GC_MASTERING_POLICY, 'Read mostly', 'Y')) rd,
                                 MAX(DECODE(GC_MASTERING_POLICY, 'Read mostly', NVL(REMASTER_CNT,1))) rd_cnt
                          FROM   v$gcspfmaster_info b
                          GROUP  BY data_object_id
                          ORDER BY NVL(aff_cnt,0)+NVL(rd_cnt,0) DESC) A
                    WHERE ROWNUM<=50)
            JOIN   &check_access_obj
            USING  (data_object_id)
            ORDER  BY seq;
        $END
        :CUR1 := c;
    END IF;
END;
/