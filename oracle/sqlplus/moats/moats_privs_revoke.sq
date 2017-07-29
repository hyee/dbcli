
set define on
set pause on

define moats_priv_target = &moats_priv_target;

prompt
prompt
prompt **************************************************************************
prompt **************************************************************************
prompt
prompt    MOATS Uninstaller: Revoke Privileges
prompt    ====================================
prompt
prompt    This will revoke MOATS privileges from &moats_priv_target..
prompt
prompt    To continue press Enter. To quit press Ctrl-C.
prompt
prompt    (c) www.oracle-developer.net, www.e2sn.com
prompt
prompt **************************************************************************
prompt **************************************************************************
prompt
prompt

pause

revoke create view from &moats_priv_target;
revoke create type from &moats_priv_target;
revoke create table from &moats_priv_target;
revoke create procedure from &moats_priv_target;
revoke execute on dbms_lock from &moats_priv_target;
revoke select on v_$session from &moats_priv_target;
revoke select on v_$statname from &moats_priv_target;
revoke select on v_$sysstat from &moats_priv_target;
revoke select on v_$latch from &moats_priv_target;
revoke select on v_$timer from &moats_priv_target;
revoke select on v_$sql from &moats_priv_target;

undefine moats_priv_target;

set pause off
