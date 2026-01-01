
local blocks,rows=0,0
if obj.object_type:find('^TABLE') or obj.object_type:find('^MATERIALIZE') then
    local result=db:dba_query(db.internal_call,
                              [[select nvl(cluster_name,table_name),blocks,num_rows
                               from ALL_TABLES
                               WHERE owner = :owner AND table_name = :object_name]],
                              {owner=obj[1],object_name=obj[2]})
    result=db.resultset:rows(result,-1)
    result=result[2] or {}
    obj.table_name=result[1]
    blocks,rows=env.tonumber(result[2]) or 0,env.tonumber(result[3]) or 0

    if obj.object_name:find('^X%$') and obj.owner=='SYS' and obj.object_id>=4200000000 then
        obj.object_type='FIXED TABLE'
    end
else
    obj.table_name=''
end
env.var.define_column('OWNER,TABLE_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')

return  obj.object_type=='FIXED TABLE' and [[
        SELECT /*+outline_leaf ordered use_nl(b c) opt_param('container_data' 'all') opt_param('optimizer_dynamic_sampling' 5)*/ 
               a.*,
               C.AVG_COL_LEN AVG_LEN,
               C.NUM_DISTINCT "NDV",
               CASE WHEN B.ROWCNT>=c.NUM_NULLS THEN round(c.NUM_NULLS*100/nullif(B.ROWCNT,0),2) END "Nulls(%)",
               CASE WHEN B.ROWCNT>=c.NUM_NULLS THEN round((B.ROWCNT-c.NUM_NULLS)/nullif(C.NUM_DISTINCT,0),2) END CARDINALITY,
               c.sample_size,
               c.LAST_ANALYZED,
               case when C.LOW_VALUE is not null then 
               substrb(decode(regexp_substr(DATA_TYPE,'[^\(]+')
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(C.LOW_VALUE))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(C.LOW_VALUE))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(C.LOW_VALUE))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(C.LOW_VALUE))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(C.LOW_VALUE))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(C.LOW_VALUE))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(C.LOW_VALUE))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(C.LOW_VALUE))
                  ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(C.LOW_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(C.LOW_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(C.LOW_VALUE, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(C.LOW_VALUE, 25, 2), 'XX')-60,0)
                  ,'DATE',lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 1, 2), 'XX')-100,2,0)||
                          lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                          lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(C.LOW_VALUE, 13, 2), 'XX')-1,2,0)
                  ,  C.LOW_VALUE),1,32) end LOW_VALUE,
                case when C.HIGH_VALUE is not null then 
                substrb(decode(regexp_substr(DATA_TYPE,'[^\(]+')
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(C.HIGH_VALUE))
                      ,'FLOAT'        ,to_char(utl_raw.cast_to_number(C.HIGH_VALUE))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(C.HIGH_VALUE))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(C.HIGH_VALUE))
                      ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(C.HIGH_VALUE))
                      ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(C.HIGH_VALUE))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(C.HIGH_VALUE))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(C.HIGH_VALUE))
                      ,'TIMESTAMP'   , lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')
                        ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 25, 2), 'XX')-60,0)
                        ,'DATE',lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 1, 2), 'XX')-100,2,0)||
                                lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(C.HIGH_VALUE, 13, 2), 'XX')-1,2,0)
                        ,  C.HIGH_VALUE),1,32) end HIGH_VALUE
        FROM (
            SELECT KQFTAOBJ obj#, c.KQFCOCNO COL#, c.kqfconam COLUMN_NAME,
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
                           111,'REF',
                           112,'CLOB',
                           113,'BLOB',
                           114,'BFILE',
                           115,'CFILE',
                           121,'CUSTOM OBJ',
                           122,'CUSTOM OBJ',
                           123,'CUSTOM OBJ',
                           178,'TIME',
                           179,'TIME WITH TIME ZONE',
                           180,'TIMESTAMP',
                           181,'TIMESTAMP WITH TIME ZONE',
                           231,'TIMESTAMP WITH LOCAL TIME ZONE',
                           182,'INTERVAL YEAR TO MONTH',
                           183,'INTERVAL DAY TO SECOND',
                           208,'UROWID',
                           'UNKNOWN') || '(' || to_char(c.kqfcosiz) || ')' DATA_TYPE,
                   c.kqfcosiz col_size, 
                   c.kqfcooff col_offset, lpad('0x' || TRIM(to_char(c.kqfcooff, 'XXXXXX')), 8) offset_hex,
                   decode(c.kqfcoidx, 0,'','Yes('||c.kqfcoidx||')') "Indexed?"
            FROM   sys.x$kqfta t, sys.x$kqfco c
            WHERE  c.kqfcotab = t.indx
            AND    c.inst_id = t.inst_id
            AND   (t.kqftanam=:object_name or t.kqftanam=(SELECT KQFDTEQU FROM sys.x$kqfdt WHERE KQFDTNAM=:object_name))) a,
            sys.tab_stats$ b,
            SYS.DBA_TAB_COL_STATISTICS c
        WHERE a.obj#=b.obj#(+)
        AND   c.owner(+)=:owner
        AND   c.table_name(+)=:object_name
        AND   c.column_name(+)=a.column_name
        ORDER  BY 1,2
    ]] or {[[
        SELECT /*INTERNAL_DBCLI_CMD topic="Column info"*/ 
             /*+opt_param('container_data' 'current') opt_param('optimizer_dynamic_sampling' 5)
               no_parallel opt_param('_optim_peek_user_binds','false') use_hash(a b c) use_hash(d) swap_join_inputs(c) */
               a.INTERNAL_COLUMN_ID NO#,
               a.COLUMN_NAME NAME,
               a.DATA_TYPE_OWNER || NVL2(a.DATA_TYPE_OWNER, '.', '') ||
               CASE WHEN a.DATA_TYPE IN('CHAR','VARCHAR','VARCHAR2','NCHAR','NVARCHAR','NVARCHAR2','RAW') --
                    THEN a.DATA_TYPE||'(' || DECODE(a.CHAR_USED, 'C', a.CHAR_LENGTH,a.DATA_LENGTH) || DECODE(a.CHAR_USED, 'C', ' CHAR') || ')' --
                    WHEN a.DATA_TYPE = 'NUMBER' --
                    THEN (CASE WHEN nvl(a.DATA_scale, a.DATA_PRECISION) IS NULL THEN a.DATA_TYPE
                              WHEN a.DATA_SCALE > 0 THEN DATA_TYPE||'(' || NVL(''||a.DATA_PRECISION, '38') || ',' || DATA_SCALE || ')'
                              WHEN a.DATA_PRECISION IS NULL AND a.DATA_SCALE=0 THEN 'INTEGER'
                              ELSE a.DATA_TYPE||'(' || a.DATA_PRECISION ||')' END)
                    $IF DBMS_DB_VERSION.VERSION > 22 $THEN
                    WHEN a.DATA_TYPE = 'VECTOR' THEN A.VECTOR_INFO
                    $END
                    ELSE a.DATA_TYPE 
               END
                 $IF DBMS_DB_VERSION.VERSION > 22 $THEN
                 ||rtrim(' '||trim('.' from decode(a.domain_owner,a.owner,'',a.domain_owner)||'.'||a.domain_name))
                 $END
                 $IF DBMS_DB_VERSION.VERSION>12 OR DBMS_DB_VERSION.VERSION=12 and DBMS_DB_VERSION.RELEASE>1 $THEN
                 ||CASE WHEN a.COLLATION != nvl(B.DEFAULT_COLLATION,a.COLLATION) THEN ' COLLATE '||a.COLLATION END
                 $END         
               as data_type,
               DECODE(a.NULLABLE, 'N', 'NOT NULL', '') NULLABLE,
               (CASE
                   WHEN a.default_length > 0 THEN
                        a.DATA_DEFAULT
                   ELSE
                        NULL
               END) "Default",
               NVL2(d.cname,''''||d.INTEGRITY_ALG||''''||decode(d.SALT,'NO',' NO SALT'),'') ENCRYPTION,
               e.redaction,
               a.HIDDEN_COLUMN "Hidden?",
               a.AVG_COL_LEN AVG_LEN,
               a.num_distinct "NDV",
               CASE WHEN b.num_rows>=a.num_nulls THEN round(a.num_nulls*100/nullif(b.num_rows,0),2) END "Nulls(%)",
               round(greatest(0,b.num_rows-a.num_nulls)/nullif(a.num_distinct,0),2) CARDINALITY,
               nullif(HISTOGRAM,'NONE') HISTOGRAM,
               a.NUM_BUCKETS buckets,
               case when a.low_value is not null then 
               substrb(decode(dtype
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(low_value))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(low_value))
                  ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(low_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(low_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(low_value, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(low_value, 25, 2), 'XX')-60,0)
                  ,'DATE',lpad(TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX')-100,2,0)||
                          lpad(TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX')-1,2,0)
                  ,  low_value),1,32) end low_value,
                case when a.high_value is not null then 
                substrb(decode(dtype
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(high_value))
                      ,'FLOAT'        ,to_char(utl_raw.cast_to_number(high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(high_value))
                      ,'TIMESTAMP'   , lpad(TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(high_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                        ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(high_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(high_value, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(high_value, 25, 2), 'XX')-60,0)
                        ,'DATE',lpad(TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX')-100,2,0)||
                                lpad(TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX')-1,2,0)
                        ,  high_value),1,32) end high_value,
            c.comments
        FROM      (select /*+no_merge*/ a.*,regexp_replace(data_type,'\(.+\)') dtype from all_tab_cols a where a.owner=:owner and a.table_name=:object_name) a
        LEFT JOIN (select /*+no_merge*/ * from all_tables a where '&object_type' like 'TABLE%' and a.owner=:owner and a.table_name=:object_name) b 
        ON        (a.table_name=b.table_name)
        LEFT JOIN (select /*+no_merge*/ column_name cname,comments from all_col_comments where owner=:owner and table_name=:object_name) c
        ON        (a.column_name=c.cname)
        LEFT JOIN (select /*+no_merge*/ column_name cname,SALT,INTEGRITY_ALG from all_encrypted_columns where '&object_type' like 'TABLE%' and owner=:owner and table_name=:object_name) d
        ON        (a.column_name=d.cname)
        LEFT JOIN (
        $IF $$VERSION > 1101 AND ($$SELECT_CATALOG_ROLE OR $$SYSDBA) $THEN
            select /*+no_merge*/ column_name cname,REPLACE(FUNCTION_TYPE,' REDACTION') REDACTION
            from  REDACTION_COLUMNS 
            join  REDACTION_POLICIES USING (object_owner,object_name)
            where object_owner='&owner' and object_name='&object_name' and '&object_type' like 'TABLE%' 
        $ELSE
            SELECT ''  cname,'' REDACTION FROM DUAL where 1=2
        $END
        ) e
        ON        (a.column_name=e.cname)
        ORDER BY NO#]],
    [[
        WITH /*topic="Index info" */ 
        I AS (SELECT /*+cardinality(1) outline_leaf push_pred(c) opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('container_data' 'current') opt_param('optimizer_dynamic_sampling' 5) */ 
                           I.*,nvl(c.LOCALITY,'GLOBAL') LOCALITY,
                           PARTITIONING_TYPE||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+no_merge*/* FROM all_part_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') PARTITIONED_BY,
                           nullif(SUBPARTITIONING_TYPE,'NONE')||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') SUBPART_BY
                    FROM   ALL_INDEXES I,ALL_PART_INDEXES C
                    WHERE  C.OWNER(+) = I.OWNER
                    AND    C.INDEX_NAME(+) = I.INDEX_NAME
                    AND    I.TABLE_OWNER = :owner
                    AND    I.TABLE_NAME = :table_name)
        SELECT /*+use_hash(e c) outline_leaf no_parallel opt_param('container_data' 'current') leading(i c e) opt_param('_sort_elimination_cost_ratio',5)*/
                DECODE(C.COLUMN_POSITION, 1, I.OWNER, '') OWNER,
                DECODE(C.COLUMN_POSITION, 1, I.INDEX_NAME, '') INDEX_NAME,
                DECODE(C.COLUMN_POSITION, 1, 
                       trim(',' from I.INDEX_TYPE||','||LOCALITY||','
                            ||DECODE(I.UNIQUENESS,'UNIQUE','UNIQUE,')
                            ||NVL2(PARTITIONED_BY,'PARTT['||PARTITIONED_BY||NULLIF(','||SUBPART_BY,',')||'],','')
                            ||nullif(decode(I.STATUS,'N/A',(SELECT MIN(STATUS) FROM All_Ind_Partitions p WHERE p.INDEX_OWNER = I.OWNER AND p.INDEX_NAME = I.INDEX_NAME),I.STATUS)||',','VALID,')
                        )) attrs,
                --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
                DECODE(C.COLUMN_POSITION, 1, i.BLEVEL) BLV,
                DECODE(C.COLUMN_POSITION, 1, round(100*i.num_rows*]]..blocks..'/nullif('..rows..[[*i.CLUSTERING_FACTOR,0),2)) "Blks/|CF(%)",
                DECODE(C.COLUMN_POSITION, 1, dbms_xplan.format_number(i.num_rows)) "Rows",
                DECODE(C.COLUMN_POSITION, 1, dbms_xplan.format_number(i.DISTINCT_KEYS)) NDV,
                DECODE(C.COLUMN_POSITION, 1, dbms_xplan.format_number(i.LEAF_BLOCKS)) "Blks",
                DECODE(C.COLUMN_POSITION, 1, AVG_LEAF_BLOCKS_PER_KEY) "Leaf|B/KEY",
                DECODE(C.COLUMN_POSITION, 1, AVG_DATA_BLOCKS_PER_KEY) "Data|B/KEY",
                DECODE(C.COLUMN_POSITION, 1, ceil(i.num_rows/greatest(i.DISTINCT_KEYS,1))) "Card",
                C.COLUMN_POSITION NO#,
                C.COLUMN_NAME,
                E.COLUMN_EXPRESSION COLUMN_EXPR,
                C.DESCEND DIR,
                DECODE(C.COLUMN_POSITION, 1, i.LAST_ANALYZED) LAST_ANALYZED
        FROM   I,  ALL_IND_COLUMNS C,  all_ind_expressions e
        WHERE  C.INDEX_OWNER = I.OWNER
        AND    C.INDEX_NAME = I.INDEX_NAME
        AND    C.INDEX_NAME = e.INDEX_NAME(+)
        AND    C.INDEX_OWNER = e.INDEX_OWNER(+)
        AND    C.column_position = e.column_position(+)
        AND    :owner = c.table_owner
        AND    :table_name =c.table_name
        AND    :owner = E.table_owner(+)
        AND    :table_name =e.table_name(+)
        ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD topic="Constraint info"*/ 
               --+no_parallel opt_param('_optim_peek_user_binds','false') opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'current')
               DECODE(R, 1, CONSTRAINT_NAME) CONSTRAINT_NAME,
               DECODE(R, 1, CONSTRAINT_TYPE) CTYPE,
               DECODE(R, 1, R_TABLE) R_TABLE,
               DECODE(R, 1, R_CONSTRAINT) R_CONSTRAINT,
               SEARCH_CONDITION C_CONDITION,
               DECODE(R, 1, status) status,
               --DECODE(R, 1, DEFERRABLE) DEFERRABLE,
               DECODE(R, 1, DEFERRED) DEFERRED,
               DECODE(R, 1, VALIDATED) VALIDATED,
               COLUMN_NAME
        FROM   (SELECT --+outline_leaf leading(a r c) use_nl(a r) use_hash(c) push_pred(r) push_pred(c) 
                       A.CONSTRAINT_NAME,
                       A.CONSTRAINT_TYPE,
                       R.TABLE_NAME R_TABLE,
                       A.R_CONSTRAINT_NAME R_CONSTRAINT,
                       a.status,
                       a.DEFERRABLE,
                       a.DEFERRED,
                       a.VALIDATED,
                       A.SEARCH_CONDITION,
                       c.COLUMN_NAME,
                       ROW_NUMBER() OVER(PARTITION BY A.CONSTRAINT_NAME ORDER BY C.COLUMN_NAME) R
                FROM   (select * from all_constraints where owner=:owner and table_name=:object_name) a,
                       all_constraints R, 
                       ALL_CONS_COLUMNS C
                WHERE  A.R_OWNER = R.OWNER(+)
                AND    A.R_CONSTRAINT_NAME = R.CONSTRAINT_NAME(+)
                AND    A.OWNER = C.OWNER(+)
                AND    A.CONSTRAINT_NAME = C.CONSTRAINT_NAME(+)
                AND    :owner = c.owner(+)
                AND    :object_name =c.table_name(+)
                AND    (A.constraint_type != 'C' OR A.constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'))
    ]],
    [[/*grid={topic='ALL_TABLES', pivot=1}*/ 
    WITH r1 AS (SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'current')*/ * 
                FROM all_part_key_columns WHERE owner=:owner and NAME = :object_name),
           r2 AS (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=:owner and NAME = :object_name)
    SELECT PARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                 FROM   r1
                                 START  WITH column_position = 1
                                 CONNECT BY PRIOR column_position = column_position - 1)
                              PARTITIONED_BY,
            PARTITION_COUNT PARTS,
            SUBPARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                     FROM   R2
                                     START  WITH column_position = 1
                                     CONNECT BY PRIOR column_position = column_position - 1) SUBPART_BY,
            def_subpartition_count subs,
            DEF_TABLESPACE_NAME,
            DEF_PCT_FREE,
            DEF_INI_TRANS,
            DEF_LOGGING,
            DEF_COMPRESSION
    FROM   all_part_tables
    WHERE  table_name = :object_name
    AND    owner = :owner]],
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
      FROM   (SELECT * FROM ALL_TABLES   WHERE OWNER = :owner AND TABLE_NAME = :object_name) T,
             (SELECT * FROM ALL_OBJECTS  WHERE OWNER = :owner AND OBJECT_NAME = :object_name) O
      WHERE  T.TABLE_NAME=O.OBJECT_NAME]]
}