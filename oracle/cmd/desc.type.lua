local result=db:dba_query(db.internal_call,
                          [[select ELEM_TYPE_OWNER,ELEM_TYPE_NAME,COLL_TYPE,UPPER_BOUND,ELEM_TYPE_MOD
                           from ALL_COLL_TYPES 
                           WHERE owner = :owner AND type_name = :object_name]],
                          obj)
result=db.resultset:rows(result,-1)
if #result>1 then
    result=result[2]
    if result[1]~='' then
        obj.owner,obj.object_name=result[1],result[2]
    end
    obj.desc=' ['..(result[3]=='TABLE' and 'TABLE' or ('VARRAY('..result[4]..')'))..' OF '..
               (result[5]~='' and (result[5]..' ') or '')..
               (result[1]~='' and (result[1]..'.') or '')..result[2]..']'
else
    result=db:dba_query(db.internal_call,[[select SUPERTYPE_NAME from ALL_TYPES WHERE SUPERTYPE_NAME IS NOT NULL AND owner = :owner AND type_name = :object_name]],obj)
    result=db.resultset:rows(result,-1)
    if #result>1 then
        result=result[2]
        obj.desc=' [INHERITED FROM '..obj.owner..'.'..result[1]..']'
    end
end

return {[[
    SELECT /*INTERNAL_DBCLI_CMD*//*+opt_param('optimizer_dynamic_sampling' 5) */
           TYPE_NAME,
           attr_no NO#,
           CASE
              WHEN attr_no = 1 THEN
               (SELECT a.type_name||'['||DECODE(COLL_TYPE, 'TABLE', 'TABLE', 'VARRAY(' || UPPER_BOUND || ')') ||']'|| '  '
                FROM   ALL_COLL_TYPES
                WHERE  owner = :owner
                AND    type_name = a.type_name)
           END || attr_name attr_name,
           nullif(attr_type_owner||'.', '.') || --
           CASE
               WHEN attr_type_name IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                attr_type_name || '(' || LENGTH || ')' --
               WHEN attr_type_name = 'NUMBER' THEN
                (CASE
                    WHEN nvl(scale, PRECISION) IS NULL THEN
                     attr_type_name
                    WHEN scale > 0 THEN
                     attr_type_name || '(' || NVL('' || PRECISION, '38') || ',' || SCALE || ')'
                    WHEN PRECISION IS NULL AND scale = 0 THEN
                     'INTEGER'
                    ELSE
                     attr_type_name || '(' || PRECISION || ')'
                END)
               ELSE
                trim(attr_type_name)
           END data_type, 
           ATTR_TYPE_MOD ATTR_MOD, 
           Inherited inherit, 
           CHARACTER_SET_NAME "CHARSET"
    FROM   (SELECT A.*
            FROM   all_type_attrs a
            WHERE  owner = :owner AND type_name = :object_name) a
    ORDER  BY TYPE_NAME,NO#]],
    obj.redirect('package')}