
/*[[Extract the event information whose parameter1='idn'. Usage: @@NAME <idn>|<sql_id> [-a]
    The idn information can also be extracted by gv$db_object_cache.hash_value since 11g
    Options:
        -a:  List the target object in all heaps, otherwise will only list the parent cursor
    Reference: https://github.com/xtender/xt_scripts/blob/master/idn.sql
    --[[
        @ver: 12.2={,KGLOBLCT LOCKED_TOTAL,KGLOBPCT PINNED_TOTAL} default={,KGLOBT23 LOCKED_TOTAL,KGLOBT24 PINNED_TOTAL}
    --]]
]]*/

SET FEED OFF VERIFY ON
VAR C REFCURSOR
    DECLARE
    V1 VARCHAR2(64):= :V1;
    V2 INT:=0+regexp_substr(v1,'^\d+$');
BEGIN
    OPEN :C FOR
    SELECT * FROM TABLE(GV$(CURSOR(
        SELECT  inst_id,kglnahsh idn,ob.KGLOBT03 sql_id
               , ob.kglhdnsd as namespace
               , decode(kglobtyp,
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
                              'INVALID TYPE:' || kglobtyp) AS TYPE 
               ,decode(bitand(kglobflg, 3)
                         , 0, 'NOT LOADED'
                         , 2, 'NON - EXISTENT'
                         , 3, 'INVALID STATUS'
                         , decode( ob.kglobtyp, 
                                         0, 'CURSOR'                , 1, 'INDEX'                 , 2, 'TABLE'
                                       , 3, 'CLUSTER'               , 4, 'VIEW'                  , 5, 'SYNONYM'
                                       , 6, 'SEQUENCE'              , 7, 'PROCEDURE'             , 8, 'FUNCTION'
                                       , 9, 'PACKAGE'               , 10,'NON-EXISTENT'          , 11,'PACKAGE BODY'
                                       , 12,'TRIGGER'               , 13,'TYPE'                  , 14,'TYPE BODY'
                                       , 15,'OBJECT'                , 16,'USER'                  , 17,'DBLINK'
                                       , 18,'PIPE'                  , 19,'TABLE PARTITION'       , 20,'INDEX PARTITION'
                                       , 21,'LOB'                   , 22,'LIBRARY'               , 23,'DIRECTORY'
                                       , 24,'QUEUE'                 , 25,'INDEX-ORGANIZED TABLE' , 26,'REPLICATION OBJECT GROUP'
                                       , 27,'REPLICATION PROPAGATOR', 28,'JAVA SOURCE'           , 29,'JAVA CLASS'
                                       , 30,'JAVA RESOURCE'         , 31,'JAVA JAR'
                                    , 'INVALID TYPE:'||ob.KGLOBTYP
                          )
                ) as ftype
               ,trim(',' from decode(kglobhs0,0,'','0,')||decode(kglobhs1,0,'','1,')||decode(kglobhs2,0,'','2,')||decode(kglobhs3,0,'','3,')||decode(kglobhs4,0,'','4,')||decode(kglobhs5,0,'','5,')||decode(kglobhs6,0,'','6,')||decode(kglobhs7,0,'','7,')) heaps
               ,kglobhs0+kglobhs1+kglobhs2+kglobhs3+kglobhs4+kglobhs5+kglobhs6+kglobhs7 as SHARABLE_MEM
               ,kglhdldc                                                       as LOADS 
               ,kglhdexc                                                       as EXECUT
               ,kglhdlkc                                                       as LOCKS 
               ,kglobpc0                                                       as PINS  
               ,decode(kglhdkmk,0,'NO',' YES')                                 as KEPT  
               ,kglhdclt                                                       as CHILD_LATCH
               ,kglhdivc                                                       as INVALIDATIONS
               ,DECODE(KGLHDLMD
                          ,0   ,'NONE'
                          ,1   ,'NULL'
                          ,2   ,'SHARED'
                          ,3   ,'EXCLUSIVE'
                          ,'UNKOWN')                                           as LOCK_MODE
               ,DECODE(KGLHDPMD
                          ,0   ,'NONE'
                          ,1   ,'NULL'
                          ,2   ,'SHARED'
                          ,3   ,'EXCLUSIVE'
                          ,'UNKOWN')                                           as PIN_MODE
               ,DECODE(KGLOBSTA
                          ,1   ,'VALID'
                          ,2   ,'VALID_AUTH_ERROR'
                          ,3   ,'VALID_COMPILE_ERROR'
                          ,4   ,'VALID_UNAUTH'
                          ,5   ,'INVALID_UNAUTH'
                          ,6   ,'INVALID'
                          ,'UNKOWN')                                           as STATUS
               ,KGLNAHSV as FULL_HASH_VALUE
               ,SUBSTR(TO_CHAR(KGLNATIM,'YYYY-MM-DD/HH24:MI:SS'),1,19)         as "TIMESTAMP"
               ,SUBSTR(TO_CHAR(KGLNAPTM,'YYYY-MM-DD/HH24:MI:SS'),1,19)         as "PREVIOUS_TIMESTAMP"
               &ver
               ,ob.kglnaown    owner
               ,ob.KGLNAOBJ    object
               ,ob.KGLFNOBJ    fn_obj
        FROM   (select * from sys.x$kglob where kglnahsh=v2
                union all 
                select * from sys.x$kglob where KGLOBT03=v1) ob
        WHERE  (ob.kglhdadr = ob.kglhdpar or lower(:v2)='-a')
        AND    rownum <=10
    )));
END;
/