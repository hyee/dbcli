/*[[
    Show object dependency, usage: @@NAME {[owner.]name [depth]} [-c|-p] [-t|-l] 
    Options:
       p: Show target object's depending objects(default)
       c: Show the objects that depend on target object
       t: Show dependence tree(Default)
       l: Show object list, instead of tree view

    --[[
       &F1  : P={p_obj#},C={d_obj#}
       &F2  : P={d_obj#},C={p_obj#}
       &F3  : P={rcon#},C={con#}
       &F31 : P={obj#},C={robj#}
       &F4  : P={con#},C={rcon#}
       &F5  : P={OBJ#},C={BO#}
       &CC  : T={1},L={0}
       &SRT : T={'9'},L={1}
       &DST : T={},L={DISTINCT}
       @CHECK_ACCESS: sys.obj$/sys.dependency$={1}
    --]]
]]*/

ora _find_object &V1

SET FEED OFF
SET PRINTSIZE 10000
VAR CUR REFCURSOR

DECLARE
    TYPE t IS TABLE OF VARCHAR2(1) INDEX BY VARCHAR2(22);
    v_founds  t;
    v_result  CLOB;
    v_objid   INT;
    v_owner   VARCHAR2(128);
    v_counter PLS_INTEGER := 0;
    v_curobj  INT:=-1;
    v_level   PLS_INTEGER := nvl(to_number(:V2),5);
    cur       SYS_REFCURSOR;
    PROCEDURE n(obj INT, lv INT, con INT:=NULL) IS
        TYPE t IS TABLE OF INT;
        v_list  t;
        v_lv    t;
        v_con   t;
        v_stack VARCHAR2(200);
        v_bdy   INT;
    BEGIN
        IF lv>v_level THEN RETURN; END IF;
        IF &CC =1 OR NOT v_founds.exists(obj) THEN
            v_stack := '<ROW><OBJ>' || obj||  '</OBJ><CON>' || con ||'</CON><LV>' || lv || '</LV></ROW>';
            dbms_lob.writeappend(v_result, LENGTH(v_stack), v_stack);
        END IF;
        v_counter := v_counter + 1;
        IF NOT v_founds.exists(obj) AND obj IS NOT NULL THEN
            v_founds(obj) := 1;
            --IF '&F2' !='p_obj#' THEN
                SELECT /*+ordered index(dep1) use_nl(dep1 o2 o1)*/
                       MAX(&F2) INTO v_bdy
                FROM   sys.dependency$ dep1, sys.obj$ o2, sys.obj$ o1
                WHERE  dep1.d_obj# = o2.obj#
                AND    dep1.p_obj# = o1.obj#
                AND    to_char(o2.name)  = to_char(o1.name)
                AND    to_char(o2.owner#) = to_char(o1.owner#)
                AND    to_char(o1.type#) IN ('9', '13')
                AND    to_char(o2.type#) IN ('11', '14')
                AND    dep1.&F1 = obj;
            --END IF;

            SELECT /*+index(dep)*/ &F1,1, to_number(null) con
            BULK   COLLECT INTO  v_list,v_lv,v_con
            FROM   sys.dependency$ dep
            WHERE  &F2 in(obj,v_bdy)
            AND    &F1 !=obj
            UNION ALL
            SELECT  /*+QB_NAME(A) CONNECT_BY_FILTERING(@A) */
                   DECODE('&F1','p_obj#',nvl(robj#,obj#),obj#),level lv, &F3
            FROM   sys.cdef$ a
            WHERE  robj# is not null
            START WITH &F31=obj and type#!=7
            CONNECT BY NOCYCLE a.&F4 = PRIOR a.&F3-- AND robj# is not null
            UNION ALL
            SELECT DECODE('&F1','p_obj#',BO#,obj#),1 lv, null
            FROM   sys.ind$ a
            WHERE  a.&F5=obj;

            FOR i IN 1 .. v_list.count LOOP
                n(v_list(i), lv + v_lv(i),v_con(i));
            END LOOP;
        END IF;
    END;
BEGIN
    v_objid := :object_id;
    v_owner := :object_owner;

    dbms_lob.createtemporary(v_result, TRUE);
    dbms_output.enable(NULL);
    dbms_lob.writeappend(v_result, 8, '<ROWSET>');
    n(v_objid, 0);
    dbms_lob.writeappend(v_result, 9, '</ROWSET>');

    OPEN :cur FOR --
    WITH dep AS(
       SELECT /*+materialize*/
              EXTRACTVALUE(COLUMN_VALUE,'/ROW/OBJ')+0 obj,
              EXTRACTVALUE(COLUMN_VALUE,'/ROW/CON')+0 con,
              EXTRACTVALUE(COLUMN_VALUE,'/ROW/LV')+0  lv
       FROM TABLE(XMLSEQUENCE(EXTRACT(XMLTYPE(v_result),'/ROWSET/ROW')))
    ) ,
    res AS(
        SELECT --+ordered use_nl(dep op us) index(us) no_expand
               LPAD(' ',lv*2*&CC) ||us.username||'.'||op.name
                  ||nvl2(con,(select '('||name||')' from sys.con$ c where c.con#=dep.con),'') OBJECT_NAME,
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
        FROM   dep,sys.obj$ op,dba_users us
        WHERE  dep.obj = op.obj#
        AND    op.owner#=us.user_id
        AND   (us.username NOT IN('SYS','SYSTEM','PUBLIC') or v_owner in('SYS','SYSTEM','PUBLIC'))
        AND   (op.type#!=5 or us.username in('SYS','SYSTEM','PUBLIC')))
    select lpad(rownum,5)||' | ' "#", a.* FROM (select &DST * from res WHERE object_type NOT IN('UNDEFINED') ORDER BY &SRT) A;

EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('Cannot find target object!');
END;
/
