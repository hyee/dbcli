/*[[
find objects with object_id/object_name. Usage: @@NAME {object_id | [owner.]<object_name>[.subname]}

Sample Output:
==============
ORCL> ora obj obj$
    Top 50 matched objects:
    =======================
    OBJECT_ID DATA_OBJECT_ID OWNER OBJECT_NAME OBJECT_TYPE SUBOBJECT_NAME       CREATED          LAST_DDL_TIME         TIMESTAMP      STATUS TEMPORARY GENERATED SECONDARY
    --------- -------------- ----- ----------- ----------- -------------- ------------------- ------------------- ------------------- ------ --------- --------- ---------
       727556         727556 SYS   OBJ$        TABLE                      2017-08-02 05:34:20 2018-10-12 07:06:09 2017-08-02:05:34:20 VALID  N         N         N
ORCL> ora obj 727555
    Top 50 matched objects:
    =======================
    OBJECT_ID DATA_OBJECT_ID OWNER     OBJECT_NAME     OBJECT_TYPE SUBOBJECT_NAME       CREATED          LAST_DDL_TIME         TIMESTAMP      STATUS TEMPORARY GENERATED 
    --------- -------------- ----- ------------------- ----------- -------------- ------------------- ------------------- ------------------- ------ --------- --------- 
       727555                SYS   _ACTUAL_EDITION_OBJ VIEW                       2017-08-02 05:34:19 2017-08-02 05:36:06 2017-08-02:05:36:06 VALID  N         N         

    --[[
        @check_access_obj: dba_objects={dba_objects}, default={all_objects}
        @check_access_pdb: pdb/awr_pdb_seg_stat_obj={awr_pdb_seg_stat_obj} default={dba_hist_seg_stat_obj}
        @check_access_awr: {
          dba_hist_seg_stat_obj={
            UNION ALL
            SELECT obj#,dataobj#,NULL,owner,object_name,object_type,subobject_name,null,null,null,null,2
            FROM   &check_access_pdb
            WHERE  dbid=:dbid
            AND    regexp_substr(:V1,'^\d+$')+0 in(obj#,dataobj#)
          }
          default={}
        }
        @check_access_bin: dba_recyclebin={dba_recyclebin} user_recyclebin={user_recyclebin} default={0}
        @ARGS: 1
    --]]
]]*/
SET FEED OFF
ora _find_object &V1 1
VAR cur REFCURSOR Top 50 matched objects;
DECLARE
    rec SYS_REFCURSOR;
    own VARCHAR2(128):=:object_owner;
    nam VARCHAR2(128):=:object_name;
    fil VARCHAR2(128):='%'||TRIM('%' FROM UPPER(:V1))||'%';
BEGIN
    IF own IS NOT NULL THEN
        OPEN rec FOR
            SELECT * FROM (
                SELECT /*+no_expand*/ 
                       object_id OBJ#,DATA_OBJECT_ID DATA_OBJ#,NAMESPACE NS#,owner, object_name obj_name,object_type obj_type,
                       case when :object_type IN('PACKAGE','TYPE') then :object_subname else subobject_name end subobj_name,
                       TRIM(',' FROM 
                            CASE WHEN STATUS!='VALID' THEN STATUS||',' END ||
                            CASE WHEN TEMPORARY='Y' THEN 'TEMPORARY,' END ||
                            CASE WHEN GENERATED='Y' THEN 'GENERATED,' END ||
                            CASE WHEN SECONDARY='Y' THEN 'SECONDARY,' END ||
                        $IF DBMS_DB_VERSION.VERSION>10 $THEN
                             CASE WHEN EDITION_NAME IS NOT NULL THEN 'EDITION='||EDITION_NAME||',' END||
                        $END
                        $IF DBMS_DB_VERSION.VERSION>11 $THEN
                            CASE WHEN SHARING!='NONE' THEN SHARING||',' END ||
                        $END
                        $IF DBMS_DB_VERSION.VERSION>12 OR (DBMS_DB_VERSION.VERSION>11 AND DBMS_DB_VERSION.RELEASE>1) $THEN
                            CASE WHEN APPLICATION='Y' THEN 'APP-COMMON,' END ||
                            CASE WHEN nullif(DEFAULT_COLLATION,'USING_NLS_COMP') IS NOT NULL THEN 'COLLATION='||DEFAULT_COLLATION||',' END ||
                            CASE WHEN SHARDED='Y' THEN 'SHARD'||
                                CASE
                                    $IF DBMS_DB_VERSION.VERSION>22 $THEN 
                                    WHEN SYNCHRONOUS_DUPLICATED='Y' THEN '-SYNC-DUPL,'
                                    $END
                                    WHEN DUPLICATED='Y' THEN '-DUPL,'
                                ELSE
                                    'ED,'
                                END
                            END ||
                        $END
                        $IF DBMS_DB_VERSION.VERSION>22 $THEN
                            CASE WHEN IMPORTED_OBJECT='Y' THEN 'IMPORTED,' END ||
                        $END
                            ''
                        ) ATTRS,
                       CREATED,LAST_DDL_TIME,TIMESTAMP,1 pos
                FROM   &check_access_obj 
                WHERE  owner=own
                AND    object_name=nam
                AND    (:object_type IN('PACKAGE','TYPE')  OR nvl(subobject_name,' ') like :object_subname||'%') &check_access_awr
                ORDER  BY pos,OBJ#)
            WHERE ROWNUM<=50;
    ELSE
        dbms_output.put_line('No results from dba_objects, searching from recyclebin...');
        OPEN rec FOR
        SELECT * FROM(
            SELECT * 
            FROM   &check_access_bin 
            WHERE  upper(object_name||'/'||owner||'.'||ORIGINAL_NAME||'.'||PARTITION_NAME||'/'||BASE_OBJECT) LIKE fil
            ORDER  BY OWNER,ORIGINAL_NAME,PARTITION_NAME)
        WHERE ROWNUM<=50;
    END IF;
    :cur :=rec;
END;
/
