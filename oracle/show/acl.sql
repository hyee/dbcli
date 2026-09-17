/*[[Show Network Access Control configurations
--[[
    @check_version: 12.1={}
    @check_access_cdb : cdb_host_acls={CDB_} dba_host_acls={DBA_} default={USER_}
    @check_access_con : cdb_host_acls={con_id,ACL_OWNER,} default={ACL_OWNER,} default={}
    @check_access_con1: cdb_host_acls={con_id,} default={}
--]]
]]*/
set autohide col feed off colautosize body

PRO &check_access_cdb.WALLET_ACES
PRO =================
SELECT *
FROM   &check_access_cdb.WALLET_ACES
RIGHT  JOIN (SELECT '|' "|", a.* FROM &check_access_cdb.HOST_ACES a)
USING  (&check_access_con1 ace_order, principal, principal_type, inverted_principal, grant_type)
ORDER  BY 1, principal;

PRO &check_access_cdb.NETWORK_ACLS
PRO =================
SELECT *
FROM   &check_access_cdb.host_acls a
LEFT   JOIN &check_access_cdb.acl_name_map
USING  (&check_access_con acl)
LEFT   JOIN &check_access_cdb.NETWORK_ACL_PRIVILEGES
USING  (&check_access_con aclid, acl)
ORDER  BY 1, principal, privilege;

PRO &check_access_cdb.WALLET_ACLS
PRO =================
SELECT * FROM &check_access_cdb.WALLET_ACLS