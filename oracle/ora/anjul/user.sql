/* [[Provides information about the user. Usage: user <username>]] */

set feed off
SELECT user_id, username, account_status, profile,
       INITIAL_RSRC_CONSUMER_GROUP RESOURCE_GROUP,
       created, expiry_date, lock_date, lcount lock_count, default_tablespace, temporary_tablespace
FROM   dba_users, sys.user$
WHERE  user_id = user#
AND    username LIKE NVL2(:V1,upper('%&V1%'),SYS_CONTEXT('USERENV','CURRENT_SCHEMA'));

SELECT username, tablespace_name, decode(max_bytes, -1, 'UNLIMITED', ceil(max_bytes / 1024 / 1024) || 'M') "QUOTA"
FROM   dba_ts_quotas 
WHERE  username LIKE NVL2(:V1,upper('%&V1%'),SYS_CONTEXT('USERENV','CURRENT_SCHEMA'))
ORDER  BY 1,2;

SELECT grantee username, granted_role || ' ' || decode(admin_option, 'NO', '', 'YES', 'WITH ADMIN OPTION') "User Roles"
FROM   dba_role_privs join dba_users on(username=grantee) 
WHERE  grantee LIKE NVL2(:V1,upper('%&V1%'),SYS_CONTEXT('USERENV','CURRENT_SCHEMA'))
ORDER  BY 1,2;

SELECT grantee username, privilege || ' ' || decode(admin_option, 'NO', '', 'YES', 'WITH ADMIN OPTION') "User Privileges"
FROM   dba_sys_privs join dba_users on(username=grantee) 
WHERE  grantee LIKE NVL2(:V1,upper('%&V1%'),SYS_CONTEXT('USERENV','CURRENT_SCHEMA'))
ORDER  BY 1,2;

SELECT /*+no_merge(a)*/ CONNECT_BY_ROOT(granted_role) username, lpad(' ', 2 * LEVEL) || granted_role "User, its roles and privileges"
FROM   (
         /* THE USERS */
         SELECT NULL grantee, username granted_role
         FROM   dba_users
         WHERE  username LIKE NVL2(:V1,upper('%&V1%'),SYS_CONTEXT('USERENV','CURRENT_SCHEMA'))
         /* THE ROLES TO ROLES RELATIONS */
         UNION
         SELECT grantee, granted_role
         FROM   dba_role_privs
         /* THE ROLES TO PRIVILEGE RELATIONS */
         UNION
         SELECT grantee, privilege
         FROM   dba_sys_privs) a
START  WITH grantee IS NULL
CONNECT BY grantee = PRIOR granted_role;

