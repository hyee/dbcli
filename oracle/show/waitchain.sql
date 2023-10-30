/*[[Show info in v$wait_chains
    --[[
        @check_version: 11.2={}
    ]]--
]]*/

col in_wait format smhd2
WITH c AS(
    SELECT /*+materialize*/c.*, 
           c.SID||','||c.sess_serial#||',@'||c.instance sess#,
           nullif(c.blocker_SID||','||c.blocker_sess_serial#||',@'||c.blocker_instance,',,@') blocker# 
    FROM  v$wait_chains c),
r1(cid,sess#,lv,blocker#,root) AS (
    SELECT chain_id,sess#, 0 lv,blocker#,sess# root
    FROM   c
    WHERE  nvl(blocker#,sess#)=sess#
    UNION ALL
    SELECT c.chain_id,c.sess#, r1.lv + 1,c.blocker#,r1.root
    FROM   c, r1
    WHERE  c.blocker#=r1.sess#)
    SEARCH DEPTH FIRST BY cid SET cid_order
    CYCLE sess# SET cycle TO 1 DEFAULT 0,
r2(cid,sess#,lv,blocker#,root) AS (
    SELECT chain_id,sess#, 0 lv,blocker#,sess# root
    FROM   c
    WHERE  sess# not in(select sess# from r1)
    UNION ALL
    SELECT c.chain_id,c.sess#, r1.lv + 1,c.blocker#,r1.root
    FROM   c, r2 r1
    WHERE  c.blocker#=r1.sess#)
    SEARCH DEPTH FIRST BY cid SET cid_order
    CYCLE sess# SET cycle TO 1 DEFAULT 0
SELECT decode(cycle,1,'Y','N') cycle,
       rpad(' ',lv*3)|| nvl(wait_event_text,chain_signature) wait_event_text,
       sess# sid,
       c.blocker# blocked_by,
       s1.sql_id sql_id,
       osid spid,
       in_wait_secs in_wait,
       c.row_wait_obj# row_wait#,
       c.p1,
       c.p1_text p1text,
       c.p2,
       c.p2_text p2text,
       c.p3,
       c.p3_text p3text
FROM   (select r.*,max(lv) over(partition by root) max_lv from (select * from r1 union all select * from r2) r) r
JOIN   c USING(sess#)
LEFT   JOIN gv$session s1
ON     s1.inst_id = c.instance
AND    s1.sid = c.sid
AND    s1.serial# = c.sess_serial#
LEFT  JOIN gv$session s2
ON     s2.inst_id = c.blocker_instance
AND    s2.sid = c.blocker_sid
AND    s2.serial# = c.blocker_sess_serial#
WHERE  (max_lv between 1 and 30 or not exists(select * from v$event_name where wait_class='Idle' and name=wait_event_text) and wait_event_text!='<not in a wait>')
ORDER  BY cid_order

