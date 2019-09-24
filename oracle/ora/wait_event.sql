/*[[
	Run SQL statement with events 'wait_event[all]' enabled. Usage: @@NAME <Other SQL Commands>
	Example: @@NAME "exec dbms_lock.sleep(10)"
	--[[
		@ARGS: 1
		@VER:  12={}
	--]]
]]*/
set feed off
var file varchar2(300)
BEGIN
    execute immediate  'alter session set tracefile_identifier='''||to_char(sysdate,'yyyymmddhh24miss')||'''';
    execute immediate q'[alter session set events 'wait_event[all] trace(''\nevent="%", p1=%, p2=%, p3=%, ela=%, tstamp=% shortstack=%'', evargs(5), evargn(2), evargn(3),evargn(4), evargn(1), evargn(7),shortstack())']';
END;
/
SET ONERREXIT OFF
&V1
SET ONERREXIT ON
BEGIN
	execute immediate q'[alter session set events 'wait_event[all] off']';
	execute immediate q'[select value from v$diag_info where name='Default Trace File']' into :file;
    execute immediate   'alter session set tracefile_identifier=''''';
END;
/
oradebug profile "&file" server