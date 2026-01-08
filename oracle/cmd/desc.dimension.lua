
return {
    [[SELECT /*topic="Dimemsion Info"*/ /*PIVOT*/ 
             o.*,d.invalid,d.compile_state,d.revision 
      FROM   dba_objects o,dba_dimensions d
      WHERE  o.owner=d.owner
      AND    o.object_name=d.DIMENSION_NAME
      AND    o.object_type='DIMENSION'
      AND    o.owner=:owner
      AND    o.object_name=:object_name]],
    [[
    WITH attrs1 AS
     (SELECT /*+outline_leaf*/
               l.level_name,
               a.attribute_name,
               detailobj_name src_table,
               (SELECT listagg(k.column_name || DECODE(skip_when_null, 'Y', ' SKIP WHEN NULL'), ',' || CHR(10)) WITHIN GROUP(ORDER BY key_position)
                FROM   dba_dim_level_key K
                WHERE  owner = :owner
                AND    DIMENSION_NAME = :object_name
                AND    k.level_name = l.level_name) src_cols,
               determine_cols
      FROM   (SELECT *
              FROM   dba_dim_levels
              WHERE  owner = :owner
              AND    DIMENSION_NAME = :object_name) l
      JOIN   (SELECT level_name,
                    attribute_name,
                    listagg(column_name || DECODE(inferred, 'Y', ' INFERRED'), ',' || CHR(10)) WITHIN GROUP(ORDER BY column_name) determine_cols
             FROM   dba_dim_attributes
             WHERE  owner = :owner
             AND    DIMENSION_NAME = :object_name
             GROUP  BY level_name, attribute_name) a
      ON     (a.level_name = l.level_name)),
    attrs AS(
      SELECT /*+outline_leaf materialize*/
             a.*,
             GREATEST(
                nvl(regexp_count(src_cols,chr(10)),0),
                nvl(regexp_count(determine_cols,chr(10)),0)
             )+1 lines_
      FROM   attrs1 a
    ),
    hier AS
     (SELECT /*+outline_leaf materialize*/ *
      FROM   (SELECT c.*, MAX(position) OVER (PARTITION BY hierarchy_name) max_pos
              FROM   dba_dim_child_of c
              WHERE  owner = :owner
              AND    dimension_name = :object_name) c
      LEFT   JOIN (
              SELECT hierarchy_name,dim_key_id join_key_id,
                     MAX(child_join_owner||'.'||child_join_table)
                     ||'('
                     ||listagg(child_join_column, ',') WITHIN GROUP(ORDER BY key_position)
                     ||')' join_table
              FROM   dba_dim_join_key
              WHERE  owner = :owner
              AND    dimension_name = :object_name
              GROUP BY hierarchy_name,dim_key_id) k
      USING  (hierarchy_name, join_key_id))
    SELECT /*topic="Hierarchy Info" */ 
           DECODE(position, max_pos, hierarchy_name) hierarchy_name, 
           LPAD(' ', (max_pos - position) * 2) 
               || level_name
               || replace(rpad(' ',lines_,'x'),'x',chr(10)||LPAD(' ', (max_pos - position +1) * 2)||'|')
               || decode(position,0,'$UDL$ ')
           AS "LEVEL",
           position "LV#",
           attribute_name,src_table,src_cols,determine_cols,join_table
    FROM   (SELECT hierarchy_name, position, max_pos, 
                   attrs.*,join_table
            FROM   hier
            JOIN   attrs
            ON     (hier.parent_level_name = attrs.level_name)
            UNION ALL
            SELECT hierarchy_name, position-1, max_pos, 
                   attrs.*,join_table
            FROM   hier
            JOIN   attrs
            ON     (hier.child_level_name = attrs.level_name)
            WHERE  hier.position = 1) a
    ORDER  BY a.hierarchy_name, a.position DESC]]}