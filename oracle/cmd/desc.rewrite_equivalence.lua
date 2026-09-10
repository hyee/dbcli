env.set.set('COLWRAP', 180)
env.var.define_column("owner,object_name,object_type","noprint")
return {
    [[SELECT /*topic="SOURCE_STMT"*/ source_stmt
      FROM   all_rewrite_equivalences
      WHERE  owner = :owner
      AND    name = :object_name]],
    [[SELECT /*topic="DESTINATION_STMT"*/ destination_stmt
      FROM   all_rewrite_equivalences
      WHERE  owner = :owner
      AND    name = :object_name]],
    [[SELECT /*PIVOT*/ a.rewrite_mode, b.*
      FROM   all_rewrite_equivalences a, all_objects b
      WHERE  a.owner = :owner
      AND    a.name = :object_name
      AND    b.owner = :owner
      AND    object_name = :object_name
      AND    b.object_id = :object_id]],
}
