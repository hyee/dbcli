/*[[
	Profile the input SQL commands with btl-report. Usage: @@NAME <directory_name> <SQL Commands>
	If dbms_java does not exist, then execute @?/javavm/install/initjvm.sql with SYSDBA
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
   file VARCHAR2(300);
   msg VARCHAR2(3000);
   sep VARCHAR2(1);
BEGIN
   select max(directory_path) into dir 
   from   all_directories b
   where  upper(directory_name)=upper(:V1);
   IF dir IS NULL THEN
       raise_application_error(-20001,'No such directory or no access right: '||:V1);
   END IF;
   sep   := regexp_substr(dir,'[\\/]');
   dir   := regexp_replace(dir,'[\\/]$')||sep;
   file  := dir||'btl_'||to_char(sysdate,'YYYYMMDDHH24MISS');
   n     := sys.dbms_java.init_btl(file, 1, 0, 0); 
   :file := file;
   sys.dbms_java.start_btl();
EXCEPTION WHEN OTHERS THEN
   IF SQLCODE=-29532 THEN
       msg:='You don''t have access to the directory, please grant below access rights:'||chr(10);
       msg:=msg||' grant JAVASYSPRIV to '||sys_context('userenv','current_schema')||';';
       msg:=msg||' exec dbms_java.grant_permission('''||sys_context('userenv','current_schema')||''', ''SYS:java.io.FilePermission'','''||dir||file||''', ''write'');'||chr(10);
       msg:=msg||' exec dbms_java.grant_permission('''||sys_context('userenv','current_schema')||''', ''SYS:oracle.aurora.security.JServerPermission'',''DUMMY'', '''');';
       raise_application_error(-20001,msg);
   ELSE
       RAISE;
   END IF;
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
