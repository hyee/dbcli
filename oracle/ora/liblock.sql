/*[[
    Check the holder of library cache objects. Usage: @@NAME {[<sid>|<object_name>] [inst_id]} [-u] [-w]
        -u: only show locked/pin objects within current_schema
        -w: only show the records that have waiters

    Sample Output:
    =============
    LOCK_TYPE  OBJECT_HANDLE      OBJECT_NAME     OBJECT_TYPE  HOLDING_SESSION HOLD_MODE   HOLDER_EVENT    HOLDER_SQL_ID WAITING_SESSION WAIT_MODE   WAITER_EVENT    WAITER_SQL_ID
    --------- ---------------- ------------------ ------------ --------------- --------- ----------------- ------------- --------------- --------- ----------------- -------------
    Pin       0000002BA3ABDC58 SYSTEM.MON_DB      PACKAGE      289,55303,@1    SHARED    PL/SQL lock timer 68gsknzub3950 325,16540,@2    EXCLUSIVE library cache pin cadwyvrgwdkvz
    Pin       0000002BA6A9B2E0 SYSTEM.MON_DB      PACKAGE      291,9375,@4     SHARED    PL/SQL lock timer ayxf7qwpa2mhj 325,16540,@2    EXCLUSIVE library cache pin cadwyvrgwdkvz
    Pin       0000002B6F8A7910 SYSTEM.MON_DB      PACKAGE      420,25372,@3    SHARED    PL/SQL lock timer 1bvuy52rj19k1 325,16540,@2    EXCLUSIVE library cache pin cadwyvrgwdkvz
    Pin       0000002B9339EC40 SYSTEM.MON_DB      PACKAGE      452,63939,@2    SHARED    PL/SQL lock timer d6a0tfanz9b15 325,16540,@2    EXCLUSIVE library cache pin cadwyvrgwdkvz
    Pin       0000002B6F8A7910 SYSTEM.MON_DB      PACKAGE      514,46802,@3    SHARED    PL/SQL lock timer 2gx6530gfrus4 325,16540,@2    EXCLUSIVE library cache pin cadwyvrgwdkvz
    Pin       0000002B7F939070 SYS.DBMS_LOCK      PACKAGE BODY 289,55303,@1    SHARED    PL/SQL lock timer 68gsknzub3950
    Pin       0000002B8A397CC0 SYS.DBMS_LOCK      PACKAGE      289,55303,@1    SHARED    PL/SQL lock timer 68gsknzub3950
    Pin       0000002BADFE08C0 SYS.DBMS_LOCK      PACKAGE BODY 291,9375,@4     SHARED    PL/SQL lock timer ayxf7qwpa2mhj
    Pin       0000002B8A404F60 SYS.DBMS_LOCK      PACKAGE      291,9375,@4     SHARED    PL/SQL lock timer ayxf7qwpa2mhj
    Pin       0000002B77A45788 SYS.DBMS_LOCK      PACKAGE BODY 420,25372,@3    SHARED    PL/SQL lock timer 1bvuy52rj19k1
    Pin       0000002B9ACEAD98 SYS.DBMS_LOCK      PACKAGE      420,25372,@3    SHARED    PL/SQL lock timer 1bvuy52rj19k1

    --[[
        &FILTER:  default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1}, w={w.sid is not null}
        &V2    :  default={&instance}
        @CHECK_ACCESS: gv$libcache_locks={gv$libcache_locks},Dba_Kgllock={(SELECT NULL inst_id,KGLLKTYPE TYPE,KGLLKUSE HOLDING_USER_SESSION,KGLLKHDL OBJECT_HANDLE,KGLLKMOD MODE_HELD,KGLLKREQ MODE_REQUESTED FROM Dba_Kgllock)}
        @OBJ_CACHE: {
                  12.1={(select owner to_owner,name to_name,addr to_address,TYPE from v$db_object_cache where instr(name,' ')=0)} 
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
    SELECT /*+materialize*/  * 
    FROM &GV
        SELECT /*+ordered no_merge(h) use_hash(h l d)*/DISTINCT 
                 l.type lock_type,
                 OBJECT_HANDLE handler,
                 MODE_REQUESTED,MODE_HELD,
                 DECODE(MODE_HELD, 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') held_mode,
                 DECODE(MODE_REQUESTED, 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') req_mode,
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
        AND    greatest(mode_held,mode_requested)>1
        JOIN   &OBJ_CACHE d
        ON     l.object_handle = d.to_address
        WHERE  d.to_name IS NOT NULL
        AND    userenv('instance')=nvl(''||:v2,userenv('instance'))
        AND    nvl(upper(:V1),'0') in(''||h.sid,'0',d.to_name,NULLIF(d.to_owner||'.','.')||d.to_name))
        )))
SELECT /*+no_expand*/distinct
       nvl(h.lock_type,w.lock_type) lock_type,
       nvl(h.handler,w.handler) object_handle, 
       nvl(h.object_name,w.object_name) object_name,
       nvl(h.object_type,w.object_type) object_type,
       h.session# holding_session, nvl(h.held_mode,w.held_mode) hold_mode,  
       h.event holder_event, h.sql_id holder_sql_id,
       w.session# waiting_session, nvl(w.req_mode,h.req_mode) wait_mode,
       w.event waiter_event, w.sql_id waiter_sql_id
FROM   lp h full JOIN lp w
ON     h.lock_type = w.lock_type and h.object_type=w.object_type and  h.mode_held>1 and w.mode_requested>1 and
      ((h.inst_id  = w.inst_id and h.handler     = w.handler) or
       (h.inst_id != w.inst_id and h.object_name = w.object_name))
WHERE  (h.mode_held>1 or w.mode_requested>1)
AND    (&filter) AND (&FILTER2)
ORDER BY nvl2(waiting_session,0,1),object_name,lock_type,holding_session,waiting_session;