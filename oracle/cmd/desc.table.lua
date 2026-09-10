
local blocks, rows = 0, 0
if obj.object_type:find('^TABLE') or obj.object_type:find('^MATERIALIZE') then
    local result = db:dba_query(db.internal_call,
                                [[SELECT nvl(cluster_name, table_name), blocks, num_rows
                                  FROM   all_tables
                                  WHERE  owner = :owner
                                  AND    table_name = :object_name]],
                                {owner = obj[1], object_name = obj[2]})
    result = db.resultset:rows(result, -1)
    result = result[2] or {}
    obj.table_name = result[1]
    blocks, rows = env.tonumber(result[2]) or 0, env.tonumber(result[3]) or 0

    if obj.object_name:find('^X%$') and obj.owner == 'SYS' and obj.object_id >= 4200000000 then
        obj.object_type = 'FIXED TABLE'
    end
else
    obj.table_name = ''
end
env.var.define_column('OWNER,TABLE_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')

return obj.object_type == 'FIXED TABLE' and [[
    SELECT /*+outline_leaf ordered use_nl(b c) opt_param('container_data' 'all') opt_param('optimizer_dynamic_sampling' 5)*/
           a.*,
           c.avg_col_len avg_len,
           c.num_distinct "NDV",
           CASE WHEN b.rowcnt >= c.num_nulls THEN round(c.num_nulls*100/nullif(b.rowcnt, 0), 2) END "Nulls(%)",
           CASE WHEN b.rowcnt >= c.num_nulls THEN round((b.rowcnt-c.num_nulls)/nullif(c.num_distinct, 0), 2) END cardinality,
           c.sample_size,
           c.last_analyzed,
           CASE WHEN c.low_value IS NOT NULL THEN
            substrb(decode(regexp_substr(data_type, '[^\(]+')
              ,'NUMBER'       ,to_char(utl_raw.cast_to_number(c.low_value))
              ,'FLOAT'        ,to_char(utl_raw.cast_to_number(c.low_value))
              ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(c.low_value))
              ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(c.low_value))
              ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(c.low_value))
              ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(c.low_value))
              ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(c.low_value))
              ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(c.low_value))
              ,'TIMESTAMP'    , lpad(to_number(substr(c.low_value, 1, 2), 'XX')-100, 2, 0)||
                                lpad(to_number(substr(c.low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                lpad(to_number(substr(c.low_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                                lpad(to_number(substr(c.low_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                                lpad(to_number(substr(c.low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.low_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                nvl(substr(to_number(substr(c.low_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
              ,'TIMESTAMP WITH TIME ZONE',
                                lpad(to_number(substr(c.low_value, 1, 2), 'XX')-100, 2, 0)||
                                lpad(to_number(substr(c.low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                lpad(to_number(substr(c.low_value, 5, 2), 'XX'), 2, 0)|| '-' ||
                                lpad(to_number(substr(c.low_value, 7, 2), 'XX'), 2, 0)|| ' ' ||
                                lpad(to_number(substr(c.low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.low_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                nvl(substr(to_number(substr(c.low_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')||' '||
                                nvl(to_number(substr(c.low_value, 23, 2), 'XX')-20, 0)||':'||
                                nvl(to_number(substr(c.low_value, 25, 2), 'XX')-60, 0)
              ,'DATE',lpad(to_number(substr(c.low_value, 1, 2), 'XX')-100, 2, 0)||
                      lpad(to_number(substr(c.low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                      lpad(to_number(substr(c.low_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                      lpad(to_number(substr(c.low_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                      lpad(to_number(substr(c.low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(c.low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(c.low_value, 13, 2), 'XX')-1, 2, 0)
              ,  c.low_value), 1, 32) END low_value,
           CASE WHEN c.high_value IS NOT NULL THEN
            substrb(decode(regexp_substr(data_type, '[^\(]+')
              ,'NUMBER'       ,to_char(utl_raw.cast_to_number(c.high_value))
              ,'FLOAT'        ,to_char(utl_raw.cast_to_number(c.high_value))
              ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(c.high_value))
              ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(c.high_value))
              ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(c.high_value))
              ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(c.high_value))
              ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(c.high_value))
              ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(c.high_value))
              ,'TIMESTAMP'    , lpad(to_number(substr(c.high_value, 1, 2), 'XX')-100, 2, 0)||
                                lpad(to_number(substr(c.high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                lpad(to_number(substr(c.high_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                                lpad(to_number(substr(c.high_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                                lpad(to_number(substr(c.high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.high_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                nvl(substr(to_number(substr(c.high_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
              ,'TIMESTAMP WITH TIME ZONE',
                                lpad(to_number(substr(c.high_value, 1, 2), 'XX')-100, 2, 0)||
                                lpad(to_number(substr(c.high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                lpad(to_number(substr(c.high_value, 5, 2), 'XX'), 2, 0)|| '-' ||
                                lpad(to_number(substr(c.high_value, 7, 2), 'XX'), 2, 0)|| ' ' ||
                                lpad(to_number(substr(c.high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                lpad(to_number(substr(c.high_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                nvl(substr(to_number(substr(c.high_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')||' '||
                                nvl(to_number(substr(c.high_value, 23, 2), 'XX')-20, 0)||':'||
                                nvl(to_number(substr(c.high_value, 25, 2), 'XX')-60, 0)
              ,'DATE',lpad(to_number(substr(c.high_value, 1, 2), 'XX')-100, 2, 0)||
                      lpad(to_number(substr(c.high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                      lpad(to_number(substr(c.high_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                      lpad(to_number(substr(c.high_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                      lpad(to_number(substr(c.high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(c.high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                      lpad(to_number(substr(c.high_value, 13, 2), 'XX')-1, 2, 0)
              ,  c.high_value), 1, 32) END high_value
    FROM   (SELECT kqftaobj obj#, c.kqfcocno col#, c.kqfconam column_name,
                   decode(kqfcodty,
                           1,'VARCHAR2',
                           2,'NUMBER',
                           8,'LONG',
                           9,'VARCHAR',
                           12,'DATE',
                           23,'RAW',
                           24,'LONG RAW',
                           58,'CUSTOM OBJ',
                           69,'ROWID',
                           96,'CHAR',
                           100,'BINARY_FLOAT',
                           101,'BINARY_DOUBLE',
                           105,'MLSLABEL',
                           106,'MLSLABEL',
                           108,'OBJECT',
                           111,'REF',
                           112,'CLOB',
                           113,'BLOB',
                           114,'BFILE',
                           115,'CFILE',
                           119,'JSON',
                           121,'CUSTOM OBJ',
                           122,'CUSTOM OBJ',
                           123,'CUSTOM OBJ',
                           127,'VECTOR',
                           178,'TIME',
                           179,'TIME WITH TIME ZONE',
                           180,'TIMESTAMP',
                           181,'TIMESTAMP WITH TIME ZONE',
                           231,'TIMESTAMP WITH LOCAL TIME ZONE',
                           182,'INTERVAL YEAR TO MONTH',
                           183,'INTERVAL DAY TO SECOND',
                           208,'UROWID',
                           252,'BOOLEAN',
                           'UNKNOWN('||kqfcodty||')') || '(' || to_char(c.kqfcosiz) || ')' data_type,
                   c.kqfcosiz col_size,
                   c.kqfcooff col_offset,
                   lpad('0x' || trim(to_char(c.kqfcooff, 'XXXXXX')), 8) offset_hex,
                   decode(c.kqfcoidx, 0, '', 'Yes('||c.kqfcoidx||')') "Indexed?"
            FROM   sys.x$kqfta t, sys.x$kqfco c
            WHERE  c.kqfcotab = t.indx
            AND    c.inst_id = t.inst_id
            AND   (t.kqftanam = :object_name OR t.kqftanam = (SELECT kqfdtequ FROM sys.x$kqfdt WHERE kqfdtnam = :object_name))) a,
           sys.tab_stats$ b,
           sys.dba_tab_col_statistics c
    WHERE  a.obj# = b.obj#(+)
    AND    c.owner(+) = :owner
    AND    c.table_name(+) = :object_name
    AND    c.column_name(+) = a.column_name
    ORDER  BY 1, 2
    ]] or {[[
        SELECT /*INTERNAL_DBCLI_CMD topic="Column info"*/
             /*+opt_param('container_data' 'current') opt_param('optimizer_dynamic_sampling' 5)
               no_parallel opt_param('_optim_peek_user_binds','false') use_hash(a b c) use_hash(d) swap_join_inputs(c) */
               a.internal_column_id no#,
               a.column_name name,
               a.data_type_owner || nvl2(a.data_type_owner, '.', '') ||
               CASE WHEN a.data_type IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'RAW') --
                    THEN a.data_type||'(' || decode(a.char_used, 'C', a.char_length, a.data_length) || decode(a.char_used, 'C', ' CHAR') || ')' --
                    WHEN a.data_type IN ('NCHAR', 'NVARCHAR', 'NVARCHAR2')
                    THEN a.data_type||'(' || a.char_length || ')' --
                    WHEN a.data_type IN ('NCLOB', 'CLOB', 'BLOB') THEN a.data_type
                    WHEN a.data_type = 'NUMBER' THEN
                        CASE WHEN nvl(a.data_scale, a.data_precision) IS NULL THEN a.data_type
                             WHEN a.data_scale > 0 THEN data_type||'(' || nvl(''||a.data_precision, '38') || ',' || data_scale || ')'
                             WHEN a.data_precision IS NULL AND a.data_scale = 0 THEN 'INTEGER'
                             ELSE a.data_type||'(' || a.data_precision ||')'
                        END
                    $IF dbms_db_version.version > 22 $THEN
                    WHEN a.data_type = 'VECTOR' THEN a.vector_info
                    $END
                    ELSE a.data_type
               END
                 $IF dbms_db_version.version > 22 $THEN
                 ||rtrim(' '||trim('.' from decode(a.domain_owner, a.owner, '', a.domain_owner)||'.'||a.domain_name))
                 $END
                 $IF dbms_db_version.version>12 OR dbms_db_version.version=12 and dbms_db_version.RELEASE>1 $THEN
                 ||CASE WHEN a.collation != nvl(b.default_collation, a.collation) THEN ' COLLATE '||a.collation END
                 $END
                 ||nvl2(l.cname, '['||trim(decode(l.in_row, 'YES', nvl(l.max_inline, a.data_length)||' INLINE', 'NOINLINE')||decode(l.compression, 'NO', ' NOCOMPRESS', ' COMPRESS '||l.compression)||decode(l.cache, 'YES', ' CACHE', ' NOCACHE')||']'), '')
               AS data_type,
               decode(a.nullable, 'N', 'NOT NULL', '') nullable,
               (CASE
                   WHEN a.default_length > 0 THEN
                        a.data_default
                   ELSE
                        NULL
               END) "Default",
               nvl2(d.cname, ''''||d.integrity_alg||''''||decode(d.salt, 'NO', ' NO SALT'), '') encryption,
               e.redaction,
               a.hidden_column "Hidden?",
               a.avg_col_len avg_len,
               a.num_distinct "NDV",
               CASE WHEN b.num_rows >= a.num_nulls THEN round(a.num_nulls*100/nullif(b.num_rows, 0), 2) END "Nulls(%)",
               round(greatest(0, b.num_rows-a.num_nulls)/nullif(a.num_distinct, 0), 2) cardinality,
               nullif(histogram, 'NONE') histogram,
               a.num_buckets buckets,
               CASE WHEN a.low_value IS NOT NULL THEN
                substrb(decode(dtype
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(low_value))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(low_value))
                  ,'TIMESTAMP'    , lpad(to_number(substr(low_value, 1, 2), 'XX')-100, 2, 0)||
                                    lpad(to_number(substr(low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                    lpad(to_number(substr(low_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                                    lpad(to_number(substr(low_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                                    lpad(to_number(substr(low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(low_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                    nvl(substr(to_number(substr(low_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(to_number(substr(low_value, 1, 2), 'XX')-100, 2, 0)||
                                    lpad(to_number(substr(low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                    lpad(to_number(substr(low_value, 5, 2), 'XX'), 2, 0)|| '-' ||
                                    lpad(to_number(substr(low_value, 7, 2), 'XX'), 2, 0)|| ' ' ||
                                    lpad(to_number(substr(low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(low_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                    nvl(substr(to_number(substr(low_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')||' '||
                                    nvl(to_number(substr(low_value, 23, 2), 'XX')-20, 0)||':'||
                                    nvl(to_number(substr(low_value, 25, 2), 'XX')-60, 0)
                  ,'DATE',lpad(to_number(substr(low_value, 1, 2), 'XX')-100, 2, 0)||
                          lpad(to_number(substr(low_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                          lpad(to_number(substr(low_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                          lpad(to_number(substr(low_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                          lpad(to_number(substr(low_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                          lpad(to_number(substr(low_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                          lpad(to_number(substr(low_value, 13, 2), 'XX')-1, 2, 0)
                  ,  low_value), 1, 32) END low_value,
               CASE WHEN a.high_value IS NOT NULL THEN
                substrb(decode(dtype
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(high_value))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(high_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(high_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(high_value))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(high_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(high_value))
                  ,'TIMESTAMP'    , lpad(to_number(substr(high_value, 1, 2), 'XX')-100, 2, 0)||
                                    lpad(to_number(substr(high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                    lpad(to_number(substr(high_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                                    lpad(to_number(substr(high_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                                    lpad(to_number(substr(high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(high_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                    nvl(substr(to_number(substr(high_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(to_number(substr(high_value, 1, 2), 'XX')-100, 2, 0)||
                                    lpad(to_number(substr(high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                                    lpad(to_number(substr(high_value, 5, 2), 'XX'), 2, 0)|| '-' ||
                                    lpad(to_number(substr(high_value, 7, 2), 'XX'), 2, 0)|| ' ' ||
                                    lpad(to_number(substr(high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                                    lpad(to_number(substr(high_value, 13, 2), 'XX')-1, 2, 0)|| '.' ||
                                    nvl(substr(to_number(substr(high_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')||' '||
                                    nvl(to_number(substr(high_value, 23, 2), 'XX')-20, 0)||':'||
                                    nvl(to_number(substr(high_value, 25, 2), 'XX')-60, 0)
                  ,'DATE',lpad(to_number(substr(high_value, 1, 2), 'XX')-100, 2, 0)||
                          lpad(to_number(substr(high_value, 3, 2), 'XX')-100, 2, 0)|| '-' ||
                          lpad(to_number(substr(high_value, 5, 2), 'XX') , 2, 0)|| '-' ||
                          lpad(to_number(substr(high_value, 7, 2), 'XX') , 2, 0)|| ' ' ||
                          lpad(to_number(substr(high_value, 9, 2), 'XX')-1, 2, 0)|| ':' ||
                          lpad(to_number(substr(high_value, 11, 2), 'XX')-1, 2, 0)|| ':' ||
                          lpad(to_number(substr(high_value, 13, 2), 'XX')-1, 2, 0)
                  ,  high_value), 1, 32) END high_value,
               c.comments
        FROM       (SELECT /*+no_merge*/ a.*, regexp_replace(data_type, '\(.+\)') dtype FROM all_tab_cols a WHERE a.owner = :owner AND a.table_name = :object_name) a
        LEFT JOIN  (SELECT /*+no_merge*/ * FROM all_tables a WHERE '&object_type' LIKE 'TABLE%' AND a.owner = :owner AND a.table_name = :object_name) b
        ON         (a.table_name = b.table_name)
        LEFT JOIN  (SELECT /*+no_merge*/ column_name cname, comments FROM all_col_comments WHERE owner = :owner AND table_name = :object_name) c
        ON         (a.column_name = c.cname)
        LEFT JOIN  (SELECT /*+no_merge*/ column_name cname, salt, integrity_alg FROM all_encrypted_columns WHERE '&object_type' LIKE 'TABLE%' AND owner = :owner AND table_name = :object_name) d
        ON         (a.column_name = d.cname)
        LEFT JOIN  (SELECT /*+no_merge*/ column_name cname, in_row, cache,
                    $IF dbms_db_version.version > 22 $THEN max_inline $ELSE to_number(NULL) $END max_inline,
                    $IF dbms_db_version.version > 10 $THEN
                        securefile, compression
                    $ELSE
                        'NO' securefile, 'NO' compression
                    $END
                    FROM   all_lobs
                    WHERE  '&object_type' LIKE 'TABLE%'
                    AND    owner = :owner
                    AND    table_name = :object_name) l
        ON         (a.column_name = l.cname)
        LEFT JOIN  (
        $IF $$VERSION > 1101 AND ($$SELECT_CATALOG_ROLE OR $$SYSDBA) $THEN
            SELECT /*+no_merge*/ column_name cname, replace(function_type, ' REDACTION') redaction
            FROM   redaction_columns
            JOIN   redaction_policies USING (object_owner, object_name)
            WHERE  object_owner = '&owner'
            AND    object_name = '&object_name'
            AND    '&object_type' LIKE 'TABLE%'
        $ELSE
            SELECT ''  cname, '' redaction FROM dual WHERE 1=2
        $END
        ) e
        ON         (a.column_name = e.cname)
        ORDER  BY no#]],
    [[
        WITH /*topic="Index info" */
        i AS (SELECT /*+cardinality(1) outline_leaf push_pred(c) opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('container_data' 'current') opt_param('optimizer_dynamic_sampling' 5) */
                           i.*, nvl(c.locality, 'GLOBAL') locality,
                           partitioning_type||extractvalue(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+CURSOR_SHARING_FORCE no_merge*/* FROM all_part_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') partitioned_by,
                           nullif(subpartitioning_type, 'NONE')||extractvalue(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+CURSOR_SHARING_FORCE no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') subpart_by
                    FROM   all_indexes i, all_part_indexes c
                    WHERE  c.owner(+) = i.owner
                    AND    c.index_name(+) = i.index_name
                    AND    i.table_owner = :owner
                    AND    i.table_name = :table_name)
        SELECT /*+use_hash(e c) outline_leaf no_parallel opt_param('container_data' 'current') leading(i c e) opt_param('_sort_elimination_cost_ratio',5)*/
                decode(c.column_position, 1, i.owner, '') owner,
                decode(c.column_position, 1, i.index_name, '') index_name,
                decode(c.column_position, 1,
                       trim(',' from i.index_type||','||locality||','
                            ||decode(i.uniqueness, 'UNIQUE', 'UNIQUE,')
                            ||nvl2(partitioned_by, 'PARTT['||partitioned_by||nullif(','||subpart_by, ',')||'],', '')
                            ||nullif(decode(i.status, 'N/A', (SELECT MIN(status) FROM all_ind_partitions p WHERE p.index_owner = i.owner AND p.index_name = i.index_name), i.status)||',', 'VALID,')
                        )) attrs,
                --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
                decode(c.column_position, 1, i.blevel) blv,
                decode(c.column_position, 1, round(100*i.num_rows*]]..blocks..'/nullif('..rows..[[*i.clustering_factor, 0), 2)) "Blks/|CF(%)",
                decode(c.column_position, 1, dbms_xplan.format_number(i.num_rows)) "Rows",
                decode(c.column_position, 1, dbms_xplan.format_number(i.distinct_keys)) ndv,
                decode(c.column_position, 1, dbms_xplan.format_number(i.leaf_blocks)) "Blks",
                decode(c.column_position, 1, avg_leaf_blocks_per_key) "Leaf|B/KEY",
                decode(c.column_position, 1, avg_data_blocks_per_key) "Data|B/KEY",
                decode(c.column_position, 1, ceil(i.num_rows/greatest(i.distinct_keys, 1))) "Card",
                c.column_position no#,
                c.column_name,
                e.column_expression column_expr,
                c.descend dir,
                decode(c.column_position, 1, i.last_analyzed) last_analyzed
        FROM   i,  all_ind_columns c,  all_ind_expressions e
        WHERE  c.index_owner = i.owner
        AND    c.index_name = i.index_name
        AND    c.index_name = e.index_name(+)
        AND    c.index_owner = e.index_owner(+)
        AND    c.column_position = e.column_position(+)
        AND    :owner = c.table_owner
        AND    :table_name = c.table_name
        AND    :owner = e.table_owner(+)
        AND    :table_name = e.table_name(+)
        ORDER  BY c.index_name, c.column_position]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD topic="Constraint info"*/
               --+no_parallel opt_param('_optim_peek_user_binds','false') opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'current')
               decode(r, 1, constraint_name) constraint_name,
               decode(r, 1, constraint_type) ctype,
               decode(r, 1, r_table) r_table,
               decode(r, 1, r_constraint) r_constraint,
               search_condition c_condition,
               decode(r, 1, status) status,
               --DECODE(R, 1, DEFERRABLE) DEFERRABLE,
               decode(r, 1, deferred) deferred,
               decode(r, 1, validated) validated,
               decode(r, 1, rely) rely,
               decode(r, 1, bad) bad,
               column_name
        FROM   (SELECT --+outline_leaf leading(a r c) use_nl(a r) use_hash(c) push_pred(r) push_pred(c)
                       a.constraint_name,
                       a.constraint_type,
                       r.table_name r_table,
                       a.r_constraint_name r_constraint,
                       a.status,
                       a.deferrable,
                       a.deferred,
                       a.validated,
                       a.rely,
                       a.bad,
                       a.search_condition,
                       c.column_name,
                       row_number() OVER(PARTITION BY a.constraint_name ORDER BY c.column_name) r
                FROM   (SELECT * FROM all_constraints WHERE owner = :owner AND table_name = :object_name) a,
                       all_constraints r,
                       all_cons_columns c
                WHERE  a.r_owner = r.owner(+)
                AND    a.r_constraint_name = r.constraint_name(+)
                AND    a.owner = c.owner(+)
                AND    a.constraint_name = c.constraint_name(+)
                AND    :owner = c.owner(+)
                AND    :object_name = c.table_name(+)
                AND    (a.constraint_type != 'C' OR a.constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'))
    ]],
    [[/*grid={topic='Partitions', pivot=1}*/
    WITH r1 AS (SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'current')*/ *
                FROM   all_part_key_columns
                WHERE  owner = :owner
                AND    name = :object_name
    ),   r2 AS (SELECT /*+no_merge*/ *
                FROM   all_subpart_key_columns
                WHERE  owner = :owner
                AND    name = :object_name)
    SELECT partitioning_type || (SELECT max('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                 FROM   r1
                                 START  WITH column_position = 1
                                 CONNECT BY PRIOR column_position = column_position - 1)
                              partitioned_by,
           partition_count parts,
           subpartitioning_type || (SELECT max('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                     FROM   r2
                                     START  WITH column_position = 1
                                     CONNECT BY PRIOR column_position = column_position - 1) subpart_by,
           def_subpartition_count subs,
           def_tablespace_name,
           def_pct_free,
           def_ini_trans,
           def_logging,
           def_compression
    FROM   all_part_tables
    WHERE  table_name = :object_name
    AND    owner = :owner]],
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
      FROM   (SELECT * FROM all_tables   WHERE owner = :owner AND table_name = :object_name) t,
             (SELECT * FROM all_objects  WHERE owner = :owner AND object_name = :object_name AND subobject_name IS NULL) o
      WHERE  t.table_name = o.object_name]]
}
