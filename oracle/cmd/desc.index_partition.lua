local query = obj.redirect('index')
query[#query] = [[
    SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
    FROM   (SELECT * FROM all_ind_partitions WHERE index_owner = :owner AND index_name = :object_name AND partition_name = :object_subname) t,
           (SELECT * FROM all_objects  WHERE owner = :owner AND object_name = :object_name AND subobject_name = :object_subname) o
    WHERE  t.index_name = o.object_name]]
return query
