return [[
    SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) use_hash(a b) NATIVE_FULL_OUTER_JOIN*/ 
           SUBPROGRAM_ID PROG#,
           NVL(A.ELEMENT,B.ELEMENT) ELEMENT,
           NVL2(a.RETURNS,'FUNCTION',decode(sign(results),1,'FUNCTION','PROCEDURE')) Type,
           ARGUMENTS,
           NVL(a.RETURNS,DECODE(INHERITED,'YES','<INHERITED FROM SUPER>')) returns,
           AGGREGATE,PIPELINED,PARALLEL,INTERFACE,DETERMINISTIC,AUTHID
    FROM   (SELECT /*+no_merge use_hash(a b)*/
                   a.*, 
                   b.returns,
                   b.ARGUMENTS,
                   b.results,
                   PROCEDURE_NAME||NVL2(a.OVERLOAD,' (#'||a.OVERLOAD||')','') ELEMENT,
                   row_number() OVER(PARTITION BY A.PROCEDURE_NAME,b.ARGUMENTS,B.RESULTS ORDER BY A.SUBPROGRAM_ID) OV
            FROM   ALL_PROCEDURES A LEFT JOIN (
                SELECT /*+no_merge*/
                       SUBPROGRAM_ID,
                       MAX(decode(position,0,CASE
                           WHEN pls_type IS NOT NULL THEN
                            pls_type
                           WHEN type_subname IS NOT NULL THEN
                            type_name || '.' || type_subname
                           WHEN type_name IS NOT NULL THEN
                            type_name||'('||DATA_TYPE||')'
                           ELSE
                            data_type
                       END)) returns,
                       COUNT(CASE WHEN position=0 THEN 1 END) RESULTS,
                       COUNT(CASE WHEN position>0 THEN 1 END) ARGUMENTS
                FROM   all_Arguments b
                WHERE  owner=:owner
                AND    package_name=:object_name
                GROUP  BY SUBPROGRAM_ID) b
            ON     (a.SUBPROGRAM_ID=b.SUBPROGRAM_ID)
            WHERE  owner=:owner AND object_name=:object_name
            AND    a.SUBPROGRAM_ID > 0
    ) a FULL JOIN (
        SELECT /*+no_merge*/
               a.*,DECODE(INHERITED,'NO',METHOD_NAME) PROCEDURE_NAME,PARAMETERS ARGUMENTS,
               MIN(METHOD_NO) OVER(PARTITION BY DECODE(INHERITED,'YES',METHOD_NAME)) METHOD_SEQ,
               METHOD_NAME||DECODE(COUNT(1) OVER(PARTITION BY METHOD_NAME),1,'',' (#'||ROW_NUMBER() OVER(PARTITION BY METHOD_NAME ORDER BY METHOD_NO)||')') ELEMENT,
               row_number() OVER(PARTITION BY DECODE(INHERITED,'NO',METHOD_NAME),PARAMETERS,RESULTS ORDER BY METHOD_NO) OV
        FROM   all_type_methods A 
        WHERE  :object_type='TYPE' 
        AND    owner=:owner AND type_name=:object_name) b
    USING   (PROCEDURE_NAME,ARGUMENTS,RESULTS,OV)
    ORDER BY SUBPROGRAM_ID,method_seq,method_no]]
