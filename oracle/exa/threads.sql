
/*[[List active cell threads. Usage: @@NAME [<minutes>] ]]*/
col r,gid noprint
set rownum on 

WITH db AS
 (SELECT /*+materialize*/b.*
  FROM   v$cell_state a,
         xmltable('/stats[@type="databasedes"]' passing xmltype(a.statistics_value) columns --
                  db VARCHAR2(128) path 'stat[@name="db name"]',
                  DATABASE_ID INT path 'stat[@name="db id"]') b
  WHERE  statistics_type = 'DBDES'),
stats AS
 (SELECT /*+ordered use_hash(a b)*/
         DATABASE_ID DBID,
         CON_ID,
         db,
         grouping_id(TRIM(SQL_ID), JOB_TYPE) gid,
         TRIM(SQL_ID) SQL_ID,
         JOB_TYPE,
         COUNT(1) aas,
         COUNT(DISTINCT CELL_NAME || ',' || THREAD_ID) threads,
         COUNT(DISTINCT INSTANCE_ID || ',' || SESSION_ID) sids
  FROM   v$cell_ofl_thread_history a
  LEFT   JOIN db b
  USING  (DATABASE_ID)
  WHERE  (TRIM(SQL_ID) IS NOT NULL OR lower(WAIT_STATE) LIKE 'working%')
  AND    SNAPSHOT_TIME >= SYSDATE - nvl(0 + :v1, 180) / 1440
  GROUP  BY DATABASE_ID, CON_ID, db, CUBE(TRIM(SQL_ID), JOB_TYPE)),
sqls AS
 (SELECT *
  FROM   (SELECT DBID,
                 CON_ID,
                 db,
                 gid,
                 '*' "*",
                 sql_id,
                 AAS,
                 THREADS,
                 SIDS,
                 first_Value(job_type || ' (' || aas || ')') over(PARTITION BY DBID, CON_ID, sql_id ORDER BY decode(gid, 1, 0, aas) DESC) top_job_type,
                 row_number() over(PARTITION BY DBID, CON_ID ORDER BY gid DESC, aas DESC) r
          FROM   stats a
          WHERE  sql_id IS NOT NULL)
  WHERE  gid > 0),
jobs AS
 (SELECT *
  FROM   (SELECT DBID,
                 CON_ID,
                 db,
                 gid,
                 '*' "*",
                 job_type,
                 AAS,
                 THREADS,
                 SIDS,
                 first_Value(nvl2(sql_id, sql_id || ' (' || aas || ')', NULL)) over(PARTITION BY DBID, CON_ID, job_type ORDER BY nvl2(sql_id, 0, 1), decode(gid, 1, 0, aas) DESC) top_sql_id,
                 row_number() over(PARTITION BY DBID, CON_ID ORDER BY gid DESC, aas DESC) r,
                 '|' "|"
          FROM   stats a
          WHERE  job_type IS NOT NULL)
  WHERE  gid > 0)
SELECT * FROM jobs A FULL JOIN sqls B USING (dbid, CON_ID, db, r, "*") ORDER BY sign(dbid) DESC, nvl(A.AAS, B.AAS) DESC;