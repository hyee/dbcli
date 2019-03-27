/*[[
Check the holder of library cache objects. Usage: @@NAME {[<sid>|<object_name>] [inst_id]} [-u] [-w]
    -u: only show locked/pin objects within current_schema
    --[[
        &FILTER:  default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1}, w={w.sid is not null}
        &V2    :  default={&instance}
        @CHECK_ACCESS: gv$libcache_locks={gv$libcache_locks},Dba_Kgllock={(SELECT NULL inst_id,KGLLKTYPE TYPE,KGLLKUSE HOLDING_USER_SESSION,KGLLKHDL OBJECT_HANDLE,KGLLKMOD MODE_HELD,KGLLKREQ MODE_REQUESTED FROM Dba_Kgllock)}
        @OBJ_CACHE: {
                  12.1={(select owner to_owner,name to_name,addr to_address,TYPE from v$db_object_cache)} 
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
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
    --]]    
]]*/
set feed off verify on

WITH LP AS (
    SELECT * FROM &GV
        SELECT /*+ordered no_merge(h) use_hash(l d)*/DISTINCT 
                 l.type lock_type,
                 OBJECT_HANDLE handler,
                 CASE WHEN MODE_REQUESTED > 1 THEN 'WAIT' ELSE 'HOLD' END TYPE,
                 DECODE(GREATEST(MODE_REQUESTED, MODE_HELD), 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') lock_mode,
                 nullif(d.to_owner || '.', '.') || d.to_name object_name,
                 h.sid || ',' || h.serial# || ',@' || USERENV('instance') session#,
                 d.type object_type,
                 h.event,
                 h.sql_id,
                 h.sid,d.to_name obj, USERENV('instance') inst_id
        FROM    v$session h
        JOIN   (SELECT KGLLKTYPE TYPE,
                       KGLLKUSE  HOLDING_USER_SESSION,
                       KGLLKHDL  OBJECT_HANDLE,
                       KGLLKMOD  MODE_HELD,
                       KGLLKREQ  MODE_REQUESTED
                FROM   Dba_Kgllock) l
        ON     l.holding_user_session = h.saddr
        JOIN   &OBJ_CACHE d
        ON     l.object_handle = d.to_address
        WHERE  greatest(mode_held, mode_requested) > 1
        AND    d.to_owner IS NOT NULL
        AND    userenv('instance')=nvl(''||:v2,userenv('instance'))
        AND    nvl(upper(:V1),'0') in(''||h.sid,'0',d.to_name,NULLIF(d.to_owner||'.','.')||d.to_name))
        )))
SELECT /*+no_expand*/distinct
       h.lock_type,h.handler object_handle, h.object_name,h.object_type,
       h.session# holding_session, h.lock_mode hold_mode,  
       h.event holder_event, h.sql_id holder_sql_id,
       w.session# waiting_session, w.lock_mode wait_mode,
       w.event waiter_event, w.sql_id waiter_sql_id
FROM   lp h LEFT JOIN lp w
ON     h.lock_type = w.lock_type and h.object_type=w.object_type and w.type = 'WAIT' and
      ((h.inst_id  = w.inst_id and h.handler     = w.handler) or
       (h.inst_id != w.inst_id and h.object_name = w.object_name))
WHERE  h.type='HOLD'
AND  (&filter) AND (&FILTER2)
AND   h.type = 'HOLD' 
ORDER BY nvl2(waiting_session,0,1),object_name,lock_type,holding_session,waiting_session;