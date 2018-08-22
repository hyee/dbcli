/*[[get latch info: latchprof {<sid|sql_id> [event] [seconds} [-addr|-block]
     --[[
        &fields: default={inst_id,sid,name,sql_id,obj} f={inst_id,sid,name,laddr,sql_id,obj} block={inst_id,sid,name,sql_id,obj,block#}
        &V3    : default={5}
        @GV    : 11.1={TABLE(GV$(CURSOR(} default={(((}
     --]]
]]*/
--------------------------------------------------------------------------------
--
-- File name:   latchprof.sql ( Latch Holder Profiler )
-- Purpose:     Perform high-frequency sampling on V$LATCHHOLDER
--              and present a profile of latches held by sessions
--
-- Author:      Tanel Poder
-- Copyright:   (c) http://www.tanelpoder.com
--
-- Usage:       @latchprof <what> <sid> <latch name> <#samples>
--              @latchprof name 350 % 100000                - monitor all latches SID 350 is holding
--              @latchprof sid,name % library 1000000       - monitor which SIDs hold latches with "library" in their name
--              @latchprof sid,name,laddr % 40D993A0 100000 - monitor which SIDs hold child latch with address 0x40D993A0
-- Other:
--              The sampling relies on NESTED LOOP join method and having
--              V$LATCHHOLDER as the inner (probed) table. Note that on 9i
--              you may need to run this script as SYS as it looks like otherwise
--              the global USE_NL hint is not propagated down to X$ base tables
--
--              The join in exec plan step 8 MUST be a NESTED LOOPS join, this is how
--              the high speed sampling of changing dataset from V$LATCHHOLDER
--              is done, otherwise you will not see correct results.
--
-- -----------------------------------------------------------------------------------------------
-- | Id  | Operation                            | Name       | E-Rows |  OMem |  1Mem | Used-Mem |
-- -----------------------------------------------------------------------------------------------
-- |   1 |  MERGE JOIN CARTESIAN                |            |      1 |       |       |          |
-- |   2 |   MERGE JOIN CARTESIAN               |            |      1 |       |       |          |
-- |*  3 |    FIXED TABLE FULL                  | X$KSUTM    |      1 |       |       |          |
-- |   4 |    BUFFER SORT                       |            |      1 |  9216 |  9216 | 8192  (0)|
-- |   5 |     VIEW                             |            |      1 |       |       |          |
-- |   6 |      SORT ORDER BY                   |            |      1 |  2048 |  2048 | 2048  (0)|
-- |   7 |       SORT GROUP BY                  |            |      1 |  9216 |  9216 | 8192  (0)|
-- |   8 |        NESTED LOOPS                  |            |      1 |       |       |          |
-- |   9 |         VIEW                         |            |      1 |       |       |          |
-- |  10 |          CONNECT BY WITHOUT FILTERING|            |        |       |       |          |
-- |  11 |           FAST DUAL                  |            |      1 |       |       |          |
-- |* 12 |         FIXED TABLE FULL             | X$KSUPRLAT |      1 |       |       |          |
-- |  13 |   BUFFER SORT                        |            |      1 |  9216 |  9216 | 8192  (0)|
-- |* 14 |    FIXED TABLE FULL                  | X$KSUTM    |      1 |       |       |          |
-- -----------------------------------------------------------------------------------------------
--
--              If you want to drill down to latch child level, include "laddr" in first parameter
--              to latchprof
--
--              Then you can use la.sql (V$LATCH_PARENT/V$LATCH_CHILDREN) to
--              map the latch address back to latch child# if needed
--
--------------------------------------------------------------------------------
PRO Sampling, it could take around &V3 seconds ...

WITH
    t1 AS (SELECT hsecs FROM v$timer),
    sam AS (
      SELECT * FROM &GV
        SELECT /*+ opt_param('_optimizer_mjc_enabled','false') ORDERED ORDERED_PREDICATES USE_NL(s2 s) USE_NL(l l.gv$latchholder.x$ksuprlat) NO_TRANSFORM_DISTINCT_AGG  no_expand*/
            &fields
          , COUNT(DISTINCT gets)           dist_samples
          , COUNT(*)                       total_samples
          , COUNT(*)/max(max(r)) over()    sample_rate
        FROM
            (SELECT hsecs+&v3*100 target,rownum r 
             FROM v$timer
             WHERE  userenv('instance')=nvl(:instance,userenv('instance'))
             CONNECT BY LEVEL <= &v3*5e4) s1,
            (select hsecs from v$timer) s2,
            v$latchholder l,
            (SELECT /*+MERGE MERGE(s)*/ userenv('instance') inst_id
                  , sid  indx
                  , ROW_WAIT_OBJ# obj
                  , nvl2(nullif(ROW_WAIT_FILE#,0),ROW_WAIT_FILE#||','||ROW_WAIT_BLOCK#,'') block#
                  , sql_id
             FROM v$session s
             WHERE  ('&V1' is null or '&V1' in(sql_id,''||sid))) s
        WHERE s2.hsecs<s1.target
        AND  (LOWER(l.name) LIKE LOWER('%&V2%') OR LOWER(RAWTOHEX(l.laddr)) LIKE LOWER('%&V2%'))
        AND  l.sid = s.indx
        AND  inst_id=nvl(:instance,inst_id)
        GROUP BY &fields
    )))
    ORDER BY total_samples DESC),
    t2 AS (SELECT hsecs FROM v$timer)
SELECT /*+ ORDERED monitor*/
       &fields,
       s.total_samples "Held",
       s.dist_samples "Gets",
       round(s.total_samples/nullif(sum(s.total_samples) over(),0) * 100,2)  "Held %",
       round((t2.hsecs - t1.hsecs) * 10 * sample_rate,3) "Held ms",
       round((t2.hsecs - t1.hsecs) * 10 * sample_rate / dist_samples,3) "Avg hold ms",
       round(sample_rate*100,3) "Seen %"
FROM t1,sam s,t2
WHERE ROWNUM <= 50;

