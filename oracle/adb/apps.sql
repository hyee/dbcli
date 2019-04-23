/*[[Show container applications.]]*/
SELECT c.con_id,c.name, aps.app_id,aps.app_name, aps.app_version, aps.app_status 
FROM dba_app_pdb_status aps JOIN v$containers c 
ON c.con_uid = aps.con_uid;

SELECT app.app_name, obj.owner, obj.object_name, obj.object_type, obj.sharing, obj.CREATED_APPID
FROM   dba_objects obj, dba_applications app
WHERE  obj.application = 'Y'
AND    obj.created_appid = app.app_id;