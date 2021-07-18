/*[[Show QPS metrics. Usage: @@NAME [<instance>]
    
]]*/
COL "Avg,Select,Insert,Update,Delete,Commit,NON-DML,Dur" for usmhd2
COL "Size/s" for kmg2
COL "QPS,Query,Exec,Ping,Others,Get,Scan,2PC,Cop,Lock,Scan|Keys,Scan|Select,Scan|Index,Scan|Analyze" for tmb2

grid {
    [[/*grid={topic='QPS'}*/
        SELECT DATE_FORMAT(TIME,'%H:%i') Minute,
               ROUND(SUM(IF(result = 'OK',Value,0)),2) QPS,
               ROUND(SUM(IF(result = 'Error',Value,0)),2) Errs,
               ROUND(SUM(CASE WHEN result='OK' AND type='Query' THEN Value END),2) Query,
               ROUND(SUM(CASE WHEN result='OK' AND type='StmtExecute' THEN Value END),2) Exec,
               ROUND(SUM(CASE WHEN result='OK' AND type='Ping' THEN Value END),2) Ping,
               ROUND(SUM(CASE WHEN result='OK' and type not in('Query','StmtExecute','Ping') THEN Value END),2) Others
        FROM   metrics_schema.tidb_qps
        WHERE  value>0
        AND    (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))
        GROUP  BY Minute
        ORDER  BY Minute DESC
    ]],'|',[[/*grid={topic='Query Time'}*/
        SELECT DATE_FORMAT(TIME,'%H:%i') Minute,
               ROUND(AVG(VALUE)*1e6,2) `Avg`,
               ROUND(AVG(IF(sql_type='Select',value,null))*1e6,2) `Select`,
               ROUND(AVG(IF(sql_type='Insert',value,null))*1e6,2) `Insert`,
               ROUND(AVG(IF(sql_type='Update',value,null))*1e6,2) `Update`,
               ROUND(AVG(IF(sql_type='Delete',value,null))*1e6,2) `Delete`,
               ROUND(AVG(IF(sql_type in('Commit','Rollback'),value,null))*1e6,2) `Commit`,
               ROUND(AVG(IF(sql_type NOT IN('Select','Insert','Update','Delete','Commit','Rollback'),value,null))*1e6,2) `NON-DML`
        FROM   metrics_schema.tidb_query_duration
        WHERE  value>0
        AND    (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))
        GROUP  BY Minute
        ORDER  BY Minute DESC
    ]],'-',{
    [[/*grid={topic='gRPC QPS'}*/
        SELECT DATE_FORMAT(TIME,'%H:%i') Minute,
               ROUND(SUM(VALUE),2) `QPS`,
               ROUND(SUM(IF(type LIKE '%get',value,null)),2) `Get`,
               ROUND(SUM(IF(type LIKE '%scan',value,null)),2) `Scan`,
               ROUND(SUM(IF(type IN('kv_prewrite','kv_commit'),value,null)),2) `2PC`,
               ROUND(SUM(IF(type IN('coprocessor'),value,null)),2) `Cop`,
               ROUND(SUM(IF(type LIKE '%lock',value,null)),2) `Lock`
        FROM   metrics_schema.tikv_grpc_qps
        WHERE  value>0
        AND    (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))
        GROUP  BY Minute
        ORDER  BY Minute DESC
    ]],'|',[[/*grid={topic='Cop Time'}*/
        SELECT * FROM 
        (
            SELECT DATE_FORMAT(TIME,'%H:%i') Minute,
                   ROUND(AVG(VALUE)*1e6,2) `Dur`
            FROM   metrics_schema.tidb_cop_duration
            WHERE  value>0
            AND    (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))
            GROUP  BY Minute
        ) A LEFT JOIN (
            SELECT DATE_FORMAT(TIME,'%H:%i') Minute,
                   ROUND(AVG(VALUE),2) `Size/s`
            FROM   metrics_schema.tikv_cop_total_response_size_per_seconds
            WHERE  value>0
            AND    (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))
            GROUP  BY Minute
        ) B USING (Minute)
        LEFT JOIN (
            SELECT DATE_FORMAT(TIME,'%H:%i') Minute,
                   ROUND(SUM(VALUE),2) `Scan|Keys`,
                   ROUND(AVG(IF(req='select',VALUE,NULL)),2) `Scan|Select`,
                   ROUND(AVG(IF(req='index',VALUE,NULL)),2) `Scan|Index`,
                   ROUND(AVG(IF(req LIKE 'analyze%',VALUE,NULL)),2) `Scan|Analyze`
            FROM   metrics_schema.tikv_cop_scan_keys_num
            WHERE  value>0
            AND    (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))
            GROUP  BY Minute
        ) c USING (Minute)
        ORDER  BY Minute DESC
    ]]}
}