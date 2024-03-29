/*[[Show object privileges. Usage: @@NAME <object_name>
    --[[
        @ARGS: 1
        @CHECK_ACCESS_TAB: dba_tab_privs={dba} default={all}
        @CHECK_ACCESS_OWN: dba_tab_privs={OWNER} default={TABLE_SCHEMA}
        @CHECK_ACCESS_R1 : DBA_ROLE_PRIVS={DBA_ROLE_PRIVS} DEFAULT={role_role_privs}
        @CHECK_ACCESS_R2 : DBA_SYS_PRIVS={DBA_SYS_PRIVS} DEFAULT={role_sys_privs}
        @CHECK_ACCESS_R3 : {
            DBA_SCHEMA_PRIVS={DBA_SCHEMA_PRIVS} 
            default={(SELECT CAST('' AS VARCHAR2(128)) GRANTEE,
                             CAST('' AS VARCHAR2(40)) PRIVILEGE,
                             CAST('' AS VARCHAR2(128)) SCHEMA,
                             CAST('' AS VARCHAR2(3)) ADMIN_OPTION,
                             CAST('' AS VARCHAR2(3)) COMMON,
                             CAST('' AS VARCHAR2(3)) INHERITED
                      FROM DUAL WHERE 1=2)}
        }
    --]]
]]*/
ora _find_object "&V1" 1
set feed off

PRO TABLE_PRIVILEGES:
PRO =================
select * from TABLE_PRIVILEGES
where (OWNER=:OBJECT_OWNER and TABLE_NAME=:OBJECT_NAME) 
OR upper(:V1) IN(GRANTEE,TABLE_NAME)
ORDER BY GRANTEE,TABLE_NAME;

PRO DBA_TAB_PRIVS:
PRO ===============
select * from &CHECK_ACCESS_TAB._tab_privs
where (&CHECK_ACCESS_OWN=:OBJECT_OWNER and TABLE_NAME=:OBJECT_NAME) 
OR upper(:V1) IN(GRANTEE,TABLE_NAME)
ORDER BY GRANTEE,TABLE_NAME;

PRO DBA_COL_PRIVS:
PRO ===============
select * from &CHECK_ACCESS_TAB._col_privs
where (&CHECK_ACCESS_OWN=:OBJECT_OWNER and TABLE_NAME=:OBJECT_NAME) 
OR upper(:V1) IN(GRANTEE,TABLE_NAME,COLUMN_NAME)
ORDER BY GRANTEE,TABLE_NAME,COLUMN_NAME;

PRO COLUMN_PRIVILEGES:
PRO ===============
select * from COLUMN_PRIVILEGES
where (OWNER=:OBJECT_OWNER and TABLE_NAME=:OBJECT_NAME) 
OR upper(:V1) IN(GRANTEE,TABLE_NAME,COLUMN_NAME)
ORDER BY GRANTEE,TABLE_NAME,COLUMN_NAME;

PRO DBA_ROLE_PRIVS:
PRO ===============
select * from &CHECK_ACCESS_R1 WHERE upper(:V1) in(GRANTED_ROLE,GRANTEE)
ORDER BY 1,2;

PRO DBA_SYS_PRIVS:
PRO ===============
select * from &CHECK_ACCESS_R2 WHERE upper(:V1) in(GRANTEE,PRIVILEGE)
ORDER BY 1,2;

PRO DBA_SCHEMA_PRIVS:
PRO =================
select * from &CHECK_ACCESS_R3 WHERE upper(:V1) in(GRANTEE,PRIVILEGE)
ORDER BY 1,2;