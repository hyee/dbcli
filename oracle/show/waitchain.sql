/*[[Show info in v$wait_chains
    --[[
        @check_version: 11.2={}
    ]]--
]]*/
WITH c AS(SELECT /*+materialize*/* FROM  v$wait_chains),
r(cid,INSTANCE,SID,sess_serial#,lv,blocker_instance,blocker_sid) AS
 (SELECT chain_id,INSTANCE, SID, sess_serial#, 0 lv,blocker_instance,blocker_sid
  FROM   c
  WHERE  blocker_SID IS NULL
  OR     (CHAIN_IS_CYCLE='TRUE' and chain_id=(select min(chain_id) from c where CHAIN_IS_CYCLE='TRUE'))
  UNION ALL
  SELECT c.chain_id,c.INSTANCE, c.SID, c.sess_serial#, r.lv + 1,c.blocker_instance,c.blocker_sid
  FROM   c, r
  WHERE  c.blocker_instance = r.INSTANCE
  AND    c.blocker_sid = r.sid
  AND    (not (c.sid=r.sid and c.instance=r.instance) or r.lv<2)
  AND    (not (r.blocker_instance=r.instance and r.blocker_sid = r.sid and r.lv>0))
  AND    c.blocker_sess_serial# = r.sess_serial#
  AND    r.lv < 10)
SEARCH DEPTH FIRST BY cid SET cid_order
SELECT rpad(' ',lv*3)|| nvl(wait_event_text,chain_signature) wait_event_text,
       c.INSTANCE inst,
       (SELECT s1.sql_id
        FROM   gv$session s1
        WHERE  s1.inst_id = c.instance
        AND    s1.sid = c.sid
        AND    s1.serial# = c.sess_serial#) sql_id,
       c.SID||','||c.sess_serial#||',@'||c.instance sid,
       nullif(c.blocker_SID||','||c.blocker_sess_serial#||',@'||c.blocker_instance,',,@') block_sid,
       (SELECT s2.sql_id
        FROM   gv$session s2
        WHERE  s2.inst_id = c.blocker_instance
        AND    s2.sid = c.blocker_sid
        AND    s2.serial# = c.blocker_sess_serial#) bl_sql_id,
       osid,
       pid,
       blocker_osid bl_osid,
       blocker_pid bl_pid,
       in_wait,
       p1,
       p1_text p1text,
       p2,
       p2_text p2text,
       p3,
       p3_text p3text,
       in_wait_secs,
       time_remaining_secs remaining,
       row_wait_obj#
FROM   r ,c
WHERE  c.instance = r.INSTANCE
  AND  c.sid = r.sid
  AND  c.sess_serial# = r.sess_serial#
  AND  (lv>0 or not exists(select * from v$event_name where wait_class='Idle' and name=wait_event_text))
ORDER  BY cid_order

