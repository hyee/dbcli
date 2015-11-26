/* [[Provides information about the user. Usage: user <username>]] */


select
  user_id,
  username,
  account_status,
  profile,
  --authentication_type,
  created,
  expiry_date,
  lock_date,
  lcount lock_count,
  default_tablespace,
  temporary_tablespace
from dba_users, sys.user$
  where
  user_id=user#
  and username like upper('%&V1%');

  select tablespace_name
  ,      decode(max_bytes, -1, 'unlimited'
  ,      ceil(max_bytes / 1024 / 1024) || 'M' ) "QUOTA"
  from   dba_ts_quotas
  where  username like upper('%&V1%');


  select granted_role || ' ' || decode(admin_option, 'NO', '', 'YES', 'with admin option') "User Roles"
  from   dba_role_privs
  where  grantee like upper('%&V1%');



  select privilege || ' ' || decode(admin_option, 'NO', '', 'YES', 'with admin option') "User Privileges"
  from   dba_sys_privs
  where  grantee like upper('%&V1%');

  select
    lpad(' ', 2*level) || granted_role "User, its roles and privileges"
  from
    (
    /* THE USERS */
      select
        null     grantee,
        username granted_role
      from
        dba_users
      where
        username like upper('%&V1%')--Change the username accordingly
    /* THE ROLES TO ROLES RELATIONS */
    union
      select
        grantee,
        granted_role
      from
        dba_role_privs
    /* THE ROLES TO PRIVILEGE RELATIONS */
    union
      select
        grantee,
        privilege
      from
        dba_sys_privs
    )
  start with grantee is null
  connect by grantee = prior granted_role;
