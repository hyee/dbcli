/*[[Show audit configurations
	--[[
		@12c: 12.1={} default={--}
	--]]
]]*/
SET FEED OFF
COL BYTES,INITIAL_EXTENT,NEXT_EXTENT FOR KMG
COL BLOCKS FOR TMB

PRO Audit Trail Properties
PRO ======================
SELECT AUDIT_TRAIL, PARAMETER_NAME,PARAMETER_VALUE FROM DBA_AUDIT_MGMT_CONFIG_PARAMS ORDER BY 1,2;

pro   
pro Size of Audit log tables
PRO ========================
SELECT OWNER,SEGMENT_NAME,SEGMENT_SUBTYPE,TABLESPACE_NAME,COUNT(1) SEGMENTS,SUM(BYTES) BYTES,SUM(BLOCKS) BLOCKS,SUM(EXTENTS) EXTENTS,MAX(NEXT_EXTENT) NEXT_EXTENT
FROM DBA_SEGMENTS 
WHERE SEGMENT_NAME IN('AUD$','FGA_LOG$','AUDIT_TRAIL$','AUD$UNIFIED') AND OWNER IN ('SYS','DVSYS','AUDSYS')
GROUP BY OWNER,SEGMENT_NAME,SEGMENT_SUBTYPE,TABLESPACE_NAME
ORDER BY 1,2,3,4;

pro Audit config for stmt/priv
pro ==========================
SELECT a.* FROM dba_stmt_audit_opts a
UNION
SELECT a.* FROM dba_priv_audit_opts a
ORDER BY 1,3;

&12c pro Unified Audit config
&12c pro ====================
&12c SELECT * FROM V$OPTION WHERE PARAMETER = 'Unified Auditing';
&12c SELECT * FROM AUDIT_UNIFIED_ENABLED_POLICIES JOIN AUDIT_UNIFIED_POLICIES USING(POLICY_NAME);

pro Audit config for object
pro =======================
SELECT * FROM DBA_OBJ_AUDIT_OPTS ORDER BY 1,2;

pro Fine Grained Auditing(FGA) config
pro =================================
SELECT * FROM dba_audit_policies ORDER BY 1,2;