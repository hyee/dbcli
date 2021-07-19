/*[[Show data lock contentions]]*/
col hash_key break -
COL "Trx|Time,Avg|Ela,Avg|Retry" for usmhd2
env headstyle initcap

SELECT substr(md5(a.key),1,13) hash_key,
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
FROM   information_schema.data_lock_waits a
JOIN   information_schema.tidb_trx b
ON     (b.id IN (a.current_holding_trx_id, a.trx_id))
LEFT   JOIN information_schema.cluster_statements_summary c
ON     c.digest=IF(b.id=a.trx_id, a.sql_digest, b.current_sql_digest)
GROUP BY a.key,type,b.id,sid
ORDER  BY hash_key,type