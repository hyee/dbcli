/*[[
Display the areas / features in Oracle kernel that a hint affects(displayed as a feature/module hierarchy). Usage: @@NAME <hint_name>
Based tables: v$sql_feature,v$sql_feature_hierarchy,v$sql_hint
Refer to Tanel Poder's same script

Example:
SQL> ora hinth ign                                                                          
               NAME             VERSION  SUPPORT_LEVELS     DESCRIPTION                HINTH_PATH
    --------------------------- -------- -------------- ------------------- --------------------------------
    IGNORE_OPTIM_EMBEDDED_HINTS 10.1.0.3 STATEMENT      A Universal Feature ALL
    IGNORE_ROW_ON_DUPKEY_INDEX  11.1.0.7 OBJECT         DML                 ALL -> COMPILATION -> CBO -> DML
    IGNORE_WHERE_CLAUSE         9.2.0    STATEMENT      A Universal Feature ALL

]]*/
WITH feature_hierarchy AS
 (SELECT f.sql_feature, f.description, SYS_CONNECT_BY_PATH(REPLACE(f.sql_feature, 'QKSFM_', ''), ' -> ') path
  FROM   v$sql_feature f, v$sql_feature_hierarchy fh
  WHERE  f.sql_feature = fh.sql_feature
  CONNECT BY fh.parent_id = PRIOR f.sql_Feature
  START  WITH fh.sql_feature = 'QKSFM_ALL')
SELECT hi.name, hi.version,
       TRIM('/' FROM Case when bitand(target_level,1)>0 THEN 'STATEMENT/' END||
                     Case when bitand(target_level,2)>0 THEN 'QUERY_BLOCK/' END||
                     Case when bitand(target_level,4)>0 THEN 'OBJECT/' END||
                     Case when bitand(target_level,8)>0 THEN 'JOIN' END) Support_levels,
       fh.description,REGEXP_REPLACE(fh.path, '^ -> ', '') hinth_path
FROM   v$sql_hint hi, feature_hierarchy fh
WHERE  hi.sql_feature = fh.sql_feature
      --    hi.sql_feature = REGEXP_REPLACE(fh.sql_feature, '_[[:digit:]]+$')
AND    UPPER(hi.name||' '||fh.path) LIKE UPPER('%&V1%')
ORDER  BY 1
