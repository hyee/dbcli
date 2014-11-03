/*[[Find locked objects in gv$locked_object]]*/
SELECT b.owner, b.object_name, c.inst_id,c.sid,c.LOGON_TIME, c.PROGRAM,c.MODULE,c.osuser,c.machine,c.SQL_ID,c.event
FROM   gv$locked_object a, All_Objects b,gv$session c
WHERE  a.object_id = b.object_id
AND    a.inst_id=c.inst_id
AND    a.session_id=c.sid