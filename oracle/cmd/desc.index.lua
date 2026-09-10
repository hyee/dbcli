env.var.define_column('OWNER,INDEX_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
local rtn = {
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'current')*/
           decode(column_position, 1, table_owner||'.'||table_name) table_name,
           column_position no#,
           column_name,
           column_expression column_expr,
           column_length,
           char_length,
           descend
      FROM   all_ind_columns
      LEFT   JOIN all_ind_expressions
      USING  (index_owner, index_name, column_position, table_owner, table_name)
      WHERE  index_owner = :1
      AND    index_name = :2
      ORDER  BY no#]],
    [[WITH r1 AS (SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('container_data' 'current')*/*
                  FROM   all_part_key_columns
                  WHERE  owner = :owner
                  AND    name = :object_name),
           r2 AS (SELECT /*+no_merge*/ *
                  FROM   all_subpart_key_columns
                  WHERE  owner = :owner
                  AND    name = :object_name)
     SELECT locality,
            partitioning_type || (SELECT max('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                 FROM   r1
                                 START  WITH column_position = 1
                                 CONNECT BY PRIOR column_position = column_position - 1) partitioned_by,
            partition_count parts,
            subpartitioning_type || (SELECT max('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                     FROM   r2
                                     START  WITH column_position = 1
                                     CONNECT BY PRIOR column_position = column_position - 1) subpart_by,
            def_subpartition_count subs,
            def_tablespace_name,
            def_pct_free,
            def_ini_trans,
            def_logging
     FROM   all_part_indexes
     WHERE  index_name = :object_name
     AND    owner = :owner]],
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
      FROM   (SELECT * FROM all_indexes  WHERE owner = :owner AND index_name = :object_name) t,
             (SELECT * FROM all_objects  WHERE owner = :owner AND object_name = :object_name AND subobject_name IS NULL) o
      WHERE  t.index_name = o.object_name]]
}

if db.props.version > 23.2 then
    local idx = #rtn - 1
    if db:check_access("VECSYS.VECTOR$INDEX", true) then
        env.table.insert(rtn, idx, [[
        SELECT json_serialize(idx_params RETURNING VARCHAR2 PRETTY) "Vector Index Params",'|' "|",
               json_serialize(idx_auxiliary_tables RETURNING VARCHAR2 PRETTY) "Vector Auxiliary Tables"
        FROM   vecsys.vector$index WHERE idx_objn = :object_id]])
        idx = idx + 1
    end
    if db:check_access("SYS.V_$VECTOR_GRAPH_INDEX", true) then
        env.table.insert(rtn, idx, [[
        SELECT /*+topic="HNSW Index Info"*/
               inst_id              "INST|ID",
               index_graph_type     "GRAPH|TYPE",
               num_layers           "NUM|LAYERS",
               num_vectors          "NUM|VECTORS",
               sparse_layer_vectors "SPARSE|VECTORS",
               num_neighbors        "NUM|NEIGHBORS",
               ef_construction      "EF|CONSTRUCTION",
               total_edges          "TOTAL|EDGES",
               ref_count            "REF|COUNT",
               query_dist_count     "QUERY|DIST_COUNT",
               creation_dist_count  "CREATION|DIST_COUNT",
               pruned_neighbors     "PRUNED|NEIGHBORS",
               num_snapshots        "NUM|SNAPSHOTS",
               max_snapshot         "MAX|SNAPSHOT",
               dbms_xplan.format_size(allocated_bytes) "ALLOC|BYTES",
               dbms_xplan.format_size(used_bytes)      "USED|BYTES",
               covering_cols        "COVERING|COLS"
        FROM   sys.gv_$vector_graph_index
        WHERE  index_objn = :object_id]])
        idx = idx + 1
    end

    if db.props.version >= 23.26 and db:check_access("SYS.DBMS_VECTOR", true) then
        env.table.insert(rtn, idx, [[
        DECLARE
            arr  dbms_output.chararr;
            siz  PLS_INTEGER;
            txt  VARCHAR2(4000);
        BEGIN
            dbms_output.disable;
            dbms_output.enable(NULL);
            sys.dbms_vector.get_index_status(:owner, :object_name);
            dbms_output.get_lines(arr, siz);
            dbms_output.disable;
            dbms_output.enable(NULL);
            IF nvl(siz, 0) = 0 THEN
                RETURN;
            END IF;

            FOR i IN 1 .. siz LOOP
                txt := txt || arr(i) || chr(10);
            END LOOP;
            OPEN :v_cur FOR
                SELECT trim(txt) index_status
                FROM   dual;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;]])
        idx = idx + 1
    end
end

return rtn;
