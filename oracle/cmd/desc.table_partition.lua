env.var.define_column('OWNER,TABLE_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
return {[[
         SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) use_hash(a b c) opt_param('container_data' 'current_dictionary')*/ 
                COLUMN_ID NO#,
                a.COLUMN_NAME NAME,
                DATA_TYPE_OWNER || NVL2(DATA_TYPE_OWNER, '.', '') ||
                CASE WHEN DATA_TYPE IN('CHAR',
                                       'VARCHAR',
                                       'VARCHAR2',
                                       'NCHAR',
                                       'NVARCHAR',
                                       'NVARCHAR2',
                                       'RAW') --
                THEN DATA_TYPE||'(' || DECODE(CHAR_USED, 'C', CHAR_LENGTH,DATA_LENGTH) || DECODE(CHAR_USED, 'C', ' CHAR') || ')' --
                WHEN DATA_TYPE = 'NUMBER' --
                THEN (CASE WHEN nvl(DATA_scale, DATA_PRECISION) IS NULL THEN DATA_TYPE
                           WHEN DATA_scale > 0 THEN DATA_TYPE||'(' || NVL(''||DATA_PRECISION, '38') || ',' || DATA_SCALE || ')'
                           WHEN DATA_PRECISION IS NULL AND DATA_scale=0 THEN 'INTEGER'
                           ELSE DATA_TYPE||'(' || DATA_PRECISION ||')' END) ELSE DATA_TYPE END
                data_type,
                DECODE(NULLABLE, 'N', 'NOT NULL', '') NULLABLE,
                (CASE
                    WHEN default_length > 0 THEN
                     DATA_DEFAULT
                    ELSE
                     NULL
                END) "Default",
                HIDDEN_COLUMN "Hidden?",
                a.AVG_COL_LEN AVG_LEN,
                a.num_distinct "NDV",
                CASE WHEN b.num_rows>=a.num_nulls THEN round(a.num_nulls*100/nullif(b.num_rows,0),2) END "Nulls(%)",
                round(greatest(0,b.num_rows-a.num_nulls)/nullif(a.num_distinct,0),2) CARDINALITY,
                nullif(a.HISTOGRAM,'NONE') HISTOGRAM，
                a.NUM_BUCKETS buckets,
                case when a.low_value is not null then 
                substrb(decode(dtype
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(a.low_value))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(a.low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(a.low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(a.low_value))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(a.low_value))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(a.low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(a.low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(a.low_value))
                  ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(a.low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(a.low_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(a.low_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(a.low_value, 23,2),'XX')-20,0)||':'||nvl(TO_NUMBER(SUBSTR(a.low_value, 25, 2), 'XX')-60,0)
                  ,'DATE',lpad(TO_NUMBER(SUBSTR(a.low_value, 1, 2), 'XX')-100,2,0)||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 13, 2), 'XX')-1,2,0)
                  ,  a.low_value),1,32) end low_value,
                case when a.high_value is not null then 
                substrb(decode(dtype
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(a.high_value))
                      ,'FLOAT'        ,to_char(utl_raw.cast_to_number(a.high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(a.high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(a.high_value))
                      ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(a.high_value))
                      ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(a.high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(a.high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(a.high_value))
                      ,'TIMESTAMP'    ,lpad(TO_NUMBER(SUBSTR(a.high_value, 1, 2), 'XX')-100,2,0)||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                       nvl(substr(TO_NUMBER(SUBSTR(a.high_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                      ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(a.high_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(a.high_value, 23,2),'XX')-20,0)||':'||nvl(TO_NUMBER(SUBSTR(a.high_value, 25, 2), 'XX')-60,0)
                     ,'DATE',lpad(TO_NUMBER(SUBSTR(a.high_value, 1, 2), 'XX')-100,2,0)||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 13, 2), 'XX')-1,2,0)
                        ,  a.high_value),1,32) end high_value
         FROM   (select /*+no_merge*/ c.*,regexp_replace(data_type,'\(.+\)') dtype from all_tab_cols c where owner=:owner and table_name=:object_name) c,  
                (select /*+no_merge*/ * from all_part_col_Statistics where owner=:owner and table_name=:object_name and partition_name=:object_subname) a,
                (select /*+no_merge*/ * from all_tab_partitions  where table_owner=:owner and table_name=:object_name and partition_name=:object_subname) b
         WHERE  a.owner=c.owner and a.table_name=c.table_name and a.column_name=c.column_name
         AND    a.owner=B.table_owner and a.table_name=B.table_name and a.partition_name=b.partition_name
         ORDER BY NO#]],
    [[
        WITH I AS (SELECT /*+cardinality(1) outline_leaf push_pred(c) no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 5) */ 
                           I.*,I.INDEX_OWNER OWNER,nvl(c.LOCALITY,'GLOBAL') LOCALITY,
                           nullif(SUBPARTITIONING_TYPE,'NONE')||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i1.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') SUBPART_BY
                    FROM   ALL_IND_PARTITIONS I,ALL_PART_INDEXES C,
                          (SELECT OWNER,INDEX_NAME FROM ALL_INDEXES WHERE TABLE_OWNER = :owner AND TABLE_NAME=:object_name) I1
                    WHERE  C.OWNER(+) = I.INDEX_OWNER
                    AND    C.INDEX_NAME(+) = I.INDEX_NAME
                    AND    I.PARTITION_NAME=:object_subname
                    AND    I.INDEX_OWNER = I1.OWNER
                    AND    I.INDEX_NAME = I1.INDEX_NAME)
        SELECT /*+no_parallel opt_param('container_data' 'current_dictionary') outline_leaf use_hash(c e) leading(i c e)  opt_param('_optim_peek_user_binds','false') opt_param('_sort_elimination_cost_ratio',5)*/
                DECODE(C.COLUMN_POSITION, 1, I.OWNER, '') OWNER,
                DECODE(C.COLUMN_POSITION, 1, I.INDEX_NAME, '') INDEX_NAME,
                DECODE(C.COLUMN_POSITION, 1, SUBPART_BY, '') "SUBPARTITIONED",
                DECODE(C.COLUMN_POSITION, 1, LOCALITY, '') "LOCALITY",
                --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
                DECODE(C.COLUMN_POSITION, 1, decode(I.STATUS,'N/A',(SELECT MIN(STATUS) FROM All_Ind_Partitions p WHERE p.INDEX_OWNER = I.OWNER AND p.INDEX_NAME = I.INDEX_NAME),I.STATUS), '') STATUS,
                DECODE(C.COLUMN_POSITION, 1, i.BLEVEL) BLEVEL,
                DECODE(C.COLUMN_POSITION, 1, round(100*i.CLUSTERING_FACTOR/greatest(i.num_rows,1),2)) "CF(%)/Rows",
                DECODE(C.COLUMN_POSITION, 1, i.DISTINCT_KEYS) DISTINCTS,
                DECODE(C.COLUMN_POSITION, 1, i.LEAF_BLOCKS) LEAF_BLOCKS,
                DECODE(C.COLUMN_POSITION, 1, AVG_LEAF_BLOCKS_PER_KEY) "LB/KEY",
                DECODE(C.COLUMN_POSITION, 1, AVG_DATA_BLOCKS_PER_KEY) "DB/KEY",
                DECODE(C.COLUMN_POSITION, 1, ceil(i.num_rows/greatest(i.DISTINCT_KEYS,1))) CARD,
                DECODE(C.COLUMN_POSITION, 1, i.LAST_ANALYZED) LAST_ANALYZED,
                C.COLUMN_POSITION NO#,
                C.COLUMN_NAME,
                E.COLUMN_EXPRESSION COLUMN_EXPR,
                C.DESCEND
        FROM   I,  ALL_IND_COLUMNS C,  all_ind_expressions e
        WHERE  C.INDEX_OWNER = I.OWNER
        AND    C.INDEX_NAME = I.INDEX_NAME
        AND    C.INDEX_NAME = e.INDEX_NAME(+)
        AND    C.INDEX_OWNER = e.INDEX_OWNER(+)
        AND    C.column_position = e.column_position(+)
        AND    :owner = c.table_owner
        AND    :object_name =c.table_name
        AND    :owner = E.table_owner(+)
        AND    :object_name =e.table_name(+)
        ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION]],     
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
        FROM   (SELECT * FROM ALL_TAB_PARTITIONS   WHERE TABLE_OWNER = :owner AND TABLE_NAME = :object_name AND PARTITION_NAME=:object_subname) T,
               (SELECT * FROM ALL_OBJECTS  WHERE OWNER = :owner AND OBJECT_NAME = :object_name AND subobject_name=:object_subname) O
        WHERE  T.TABLE_NAME=O.OBJECT_NAME]]
}