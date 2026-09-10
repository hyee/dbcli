return [[
    SELECT /*INTERNAL_DBCLI_CMD*/ /*+outline_leaf opt_param('optimizer_dynamic_sampling' 5) opt_param('container_data' 'all') use_hash(a b) NATIVE_FULL_OUTER_JOIN*/
           subprogram_id prog#,
           nvl(a.element, b.element) element,
           nvl2(a.returns, 'FUNCTION', decode(sign(results), 1, 'FUNCTION', 'PROCEDURE')) type,
           arguments,
           nvl(a.returns, decode(inherited, 'YES', '<INHERITED FROM SUPER>')) returns,
           aggregate, pipelined, parallel, interface, deterministic, authid
    FROM   (
        SELECT /*+no_merge use_hash(a b)*/
               a.*,
               b.returns,
               b.arguments,
               b.results,
               procedure_name||nvl2(a.overload, ' (#'||a.overload||')', '') element,
               row_number() OVER(PARTITION BY a.procedure_name, b.arguments, b.results ORDER BY a.subprogram_id) ov
        FROM   all_procedures a
        LEFT   JOIN (
                   SELECT /*+no_merge*/
                          subprogram_id,
                          max(decode(position, 0, CASE
                              WHEN pls_type IS NOT NULL THEN
                                  pls_type
                              WHEN type_subname IS NOT NULL THEN
                                  type_name || '.' || type_subname
                              WHEN type_name IS NOT NULL THEN
                                  type_name||'('||data_type||')'
                              ELSE
                                  data_type
                          END)) returns,
                          count(CASE WHEN position = 0 THEN 1 END) results,
                          count(CASE WHEN position > 0 THEN 1 END) arguments
                   FROM   all_arguments b
                   WHERE  owner = :owner
                   AND    package_name = :object_name
                   GROUP  BY subprogram_id) b
        ON     (a.subprogram_id = b.subprogram_id)
        WHERE  owner = :owner
        AND    object_name = :object_name
        AND    a.subprogram_id > 0) a
    FULL   JOIN (
        SELECT /*+no_merge*/
               a.*,
               decode(inherited, 'NO', method_name) procedure_name,
               parameters arguments,
               MIN(method_no) OVER(PARTITION BY decode(inherited, 'YES', method_name)) method_seq,
               method_name||decode(count(1) OVER(PARTITION BY method_name), 1, '', ' (#'||row_number() OVER(PARTITION BY method_name ORDER BY method_no)||')') element,
               row_number() OVER(PARTITION BY decode(inherited, 'NO', method_name), parameters, results ORDER BY method_no) ov
        FROM   all_type_methods a
        WHERE  :object_type = 'TYPE'
        AND    owner = :owner
        AND    type_name = :object_name) b
    USING  (procedure_name, arguments, results, ov)
    ORDER  BY subprogram_id, method_seq, method_no]]
