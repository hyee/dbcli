/*[[
	Profile the input SQL commands with btl-report. Usage: @@NAME <directory_name> <SQL Commands>
	If dbms_java does not exist, then execute @?/javavm/install/initjvm.sql
    You may need to grant the JAVASYSPRIV access right to the user who will execute this script.
	
	Example:  @@NAME DATA_PUMP_DIR "exec dbms_lock.sleep(10)"
	--[[
		@ARGS：2
		@CHECK_ACCESS_JAVA: sys.dbms_java={}
	--]]
]]*/
set feed off
var file varchar2(300);
DECLARE
   n   NUMBER;
   dir VARCHAR2(300);
BEGIN
   select max(directory_path) into dir 
   from  table_privileges a,all_directories b
   where a.owner=b.owner
   and   a.table_name=b.directory_name
   and   upper(directory_name)=upper(:V1);
   IF dir IS NULL THEN
       raise_application_error(-20001,'No such directory or don''t have the access right: '||:V1);
   END IF;
   dir:= '/'||trim('/' from dir)||'/btl_'||to_char(sysdate,'YYYYMMDDHH24MISS');
   n  := sys.dbms_java.init_btl(dir, 1, 0, 0); 
   sys.dbms_java.start_btl();
   :file := dir;
END;
/
SET ONERREXIT OFF
&V2
SET ONERREXIT ON
BEGIN
   sys.dbms_java.stop_btl();
   sys.dbms_java.terminate_btl();
   dbms_output.put_line('Please run below command to generate the profile result:');
   dbms_output.put_line('  ./btl-report &file..btl &file..bts > &file..log');
END;
/
