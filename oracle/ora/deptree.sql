/*[[
    Show the object dependencies. Usage: @@NAME {[owner.]name [depth]} [-c|-p] [-t|-l]
    It reads the SYS internal tables(obj$/dependency$/con$/cdef$/ind$/sum$), so it requires the SYSDBA privilege,
    the SELECT ANY DICTIONARY privilege, or explicit SELECT grants on those tables.
    Since 12c, SELECT ANY DICTIONARY no longer covers a few sensitive SYS tables(default_pwd$, enc$, link$,
    user$, user_history$ and xs$verifiers), but the ones used here are still covered.

    Options:
        -p : Show the objects on which the target object depends(default)
        -c : Show the objects that depend on the target object
        -t : Show the dependency tree(default)
        -l : Show a flat object list instead of the tree view

    Sample Output:
    ==============
    ORCL> @@NAME dbms_workload_repository 3
          # OBJECT_NAME                                                 OBJECT_ID OBJECT_TYPE STATUS CREATED             LAST_DDL
    ------- ----------------------------------------------------------- --------- ----------- ------ ------------------- -------------------
        1 | SYS.DBMS_WORKLOAD_REPOSITORY                                     8460 PACKAGE     VALID  2011-08-28 22:12:37 2013-12-20 15:54:50
        2 |   SYS.STANDARD                                                   1253 PACKAGE     VALID  2011-08-28 22:11:03 2013-12-20 15:21:00
        3 |     SYS.DUAL                                                      116 TABLE       VALID  2011-08-28 22:10:49 2011-08-28 22:10:52
        4 |   SYS.AWRBL_DETAILS_TYPE_TABLE                                   6579 TYPE        VALID  2011-08-28 22:12:12 2013-12-20 15:25:32
        5 |     SYS.STANDARD                                                 1253 PACKAGE     VALID  2011-08-28 22:11:03 2013-12-20 15:21:00
        6 |     SYS.AWRBL_DETAILS_TYPE                                       6578 TYPE        VALID  2011-08-28 22:12:12 2013-12-20 15:25:32
        7 |       SYS.STANDARD                                               1253 PACKAGE     VALID  2011-08-28 22:11:03 2013-12-20 15:21:00
        8 |   SYS.AWRBL_METRIC_TYPE_TABLE                                    6583 TYPE        VALID  2011-08-28 22:12:12 2013-12-20 15:25:32
        9 |     SYS.STANDARD                                                 1253 PACKAGE     VALID  2011-08-28 22:11:03 2013-12-20 15:21:00
       10 |     SYS.AWRBL_METRIC_TYPE                                        6582 TYPE        VALID  2011-08-28 22:12:12 2013-12-20 15:25:32
       11 |       SYS.STANDARD                                               1253 PACKAGE     VALID  2011-08-28 22:11:03 2013-12-20 15:21:00
    --[[
       &F1  : P={p_obj#},C={d_obj#}
       &F2  : P={d_obj#},C={p_obj#}
       &F3  : P={rcon#},C={con#}
       &F31 : P={obj#},C={robj#}
       &F4  : P={con#},C={rcon#}
       &F5  : P={OBJ#},C={BO#}
       &CC  : T={1},L={0}
       &SRT : T={seq},L={1}
       &DST : T={},L={DISTINCT}
       @ARGS: 1
       @CHECK_ACCESS: sys.obj$/sys.dependency$/sys.con$/sys.cdef$/sys.ind$/sys.sum$={}
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
    v_curobj  INT := -1;
    v_seq     PLS_INTEGER := 0;
    v_level   PLS_INTEGER := 5;
    cur       SYS_REFCURSOR;
    PROCEDURE n(obj INT, lv INT, con INT := NULL) IS
        TYPE t IS TABLE OF INT;
        TYPE t_uniq IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(64);
        v_list  t;
        v_lv    t;
        v_con   t;
        v_uniq  t_uniq;
        v_key   VARCHAR2(64);
        v_stack VARCHAR2(200);
        v_bdy   INT;
    BEGIN
        IF lv > v_level THEN RETURN; END IF;
        IF &CC = 1 OR NOT v_founds.exists(obj) THEN
            v_stack := '<ROW><SEQ>' || v_seq || '</SEQ><OBJ>' || obj || '</OBJ><CON>' || con || '</CON><LV>' || lv || '</LV></ROW>';
            dbms_lob.writeappend(v_result, length(v_stack), v_stack);
            v_seq := v_seq + 1;
        END IF;
        v_counter := v_counter + 1;
        IF NOT v_founds.exists(obj) AND obj IS NOT NULL THEN
            v_founds(obj) := 1;
            SELECT /*+ordered index(dep1) use_nl(dep1 o2 o1)*/
                   max(&F2) INTO v_bdy
            FROM   sys.dependency$ dep1, sys.obj$ o2, sys.obj$ o1
            WHERE  dep1.d_obj# = o2.obj#
            AND    dep1.p_obj# = o1.obj#
            AND    to_char(o2.name) = to_char(o1.name)
            AND    to_char(o2.owner#) = to_char(o1.owner#)
            AND    to_char(o1.type#) IN('9', '13')
            AND    to_char(o2.type#) IN('11', '14')
            AND    dep1.&F1 = obj;

            SELECT /*+index(dep)*/ &F1, 1, to_number(NULL) con
            BULK   COLLECT INTO v_list, v_lv, v_con
            FROM   sys.dependency$ dep
            WHERE  &F2 IN(obj, v_bdy)
            AND    &F1 != obj
            UNION ALL
            SELECT /*+QB_NAME(A) CONNECT_BY_FILTERING(@A)*/
                   decode('&F1', 'p_obj#', nvl(robj#, obj#), obj#), level lv, &F3
            FROM   sys.cdef$ a
            WHERE  robj# IS NOT NULL
            START WITH &F31 = obj AND type# != 7
            CONNECT BY NOCYCLE a.&F4 = PRIOR a.&F3 -- AND robj# is not null
            UNION ALL
            SELECT decode('&F1', 'p_obj#', bo#, obj#), 1 lv, NULL
            FROM   sys.ind$ a
            WHERE  a.&F5 = obj;

            FOR i IN 1 .. v_list.count LOOP
                v_key := nvl(v_list(i), -1) || '/' || v_lv(i) || '/' || nvl(v_con(i), -1);
                IF NOT v_uniq.exists(v_key) THEN
                    v_uniq(v_key) := 1;
                    n(v_list(i), lv + v_lv(i), v_con(i));
                END IF;
            END LOOP;
        END IF;
    END;
BEGIN
    v_objid := :object_id;
    v_owner := :object_owner;

    IF regexp_like(:V2, '^\s*\d+\s*$') THEN
        v_level := to_number(:V2);
    ELSIF :V2 IS NOT NULL THEN
        raise_application_error(-20001, 'Invalid depth: ' || :V2);
    END IF;

    dbms_lob.createtemporary(v_result, TRUE);
    dbms_output.enable(NULL);
    dbms_lob.writeappend(v_result, 8, '<ROWSET>');
    n(v_objid, 0);
    dbms_lob.writeappend(v_result, 9, '</ROWSET>');

    OPEN :cur FOR --
    WITH dep AS(
        SELECT /*+materialize*/
               extractvalue(column_value, '/ROW/SEQ') + 0 seq,
               extractvalue(column_value, '/ROW/OBJ') + 0 obj,
               extractvalue(column_value, '/ROW/CON') + 0 con,
               extractvalue(column_value, '/ROW/LV')  + 0 lv
        FROM   TABLE(xmlsequence(extract(xmltype(v_result), '/ROWSET/ROW')))
    ),
    res AS(
        SELECT --+ordered use_nl(dep op us) index(us) no_expand
               lpad(' ', lv * 2 * &CC) || us.username || '.' || op.name
                  || nvl2(con, (SELECT '(' || name || ')' FROM sys.con$ c WHERE c.con# = dep.con), '') OBJECT_NAME,
               op.obj# OBJECT_ID,
               decode(op.type#,
                      0, 'NEXT OBJECT',
                      1, 'INDEX',
                      2, 'TABLE',
                      3, 'CLUSTER',
                      4, 'VIEW',
                      5, 'SYNONYM',
                      6, 'SEQUENCE',
                      7, 'PROCEDURE',
                      8, 'FUNCTION',
                      9, 'PACKAGE',
                      11, 'PACKAGE BODY',
                      12, 'TRIGGER',
                      13, 'TYPE',
                      14, 'TYPE BODY',
                      19, 'TABLE PARTITION',
                      20, 'INDEX PARTITION',
                      21, 'LOB',
                      22, 'LIBRARY',
                      23, 'DIRECTORY',
                      24, 'QUEUE',
                      28, 'JAVA SOURCE',
                      29, 'JAVA CLASS',
                      30, 'JAVA RESOURCE',
                      32, 'INDEXTYPE',
                      33, 'OPERATOR',
                      34, 'TABLE SUBPARTITION',
                      35, 'INDEX SUBPARTITION',
                      40, 'LOB PARTITION',
                      41, 'LOB SUBPARTITION',
                      42, nvl((SELECT 'REWRITE EQUIVALENCE' FROM sys.sum$ s WHERE s.obj# = op.obj# AND bitand(s.xpflags, 8388608) = 8388608), 'MATERIALIZED VIEW'),
                      43, 'DIMENSION',
                      44, 'CONTEXT',
                      46, 'RULE SET',
                      47, 'RESOURCE PLAN',
                      48, 'CONSUMER GROUP',
                      51, 'SUBSCRIPTION',
                      52, 'LOCATION',
                      55, 'XML SCHEMA',
                      56, 'JAVA DATA',
                      57, 'EDITION',
                      59, 'RULE',
                      60, 'CAPTURE',
                      61, 'APPLY',
                      62, 'EVALUATION CONTEXT',
                      66, 'JOB',
                      67, 'PROGRAM',
                      68, 'JOB CLASS',
                      69, 'WINDOW',
                      72, 'WINDOW GROUP',
                      74, 'SCHEDULE',
                      79, 'CHAIN',
                      81, 'FILE GROUP',
                      82, 'MINING MODEL',
                      87, 'ASSEMBLY',
                      90, 'CREDENTIAL',
                      92, 'CUBE DIMENSION',
                      93, 'CUBE',
                      94, 'MEASURE FOLDER',
                      95, 'CUBE BUILD PROCESS',
                      'UNDEFINED') object_type,
               decode(op.status, 0, 'N/A', 1, 'VALID', 'INVALID') STATUS,
               op.ctime CREATED,
               op.mtime LAST_DDL,
               dep.seq seq
        FROM   dep, sys.obj$ op,
               (SELECT user_id, username FROM dba_users UNION ALL SELECT 1, 'PUBLIC' FROM dual) us
        WHERE  dep.obj = op.obj#
        AND    op.owner# = us.user_id
        AND   (us.username NOT IN('SYS', 'SYSTEM', 'PUBLIC') OR v_owner IN('SYS', 'SYSTEM', 'PUBLIC'))
        AND   (op.type# != 5 OR us.username IN('SYS', 'SYSTEM', 'PUBLIC')))
    SELECT lpad(rownum, 5) || ' | ' "#", a.*
    FROM   (SELECT &DST object_name, object_id, object_type, status, created, last_ddl
            FROM   res
            WHERE  object_type NOT IN('UNDEFINED')
            ORDER  BY &SRT) A;

EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('Cannot find target object!');
END;
/
