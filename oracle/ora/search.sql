/*[[Fuzzily search objects with object_id/keyword. Usage: @@NAME [object_id|data_object_id|keyword] 

Sample Output:
==============
ORCL> ora search v%$%lock%view
    OWNER OBJECT_NAME                                                   SUBOBJECT_NAME OBJECT_ID DATA_OBJECT OBJECT_TYPE       CREATED            LAST_DDL       STATUS TEMPORARY
    ----- ------------------------------------------------------------- -------------- --------- ----------- ----------- ------------------- ------------------- ------ ---------
    SYS   GV_$BLOCKING_QUIESCE                                                              2723             VIEW        2014-07-07 05:40:14 2018-10-12 06:53:43 VALID  N
    SYS   GV_$CACHE_LOCK                                                                    3702             VIEW        2014-07-07 05:40:20 2018-10-12 06:53:47 VALID  N
    SYS   GV_$CR_BLOCK_SERVER                                                               2340             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:42 VALID  N
    SYS   GV_$CURRENT_BLOCK_SERVER                                                          2342             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:42 VALID  N
    SYS   GV_$DATABASE_BLOCK_CORRUPTION                                                     2584             VIEW        2014-07-07 05:40:13 2018-10-12 06:53:42 VALID  N
    SYS   GV_$DLM_ALL_LOCKS                                                                 2322             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:41 VALID  N
    SYS   GV_$DLM_LOCKS                                                                     2324             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:42 VALID  N
    SYS   GV_$ENQUEUE_LOCK                                                                  2280             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:41 VALID  N
    SYS   GV_$GES_BLOCKING_ENQUEUE                                                          2336             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:42 VALID  N
    SYS   GV_$GES_DEADLOCKS                                                                 3662             VIEW        2014-07-07 05:40:20 2018-10-12 06:53:47 VALID  N
    SYS   GV_$GES_DEADLOCK_SESSIONS                                                         3666             VIEW        2014-07-07 05:40:20 2018-10-12 06:53:47 VALID  N
    SYS   GV_$GLOBAL_BLOCKED_LOCKS                                                          2753             VIEW        2014-07-07 05:40:14 2018-10-12 06:53:43 VALID  N
    SYS   GV_$LIBCACHE_LOCKS                                                                2498             VIEW        2014-07-07 05:40:12 2018-10-12 06:53:42 VALID  N
    SYS   GV_$LOCK                                                                          2418             VIEW        2014-07-07 05:40:12 2018-10-12 07:00:59 VALID  N
    SYS   GV_$LOCKDOWN_RULES                                                              839979             VIEW        2018-10-12 06:53:49 2018-10-12 06:53:49 VALID  N
    SYS   GV_$LOCKED_OBJECT                                                                 2398             VIEW        2014-07-07 05:40:12 2018-10-12 06:53:42 VALID  N
    SYS   GV_$LOCKS_WITH_COLLISIONS                                                         2362             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:42 VALID  N
    SYS   GV_$LOCK_ACTIVITY                                                                 2701             VIEW        2014-07-07 05:40:14 2018-10-12 06:53:43 VALID  N
    SYS   GV_$LOCK_ELEMENT                                                                  2360             VIEW        2014-07-07 05:40:11 2018-10-12 06:53:42 VALID  N
    SYS   GV_$LOCK_TYPE                                                                     2839             VIEW        2014-07-07 05:40:15 2018-10-12 06:53:43 VALID  N
    SYS   GV_$NFS_LOCKS                                                                     3370             VIEW        2014-07-07 05:40:18 2018-10-12 06:53:46 VALID  N
    SYS   GV_$NONLOGGED_BLOCK                                                               3770             VIEW        2014-07-07 05:40:20 2018-10-12 06:53:47 VALID  N
    SYS   GV_$SESSION_BLOCKERS                                                              2640             VIEW        2014-07-07 05:40:13 2018-10-12 06:53:43 VALID  N
    SYS   GV_$_LOCK                                                                         2416             VIEW        2014-07-07 05:40:12 2018-10-12 06:53:42 VALID  N
    --[[
        @check_access_obj: dba_objects={dba_objects}, default={all_objects}
        @check_access_pro: dba_Procedures={dba_Procedures}, default={all_Procedures}
        @check_access_fn : V$SQLFN_METADATA={}, default={--}
        @check_access_ft : v$fixed_table={}, default={--}
        @ARGS: 1
    --]]
]]*/
COL R NOPRINT
SELECT * FROM (SELECT A.*,ROW_NUMBER() OVER(PARTITION BY OWNER,OBJECT_NAME,SUBOBJECT_NAME ORDER BY OBJECT_ID) R
FROM (
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
) A) WHERE R=1
ORDER  BY 1, 2