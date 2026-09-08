/*[[
    Get SQL text and online stats. Usage: @@NAME <sql_id> [inst_id] [-q|-l|<child_no>|<snap_id>]
    When the 3rd parameter is specified:
        -q      : List all bind captures
        -l      : Use the last bind capture to replace the SQL text
        <number>: Use the bind capture of the given child_number/snap_id to replace the SQL text

    Sample Output:
    ==============
    ORCL> ora sql g6px76dmjv1jy
       TOP_SQL       PHV     PLAN_LINE PROGRAM# EVENT  AAS
    ------------- ---------- --------- -------- ------ ---
    g6px76dmjv1jy 3702721588         2          ON CPU  49
    g6px76dmjv1jy 3702721588         2     7294 ON CPU  44
    g6px76dmjv1jy 3702721588         2     7292 ON CPU  26
    b6usrg82hwsa3 3702721588         2    12703 ON CPU   2

       PHV     PROGRAM#    ACS    OUTLINE USER# EXEC PARSE ALL_ELA|AVG_ELA  CPU  IO CC CL AP PL_JAVA  BUFF CELLIO WRITE READ OFLIN OFLOUT ROWS# FETCHES
    ---------- -------- --------- ------- ----- ---- ----- -------+------- ----- -- -- -- -- ------- ----- ------ ----- ---- ----- ------ ----- -------
    3702721588 0        SHAREABLE         SYS     66    66   2.21m|  2.01s 1.96s  0  0  0  0       0 365     0  B  0  B 0  B  0  B   0  B     1       1
                                                                  |

    Result written to D:\dbcli\cache\orcl\clob_1.txt
    SQL_TEXT
    ---------------------------------------------------------------------------------------------------------------------------------------------------
    select count(*) from wri$_optstat_opr o, wri$_optstat_opr_tasks t where o.id = t.op_id(+) and o.operation = 'gather_database_stats (auto)' and (not
     '//error'),   '^<error>ORA-200[0-9][0-9]') or  not regexp_like(   extract(xmltype('<notes>' || t.notes || '</notes>'), '//error'),   '^<error>ORA-

    --[[
        @VER12: 12.1={} default={--}
        @VER122: 12.2={} default={--}
        @VER:   11.2={} DEFAULT={--}
        @VER23: 23={-RESULT_CACHE_EXECUTIONS} DEFAULT={}
        @ver18: 18={1} default={1e4}
        @check_access_hist: dba_hist_sqltext={} default={--}
        @check_access_bind: dba_hist_sqlbind={1} default={0}
        @check_access_pdb : awrpdb={AWR_PDB_ACTIVE_SESS_HISTORY} default={DBA_HIST_ACTIVE_SESS_HISTORY}
        @ARGS: 1
        &V3  : default={} q={Q} l={L}
        &V2  : default={&instance}
    --]]
]]*/
set feed off
COL AVG_ELA,ALL_ELA,CPU,IO,CC,CL,AP,PL_JAVA,Parse|CPU FORMAT USMHD2
COL CELLIO,READ,WRITE,CELLIO,OFLIN,OFLOUT FORMAT KMG
COL buffs,reads,dxws,Parse|Buffs for tmb2
VAR c REFCURSOR;
VAR b REFCURSOR "Bind List"
VAR src  VARCHAR2;
VAR inst VARCHAR2;
VAR txt  CLOB;
SET VERIFY OFF AUTOHIDE all

DECLARE
    sql_text  CLOB;
    text      CLOB;
    inst      INT := regexp_substr(:v2, '^\d+$');
    child     INT := regexp_substr(:v3, '^\d+$');
    binds     xmltype := xmltype('<BINDS/>');
    name      VARCHAR2(128);
    elem      xmltype;
    bind_val  sys.anydata;
    bind_type VARCHAR2(128);
    dtype     VARCHAR2(128);
    val       VARCHAR2(128);
    str_val   VARCHAR2(32767);
    cur       SYS_REFCURSOR;
    not_null  BOOLEAN;
    opname    VARCHAR2(128);
    occu      PLS_INTEGER := 1;
    last_cap  VARCHAR2(20);
    PROCEDURE repl(format VARCHAR2, value VARCHAR2, defaults VARCHAR2 := NULL) IS
        val VARCHAR2(32767);
        fmt VARCHAR2(300) := format;
    BEGIN
        IF opname IN ('EXECUTE', 'DECLARE', 'BEGIN', 'CALL') THEN
            IF last_cap IS NULL THEN
                str_val := name;
                RETURN;
            END IF;
            occu := 0;
        END IF;
        IF value IS NULL AND defaults IS NULL THEN
            fmt := replace(fmt, q'['%s']', '%s');
        ELSIF instr(value, '''') > 0 THEN
            fmt := replace(fmt, q'['%s']', 'q''!%s!''');
        END IF;
        val     := utl_lms.format_message(fmt, coalesce(CASE WHEN fmt LIKE '%YYYY-%' THEN replace(replace(value, 'T', ' '), 'Z') ELSE value END, defaults, 'NULL'));
        str_val := val;
        text    := regexp_replace(text, '#!' || name || '!#', val, 1, occu, 'i');
    END;
BEGIN
    BEGIN
        SELECT *
        INTO   sql_text, :src, :inst
        FROM   (SELECT sql_fulltext sql_text, 'gv$active_session_history' src, 'inst_id' inst
                FROM   gv$sqlarea
                WHERE  sql_id = '&v1'
                AND    rownum < 2
                $IF dbms_db_version.version >11 $THEN
                UNION ALL
                SELECT to_clob(sql_text) sql_text, 'gv$active_session_history' src, 'inst_id' inst
                FROM   gv$sql_monitor
                WHERE  sql_id = '&v1'
                AND    sql_text IS NOT NULL
                AND    is_full_sqltext = 'Y'
                AND    rownum < 2
                $END
                &check_access_hist  union all select sql_text,q'[(select /*+full(a.AWR_CDB_ACTIVE_SESS_HISTORY.ash)*/ * from &check_access_pdb a where dbid='&dbid')]','instance_number' inst from dba_hist_sqltext src where sql_id='&v1' and ROWNUM<2
                )
        WHERE  rownum < 2;
    EXCEPTION
        WHEN OTHERS THEN
            :src  := 'gv$active_session_history';
            :inst := 'inst_id';
            :txt  := '';
            OPEN :c FOR SELECT '<No Result>' sql_text FROM dual;
            RETURN;
    END;

    IF child IS NOT NULL OR upper(:v3) IN ('-L', 'L') THEN
        dbms_lob.createtemporary(text, TRUE);
        dbms_lob.append(text, sql_text);
        dbms_lob.writeappend(text, 1, ' ');
        text    := regexp_replace(text, '^\s*/\*.*?\*/', '', 'in');
        text    := regexp_replace(text, q'{:("?)([0-9a-zA-Z$_#]+)\1([^0-9a-zA-Z'$_#])}', '#!:\2!#\3');
        opname  := upper(regexp_substr(text, '\w+'));

        FOR r IN (WITH qry AS
                      (SELECT a.*, dense_rank() over(ORDER BY captured, r DESC) seq
                       FROM   (SELECT a.*, decode(max(was_captured) over(PARTITION BY r), 'YES', 0, 1) captured
                               FROM   (SELECT max(last_captured) over(PARTITION BY child_number, inst_id) || child_number || ':' || inst_id r,
                                              '' || child_number c,
                                              was_captured,
                                              position,
                                              name,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              inst_id,
                                              last_captured,
                                              'GV$SQL_BIND_CAPTURE' src
                                       FROM   gv$sql_bind_capture a
                                       WHERE  sql_id = '&v1'
                                       AND    child_number = nvl(child, child_number)
                                       AND    inst_id = nvl(inst, inst_id)
                                       $IF &check_access_bind=1 $THEN
                                       UNION ALL
                                       SELECT max(last_captured) over(PARTITION BY dbid, snap_id, instance_number) || dbid || ':' || snap_id || ':' || instance_number,
                                              '' || snap_id c,
                                              was_captured,
                                              position,
                                              name,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              instance_number,
                                              last_captured,
                                              'DBA_HIST_SQLBIND' src
                                       FROM   dba_hist_sqlbind a
                                       WHERE  sql_id = '&v1'
                                       AND    dbid = '&dbid'
                                       AND    snap_id = nvl(child, snap_id)
                                       AND    instance_number = nvl(inst, instance_number)
                                       $END
                                       ) a) a)
                      SELECT inst_id inst,
                             position pos#,
                             qry.name,
                             datatype,
                             datatype_string,
                             value_string,
                             value_anydata,
                             to_char(qry.last_captured) last_captured,
                             src
                      FROM   qry
                      WHERE  seq = 1
                      ORDER  BY position) LOOP
            name     := r.name;
            dtype    := r.datatype_string;
            bind_val := r.value_anydata;
            not_null := bind_val IS NOT NULL;
            last_cap := r.last_captured;
            CASE regexp_replace(dtype, '\(\d+\)')
                WHEN 'NUMBER' THEN
                    repl('%s', CASE WHEN not_null THEN anydata.accessnumber(bind_val) END, 'TO_NUMBER(NULL)');
                WHEN 'BINARY_DOUBLE' THEN
                    repl('TO_BINARY_DOUBLE(%s)', CASE WHEN not_null THEN anydata.accessbdouble(bind_val) END);
                WHEN 'BINARY_FLOAT' THEN
                    repl('TO_BINARY_FLOAT(%s)', CASE WHEN not_null THEN anydata.accessbfloat(bind_val) END);
                WHEN 'VARCHAR' THEN
                    repl('''%s''', CASE WHEN not_null THEN anydata.accessvarchar(bind_val) END);
                WHEN 'VARCHAR2' THEN
                    repl('''%s''', CASE WHEN not_null THEN anydata.accessvarchar2(bind_val) END);
                WHEN 'CHAR' THEN
                    repl('''%s''', CASE WHEN not_null THEN anydata.accesschar(bind_val) END);
                WHEN 'NCHAR' THEN
                    repl('TO_NCHAR(''%s'')', CASE WHEN not_null THEN anydata.accessnchar(bind_val) END);
                WHEN 'NVARCHAR2' THEN
                    repl('TO_NCHAR(''%s'')', CASE WHEN not_null THEN anydata.accessnvarchar2(bind_val) END);
                WHEN 'CLOB' THEN
                    NULL;
                WHEN 'BLOB' THEN
                    NULL;
                WHEN 'DATE' THEN
                    repl(q'[TO_DATE('%s','YYYY-MM-DD HH24:MI:SS')]', CASE WHEN not_null THEN anydata.accessdate(bind_val) END);
                WHEN 'TIMESTAMP' THEN
                    repl(q'[TO_TIMESTAMP('%s','YYYY-MM-DD HH24:MI:SSxff')]', CASE WHEN not_null THEN anydata.accesstimestamp(bind_val) END);
                WHEN 'TIMESTAMP WITH TIME ZONE' THEN
                    repl(q'[TO_TIMESTAMP_TZ('%s','YYYY-MM-DD HH24:MI:SSxff TZH:TZM')]', CASE WHEN not_null THEN anydata.accesstimestamptz(bind_val) END);
                WHEN 'TIMESTAM WITH LOCAL TIME ZONE' THEN
                    repl(q'[TO_TIMESTAMP_TZ('%s','YYYY-MM-DD HH24:MI:SSxff TZH:TZM')]', CASE WHEN not_null THEN anydata.accesstimestampltz(bind_val) END);
                WHEN 'RAW' THEN
                    repl(q'[HEXTORAW('%s')]', rawtohex(CASE WHEN not_null THEN anydata.accessraw(bind_val) END));
                WHEN 'ROWID' THEN
                    repl('CAST(''%s'' AS ROWID)', CASE WHEN not_null THEN anydata.accessvarchar2(bind_val) END);
                WHEN 'UROWID' THEN
                    repl('CAST(''%s'' AS UROWID)', CASE WHEN not_null THEN anydata.accessurowid(bind_val) END);
                WHEN 'INTERVAL DAY TO' THEN
                    repl('TO_DSINTERVAL(''%s'')', CASE WHEN not_null THEN anydata.accessvarchar2(bind_val) END);
                WHEN 'INTERVAL YEAR TO' THEN
                    repl('TO_YMINTERVAL(''%s'')', CASE WHEN not_null THEN anydata.accessvarchar2(bind_val) END);
                ELSE
                    IF dtype IN ('CURSOR', 'NESTED TABLE', 'VARRAY') THEN
                        repl(name || '/*%s*/', dtype);
                    ELSE
                        repl('NULL/*' || name || ':%s*/', dtype);
                    END IF;
            END CASE;
            SELECT xmlelement("BIND",
                              xmlelement("inst", r.inst),
                              xmlelement("pos", r.pos#),
                              xmlelement("name", r.name),
                              xmlelement("value", nvl(str_val, r.value_string)),
                              xmlelement("dtype", dtype),
                              xmlelement("last_captured", r.last_captured),
                              xmlelement("src", r.src))
            INTO   elem
            FROM   dual;
            binds := binds.appendchildxml('/*', elem);
        END LOOP;
        text     := trim(regexp_replace(text, '#!(:[0-9a-zA-Z$_#]+)!#', '\1'));
        sql_text := text;
        OPEN cur FOR SELECT text sql_text FROM dual;
        OPEN :b FOR
            SELECT extractvalue(column_value, '//inst') + 0 inst,
                   extractvalue(column_value, '//pos') + 0 pos#,
                   cast(extractvalue(column_value, '//name') AS VARCHAR2(128)) name,
                   extractvalue(column_value, '//value') replace_text,
                   cast(extractvalue(column_value, '//dtype') AS VARCHAR2(30)) data_type,
                   cast(extractvalue(column_value, '//last_captured') AS VARCHAR2(20)) last_captured,
                   cast(extractvalue(column_value, '//src') AS VARCHAR2(30)) source
            FROM   TABLE(xmlsequence(extract(binds, '/BINDS/BIND')));
    ELSIF upper(:v3) IN ('-Q', 'Q') THEN
        OPEN cur FOR
            SELECT *
            FROM   (SELECT *
                    FROM   (SELECT inst_id, child_number "Child#/Snap#", max(last_captured) last_captured,
                                   COUNT(nullif(was_captured, 'NO')) || '/' || COUNT(1) captures,
                                   'GV$SQL_BIND_CAPTURE' souce_view
                            FROM   gv$sql_bind_capture a
                            WHERE  sql_id = '&v1'
                            AND    inst_id = nvl(inst, inst_id)
                            GROUP  BY inst_id, child_number
                            $IF &check_access_bind=1 $THEN
                            UNION ALL
                            SELECT instance_number, snap_id, max(last_captured) last_captured,
                                   COUNT(nullif(was_captured, 'NO')) || '/' || COUNT(1) captures,
                                   'DBA_HIST_SQLBIND' souce_view
                            FROM   dba_hist_sqlbind a
                            WHERE  sql_id = '&v1'
                            AND    dbid = '&dbid'
                            AND    instance_number = nvl(inst, instance_number)
                            GROUP  BY instance_number, snap_id
                            $END
                            )
                    WHERE  nvl(last_captured, sysdate) BETWEEN nvl(to_date(:starttime, 'YYMMDDHH24MISS'), sysdate - 7) AND nvl(to_date(:endtime, 'YYMMDDHH24MISS'), sysdate)
                    ORDER  BY 3 DESC, 2 DESC, 1)
            WHERE  rownum <= 50;
    ELSE
        OPEN cur FOR SELECT sql_text sql_text FROM dual;
    END IF;
    :c   := cur;
    :txt := sql_text;
END;
/
PRINT b;
PRINT c;
save txt last_sql_&V1..txt

col MEM,OPTIMAL,ONEPASS,TEMP,LAST_TEMP FOR KMG2
col ACTIVES FOR usmhd2
col OPTIMALS,ONEPASS,MULTIS FOR TMB2
COL FLASH FOR PCT2

grid {
[[/*grid={topic='ASH Result'}*/
  SELECT *
  FROM   (SELECT /*+full(a.a) leading(a.a) use_hash(a.a a.s) swap_join_inputs(a.s)
                    full(A.GV$ACTIVE_SESSION_HISTORY.A)
                    leading(A.GV$ACTIVE_SESSION_HISTORY.A)
                    use_hash(A.GV$ACTIVE_SESSION_HISTORY.A A.GV$ACTIVE_SESSION_HISTORY.S)
                    swap_join_inputs(A.GV$ACTIVE_SESSION_HISTORY.S)
                    use_hash(@GV_ASHV A@GV_ASHV)
                */
                 &VER top_level_sql_id top_sql,
                 COUNT(1) aas,
                 nvl(event, 'ON CPU') event,
                 sql_plan_hash_value phv,
                 &VER sql_plan_line_id plan_line,
                 &VER nvl(trim(sql_plan_operation || ' ' || sql_plan_options), top_level_call_name) operation,
                 plsql_entry_object_id program#, plsql_object_id call#
          FROM   &src a
          WHERE  '&V1' in(sql_id, top_level_sql_id)
          AND    &inst=nvl(regexp_substr('&V2','^\d+$')+0,&inst)
          AND    sample_time+0 BETWEEN nvl(to_date('&starttime','YYMMDDHH24MISS'),sysdate-7) and nvl(to_date('&endtime','YYMMDDHH24MISS'),sysdate)
          GROUP  BY sql_plan_hash_value, plsql_entry_object_id, plsql_object_id, event
                    &VER ,sql_plan_line_id,top_level_sql_id,NVL(TRIM(SQL_PLAN_OPERATION||' '||SQL_PLAN_OPTIONS),TOP_LEVEL_CALL_NAME)
          ORDER  BY aas DESC)
  WHERE  rownum <= 10]],
'|',[[/*grid={topic='SQL Workarea'}*/
SELECT /*+use_hash(a b)*/ phv,
       operation_type,
       policy,
       COUNT(1) cnt,
       nullif(max(active_time * &ver18), 0) actives,
       max(last_memory_used) mem,
       nullif(max(last_degree), 1) last_dop,
       '|' "|",
       last_execution last_exec,
       nullif(sum(optimal_executions), 0) optimals,
       nullif(max(estimated_optimal_size), 0) optimal,
       nullif(sum(onepass_executions), 0) onepasses,
       nullif(max(estimated_onepass_size), 0) onepass,
       nullif(sum(multipasses_executions), 0) multis,
       '|' "|",
       nullif(max(max_tempseg_size), 0) temp,
       nullif(max(last_tempseg_size), 0) last_temp
FROM   (select * from gv$sql_workarea where sql_id=:v1) a
JOIN   (select inst_id, sql_id, child_number, plan_hash_value phv from gv$sql where sql_id=:v1) b
USING  (inst_id, sql_id, child_number)
GROUP  BY phv, operation_type, policy, last_execution
ORDER  BY mem + temp DESC NULLS LAST]]}

PRO
SELECT plan_hash_value plan_hash,
       &ver12 max(phf) plan_full,
       max(bg) "Parse|Buffs",
       max(cpu) "Parse|CPU",
       nullif(program_id || nullif('#' || program_line#, '#0'), '0') program#,
       trim(chr(10) FROM ''
       &ver12      || decode(is_reoptimizable, 'Y', 'REOPTIMIZABLE' || chr(10))
       &ver12      || decode(is_resolved_adaptive_plan, 'Y', 'RESOLVED_ADAPTIVE_PLAN' || chr(10))
       &ver        || decode(is_bind_sensitive, 'Y', 'BIND_SENSITIVE' || chr(10))
       &ver        || decode(is_bind_aware, 'Y', 'BIND_AWARE' || chr(10))
       &ver        || decode(is_shareable, 'Y', 'SHAREABLE' || chr(10))
       &ver        || decode(is_obsolete, 'Y', 'OBSOLETE' || chr(10))
       &ver122     || decode(is_rolling_invalid, 'Y', 'ROLLING_INVALID' || chr(10))
       &ver122     || decode(is_rolling_refresh_invalid, 'Y', 'ROLLING_REFRESH_INVALID' || chr(10))
       ) info,
       trim('/' FROM sql_profile
       &ver || '/' || sql_plan_baseline
       &ver || '/' || sql_patch
       ) outline,
       parsing_schema_name user#,
       SUM(exec) AS exec,
       SUM(parse_calls) parse,
       round(SUM(elapsed_time), 3) all_ela,
       '|' "|",
       round(SUM(elapsed_time) / SUM(exec), 3) avg_ela,
       round(SUM(cpu_time) / SUM(exec), 3) cpu,
       nullif(round(SUM(user_io_wait_time) / SUM(exec), 3), 0) io,
       nullif(round(SUM(concurrency_wait_time) / SUM(exec), 3), 0) cc,
       nullif(round(SUM(cluster_wait_time) / SUM(exec), 3), 0) cl,
       nullif(round(SUM(application_wait_time) / SUM(exec), 3), 0) ap,
       nullif(round(SUM(plsql_exec_time + java_exec_time) / SUM(exec), 3), 0) pl_java,
       nullif(round(SUM(buffer_gets) / SUM(exec), 3), 0) AS buffs,
       nullif(round(SUM(disk_reads) / SUM(exec), 3), 0) reads,
       nullif(round(SUM(direct_writes) / SUM(exec), 3), 0) dxws,
       &ver nullif(round(SUM(io_interconnect_bytes) / SUM(exec), 3), 0) cellio,
       &ver nullif(round(SUM(physical_write_bytes) / SUM(exec), 3), 0) AS write,
       &ver nullif(round(SUM(physical_read_bytes) / SUM(exec), 3), 0) AS read,
       &ver nullif(round(SUM(optimized_phy_read_requests) / nullif(SUM(physical_read_requests), 0), 3), 0) AS flash,
       &ver nullif(round(SUM(io_cell_offload_eligible_bytes) / SUM(exec), 3), 0) oflin,
       &ver nullif(round(SUM(io_cell_offload_returned_bytes) / SUM(exec), 3), 0) oflout,
       nullif(round(SUM(rows_processed) / SUM(exec), 3), 0) rows#,
       nullif(round(SUM(fetches) / SUM(exec), 3), 0) fetches
FROM   (SELECT greatest(executions + users_executing &VER23, 1) exec, a.*
        FROM   gv$sql a
        WHERE  sql_id = :v1
        AND    inst_id = nvl(regexp_substr(:v2, '^\d+$') + 0, inst_id))
LEFT JOIN (
        SELECT inst_id, sql_id, plan_hash_value,
               max(nullif(to_char(regexp_substr(other_xml, '"plan_hash_full".*?(\d+)', 1, 1, 'n', 1)), '0')) phf,
               avg(to_number(to_char(regexp_substr(other_xml, '"bg".*?(\d+)', 1, 1, 'n', 1)))) bg,
               avg(to_number(to_char(regexp_substr(other_xml, '"cpu_time".*?(\d+)', 1, 1, 'n', 1))) * 1000) cpu
        FROM   gv$sql_plan
        WHERE  sql_id = :v1
        AND    inst_id = nvl(regexp_substr(:v2, '^\d+$') + 0, inst_id)
        AND    other_xml IS NOT NULL
        GROUP  BY inst_id, sql_id, plan_hash_value
) USING(inst_id, sql_id, plan_hash_value)
GROUP  BY sql_id,
          plan_hash_value,
          &ver12 is_reoptimizable, is_resolved_adaptive_plan,
          &ver122 is_rolling_invalid, is_rolling_refresh_invalid,
          &ver is_bind_sensitive, is_obsolete, is_bind_aware, is_shareable,
          program_id,
          program_line#,
          sql_profile,
          &ver sql_plan_baseline, sql_patch,
          parsing_schema_name;

--show sqlver -s"&v1"
