/*[[Fuzzily search objects with object_id/keyword. Usage: @@NAME [object_id|data_object_id|keyword] 
    --[[
        @check_access_obj: dba_objects={dba_objects}, default={all_objects}
        @check_access_pro: dba_Procedures={dba_Procedures}, default={all_Procedures}
        @check_access_fn : V$SQLFN_METADATA={}, default={--}
        @check_access_ft : v$fixed_table={}, default={--}
    --]]
]]*/
SELECT OWNER,
       OBJECT_NAME,
       SUBOBJECT_NAME,
       OBJECT_ID,
       DATA_OBJECT_ID DATA_OBJECT,
       OBJECT_TYPE,
       CREATED,
       LAST_DDL_TIME  LAST_DDL,
       STATUS,
       TEMPORARY
FROM   &check_access_obj
WHERE  UPPER(OWNER || '.' || OBJECT_NAME || chr(1) || OBJECT_ID || chr(1) ||
             SUBOBJECT_NAME || chr(1) || DATA_OBJECT_ID || chr(1) ||object_type|| chr(1)||
             TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') || chr(1) ||
             TO_CHAR(LAST_DDL_TIME, 'YYYY-MM-DD HH24:MI:SS') || chr(1) || STATUS) LIKE '%' || NVL(UPPER(:V1), 'xxxx') || '%' escape '\'
UNION ALL
SELECT a.owner,
       a.object_name,
       a.procedure_name subobject_name,
       b.object_id,
       a.subprogram_id,
       b.object_type||'.PROCEDURE',
       b.created,
       b.last_ddl_time,
       b.STATUS,
       b.TEMPORARY
FROM   &check_access_pro a, &check_access_obj b
WHERE  a.owner = b.owner
and    a.object_name=b.object_name
AND    procedure_name IS NOT NULL
AND    upper(a.owner||'.'||a.procedure_name || CHR(1) || a.subprogram_id|| chr(1) ||'PROCEDURE/FUNCTION'|| chr(1)) LIKE '%' || NVL(UPPER(:V1), 'xxxx') || '%' escape '\'
&check_access_fn UNION ALL
&check_access_fn SELECT 'PUBLIC',
&check_access_fn        name,
&check_access_fn        nullif('('||(SELECT listagg(datatype, ',') within GROUP(ORDER BY argnum) FROM V$SQLFN_ARG_METADATA WHERE func_id = a.func_id)||')','()') args,
&check_access_fn        null,null,'FUNCTION => '||DATATYPE,null,null,VERSION,null
&check_access_fn FROM   V$SQLFN_METADATA a
&check_access_fn WHERE  name||' '||VERSION like '%'||NVL(UPPER(:V1), 'xxxx')||'%' escape '\'
&check_access_ft UNION ALL
&check_access_ft SELECT 'SYSDBA',NAME,NULL,object_id,null,'FIXED TABLE',null,null,null,null
&check_access_ft FROM   v$fixed_table WHERE TYPE='TABLE' AND NAME LIKE '%'||NVL(UPPER(:V1), 'xxxx')||'%'
ORDER  BY 1, 2