/*[[Show data lock contentions]]*/

SELECT b.id,
       b.state,
       b.waiting_start_time,
       b.all_sql_digests,
       c.digest_text sql_text
FROM   information_schema.data_lock_waits a
JOIN   information_schema.tidb_trx b
ON     (b.id IN (a.current_holding_trx_id, a.trx_id))
LEFT   JOIN information_schema.cluster_statements_summary c
ON     (b.all_sql_digests = c.digest)\G