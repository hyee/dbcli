local ad=[[(SELECT  /*+no_merge monitor
                       opt_param('optimizer_dynamic_sampling' 5) 
                       opt_param('optimizer_adaptive_plans' 'false') 
                       opt_param('_optimizer_cartesian_enabled' 'false')
                       opt_param('container_data' 'current')
                       opt_param('_optimizer_cbqt_or_expansion' 'off')
                       opt_param('_optimizer_reduce_groupby_key' 'false') 
                       opt_param('_optimizer_group_by_placement' 'false') 
                       opt_param('_optimizer_aggr_groupby_elim' 'false') */
                     row_number() OVER(ORDER BY ba.seq, a.order_num) seq,
                     a.attribute_name,
                     ba.alt,
                     ba.role,
                     ba.level_name,
                     d.level_type,
                     ba.dtm_levels,
                     e.used_hiers,
                     nullif(b.owner || '.', ad.owner || '.') || b.table_name || '.' || column_name source_column,
                     decode(ba.role, 'KEY', regexp_substr(to_char(substr(d.member_name_expr,1,1000)),'[^'||chr(10)||']*')) member_expr,
                     d.skip_when_null skip_null,
                     aggs.level_order,
                     c.caption attr_caption,
                     c.descr attr_Desc,
                     decode(ba.role, 'KEY', regexp_substr(to_char(substr(d.member_caption_expr,1,1000)),'[^'||chr(10)||']*')) level_caption,
                     decode(ba.role, 'KEY', regexp_substr(to_char(substr(d.member_description_expr,1,1000)),'[^'||chr(10)||']*')) level_desc
              FROM   (SELECT *
                      FROM   all_attribute_dim_tables tb
                      WHERE  tb.owner = ad.owner
                      AND    tb.dimension_name = ad.dimension_name
                      AND    tb.origin_con_id = :origin_con_id) b
              JOIN   (SELECT *
                     FROM   all_attribute_dim_attrs attr
                     WHERE  attr.owner = ad.owner
                     AND    attr.dimension_name = ad.dimension_name
                     AND    attr.origin_con_id = :origin_con_id) a
              ON     (a.table_alias = b.table_alias)
              LEFT   JOIN (SELECT ROWNUM seq, a.*
                          FROM   (SELECT attribute_name,
                                         MAX(is_minimal_dtm) is_minimal_dtm,
                                         MIN(ROLE) ROLE,
                                         MAX(DECODE(ROLE, 'KEY', level_name)) level_name,
                                         MAX(DECODE(ROLE, 'KEY', is_alternate)) alt,
                                         MAX(DECODE(ROLE, 'KEY', GREATEST(attr_order_num,key_order_num))) key_ord,
                                         listagg(DISTINCT DECODE(role, 'PROP', level_name), '/') WITHIN GROUP(ORDER BY order_num) dtm_levels,
                                         COUNT(DECODE(role, 'PROP', 1)) dtms,
                                         SUM(DECODE(role, 'KEY', 0, 255) + order_num) ords
                                  FROM   (SELECT /*+no_expand*/ * FROM all_attribute_dim_level_attrs WHERE :origin_con_id=origin_con_id OR origin_con_id IS NULL) attr
                                  LEFT   JOIN (SELECT * FROM all_attribute_dim_keys WHERE :origin_con_id=origin_con_id)
                                  USING (owner,dimension_name,attribute_name,level_name,origin_con_id)
                                  WHERE  owner = ad.owner
                                  AND    dimension_name = ad.dimension_name
                                  GROUP  BY attribute_name
                                  ORDER  BY is_minimal_dtm,dtms,ords,key_ord) a) ba
              ON     (a.attribute_name = ba.attribute_name)
              LEFT   JOIN (SELECT level_name,
                                 listagg(agg_func || ' ' || attribute_name || NULLIF(' ' || criteria, ' ASC') || NULLIF(' NULLS ' || nulls_position, ' NULLS ' || DECODE(criteria, 'ASC', 'LAST', 'FIRST')),
                                         ',') WITHIN GROUP(ORDER BY order_num) level_order
                          FROM   all_attribute_dim_order_attrs
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = :origin_con_id
                          GROUP  BY level_name) aggs
              ON     (ba.level_name = aggs.level_name)
              LEFT   JOIN (SELECT attribute_name,
                                 MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) caption,
                                 MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) descr
                          FROM   all_attribute_dim_attr_class j
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = :origin_con_id
                          GROUP  BY attribute_name) c
              ON     (a.attribute_name = c.attribute_name)
              LEFT   JOIN (SELECT *
                          FROM   all_attribute_dim_levels
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = :origin_con_id) d
              ON     (ba.level_name = d.level_name)
              LEFT   JOIN (SELECT level_name, listagg(hier_name, ',') WITHIN GROUP(ORDER BY hier_name) used_hiers
                          FROM   all_hierarchies
                          JOIN   all_hier_levels
                          USING  (owner, hier_name, origin_con_id)
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = :origin_con_id
                          GROUP  BY level_name, dimension_owner, dimension_name) e
              ON     (ba.level_name = e.level_name)
              WHERE  b.origin_con_id = :origin_con_id
              ORDER  BY 1)]]
local ah=([[ (SELECT /*+no_merge*/ 
                     row_number() OVER(ORDER BY adk.hier_seq NULLS LAST, adt.seq, ahc.order_num) seq,
                     NVL(adk.hier_level, adt.level_name) hier_level,
                     adt.level_type,
                     NVL(adt.attribute_name, ahc.column_name) column_name,
                     adt.alt,
                     adt.dtm_levels,
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
                     ahc.nullable,
                     ahc.role,
                     coalesce(adt.source_column,regexp_substr(to_char(substr(ahd.expression,1,1000)),'[^'||chr(10)||']*')) source_column,
                     adt.member_expr,
                     adt.skip_null,
                     adt.level_order,
                     NVL(ahd.caption, adt.attr_caption) caption,
                     NVL(ahd.descr, adt.attr_desc) description
              FROM   all_attribute_dimensions ad
              JOIN   all_hier_columns ahc
              ON     (ah.owner = ahc.owner AND ah.hier_name = ahc.hier_name AND ahc.origin_con_id = :origin_con_id)
              OUTER  APPLY(SELECT *
                           FROM   (SELECT level_name,
                                          attribute_name,
                                          lpad(' ', 2 * lv.order_num) || level_name || '(*)' hier_level,
                                          lv.order_num hier_seq
                                   FROM   all_hier_levels lv
                                   JOIN   all_hier_level_id_attrs attr
                                   USING  (owner, hier_name, origin_con_id, level_name)
                                   WHERE  owner = ah.owner
                                   AND    hier_name = ah.hier_name
                                   AND    origin_con_id = :origin_con_id)
                           WHERE  attribute_name = ahc.column_name) adk
              OUTER  APPLY(SELECT /*+no_merge(i) NO_GBY_PUSHDOWN(i)*/
                                   g.*, i.caption, i.descr
                           FROM   all_hier_hier_attributes g,
                                  (SELECT hier_attr_name,
                                          MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                                          MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  descr
                                   FROM   all_hier_hier_attr_class
                                   WHERE  owner = ah.owner
                                   AND    hier_name = ah.hier_name
                                   AND    origin_con_id = :origin_con_id
                                   GROUP  BY hier_attr_name) i
                           WHERE  g.hier_attr_name = i.hier_attr_name(+)
                           AND    ahc.column_name = g.hier_attr_name
                           AND    ah.hier_name = g.hier_name
                           AND    ah.owner = g.owner
                           AND    g.origin_con_id = :origin_con_id) ahd
              OUTER  APPLY(SELECT *
                           FROM   @ad@ adt
                           WHERE  TRIM(adt.attribute_name) = ahc.column_name) adt
              WHERE  ah.dimension_owner = ad.owner
              AND    ah.dimension_name = ad.dimension_name
              AND    ad.origin_con_id = :origin_con_id)]]):gsub('@ad@',ad)
if object_type=='ANALYTIC VIEW' then
    env.var.define_column('CATEGORY','BREAK','SKIP','-')
    cfg.set("colsep",'|')
end

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
      ORDER  BY 1]]):gsub('@ad@',ad))}
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
      ORDER  BY 1]]):gsub('@ah@',ah))}
or obj.object_type=='ANALYTIC VIEW' and {
   [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ * 
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
   [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5) */ 
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
    FROM   (SELECT owner,
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
    SELECT /*+outline_leaf ordered*/
           nvl2(avh.hier_name, 'HIER: ', '') || av.hier_name CATEGORY,
           row_number() over(partition by av.hier_name order by hier.seq,av.order_num) "#",
           hier.hier_level,
           hier.level_type,
           NVL(hier.column_name, av.column_name) column_name,
           hier.alt,
           hier.dtm_levels,
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
           NVL(avc.cached,av.dyn_all_cache) cached,
           av.nullable,
           av.role,
           nvl(RTRIM(nvl2(hier.source_column,hier.source_column || ' => ','') ||
                 nvl2(COALESCE(ak.av_key_column, meas.measure_name),
                      nvl2(meas.measure_name,
                           nvl(meas.aggr_function,av.default_aggr)||'('|| av.table_name || '.' || meas.measure_name||')',
                           av.table_name || '.' || ak.av_key_column),
                      ''),
                 '=> '), to_char(calc.meas_expression)) source_column,
           hier.member_expr,
           hier.skip_null,
           hier.level_order,
           hier.caption caption,
           hier.description DESCRIPTION
    FROM   (
        SELECT /*+no_merge outline_leaf use_nl(base av) opt_estimate(query_block rows=50)*/ * 
        FROM   all_analytic_views base
        JOIN   all_analytic_view_columns av
        USING  (owner,analytic_view_name,origin_con_id)
        WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) av
    LEFT   JOIN (SELECT * from all_analytic_view_base_meas WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) meas
    ON     (av.column_name = meas.measure_name)
    LEFT   JOIN (SELECT * from all_analytic_view_calc_meas WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) calc
    ON     (av.column_name = calc.measure_name)
    LEFT   JOIN (SELECT * from all_analytic_view_keys WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) ak
    ON     (av.column_name = ak.ref_dimension_attr)
    LEFT   JOIN (SELECT * from all_analytic_view_dimensions WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) ad
    ON     (av.dimension_name = ad.dimension_alias)
    LEFT   JOIN (SELECT * from all_analytic_view_hiers WHERE (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id)) avh
    ON     (av.hier_name = avh.hier_alias AND av.dimension_name = avh.dimension_alias)
    OUTER  APPLY (SELECT dtl.*
                  FROM   all_hierarchies ah
                  CROSS  APPLY @ah@ dtl
                  WHERE  av.column_name = TRIM(dtl.column_name)
                  AND    avh.hier_owner = ah.owner
                  AND    avh.hier_name = ah.hier_name
                  AND    ah.origin_con_id = :origin_con_id) hier
    OUTER APPLY (SELECT regexp_replace(listagg(av_lvlgrp_order,',') WITHIN GROUP(ORDER BY av_lvlgrp_order),'^0$','Y') CACHED
                 FROM (SELECT *
                       FROM   all_analytic_view_lvlgrps
                       WHERE  (owner,analytic_view_name,origin_con_id)=(:owner,:object_name,:origin_con_id))
                 WHERE (measure_name IS NULL AND
                        av.hier_name = hier_alias AND 
                        av.dimension_name = dimension_alias AND
                        regexp_substr(hier.hier_level,'[^\(\) ]+')=level_name)
                    OR
                       (av.column_name=measure_name AND
                        av.dimension_name IS NULL)) avc
    ORDER  BY av.dimension_name, av.hier_name, hier.seq, av.order_num]]):gsub('@ah@',ah))
}