env.var.define_column('OWNER,ZONEMAP_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
return {[[/*topic="ZONEMAP QUERY TEXT"*/
    SELECT query text
    FROM   all_zonemaps
    WHERE  owner = :owner
    AND    zonemap_name = :object_name
]],[[/*topic="ZONEMAP QUERY MEASURES"*/
    SELECT *
    FROM   all_zonemap_measures
    WHERE  owner = :owner
    AND    zonemap_name = :object_name
    ORDER  BY position_in_select
]],[[/*topic="ZONEMAP LAST REFRESH"*/
    SELECT DISTINCT
           last_refresh_scn "REFRESH|LAST_SCN",
           last_refresh_date "REFRESH|LAST_DATE",
           refresh_method "REFRESH|METHOD",
           fullrefreshtim "FULL|SECS",
           increfreshtim "INCR|SECS",
           TRIM(',' FROM decode(contains_views, 'Y', 'CONTAINS_VIEWS,')
               ||decode(unusable, 'Y', 'UNUSABLE,')
               ||decode(restricted_syntax, 'Y', 'RESTRICTED_SYNTAX,')
               ||decode(inc_refreshable, 'Y', 'INC_REFRESHABLE,')
               ||decode(known_stale, 'Y', 'KNOWN_STALE,')) "REFRESH|ATTRS",
           detail_owner||'.'||detail_relation||' ['||detail_type||']' "SOURCE|OBJECT"
    FROM   all_summary_detail_tables a
    JOIN   all_summaries b
    USING  (owner, summary_name)
    WHERE  owner = :owner
    AND    summary_name = :object_name
]],[[
    SELECT /*PIVOT*/
           owner,
           zonemap_name,
           fact_owner,
           fact_table,
           scale,
           hierarchical,
           with_clustering,
           query_len,
           pruning,
           refresh_mode,
           refresh_method,
           last_refresh_method,
           invalid,
           stale,
           unusable,
           compile_state
    FROM   all_zonemaps
    WHERE  owner = :owner
    AND    zonemap_name = :object_name
]]}
