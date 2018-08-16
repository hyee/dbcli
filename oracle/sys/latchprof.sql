/*[[
 Perform high-frequency sampling on V$LATCHHOLDER and present a profile of latches held by sessions including extended statistics about in which kernel function the latch held was taken
 Usage:       @@NAME [<sid>] [<what>] [<latch name>] [<#samples>]

 File name:   latchprofx.sql ( Latch Holder Profiler eXtended )
 Author:      Tanel Poder
 Copyright:   (c) http://www.tanelpoder.com  

 Examples:    @@NAME 350 name % 100000                   - monitor all latches SID 350 is holding
              @@NAME % sid,name library 1000000          - monitor which SIDs hold latches with "library" in their name
              @@NAME % sid,name,laddr 40D993A0 100000    - monitor which SIDs hold child latch with address 0x40D993A0
              @@NAME % sid,name,func % 100000            - monitor all sessions and latches and show
                                                           latch get Where info (locations in kernel code
                                                           where the latch get was done)

              @@NAME 89 sid,name,hmode,func "cache buffers chains" 100000
                                                         - monitor functions that took latch for SID 89 only
                                                           and report only "cache buffers chains" latch holders
                                                           also report hold mode HMODE (shared or exclusive)

              @@NAME % sid,name,hmode,func,object 40D993A0 100000
                                                         - monitor for what object's access the child latch at
                                                           particular address was taken. for cache buffers chains
                                                           latch the object means data block address (DBA)
                                                           of the block accessed in buffer cache.
                                                           you can translate the 6-byte DBA to rfile#/block#
                                                           using dbms_utility or dba.sql script from TPT scripts

 Other:       This script is based on X$ tables instead of V$ tables
              as some info required is not externalized to V$.
              So you need to run this script either as SYS or
              need to have relevant X$ proxy views created

              The sampling relies on NESTED LOOP join method and having
              X$KSUPRLAT as the inner (probed) table. 

              If sampling always reports a single latch event even though 
              many different events (or parameter values) are expected then 
              the execution plan used is not right.

              The join in exec plan step 9 MUST be a NESTED LOOPS join, this is how
              the high speed sampling is done.

 -----------------------------------------------------------------------------------------------------
 | Id  | Operation                             | Name            | E-Rows |  OMem |  1Mem | Used-Mem |
 -----------------------------------------------------------------------------------------------------
 |   1 |  MERGE JOIN CARTESIAN                 |                 |      1 |       |       |          |
 |   2 |   MERGE JOIN CARTESIAN                |                 |      1 |       |       |          |
 |*  3 |    FIXED TABLE FULL                   | X$KSUTM         |      1 |       |       |          |
 |   4 |    BUFFER SORT                        |                 |      1 |  9216 |  9216 | 8192  (0)|
 |   5 |     VIEW                              |                 |      1 |       |       |          |
 |   6 |      SORT ORDER BY                    |                 |      1 |  2048 |  2048 | 2048  (0)|
 |   7 |       HASH GROUP BY                   |                 |      1 |       |       |          |
 |   8 |        NESTED LOOPS OUTER             |                 |      1 |       |       |          |
 |   9 |         NESTED LOOPS                  |                 |      1 |       |       |          |
 |  10 |          VIEW                         |                 |      1 |       |       |          |
 |  11 |           CONNECT BY WITHOUT FILTERING|                 |        |       |       |          |
 |  12 |            FAST DUAL                  |                 |      1 |       |       |          |
 |* 13 |          FIXED TABLE FULL             | X$KSUPRLAT      |      1 |       |       |          |
 |* 14 |         FIXED TABLE FIXED INDEX       | X$KSLLW (ind:2) |      1 |       |       |          |
 |  15 |   BUFFER SORT                         |                 |      1 |  9216 |  9216 | 8192  (0)|
 |* 16 |    FIXED TABLE FULL                   | X$KSUTM         |      1 |       |       |          |
 -----------------------------------------------------------------------------------------------------

              If you want to drill down to latch child level, include "name" in first parameter to latchprof

              Then you can use la.sql (V$LATCH_PARENT/V$LATCH_CHILDREN) to
              map the latch address back to latch child#
    --[[
        &V1: default={%}
        &V2: default={sess#,name,hmode,func,object} func={sid,name,func}
        &V3: default={%}
        &v4: default={200000}
    --]]
]]*/

-- what includes what columns to display and aggregate and also options like latch name filtering
DEF _lhp_what="&V2"
DEF _lhp_sid="&V1"
DEF _lhp_name="&V3"
DEF _lhp_samples="&V4"

PROMPT
PROMPT -- LatchProfX 2.02 by Tanel Poder ( http://www.tanelpoder.com )

WITH t1 AS
 (SELECT KSUTMTIM hsecs FROM x$ksutm),
samples AS
 (SELECT * FROM TABLE(GV$(CURSOR(
      SELECT  /*+ ORDERED USE_NL(l.x$ksuprlat) USE_NL(s.x$ksuse) NO_TRANSFORM_DISTINCT_AGG */
              &_lhp_what, COUNT(DISTINCT gets) dist_samples, COUNT(*) total_samples, COUNT(*) / &_lhp_samples total_samples_pct
      FROM   (SELECT /*+ NO_MERGE */1
              FROM   x$ksutm
              CONNECT BY LEVEL <= &_lhp_samples) s1,
             (SELECT ksuprpid PID,
                     ksuprsid SID,
                     inst_id,
                     ksuprsid||'@'||inst_id sess#,
                     ksuprlnm NAME,
                     ksuprlat LADDR,
                     ksulawhr,
                     TO_CHAR(ksulawhy, 'XXXXXXXXXXXXXXXX') OBJECT,
                     ksulagts GETS,
                     lower(ksuprlmd) HMODE
              FROM   x$ksuprlat) l,
             (SELECT inst_id,indx, ksusesqh sqlhash, ksusesql sqladdr, ksusesph planhash, ksusesch sqlchild, ksusesqi sqlid FROM x$ksuse) s,
             (SELECT inst_id,indx, ksllwnam func, ksllwnam, ksllwlbl objtype, ksllwlbl FROM x$ksllw) w
      WHERE  l.sid like '&_lhp_sid'
      AND    l.ksulawhr = w.indx(+)
      AND    l.inst_id=w.inst_id(+)
      AND    l.sid = s.indx
      AND    l.inst_id=s.inst_id
      AND    (LOWER(l.name) LIKE LOWER('%&_lhp_name%') OR LOWER(RAWTOHEX(l.laddr)) LIKE LOWER('%&_lhp_name%'))
      GROUP  BY &_lhp_what
      )))
    ORDER  BY total_samples DESC),
t2 AS
 (SELECT KSUTMTIM hsecs FROM x$ksutm)
 
SELECT /*+ ORDERED */
     &_lhp_what,
     s.total_samples,
     s.dist_samples,
     s.total_samples / &_lhp_samples * 100 latchprof_pct_total_samples,
     (t2.hsecs - t1.hsecs) * 10 * s.total_samples / &_lhp_samples latchprof_total_ms,
     ROUND((t2.hsecs - t1.hsecs) * 10 * s.total_samples / dist_samples / &_lhp_samples,4) latchprof_avg_ms
FROM   t1, samples s, t2
WHERE  ROWNUM <= 50;