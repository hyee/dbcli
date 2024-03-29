/*[[
  Show mutex sleep info. Usage: @@NAME [<sid>|<sql_id>|<event>|<idn>] [<inst_id>]
  Refer to Doc ID 1298015.1/1298471.1/1310764.1/2463140.1/31933451
  Possible parameters that impact the event:
    _column_tracking_level
    _optimizer_extended_stats_usage_control
    _optimizer_dsdir_usage_control
    _sql_plan_directive_mgmt_control
    _fast_cursor_reexecute
    _kgl_hot_object_copies => hot copies group by mod(sid,_kgl_hot_object_copies)+1
  
  idn: => v$sqlarea.hash_value 
       => v$db_object_cache.hash_value
       => v$object_dependency.from_hash/to_hash
       => x$kglob.knlnahsh

  Mainly used to diagnostic below events:
  =======================================
  * cursor: mutex X - A cursor is being parsed and is trying to get the cursor mutex in eXclusive mode.Happens when:
  *                   1) anonymous PL/SQL block is executed concurrently at high frequency
  *                   2) build new cursor or capture SQL bind data
  *                   3) update SQL stats
  * cursor: mutex S - A cursor is being parsed and is trying to get the cursor mutex in Share mode.Happens when:
  *                   1) high version count
  *                   2) examing the parent,cursor stats
  *                   3) wait for mutex X holder to release
  * cursor: pin X   - A cursor is being parsed and is trying to get the cursor pin in eXclusive mode
  *                   * reload cursor
  * cursor: pin S   - A cursor is being parsed and is trying to get the cursor pin in Share mode
  *                   * to update cursor ref count
  *                   * happens when the same SQL operator is executed concurrently at high frequency
  * cursor: pin S wait on X - A cursor is being parsed and has the cursor pin in Share but another session has it in eXclusive mode
  * library cache: mutex X - A library cache operation is being performed and is trying to get the library cache mutex in eXclusive mode, commonly happen on PL/SQL block or sequence
  * library cache: bucket mutex X    
  * library cache: dependency mutex X
  * library cache: mutex S - A library cache operation is being performed and is trying to get the library cache mutex in Share mode         


  Example Output:
  ================
    INST_ID        LAST_TIME           HASH    SLEEPS CNT     LOCATION      MUTEX_TYPE   OBJECT
    ------- ----------------------- ---------- ------ --- ---------------- ------------- -------------------
          2 2019-09-03 23:56:10.107 1011610568     25  25 kglhdgn2 106     Library Cache select type#,blocks
          2 2019-09-03 23:56:10.108 1736623433      5   5 kglpndl1  95     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      4   4 kgllkdl1  85     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      3   2 kglpnal1  90     Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      3   2 kglget2   2      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      2   2 kglpin1   4      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      1   1 kglpnal2  91     Library Cache SEG$
          3 2019-09-03 23:27:39.394 1736623433      3   3 kglpndl1  95     Library Cache SEG$
  --[[
        &V2: default={&instance}
        @OBJ_CACHE: {
                  11.2={(select owner to_owner,name to_name,TYPE,hash_value from_hash from v$db_object_cache)} 
                  default={(select a.*,
                    decode(to_type,
                          -1,'NONE',
                          0,'CURSOR',
                          1,'INDEX',
                          2,'TABLE',
                          3,'CLUSTER',
                          4,'VIEW',
                          5,'SYNONYM',
                          6,'SEQUENCE',
                          7,'PROCEDURE',
                          8,'FUNCTION',
                          9,'PACKAGE',
                          10,'NON-EXISTENT',
                          11,'PACKAGE BODY',
                          12,'TRIGGER',
                          13,'TYPE',
                          14,'TYPE BODY',
                          15,'OBJECT',
                          16,'USER',
                          17,'DBLINK',
                          18,'PIPE',
                          19,'TABLE PARTITION',
                          20,'INDEX PARTITION',
                          21,'LOB',
                          22,'LIBRARY',
                          23,'DIRECTORY',
                          24,'QUEUE',
                          25,'INDEX-ORGANIZED TABLE',
                          26,'REPLICATION OBJECT GROUP',
                          27,'REPLICATION PROPAGATOR',
                          28,'JAVA SOURCE',
                          29,'JAVA CLASS',
                          30,'JAVA RESOURCE',
                          31,'JAVA JAR',
                          32,'INDEX TYPE',
                          33,'OPERATOR',
                          34,'TABLE SUBPARTITION',
                          35,'INDEX SUBPARTITION',
                          36,'REPLICATED TABLE OBJECT',
                          37,'REPLICATION INTERNAL PACKAGE',
                          38,'CONTEXT POLICY',
                          39,'PUB SUB INTERNAL INFORMATION',
                          40,'LOB PARTITION',
                          41,'LOB SUBPARTITION',
                          42,'SUMMARY',
                          43,'DIMENSION',
                          44,'APP CONTEXT',
                          45,'STORED OUTLINE',
                          46,'RULESET',
                          47,'RESOURCE MANAGER PLAN',
                          48,'RESOURCE MANAGER CONSUMER GROUP',
                          49,'PENDING RESOURCE MANAGER PLAN',
                          50,'PENDING RESOURCE MANAGER CONSUMER GROUP',
                          51,'SUBSCRIPTION',
                          52,'LOCATION',
                          53,'REMOTE OBJECT',
                          54,'SNAPSHOT METADATA',
                          55,'XDB SCHEMA DATA',
                          56,'JAVA SHARED DATA',
                          57,'EDITION',
                          58,'TRANSFORMATION',
                          62,'RULE EVALUATION CONTEXT',
                          66,'SCHEDULER JOB',
                          67,'SCHEDULER PROGRAM',
                          68,'SCHEDULER CLASS',
                          69,'SCHEDULER WINDOW',
                          70,'MULTI-VERSIONED OBJECT',
                          72,'SCHEDULER GROUP',
                          74,'SCHEDULER SCHEDULE',
                          75,'SQL TUNING BASE OBJECT',
                          76,'HINTSET OBJECT',
                          77,'SCHEDULER GLOBAL ATTRIBUTE',
                          78,'SCHEDULER EARLIEST START TIME',
                          89,'SCHEDULER LIGHTWEIGHT JOB',
                          99,'OBJECT ID',
                          102,'CURSOR STATS',
                          109,'SECURITY CLASS',
                          110,'ACL',
                          111,'PDB',
                          115,'AUDIT POLICY',
                          126,'Optimizer Finding',
                          127,'Optimizer Directive Owner',
                          135,'USER PRIVILEGES',
                          145,'FED APP',
                          153,'CMP',
                          154,'Optimizer Expression Header',
                          155,'Optimizer Expresion Object',
                          158,'RUNTIME STATISTICS',
                          255,'NONE',
                          'INVALID TYPE:' || to_type) AS TYPE
                from v$object_dependency A)} 
                }
  --]]

]]*/

set feed off AUTOHIDE COL
PRO Current Mutex Waits
PRO ======================
SELECT DISTINCT *
FROM   TABLE(gv$(CURSOR( --
          SELECT /*+ordered use_hash(b)*/
                  userenv('instance') inst_id,
                  P1 idn, --_kgl_bucket_count
                  sid,
                  a.event,
                  nullif(trunc(p3 / power(16,8)),0) obj#,
                  decode(p1text,'cache id',p2,nullif(bitand(p3,power(2,16)-1),0)) LOC#,
                  nullif(decode(trunc(p2 / power(16,8)), 0, trunc(P2 / 65536), trunc(P2 / power(16,8))),0) holder_sid,
                  mod(p2,64436) refs,
                  a.sql_id,
                  decode(p1text,'idn',trim(regexp_replace(substr(b.to_name, 1, 200),'\s+',' ')) || 
                  CASE
                      WHEN b.to_name LIKE 'table_%' AND
                           regexp_like(regexp_substr(b.to_name, '[^\_]+', 1, 4), '^[0-9A-Fa-f]+$') THEN
                       ' (obj# ' || to_number(regexp_substr(b.to_name, '[^\_]+', 1, 4), 'xxxxxxxxxx') || ')'
                  END,c.parameter) name
          FROM   v$session a
          LEFT JOIN &OBJ_CACHE b
          ON  a.p1text='idn' AND  a.p1 = b.from_hash
          LEFT JOIN v$rowcache c
          ON  a.p1text='cache id' AND  a.p1 = c.cache#
          WHERE  nvl(:v1,'x') in('x',''||a.sid,a.sql_id,a.event,''||p1)
          AND   (p1text = 'idn' AND p2text = 'value' AND p3text = 'where'
                 OR  p1text = 'cache id')
          AND    userenv('instance') = nvl(:V2, userenv('instance')))));

PRO ASH Mutex Waits
PRO ======================
SELECT *
FROM   (SELECT *
        FROM   TABLE(gv$(CURSOR (
                          SELECT /*+ordered use_hash(b)*/
                                  DISTINCT a.*, 
                                  decode(p1text,'idn',b.type,c.type) type, 
                                  b.to_owner owner, 
                                  decode(p1text,'idn',trim(regexp_replace(substr(b.to_name, 1, 200),'\s+',' ')),c.parameter) name
                          FROM   (SELECT userenv('instance') inst_id,p1text,p1,
                                         obj#,loc#,
                                         sql_id,
                                         event,
                                         MAX(sample_time) last_time,
                                         COUNT(1) cnt
                                  FROM   (SELECT session_id sid,
                                                 sample_time,
                                                 event,
                                                 sql_id,
                                                 p1,p1text,
                                                 nvl(nullif(current_obj#,-1),
                                                     nullif(trunc(p3 / 4294967296),0)) obj#,
                                                 decode(p1text,'cache id',p2,nullif(bitand(p3,power(2,16)-1),0)) LOC#,
                                                 nullif(decode(trunc(p2 / 4294967296), 0, trunc(P2 / 65536), trunc(P2 / 4294967296)),0) holder_sid
                                          FROM   v$active_session_history
                                          WHERE  (p1text = 'idn' AND p2text = 'value' AND p3text = 'where'
                                              OR  p1text = 'cache id')
                                          AND    nvl(:v1,'x') in('x',''||session_id,sql_id,event,top_level_sql_id,''||p1)
                                          AND    userenv('instance') = nvl(:V2, userenv('instance')))
                                  GROUP  BY obj#,LOC#, p1,p1text,sql_id, event) a
                          LEFT JOIN &OBJ_CACHE b
                          ON  a.p1text='idn' AND  a.p1 = b.from_hash
                          LEFT JOIN v$rowcache c
                          ON  a.p1text='cache id' AND  a.p1 = c.cache#
                          )))
        ORDER  BY last_Time DESC)
WHERE  rownum <= 50;

col "Location|Wait,Location|Avg Wait" for usmhd2

PRO Mutex Sleep History
PRO =======================
SELECT * FROM (
    SELECT *
    FROM   TABLE(gv$(CURSOR(
        SELECT  /*+ordered use_hash(b)*/
                DISTINCT 
                userenv('instance') inst_id,
                a.*,
                c.SLEEPS "Location|Sleeps",
                c.WAIT_TIME "Location|Wait",
                round(c.WAIT_TIME/nullif(c.SLEEPS,0),2) "Location|Avg Wait",
                nvl(trim(regexp_replace(substr(to_name, 1, 200),'\s+',' ')),d.parameter) name
        FROM   (
            SELECT mutex_identifier idn,
                   CASE WHEN regexp_substr(:V1,'^\d+$')+0 IN (blocking_session,requesting_session) THEN
                        blocking_session||'/'||requesting_session
                   END "Holder|Waiter",
                   MAX(SLEEP_TIMESTAMP) LAST_TIME,
                   SUM(sleeps) sleeps,
                   COUNT(1) CNT,
                   MAX(gets) gets,
                   null p1,
                   mutex_type,
                   '|' "|",
                   location "Location|Name"
            FROM   v$mutex_sleep_history
            WHERE  userenv('instance') = nvl(:V2, userenv('instance'))
            AND    (:V1 IS NULL
                 OR regexp_substr(:V1,'^\d+$')+0 IN(-1,requesting_session,blocking_session,''||mutex_identifier)
                 OR instr(lower(:V1),lower(MUTEX_TYPE))>0)
            GROUP  BY mutex_identifier,location, mutex_type,
                      CASE WHEN regexp_substr(:V1,'^\d+$')+0 IN (blocking_session,requesting_session) THEN
                        blocking_session||'/'||requesting_session
                      END
        ) A 
        LEFT JOIN &OBJ_CACHE b
        ON   a.idn=b.from_hash
        LEFT JOIN v$rowcache d
        ON   a.mutex_type='Row Cache' AND a.p1=d.cache#
        LEFT JOIN v$mutex_sleep c
        ON a."Location|Name"=c.location AND a.mutex_type=c.mutex_type
    )))
    ORDER  BY LAST_TIME DESC)
WHERE  rownum <= 50;
