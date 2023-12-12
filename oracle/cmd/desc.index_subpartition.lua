local query = obj.redirect('index')
query[3]= [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
        FROM   (SELECT * FROM ALL_IND_PARTITIONS WHERE INDEX_OWNER = :owner AND INDEX_NAME = :object_name AND SUBPARTITION_NAME=:object_subname) T,
               (SELECT * FROM ALL_OBJECTS  WHERE OWNER = :owner AND OBJECT_NAME = :object_name AND subobject_name=:object_subname) O
        WHERE  T.INDEX_NAME=O.OBJECT_NAME]]
return query