/*[[Show PL/SQL compile environment.]]*/
set feed off
BEGIN
    dbms_output.put_line('$$PLSCOPE_SETTINGS       = '|| $$PLSCOPE_SETTINGS);
    dbms_output.put_line('$$PLSQL_CCFLAGS          = '|| $$PLSQL_CCFLAGS);
    dbms_output.put_line('$$PLSQL_CODE_TYPE        = '|| $$PLSQL_CODE_TYPE);
    dbms_output.put_line('$$PLSQL_OPTIMIZE_LEVEL   = '|| $$PLSQL_OPTIMIZE_LEVEL);
    --DBMS_OUTPUT.PUT_LINE('$$PLSQL_DEBUG = '          || $$PLSQL_DEBUG);
    dbms_output.put_line('$$PLSQL_WARNINGS         = '|| $$PLSQL_WARNINGS);
    dbms_output.put_line('$$NLS_LENGTH_SEMANTICS   = '|| $$NLS_LENGTH_SEMANTICS);

    dbms_output.put_line('$$PLSQL_LINE             = '|| $$PLSQL_LINE);
    dbms_output.put_line('$$PLSQL_UNIT             = '|| $$PLSQL_UNIT);
    dbms_output.put_line('$$PLSQL_UNIT_OWNER       = '|| $$PLSQL_UNIT_OWNER);
    dbms_output.put_line('$$PLSQL_UNIT_TYPE        = '|| $$PLSQL_UNIT_TYPE);

    dbms_output.put_line('UID                      = '|| uid);
    dbms_output.put_line('USER                     = '|| user);
    dbms_output.put_line('CURRENT_USER             = '|| sys_context('USERENV','CURRENT_USER'));
    dbms_output.put_line('CURRENT_SCHEMA           = '|| sys_context('USERENV','CURRENT_SCHEMA'));
    --some values are impacted by parameter fixed_date
    dbms_output.put_line('SYSDATE                  = '|| sysdate);
    dbms_output.put_line('SYSTIMESTAMP             = '|| systimestamp);
    dbms_output.put_line('CURRENT_DATE             = '|| current_date);
    dbms_output.put_line('CURRENT_TIMESTAMP        = '|| current_timestamp);
    dbms_output.put_line('LOCALTIMESTAMP           = '|| localtimestamp);
    dbms_output.put_line('DBTIMEZONE               = '|| dbtimezone);
    dbms_output.put_line('SESSIONTIMEZONE          = '|| sessiontimezone);
    dbms_output.put_line('DBMS_UTILITY.GET_TIME    = '|| dbms_utility.get_time||' (v$timer)');
    dbms_output.put_line('DBMS_UTILITY.GET_CPU_TIME= '|| dbms_utility.get_cpu_time);
END;
/