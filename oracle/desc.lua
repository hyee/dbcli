local env=env
local db,cfg=env.oracle,env.set
local desc={}
local search_sql=[[
   WITH A AS (SELECT /*+materialize*/ * FROM(
           SELECT owner, object_name, SUBOBJECT_NAME, object_type,decode(object_type,'SYNONYM',3,1) seq
                FROM   All_objects A
                WHERE  object_type NOT LIKE '% BODY'
                AND    upper('.' || A.owner || '.' || A.object_name || '.' || A.SUBOBJECT_NAME || '.') LIKE upper(:1)
                UNION ALL
                SELECT owner, object_name, procedure_name, 'PROCEDURE',2
                FROM   All_procedures A
                WHERE  upper('.' || A.owner || '.' || A.object_name || '.' || A.procedure_name || '.') LIKE upper(:1)
                ORDER  BY SEQ,SUBOBJECT_NAME NULLS FIRST
       ) WHERE ROWNUM<2)
       SELECT /*+ordered */ /*INTERNAL_DBCLI_CMD*/
             NVL(B.TABLE_OWNER, A.OWNER) OWNER,
             NVL(B.TABLE_NAME, A.OBJECT_NAME) OBJECT_NAME,
             A.SUBOBJECT_NAME,
             CASE
                 WHEN object_type = 'SYNONYM' THEN
                  (SELECT MAX(object_type)
                   FROM   all_objects c
                   WHERE  b.TABLE_OWNER = c.owner
                   AND    c.object_name = b.table_name)        
                 ELSE
                  object_type
             END object_type,
             a.seq
        FROM   A,
               ALL_SYNONYMS B
        WHERE  A.OWNER = B.owner(+)
        AND    A.OBJECT_NAME = B.SYNONYM_NAME(+)
    ]]

local desc_sql={
    PROCEDURE=[[
        SELECT /*INTERNAL_DBCLI_CMD*/ NVL2(overload, overload || '.', '') || position NO#,
               decode(position,0,'(RESULT)',Nvl(ARGUMENT_NAME, DATA_TYPE)) Argument,
               (CASE
                   WHEN pls_type IS NOT NULL THEN
                    pls_type
                   WHEN type_subname IS NOT NULL THEN
                    type_name || '.' || type_subname
                   ELSE
                    data_type
               END) DATA_TYPE,in_out,defaulted,default_value,character_set_name charset
        FROM   ALL_ARGUMENTS
        WHERE  owner=:1 and nvl(package_name,' ')=nvl(:2,' ') and object_name=:3
        AND    data_level=0
        ORDER  BY overload, POSITION]],
    
    PACKAGE=[[
    SELECT NO#,ELEMENT,NVL2(RETURNS,'FUNCTION','PROCEDURE') Type,ARGUMENTS,RETURNS,
           AGGREGATE,PIPELINED,PARALLEL,INTERFACE,DETERMINISTIC,AUTHID
    FROM (    
        SELECT /*INTERNAL_DBCLI_CMD*/ SUBPROGRAM_ID NO#,
               PROCEDURE_NAME||NVL2(OVERLOAD,' (#'||OVERLOAD||')','') ELEMENT,
               (SELECT (CASE
                           WHEN pls_type IS NOT NULL THEN
                            pls_type
                           WHEN type_subname IS NOT NULL THEN
                            type_name || '.' || type_subname
                           ELSE
                            data_type
                       END)
                FROM   All_Arguments b
                WHERE  a.SUBPROGRAM_ID = b.SUBPROGRAM_ID
                AND    NVL(a.OVERLOAD, -1) = NVL(b.OVERLOAD, -1)
                AND    position = 0
                AND    a.object_id = b.object_id) RETURNS,
               (SELECT COUNT(1)
                FROM   All_Arguments b
                WHERE  a.SUBPROGRAM_ID = b.SUBPROGRAM_ID
                AND    NVL(a.OVERLOAD, -1) = NVL(b.OVERLOAD, -1)
                AND    position > 0
                AND    a.object_id = b.object_id) ARGUMENTS, 
               AGGREGATE,
               PIPELINED,
               PARALLEL,
               INTERFACE,
               DETERMINISTIC,
               AUTHID
        FROM   all_PROCEDURES a
        WHERE  owner=:1 and object_name =:2
        AND    SUBPROGRAM_ID > 0
    ) ORDER  BY NO#]],

    INDEX={[[select /*INTERNAL_DBCLI_CMD*/ column_position NO#,column_name,column_length,char_length,descend from all_ind_columns
            WHERE  index_owner=:1 and index_name=:2
            ORDER BY NO#]],
            [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/* FROM ALL_INDEXES WHERE owner=:1 and index_name=:2]]},
    TYPE=[[
        SELECT /*INTERNAL_DBCLI_CMD*/ attr_no NO#,
               attr_name,
               attr_type_owner||NVL2(attr_type_owner,'.','')||
               attr_TYPE_OWNER || NVL2(attr_TYPE_OWNER, '.', '') ||
               CASE WHEN attr_type_name IN('CHAR',
                                      'VARCHAR',
                                      'VARCHAR2',
                                      'NCHAR',
                                      'NVARCHAR',
                                      'NVARCHAR2',
                                      'RAW') --
               THEN attr_type_name||'(' || LENGTH || ')' --
               WHEN attr_type_name = 'NUMBER' --
               THEN (CASE WHEN nvl(scale, PRECISION) IS NULL THEN attr_type_name
                          WHEN scale > 0 THEN attr_type_name||'(' || NVL(''||PRECISION, '38') || ',' || SCALE || ')'
                          WHEN PRECISION IS NULL AND scale=0 THEN 'INTEGER'
                          ELSE attr_type_name||'(' || PRECISION  || ')' END) ELSE attr_type_name END
               data_type,
               attr_type_name || CASE
                   WHEN attr_type_name IN
                        ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') --
                    THEN
                    '(' || LENGTH || ')'
                   WHEN attr_type_name = 'NUMBER' THEN
                    (CASE
                        WHEN scale IS NULL AND PRECISION IS NULL THEN
                         ''
                        WHEN scale <> 0 THEN
                         '(' || NVL(PRECISION, 38) || ',' || SCALE || ')'
                        ELSE
                         '(' || NVL(PRECISION, 38) || ')'
                    END)
                   ELSE
                    ''
               END data_type,
               Inherited
        FROM   all_type_attrs
        WHERE  owner=:1  and type_name=:2
        ORDER BY NO#]],
    TABLE={[[
        SELECT /*INTERNAL_DBCLI_CMD*/ COLUMN_ID NO#,
               COLUMN_NAME NAME,
               DATA_TYPE_OWNER || NVL2(DATA_TYPE_OWNER, '.', '') ||
               CASE WHEN DATA_TYPE IN('CHAR',
                                      'VARCHAR',
                                      'VARCHAR2',
                                      'NCHAR',
                                      'NVARCHAR',
                                      'NVARCHAR2',
                                      'RAW') --
               THEN DATA_TYPE||'(' || DATA_LENGTH || DECODE(CHAR_USED, 'C', ' CHAR') || ')' --
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
               AVG_COL_LEN AVG_LEN,
               NUM_DISTINCT num_vals,
               num_nulls,
               SAMPLE_SIZE,   
               HISTOGRAM,
               decode(data_type
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(low_value))
                  ,'DATE',RTRIM(LTRIM(TO_CHAR(100 * (TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX') - 100) +
                                         (TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX') - 100),
                                         '0000')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX'), '00')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX'), '00')) || ' ' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX') - 1, '00')))
                  ,  low_value) low_v,
                decode(data_type
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(high_value))
                      ,'DATE', RTRIM(LTRIM(TO_CHAR(100 * (TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX') - 100) +
                                         (TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX') - 100),
                                         '0000')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX'), '00')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX'), '00')) || ' ' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX') - 1, '00')))
                      ,  high_value) hi_v
        FROM   all_tab_cols
        WHERE  upper(owner)=:1  and table_name=:2
        ORDER BY NO#]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*+ RULE */
             DECODE(C.COLUMN_POSITION, 1, I.INDEX_NAME, '') INDEX_NAME,
             DECODE(C.COLUMN_POSITION, 1, I.INDEX_TYPE, '') INDEX_TYPE,
             DECODE(C.COLUMN_POSITION, 1, DECODE(I.UNIQUENESS,'UNIQUE','YES','NO'), '') "UNIQUE",
             DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",             
             DECODE(C.COLUMN_POSITION, 1, decode(I.STATUS,'N/A',(SELECT MIN(STATUS) FROM All_Ind_Partitions p WHERE p.INDEX_OWNER = I.OWNER AND p.INDEX_NAME = I.INDEX_NAME),I.STATUS), '') STATUS,
             C.COLUMN_POSITION NO#,
             C.COLUMN_NAME,
             C.DESCEND
        FROM   ALL_IND_COLUMNS C, ALL_INDEXES I
        WHERE  C.INDEX_OWNER = I.OWNER
        AND    C.INDEX_NAME = I.INDEX_NAME
        AND    I.TABLE_OWNER = :1
        AND    I.TABLE_NAME = :2        
        ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION]],
    [[
        SELECT DECODE(R, 1, CONSTRAINT_NAME) CONSTRAINT_NAME,
               DECODE(R, 1, CONSTRAINT_TYPE) CTYPE,
               DECODE(R, 1, R_TABLE) R_TABLE,
               DECODE(R, 1, R_CONSTRAINT) R_CONSTRAINT,
               SEARCH_CONDITION C_CONDITION,
               DECODE(R, 1, status) status,
               --DECODE(R, 1, DEFERRABLE) DEFERRABLE,
               DECODE(R, 1, DEFERRED) DEFERRED,
               DECODE(R, 1, VALIDATED) VALIDATED,
               COLUMN_NAME
        FROM   (SELECT A.CONSTRAINT_NAME,
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
                FROM   all_constraints a, all_constraints R, ALL_CONS_COLUMNS C
                WHERE  A.owner = :1
                AND    A.TABLE_NAME = :2
                AND    A.R_OWNER = R.OWNER(+)
                AND    A.R_CONSTRAINT_NAME = R.CONSTRAINT_NAME(+)
                AND    A.OWNER = C.OWNER(+)
                AND    A.CONSTRAINT_NAME = C.CONSTRAINT_NAME(+)
                AND    (A.constraint_type != 'C' OR A.constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'))
    ]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/*
        FROM   all_TABLES T
        WHERE  T.OWNER = :1 AND T.TABLE_NAME = :2]]},
    ['TABLE PARTITION']={[[
        SELECT /*INTERNAL_DBCLI_CMD*/ COLUMN_ID NO#,
               COLUMN_NAME NAME,
               DATA_TYPE_OWNER || NVL2(DATA_TYPE_OWNER, '.', '') ||
               CASE WHEN DATA_TYPE IN('CHAR',
                                      'VARCHAR',
                                      'VARCHAR2',
                                      'NCHAR',
                                      'NVARCHAR',
                                      'NVARCHAR2',
                                      'RAW') --
               THEN DATA_TYPE||'(' || DATA_LENGTH || DECODE(CHAR_USED, 'C', ' CHAR') || ')' --
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
               b.AVG_COL_LEN AVG_LEN,
               b.NUM_DISTINCT num_vals,
               b.num_nulls,
               b.SAMPLE_SIZE,   
               b.HISTOGRAM,
               decode(data_type
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(b.low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(b.low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(b.low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(b.low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(b.low_value))
                  ,'DATE',RTRIM(LTRIM(TO_CHAR(100 * (TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX') - 100) +
                                         (TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX') - 100),
                                         '0000')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX'), '00')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX'), '00')) || ' ' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX') - 1, '00')))
                  ,  low_value) low_v,
                decode(data_type
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(high_value))
                      ,'DATE', RTRIM(LTRIM(TO_CHAR(100 * (TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX') - 100) +
                                         (TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX') - 100),
                                         '0000')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX'), '00')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX'), '00')) || ' ' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX') - 1, '00')))
                      ,  high_value) hi_v
        FROM   all_tab_cols JOIN All_Part_Col_Statistics b USING(owner,table_name,COLUMN_NAME)
        WHERE  upper(owner)=:1 and table_name=:2 AND partition_name=:3
        ORDER BY NO#]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*+ RULE */
             DECODE(C.COLUMN_POSITION, 1, I.INDEX_TYPE, '') TYPE,
             DECODE(C.COLUMN_POSITION, 1, DECODE(C.UNIQUENESS,'UNIQUE','YES','NO'), '') UNIQUE,
             DECODE(C.COLUMN_POSITION, 1, C.INDEX_NAME, '') INDEX_NAME,
             DECODE(C.COLUMN_POSITION, 1, C.STATUS, '') STATUS,
             C.COLUMN_POSITION NO#,
             C.COLUMN_NAME,
             C.DESCEND
        FROM   ALL_IND_COLUMNS C, ALL_INDEXES I
        WHERE  C.INDEX_OWNER = I.OWNER
        AND    C.INDEX_NAME = I.INDEX_NAME
        AND    I.TABLE_OWNER = :1
        AND    I.TABLE_NAME = :2        
        ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/*
        FROM   all_tab_partitions T
        WHERE  T.TABLE_OWNER = :1 AND T.TABLE_NAME = :2 AND partition_name=:3]]}           
}

desc_sql.VIEW=desc_sql.TABLE[1]
desc_sql['MATERIALIZED VIEW']=desc_sql.TABLE[1]
desc_sql['INDEX PARTITION']=desc_sql.INDEX
desc_sql.FUNCTION=desc_sql.PROCEDURE

function desc.desc(name,option)
    if not name then return end
    local rs
    local obj=db:check_obj(name)
    if obj then
        rs={obj.owner,obj.object_name,obj.object_subname or "",
           obj.object_subname and obj.object_type=="PACKAGE" and "PROCEDURE"
           or obj.object_type,2}
    else
        rs=db:get_value(search_sql,{'%.'..name:upper()..'.%'})
    end
    if not rs then return print("Cannot find this object!") end

    local sqls=desc_sql[rs[4]]
    if not sqls then return print("Cannot describe "..rs[4]..'!') end
    if type(sqls)~="table" then sqls={sqls} end
    if (rs[4]=="PROCEDURE" or rs[4]=="FUNCTION") and rs[5]~=2 then
        rs[2],rs[3]=rs[3],rs[2]
    end
    
    local dels=string.rep("=",100)
    local feed=cfg.get("feed")
    cfg.set("feed","off",true)
    print(("%s : %s%s%s\n"..dels):format(rs[4],rs[1],rs[2]=="" and "" or "."..rs[2],rs[3]=="" and "" or "."..rs[3]))
    for i,sql in ipairs(sqls) do
        if sql:find("/*PIVOT*/",1,true) then cfg.set("PIVOT",1) end
        db:query(sql,rs)
        if i<#sqls then print(dels) end
    end
    
    if option and option:upper()=='ALL' then
        if rs[2]==""  then rs[2],rs[3]=rs[3],rs[2] end
        print(dels)
        cfg.set("PIVOT",1)        
        db:query([[SELECT * FROM ALL_OBJECTS WHERE OWNER=:1 AND OBJECT_NAME=:2 AND nvl(SUBOBJECT_NAME,' ')=nvl(:3,' ')]],rs)
    end

    cfg.temp("feed",feed,true)
end

env.set_command(nil,{"describe","desc"},'Describe datbase object. Usage: desc [owner.]<object>[.partition] | [owner.]<pkg|typ>[.<function|procedure>]',desc.desc,false,3)
return desc
