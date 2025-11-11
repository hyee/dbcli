env.var.define_column('OWNER,INDEX_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
return {
    [[select /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'current')*/ 
               DECODE(column_position,1,table_owner||'.'||table_name) table_name,
               column_position NO#,
               column_name,column_expression column_expr,column_length,char_length,descend
        from   all_ind_columns 
        left   join all_ind_expressions using(index_owner,index_name,column_position,table_owner,table_name)
        WHERE  index_owner=:1 and index_name=:2
        ORDER BY NO#]],
    [[WITH  r1 AS (SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('container_data' 'current')*/*
                   FROM all_part_key_columns 
                   WHERE owner=:owner and NAME = :object_name),
            r2 AS (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=:owner and NAME = :object_name)
     SELECT LOCALITY,
            PARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                  FROM   r1
                                  START  WITH column_position = 1
                                  CONNECT BY PRIOR column_position = column_position - 1) PARTITIONED_BY,
            PARTITION_COUNT PARTS,
            SUBPARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                     FROM   R2
                                     START  WITH column_position = 1
                                     CONNECT BY PRIOR column_position = column_position - 1) SUBPART_BY,
            def_subpartition_count subs,
            DEF_TABLESPACE_NAME,
            DEF_PCT_FREE,
            DEF_INI_TRANS,
            DEF_LOGGING
        FROM   all_part_indexes
        WHERE  index_name = :object_name
        AND    owner = :owner]],
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
      FROM   (SELECT * FROM ALL_INDEXES  WHERE OWNER = :owner AND INDEX_NAME = :object_name) T,
             (SELECT * FROM ALL_OBJECTS  WHERE OWNER = :owner AND OBJECT_NAME = :object_name) O
      WHERE  T.INDEX_NAME=O.OBJECT_NAME]]
}