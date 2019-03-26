/*[[This script needs SYS access to find out who are pinning the target object. Usage: @@NAME <ALL|LOCK|PIN|KEPT|object_name>]]*/
SELECT *
FROM   (SELECT kglnaown owner,
               kglnaobj object_name,
               decode(bitand(kglobflg, 3),
                      0,'NOT LOADED',
                      2,'NON-EXISTENT',
                      3,'INVALID STATUS',
                      decode(kglobtyp,
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
                             39,'PUB_SUB',
                             40,'LOB PARTITION',
                             41,'LOB SUBPARTITION',
                             42,'SUMMARY',
                             43,'DIMENSION',
                             44,'APP CONTEXT',
                             45,'STORED OUTLINE',
                             46,'RULESET',
                             47,'RSRC PLAN',
                             48,'RSRC CONSUMER GROUP',
                             49,'PENDING RSRC PLAN',
                             50,'PENDING RSRC CONSUMER GROUP',
                             51,'SUBSCRIPTION',
                             52,'LOCATION',
                             53,'REMOTE OBJECT',
                             54,'SNAPSHOT METADATA',
                             55,'XDB',
                             56,'JAVA SHARED DATA',
                             57,'SECURITY PROFILE',
                             'INVALID TYPE')) object_type,
               B.osuser,
               B.INST_ID,
               B.SID,
               kglobhs0 + kglobhs1 + kglobhs2 + kglobhs3 + kglobhs4 + kglobhs5 + kglobhs6 sharable_mem,
               kglhdldc loads,
               kglhdexc executions,
               kglhdlkc locks,
               kglobpc0 pins,
               decode(kglhdkmk, 0,'NO', 'YES') kept,
               kglhdclt child_latch
        FROM   SYS.X$KGLPN A, GV$SESSION B, SYS.X$KGLOB C
        WHERE  A.KGLPNUSE = B.SADDR
        AND    A.INST_ID = B.INST_ID
        AND    A.INST_ID = C.INST_ID
        AND    kglobtyp NOT IN (0,55) --exclude cursor and xdb
        AND    A.KGLPNHDL = C.KGLHDADR)
WHERE  CASE nvl(upper(:V1), 'x')
           WHEN 'x'    THEN 1
           WHEN 'ALL'  THEN 1
           WHEN 'PIN'  THEN sign(pins)
           WHEN 'LOCK' THEN sign(locks)
           WHEN 'KEPT' THEN decode(kept,'YES',1)
           ELSE  sign(instr(upper(owner ||'.' || object_name || CHR(1) || object_type||CHR(1) ||osuser), upper(:V1)))
        END = 1
ORDER  BY 1,2,3
