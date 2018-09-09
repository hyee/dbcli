/*[[
Show all database instances
--[[
    @blocked: 11.2={blocked,},10.2={SHUTDOWN_PENDING,}
--]]
]]*/

--Show node-level sysdate by querying the logon time of px sessions from px queries
var cur refcursor;
set feed off verify on
declare
    cur sys_refcursor;
begin
$IF DBMS_DB_VERSION.VERSION>10 $THEN
	open cur for q'[
		SELECT decode(userenv('instance')+0,a.inst_id,'*',' ')||a.inst_id inst_id, instance_name,version,
		       host_name,user,
		       status,archiver,&blocked
		       to_char(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
		       b.current_time inst_current_time
		from gv$instance a,
		     TABLE(gv$(cursor(SELECT logon_time current_time,USERENV('instance') inst_id FROM v$session a JOIN v$mystat using(sid) WHERE ROWNUM<2))) b
		WHERE a.inst_id=b.inst_id(+)
		order by a.inst_id]';
$ELSE
	open cur for
		WITH PX AS (SELECT /*+materialize*/ * FROM gv$px_session WHERE sid IS NOT NULL),
		     SS AS (SELECT /*+materialize*/ inst_id,sid,logon_time from gv$session where status='ACTIVE' and username=user),
		     tim AS(SELECT /*+no_merge*/ inst_id,max(logon_time) tim
		            FROM   ss natural join PX
		            WHERE  qcsid = userenv('sid')
		            AND    qcinst_id = userenv('instance')
		            GROUP BY inst_id)
		SELECT decode(userenv('instance')+0,a.inst_id,'*',' ')||a.inst_id inst_id, instance_name,version,
		       host_name,user,
		       status,archiver,
		       to_char(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
		       to_char(nvl(b.tim,sysdate),'YYYY-MM-DD HH24:MI:SS') inst_current_time
		from gv$instance a,tim b
		WHERE a.inst_id=b.inst_id(+)
		order by a.inst_id;
$end
	:cur := cur;
end;
/