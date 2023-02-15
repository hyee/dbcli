/*[[Show Network Access Control configurations
--[[
    @check_access_cdb : cdb_host_acls={CDB_} dba_host_acls={DBA_} default={USER_}
    @check_access_con : cdb_host_acls={con_id,ACL_OWNER,} default={ACL_OWNER,} default={}
    @check_access_con1: cdb_host_acls={con_id,} default={}
--]]
]]*/
SET AUTOHIDE COL FEED OFF COLAUTOSIZE BODY

PRO &check_access_cdb.WALLET_ACES
PRO =================
SELECT * 
FROM &check_access_cdb.WALLET_ACES
RIGHT JOIN (select '|' "|", a.* from &check_access_cdb.HOST_ACES a)
USING (&check_access_con1 ACE_ORDER,PRINCIPAL,PRINCIPAL_TYPE,INVERTED_PRINCIPAL,GRANT_TYPE)
ORDER BY 1,PRINCIPAL;

PRO &check_access_cdb.NETWORK_ACLS
PRO =================
SELECT *
FROM   &check_access_cdb.host_acls a
LEFT   JOIN &check_access_cdb.acl_name_map
USING  (&check_access_con ACL)
LEFT   JOIN &check_access_cdb.NETWORK_ACL_PRIVILEGES
USING  (&check_access_con  ACLID, ACL)
ORDER BY 1,PRINCIPAL,PRIVILEGE;

PRO &check_access_cdb.WALLET_ACLS
PRO =================
SELECT * FROM &check_access_cdb.WALLET_ACLS