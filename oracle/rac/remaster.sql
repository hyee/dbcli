/*[[Show gc remastering of the target object. Usage: @@NAME <object_id>|[<owner>.]<object_name> ]]*/

findobj "&V1" "" 1

SELECT OWNER,OBJECT_NAME,SUBOBJECT_NAME,
       b.*,
       c.POLICY_EVENT,
       C.EVENT_DATE,
       C.TARGET_INSTANCE_NUMBER
FROM   ALL_OBJECTS a,v$gcspfmaster_info b,gv$policy_history c
WHERE  a.data_object_id=b.data_object_id(+)
AND    a.data_object_id=c.data_object_id(+)
AND    a.owner=:object_owner
AND    a.object_name=:object_name;
