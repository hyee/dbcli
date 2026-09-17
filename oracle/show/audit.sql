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
SELECT audit_trail, parameter_name,parameter_value FROM dba_audit_mgmt_config_params ORDER BY 1,2;

pro
pro Size of Audit log tables
PRO ========================
SELECT owner,segment_name,
       decode(segment_name,'AUD$','DBA_AUDIT_TRAIL','FGA_LOG$','DBA_FGA_AUDIT_TRAIL','AUDIT_TRAIL$','','AUD$UNIFIED','UNIFIED_AUDIT_TRAIL') view_name,
       segment_subtype,tablespace_name,count(1) segments,sum(bytes) bytes,sum(blocks) blocks,sum(extents) extents,max(next_extent) next_extent
FROM   dba_segments
WHERE  segment_name IN('AUD$','FGA_LOG$','AUDIT_TRAIL$','AUD$UNIFIED') AND owner IN ('SYS','DVSYS','AUDSYS')
GROUP  BY owner,segment_name,segment_subtype,tablespace_name
ORDER  BY 1,2,3,4;

pro Audit config for stmt/priv
pro ==========================
SELECT a.* FROM dba_stmt_audit_opts a
UNION
SELECT a.* FROM dba_priv_audit_opts a
ORDER  BY 1,3;

&12c pro Unified Audit config
&12c pro ====================
&12c SELECT * FROM v$option WHERE parameter = 'Unified Auditing';
&12c pro Unified Audit Policies
&12c pro ======================
&12c SELECT * FROM audit_unified_enabled_policies JOIN audit_unified_policies USING(policy_name);

pro Audit config for objects
pro ========================
SELECT * FROM dba_obj_audit_opts ORDER BY 1,2;

pro Fine Grained Auditing(FGA) config
pro =================================
SELECT * FROM dba_audit_policies ORDER BY 1,2;