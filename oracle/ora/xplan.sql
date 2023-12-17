/*[[explain/trace/execute SQL. Usage: @@NAME [-o|-c|-exec|-10046|-obj] {<sql_id> [<child_num>|<snap_id>|<phv>]} | {[<schema>] <sql_text>}
    The script will call dbms_sqlpa.remote_process_sql instead of "EXPLAIN PLAN" or "EXECUTE IMMEDIATE" so that the bind variables can be applied.
   
    -o [-low|-high]: generate optimizer trace
    -c [-low|-high]: generate compiler trace(10053)
    -exec          : execute SQL instead of explain only
    -10046         : execute SQL and get 10046 trace file

    --[[
        
        @ARGS : 1
        &opt  : default={EXPLAIN_PLAN} exec={EXECUTE,GATHER_SQL_STATS} gather={GATHER_SQL_STATS} obj={COMPUTE_OBJECTS} diag={DIAGNOSE_SQL} 10046={3}
        &trace: default={0} o={1} c={2}
        &load : default={--} o={} c={} 10046={}
        &lv   : default={medium} low={low} high={high}
        @O121 : 12.1={} default={--}
        @O122 : 12.2={} default={--}
        @O181 : 18.1={} default={--}
    --]]
]]*/
set verify off feed off
var cur REFCURSOR;
var xplan VARCHAR2(300);
col ela for usmhd2
col cpu for pct2
col val,xplan_cost,exec_cost for k0
col buff,reads,dxwrites,rows#,blocks,extents for tmb2
col bytes,NEXT_KB for kmg2

DECLARE
    cur     SYS_REFCURSOR;
    action  VARCHAR2(100):=:opt;
    con     VARCHAR2(128);
    own     VARCHAR2(128):=regexp_substr(:v2,'^\S+$');
    id      INT:=regexp_substr(own,'^\d+$');
    sq_text CLOB:=trim(:V1);
    sq_id   VARCHAR2(20):= regexp_substr(sq_text,'^\S{10,20}$');
    sq_nid  VARCHAR2(20);
    sig     INT;
    bw      RAW(2000);
    xplan   VARCHAR2(300);
    err     VARCHAR2(32767);
    trace   VARCHAR2(200);
    fixctl  INT;
    PX      INT;
    phv     INT;
    phv1    INT;
    phv2    INT;
    st      DATE;
    ctrl    VARCHAR2(2000);
    siz     INT;
    rdata   NUMBER;
    rtype   NUMBER;
    extra   CLOB;
    stats   V$SQL%ROWTYPE;
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
    PROCEDURE pr(nam VARCHAR2,val VARCHAR2) IS
    BEGIN
        IF trim(val) IS NULL THEN
            RETURN;
        END IF;
        dbms_output.put_line('| '||rpad(nam,23)||' : '||val);
    END;
BEGIN
    dbms_output.enable(null);
    own := replace(own,id);
    IF sq_id IS NOT NULL THEN
    BEGIN
        SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/ nvl(upper(own),nam),txt,sig,br,phv
        INTO own,sq_text,sig,bw,phv
        FROM (
            SELECT * FROM (
                SELECT parsing_schema_name nam, sql_fulltext txt, force_matching_signature sig, bind_data br,plan_hash_value phv
                FROM   gv$sql a
                WHERE  sql_id = sq_id
                AND    sql_fulltext IS NOT NULL
                AND    nvl(id, child_number) IN (child_number, plan_hash_value)
                ORDER  BY nvl2(bind_data,1,2),last_active_time desc
            ) 
            WHERE rownum<2
            UNION ALL
            SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data,plan_hash_value
            FROM   all_sqlset_statements a
            WHERE  sql_id = sq_id
            AND    sql_text IS NOT NULL
            AND    nvl(id, sqlset_id) IN (sqlset_id, plan_hash_value)
            UNION ALL
            SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data,plan_hash_value
            FROM   dba_hist_sqltext
            JOIN  (SELECT *
                   FROM   (SELECT dbid, sql_id, parsing_schema_name, force_matching_signature, bind_data,plan_hash_value
                           FROM   dba_hist_sqlstat
                           WHERE  sql_id = sq_id
                           AND    nvl(id, snap_id) IN (snap_id, plan_hash_value)
                           ORDER  BY decode(dbid, sys_context('userenv', 'dbid'), 1, 2),nvl2(bind_data,1,2), snap_id DESC)
                   WHERE  rownum < 2)
            USING  (dbid, sql_id)
            WHERE  sql_id = sq_id
            AND    sql_text IS NOT NULL
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

    IF &trace>0 THEN
        trace  :='alter session set events ''trace [SQL_'|| CASE trace WHEN 1 THEN 'Optimizer' ELSE 'Compiler' END || '.*] @''';
        fixctl := sys.dbms_sqldiag.get_fix_control(16923858);
        IF fixctl=6 THEN
            EXECUTE IMMEDIATE q'{alter session set "_fix_control"='16923858:4'}';
        END IF;
        EXECUTE IMMEDIATE 'ALTER SESSION SET tracefile_identifier='''||sq_id||'_'||ROUND(DBMS_RANDOM.VALUE(1,1E6))||'''';
        EXECUTE IMMEDIATE replace(trace,'@','disk &lv');
    ELSIF action='3' THEN
        trace  :='alter session set events ''10046 trace name context @''';
        EXECUTE IMMEDIATE 'ALTER SESSION SET tracefile_identifier='''||sq_id||'_'||ROUND(DBMS_RANDOM.VALUE(1,1E6))||'''';
        EXECUTE IMMEDIATE replace(trace,'@','forever,level 12');
        action := 'EXECUTE,GATHER_SQL_STATS';
    ELSIF action='GATHER_SQL_STATS' THEN
        ctrl:='<parameter name="sharing">"1"</parameter><parameter name="approximate">"OTNFSLVRH_"</parameter>';
    END IF;
    st := SYSDATE;
    --SELECT value into siz
    --FROM   v$parameter where name='sort_area_size';
    --execute immediate 'alter session set sort_area_size='||round(65536+1024*1024*512*dbms_random.value);
    phv1 := phv;
    dbms_sqlpa.remote_process_sql(
            sql_text => sq_text,
            parsing_schema => own,
            bind_data => bw,
            bind_list => null,
            action => action,
            time_limit => 3600,
            plan_hash1 => phv1,
            buffer_gets => stats.buffer_gets,
            cpu_time => stats.cpu_time,
            elapsed_time => stats.elapsed_time,
            disk_reads => stats.disk_reads,
            disk_writes => stats.direct_writes,
            rows_processed => stats.rows_processed,
            optimizer_cost => stats.optimizer_cost,
            parse_time => stats.parse_calls,
            err_code => sig,
            err_mesg => err,
            trace_flags => 0,
            extra_res => extra,
            other_xml => stats.sql_fulltext,
            physical_read_requests => stats.physical_read_requests,
            physical_write_requests => stats.physical_write_requests,
            physical_read_bytes => stats.physical_read_bytes,
            physical_write_bytes => stats.physical_write_bytes,
            user_io_time => stats.user_io_wait_time,
            plan_hash2 => phv2,
            io_interconnect_bytes => stats.io_interconnect_bytes,
            action_flags => 0,
            control_options_xml => ctrl
            &O121 ,con_dbid=>null,con_name=>con
            &O122 ,param_xml=>null
            &O181 ,result_data_checksum=>rdata,result_type_checksum=>rtype);
    dbms_output.put_line('===================================================');
    pr('plan_hash1',phv1);
    pr('plan_hash2',phv2);
    pr('optimizer_cost',stats.optimizer_cost);
    pr('buffer_gets',stats.buffer_gets);
    pr('parse_time',stats.parse_calls||' us');
    pr('elapsed_time',stats.elapsed_time||' us');
    pr('cpu_time',stats.cpu_time||' us');
    pr('user_io_time',stats.user_io_wait_time||' us');
    pr('rows_processed',stats.rows_processed);
    pr('io_interconnect_bytes',stats.io_interconnect_bytes);
    pr('disk_reads',stats.disk_reads);
    pr('physical_read_bytes',stats.physical_read_bytes);
    pr('physical_read_requests',stats.physical_read_requests);
    pr('disk_writes',stats.direct_writes);
    pr('physical_write_requests',stats.physical_write_requests);
    pr('physical_write_bytes',stats.physical_write_bytes);
    &O121 pr('con_name',con);
    &O181 pr('result_data_checksum',rdata);
    &O181 pr('result_type_checksum',rtype);
    pr('other_xml',stats.sql_fulltext);
    pr('err_code',sig);
    pr('err_mesg',err);
    pr('extra_res',extra);
    dbms_output.put_line('===================================================');
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

    IF phv2 is not null THEN
        xplan := 'ORG_PHV: '||phv||'  ->  ACT_PHV: '||phv2;
        SELECT MAX(sql_id||' # '||child_number)
        INTO   sq_nid
        FROM (SELECT sql_id,child_number
              FROM   v$sql
              WHERE  plan_hash_value=phv2
              AND    parsing_schema_name=own
              AND    parsing_user_id=sys_context('userenv','CURRENT_USERID')
              AND    program_id=0
              ORDER  BY decode(force_matching_signature,stats.force_matching_signature,1,2),
                        sign(instr(sql_fulltext,regexp_replace(to_char(substr(sq_text,1,512)),'^\s+|\s+$'))) desc,
                        last_active_time desc nulls last)
        WHERE rownum<2;

        IF sq_nid IS NOT NULL THEN
            xplan :='|  '||xplan||'  |  ORG_SQL: '||sq_id||'  ->  ACT_SQL: '||sq_nid||'  |';
            dbms_output.put_line(xplan);
            dbms_output.put_line(lpad('=',length(xplan),'='));
            xplan := 'ora plan -g '||substr(sq_nid,1,13)||' '||phv2||CASE WHEN px>0 THEN ' -all -projection' else ' -ol' END;
        ELSE
            DELETE PLAN_TABLE
            WHERE  PLAN_ID=phv2;
            dbms_output.put_line(xplan);
            dbms_output.put_line(lpad('=',length(xplan),'='));
            xplan := 'xplan -'||sq_id||' '||phv2;
        END IF;
    ELSE 
        sig := -1;
    END IF;

    :xplan   := xplan;
    :cur     := cur;
END;
/

&xplan 
print cur
&load loadtrace default 256
