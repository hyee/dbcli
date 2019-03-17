
/*[[List active cell threads. Usage: @@NAME [<minutes>] [keyword] ]]*/
col gid,r noprint
set rownum on verify on feed off
var c refcursor

DECLARE
    c sys_refcursor;
BEGIN
    if :V2 IS NULL THEN
        open c for
            WITH db AS
                (SELECT /*+materialize*/b.*
                FROM   v$cell_state a,
                        xmltable('/stats[@type="databasedes"]' passing xmltype(a.statistics_value) columns --
                                db VARCHAR2(128) path 'stat[@name="db name"]',
                                DATABASE_ID INT path 'stat[@name="db id"]') b
                WHERE  statistics_type = 'DBDES'),
            stats AS
                (SELECT /*+ordered use_hash(a b) no_expand*/
                        DATABASE_ID DBID,
                        CON_ID,
                        nvl(db,' ') db,
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
                                row_number() over(PARTITION BY DBID, CON_ID ORDER BY sign(gid) desc, aas DESC) r
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
                                row_number() over(PARTITION BY DBID, CON_ID ORDER BY sign(gid) desc, aas DESC) r,
                                '|' "|"
                        FROM   stats a
                        WHERE  job_type IS NOT NULL)
                WHERE  gid > 0)
            SELECT * FROM jobs A FULL JOIN sqls B USING (dbid, CON_ID, db, r, "*") 
            ORDER BY sign(dbid) DESC, GREATEST( nvl(B.AAS,0),nvl(A.AAS,0)) desc,r;
    ELSE
        open c for 
            SELECT /*+ordered use_hash(a b) no_expand*/
                    DATABASE_ID DBID,
                    CON_ID,
                    JOB_TYPE,
                    TRIM(SQL_ID) SQL_ID,
                    WAIT_STATE,
                    COUNT(1) aas,
                    COUNT(DISTINCT CELL_NAME || ',' || THREAD_ID) threads,
                    COUNT(DISTINCT INSTANCE_ID || ',' || SESSION_ID) sids,
                    MIN(SNAPSHOT_TIME) FIRST_SEEN,
                    MAX(SNAPSHOT_TIME) LAST_SEEND
            FROM   v$cell_ofl_thread_history a
            WHERE  lower(JOB_TYPE||','||trim(sql_id)) like lower('%&v2%')
            AND    SNAPSHOT_TIME >= SYSDATE - nvl(0 + :v1, 180) / 1440
            GROUP  BY DATABASE_ID, CON_ID, JOB_TYPE,TRIM(SQL_ID),WAIT_STATE
            ORDER  BY AAS DESC;
    END IF;
    :c := c;
END;
/