/*[[Show table size. Usage: tabsize [keyword] ]]*/
set feed off
SELECT CHAR(DATE(t.stats_time)) || ' ' || CHAR(TIME(t.stats_time)) AS statstime,
       trim(t.tabschema) || '.' || trim(t.tabname) AS tabname,
       card AS rows_per_table,
       DECIMAL(FLOAT(t.npages) / (1024 / (b.pagesize / 1024)), 9, 2) AS used_mb,
       DECIMAL(FLOAT(t.fpages) / (1024 / (b.pagesize / 1024)), 9, 2) AS allocated_mb
  FROM syscat.tables t, syscat.tablespaces b
 WHERE t.tbspace = b.tbspace
 AND   (:V1 IS NULL OR trim(t.tabschema) || '.' || t.tabname like upper('%'||:V1||'%'))
 WITH ur;