/*[[Show object dependency, usage: ora deptree [-p|-c] [owner.]name 
    --[[
       &F2: P={d_obj#},C={p_obj#}
       &F1: P={p_obj#},C={d_obj#}
    --]]
]]*/
SET FEED OFF
WITH obj AS
 (SELECT --+materialize
         MAX(obj#) KEEP(DENSE_RANK FIRST ORDER BY DECODE(us.name,'PUBLIC','ZZZZ',us.name)) o,
         max(us.name) KEEP(DENSE_RANK FIRST ORDER BY DECODE(us.name,'PUBLIC','ZZZZ',us.name)) name
  FROM   sys.obj$ obj,sys.user$ us
  WHERE  us.name in (decode(instr(:V1,'.'),0,USER,upper(regexp_substr(:V1,'^[^\.]+'))),decode(instr(:V1,'.'),0,'PUBLIC','#'))
  AND    obj.name = upper(decode(instr(:V1,'.'),0,:V1,regexp_substr(:V1,'[^\.]+$')))
  AND    obj.owner#=us.user#
  AND    subname IS NULL),
res AS(
SELECT /*+ordered use_nl(dep op us) no_merge(dep) no_expand*/ 
       LPAD(' ',(lv-1)*4) ||us.name||'.'||op.name OBJECT_NAME,
          decode(op.type#,
              0,'NEXT OBJECT',
              1,'INDEX',
              2,'TABLE',
              3,'CLUSTER',
              4,'VIEW',
              5,'SYNONYM',
              6,'SEQUENCE',
              7,'PROCEDURE',
              8,'FUNCTION',
              9,'PACKAGE',
              11,'PACKAGE BODY',
              12,'TRIGGER',
              13,'TYPE',
              14,'TYPE BODY',
              19,'TABLE PARTITION',
              20,'INDEX PARTITION',
              21,'LOB',
              22,'LIBRARY',
              23,'DIRECTORY',
              24,'QUEUE',
              28,'JAVA SOURCE',
              29,'JAVA CLASS',
              30,'JAVA RESOURCE',
              32,'INDEXTYPE',
              33,'OPERATOR',
              34,'TABLE SUBPARTITION',
              35,'INDEX SUBPARTITION',
              40,'LOB PARTITION',
              41,'LOB SUBPARTITION',
              42,nvl((SELECT 'REWRITE EQUIVALENCE' FROM sys.sum$ s WHERE s.obj# = op.obj# AND bitand(s.xpflags, 8388608) = 8388608),'MATERIALIZED VIEW'),
              43,'DIMENSION',
              44,'CONTEXT',
              46,'RULE SET',
              47,'RESOURCE PLAN',
              48,'CONSUMER GROUP',
              51,'SUBSCRIPTION',
              52,'LOCATION',
              55,'XML SCHEMA',
              56,'JAVA DATA',
              57,'EDITION',
              59,'RULE',
              60,'CAPTURE',
              61,'APPLY',
              62,'EVALUATION CONTEXT',
              66,'JOB',
              67,'PROGRAM',
              68,'JOB CLASS',
              69,'WINDOW',
              72,'WINDOW GROUP',
              74,'SCHEDULE',
              79,'CHAIN',
              81,'FILE GROUP',
              82,'MINING MODEL',
              87,'ASSEMBLY',
              90,'CREDENTIAL',
              92,'CUBE DIMENSION',
              93,'CUBE',
              94,'MEASURE FOLDER',
              95,'CUBE BUILD PROCESS',
              'UNDEFINED')  object_type,
              decode(op.status, 0, 'N/A', 1, 'VALID', 'INVALID') STATUS,
              op.ctime,
              op.mtime
FROM   (select dep.*,obj.*,level lv 
        from obj,sys.dependency$ dep 
        CONNECT BY nocycle dep.&F2 = PRIOR dep.&F1 START WITH dep.&F2 =obj.o
        order siblings by dep.&F1) dep, sys.obj$ op,sys.user$ us
WHERE  dep.&F1 = op.obj#
AND    op.owner#=us.user#
AND    (us.name!='SYS' or dep.name in('SYS','PUBLIC')))
select * from res WHERE object_type NOT IN('UNDEFINED','SYNONYM')
