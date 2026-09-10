env.var.define_column('OWNER,TABLE_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
return {[[
    SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) use_hash(a b c) opt_param('container_data' 'current')*/
           column_id no#,
           a.column_name name,
           data_type_owner || nvl2(data_type_owner, '.', '') ||
           CASE WHEN data_type IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'RAW') --
                THEN data_type||'(' || decode(c.char_used, 'C', c.char_length, c.data_length) || decode(c.char_used, 'C', ' CHAR') || ')' --
                WHEN data_type IN ('NCHAR', 'NVARCHAR', 'NVARCHAR2') THEN data_type||'(' || c.char_length || ')' --
                WHEN c.data_type IN ('NCLOB', 'CLOB', 'BLOB') THEN data_type
                WHEN c.data_type = 'NUMBER' THEN
                    CASE WHEN nvl(c.data_scale, c.data_precision) IS NULL THEN c.data_type
                         WHEN c.data_scale > 0 THEN data_type||'(' || nvl(''||c.data_precision, '38') || ',' || data_scale || ')'
                         WHEN c.data_precision IS NULL AND c.data_scale = 0 THEN 'INTEGER'
                         ELSE c.data_type||'(' || c.data_precision ||')'
                    END
                $IF dbms_db_version.version > 22 $THEN
                WHEN c.data_type = 'VECTOR' THEN c.vector_info
                $END
                ELSE c.data_type
           END
            $IF dbms_db_version.version > 22 $THEN
            ||rtrim(' '||trim('.' from decode(c.domain_owner, c.owner, '', c.domain_owner)||'.'||c.domain_name))
            $END
            ||nvl2(l.cname, '['||trim(decode(l.in_row, 'YES', l.max_inline||' INLINE', 'NOINLINE')||decode(l.compression, 'NO', ' NOCOMPRESS', ' COMPRESS '||l.compression)||decode(l.cache, 'YES', ' CACHE', ' NOCACHE')||']'), '')
           AS data_type,
           decode(nullable, 'N', 'NOT NULL', '') nullable,
           (CASE
               WHEN default_length > 0 THEN
                data_default
               ELSE
                NULL
           END) "Default",
           hidden_column "Hidden?",
           a.avg_col_len avg_len,
           a.num_distinct "NDV",
           CASE WHEN b.num_rows >= a.num_nulls THEN round(a.num_nulls*100/nullif(b.num_rows, 0), 2) END "Nulls(%)",
           round(greatest(0, b.num_rows-a.num_nulls)/nullif(a.num_distinct, 0), 2) cardinality,
           nullif(a.histogram, 'NONE') histogram,
           a.num_buckets buckets,
           CASE WHEN a.low_value IS NOT NULL THEN
            substrb(decode(dtype
              ,'NUMBER'       ,to_char(utl_raw.cast_to_number(a.low_value))
              ,'FLOAT'        ,to_char(utl_raw.cast_to_number(a.low_value))
              ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(a.low_value))
              ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(a.low_value))
              ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(a.low_value))
              ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(a.low_value))
              ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(a.low_value))
              ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(a.low_value))
              ,'TIMESTAMP'    , lpad(to_number(substr(a.low_value, 1, 2), 'XX')-100, 2, 0)||
                                lpad(to_number(substr(a.low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                lpad(to_number(substr(a.low_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                                lpad(to_number(substr(a.low_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                                lpad(to_number(substr(a.low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(a.low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(a.low_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                nvl(substr(to_number(substr(a.low_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
              ,'TIMESTAMP WITH TIME ZONE',
                                lpad(to_number(substr(a.low_value, 1, 2), 'XX')-100, 2, 0)||
                                lpad(to_number(substr(a.low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                lpad(to_number(substr(a.low_value, 5, 2), 'XX'), 2, 0)|| '-' ||
                                lpad(to_number(substr(a.low_value, 7, 2), 'XX'), 2, 0)|| ' ' ||
                                lpad(to_number(substr(a.low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(a.low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(a.low_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                nvl(substr(to_number(substr(a.low_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')||' '||
                                nvl(to_number(substr(a.low_value, 23, 2), 'XX')-20, 0)||':'||nvl(to_number(substr(a.low_value, 25, 2), 'XX')-60, 0)
              ,'DATE',lpad(to_number(substr(a.low_value, 1, 2), 'XX')-100, 2, 0)||
                      lpad(to_number(substr(a.low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                      lpad(to_number(substr(a.low_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                      lpad(to_number(substr(a.low_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                      lpad(to_number(substr(a.low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(a.low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(a.low_value, 13, 2), 'XX')-1, 2, 0)
              ,  a.low_value), 1, 32) END low_value,
           CASE WHEN a.high_value IS NOT NULL THEN
            substrb(decode(dtype
              ,'NUMBER'       ,to_char(utl_raw.cast_to_number(a.high_value))
              ,'FLOAT'        ,to_char(utl_raw.cast_to_number(a.high_value))
              ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(a.high_value))
              ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(a.high_value))
              ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(a.high_value))
              ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(a.high_value))
              ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(a.high_value))
              ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(a.high_value))
              ,'TIMESTAMP'    ,lpad(to_number(substr(a.high_value, 1, 2), 'XX')-100, 2, 0)||
                               lpad(to_number(substr(a.high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                               lpad(to_number(substr(a.high_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                               lpad(to_number(substr(a.high_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                               lpad(to_number(substr(a.high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                               lpad(to_number(substr(a.high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                               lpad(to_number(substr(a.high_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                               nvl(substr(to_number(substr(a.high_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
              ,'TIMESTAMP WITH TIME ZONE',
                               lpad(to_number(substr(a.high_value, 1, 2), 'XX')-100, 2, 0)||
                               lpad(to_number(substr(a.high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                               lpad(to_number(substr(a.high_value, 5, 2), 'XX'), 2, 0)|| '-' ||
                               lpad(to_number(substr(a.high_value, 7, 2), 'XX'), 2, 0)|| ' ' ||
                               lpad(to_number(substr(a.high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                               lpad(to_number(substr(a.high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                               lpad(to_number(substr(a.high_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                               nvl(substr(to_number(substr(a.high_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')||' '||
                               nvl(to_number(substr(a.high_value, 23, 2), 'XX')-20, 0)||':'||nvl(to_number(substr(a.high_value, 25, 2), 'XX')-60, 0)
              ,'DATE',lpad(to_number(substr(a.high_value, 1, 2), 'XX')-100, 2, 0)||
                      lpad(to_number(substr(a.high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                      lpad(to_number(substr(a.high_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                      lpad(to_number(substr(a.high_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                      lpad(to_number(substr(a.high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(a.high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(a.high_value, 13, 2), 'XX')-1, 2, 0)
              ,  a.high_value), 1, 32) END high_value
    FROM   (SELECT /*+no_merge*/ c.*, regexp_replace(data_type, '\(.+\)') dtype FROM all_tab_cols c WHERE owner = :owner AND table_name = :object_name) c,
           (SELECT /*+no_merge*/ * FROM all_part_col_statistics WHERE owner = :owner AND table_name = :object_name AND partition_name = :object_subname) a,
           (SELECT /*+no_merge*/ * FROM all_tab_partitions WHERE table_owner = :owner AND table_name = :object_name AND partition_name = :object_subname) b,
           (SELECT /*+no_merge*/ column_name cname, in_row, cache,
                   $IF dbms_db_version.version > 22 $THEN max_inline $ELSE to_number(NULL) $END max_inline,
                   $IF dbms_db_version.version > 10 $THEN
                       securefile, compression
                   $ELSE
                       'NO' securefile, 'NO' compression
                   $END
            FROM   all_lob_partitions
            WHERE  table_owner = :owner
            AND    table_name = :object_name
            AND    partition_name = :object_subname) l
    WHERE  a.owner = c.owner
    AND    a.table_name = c.table_name
    AND    a.column_name = c.column_name
    AND    a.column_name = l.cname(+)
    AND    a.owner = b.table_owner
    AND    a.table_name = b.table_name
    AND    a.partition_name = b.partition_name
    ORDER  BY no#]],
    [[
        WITH i AS (SELECT /*+cardinality(1) outline_leaf push_pred(c) no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 5) */
                           i.*, i.index_owner owner, nvl(c.locality, 'GLOBAL') locality,
                           nullif(subpartitioning_type, 'NONE')||extractvalue(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+CURSOR_SHARING_FORCE no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i1.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') subpart_by
                    FROM   all_ind_partitions i, all_part_indexes c,
                          (SELECT owner, index_name FROM all_indexes WHERE table_owner = :owner AND table_name = :object_name) i1
                    WHERE  c.owner(+) = i.index_owner
                    AND    c.index_name(+) = i.index_name
                    AND    i.partition_name = :object_subname
                    AND    i.index_owner = i1.owner
                    AND    i.index_name = i1.index_name)
        SELECT /*+no_parallel opt_param('container_data' 'current') outline_leaf use_hash(c e) leading(i c e)  opt_param('_optim_peek_user_binds','false') opt_param('_sort_elimination_cost_ratio',5)*/
                decode(c.column_position, 1, i.owner, '') owner,
                decode(c.column_position, 1, i.index_name, '') index_name,
                decode(c.column_position, 1, subpart_by, '') "SUBPARTITIONED",
                decode(c.column_position, 1, locality, '') "LOCALITY",
                --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
                decode(c.column_position, 1, decode(i.status, 'N/A', (SELECT MIN(status) FROM all_ind_partitions p WHERE p.index_owner = i.owner AND p.index_name = i.index_name), i.status), '') status,
                decode(c.column_position, 1, i.blevel) blevel,
                decode(c.column_position, 1, round(100*i.clustering_factor/greatest(i.num_rows, 1), 2)) "CF(%)/Rows",
                decode(c.column_position, 1, i.distinct_keys) distincts,
                decode(c.column_position, 1, i.leaf_blocks) leaf_blocks,
                decode(c.column_position, 1, avg_leaf_blocks_per_key) "LB/KEY",
                decode(c.column_position, 1, avg_data_blocks_per_key) "DB/KEY",
                decode(c.column_position, 1, ceil(i.num_rows/greatest(i.distinct_keys, 1))) card,
                decode(c.column_position, 1, i.last_analyzed) last_analyzed,
                c.column_position no#,
                c.column_name,
                e.column_expression column_expr,
                c.descend
        FROM   i,  all_ind_columns c,  all_ind_expressions e
        WHERE  c.index_owner = i.owner
        AND    c.index_name = i.index_name
        AND    c.index_name = e.index_name(+)
        AND    c.index_owner = e.index_owner(+)
        AND    c.column_position = e.column_position(+)
        AND    :owner = c.table_owner
        AND    :object_name = c.table_name
        AND    :owner = e.table_owner(+)
        AND    :object_name = e.table_name(+)
        ORDER  BY c.index_name, c.column_position]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
        FROM   (SELECT * FROM all_tab_partitions   WHERE table_owner = :owner AND table_name = :object_name AND partition_name = :object_subname) t,
               (SELECT * FROM all_objects  WHERE owner = :owner AND object_name = :object_name AND subobject_name = :object_subname) o
        WHERE  t.table_name = o.object_name]]
}
