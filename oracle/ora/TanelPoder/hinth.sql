/*[[
Display the areas / features in Oracle kernel that a hint affects(displayed as a feature/module hierarchy). Usage: @@NAME <keyword>|-f"<filter>"
Based tables: v$sql_feature,v$sql_feature_hierarchy,v$sql_hint
Refer to Tanel Poder's same script

Example:
SQL> ora hinth ign                                                                          
               NAME             VERSION  SUPPORT_LEVELS     DESCRIPTION                HINTH_PATH
    --------------------------- -------- -------------- ------------------- --------------------------------
    IGNORE_OPTIM_EMBEDDED_HINTS 10.1.0.3 STATEMENT      A Universal Feature ALL
    IGNORE_ROW_ON_DUPKEY_INDEX  11.1.0.7 OBJECT         DML                 ALL -> COMPILATION -> CBO -> DML
    IGNORE_WHERE_CLAUSE         9.2.0    STATEMENT      A Universal Feature ALL


  --[[
    &filter: defaultr={UPPER(hi.name||' '||fh.path) LIKE UPPER('%&V1%')} f={}
  ]]--
]]*/
WITH feature_hierarchy AS
 (SELECT /*+no_merge*/ 
         f.sql_feature, f.description, SYS_CONNECT_BY_PATH(f.sql_feature, ' -> ') path
  FROM   v$sql_feature f, v$sql_feature_hierarchy fh
  WHERE  f.sql_feature = fh.sql_feature
  CONNECT BY fh.parent_id = PRIOR f.sql_Feature
  START  WITH fh.sql_feature = 'QKSFM_ALL')
SELECT /*+use_hash(hi fh)*/
       hi.name, hi.version,
       TRIM('/' FROM Case when bitand(target_level,1)>0 THEN 'STATEMENT/' END||
                     Case when bitand(target_level,2)>0 THEN 'QUERY_BLOCK/' END||
                     Case when bitand(target_level,4)>0 THEN 'OBJECT/' END||
                     Case when bitand(target_level,8)>0 THEN 'JOIN' END) Support_levels,
       nvl(fh.description,hi.sql_feature) description,
       REGEXP_REPLACE(replace(fh.path,'QKSFM_'), '^ -> ', '') "Hint Path (QKSFM_*)"
FROM   v$sql_hint hi, feature_hierarchy fh
WHERE  hi.sql_feature = fh.sql_feature(+)
      --    hi.sql_feature = REGEXP_REPLACE(fh.sql_feature, '_[[:digit:]]+$')
AND    (&filter)
ORDER  BY 1
