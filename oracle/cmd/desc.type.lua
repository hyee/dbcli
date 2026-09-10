local result = db:dba_query(db.internal_call,
                            [[SELECT elem_type_owner, elem_type_name, coll_type, upper_bound, elem_type_mod
                              FROM   all_coll_types
                              WHERE  owner = :owner
                              AND    type_name = :object_name]],
                            obj)
result = db.resultset:rows(result, -1)
if #result > 1 then
    result = result[2]
    if result[1] ~= '' then
        obj.owner, obj.object_name = result[1], result[2]
    end
    obj.desc = ' ['..(result[3] == 'TABLE' and 'TABLE' or ('VARRAY('..result[4]..')'))..' OF '..
                   (result[5] ~= '' and (result[5]..' ') or '')..
                   (result[1] ~= '' and (result[1]..'.') or '')..result[2]..']'
else
    result = db:dba_query(db.internal_call,
                          [[SELECT supertype_name
                            FROM   all_types
                            WHERE  supertype_name IS NOT NULL
                            AND    owner = :owner
                            AND    type_name = :object_name]], obj)
    result = db.resultset:rows(result, -1)
    if #result > 1 then
        result = result[2]
        obj.desc = ' [INHERITED FROM '..obj.owner..'.'..result[1]..']'
    end
end

return {[[
    SELECT /*INTERNAL_DBCLI_CMD*//*+opt_param('optimizer_dynamic_sampling' 5) */
           type_name,
           attr_no no#,
           CASE
               WHEN attr_no = 1 THEN
                (SELECT a.type_name||'['||decode(coll_type, 'TABLE', 'TABLE', 'VARRAY(' || upper_bound || ')') ||']'|| '  '
                 FROM   all_coll_types
                 WHERE  owner = :owner
                 AND    type_name = a.type_name)
           END || attr_name attr_name,
           nullif(attr_type_owner||'.', '.') || --
           CASE
               WHEN attr_type_name IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                attr_type_name || '(' || length || ')' --
               WHEN attr_type_name = 'NUMBER' THEN
                (CASE
                    WHEN nvl(scale, precision) IS NULL THEN
                     attr_type_name
                    WHEN scale > 0 THEN
                     attr_type_name || '(' || nvl('' || precision, '38') || ',' || scale || ')'
                    WHEN precision IS NULL AND scale = 0 THEN
                     'INTEGER'
                    ELSE
                     attr_type_name || '(' || precision || ')'
                END)
               ELSE
                trim(attr_type_name)
           END data_type,
           attr_type_mod attr_mod,
           inherited inherit,
           character_set_name "CHARSET"
    FROM   (SELECT a.*
            FROM   all_type_attrs a
            WHERE  owner = :owner
            AND    type_name = :object_name) a
    ORDER  BY type_name, no#]],
    obj.redirect('package'),
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*NO_HIDE*/ /*+OUTLINE_LEAF*/ *
      FROM   (SELECT * FROM all_types   WHERE owner = :owner AND type_name = :object_name) t,
             (SELECT * FROM all_objects WHERE owner = :owner AND object_name = :object_name and object_type='TYPE') o
      WHERE  t.type_name = o.object_name ]]
}
