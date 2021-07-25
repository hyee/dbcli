/*[[Show CPU, memory and storage usages. Usage: @@NAME <instance>]]*/
env feed off
COL "AVG|CPU,AVG|GC,0 Min|CPU,0 Min|GC,1 Min|CPU,1 Min|GC,2 Min|CPU,2 Min|GC,3 Min|CPU,3 Min|GC,4 Min|CPU,4 Min|GC,5 Min|CPU,5 Min|GC,6 Min|CPU,6 Min|GC,7 Min|CPU,7 Min|GC,8 Min|CPU,8 Min|GC,9 Min|CPU,9 Min|GC" FOR pct2
SELECT inst, job `Type`, 
       '|' `|`,  
       AVG(IF(t='node',v,NULL)) `AVG|CPU`, 
       AVG(IF(t='gc',v,NULL)) `AVG|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(now(),'%m%d-%H:%i'),v,null)) `0 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(now(),'%m%d-%H:%i'),v,null)) `0 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -1 minute),'%m%d-%H:%i'),v,null)) `1 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -1 minute),'%m%d-%H:%i'),v,null)) `1 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -2 minute),'%m%d-%H:%i'),v,null)) `2 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -2 minute),'%m%d-%H:%i'),v,null)) `2 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -3 minute),'%m%d-%H:%i'),v,null)) `3 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -3 minute),'%m%d-%H:%i'),v,null)) `3 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -4 minute),'%m%d-%H:%i'),v,null)) `4 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -4 minute),'%m%d-%H:%i'),v,null)) `4 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -5 minute),'%m%d-%H:%i'),v,null)) `5 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -5 minute),'%m%d-%H:%i'),v,null)) `5 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -6 minute),'%m%d-%H:%i'),v,null)) `6 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -6 minute),'%m%d-%H:%i'),v,null)) `6 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -7 minute),'%m%d-%H:%i'),v,null)) `7 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -7 minute),'%m%d-%H:%i'),v,null)) `7 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -8 minute),'%m%d-%H:%i'),v,null)) `8 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -8 minute),'%m%d-%H:%i'),v,null)) `8 Min|GC`,
       '|' `|`,
       AVG(IF(t='node' AND ts=DATE_FORMAT(date_add(now(), interval -9 minute),'%m%d-%H:%i'),v,null)) `9 Min|CPU`, 
       AVG(IF(t='gc' AND ts=DATE_FORMAT(date_add(now(), interval -9 minute),'%m%d-%H:%i'),v,null)) `9 Min|GC`
FROM   (SELECT t, INSTANCE inst, date_format(TIME, '%m%d-%H:%i') ts, job, ROUND(AVG(VALUE),4) v
        FROM   (SELECT 'gc' t, a.*
                FROM   metrics_schema.go_gc_cpu_usage a
                WHERE  value>0 and ('&V1' IS NULL OR lower(instance) LIKE lower(concat('%&V1%')))
                UNION ALL
                SELECT 'node' t, b.*
                FROM   metrics_schema.process_cpu_usage b
                WHERE  value>0 and ('&V1' IS NULL OR lower(instance) LIKE lower(concat('%&V1%')))) a
        GROUP  BY t, inst, ts, job
        HAVING v>0) b
GROUP  BY inst, job
ORDER  BY `AVG|CPU` desc;

COL "MAX|MEM,MAX|Go Heap,0 Min|MEM,1 Min|MEM,2 Min|MEM,3 Min|MEM,4 Min|MEM,5 Min|MEM,6 Min|MEM,7 Min|MEM,8 Min|MEM,9 Min|MEM" FOR KMG2
COL "Go|Heap" FOR PCT0

SELECT inst, job `Type`, 
       '|' `|`,  
       MAX(IF(t='node',v,NULL)) `Max|Mem`, 
       MAX(IF(t='gc',v,NULL)) `Max|Go Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=0,v,null)) `0 Min|Mem`, 
       SUM(IF(t='gc' AND ts=0,v,null))/SUM(IF(t='node' AND ts=0,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=1,v,null)) `1 Min|Mem`, 
       SUM(IF(t='gc' AND ts=1,v,null))/SUM(IF(t='node' AND ts=1,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=2,v,null)) `2 Min|Mem`, 
       SUM(IF(t='gc' AND ts=2,v,null))/SUM(IF(t='node' AND ts=2,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=3,v,null)) `3 Min|Mem`, 
       SUM(IF(t='gc' AND ts=3,v,null))/SUM(IF(t='node' AND ts=3,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=4,v,null)) `4 Min|Mem`, 
       SUM(IF(t='gc' AND ts=4,v,null))/SUM(IF(t='node' AND ts=4,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=5,v,null)) `5 Min|Mem`, 
       SUM(IF(t='gc' AND ts=5,v,null))/SUM(IF(t='node' AND ts=5,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=6,v,null)) `6 Min|Mem`, 
       SUM(IF(t='gc' AND ts=6,v,null))/SUM(IF(t='node' AND ts=6,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=7,v,null)) `7 Min|Mem`, 
       SUM(IF(t='gc' AND ts=7,v,null))/SUM(IF(t='node' AND ts=7,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=8,v,null)) `8 Min|Mem`, 
       SUM(IF(t='gc' AND ts=8,v,null))/SUM(IF(t='node' AND ts=8,v,null)) `Go|Heap`,
       '|' `|`,
       AVG(IF(t='node' AND ts=9,v,null)) `9 Min|Mem`, 
       SUM(IF(t='gc' AND ts=9,v,null))/SUM(IF(t='node' AND ts=9,v,null)) `Go|Heap`
FROM   (SELECT t, INSTANCE inst, floor(time_to_sec(timediff(now(),time))/60) ts, job, ROUND(AVG(VALUE),4) v
        FROM   (SELECT 'gc' t, a.*
                FROM   metrics_schema.go_heap_mem_usage a
                WHERE  value>0 and ('&V1' IS NULL OR lower(instance) LIKE lower(concat('%&V1%')))
                UNION ALL
                SELECT 'node' t, b.*
                FROM   metrics_schema.tidb_process_mem_usage b
                WHERE  value>0 and ('&V1' IS NULL OR lower(instance) LIKE lower(concat('%&V1%')))) a
        GROUP  BY t, inst, ts, job
        HAVING v>0) b
GROUP  BY inst, job
ORDER  BY `MAX|MEM` desc;

col "TiKv|Capacity,TiKV|Free,TiKV|Used,Engine|Default,Engine|Raft,Engine|Lock,Engine|Writ,Mem|Default,Mem|Raft,Mem|Lock,Mem|Writ,Cache|KV,Cache|Raft,Engine|Blob,Live|Blob" for kmg2
SELECT * FROM 
(SELECT INSTANCE `TiKV|Instance`,
        MAX(IF(type='capacity',VALUE,0)) `TiKV|Capacity`,
        MAX(IF(type='available',VALUE,0)) `TiKV|Free`
 FROM   metrics_schema.tikv_store_size
 WHERE  Time>=date_add(now(),interval -1 minute)
 AND   ('&V1' IS NULL OR lower(instance) LIKE lower(concat('%&V1%')))
 GROUP  BY Instance) A
LEFT JOIN (
 SELECT INSTANCE `TiKV|Instance`,
        '|' `|`,
        MAX(IF(type='default',VALUE,0)) `Engine|Default`,
        MAX(IF(type='raft',VALUE,0)) `Engine|Raft`,
        MAX(IF(type='lock',VALUE,0)) `Engine|Lock`,
        MAX(IF(type='write',VALUE,0)) `Engine|Writ`
 FROM   metrics_schema.tikv_engine_size
 WHERE  Time>=date_add(now(),interval -1 minute)
 GROUP  BY Instance
) B USING(`TiKV|Instance`)
LEFT JOIN (
 SELECT INSTANCE `TiKV|Instance`,
        SUM(VALUE) `Engine|Blob`
 FROM   metrics_schema.tikv_engine_blob_file_size
 WHERE  Time>=date_add(now(),interval -1 minute)
 GROUP  BY Instance
) C USING(`TiKV|Instance`)
LEFT JOIN (
 SELECT INSTANCE `TiKV|Instance`,
        '|' `|`,
        SUM(IF(cf='default',VALUE,0)) `Mem|Default`,
        SUM(IF(cf='raft',VALUE,0)) `Mem|Raft`,
        SUM(IF(cf='lock',VALUE,0)) `Mem|Lock`,
        SUM(IF(cf='write',VALUE,0)) `Mem|Writ`
 FROM   metrics_schema.tikv_memtable_size
 WHERE  Time>=date_add(now(),interval -1 minute)
 GROUP  BY Instance
) D USING(`TiKV|Instance`)
LEFT JOIN (
 SELECT INSTANCE `TiKV|Instance`,
        '|' `|`,
        MAX(IF(db='kv',VALUE,0)) `Cache|KV`,
        MAX(IF(db='raft',VALUE,0)) `Cache|Raft`
 FROM   metrics_schema.tikv_block_cache_size
 WHERE  Time>=date_add(now(),interval -1 minute)
 GROUP  BY Instance
) E USING(`TiKV|Instance`)
LEFT JOIN (
 SELECT INSTANCE `TiKV|Instance`,
        SUM(VALUE) `Live|Blob`
 FROM   metrics_schema.tikv_engine_live_blob_size
 WHERE  Time>=date_add(now(),interval -1 minute)
 GROUP  BY Instance
) F USING(`TiKV|Instance`);