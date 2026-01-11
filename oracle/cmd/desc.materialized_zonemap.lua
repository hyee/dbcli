env.var.define_column('OWNER,ZONEMAP_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
return {[[/*topic="ZONEMAP QUERY TEXT"*/
    SELECT QUERY TEXT FROM ALL_ZONEMAPS WHERE OWNER=:owner AND ZONEMAP_NAME=:object_name     
]],[[/*topic="ZONEMAP QUERY MEASURES"*/
    SELECT * FROM all_zonemap_measures WHERE OWNER=:owner AND ZONEMAP_NAME=:object_name ORDER BY POSITION_IN_SELECT
]],[[/*topic="ZONEMAP LAST REFRESH"*/
    SELECT DISTINCT
          LAST_REFRESH_SCN "REFRESH|LAST_SCN",LAST_REFRESH_DATE "REFRESH|LAST_DATE",REFRESH_METHOD "REFRESH|METHOD",
          FULLREFRESHTIM "FULL|SECS",INCREFRESHTIM "INCR|SECS",
          trim(',' from decode(CONTAINS_VIEWS,'Y','CONTAINS_VIEWS,')
              ||decode(UNUSABLE,'Y','UNUSABLE,')
              ||decode(RESTRICTED_SYNTAX,'Y','RESTRICTED_SYNTAX,')
              ||decode(INC_REFRESHABLE,'Y','INC_REFRESHABLE,')
              ||decode(KNOWN_STALE,'Y','KNOWN_STALE,')) "REFRESH|ATTRS",
           DETAIL_OWNER||'.'||DETAIL_RELATION||' ['||DETAIL_TYPE||']' "SOURCE|OBJECT"
    FROM  all_summary_detail_tables a
    JOIN  all_summaries b
    USING (owner,summary_name)
    WHERE owner=:owner AND summary_name=:object_name
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
    FROM  ALL_ZONEMAPS
    WHERE OWNER=:owner AND ZONEMAP_NAME=:object_name
]]}