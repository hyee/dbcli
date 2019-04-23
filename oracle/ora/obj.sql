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
        @ARGS: 1
    --]]
]]*/
SET FEED OFF
ora _find_object &V1
VAR cur REFCURSOR Top 50 matched objects;
BEGIN
    OPEN :cur FOR
        SELECT * FROM (
            SELECT /*+no_expand*/ 
                   object_id,DATA_OBJECT_ID,owner, object_name,object_type,
                   case when :object_type IN('PACKAGE','TYPE') then :object_subname else subobject_name end subobject_name,
                   CREATED,LAST_DDL_TIME,TIMESTAMP,STATUS,TEMPORARY,GENERATED,SECONDARY
            FROM   &check_access_obj 
            WHERE  owner=:object_owner
            AND    object_name=:object_name
            --AND    object_type like :object_type||'%'
            AND    (:object_type IN('PACKAGE','TYPE')  OR nvl(subobject_name,' ') like :object_subname||'%')
            ORDER  BY OBJECT_ID)
        WHERE ROWNUM<=50;
END;
/
