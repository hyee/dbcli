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
set feed off verify off
var file varchar2(300);
var cmds varchar2(4000);
DECLARE
    n    NUMBER;
    dir  VARCHAR2(300);
    file VARCHAR2(300);
    msg  VARCHAR2(3000);
    sep  VARCHAR2(1);
    cmds VARCHAR2(32767):=:V2;
    c    varchar2(5);
BEGIN
    SELECT COUNT(1)
    INTO   n
    FROM   v$option
    WHERE  parameter = 'Java'
    AND    VALUE = 'TRUE';
    IF n = 0 THEN
        raise_application_error(-20001, 'Current DB release is not support JavaVM.');
    END IF;

    SELECT COUNT(1)
    INTO   n
    FROM   dba_registry t
    WHERE  comp_id = 'JAVAVM'
    AND    status = 'VALID';
    IF n = 0 THEN
        raise_application_error(-20001, 'JavaVM is not installed, please install @?/javavm/install/initjvm.sql with SYSDBA');
    END IF;

    SELECT COUNT(1)
    INTO   n
    FROM   dba_objects t
    WHERE  object_name = 'oracle/aurora/perf/OracleBTL'
    AND    owner = 'SYS'
    AND    object_type = 'JAVA CLASS'
    AND    status = 'VALID';
    IF n = 0 THEN
        raise_application_error(-20001, 'Cannot find object oracle/aurora/perf/OracleBTL, or its status is invalid.');
    END IF;

    SELECT MAX(directory_path) INTO dir 
    FROM   all_directories b 
    WHERE  upper(directory_name) = upper(:V1);
    IF dir IS NULL THEN
        raise_application_error(-20001, 'No such directory or no access right: ' || :V1);
    END IF;

    msg := 'You don''t have access to the directory, please grant one of below access rights:' || chr(10);
    msg := msg || '    grant JAVASYSPRIV to ' || user || ';'|| chr(10);
    msg := msg || '    exec dbms_java.grant_permission(USER, ''SYS:java.io.FilePermission'',''' || dir ||  '-'', ''write'');' || chr(10);
    msg := msg || 'And possible: exec dbms_java.grant_permission(USER, ''SYS:oracle.aurora.security.JServerPermission'',''DUMMY'', '''');';
    SELECT SUM(c) into n
    FROM  (
        SELECT count(1) c
        FROM   dba_role_privs 
        WHERE  granted_role='JAVASYSPRIV'
        AND    grantee=user
        UNION ALL
        SELECT count(1) c
        FROM   dba_java_policy 
        WHERE  type_name='TYPE_NAME'
        AND    grantee=user
        AND    type_name='java.io.FilePermission'
        AND    name=dir||'-'
        AND    enabled='ENABLED'
        AND    instr(action,'write')>0);
    
    IF n = 0 AND sys_context('USERENV','ISDBA')='FALSE' THEN
        raise_application_error(-20001, msg);
    END IF;

    sep   := regexp_substr(dir, '[\\/]');
    dir   := regexp_replace(dir, '[\\/]$') || sep;
    file  := dir || 'btl_' || to_char(SYSDATE, 'YYYYMMDDHH24MISS');
    n     := sys.dbms_java.init_btl(file, 1, 0, 0);
    :file := file;
    sys.dbms_java.start_btl();

    cmds:=trim(cmds);
    c:=substr(cmds,-1);
    if c!=';' and c!='/' or upper(substr(cmds,-128)) like 'END;' then
        cmds := cmds ||';';
    end if;
    
    if upper(substr(cmds,-128)) like 'END;' then
        cmds := cmds || chr(10) || '/';
    end if;
    :cmds := cmds;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20001 THEN
            raise;
        END IF;
        dbms_output.put_line(trim(replace(regexp_replace(sqlerrm,'.*?Exception:'),'. ','.'||chr(10))));
        IF SQLCODE = -29538 THEN
            raise_application_error(-20001, 'JavaVM isn''t installed in CURRENT instance, run @?/javavm/install/initjvm.sql with SYSDBA');
        ELSIF SQLCODE = -29532 THEN
            raise_application_error(-20001, msg);
        ELSE
            RAISE;
        END IF;
END;
/

set internal on
SET ONERREXIT OFF
&cmds;

SET ONERREXIT ON;
SET ONERREXIT ON
set internal off

BEGIN
   sys.dbms_java.stop_btl();
   sys.dbms_java.terminate_btl();
   dbms_output.put_line('Please run below command to generate the profile result:');
   dbms_output.put_line('  ./btl-report &file..btl &file..bts > &file..log');
   dbms_output.put_line('And then run "odb profile <path>/&file..log" to analyze the report.');
END;
/
