/*[[
    markhot/umarkhot target object. Usage: @@NAME {[<owner>.]<object_name>}|<sql_id>|<hash_value> [-u]
    relative parameter: _kgl_hot_object_copies => hot copies group by mod(sid,_kgl_hot_object_copies)+1, shoud be less than CPU cores
   -u : ummarkhot
    --[[
        &mark: default={markhot} u={unmarkhot}
        @check_access_x: sys.x$kglob={1} default={0}
    --]]
]]*/
set feed off
ora _find_object "&V1" 1
var c refcursor;
DECLARE
   own VARCHAR2(128):=:object_owner;
   nam VARCHAR2(128):=:object_name;
   typ VARCHAR2(128):=:object_type;
   oid INT          :=:object_id;
   sq  VARCHAR2(128):=:V1;
   hv  VARCHAR2(64);
   hs  INT := regexp_substr(sq,'^\d+$');
   ns  INT;
   nn  VARCHAR2(128);
BEGIN
    IF sq IS NULL THEN
        OPEN :c FOR q'~
            SELECT *
            FROM   (SELECT idn,obj#,
                           SUM(cnt) AAS,
                           SUM(parses) parses,
                           owner,name
                    FROM   TABLE(gv$(CURSOR (
                          SELECT /*+ordered use_hash(b)*/
                                  a.*, 
                                  b.type, 
                                  b.owner, 
                                  b.name
                          FROM   (SELECT userenv('instance') inst_id,p1 idn,
                                         obj#,loc#,
                                         sql_id,
                                         event,
                                         MAX(sample_time) last_time,
                                         COUNT(1) cnt,
                                         COUNT(CASE WHEN IN_PARSE='Y' THEN 1 END) parses
                                  FROM   (SELECT session_id sid,
                                                 sample_time,
                                                 event,
                                                 sql_id,
                                                 p1,
                                                 in_parse,
                                                 nullif(trunc(p3 / 4294967296),0) obj#,
                                                 nullif(trunc(mod(p3,power(16,8))/power(16,4)),0) LOC#,
                                                 nullif(decode(trunc(p2 / 4294967296), 0, trunc(P2 / 65536), trunc(P2 / 4294967296)),0) holder_sid
                                          FROM   v$active_session_history
                                          WHERE  p1text = 'idn'
                                          AND    p2text = 'value'
                                          AND    p3text = 'where'
                                          AND    sample_time+0>sysdate-3/24)
                                  GROUP  BY obj#,LOC#, p1, sql_id, event) a,
                                  v$db_object_cache b
                          WHERE  a.idn = b.hash_value)))
                    GROUP BY idn,obj#,owner,name
                    ORDER  BY AAS DESC)
            WHERE  rownum <= 50~';
    ELSIF own IS NULL THEN
        IF hs IS NULL THEN
            SELECT hs INTO hs
            FROM (
                SELECT trunc(MOD(SUM(p * power(32, len - lv)) OVER(ORDER BY lv),pow)) hs
                FROM   (SELECT level lv,
                               length(sq) len,
                               instr('0123456789abcdfghjkmnpqrstuvwxyz', substr(sq, level, 1)) - 1 p,
                               power(2, 32) pow
                        FROM dual 
                        connect by level<=length(sq))
                ORDER BY lv desc)
            WHERE ROWNUM=1;
            IF hs IS NULL THEN
                raise_application_error(-20001,'Cannot find target object or SQL Id: '||sq);
            END IF;
        END IF;
        $IF &check_access_x=1 $THEN
            SELECT max(full_hash),max(namespace#),max(namespace)
            INTO   hv,ns,nn
            FROM   TABLE(GV$(CURSOR(
                SELECT KGLNAHSV full_hash,kglhdnsp namespace#,KGLHDNSD namespace
                FROM   sys.x$kglob
                WHERE  KGLNAHSH=hs
                AND    ROWNUM<2
            ))) WHERE ROWNUM<2;
        $ELSE
            $IF DBMS_DB_VERSION.VERSION<12 $THEN
                raise_application_error(-20001,'Only support Oracle 12c+');
            $END
            SELECT MAX(full_hash_value),
                   MAX(namespace),
                   DECODE(MAX(namespace), --x$kglst
                        'SQL AREA',0,
                        'TABLE/PROCEDURE',1,
                        'BODY',2,
                        'TRIGGER',3,
                        'INDEX',4,
                        'CLUSTER',5,
                        'PIPE',7,
                        'LOB',8,
                        'DIRECTORY',9,
                        'QUEUE',10,
                        'JAVA SOURCE',13,
                        'JAVA RESOURCE',14,
                        'PUB SUB INTERNAL INFORMATION',18,
                        'APP CONTEXT',21,
                        'RULESET',23,
                        'RESOURCE MANAGER',24,
                        'XML SCHEMA',25,
                        'SUBSCRIPTION',28,
                        'JAVA DATA',32,
                        'TRANSFORMATION',34,
                        'RULE',36,
                        'RULE EVALUATION CONTEXT',38,
                        'MULTI-VERSION OBJECT FOR TABLE',45,
                        'MULTI-VERSION OBJECT FOR INDEX',48,
                        'SCHEDULER GLOBAL ATTRIBUTE',51,
                        'RESOURCE MANAGER CDB',52,
                        'TEMPORARY TABLE',53,
                        'TEMPORARY INDEX',55,
                        'EDITION',64,
                        'DBLINK',69,
                        'OBJECT ID',72,
                        'SCHEMA',73,
                        'DBINSTANCE',74,
                        'SQL AREA STATS',75,
                        'ACCOUNT_STATUS',79,
                        'SQL AREA BUILD',82,
                        'AUDIT POLICY',93,
                        'OPTIMIZER FINDING',103,
                        'OPTIMIZER DIRECTIVE OWNER',104,
                        'USER PRIVILEGE',112,
                        'KZP Exempt Access Policy list',115,
                        'Last_Successful_Logon_Time',127,
                        'FED APP',129,
                        'APP STATE',130,
                        'CMP',136,
                        'OPTIMIZER EXPRESSION HEADER',137,
                        'OPTIMIZER EXPRESSION OBJECT',138,
                        'INMEMORY SERVICE METADATA',140,
                        'RUNTIME STATISTICS',141,
                        'INDEX',146,
                        'CLUSTER',148,
                        'TRIGGER',157,
                        'DBLINK',162,
                        'PIPE',163,
                        'LOB',166,
                        'DIRECTORY',168,
                        'QUEUE',169,
                        'JAVA SOURCE',173,
                        'JAVA RESOURCE',175,
                        'INDEX',177,
                        'PUB SUB INTERNAL INFORMATION',184,
                        'APP CONTEXT',189,
                        'RULESET',191,
                        'SUBSCRIPTION',196,
                        'EDITION',202,
                        'TRANSFORMATION',203,
                        'RULE',204,
                        'RULE EVALUATION CONTEXT',207,
                        'SCHEDULER GLOBAL ATTRIBUTE',222,
                        'OBJECT ID',244,
                        'AUDIT POLICY',260,
                        'KZP Exempt Access Policy list',283,
                        'FED APP',290,
                        'CMP',298,
                        'INMEMORY SERVICE METADATA',302,
                        'RUNTIME STATISTICS',303)
            INTO   hv,nn,ns
            FROM   gv$db_object_cache
            WHERE  HASH_VALUE=hs
            AND    ROWNUM<2;
        $END
        IF hv IS NULL or ns IS NULL THEN
            raise_application_error(-20001,'Cannot find target object: '||sq);
        END IF;

        BEGIN
            sys.dbms_shared_pool.&mark(hash=>hv,namespace=>ns,global=>true);
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE=-26680 THEN --ORA-26680: object type not supported
                dbms_output.put_line('object type "'||nn||'"('||ns||') is unsupported, changing _kgl_debug');
                IF :mark='markhot' THEN
                    execute immediate 'alter system set "_kgl_debug"="hash='''||hv||'''  debug=33554432"';
                ELSE
                    execute immediate 'alter system set "_kgl_debug"=''''';
                END IF;
            ELSE
                RAISE;
            END IF;
        END;
    ELSE
        $IF &check_access_x=1 $THEN
            SELECT namespace INTO ns
            FROM   SYS.OBJ$
            WHERE  OBJ#=OID;
        $ELSE
            SELECT namespace INTO ns
            FROM   dba_objects
            WHERE  object_id=OID;
        $END
        BEGIN
            sys.dbms_shared_pool.&mark(own,nam,namespace=>ns);
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE=-26680 THEN --ORA-26680: object type not supported
                dbms_output.put_line('object type "'||nn||'"('||ns||') is unsupported, changing _kgl_debug');
                IF :mark='markhot' THEN
                    execute immediate 'alter system set "_kgl_debug"="schema='''||own||''' name='''||nam||''' namespace='||ns||'  debug=33554432"';
                ELSE
                    execute immediate 'alter system set "_kgl_debug"=''''';
                END IF;
            ELSE
                RAISE;
            END IF;
        END;
        IF typ IN ('PACKAGE','TYPE') THEN
            sys.dbms_shared_pool.&mark(own,nam,namespace=>2);
        END IF;
    END IF;

    OPEN :c FOR 
        SELECT inst_id inst,PROPERTY PROP,own||'.'||nam NAME,NAMESPACE,KEPT,STATUS,LOADS,EXECUTIONS EXECS,LOCKS,PINS,INVALIDATIONS INVALIDS,TIMESTAMP,NULL SQL_TEXT
        FROM   gv$db_object_cache
        WHERE  OWNER=own AND NAME=nam
        UNION ALL
        SELECT inst_id inst,PROPERTY,hv OBJECT_NAME,'['||ns||']'||NAMESPACE,KEPT,STATUS,LOADS,EXECUTIONS EXECS,LOCKS,PINS,INVALIDATIONS INVALIDS,TIMESTAMP,NAME
        FROM   gv$db_object_cache
        WHERE  hash_value=hs
        ORDER BY 1,2;
END;
/