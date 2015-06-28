/*[[Library cache lock holders/waiters.
Refer to: https://github.com/xtender/xt_scripts
]]*/
SELECT DISTINCT to_char(ses.ksusenum) sid, ses.ksuseser serial, ses.ksuudlna username,
                KSUSEMNM module, ob.kglnaown obj_owner, ob.kglnaobj obj_name, lk.kgllkcnt lck_cnt,
                lk.kgllkmod lock_mode, lk.kgllkreq lock_req, w.state, w.event, w.wait_Time wtime,
                w.seconds_in_Wait secs
FROM   x$kgllk lk, x$kglob ob, x$ksuse ses, v$session_wait w
WHERE  lk.kgllkhdl IN (SELECT /*+ precompute_subquery */kgllkhdl
                       FROM   x$kgllk
                       WHERE  kgllkreq > 0)
AND    ob.kglhdadr = lk.kgllkhdl
AND    lk.kgllkuse = ses.addr
AND    w.sid = ses.indx
ORDER  BY seconds_in_wait DESC
