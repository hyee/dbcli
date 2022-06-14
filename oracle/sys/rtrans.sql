/*[[
    Show global(remote) transactions from db links.
    Author   : xtender@github
    Reference: https://github.com/xtender/xt_scripts/blob/master/transactions

    --[[
        @ver: 11.2={} default={--}
    --]]
]]*/
set feed off
PRO Sessions through db links:
PRO ==========================
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT s.sid||','||s.serial#||',@'||g.inst_id sid,s.username,
           nvl2(REPLACE(K2GTIBID, '0'), 'FROM REMOTE', 'TO REMOTE') AS direction,
           regexp_replace(g.k2gtitid_ora,'^(.*)\.(\w+)\.(\d+\.\d+\.\d+)$','\3') as remote_trans,
           regexp_replace(g.k2gtitid_ora, '^(.*)\.(\w+)\.(\d+\.\d+\.\d+)$', '\1') AS remote_db,
           to_number(hextoraw(REVERSE(regexp_replace(k2gtitid_ora,'^(.*)\.(\w+)\.(\d+\.\d+\.\d+)$','\2'))),'XXXXXXXXXXXX') AS remote_dbid,
           DECODE(g.K2GTDFLG,
                   0,'ACTIVE',
                   1,'COLLECTING',
                   2,'FINALIZED',
                   4,'FAILED',
                   8,'RECOVERING',
                   16,'UNASSOCIATED',
                   32,'FORGOTTEN',
                   64,'READY FOR RECOVERY',
                   128,'NO-READONLY FAILED',
                   256,'SIBLING INFO WRITTEN',
                   512,'[ORACLE COORDINATED]ACTIVE',
                   512 + 1,'[ORACLE COORDINATED]COLLECTING',
                   512 + 2,'[ORACLE COORDINATED]FINALIZED',
                   512 + 4,'[ORACLE COORDINATED]FAILED',
                   512 + 8,'[ORACLE COORDINATED]RECOVERING',
                   512 + 16,'[ORACLE COORDINATED]UNASSOCIATED',
                   512 + 32,'[ORACLE COORDINATED]FORGOTTEN',
                   512 + 64,'[ORACLE COORDINATED]READY FOR RECOVERY',
                   512 + 128,'[ORACLE COORDINATED]NO-READONLY FAILED',
                   1024,'[MULTINODE]ACTIVE',
                   1024 + 1,'[MULTINODE]COLLECTING',
                   1024 + 2,'[MULTINODE]FINALIZED',
                   1024 + 4,'[MULTINODE]FAILED',
                   1024 + 8,'[MULTINODE]RECOVERING',
                   1024 + 16,'[MULTINODE]UNASSOCIATED',
                   1024 + 32,'[MULTINODE]FORGOTTEN',
                   1024 + 64,'[MULTINODE]READY FOR RECOVERY',
                   1024 + 128,'[MULTINODE]NO-READONLY FAILED',
                   1024 + 256,'[MULTINODE]SIBLING INFO WRITTEN',
                   'COMBINATION') STATE,s.status sesstatus,
           DECODE(g.K2GTETYP, 0,'FREE', 1,'LOOSELY COUPLED', 2,'TIGHTLY COUPLED') COUPLING,
           s.sql_id,s.event,s.logon_time,
           g.K2GTIFMT FORMATID, g.K2GTECNT BRANCHES,g.K2GTERCT REFCOUNT, g.K2GTDPCT PREPARECOUNT, g.K2GTDFLG FLAGS
           -- additional columns:
           &ver, g.k2gtitid_ora AS globalid_ora, g.K2GTITID_EXT GLOBALID, g.K2GTIBID BRANCHID
    FROM   SYS.X$K2GTE2 g, v$session s
    WHERE  s.saddr=g.k2gtdses)));

/* --Also available with below SQL
SELECT --+ORDERED 
     substr(s.ksusemnm, 1, 10) || '-' || substr(s.ksusepid, 1, 10) "ORIGIN",
     substr(g.K2GTITID_ORA, 1, 35) "GTXID",
     s2.sid||','||s2.serial#||',@'||s2.inst_id sid , s2.username,
     substr(decode(bitand(ksuseidl, 11),
                    1,'ACTIVE',
                    0,DECODE(bitand(ksuseflg, 4096), 0, 'INACTIVE', 'CACHED'),
                    2,'SNIPED',
                    3,'SNIPED',
                    'KILLED'),
             1,
             1) "STATUS", s2.event "WAITING"
FROM   sys.x$k2gte g, sys.x$ktcxb t, sys.x$ksuse s, gv$session s2
WHERE  g.K2GTDXCB = t.ktcxbxba
AND    g.K2GTDSES = t.ktcxbses
AND    s.addr = g.K2GTDSES
AND    t.inst_id = g.inst_id
AND    s.inst_id=g.inst_id
AND    s2.inst_id=s.inst_id
AND    s2.sid = s.indx;
*/

PRO Info of dba_2pc_pending:
PRO ========================
select
     LOCAL_TRAN_ID
    ,STATE
    ,MIXED
    ,ADVICE
    ,TRAN_COMMENT
    ,FAIL_TIME
    ,FORCE_TIME
    ,RETRY_TIME
    ,OS_USER
    ,OS_TERMINAL
    ,HOST
    ,DB_USER
    ,COMMIT#
    ,GLOBAL_TRAN_ID
from dba_2pc_pending;