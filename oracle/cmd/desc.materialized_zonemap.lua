env.var.define_column('OWNER,ZONEMAP_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
return {[[
    SELECT * FROM all_zonemap_measures WHERE OWNER=:owner AND ZONEMAP_NAME=:object_name ORDER BY POSITION_IN_SELECT
]],[[
    SELECT QUERY TEXT FROM ALL_ZONEMAPS
    WHERE OWNER=:owner AND ZONEMAP_NAME=:object_name     
]],[[
    SELECT  /*PIVOT*/
             OWNER,
             ZONEMAP_NAME,
             FACT_OWNER,
             FACT_TABLE,
             SCALE,
             HIERARCHICAL,
             WITH_CLUSTERING,
             QUERY_LEN,
             PRUNING,
             REFRESH_MODE,
             REFRESH_METHOD,
             LAST_REFRESH_METHOD,
             INVALID,
             STALE,
             UNUSABLE,
             COMPILE_STATE
    FROM ALL_ZONEMAPS
    WHERE OWNER=:owner AND ZONEMAP_NAME=:object_name
]]}