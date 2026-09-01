/*[[explain/trace/execute SQL. Usage: @@NAME [-o|-c|-exec|-10046|-obj] {<sql_id> [<schema>|<child_num>|<snap_id>|<phv>]} | <sql_text>
    The script will call DBMS_SQLTUNE_INTERNAL.I_PROCESS_SQL_CALLOUT instead of "EXPLAIN PLAN" or "EXECUTE IMMEDIATE" so that the bind variables can be applied.
    When the SQL has bind_data, the "Bind Info" grid will list every bind variable with the data type (including precision/length from the peeked bind metadata), the declared max length, the peeked value (from the generated plan) and the value stored in bind_data, both decoded into readable format. The character set ID (csid) of peeked binds is resolved into the character set name via NLS_CHARSET_NAME (blank for non-character types). Values that cannot be decoded are shown as "(0x) <hex>".
   
    -o [-low|-high]: generate optimizer trace
    -c [-low|-high]: generate compiler trace(10053)
    -env           : load sql optimizer env as well
    -exec          : execute SQL instead of explain only
    -monitor       : together with -exec, add hint "monitor"
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
        &env : default={0} env={1}
        &mon : default={0} monitor={1}
        @con : 12.1={,con_dbid} default={}
    --]]
]]*/
set verify off feed off
var cur REFCURSOR;
var bd REFCURSOR "Bind Info"
var xplan VARCHAR2(300);
col ela for usmhd2
col cpu for pct2
col val,xplan_cost,first_row,all_rows for k0
col buff,reads,dxwrites,rows#,blocks,extents for tmb2
col bytes,NEXT_KB for kmg2

DECLARE
    cur     SYS_REFCURSOR;
    binds   SYS_REFCURSOR;
    own     VARCHAR2(128):=regexp_substr(:v2,'^\S+$');
    id      INT:=regexp_substr(own,'^\d+$');
    sq_text CLOB:=trim(:V1);
    sq_id   VARCHAR2(20):= regexp_substr(sq_text,'^\S{10,20}$');
    sq_nid  VARCHAR2(20);
    sig     INT;
    stmt    SYS.SQLSET_ROW;
    bw      RAW(2000);
    env     RAW(2000);
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
        SELECT /*+NO_MINITOR OPT_PARAM('_fix_control' '26552730:0')*/ nvl(upper(own),nam),txt,sig,br,phv,env
        INTO own,sq_text,sig,bw,phv,env
        FROM (
            SELECT * FROM (
                SELECT parsing_schema_name nam, sql_fulltext txt, force_matching_signature sig, bind_data br,plan_hash_value phv,optimizer_env env
                FROM   gv$sql a
                WHERE  sql_id = sq_id
                AND    nvl(id, child_number) IN (child_number, plan_hash_value)
                ORDER  BY nvl2(bind_data,1,2),last_active_time desc
            ) WHERE rownum<2
            UNION ALL
            SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data,plan_hash_value,optimizer_env
            FROM   all_sqlset_statements a
            WHERE  sql_id = sq_id
            AND    nvl(id, sqlset_id) IN (sqlset_id, plan_hash_value)
            UNION ALL
            SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data,plan_hash_value,optimizer_env
            FROM   dba_hist_sqltext
            JOIN  (SELECT *
                   FROM   (SELECT dbid &con, sql_id, parsing_schema_name, force_matching_signature, bind_data,plan_hash_value,optimizer_env_hash_value
                           FROM   dba_hist_sqlstat
                           WHERE  sql_id = sq_id
                           AND    nvl(id, snap_id) IN (snap_id, plan_hash_value)
                           ORDER  BY decode(dbid, sys_context('userenv', 'dbid'), 1, 2),nvl2(bind_data,1,2), snap_id DESC,decode(instance_number,userenv('instance'),1,2))
                   WHERE  rownum < 2)
            USING  (dbid, sql_id &con)
            LEFT JOIN   dba_hist_optimizer_env
            USING  (dbid,optimizer_env_hash_value &con)
            WHERE  sql_id = sq_id
            UNION ALL
            SELECT username,to_clob(sql_text),force_matching_signature,null,sql_plan_hash_value,null
            FROM   gv$sql_monitor
            WHERE  sql_id = sq_id
            AND    sql_text IS NOT NULL
            AND    is_full_sqltext='Y'
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
    IF &env=1 and &mon=1 THEN
        stmt.optimizer_env := env;
    ELSIF bitand(&opt,5)>0 THEN
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

    IF bitand(&opt + &base,1)=1 THEN 
        ctrl := q'~<hint_data><hint><![CDATA[monitor]]></hint></hint_data>~';
    END IF;
    /*
    IF bitand(&opt + &base,5)>0 THEN
        ctrl := ctrl||'<parameter name="mode">safe</parameter>';
    END IF;*/

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
              AND    instr(sql_fulltext,substr(stmt.sql_text,1,512)) > 0
              AND    program_id=0
              AND    (stmt.optimizer_cost IS NULL OR stmt.optimizer_cost=optimizer_cost)
              AND    upper(ltrim(substr(sql_text,1,128))) not like 'EXPLAIN%'
              ORDER  BY decode(nvl(action,' '),stmt.action,1,2),
                        decode(force_matching_signature,stmt.force_matching_signature,1,2),
                        sign(instr(sql_fulltext,substr(stmt.sql_text,1,512))) desc,
                        last_load_time desc,child_number desc)
        WHERE rownum<2;

        IF sq_nid IS NOT NULL THEN
            xplan :='|  '||xplan||'  |  ORG_SQL: '||sq_id||'  ->  ACT_SQL: '||sq_nid||'  |';
            dbms_output.put_line(xplan);
            dbms_output.put_line(lpad('=',length(xplan),'='));
            xplan := 'ora plan -g -report '||replace(sq_nid,'#');
        ELSE
            DELETE SYS.PLAN_TABLE$ WHERE PLAN_ID=SIG;

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
            xplan := 'ora plan -p -report '||sig;
        END IF;

        OPEN binds FOR
            WITH bd AS (
                SELECT DISTINCT
                       b.position pos,nvl(name,':'||b.position) name,b.datatype_string,
                       CASE WHEN b.datatype_string LIKE 'TIMESTAM%' AND b.value_anydata IS NOT NULL THEN substr(anydata.accesstimestamp(b.value_anydata),1,32)
                            WHEN b.datatype_string LIKE 'DATE%'      AND b.value_anydata IS NOT NULL THEN to_char(anydata.accessdate(b.value_anydata),'yyyy-mm-dd hh24:mi:ss')
                            ELSE b.value_string
                       END captured_value
                FROM   TABLE(dbms_sqltune.extract_binds(bw)) b),
            pk AS (
                SELECT /*+INLINE*/ DISTINCT
                       nvl(nvl(name,name2),':'||pos) name,pos,
                       CASE WHEN dtystr IS NOT NULL THEN dtystr
                            WHEN dty IN (1,9) THEN 'VARCHAR2('||nvl(len,nvl(maxlen,mxl))||')'
                            WHEN dty = 2      THEN CASE WHEN nvl(scl,scal)=-127 THEN 'FLOAT'
                                                        WHEN pre=38 AND nvl(nvl(scl,scal),0)=0 THEN 'INTEGER'
                                                        ELSE 'NUMBER('||nvl(pre,38)||','||nvl(nvl(scl,scal),0)||')' END
                            WHEN dty = 96     THEN 'CHAR('||nvl(len,nvl(maxlen,mxl))||')'
                            WHEN dty = 23     THEN 'RAW('||nvl(len,nvl(maxlen,mxl))||')'
                            WHEN dty = 12     THEN 'DATE'
                            WHEN dty = 100    THEN 'BINARY_FLOAT'
                            WHEN dty = 101    THEN 'BINARY_DOUBLE'
                            WHEN dty = 119    THEN 'JSON'
                            WHEN dty = 127    THEN 'VECTOR'
                            WHEN dty = 178    THEN 'TIME'
                            WHEN dty = 179    THEN 'TIME WITH TIME ZONE'
                            WHEN dty = 182    THEN 'INTERVAL YEAR TO MONTH'
                            WHEN dty = 183    THEN 'INTERVAL DAY TO SECOND'
                            WHEN dty = 180    THEN 'TIMESTAMP'
                            WHEN dty = 181    THEN 'TIMESTAMP WITH TIME ZONE'
                            WHEN dty = 231    THEN 'TIMESTAMP WITH LOCAL TIME ZONE'
                            WHEN dty = 112    THEN 'CLOB'
                            WHEN dty = 113    THEN 'BLOB'
                            ELSE 'DTYPE '||to_char(dty) END datatype,
                       nvl(maxlen,mxl) maxlen,
                       CASE WHEN csid>0 THEN '['||csid||']'||nvl(nls_charset_name(csid),'Unknown') END charset,
                       CASE WHEN dty IN (1,9,96) AND csid=2000 THEN utl_i18n.raw_to_char(hextoraw(hval),'AL16UTF16')
                            WHEN dty IN (1,9,96) THEN utl_raw.cast_to_varchar2(hextoraw(hval))
                            WHEN dty IN (2,3,29) THEN to_char(utl_raw.cast_to_number(hextoraw(hval)))
                            WHEN dty IN (12,179,180,181,231) THEN
                                 to_char(100*(to_number(substr(hval,1,2),'XX')-100)
                                        + (to_number(substr(hval,3,2),'XX')-100),'fm0000')||'-'||
                                 to_char(to_number(substr(hval,5,2),'XX'),'fm00')||'-'||
                                 to_char(to_number(substr(hval,7,2),'XX'),'fm00')||' '||
                                 to_char(to_number(substr(hval,9,2),'XX')-1,'fm00')||':'||
                                 to_char(to_number(substr(hval,11,2),'XX')-1,'fm00')||':'||
                                 to_char(to_number(substr(hval,13,2),'XX')-1,'fm00')||
                                 CASE WHEN dty!=12 AND length(hval)>=22
                                      THEN '.'||lpad(to_char(to_number(rpad(substr(hval,15,8),8,'0'),'XXXXXXXX')),9,'0') END||
                                 CASE WHEN dty IN (179,181) AND length(hval)>=26
                                      THEN ' '||to_char(to_number(substr(hval,23,2),'XX')-20,'fmS99') END||
                                 CASE WHEN dty IN (179,181) AND length(hval)>=26
                                      THEN ':'||lpad(to_number(substr(hval,25,2),'XX')-60,2,'0') END
                            ELSE '(0x) '||hval
                       END peeked_value
                FROM   TABLE(stmt.sql_plan) p
                ,      XMLTABLE('/*/peeked_binds/bind' PASSING XMLTYPE(p.other_xml)
                       COLUMNS name   VARCHAR2(128)  PATH '@nam',
                               name2  VARCHAR2(128)  PATH '@name',
                               pos    INT            PATH '@pos',
                               dty    INT            PATH '@dty',
                               csid   INT            PATH '@csi',
                               dtystr VARCHAR2(128)  PATH '@dtystr',
                               maxlen INT            PATH '@maxlen',
                               mxl    INT            PATH '@mxl',
                               len    INT            PATH '@len',
                               pre    INT            PATH '@pre',
                               scl    INT            PATH '@scl',
                               scal   INT            PATH '@scal',
                               hval   VARCHAR2(4000) PATH '.') b
                WHERE  p.other_xml IS NOT NULL)
            SELECT pos "#",name,datatype,maxlen,charset,peeked_value,captured_value
            FROM  (SELECT pos,
                          nvl(pk.name,bd.name) name,
                          nvl(bd.datatype_string,pk.datatype) datatype,
                          pk.maxlen,
                          pk.charset,
                          pk.peeked_value,
                          bd.captured_value
                   FROM   pk
                   FULL   JOIN bd USING(pos))
            ORDER  BY pos,name;
    ELSIF bw IS NOT NULL THEN
        OPEN binds FOR
            SELECT DISTINCT
                   b.position,
                   nvl(name,':'||b.position) name,
                   b.datatype_string,
                   CASE WHEN b.datatype_string LIKE 'TIMESTAM%' AND b.value_anydata IS NOT NULL THEN substr(anydata.accesstimestamp(b.value_anydata),1,32)
                        WHEN b.datatype_string LIKE 'DATE%'     AND b.value_anydata IS NOT NULL THEN to_char(anydata.accessdate(b.value_anydata),'yyyy-mm-dd hh24:mi:ss')
                        ELSE b.value_string
                   END captured_value
            FROM   TABLE(dbms_sqltune.extract_binds(bw)) b
            ORDER  BY 1;
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
                SELECT /*+opt_estimate(query,rows=5)*/ 
                       0+EXTRACTVALUE(VALUE(P), '/object/num') object_id,
                       NVL(EXTRACTVALUE(VALUE(P), '/object/owner'), 'N/A') owner,
                       EXTRACTVALUE(VALUE(P), '/object/name') object_name,
                       EXTRACTVALUE(VALUE(P), '/object/type') type,
                       0+EXTRACTVALUE(VALUE(P), '/object/qksol_id') "qksol_id",
                       EXTRACTVALUE(VALUE(P), '/object/ref_source') "ref_source"
                FROM   TABLE(XMLSEQUENCE(EXTRACT(XMLTYPE(sq_text), '//object'))) p;
        ELSE
            dbms_output.put_line(sq_text);
        END IF;
    END IF;
    :xplan   := xplan;
    :cur     := cur;
    :bd      := binds;
END;
/

&xplan
print bd
print cur
&load loadtrace default 256
