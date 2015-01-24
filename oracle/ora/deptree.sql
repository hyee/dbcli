/*[[
    Show object dependency, usage: ora deptree [-c|-p] [-t|-l] [owner.]name 
    Options: 
       p: Show target object's depending objects(default)
       c: Show the objects that depend on target object
       t: Show dependence tree(Default)
       l: Show object list, instead of tree view
       
    --[[
       
       &F1  : P={p_obj#},C={d_obj#}
       &F2  : P={d_obj#},C={p_obj#}
       &F3  : P={rcon#},C={con#}
       &F4  : P={con#},C={rcon#}
       &CC  : T={1},L={0}
       &SRT : T={'9'},L={1}
       &DST : T={},L={DISTINCT}
    --]]
]]*/
SET FEED OFF
SET PRINTSIZE 10000
WITH obj AS
 (SELECT /*+materialize*/ * 
  FROM (
      SELECT --+no_expand
             object_id o,
             owner
      FROM   ALL_OBJECTS
      WHERE  owner in (decode(instr(:V1,'.'),0,USER,upper(regexp_substr(:V1,'^[^\.]+'))),decode(instr(:V1,'.'),0,'PUBLIC','#'))
      AND    object_name = upper(decode(instr(:V1,'.'),0,:V1,regexp_substr(:V1,'[^\.]+$')))
      AND    subobject_name IS NULL
      ORDER BY DECODE(OWNER,'PUBLIC','ZZZZZZ',OWNER),OBJECT_ID DESC)
  WHERE ROWNUM<2),
res AS(
SELECT --+ordered use_nl(dep op us) no_merge(dep) no_expand
       LPAD(' ',lv*2*&CC) ||us.name||'.'||op.name
          ||nvl2(con#,(select '('||name||')' from sys.con$ c where c.con#=dep.con#),'') OBJECT_NAME,
          op.obj# OBJECT_ID,
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
              op.ctime CREATED,
              op.mtime LAST_DDL
FROM   (
        SELECT o d_obj#,o p_obj#,0 lv,null con#,owner from obj WHERE &CC=1
        UNION ALL
        SELECT * FROM(
            SELECT d_obj#,p_obj#,level lv,null con#,owner
            FROM   obj,sys.dependency$ dep 
            CONNECT BY nocycle dep.&F2 = PRIOR dep.&F1 
            START WITH dep.&F2 =obj.o
            ORDER siblings by dep.&F1)
        UNION ALL
        SELECT obj#,robj#,level lv, &F3,owner
        FROM obj,sys.cdef$ a 
        START WITH obj#=obj.o and type#!=7
        CONNECT BY NOCYCLE &F4 = PRIOR &F3
        ) dep, 
        sys.obj$ op,sys.user$ us
WHERE  dep.&F1 = op.obj#
AND    op.owner#=us.user#
AND    ((us.name!='SYS' or dep.owner in('SYS','PUBLIC')) and (op.type#!=5 or us.name in('SYS','PUBLIC'))))
select lpad(rownum,5)||' | ' "#", a.* FROM (select &DST * from res WHERE object_type NOT IN('UNDEFINED') ORDER BY &SRT) A;
