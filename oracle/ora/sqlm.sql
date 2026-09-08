/*[[
        Get resource usage from SQL Monitor. Usage: @@NAME {[<sql_id> {[-l|-d|-a] [<sql_exec_id>|<plan_hash>|<report_id>]}}|"<query>"} | {. <keyword>} [-u|-f"<filter>"] [-avg]
        Related parameters for SQL Monitor:
                _sqlmon_recycle_time,_sqlmon_max_planlines,_sqlmon_max_plan,_sqlmon_threshold,control_management_pack_access,statistics_level
        A SQL can be forced to generate the SQL Monitor report by the following ALTER SYSTEM statement:
                ALTER SYSTEM SET EVENTS 'sql_monitor [sql: <sql_id1>|sql: <sql_id2>] force=true';

        Usages:
             1. @@NAME <sql_id> [<sql_exec_id>|<report_id>|<phv>] : Extract the SQL Monitor report of a specific sql_id, options: -s,-a,-f"<format>"
             2. @@NAME [. <keyword>]                              : List recent SQL Monitor reports, options: -avg,-u,-f"<filter>"
             3. @@NAME -snap <sec> <sid>                          : Monitor a specific <sid> for <sec> seconds, then list the SQL Monitor result, options: -avg
             4. @@NAME "<Query>"                                  : Read the SQL Monitor report from the target query (which returns a CLOB) and print it
             5. @@NAME <report_id>                                : Read the SQL Monitor report from dba_hist_reports with a specific report_id
             6. @@NAME <sql_id> -l [-a] [plan_hash|sql_exec_id]   : List the reports and generate the Perf Hub report for a specific sql_id, options: -avg,-u,-a,-f"<filter>"
             7. @@NAME <sql_id> -d [<plan_hash> [YYYYMMDDHH24MI]] : Extract the SQL detail report

        Options:
            -u     : Only show the SQL list within the current schema
            -f     : List the records that match the predicates, i.e.: -f"MODULE='DBMS_SCHEDULER'"
            -l     : List the available SQL Monitor reports for the specific SQL Id
            -a     : When used together with the "-l" option, generate a SQL Hub report
            -avg   : Show the average time when listing the SQL Monitor reports

        Format:
             -active : Output the report in active HTML format
             -em     : Output the report in EM HTML format
             -html   : Output the report in HTML format
             -text   : Output the report in text format

     --[[
            @ver: 12.2={} 11.2={--}
            &uniq:    default={count(DISTINCT sql_exec_id||','||to_char(sql_exec_start,'YYYYMMDDHH24MISS'))} l={1}
            &group : default={}, l={,sql_exec_id,plan_hash,sql_exec_start,last_refresh_time}
            &fields: {default={&uniq execs,GREATEST(max(last_refresh_time - sql_exec_start) keep(dense_rank last order by last_refresh_time) *86400*1e6, 1E6) "LAST",
                                to_char(MAX(last_refresh_time), 'YYMMDD HH24:MI:SS') last_seen,}
                      l={MAX(sid || ',@' || inst_id) keep(dense_rank LAST ORDER BY last_refresh_time) sid,}}
            &filter: default={1=1},f={},l={sql_id=sq_id},snap={DBOP_EXEC_ID=dopeid and dbop_name=dopename},u={username=nvl('&0',sys_context('userenv','current_schema'))}
            &avg : default={1} avg={&uniq}
            &out: default={active} html={html} em={em} text={text}
            &snap: default={0} snap={1}
            &showhub: default={0} a={1}
            &rpt   : default={0} d={1}
            &v1    : default={} x={&_sql_id}
            @check_access_hub : SYS.DBMS_PERF={&showhub} default={0}
            @check_access_sqlm: SYS.DBMS_SQL_MONITOR/SYS.DBMS_LOCK={1} default={0}
            @check_access_report: SYS.DBA_HIST_REPORTS={1} default={0}
     --]]
]]*/

set feed off VERIFY off printsize 3000
var pred number;
BEGIN
    :pred := case when coalesce(:v1,:v2) is not null then 1 else 0 end;
END;
/
var c refcursor;
var c0 refcursor;
var c1 refcursor;
var c2 refcursor;
var rs CLOB;
var filename varchar2;
var plan_hash number;
col parse,queue,cpu,app,cc,cl,plsql,java,pljava,io,oth for pct2
col dur,last,ela,time format usmhd1
col read,write,iosize,mem,temp,cellio,buffget,offload,offlrtn,calc_kmg,ofl,bytes,OFLOUT format kmg1
col est_cost,est_rows,act_rows,ioreq,outputs,FETCHES,dxwrite,calc_tmb format TMB1
col execs for tmb0
set autohide col

DECLARE /*+no_monitor*/
    plan_hash  INT := regexp_substr(:v2, '^\d+$');
    start_time DATE;
    end_time   DATE;
    sq_id      VARCHAR2(4000) := :v1;
    sq_id1     VARCHAR2(4000) := :v1;
    inst       INT := :instance;
    did        INT := :dbid;
    rpt_id     INT;
    execs      INT;
    filename   VARCHAR2(100);
    sqlmon     CLOB;
    content    CLOB;
    txt        CLOB;
    lst        SYS.ODCIVARCHAR2LIST;
    dopename   VARCHAR2(30);
    dopeid     INT;
    keyw       VARCHAR2(300) := lower(:v2);
    c2         SYS_REFCURSOR;
    sql_exec   INT;
    sql_start  DATE;
    last_date  DATE;
    serial     INT;
    xml        xmltype;
    mon        xmltype;
    elem       xmltype;
    descs      SYS.ODCIARGDESCLIST;
    TYPE t_fmt IS TABLE OF VARCHAR2(50);
    fmt        t_fmt;
    c0         SYS_REFCURSOR;
    dyn_lvl    PLS_INTEGER;
    PROCEDURE report_start IS
    BEGIN
        IF dyn_lvl IS NULL THEN
            SELECT value
            INTO   dyn_lvl
            FROM   v$parameter
            WHERE  name = 'optimizer_dynamic_sampling';
        END IF;
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling=5';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;

    PROCEDURE report_end IS
    BEGIN
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling=' || dyn_lvl;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;

    PROCEDURE wr(msg VARCHAR2) IS
    BEGIN
        dbms_lob.writeappend(txt, nvl(length(msg), 1) + 1, chr(10) || nvl(msg, '.'));
    END;

    PROCEDURE flush(section VARCHAR2) IS
    BEGIN
        IF lst.count > 0 THEN
            wr(' ' || chr(10));
            wr(lpad('=', 66, '='));
            wr('|  ' || rpad(section, 60) || '  |');
            wr(lpad('-', 66, '-'));
            FOR i IN 1 .. lst.count LOOP
                wr(lst(i));
            END LOOP;
        END IF;
    END;

    --Refer to: https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/
    FUNCTION decompress(base64_str VARCHAR2) RETURN CLOB IS
        v_clob       CLOB;
        v_blob       BLOB;
        dest_offset  INTEGER := 1;
        src_offset   INTEGER := 1;
        prev         INTEGER := 1;
        curr         INTEGER := 1;
        lob_csid     NUMBER := dbms_lob.default_csid;
        lang_context INTEGER := dbms_lob.default_lang_ctx;
        warning      INTEGER;

        PROCEDURE ap(p_line VARCHAR2) IS
            r RAW(32767) := utl_raw.cast_to_raw(p_line);
        BEGIN
            r := utl_encode.base64_decode(r);
            dbms_lob.writeappend(v_blob, utl_raw.length(r), r);
        END;

        FUNCTION zlib_decompress(p_src IN BLOB) RETURN BLOB IS
            t_out      BLOB;
            t_tmp      BLOB;
            t_raw      RAW(1);
            t_buffer   RAW(32767);
            t_hdl      BINARY_INTEGER;
            t_s1       PLS_INTEGER; -- s1 part of adler32 checksum
            t_last_chr PLS_INTEGER;
            t_size     PLS_INTEGER := length(p_src);
            t_adj      PLS_INTEGER;
            sq         VARCHAR2(2000) := '
            declare x raw(?);
            begin
                utl_compress.lz_uncompress_extract(:t_hdl, x);
                :buff := x;
            end;';
        BEGIN
            dbms_lob.createtemporary(t_out, FALSE);
            dbms_lob.createtemporary(t_tmp, FALSE);
            t_tmp := hextoraw('1F8B0800000000000003'); -- gzip header
            dbms_lob.copy(t_tmp, p_src, dbms_lob.getlength(p_src) - 2 - 4, 11, 3);
            dbms_lob.append(t_tmp, hextoraw('0000000000000000')); -- add a fake trailer
            t_hdl := utl_compress.lz_uncompress_open(t_tmp);
            t_s1  := 1;
            LOOP
                BEGIN
                    t_adj := least(t_size * 5, 4000);
                    IF t_adj < 128 THEN
                        utl_compress.lz_uncompress_extract(t_hdl, t_raw);
                        t_buffer := t_raw;
                        t_size   := 0;
                    ELSE
                        EXECUTE IMMEDIATE REPLACE(sq, '?', t_adj)
                            USING IN OUT t_hdl, IN OUT t_buffer;
                        t_size := t_size - floor(t_adj / 5);
                    END IF;
                    t_adj := utl_raw.length(t_buffer);
                    dbms_lob.append(t_out, t_buffer);
                    FOR i IN 1 .. t_adj LOOP
                        t_s1 := mod(t_s1 + to_number(rawtohex(utl_raw.substr(t_buffer, i, 1)), 'xx'), 65521);
                    END LOOP;
                EXCEPTION
                    WHEN OTHERS THEN
                        EXIT;
                END;
            END LOOP;

            t_last_chr := to_number(dbms_lob.substr(p_src, 2, dbms_lob.getlength(p_src) - 1), '0XXX') - t_s1;
            IF t_last_chr < 0 THEN
                t_last_chr := t_last_chr + 65521;
            END IF;
            dbms_lob.append(t_out, hextoraw(to_char(t_last_chr, 'fm0X')));
            IF utl_compress.isopen(t_hdl) THEN
                utl_compress.lz_uncompress_close(t_hdl);
            END IF;
            dbms_lob.freetemporary(t_tmp);
            RETURN t_out;
        END;
    BEGIN
        dbms_lob.createtemporary(v_blob, TRUE);
        dbms_lob.createtemporary(v_clob, TRUE);
        ap(base64_str);
        v_blob := zlib_decompress(v_blob);
        dbms_lob.converttoclob(v_clob,
                               v_blob,
                               dbms_lob.lobmaxsize,
                               dest_offset,
                               src_offset,
                               lob_csid,
                               lang_context,
                               warning);
        RETURN v_clob;
    END;
BEGIN
    IF &SNAP=1 THEN
        $IF &check_access_sqlm=0 OR dbms_db_version.release+dbms_db_version.version<14 $THEN
            raise_application_error(-20001,'You dont'' have access on dbms_sql_monitor/dbms_lock, or db version < 12.2!');
        $ELSE
            dopename := 'DBCLI_SNAPPER_' || userenv('SESSIONID');
            SELECT max(serial#)
            INTO   serial
            FROM   v$session
            WHERE  sid = regexp_substr(plan_hash, '^\d+$');
            IF NOT regexp_like(sq_id, '^\d+$') OR NOT regexp_like(plan_hash, '^\d+$') THEN
                raise_application_error(-20001, 'Usage: ora sqlm -snap <secs> <sid>');
            ELSIF serial IS NULL THEN
                raise_application_error(-20001, 'session#' || plan_hash || ' cannot be found in v$session!');
            END IF;
            dopeid := sys.dbms_sql_monitor.begin_operation(
                          dbop_name       => dopename,
                          dbop_eid        => dopeid,
                          forced_tracking => sys.dbms_sql_monitor.force_tracking,
                          session_id      => plan_hash,
                          session_serial  => serial);
            sys.dbms_lock.sleep(sq_id + 0);
            sys.dbms_sql_monitor.end_operation(dopename, dopeid);
            dbms_output.put_line('Filter: dbop_name=''' || dopename || ''' and dbop_exec_id=' || dopeid);
            OPEN c2 FOR
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ *
                FROM   (SELECT MAX(decode(mod(rnk, 3), 1, name)) stat_name#1,
                               MAX(decode(mod(rnk, 3), 1, value)) stat_value#1,
                               MAX(decode(mod(rnk, 3), 2, name)) stat_name#2,
                               MAX(decode(mod(rnk, 3), 2, value)) stat_value#2,
                               MAX(decode(mod(rnk, 3), 0, name)) stat_name#3,
                               MAX(decode(mod(rnk, 3), 0, value)) stat_value#3
                        FROM   (SELECT /*+ordered use_hash(b)*/
                                       substr(name, 1, 35) name,
                                       SUM(value) value,
                                       row_number() over(ORDER BY SUM(value) DESC) rnk
                                FROM   gv$sql_monitor
                                JOIN   gv$sql_monitor_sesstat
                                USING  (inst_id, key)
                                NATURAL JOIN v$statname
                                WHERE  value > 0
                                AND    dbop_name = dopename
                                AND    dbop_exec_id = dopeid
                                GROUP  BY name)
                        GROUP  BY ceil(rnk / 3)
                        ORDER  BY stat_value#1 DESC NULLS LAST)
                WHERE  rownum <= 30;
            sq_id     := NULL;
            keyw      := NULL;
            plan_hash := NULL;
        $END
        :c2 := c2;
    END IF;

    IF sqlmon IS NULL AND regexp_like(ltrim(sq_id), '^(select|with) ', 'i') THEN
        BEGIN
            sq_id := regexp_replace(sq_id, '[;/[:space:][:cntrl:]]+$');
            EXECUTE IMMEDIATE 'SELECT * FROM (' || sq_id || ') WHERE ROWNUM<2' INTO sqlmon;
        EXCEPTION
            WHEN no_data_found THEN
                raise_application_error(-20001, 'Cannot fetch report with SQL: ' || sq_id);
            WHEN OTHERS THEN
                raise_application_error(-20001, 'Error ' || sqlerrm || ' on fetching report with SQL: ' || sq_id);
        END;
    ELSIF sqlmon IS NULL AND regexp_like(sq_id, '^\d+$') THEN
        $IF &check_access_report=1 $THEN
            rpt_id := 0 + sq_id;
            report_start;
            sqlmon := dbms_auto_report.report_repository_detail(rid => rpt_id, type => 'XML');
            report_end;
        $END
        IF sqlmon IS NULL THEN
            raise_application_error(-20001, 'SQL_ID ' || sq_id || ' should not be a number!');
        END IF;
    END IF;

    IF sqlmon IS NOT NULL THEN
        sqlmon := trim(regexp_substr(sqlmon, '<report .*</report>', 1, 1, 'n'));
        IF sqlmon IS NULL OR length(sqlmon) = 0 THEN
            raise_application_error(-20001, 'Target is not a valid SQL Monitor Report file or Report Id!');
        END IF;
        xml := xmltype(sqlmon);
        mon := xml.extract('//report_parameters[1]');

        IF mon IS NULL THEN
            mon := xml.extract('/report/text()');
            IF mon IS NULL THEN
                raise_application_error(-20001, 'Target is not a valid SQL Monitor Report file or Report Id!');
            END IF;
            sqlmon := trim(mon.getclobval());
            IF length(sqlmon) > 32767 THEN
                raise_application_error(-20001, 'Unsupported SQL Monitor Report file whose compressed data over 32 KB!');
            END IF;
            sqlmon := decompress(sqlmon);
            xml := xml.deletexml('*/text()').appendchildxml('/report', xmltype(sqlmon));
            mon := xml.extract('//report_parameters[1]');
        END IF;

        sq_id := mon.extract('//report_parameters/sql_id[1]/text()').getstringval();
        elem  := mon.extract('//report_parameters/sql_exec_id[1]/text()');
        IF rpt_id IS NOT NULL THEN
            filename := 'sqlm_' || sq_id || '_' || rpt_id || '.html';
            rpt_id   := NULL;
        END IF;

        IF elem IS NOT NULL THEN
            sql_exec := elem.getnumberval();
        ELSE
            elem := mon.extract('//report_parameters/*[@sql_exec_id][1]/@sql_exec_id');
            IF elem IS NOT NULL THEN
                sql_exec := elem.getnumberval();
            END IF;
        END IF;
    END IF;

    IF sq_id IS NOT NULL AND '&group' IS NULL THEN
        --EXECUTE IMMEDIATE 'alter session set "_sqlmon_max_planlines"=3000';
        IF xml IS NULL THEN
            BEGIN
                EXECUTE IMMEDIATE 'alter session set events ''emx_control compress_xml=none''';
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;

            sql_exec := plan_hash;

            IF &rpt=0 THEN
                IF sql_exec IS NULL THEN
                    SELECT /*+no_expand no_or_expand*/
                           max(sql_id) keep(dense_rank LAST ORDER BY last_refresh_time, sql_exec_id),
                           max(sql_exec_id) keep(dense_rank LAST ORDER BY last_refresh_time),
                           max(sql_exec_start) keep(dense_rank LAST ORDER BY last_refresh_time),
                           max(last_refresh_time)
                    INTO   sq_id, sql_exec, sql_start, last_date
                    FROM   gv$sql_monitor
                    WHERE  (sql_id = sq_id OR lower(sq_id) IN ('l', 'last') AND inst_id = userenv('instance') AND sid = userenv('sid'))
                    AND    sql_exec_id > 0
                    AND    px_server# IS NULL
                    AND    sql_text IS NOT NULL
                    AND    inst_id = nvl(inst, inst_id);
                ELSE
                    SELECT max(sql_id) keep(dense_rank LAST ORDER BY last_refresh_time, sql_exec_id),
                           max(sql_exec_id) keep(dense_rank LAST ORDER BY last_refresh_time),
                           max(sql_exec_start) keep(dense_rank LAST ORDER BY last_refresh_time)
                    INTO   sq_id, sql_exec, sql_start
                    FROM   gv$sql_monitor
                    WHERE  sql_id = sq_id
                    AND    sql_exec IN (sql_exec_id, sql_plan_hash_value)
                    AND    px_server# IS NULL
                    AND    sql_text IS NOT NULL
                    AND    inst_id = nvl(inst, inst_id);
                END IF;
                $IF &check_access_report=1 $THEN
                    IF lower(sq_id1) NOT IN ('l', 'last') AND (sq_id IS NULL OR nvl(last_date, sysdate - 1) < sysdate - 2/24) THEN
                        SELECT max(key1) keep(dense_rank LAST ORDER BY ptime, key2),
                               max(report_id) keep(dense_rank LAST ORDER BY ptime, key2)
                        INTO   sq_id1, rpt_id
                        FROM   (SELECT /*+no_expand no_or_expand*/
                                       key1, key2, report_id, period_end_time ptime
                                FROM   dba_hist_reports
                                WHERE  key1 = nvl(sq_id, sq_id1)
                                AND    key2 > 0
                                AND    did IN (dbid, con_dbid)
                                AND    (plan_hash IS NULL OR plan_hash IN (key2, report_id) OR instr(report_summary, 'plan_hash>' || plan_hash || '<') > 0)
                                AND    component_name = 'sqlmonitor'
                                AND    instance_number = nvl(inst, instance_number));
                        sq_id := nvl(sq_id1, sq_id);
                    END IF;
                $END

                IF sq_id IS NULL THEN
                    raise_application_error(-20001, 'cannot find relative records for the specific SQL ID!');
                END IF;

                IF rpt_id IS NULL THEN
                    fmt := t_fmt('ALL+PLAN_SKEW+SUMMARY+SQL_FULLTEXT', 'ALL', 'ALL-BINDS', 'ALL-SQL_TEXT', 'ALL-SQL_TEXT-BINDS', 'TYPICAL');
                    report_start;
                    FOR i IN 1 .. fmt.count LOOP
                        BEGIN
                            xml := dbms_sqltune.report_sql_monitor_xml(report_level => fmt(i), sql_id => sq_id, sql_exec_start => sql_start, sql_exec_id => sql_exec, inst_id => inst);
                            dbms_output.put_line('Extracted report level is: ' || fmt(i));
                            EXIT;
                        EXCEPTION
                            WHEN OTHERS THEN
                                IF i = fmt.count THEN
                                    report_end;
                                    RAISE;
                                END IF;
                        END;
                    END LOOP;
                    report_end;
                ELSE
                    $IF &check_access_report=1 $THEN
                        SELECT xmltype(report)
                        INTO   xml
                        FROM   dba_hist_reports_details
                        WHERE  did IN (dbid, con_dbid)
                        AND    report_id = rpt_id
                        AND    instr(report, sq_id) > 0
                        AND    rownum < 2;

                        dbms_output.put_line('Extracted report from dba_hist_reports.');
                    $END
                    NULL;
                END IF;
                filename := 'sqlm_' || sq_id || nullif('_' || keyw, '_') || '.html';
            ELSE
                sql_start := nvl(to_date(nvl(:v3, :starttime), 'yymmddhh24mi'), sysdate - 7);
                report_start;
                xml := xmltype(dbms_sqltune.report_sql_detail(report_level        => 'ALL',
                                                              sql_id              => sq_id,
                                                              sql_plan_hash_value => sql_exec,
                                                              start_time          => sql_start,
                                                              duration            => 86400 * (sysdate - sql_start),
                                                              inst_id             => inst,
                                                              dbid                => did,
                                                              top_n               => 50,
                                                              type                => 'XML'));
                filename := 'sqld_' || sq_id || nullif('_' || keyw, '_') || '.html';
                report_end;
            END IF;
        END IF;

        content := dbms_report.format_report(xml, '&out');

        IF &rpt=0 THEN
            txt := dbms_report.format_report(xml.deletexml('//sql_fulltext'), 'text');
        ELSE
            dbms_lob.createtemporary(txt, TRUE);
        END IF;

        OPEN :c FOR SELECT txt FROM dual;

        --refer to https://ctandrewsayer.wordpress.com/2017/10/19/how-many-rows-were-insertedupdateddeleted-in-my-merge/
        /*$IF dbms_db_version.version>11 $THEN
            OPEN c2 FOR
            SELECT up.plan_line_id,sms.name,UP.type,count(1) processes,
                     decode(decode(up.type,5,max(up.typ1),up.type),
                                 1,sum(up.value)
                                 ,2,sum(up.value)
                                 ,3,sum(up.value)
                                 ,4,max(up.value)
                                 ,min(up.value)) calc_tmb,
                     decode(decode(up.type,5,max(up.typ1),up.type),
                                 1,sum(up.value)
                                 ,2,sum(up.value)
                                 ,3,sum(up.value)
                                 ,4,max(up.value)
                                 ,min(up.value)) calc_kmg,
                     dop_down.value_text, sms.description
            FROM   (SELECT *
                    FROM   (SELECT process_name,
                                     plan_line_id,
                                     otherstat_1_id,
                                     otherstat_1_type,
                                     otherstat_1_value,
                                     otherstat_2_id,
                                     otherstat_2_type,
                                     otherstat_2_value,
                                     otherstat_3_id,
                                     otherstat_3_type,
                                     otherstat_3_value,
                                     otherstat_4_id,
                                     otherstat_4_type,
                                     otherstat_4_value,
                                     otherstat_5_id,
                                     otherstat_5_type,
                                     otherstat_5_value,
                                     otherstat_6_id,
                                     otherstat_6_type,
                                     otherstat_6_value,
                                     otherstat_7_id,
                                     otherstat_7_type,
                                     otherstat_7_value,
                                     otherstat_8_id,
                                     otherstat_8_type,
                                     otherstat_8_value,
                                     otherstat_9_id,
                                     otherstat_9_type,
                                     otherstat_9_value,
                                     otherstat_10_id,
                                     otherstat_10_type,
                                     otherstat_10_value
                            FROM   gv$sql_plan_monitor spm
                            WHERE  spm.sql_id = sq_id
                            AND    spm.sql_exec_id = sql_exec
                            AND    sql_exec_start=sql_start) --
                             unpivot((typ1,id, TYPE, VALUE) --
                             FOR pivId IN((otherstat_1_type,otherstat_1_id, otherstat_1_type, otherstat_1_value) AS 1, (otherstat_1_type,otherstat_2_id, otherstat_2_type, otherstat_2_value) AS 2,
                                        (otherstat_1_type,otherstat_3_id, otherstat_3_type, otherstat_3_value) AS 3, (otherstat_1_type,otherstat_4_id, otherstat_4_type, otherstat_4_value) AS 4,
                                        (otherstat_1_type,otherstat_5_id, otherstat_5_type, otherstat_5_value) AS 5, (otherstat_1_type,otherstat_6_id, otherstat_6_type, otherstat_6_value) AS 6,
                                        (otherstat_1_type,otherstat_7_id, otherstat_7_type, otherstat_7_value) AS 7, (otherstat_1_type,otherstat_8_id, otherstat_8_type, otherstat_8_value) AS 8,
                                        (otherstat_1_type,otherstat_9_id, otherstat_9_type, otherstat_9_value) AS 9, (otherstat_1_type,otherstat_10_id, otherstat_10_type, otherstat_10_value) AS 10))) up
            LEFT   JOIN v$sql_monitor_statname sms
            ON     up.id = sms.id
            LEFT   JOIN (SELECT 'downgrade reason' NAME, 350 VALUE, 'DOP downgrade due to adaptive DOP' value_text
                         FROM   dual
                         UNION ALL
                         SELECT 'downgrade reason' NAME, 351 VALUE, 'DOP downgrade due to resource manager max DOP' value_text
                         FROM   dual
                         UNION ALL
                         SELECT 'downgrade reason' NAME, 352 VALUE, 'DOP downgrade due to insufficient number of processes' value_text
                         FROM   dual
                         UNION ALL
                         SELECT 'downgrade reason' NAME, 353 VALUE, 'DOP downgrade because slaves failed to join' value_text
                         FROM   dual) dop_down
            ON     sms.name = dop_down.name
            AND    up.value = dop_down.value
            WHERE  up.value IS NOT NULL
            group  by  up.plan_line_id, sms.name,up.type, dop_down.value_text, sms.description
            ORDER  BY 1, 2;
        $END
        */
        :c1 := c2;
    ELSE
        OPEN :c FOR
            SELECT * --fix control 26552730 causes ORA-12850: Could not allocate slaves on all specified instances: 2 needed, 0 allocated
            FROM   (SELECT /*+no_expand no_parallel OPT_PARAM('_fix_control' '26552730:0') no_or_expand opt_param('optimizer_dynamic_sampling' 5)*/
                           a.sql_id &group,
                           &fields
                           MAX(nvl(regexp_substr(status, '\(.*\)'), status)) keep(dense_rank LAST ORDER BY last_refresh_time, sid) last_status,
                           '|' "|",
                           greatest(1E6, round(SUM(last_refresh_time - sql_exec_start) / &avg * 86400 * 1e6, 2)) dur,
                           round(SUM(ela) / &avg, 2) ela,
                           nullif(round(SUM(queuing_time) / nullif(SUM(ela), 0), 4), 0) queue,
                           nullif(round(SUM(cpu_time) / nullif(SUM(ela), 0), 4), 0) cpu,
                           nullif(round(SUM(application_wait_time) / nullif(SUM(ela), 0), 4), 0) app,
                           nullif(round(SUM(concurrency_wait_time) / nullif(SUM(ela), 0), 4), 0) cc,
                           nullif(round(SUM(cluster_wait_time) / nullif(SUM(ela), 0), 4), 0) cl,
                           nullif(round(SUM(nvl(plsql_exec_time, 0) + nvl(java_exec_time, 0)) / nullif(SUM(ela), 0), 4), 0) pljava,
                           nullif(round(SUM(user_io_wait_time) / nullif(SUM(ela), 0), 4), 0) io,
                           nullif(round(SUM(nvl(other_time, ela - ela1)) / nullif(SUM(ela), 0), 4), 0) oth,
                           nullif(round(SUM(nvl(physical_read_bytes, 0) + nvl(physical_write_bytes, 0)) / &avg, 2), 0) bytes,
                           &ver nullif(round(SUM(io_cell_offload_eligible_bytes) / &avg, 2), 0) ofl, nullif(round(SUM(io_cell_offload_returned_bytes) / &avg, 2), 0) oflout,
                           nullif(round(avg(px) / &avg), 0) px,
                           substr(regexp_replace(regexp_replace(MAX(sql_text), '^\s+'), '\s+', ' '), 1, 200) sql_text
                    FROM   (SELECT /*+no_expand no_or_expand*/
                                   sql_id, sql_exec_start, '' || sql_exec_id sql_exec_id,
                                   max(nvl2(px_qcsid, NULL, sql_plan_hash_value)) plan_hash_value,
                                   max(nvl2(px_qcsid, NULL, sid)) sid,
                                   max(nvl2(px_qcsid, NULL, inst_id)) inst_id,
                                   max(nvl2(px_qcsid, NULL, sql_text)) sql_text,
                                   max(nvl2(px_qcsid, NULL, status)) status,
                                   SUM(nvl2(px_qcsid, 1, px_servers_allocated)) px,
                                   max(last_refresh_time) last_refresh_time,
                                   SUM(greatest(elapsed_time, cpu_time + application_wait_time + concurrency_wait_time + cluster_wait_time + user_io_wait_time + queuing_time)) ela,
                                   SUM(elapsed_time) elapsed_time,
                                   SUM(cpu_time + application_wait_time + concurrency_wait_time + cluster_wait_time + user_io_wait_time + queuing_time) ela1,
                                   to_number(NULL) other_time,
                                   SUM(cpu_time) cpu_time,
                                   SUM(queuing_time) queuing_time,
                                   SUM(application_wait_time) application_wait_time,
                                   SUM(concurrency_wait_time) concurrency_wait_time,
                                   SUM(cluster_wait_time) cluster_wait_time,
                                   SUM(plsql_exec_time) plsql_exec_time,
                                   SUM(java_exec_time) java_exec_time,
                                   SUM(user_io_wait_time) user_io_wait_time,
                                   SUM(physical_write_bytes) physical_write_bytes,
                                   SUM(physical_read_bytes) physical_read_bytes
                                   &ver ,SUM(io_cell_offload_eligible_bytes) io_cell_offload_eligible_bytes, SUM(io_cell_offload_returned_bytes) io_cell_offload_returned_bytes
                            FROM   gv$sql_monitor a
                            WHERE  (&filter)
                            GROUP  BY sql_id, sql_exec_start, sql_exec_id
            $IF &check_access_report=1 AND &pred=1 $THEN
                        UNION ALL
                        SELECT key1 sql_id,
                               to_date(key3, 'MM:DD:YYYY HH24:MI:SS') sql_exec_start,
                               report_id || '(HIST)' sql_exec_id,
                               plan_hash plan_hash_value,
                               sid,
                               inst_id,
                               sql_text,
                               status,
                               px_servers_allocated px,
                               last_refresh_time,
                               greatest(elapsed_time, nvl(cpu_time, 0) + nvl(application_wait_time, 0) + nvl(concurrency_wait_time, 0) + nvl(cluster_wait_time, 0) + nvl(user_io_wait_time, 0) + nvl(queuing_time, 0)) ela,
                               elapsed_time,
                               nvl(cpu_time, 0) + nvl(application_wait_time, 0) + nvl(concurrency_wait_time, 0) + nvl(cluster_wait_time, 0) + nvl(user_io_wait_time, 0) + nvl(queuing_time, 0) ela1,
                               other_wait_time other_time,
                               cpu_time,
                               queuing_time,
                               application_wait_time,
                               concurrency_wait_time,
                               cluster_wait_time,
                               plsql_exec_time,
                               java_exec_time,
                               user_io_wait_time,
                               physical_write_bytes,
                               physical_read_bytes
                               &ver ,io_cell_offload_eligible_bytes, io_cell_offload_returned_bytes
                        FROM   (SELECT /*+no_expand no_or_expand no_merge*/
                                       a.*,
                                       period_end_time last_refresh_time,
                                       session_id sid,
                                       instance_number inst_id,
                                       key1 sql_id,
                                       report_id sql_exec_id,
                                       xmltype(a.report_summary) summary
                                FROM   dba_hist_reports a
                                WHERE  did IN (dbid, con_dbid)
                                AND    (sq_id IS NOT NULL AND key1 = sq_id OR
                                        keyw IS NOT NULL AND (lower(report_parameters) LIKE '%' || keyw || '%' OR lower(report_summary) LIKE '%' || keyw || '%'))
                                AND    component_name = 'sqlmonitor'
                                AND    instance_number = nvl(inst, instance_number)) a,
                               xmltable('/report_repository_summary/*' PASSING a.summary COLUMNS
                                        plan_hash NUMBER PATH 'plan_hash',
                                        username VARCHAR2(128) PATH 'user',
                                        current_username VARCHAR2(128) PATH 'current_username',
                                        dbop_exec_id NUMBER PATH 'dbop_exec_id',
                                        dbop_name VARCHAR2(30) PATH 'dbop_name',
                                        module VARCHAR2(64) PATH 'module',
                                        action VARCHAR2(64) PATH 'action',
                                        program VARCHAR2(48) PATH 'program',
                                        dur NUMBER PATH 'stats/stat[@name="duration"]*1e6',
                                        elapsed_time NUMBER PATH 'stats/stat[@name="elapsed_time"]',
                                        cpu_time NUMBER PATH 'stats/stat[@name="cpu_time"]',
                                        user_io_wait_time NUMBER PATH 'stats/stat[@name="user_io_wait_time"]',
                                        application_wait_time NUMBER PATH 'stats/stat[@name="application_wait_time"]',
                                        cluster_wait_time NUMBER PATH 'stats/stat[@name="cluster_wait_time"]',
                                        concurrency_wait_time NUMBER PATH 'stats/stat[@name="concurrency_wait_time"]',
                                        queuing_time NUMBER PATH 'stats/stat[@name="queuing_time"]',
                                        other_wait_time NUMBER PATH 'stats/stat[@name="other_wait_time"]',
                                        plsql_exec_time NUMBER PATH 'stats/stat[@name="plsql_exec_time"]',
                                        java_exec_time NUMBER PATH 'stats/stat[@name="java_exec_time"]',
                                        physical_read_bytes NUMBER PATH 'stats/stat[@name="read_bytes"]',
                                        physical_write_bytes NUMBER PATH 'stats/stat[@name="write_bytes"]',
                                        io_cell_offload_eligible_bytes NUMBER PATH 'stats/stat[@name="elig_bytes"]',
                                        io_cell_offload_returned_bytes NUMBER PATH 'stats/stat[@name="ret_bytes"]',
                                        px_servers_allocated NUMBER PATH 'px_servers_allocated',
                                        offlrtn NUMBER PATH 'stats/stat[@name="ret_bytes"]',
                                        status VARCHAR2(30) PATH 'status',
                                        sql_text VARCHAR2(4000) PATH 'sql_text')
                        WHERE  (&filter)
            $END
                    ) a
            WHERE  (&SNAP=1 OR (keyw IS NOT NULL AND plan_hash IS NULL OR NOT regexp_like(upper(TRIM(sql_text)), '^(BEGIN|DECLARE|CALL)')))
            AND    (&SNAP=1 OR (keyw IS NULL OR a.sql_id || '_' || plan_hash_value || '_' || sql_exec_id || lower(sql_text) LIKE '%' || keyw || '%'))
            GROUP  BY sql_id &group
            ORDER  BY 4 DESC)
        WHERE  rownum <= 30
        ORDER  BY 4, ela;

        IF sq_id IS NOT NULL AND '&group' IS NOT NULL THEN
            IF plan_hash IS NOT NULL THEN
                $IF dbms_db_version.version>11 AND &check_access_hub =1 $THEN
                    SELECT min(sql_exec_start), max(last_refresh_time), &uniq
                    INTO   start_time, end_time, execs
                    FROM   gv$sql_monitor
                    WHERE  sql_id = sq_id
                    AND    px_server# IS NULL
                    AND    sql_plan_hash_value = plan_hash;
                    filename := 'sqlhub_' || sq_id || '.html';
                    content := sys.dbms_perf.report_sql(sql_id              => sq_id,
                                                        is_realtime         => 1,
                                                        outer_start_time    => start_time,
                                                        outer_end_time      => end_time,
                                                        selected_start_time => start_time,
                                                        selected_end_time   => end_time,
                                                        inst_id             => inst,
                                                        dbid                => did,
                                                        monitor_list_detail => 20);
                $END
                NULL;
            END IF;

            OPEN :c0 FOR
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/
                       decode(phv, plan_hash, '*', ' ') || phv plan_hash,
                       &uniq execs,
                       SUM(nvl2(error_message, 1, 0)) errs,
                       round(SUM(fetches), 2) fetches,
                       to_char(min(sql_exec_start), 'YYMMDD HH24:MI:SS') first_seen,
                       to_char(max(last_refresh_time), 'YYMMDD HH24:MI:SS') last_seen,
                       round(SUM(dur * nvl2(px_qcsid, 0, 1)) / &avg, 2) dur,
                       round(SUM(ela) / &avg, 2) ela,
                       nullif(round(SUM(queuing_time) / nullif(SUM(ela), 0), 4), 0) queue,
                       nullif(round(SUM(cpu_time) / nullif(SUM(ela), 0), 4), 0) cpu,
                       nullif(round(SUM(application_wait_time) / nullif(SUM(ela), 0), 4), 0) app,
                       nullif(round(SUM(concurrency_wait_time) / nullif(SUM(ela), 0), 4), 0) cc,
                       nullif(round(SUM(cluster_wait_time) / nullif(SUM(ela), 0), 4), 0) cl,
                       nullif(round(SUM(plsql_exec_time) / nullif(SUM(ela), 0), 4), 0) plsql,
                       nullif(round(SUM(java_exec_time) / nullif(SUM(ela), 0), 4), 0) java,
                       nullif(round(SUM(user_io_wait_time) / nullif(SUM(ela), 0), 4), 0) io,
                       nullif(round(SUM(io_interconnect_bytes) / &avg, 2), 0) cellio,
                       nullif(round(SUM(physical_read_bytes) / &avg, 2), 0) read,
                       nullif(round(SUM(physical_write_bytes) / &avg, 2), 0) write,
                       nullif(round(SUM(direct_writes) / &avg, 2), 0) dxwrite,
                       nullif(round(SUM(buffer_gets) * 8192 / &avg, 2), 0) buffget,
                       &ver nullif(round(SUM(io_cell_offload_eligible_bytes) / &avg, 2), 0) offload,
                       &ver nullif(round(SUM(io_cell_offload_returned_bytes) / &avg, 2), 0) offlrtn,
                       nullif(max(px_maxdop), 0) dop,
                       nullif(max(dops), 0) sids,
                       regexp_replace(max(error_message) keep(dense_rank LAST ORDER BY nvl2(error_message, last_refresh_time, NULL) NULLS FIRST), '\s+', ' ') last_error
                FROM   (SELECT a.*,
                               sql_plan_hash_value phv,
                               greatest(elapsed_time, cpu_time + application_wait_time + concurrency_wait_time + cluster_wait_time + user_io_wait_time + queuing_time) ela,
                               greatest((last_refresh_time - sql_exec_start) * 86400 * 1e6, 1e6) dur,
                               COUNT(DISTINCT inst_id || ',' || sid) over(PARTITION BY sql_exec_id, sql_exec_start) dops
                        FROM   gv$sql_monitor a
                        WHERE  sql_id = sq_id) b
                GROUP  BY phv
                ORDER  BY decode(phv, plan_hash, sysdate + 1, max(last_refresh_time));
        END IF;
    END IF;
    :rs       := content;
    :filename := filename;
END;
/

print c;
set colsep |
col stat_value#1,stat_value#2,stat_value#3 format #,##0
print c0;
print c1;
print c2;
save rs filename
