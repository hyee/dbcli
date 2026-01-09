local ad=[[
    (SELECT  /*+no_merge monitor
               opt_param('optimizer_dynamic_sampling' 5) 
               opt_param('optimizer_adaptive_plans' 'false') 
               opt_param('_optimizer_cartesian_enabled' 'false')
               opt_param('container_data' 'current')
               opt_param('_optimizer_cbqt_or_expansion' 'off')
               opt_param('_optimizer_reduce_groupby_key' 'false') 
               opt_param('_optimizer_group_by_placement' 'false') 
               opt_param('_optimizer_aggr_groupby_elim' 'false') 
               outline_leaf*/
             lv.level_name,
             d.level_type,
             a.attribute_name,
             lv.role,
             nullif(b.owner || '.', 'SH' || '.') || b.table_name || '.' || a.column_name source_column,
             k.is_alternate alt,
             lv.is_minimal_dtm min_dtm,
             d.skip_when_null skip_null,
             aggs.level_order,
             c.caption attr_caption,
             c.descr attr_Desc,
             decode(lv.role, 'KEY', regexp_substr(to_char(substr(d.member_name_expr,1,1000)),'[^'||chr(10)||']*')) member_name,
             decode(lv.role, 'KEY', regexp_substr(to_char(substr(d.member_caption_expr,1,1000)),'[^'||chr(10)||']*')) member_caption,
             decode(lv.role, 'KEY', regexp_substr(to_char(substr(d.member_description_expr,1,1000)),'[^'||chr(10)||']*')) member_desc,
             row_number() OVER(PARTITION BY lv.level_name ORDER BY k.key_order_num,a.column_name) seq,
             d.order_num level_seq
      FROM   (SELECT *
              FROM   all_attribute_dim_tables tb
              WHERE  (owner,dimension_name,origin_con_id) = (ad.owner,ad.dimension_name,:origin_con_id)) b
      JOIN   (SELECT attr.*
             FROM   all_attribute_dim_attrs attr
             WHERE  (owner,dimension_name,origin_con_id) = (ad.owner,ad.dimension_name,:origin_con_id)) a
      ON     (a.table_alias = b.table_alias)
      JOIN  (SELECT attr.*
             FROM   all_attribute_dim_level_attrs attr
             WHERE  (owner,dimension_name) = (ad.owner,ad.dimension_name)
             AND    (attr.origin_con_id = :origin_con_id OR origin_con_id IS NULL)) lv
      ON     (a.attribute_name = lv.attribute_name)
      JOIN   (SELECT *
              FROM   all_attribute_dim_levels
              WHERE  (owner,dimension_name,origin_con_id) = (ad.owner,ad.dimension_name,:origin_con_id)) d
      ON     (lv.level_name = d.level_name)
      LEFT JOIN  (
             SELECT *
             FROM   all_attribute_dim_keys attr
             WHERE  (owner,dimension_name,origin_con_id) = (ad.owner,ad.dimension_name,:origin_con_id)) K
      ON     (lv.attribute_name = k.attribute_name and lv.level_name=k.level_name) 
      LEFT   JOIN (
             SELECT level_name,
                    listagg(agg_func || ' ' || attribute_name || NULLIF(' ' || criteria, ' ASC') || NULLIF(' NULLS ' || nulls_position, ' NULLS ' || DECODE(criteria, 'ASC', 'LAST', 'FIRST')),
                            ',') WITHIN GROUP(ORDER BY order_num) level_order
             FROM   all_attribute_dim_order_attrs
             WHERE  (owner,dimension_name,origin_con_id) = (ad.owner,ad.dimension_name,:origin_con_id)
             GROUP  BY level_name) aggs
      ON     (lv.level_name = aggs.level_name)
      LEFT   JOIN (
             SELECT attribute_name,
                    MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) caption,
                    MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) descr
             FROM   all_attribute_dim_attr_class j
             WHERE  (owner,dimension_name,origin_con_id) = (ad.owner,ad.dimension_name,:origin_con_id)
             GROUP  BY attribute_name) c
      ON     (a.attribute_name = c.attribute_name))]]
local ah=([[(
    SELECT lpad(' ', 2 * (max_lv - lv)) 
           || decode(seq, 1, level_name, '  |')
           || CASE WHEN lv=0 AND seq=max(seq) over(partition by level_name) THEN '$UDL$' END level_name,
           ahk.column_name,
           ahk.role,
           CASE
               WHEN ahc.data_type IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                ahc.data_type || '(' || ahc.data_length || decode(ahc.char_used, 'C', ' CHAR') || ')' --
               WHEN ahc.data_type = 'NUMBER' THEN
                CASE
                    WHEN nvl(ahc.data_scale, ahc.data_precision) IS NULL THEN
                     ahc.data_type
                    WHEN data_scale > 0 THEN
                     ahc.data_type || '(' || nvl('' || ahc.data_precision, '38') || ',' || ahc.data_scale || ')'
                    WHEN ahc.data_precision IS NULL AND ahc.data_scale = 0 THEN
                     'INTEGER'
                    ELSE
                     ahc.data_type || '(' || ahc.data_precision || ')'
                END
               ELSE
                ahc.data_type
           END data_type,
           ahk.source_column,
           ahk.alt,
           ahk.min_dtm,
           ahk.skip_null,
           ahk.level_order,
           ahk.attr_caption,
           ahk.attr_desc,
           ahk.member_name,
           ahk.member_caption,
           ahk.member_desc,
           row_number() over(ORDER BY grp, lv DESC, seq) seq
    FROM   (SELECT /*+OUTLINE_LEAF*/
                   1 grp,
                   max_lv - ahk.order_num lv,
                   MAX(max_lv - ahk.order_num) over (PARTITION BY attribute_name) min_lv,
                   max_lv,
                   ahk.level_name,
                   adt.attribute_name column_name,
                   adt.seq,
                   adt.source_column,
                   adt.role,
                   adt.alt,
                   adt.min_dtm,
                   adt.skip_null,
                   adt.level_order,
                   adt.attr_caption,
                   adt.attr_desc,
                   adt.member_name,
                   adt.member_caption,
                   adt.member_desc
            FROM (SELECT ah.hier_name,ah.dimension_owner owner,ah.dimension_name from dual) ad 
            JOIN (SELECT ahk.*, MAX(order_num) over () max_lv
                  FROM   all_hier_levels ahk
                  WHERE  (owner,hier_name,origin_con_id) = (ah.owner,ah.hier_name,:origin_con_id)) ahk
            ON   (ahk.hier_name=ad.hier_name)
            CROSS APPLY(
                SELECT * 
                FROM @ad@ adt
                WHERE  adt.level_name = ahk.level_name) adt
            UNION ALL
            SELECT DISTINCT
                   2 grp,
                   0 lv,
                   0 min_lv,
                   0 max_lv,
                   'PUBLIC',
                   hier_attr_name,
                   order_num + 1 seq,
                   to_char(expression) source_column,
                   'HIER',
                   NULL alt,
                   NULL min_dtm,
                   NULL skip_null,
                   NULL,
                   caption,
                   descr,
                   NULL,
                   NULL,
                   NULL
            FROM   (SELECT /*+OUTLINE_LEAF*/
                           g.*, i.caption, i.descr, MAX(order_num) over () max_lv
                    FROM   (SELECT * FROM all_hier_hier_attributes WHERE (owner,hier_name,origin_con_id) = (ah.owner,ah.hier_name,:origin_con_id)) g,
                           (SELECT hier_attr_name,
                                   MAX(DECODE(classification,
                                              'CAPTION',
                                              regexp_substr(to_char(substr(VALUE, 1, 1000)), '[^' || chr(10) || ']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) caption,
                                   MAX(DECODE(classification,
                                              'DESCRIPTION',
                                              regexp_substr(to_char(substr(VALUE, 1, 1000)), '[^' || chr(10) || ']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) descr
                            FROM   all_hier_hier_attr_class
                            WHERE  (owner,hier_name,origin_con_id) = (ah.owner,ah.hier_name,:origin_con_id)
                            GROUP  BY hier_attr_name) i
                    WHERE  g.hier_attr_name = i.hier_attr_name(+)) ahk
            ) ahk
    JOIN   (SELECT * FROM all_hier_columns WHERE (owner,hier_name,origin_con_id) = (ah.owner,ah.hier_name,:origin_con_id)) ahc
    ON     (ahk.column_name = ahc.column_name)
    WHERE  lv = min_lv
    ORDER  BY seq)]]):gsub('@ad@',ad)

if obj.object_type=='ANALYTIC VIEW' then
    env.var.define_column('HIER_NAME','BREAK','SKIP','-')
    env.set.set("colsep",'|')
    env.set.set("colwrap",64)
elseif obj.object_type=='ATTRIBUTE DIMENSION' then
    env.var.define_column('LEVEL_NAME','BREAK','SKIP','-')
end
env.var.define_column('SEQ,LEVEL_SEQ,ORDER_NUM,KEY_ORDER_NUM','NOPRINT')

local stmt="select /*+opt_param('container_data' 'current')*/ max(origin_con_id) from " ..
      (obj.object_type=='ATTRIBUTE DIMENSION' and 'all_attribute_dimensions where (owner,dimension_name)' or
       obj.object_type=='HIERARCHY' and 'all_hierarchies where (owner,hier_name)' or
       obj.object_type=='ANALYTIC VIEW' and 'all_analytic_views where (owner,analytic_view_name)') ..
      '= (:owner,:object_name)'
obj.origin_con_id=db:dba_query(db.get_value,stmt,obj)

return obj.object_type=='ATTRIBUTE DIMENSION' and {
    [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
             dimension_type,
             compile_state,
             table_owner,
             table_name,
             table_alias,
             order_num,
             caption,
             description,
             to_char(all_member_name) all_member_name,
             to_char(all_member_caption) all_member_caption,
             to_char(all_member_description) all_member_description
      FROM   (SELECT * 
              FROM all_attribute_dimensions 
              JOIN all_attribute_dim_tables 
              USING (origin_con_id, owner, dimension_name)) ad
      OUTER  APPLY (SELECT MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                           MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  description
                    FROM   all_attribute_dim_class j
                    WHERE  owner = ad.owner
                    AND    dimension_name = ad.dimension_name
                    AND    origin_con_id = :origin_con_id)
      WHERE  owner = :owner
      AND    dimension_name = :object_name
      AND    origin_con_id = :origin_con_id]],
    (([[
      SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
             dtl.*
      FROM   all_attribute_dimensions ad
      CROSS  APPLY @ad@ dtl
      WHERE  owner=:owner 
      AND    dimension_name=:object_name
      AND    origin_con_id = :origin_con_id
      ORDER  BY level_seq,seq]]):gsub('@ad@',ad))}
or obj.object_type=='HIERARCHY' and {
    [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
             dimension_owner, dimension_name,dim_source_table,parent_attr,caption,description
      FROM   all_hierarchies hr
      OUTER APPLY(SELECT MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                         MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  description
                  FROM   all_hier_class j
                  WHERE  owner = hr.owner
                  AND    hier_name = hr.hier_name
                  AND    origin_con_id = :origin_con_id)
     JOIN  (SELECT owner dimension_owner, dimension_name, origin_con_id, nullif(table_owner||'.',owner||'.')||table_name dim_source_table FROM all_attribute_dim_tables a) dim_tab
     USING (origin_con_id,dimension_owner, dimension_name)
     WHERE owner = :owner 
     AND   origin_con_id = :origin_con_id
     AND   hier_name = :object_name]],
    (([[SELECT dtl.*
      FROM   all_hierarchies ah
      CROSS  APPLY @ah@ dtl
      WHERE  ah.owner = :owner 
      AND    ah.hier_name = :object_name
      AND    ah.origin_con_id = :origin_con_id
      ORDER  BY seq]]):gsub('@ah@',ah))}
or obj.object_type=='ANALYTIC VIEW' and {
   [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5) topic="ANALYTIC VIEW INFO"*/ * 
     FROM  all_analytic_views av
     OUTER APPLY( SELECT MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                         MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  description
                  FROM   all_analytic_view_class j
                  WHERE  owner = av.owner
                  AND    analytic_view_name = av.analytic_view_name
                  AND    origin_con_id = :origin_con_id)
     OUTER APPLY  (SELECT av_lvlgrp_order cache_id,
                         listagg(nvl2(level_name,trim('.' from dimension_alias||'.'||hier_alias||'.'||level_name),''),',') WITHIN GROUP(ORDER BY level_meas_order) cache_levels,
                         listagg(measure_name,',')  WITHIN GROUP(ORDER BY level_meas_order) cache_measures
                    FROM   all_analytic_view_lvlgrps 
                    WHERE  owner = av.owner
                    AND    analytic_view_name = av.analytic_view_name
                    AND    origin_con_id = :origin_con_id
                    GROUP  BY av_lvlgrp_order) 
     WHERE owner = :owner 
     AND   origin_con_id = :origin_con_id
     AND   analytic_view_name = :object_name]],
   [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5) outline_leaf topic="ANALYTIC VIEW DIMENSIONS"*/ 
           hier_alias,
           ltrim(nullif(hier_owner, owner) || '.' || hier_name, '.') src_hier_name,
           is_default hier_default,
           '||' "||",
           dimension_alias dim_alias,
           ltrim(nullif(dimension_owner, owner) || '.' || dimension_name, '.') src_dim_name,
           dimension_type,
           ltrim(nullif(dim_tab.table_owner, owner) || '.' || dim_tab.table_name, '.') src_dim_table,
           dim_keys,
           fact_joins,
           references_distinct dim_key_distinct,
           regexp_substr(to_char(substr(all_member_name,1,1000)),'[^'||chr(10)||']*') all_dim_member_name,
           regexp_substr(to_char(substr(all_member_caption,1,1000)),'[^'||chr(10)||']*') all_dim_member_caption,
           regexp_substr(to_char(substr(all_member_description,1,1000)),'[^'||chr(10)||']*') all_dim_member_desc
    FROM   (SELECT /*+no_merge*/
                   owner,
                   analytic_view_name,
                   origin_con_id,
                   dimension_alias,
                   listagg(av_key_column, ',') WITHIN GROUP(ORDER BY order_num) fact_joins,
                   listagg(ref_dimension_attr, ',') WITHIN GROUP(ORDER BY order_num) dim_keys
            FROM   all_analytic_view_keys
            GROUP  BY owner, analytic_view_name, origin_con_id, dimension_alias)
    JOIN   all_analytic_view_dimensions
    USING  (owner, analytic_view_name, origin_con_id, dimension_alias)
    JOIN   all_analytic_view_hiers
    USING  (owner, analytic_view_name, origin_con_id, dimension_alias)
    JOIN   (SELECT owner dimension_owner, dimension_name, origin_con_id, table_owner, table_name FROM all_attribute_dim_tables a) dim_tab
    USING  (dimension_owner, dimension_name, origin_con_id)
    WHERE  owner = :owner
    AND    origin_con_id = :origin_con_id
    AND    analytic_view_name = :object_name
    ORDER  BY 1]],
  (([[
    SELECT /*+outline_leaf topic="ANALYTIC VIEW HIERARCHIES"*/
           ah.hier_name,dtl.*
    FROM   (SELECT * FROM all_analytic_view_hiers WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) avh
    CROSS  APPLY(SELECT * FROM all_hierarchies WHERE (owner,hier_name,origin_con_id)=(avh.hier_owner,avh.hier_name,:origin_con_id)) ah
    CROSS  APPLY @ah@ dtl
    UNION ALL
    SELECT /*+outline_leaf*/
           av.hier_name,
           NULL level_name,
           av.column_name,
           av.role,
           CASE
               WHEN av.data_type IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                av.data_type || '(' || av.data_length || decode(av.char_used, 'C', ' CHAR') || ')' --
               WHEN av.data_type = 'NUMBER' THEN
                CASE
                    WHEN nvl(av.data_scale, av.data_precision) IS NULL THEN
                     av.data_type
                    WHEN data_scale > 0 THEN
                     av.data_type || '(' || nvl('' || av.data_precision, '38') || ',' || av.data_scale || ')'
                    WHEN av.data_precision IS NULL AND av.data_scale = 0 THEN
                     'INTEGER'
                    ELSE
                     av.data_type || '(' || av.data_precision || ')'
                END
               ELSE
                av.data_type
           END data_type,
           meas.column_name source_column,
           NULL alt,
           NULL min_dtm,
           NULL skip_null,
           aggr_function level_order,
           NULL,
           NULL,
           NULL,
           NULL,
           NULL,
           row_number() OVER (ORDER BY av.column_name) seq
    FROM   (SELECT measure_name, to_char(REPLACE(qual_meas_expression, '"')) column_name, aggr_function
            FROM   all_analytic_view_base_meas
            WHERE  (owner, analytic_view_name, origin_con_id) = (:owner,:object_name,:origin_con_id)
            UNION ALL
            SELECT measure_name, to_char(meas_expression), NULL
            FROM   all_analytic_view_calc_meas
            WHERE  (owner, analytic_view_name, origin_con_id) = (:owner,:object_name,:origin_con_id)) meas
    JOIN   (SELECT *
            FROM   all_analytic_view_columns
            WHERE  (owner, analytic_view_name, origin_con_id) = (:owner,:object_name,:origin_con_id)) av
    ON     (av.column_name = meas.measure_name)
    ]]):gsub('@ah@',ah))
}