/*[[find objects with object_id/object_name. Usage: obj [object_id|[owner.]<package_name|object_name>[.subname]]
    --[[
        @check_access_obj: dba_objects={dba_objects}, all_objects={dba_objects}
    --]]
]]*/
SET FEED OFF
ora _find_object &V1
VAR cur REFCURSOR;
BEGIN
    OPEN :cur FOR
        SELECT /*+no_expand*/ 
               object_id,DATA_OBJECT_ID,owner, object_name,object_type,
               :object_subname subobject_name,
               CREATED,LAST_DDL_TIME,TIMESTAMP,STATUS,TEMPORARY,GENERATED,SECONDARY
        FROM   &check_access_obj 
        WHERE  owner=:object_owner
        AND    object_name=:object_name
        AND    object_type like :object_type||'%'
        AND    (:object_type IN('PACKAGE','TYPE') OR object_id=:object_id);
END;
/
