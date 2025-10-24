/*[[explain/trace/execute SQL. Usage: @@NAME [-o|-c|-exec|-10046|-obj] {<sql_id> [<schema>|<child_num>|<snap_id>|<phv>]} | <sql_text>
    The script will call DBMS_SQLTUNE_INTERNAL.I_PROCESS_SQL_CALLOUT instead of "EXPLAIN PLAN" or "EXECUTE IMMEDIATE" so that the bind variables can be applied.
   
    -o [-low|-high]: generate optimizer trace
    -c [-low|-high]: generate compiler trace(10053)
    -exec          : execute SQL instead of explain only
    -obj           : generate relative object list
    -10046         : execute SQL and get 10046 trace file
    -nobase        : bypass possible SQL Plan Baseline

    --[[
        @ARGS: 1
        &opt  : xplan={2} exec={1} gather={8} obj={4} diag={64} o={2} c={2} 10046={3}
        &base : default={0} nobase={128}
        &trace: default={0} o={1} c={2}
        &load: default={--} o={} c={} 10046={}
        &lv  : default={medium} low={low} high={high}
    --]]
]]*/
set verify off feed off
var cur REFCURSOR;
var xplan VARCHAR2(300);
col ela for usmhd2
col cpu for pct2
col val,xplan_cost,first_row,all_rows for k0
col buff,reads,dxwrites,rows#,blocks,extents for tmb2
col bytes,NEXT_KB for kmg2

DECLARE
    cur     SYS_REFCURSOR;
    own     VARCHAR2(128):=regexp_substr(:v2,'^\S+$');
    id      INT:=regexp_substr(own,'^\d+$');
    sq_text CLOB:=trim(:V1);
    sq_id   VARCHAR2(20):= regexp_substr(sq_text,'^\S{10,20}$');
    sq_nid  VARCHAR2(20);
    sig     INT;
    stmt    SYS.SQLSET_ROW;
    bw      RAW(2000);
    xplan   VARCHAR2(300);
    err     VARCHAR2(32767);
    trace   VARCHAR2(200);
    fixctl  INT;
    PX      INT;
    phv     INT;
    st      DATE;
    ctrl    VARCHAR2(2000);
    siz     INT;
    PROCESS_CTRL_DTD CONSTANT VARCHAR2(4000) :=  
        '<?xml version="1.0"?>
         <!DOCTYPE process_ctrl [
         <!ELEMENT process_ctrl (parameter*, outline_data?, hint_data?)>
         <!ELEMENT parameter (#PCDATA)>
         <!ELEMENT outline_data (hint+)>
         <!ELEMENT hint_data (hint+)>
         <!ELEMENT hint (#PCDATA)>
         <!ATTLIST parameter name CDATA #IMPLIED>
         ]>'; 
    PROCESS_CTRL_BEGIN CONSTANT VARCHAR2(14) := '<process_ctrl>';
    PROCESS_CTRL_END   CONSTANT VARCHAR2(15) := '</process_ctrl>';
    $IF DBMS_DB_VERSION.VERSION>12 $THEN
        PROCEDURE I_PROCESS_SQL_CALLOUT(
            STMT         IN OUT SQLSET_ROW,
            EXEC_USERID  IN PLS_INTEGER:=sys_context('USERENV','CURRENT_USERID'),
            ACTION       IN BINARY_INTEGER,
            TIME_LIMIT   IN POSITIVE,
            CTRL_OPTIONS IN XMLTYPE:=null,
            EXTRA_RESULT OUT CLOB,
            ERR_CODE     OUT BINARY_INTEGER,
            ERR_MESG     OUT VARCHAR2) IS
            EXTERNAL NAME "kestsProcessSqlCallout"
            WITH CONTEXT
            PARAMETERS(CONTEXT     ,
                       STMT        ,
                       STMT         INDICATOR STRUCT,
                       STMT         DURATION OCIDURATION,
                       EXEC_USERID  UB4,
                       ACTION       UB4,
                       TIME_LIMIT   UB4,
                       CTRL_OPTIONS,
                       CTRL_OPTIONS INDICATOR SB2,
                       EXTRA_RESULT OCILOBLOCATOR,
                       EXTRA_RESULT INDICATOR SB2,
                       ERR_CODE     SB4,
                       ERR_CODE     INDICATOR SB2,
                       ERR_MESG     OCISTRING,
                       ERR_MESG     INDICATOR SB2)
            LIBRARY SYS.DBMS_SQLTUNE_LIB;
    $ELSE
        PROCEDURE I_PROCESS_SQL_CALLOUT(
            STMT         IN OUT SQLSET_ROW, 
            ACTION       IN     BINARY_INTEGER, 
            TIME_LIMIT   IN     POSITIVE,
            CTRL_OPTIONS IN     XMLTYPE:=NULL,
            EXTRA_RESULT OUT    CLOB,
            ERR_CODE     OUT    BINARY_INTEGER,
            ERR_MESG     OUT    VARCHAR2)
          IS EXTERNAL NAME "kestsProcessSqlCallout" 
          WITH CONTEXT
          PARAMETERS (CONTEXT, 
                      STMT, STMT INDICATOR STRUCT, STMT DURATION OCIDURATION,
                      ACTION UB4,
                      TIME_LIMIT UB4, 
                      CTRL_OPTIONS, CTRL_OPTIONS INDICATOR SB2, 
                      EXTRA_RESULT OCILOBLOCATOR, EXTRA_RESULT INDICATOR SB2,
                      ERR_CODE SB4, ERR_CODE INDICATOR SB2,
                      ERR_MESG OCISTRING, ERR_MESG INDICATOR SB2)
          LIBRARY SYS.DBMS_SQLTUNE_LIB;   
    $END
BEGIN
    dbms_output.enable(null);
    own := replace(own,id);
    IF sq_id IS NOT NULL THEN
    BEGIN
        SELECT /*+NO_MINITOR OPT_PARAM('_fix_control' '26552730:0')*/ nvl(upper(own),nam),txt,sig,br,phv
        INTO own,sq_text,sig,bw,phv
        FROM (
            SELECT * FROM (
                SELECT parsing_schema_name nam, sql_fulltext txt, force_matching_signature sig, bind_data br,plan_hash_value phv
                FROM   gv$sql a
                WHERE  sql_id = sq_id
                AND    nvl(id, child_number) IN (child_number, plan_hash_value)
                ORDER  BY nvl2(bind_data,1,2),last_active_time desc
            ) WHERE rownum<2
            UNION ALL
            SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data,plan_hash_value
            FROM   all_sqlset_statements a
            WHERE  sql_id = sq_id
            AND    nvl(id, sqlset_id) IN (sqlset_id, plan_hash_value)
            UNION ALL
            SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data,plan_hash_value
            FROM   dba_hist_sqltext
            JOIN  (SELECT *
                   FROM   (SELECT dbid, sql_id, parsing_schema_name, force_matching_signature, bind_data,plan_hash_value
                           FROM   dba_hist_sqlstat
                           WHERE  sql_id = sq_id
                           AND    nvl(id, snap_id) IN (snap_id, plan_hash_value)
                           ORDER  BY decode(dbid, sys_context('userenv', 'dbid'), 1, 2),nvl2(bind_data,1,2), snap_id DESC,decode(instance_number,userenv('instance'),1,2))
                   WHERE  rownum < 2)
            USING  (dbid, sql_id)
            WHERE  sql_id = sq_id
            UNION ALL
            SELECT username,to_clob(sql_text),force_matching_signature,null,sql_plan_hash_value
            FROM   gv$sql_monitor
            WHERE  sql_id = sq_id
            AND    sql_text IS NOT NULL
            AND    IS_FULL_SQLTEXT='Y'
            AND    nvl(id,sql_exec_id) in(sql_exec_id,sql_plan_hash_value)
            AND    rownum < 2
        ) WHERE ROWNUM<2;
    EXCEPTION WHEN OTHERS THEN
        raise_application_error(-20001,'Cannot find SQL Text for SQL Id: '||sq_id);
    END;
    ELSE
        IF sq_text LIKE '%/' THEN
            sq_text := trim(trim('/' from sq_text));
        ELSIF sq_text LIKE '%;' AND UPPER(sq_text) NOT LIKE '%END;' THEN
            sq_text := trim(trim(';' from sq_text));
        END IF;
        sq_id  := SYS.dbms_sqltune_util0.sqltext_to_sqlid(sq_text);
        sig    := SYS.dbms_sqltune_util0.sqltext_to_signature(sq_text,1);
        own    := nvl(upper(own),sys_context('userenv','current_schema'));
    END IF;

    stmt := SYS.SQLSET_ROW(sq_id,sig,sq_text,null,bw,own,'SYS_XPLAN',round(dbms_random.value(1e9,1e10)));

    IF bitand(&opt,5)>0 THEN
        ctrl:='<parameter name="mode">safe</parameter>';
    END IF;

    IF &trace>0 THEN
        trace  :='alter session set events ''trace [SQL_'|| CASE trace WHEN 1 THEN 'Optimizer' ELSE 'Compiler' END || '.*] @''';
        fixctl := sys.dbms_sqldiag.get_fix_control(16923858);
        IF fixctl=6 THEN
            EXECUTE IMMEDIATE q'{alter session set "_fix_control"='16923858:4'}';
        END IF;
        EXECUTE IMMEDIATE 'ALTER SESSION SET tracefile_identifier='''||sq_id||'_'||ROUND(DBMS_RANDOM.VALUE(1,1E6))||'''';
        EXECUTE IMMEDIATE replace(trace,'@','disk &lv');
    ELSIF &opt=3 THEN
        trace  :='alter session set events ''10046 trace name context @''';
        EXECUTE IMMEDIATE 'ALTER SESSION SET tracefile_identifier='''||sq_id||'_'||ROUND(DBMS_RANDOM.VALUE(1,1E6))||'''';
        EXECUTE IMMEDIATE replace(trace,'@','forever,level 12');
    ELSIF &opt=8 THEN
        ctrl:='<parameter name="sharing">1</parameter><parameter name="approximate">OT</parameter>';
    END IF;
    sq_text := NULL;
    st := SYSDATE;
    --SELECT value into siz
    --FROM   v$parameter where name='sort_area_size';
    --execute immediate 'alter session set sort_area_size='||round(65536+1024*1024*512*dbms_random.value);
    stmt.last_exec_start_time := to_date(sysdate,'YYYY-MM-DD/HH24:MI:SS');
    I_PROCESS_SQL_CALLOUT(stmt=>stmt,
                          action=>&opt + &base,
                          time_limit=>86400,
                          ctrl_options=>CASE WHEN ctrl IS NOT NULL THEN xmltype(process_ctrl_dtd||process_ctrl_begin||ctrl ||process_ctrl_end) END,
                          extra_result=>sq_text,
                          err_code=>sig,
                          err_mesg=>err);
    --execute immediate 'alter session set sort_area_size='||siz;
    IF trace IS NOT NULL THEN
        EXECUTE IMMEDIATE replace(trace,'@','off');
        IF fixctl=6 THEN
            EXECUTE IMMEDIATE q'{alter session set "_fix_control"='16923858:6'}';
        END IF;
    END IF;

    IF err IS NOT NULL THEN
        raise_application_error(-20001,err);
    END IF;

    IF stmt.sql_plan is not null and stmt.sql_plan.count>0 THEN
        SELECT nvl(max(PLAN_ID),COUNT(1)),
               MAX(CASE WHEN OTHER_XML IS NOT NULL THEN 
                        regexp_substr(to_char(regexp_substr(other_xml,'"plan_hash">\d+<')),'\d+')
               END),
               COUNT(CASE WHEN operation LIKE 'PX%' THEN 1 END)
        INTO   sig,fixctl,px
        FROM   TABLE(stmt.sql_plan);

        xplan := 'ORG_PHV: '||phv||'  ->  ACT_PHV: '||fixctl;

        SELECT /*+NO_MINITOR*/ MAX(sql_id||' #'||child_number)
        INTO   sq_nid
        FROM (SELECT sql_id,child_number
              FROM   v$sql
              WHERE  plan_hash_value=fixctl
              AND    parsing_schema_name=stmt.parsing_schema_name
              AND    parsing_user_id=sys_context('userenv','CURRENT_USERID')
              AND    program_id=0
              AND    last_load_time>=stmt.last_exec_start_time
              ORDER  BY decode(force_matching_signature,stmt.force_matching_signature,1,2),
                        sign(instr(sql_fulltext,regexp_replace(to_char(substr(stmt.sql_text,1,512)),'^\s+|\s+$'))) desc,
                        last_load_time desc,child_number desc)
        WHERE rownum<2;

        IF sq_nid IS NOT NULL THEN
            xplan :='|  '||xplan||'  |  ORG_SQL: '||sq_id||'  ->  ACT_SQL: '||sq_nid||'  |';
            dbms_output.put_line(xplan);
            dbms_output.put_line(lpad('=',length(xplan),'='));
            xplan := 'ora plan -g '||replace(sq_nid,'#','-')||CASE WHEN px>0 THEN ' -all -projection' else ' -ol' END;
        ELSE
            DELETE SYS.PLAN_TABLE$;

            INSERT INTO SYS.PLAN_TABLE$
                (STATEMENT_ID,
                 PLAN_ID,
                 TIMESTAMP,
                 REMARKS,
                 OPERATION,
                 OPTIONS,
                 OBJECT_NODE,
                 OBJECT_OWNER,
                 OBJECT_NAME,
                 OBJECT_ALIAS,
                 OBJECT_INSTANCE,
                 OBJECT_TYPE,
                 OPTIMIZER,
                 SEARCH_COLUMNS,
                 ID,
                 PARENT_ID,
                 DEPTH,
                 POSITION,
                 COST,
                 CARDINALITY,
                 BYTES,
                 OTHER_TAG,
                 PARTITION_START,
                 PARTITION_STOP,
                 PARTITION_ID,
                 DISTRIBUTION,
                 CPU_COST,
                 IO_COST,
                 TEMP_SPACE,
                 ACCESS_PREDICATES,
                 FILTER_PREDICATES,
                 PROJECTION,
                 TIME,
                 QBLOCK_NAME,
                 OTHER_XML)
            SELECT /*+NO_MINITOR*/ 'INTERNAL_DBCLI_CMD',
                   SIG,
                   SYSDATE,
                   REMARKS,
                   OPERATION,
                   OPTIONS,
                   OBJECT_NODE,
                   OBJECT_OWNER,
                   OBJECT_NAME,
                   OBJECT_ALIAS,
                   OBJECT_INSTANCE,
                   OBJECT_TYPE,
                   OPTIMIZER,
                   SEARCH_COLUMNS,
                   ID,
                   PARENT_ID,
                   DEPTH,
                   POSITION,
                   COST,
                   CARDINALITY,
                   BYTES,
                   OTHER_TAG,
                   PARTITION_START,
                   PARTITION_STOP,
                   PARTITION_ID,
                   DISTRIBUTION,
                   CPU_COST,
                   IO_COST,
                   TEMP_SPACE,
                   ACCESS_PREDICATES,
                   FILTER_PREDICATES,
                   PROJECTION,
                   TIME,
                   QBLOCK_NAME,
                   OTHER_XML
            FROM   TABLE(stmt.sql_plan);
            dbms_output.put_line(xplan);
            dbms_output.put_line(lpad('=',length(xplan),'='));
            xplan := 'xplan -'||sq_id||' '||sig;
        END IF;
    ELSE 
        sig := -1;
    END IF;

    IF sq_text IS NOT NULL THEN
        
        IF bitand(&opt,3)>0 THEN
            OPEN cur FOR
                SELECT /*+NO_MINITOR*/ 
                        xplan_cost, a.name,
                       '$HEADCOLOR$/$NOR$' "/",
                       b.first_row,b.all_rows,b.name
                FROM (
                    SELECT a.*,row_number() over(order by name) r
                    FROM   XMLTABLE('//stats[@type="compilation" and number()>-1][1]/stat' 
                           passing xmltype(sq_text)
                           columns name       varchar2(128) path '@name',
                                   xplan_cost INT path 'number()') a) a
                FULL JOIN (
                    SELECT name,first_row,all_rows,row_number() over(order by name) r
                    FROM   XMLTABLE('//stats[@type="execution" and number()>-1][1]/stat' 
                           passing xmltype(sq_text)
                           columns name       varchar2(128) path '@name',
                                   all_rows  INT path 'number()') a
                    FULL JOIN  XMLTABLE('//stats[@type="execution_first_row" and number()>-1][1]/stat' 
                           passing xmltype(sq_text)
                           columns name       varchar2(128) path '@name',
                                   first_row  INT path 'number()') b
                    USING(name)) b
                USING (r)
                ORDER  BY R;
        ELSIF bitand(&opt,4)=4 THEN
            OPEN cur FOR
                SELECT /*+NO_EXPAND NO_MINITOR*/ 
                       object_id,owner,object_name,subobject_name part_name,type,
                       COUNT(1) SEGS,
                       SUM(BYTES) BYTES,
                       SUM(BLOCKS) BLOCKS,
                       SUM(EXTENTS) EXTENTS,
                       MAX(NEXT_EXTENT) NEXT_KB,
                       MAX(TABLESPACE_NAME) TBS,
                       MAX(SEGMENT_SUBTYPE) KEEP(DENSE_RANK LAST ORDER BY TABLESPACE_NAME) TBS_TYPE
                FROM (
                    SELECT /*+opt_estimate(query,rows=5)*/ 
                           0+EXTRACTVALUE(VALUE(P), '/object/num') object_id,
                           NVL(EXTRACTVALUE(VALUE(P), '/object/owner'), 'N/A') owner,
                           EXTRACTVALUE(VALUE(P), '/object/name') object_name,
                           EXTRACTVALUE(VALUE(P), '/object/type') TYPE
                    FROM   TABLE(XMLSEQUENCE(EXTRACT(XMLTYPE(sq_text), '//object'))) P) A
                JOIN DBA_OBJECTS B
                USING (OBJECT_ID,OWNER,OBJECT_NAME)
                JOIN  (SELECT A.*,SEGMENT_NAME OBJECT_NAME FROM DBA_SEGMENTS A) C
                USING (OWNER,OBJECT_NAME)
                WHERE (B.SUBOBJECT_NAME IS NULL OR c.PARTITION_NAME=B.SUBOBJECT_NAME)
                GROUP  BY object_id,owner,object_name,subobject_name,type
                ORDER  BY owner,object_name;
        ELSE
            dbms_output.put_line(sq_text);
        END IF;
    END IF;
    :xplan   := xplan;
    :cur     := cur;
END;
/

&xplan 
print cur
&load loadtrace default 256
