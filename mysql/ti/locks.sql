/*[[Show data lock contentions]]*/
col hash_key break -
COL "Trx|Time,Avg|Ela,Avg|Retry" for usmhd2
env headstyle initcap

SELECT a.`lock`,
       json_extract(a.kv,'$.table_id')+0 `table#`,
       any_value(d.region_id) `region#`,
       json_extract(a.kv,'$._tidb_rowid') `row#`,
       any_value(concat(t.table_name,if(d.index_name is not null,concat('.',d.index_name),''))) object_name,
       IF(b.id=a.trx_id,'Waiting','Holding') type,
       b.id trx_id,
       b.session_id sid,
       any_value(b.user) user,
       any_value(b.db) db,
       any_value(b.state) state,
       any_value(greatest(0,timestampdiff(MICROSECOND,current_timestamp(3),IF(b.id=a.trx_id,b.waiting_start_time,b.start_time)))) `Trx|Time`,
       SUM(sum_latency)/greatest(1,sum(exec_count))/1e3 'Avg|Ela',
       SUM(sum_exec_retry_time)/greatest(1,sum(exec_count))/1e3 'Avg|Retry',
       any_value(concat(substr(IF(b.id=a.trx_id, a.sql_digest, b.current_sql_digest),1,13),' ..')) digest,
       any_value(substr(replace(replace(replace(replace(replace(replace(trim(c.digest_text),'\n',' '),' ','<>'),'><',''),'<>',' '),'` , ',','),'`',''),1,150)) sql_text
FROM   (select 'DATALOCK' `lock`,
                `KEY`,
                KEY_INFO,
                TRX_ID,
                CURRENT_HOLDING_TRX_ID,
                SQL_DIGEST,
                SQL_DIGEST_TEXT,
                tidb_decode_key(a.key) kv 
        from information_schema.data_lock_waits a
        union all
        select  'DEADLOCK',
                `KEY`,
                KEY_INFO,
                TRY_LOCK_TRX_ID,
                TRX_HOLDING_LOCK,
                CURRENT_SQL_DIGEST,
                CURRENT_SQL_DIGEST_TEXT,
                tidb_decode_key(a.key) kv 
        from information_schema.deadlocks a) a
JOIN   information_schema.tidb_trx b
ON     (b.id IN (a.current_holding_trx_id, a.trx_id))
LEFT   JOIN information_schema.tables t ON(json_extract(a.kv,'$.table_id')=t.tidb_table_id)
LEFT   JOIN information_schema.tikv_region_status d
ON     (t.tidb_table_id=d.table_id and t.table_schema=d.db_name
        and (json_extract(a.kv,'$.index_id') is null or json_extract(a.kv,'$.index_id')=d.index_id)
        and a.key between ifnull(d.start_key,'0') and ifnull(d.end_key,'z'))
LEFT   JOIN information_schema.cluster_statements_summary c
ON     c.digest=IF(b.id=a.trx_id, a.sql_digest, b.current_sql_digest)
GROUP BY a.kv,type,b.id,sid
ORDER  BY `table#`,`row#`,type;
