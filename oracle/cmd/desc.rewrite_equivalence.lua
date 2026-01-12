env.set.set('COLWRAP',180)
env.var.define_column("owner,object_name,object_type","noprint")
return {
    [[SELECT /*topic="SOURCE_STMT"*/ SOURCE_STMT FROM all_rewrite_equivalences WHERE OWNER=:owner AND NAME=:object_name]],
    [[SELECT /*topic="DESTINATION_STMT"*/ DESTINATION_STMT FROM all_rewrite_equivalences WHERE OWNER=:owner AND NAME=:object_name]],
    [[SELECT /*PIVOT*/ a.REWRITE_MODE,b.* 
      FROM  all_rewrite_equivalences a,all_objects b
      WHERE a.OWNER=:owner AND a.NAME=:object_name
      AND   b.OWNER=:owner AND OBJECT_NAME=:object_name
      AND   b.OBJECT_ID=:object_id]],
}