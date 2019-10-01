/*[[This script needs SYS access to find out who are pinning the target object. Usage: @@NAME <ALL|LOCK|PIN|KEPT|object_name>]]*/
SELECT *
FROM   TABLE(GV$(CURSOR(
        SELECT kglnaown owner,
               kglnaobj object_name,
               decode(c.kglobtyp, 0, 'NEXT OBJECT', 1, 'INDEX', 2, 'TABLE', 3, 'CLUSTER',
                            4, 'VIEW', 5, 'SYNONYM', 6, 'SEQUENCE',
                            7, 'PROCEDURE', 8, 'FUNCTION', 9, 'PACKAGE',
                            11, 'PACKAGE BODY', 12, 'TRIGGER',
                            13, 'TYPE', 14, 'TYPE BODY',
                            19, 'TABLE PARTITION', 20, 'INDEX PARTITION', 21, 'LOB',
                            22, 'LIBRARY', 23, 'DIRECTORY', 24, 'QUEUE',
                            28, 'JAVA SOURCE', 29, 'JAVA CLASS', 30, 'JAVA RESOURCE',
                            32, 'INDEXTYPE', 33, 'OPERATOR',
                            34, 'TABLE SUBPARTITION', 35, 'INDEX SUBPARTITION',
                            40, 'LOB PARTITION', 41, 'LOB SUBPARTITION',
                            42, 'MATERIALIZED ZONEMAP/VIEW',
                            43, 'DIMENSION',
                            44, 'CONTEXT', 46, 'RULE SET', 47, 'RESOURCE PLAN',
                            48, 'CONSUMER GROUP',
                            51, 'SUBSCRIPTION', 52, 'LOCATION',
                            55, 'XML SCHEMA', 56, 'JAVA DATA',
                            57, 'EDITION', 59, 'RULE',
                            60, 'CAPTURE', 61, 'APPLY',
                            62, 'EVALUATION CONTEXT',
                            66, 'JOB', 67, 'PROGRAM', 68, 'JOB CLASS', 69, 'WINDOW',
                            72, 'SCHEDULER GROUP', 74, 'SCHEDULE', 79, 'CHAIN',
                            81, 'FILE GROUP', 82, 'MINING MODEL', 87, 'ASSEMBLY',
                            90, 'CREDENTIAL', 92, 'CUBE DIMENSION', 93, 'CUBE',
                            94, 'MEASURE FOLDER', 95, 'CUBE BUILD PROCESS',
                            100, 'FILE WATCHER', 101, 'DESTINATION',
                            111, 'CONTAINER',
                            114, 'SQL TRANSLATION PROFILE',
                            115, 'UNIFIED AUDIT POLICY',
                            144, 'MINING MODEL PARTITION',
                            148, 'LOCKDOWN PROFILE',
                            150, 'HIERARCHY',
                            151, 'ATTRIBUTE DIMENSION',
                            152, 'ANALYTIC VIEW',
                           'UNDEFINED') object_type,
               B.osuser,
               A.INST_ID,
               B.SID,
               kglobhs0 + kglobhs1 + kglobhs2 + kglobhs3 + kglobhs4 + kglobhs5 + kglobhs6 sharable_mem,
               kglhdldc loads,
               kglhdexc executions,
               kglhdlkc locks,
               kglobpc0 pins,
               decode(kglhdkmk, 0,'NO', 'YES') kept,
               c.KGLOBPROP HOT_FLAG, 
               kglhdclt child_latch#
        FROM   SYS.X$KGLPN A, V$SESSION B, SYS.X$KGLOB C
        WHERE  A.KGLPNUSE = B.SADDR
        AND    kglobtyp NOT IN (0,55) --exclude cursor and xdb
        AND    A.KGLPNHDL = C.KGLHDADR)))
WHERE  CASE nvl(upper(:V1), 'x')
           WHEN 'x'    THEN 1
           WHEN 'ALL'  THEN 1
           WHEN 'PIN'  THEN sign(pins)
           WHEN 'LOCK' THEN sign(locks)
           WHEN 'KEPT' THEN decode(kept,'YES',1)
           ELSE  sign(instr(upper(owner ||'.' || object_name || CHR(1) || object_type||CHR(1) ||osuser||CHR(1) ||sid), upper(:V1)))
        END = 1
ORDER  BY 1,2,3
