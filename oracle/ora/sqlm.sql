/*[[
        Get resource usage from SQL monitor. Usage: @@NAME {[<sql_id> {[-l|-d|-a] [<sql_exec_id>|<plan_hash>|<report_id>]}}|"<query>"]} | {. <keyword>} [-u|-f"<filter>"] [-avg]
        Related parameters for SQL monitor: 
                _sqlmon_recycle_time,_sqlmon_max_planlines,_sqlmon_max_plan,_sqlmon_threshold,control_management_pack_access,statistics_level
        A SQL can be forced to record the sql monitor report by the alter system statement:
                ALTER SYSTEM SET EVENTS 'sql_monitor [sql: <sql_id1>|sql: <sql_id2>] force=true';

        Usages:
             1. @@NAME <sql_id> [<sql_exec_id>]                   : Extract sql monitor report with specific sql_id, options: -s,-a,-f"<format>"
             2. @@NAME [. <keyword>]                              : List recent sql monitor reports,options: -avg,-u,-f"<filter>" 
             3. @@NAME -snap <sec> <sid>                          : Monitor the specific <sid> for <sec> seconds, and then list the SQL monitor result, options: -avg
             4. @@NAME "<Query>"                                  : Read SQL Monitor report from target query(return CLOB) and print
             5. @@NAME <report_id>                                : Read SQL Monitor report from dba_hist_reports with specific report_id
             6. @@NAME <sql_id> -l [-a] [plan_hash|sql_exec_id]   : List the reports and generate perf hub report for specific sql_id, options: -avg,-u,-a,-f"<filter>"
             7. @@NAME <sql_id> -d [<plan_hash> [YYYYMMDDHH24MI]] : Extract SQL detail report

        Options:
            -u     : Only show the SQL list within current schema
            -f     : List the records that match the predicates, i.e.: -f"MODULE='DBMS_SCHEDULER'"
            -l     : List the available SQL Monitor reports for the specific SQL Id
            -a     : When together with "-l" option, generate SQL Hub report
            -avg   : Show avg time in case of listing the SQL monitor reports

        Format:
             -active : output file is in active HTML format
             -em     : output file is in EM HTML format
             -html   : output file is in HTML format
             -text   : output file is in Text format
             
     --[[
            @ver: 12.2={} 11.2={--}
            &uniq:    default={count(DISTINCT sql_exec_id||','||to_char(sql_exec_start,'YYYYMMDDHH24MISS'))}
            &option : default={}, l={,sql_exec_id,plan_hash,sql_exec_start}
            &option1: {default={&uniq execs,round(sum(ela)/&uniq,2) avg_ela,
                                to_char(MAX(last_refresh_time), 'YYMMDD HH24:MI:SS') last_seen,
                                to_char(MIN(sql_exec_start), 'YYMMDD HH24:MI:SS') first_seen,} 
                      l={}}
            &filter: default={1=1},f={},l={sql_id=sq_id},snap={DBOP_EXEC_ID=dopeid and dbop_name=dopename},u={username=nvl('&0',sys_context('userenv','current_schema'))}
            &tot : default={1} avg={0}
            &avg : defult={1} avg={&uniq}
            &out: default={active} html={html} em={em} text={text}
            &snap: default={0} snap={1}
            &showhub: default={0} a={1}
            &rpt   : default={0} d={1}
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
col dur,avg_ela,ela,parse,qu,cpu,app,cc,cl,plsql,java,pljava,io,ot,time format usmhd1
col read,write,iosize,mem,temp,cellio,buffget,offload,offlrtn,calc_kmg,ofl,bytes,OFLOUT format kmg1
col est_cost,est_rows,act_rows,ioreq,execs,outputs,FETCHES,dxwrite,calc_tmb format TMB1

DECLARE /*+no_monitor*/
    plan_hash  INT := regexp_substr(:V2, '^\d+$');
    start_time DATE;
    end_time   DATE;
    sq_id      VARCHAR2(4000):=:V1;
    sq_id1     VARCHAR2(4000):=:V1;
    inst       INT := :INSTANCE;
    did        INT := :dbid;
    rpt_id     INT;
    execs      INT;
    counter    INT := &tot;
    filename   VARCHAR2(100);
    sqlmon     CLOB;
    content    CLOB;
    txt        CLOB;
    lst        SYS.ODCIVARCHAR2LIST;
    dopename   VARCHAR(30);
    dopeid     INT;
    keyw       VARCHAR2(300):=lower(:V2);
    c2         SYS_REFCURSOR;
    sql_exec   INT;
    sql_start  DATE;
    last_date  DATE;
    serial     INT;
    xml        xmltype;
    mon        xmltype;
    elem       xmltype;
    descs      SYS.ODCIARGDESCLIST;
    type t_fmt IS TABLE OF VARCHAR2(50);
    fmt        t_fmt;
    c0         SYS_REFCURSOR;
    dyn_lvl    PLS_INTEGER;
    PROCEDURE report_start IS
    BEGIN
        IF dyn_lvl IS NULL THEN
            SELECT value into dyn_lvl from v$parameter where name='optimizer_dynamic_sampling';
        END IF;
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling=5';
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PROCEDURE report_end IS
    BEGIN
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling='||dyn_lvl;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PROCEDURE wr(msg VARCHAR2) IS
    BEGIN
        dbms_lob.writeappend(txt,nvl(length(msg),1)+1,chr(10)||nvl(msg,'.'));
    END;

    PROCEDURE flush(section VARCHAR2) IS
    BEGIN
        IF lst.count > 0 then
            wr(' '||chr(10));
            wr(lpad('=',66,'='));
            wr('|  '||rpad(section,60)||'  |');
            wr(lpad('-',66,'-'));
            for i in 1..lst.count loop
                wr(lst(i));
            end loop;
        end if;
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
            dbms_lob.writeAppend(v_blob, utl_raw.length(r), r);
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
                        t_s1 := MOD(t_s1 + to_number(rawtohex(utl_raw.substr(t_buffer, i, 1)), 'xx'), 65521);
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
        dbms_lob.CreateTemporary(v_blob, TRUE);
        dbms_lob.CreateTemporary(v_clob, TRUE);
        ap(base64_str);
        v_blob := zlib_decompress(v_blob);
        dbms_lob.ConvertToCLOB(v_clob,
                               v_blob,
                               DBMS_LOB.LOBMAXSIZE,
                               dest_offset,
                               src_offset,
                               lob_csid,
                               lang_context,
                               warning);
        RETURN v_clob;
    END;
BEGIN
    IF &SNAP=1 THEN
        $IF &check_access_sqlm=0 OR DBMS_DB_VERSION.release=1 $THEN
            raise_application_error(-20001,'You dont'' have access on dbms_sql_monitor/dbms_lock, or db version < 12.2!');
        $ELSE
            dopename := 'DBCLI_SNAPPER_'||USERENV('SESSIONID');
            select max(serial#) into serial from v$session where sid=regexp_substr(plan_hash,'^\d+$');
            if not regexp_like(sq_id,'^\d+$') or not regexp_like(plan_hash,'^\d+$') then
                raise_application_error(-20001, 'Usage: ora sqlm -snap <secs> <sid>');
            elsif serial is null then 
                raise_application_error(-20001, 'session#'||plan_hash||' cannot be found in v$session!');
            end if;
            dopeid:= sys.dbms_sql_monitor.begin_operation (
                             dbop_name       => dopename,
                             dbop_eid        => dopeid,
                             forced_tracking => sys.dbms_sql_monitor.force_tracking,
                             session_id      => plan_hash,
                             session_serial  => serial);
            sys.dbms_lock.sleep(sq_id+0);
            sys.dbms_sql_monitor.end_operation(dopename,dopeid);
            dbms_output.put_line('Filter: dbop_name='''||dopename||''' and dbop_exec_id='||dopeid);
            open c2 for 
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ *
                FROM   (SELECT MAX(DECODE(MOD(rnk, 3), 1, NAME)) stat_name#1,
                                 MAX(DECODE(MOD(rnk, 3), 1, VALUE)) stat_value#1,
                                 MAX(DECODE(MOD(rnk, 3), 2, NAME)) stat_name#2,
                                 MAX(DECODE(MOD(rnk, 3), 2, VALUE)) stat_value#2,
                                 MAX(DECODE(MOD(rnk, 3), 0, NAME)) stat_name#3,
                                 MAX(DECODE(MOD(rnk, 3), 0, VALUE)) stat_value#3
                        FROM   (SELECT  /*+ordered use_hash(b)*/
                                substr(NAME, 1, 35) NAME, SUM(VALUE) VALUE, row_number() OVER(ORDER BY SUM(VALUE) DESC) rnk
                                FROM   gv$sql_monitor
                                JOIN   gv$sql_monitor_sesstat
                                USING  (inst_id, KEY) NATURAL
                                JOIN   v$statname
                                WHERE  VALUE > 0
                                AND    dbop_name = dopename
                                AND    DBOP_EXEC_ID = dopeid
                                GROUP  BY NAME)
                        GROUP  BY CEIL(rnk / 3)
                        ORDER  BY stat_value#1 DESC NULLS LAST)
                WHERE  ROWNUM <= 30;
            sq_id     := NULL;
            keyw      := NULL;
            plan_hash := NULL;
        $END
        :C2 := C2;
    END IF;

    IF sqlmon IS NULL AND upper(sq_id) LIKE 'SELECT %' THEN
        BEGIN
            sq_id := regexp_replace(sq_id,'[;/ '||chr(10)||chr(9)||chr(13)||']+$');
            execute immediate 'SELECT * FROM ('||sq_id||') WHERE ROWNUM<2' into sqlmon;
        EXCEPTION 
            when no_data_found THEN
                raise_application_error(-20001,'Cannot fetch report with SQL: '||sq_id);
            when others then 
                raise_application_error(-20001,'Error '||sqlerrm||' on fetching report with SQL: '||sq_id);
        END;
    ELSIF sqlmon IS NULL AND regexp_like(sq_id,'^\d+$') THEN
        $IF &check_access_report=1 $THEN
            rpt_id := 0+sq_id;
            report_start;
            sqlmon := DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL(RID => rpt_id, TYPE => 'XML');
            report_end;
        $END
        IF sqlmon IS NULL THEN
             raise_application_error(-20001,'SQL_ID '||sq_id||' should not be a number!');
        END IF;
    END IF;

    IF sqlmon IS NOT NULL THEN 
        sqlmon := regexp_substr(sqlmon,'<report .*</report>',1,1,'n');
        IF sqlmon IS NULL or LENGTH(sqlmon)=0 THEN
            raise_application_error(-20001,'Target file is not a valid SQL Monitor Report file!');
        END IF;
        xml    := xmltype(sqlmon);
        mon    := xml.extract('//report_parameters[1]');

        IF mon IS NULL THEN
            sqlmon := trim(xml.extract('/report/text()').getClobVal());
            IF sqlmon IS NULL THEN
                raise_application_error(-20001,'Target file is not a valid SQL Monitor Report file!');
            END IF;
            
            IF length(sqlmon)>32767 THEN
                raise_application_error(-20001,'Unsupported SQL Monitor Report file whose compressed data over 32 KB!');
            END IF;
            sqlmon := decompress(sqlmon);
            xml    := xml.deleteXML('*/text()').appendChildXML('/report',xmltype(sqlmon));
            mon := xml.extract('//report_parameters[1]');
        END IF;

        sq_id:= mon.extract('//report_parameters/sql_id[1]/text()').getStringval();
        elem := mon.extract('//report_parameters/sql_exec_id[1]/text()');
        if rpt_id IS NOT NULL THEN
            filename := 'sqlm_' || sq_id ||'_'||rpt_id|| '.html';
            rpt_id := null;
        end if;
        
        IF elem IS NOT NULL THEN
            sql_exec:= elem.getNumberVal();
        ELSE
            elem := mon.extract('//report_parameters/*[@sql_exec_id][1]/@sql_exec_id');
            IF elem IS NOT NULL THEN
                sql_exec:= elem.getNumberVal();
            END IF;
        END IF;
    END IF;
    
    IF sq_id IS NOT NULL AND '&option' IS NULL THEN
        --EXECUTE IMMEDIATE 'alter session set "_sqlmon_max_planlines"=3000';
        IF xml IS NULL THEN
            BEGIN
                execute immediate 'alter session set events ''emx_control compress_xml=none''';
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            
            sql_exec := plan_hash;

            IF &rpt=0 THEN
                IF sql_exec IS NULL THEN
                    select /*+no_expand no_or_expand*/
                           max(sql_id) keep(dense_rank last order by last_refresh_time,sql_exec_id),
                           max(sql_exec_id) keep(dense_rank last order by last_refresh_time),
                           max(sql_exec_start) keep(dense_rank last order by last_refresh_time),
                           max(last_refresh_time)
                    into  sq_id,sql_exec,sql_start,last_date
                    from  gv$sql_monitor
                    where (sql_id=sq_id or lower(sq_id) in('l','last'))
                    AND   sql_exec_id>0 
                    AND   PX_SERVER# IS NULL
                    AND   sql_text IS NOT NULL
                    AND   inst_id=nvl(inst,inst_id);
                ELSE
                    select max(sql_id) keep(dense_rank last order by last_refresh_time,sql_exec_id),
                           max(sql_exec_id) keep(dense_rank last order by last_refresh_time),
                           max(sql_exec_start) keep(dense_rank last order by last_refresh_time)
                    into  sq_id,sql_exec,sql_start
                    from  gv$sql_monitor
                    where sql_id=sq_id
                    AND   sql_exec_id=sql_exec
                    AND   PX_SERVER# IS NULL
                    AND   sql_text IS NOT NULL
                    AND   inst_id=nvl(inst,inst_id);
                END IF;
                $IF &check_access_report=1 $THEN
                    if lower(sq_id1) not in('l','last') and (sq_id is null or last_date<sysdate-2/24) then
                        select max(key1) keep(dense_rank last order by ptime,key2),
                               max(report_id) keep(dense_rank last order by ptime,key2)
                        into  sq_id1,rpt_id
                        FROM(
                            select /*+no_expand no_or_expand*/ 
                                   key1,key2,report_id,period_end_time ptime
                            from  dba_hist_reports
                            where (did IS NULL OR did in(dbid,con_dbid))
                            AND   key1=nvl(sq_id,sq_id1)
                            AND   key2>0
                            AND   (sql_exec  IS NULL OR KEY2=sql_exec)
                            AND   (plan_hash IS NULL OR key2=plan_hash OR report_id=plan_hash or instr(report_summary,'plan_hash>'||plan_hash||'<')>0)
                            AND   component_name='sqlmonitor'
                            AND   dbid=nvl(did,dbid)
                            AND   instance_number=nvl(inst,instance_number));
                        sq_id := nvl(sq_id1,sq_id);
                    end if;
                $END

                if sq_id is null then
                    raise_application_error(-20001,'cannot find relative records for the specific SQL ID!');
                end if;

                IF rpt_id IS NULL THEN
                    fmt := t_fmt('ALL+PLAN_SKEW+SUMMARY+SQL_FULLTEXT','ALL','ALL-BINDS','ALL-SQL_TEXT','ALL-SQL_TEXT-BINDS','TYPICAL');
                    report_start;
                    FOR i in 1..fmt.count LOOP
                        BEGIN
                            xml := DBMS_SQLTUNE.REPORT_SQL_MONITOR_XML(report_level => fmt(i),  sql_id => sq_id,  SQL_EXEC_START=>sql_start,SQL_EXEC_ID => sql_exec, inst_id => inst);
                            dbms_output.put_line('Extracted report level is: '||fmt(i));
                            exit;
                        EXCEPTION WHEN OTHERS THEN
                            IF i=fmt.count THEN
                                report_end;
                                RAISE;
                            END IF;
                        END;
                    END LOOP;
                    report_end;
                ELSE
                    $IF &check_access_report=1 $THEN
                        report_start;
                        xml := SYS.DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL_XML(rpt_id);
                        report_end;
                        dbms_output.put_line('Extracted report from dba_hist_reports.');
                    $END
                END IF;
                filename := 'sqlm_' || sq_id ||nullif('_'||keyw,'_')|| '.html';
            ELSE
                sql_start := nvl(to_char(nvl(:V3,:starttime),'yymmddhh24mi'),sysdate-7);
                report_start;
                xml := xmltype(DBMS_SQLTUNE.REPORT_SQL_DETAIL(report_level => 'ALL',
                                                      sql_id => sq_id,
                                                      sql_plan_hash_value=>sql_exec,
                                                      start_time=>sql_start,
                                                      duration=> 86400*(sysdate-sql_start), 
                                                      inst_id => inst, 
                                                      dbid=>did,
                                                      top_n=>50,
                                                      type=>'XML'));
                filename := 'sqld_' || sq_id ||nullif('_'||keyw,'_') || '.html';
                report_end;
            END IF;
        END IF;

        content  := DBMS_REPORT.FORMAT_REPORT(xml, '&out') ;

        IF &rpt=0 THEN
            txt := DBMS_REPORT.FORMAT_REPORT(xml.deleteXML('//sql_fulltext'), 'text');
        ELSE
            dbms_lob.createtemporary(txt,true);
        END IF;

        OPEN :c FOR SELECT  txt from dual;
        
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
            SELECT *
            FROM   (SELECT   /*+no_expand no_or_expand opt_param('optimizer_dynamic_sampling' 5)*/ 
                             a.sql_id &OPTION,
                             &option1 
                             MAX(sid || ',@' || inst_id) keep(dense_rank LAST ORDER BY last_refresh_time) last_sid,
                             MAX(status) keep(dense_rank LAST ORDER BY last_refresh_time, sid) last_status,
                             round(sum(last_refresh_time - sql_exec_start +1/86400)/&avg * 86400*1e6, 2) dur,
                             round(sum(ela)/&avg , 2) ela,
                             round(sum(QUEUING_TIME)/&avg , 2) QU,
                             round(sum(CPU_TIME)/&avg , 2) CPU,
                             round(sum(APPLICATION_WAIT_TIME)/&avg , 2) app,
                             round(sum(CONCURRENCY_WAIT_TIME)/&avg , 2) cc,
                             round(sum(CLUSTER_WAIT_TIME)/&avg , 2) cl,
                             round(sum(nvl(PLSQL_EXEC_TIME,0)+nvl(JAVA_EXEC_TIME,0))/&avg , 2) pljava,
                             round(sum(USER_IO_WAIT_TIME)/&avg , 2) io,
                             round(sum(nvl(PHYSICAL_READ_BYTES,0)+nvl(PHYSICAL_WRITE_BYTES,0) )/&avg, 2) bytes,
                             &ver round(sum(IO_CELL_OFFLOAD_ELIGIBLE_BYTES)/&avg,2) OFL, round(sum(IO_CELL_OFFLOAD_RETURNED_BYTES)/&avg,2) OFLOUT,
                             substr(regexp_replace(regexp_replace(MAX(sql_text), '^\s+'), '\s+', ' '), 1, 200) sql_text
                    FROM   (select /*+no_expand no_or_expand*/
                                   sql_id,sql_exec_start,''||sql_exec_id sql_exec_id,
                                   max(NVL2(PX_QCSID,null,SQL_PLAN_HASH_VALUE)) plan_hash,
                                   max(NVL2(PX_QCSID,null,SQL_PLAN_HASH_VALUE)) SQL_PLAN_HASH_VALUE,
                                   max(NVL2(PX_QCSID,null,sid)) sid,
                                   max(NVL2(PX_QCSID,null,inst_id)) inst_id,
                                   max(NVL2(PX_QCSID,null,sql_text)) sql_text,
                                   max(NVL2(PX_QCSID,null,status)) status,
                                   max(last_refresh_time) last_refresh_time,
                                   sum(GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME)) ela,
                                   sum(ELAPSED_TIME) ELAPSED_TIME,
                                   sum(CPU_TIME) cpu_time,
                                   sum(QUEUING_TIME) QUEUING_TIME,
                                   sum(APPLICATION_WAIT_TIME) APPLICATION_WAIT_TIME,
                                   SUM(CONCURRENCY_WAIT_TIME) CONCURRENCY_WAIT_TIME,
                                   SUM(CLUSTER_WAIT_TIME) CLUSTER_WAIT_TIME,
                                   SUM(PLSQL_EXEC_TIME) PLSQL_EXEC_TIME,
                                   SUM(JAVA_EXEC_TIME) JAVA_EXEC_TIME,
                                   SUM(USER_IO_WAIT_TIME) USER_IO_WAIT_TIME,
                                   SUM(PHYSICAL_WRITE_BYTES) PHYSICAL_WRITE_BYTES,
                                   SUM(PHYSICAL_READ_BYTES) PHYSICAL_READ_BYTES
                                   &ver ,SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES) IO_CELL_OFFLOAD_ELIGIBLE_BYTES,sum(IO_CELL_OFFLOAD_RETURNED_BYTES) IO_CELL_OFFLOAD_RETURNED_BYTES
                            FROM  gv$sql_monitor a
                            WHERE (&filter)
                            GROUP BY sql_id,sql_exec_start,sql_exec_id
                            $IF &check_access_report=1 AND &pred=1 $THEN
                            UNION ALL
                            select key1 sql_id,to_date(key3,'MM:DD:YYYY HH24:MI:SS') sql_exec_start,report_id||'(HIST)',
                                   plan_hash,
                                   plan_hash SQL_PLAN_HASH_VALUE,
                                   sid,
                                   inst_id,
                                   sql_text,
                                   status,
                                   last_refresh_time,
                                   dur ela,
                                   ELAPSED_TIME,
                                   cpu_time,
                                   QUEUING_TIME,
                                   APPLICATION_WAIT_TIME,
                                   CONCURRENCY_WAIT_TIME,
                                   CLUSTER_WAIT_TIME,
                                   PLSQL_EXEC_TIME,
                                   JAVA_EXEC_TIME,
                                   USER_IO_WAIT_TIME,
                                   PHYSICAL_WRITE_BYTES,
                                   PHYSICAL_READ_BYTES
                                   &ver ,IO_CELL_OFFLOAD_ELIGIBLE_BYTES,IO_CELL_OFFLOAD_RETURNED_BYTES
                            FROM (
                                SELECT /*+no_expand no_or_expand*/
                                       a.*,
                                       period_end_time last_refresh_time,
                                       session_id sid,
                                       instance_number inst_id,
                                       key1 sql_id,
                                       report_id sql_exec_id,
                                       xmltype(a.report_summary) summary 
                                FROM   dba_hist_reports a
                                WHERE (did IS NULL OR did in(dbid,con_dbid))
                                AND   (sq_id IS NOT NULL AND key1=sq_id OR 
                                       keyw IS NOT NULL AND (lower(report_parameters) like '%'||keyw||'%' or lower(report_summary) like '%'||keyw||'%'))
                                AND    COMPONENT_NAME='sqlmonitor'
                                AND    instance_number=nvl(inst,instance_number)) a,
                            xmltable('/report_repository_summary/*' PASSING a.summary columns --
                                    plan_hash NUMBER PATH 'plan_hash',
                                    username  VARCHAR2(128) PATH 'user',
                                    CURRENT_USERNAME  VARCHAR2(128) PATH 'current_username',
                                    DBOP_EXEC_ID NUMBER PATH 'dbop_exec_id',
                                    DBOP_NAME VARCHAR2(30) PATH 'dbop_name',
                                    MODULE VARCHAR2(64) PATH 'module',
                                    ACTION VARCHAR2(64) PATH 'action',
                                    PROGRAM VARCHAR2(48) PATH 'program',
                                    dur NUMBER path 'stats/stat[@name="duration"]*1e6', 
                                    ELAPSED_TIME NUMBER path 'stats/stat[@name="elapsed_time"]', 
                                    CPU_TIME NUMBER path 'stats/stat[@name="cpu_time"]',
                                    USER_IO_WAIT_TIME NUMBER path 'stats/stat[@name="user_io_wait_time"]', 
                                    APPLICATION_WAIT_TIME NUMBER path 'stats/stat[@name="application_wait_time"]',
                                    CLUSTER_WAIT_TIME NUMBER path 'stats/stat[@name="cluster_wait_time"]', 
                                    CONCURRENCY_WAIT_TIME NUMBER path 'stats/stat[@name="concurrency_wait_time"]',
                                    QUEUING_TIME NUMBER path 'stats/stat[@name="queuing_time"]', 
                                    OTHER_WAIT_TIME NUMBER path 'stats/stat[@name="other_wait_time"]', 
                                    PLSQL_EXEC_TIME NUMBER path 'stats/stat[@name="plsql_exec_time"]',
                                    JAVA_EXEC_TIME NUMBER path 'stats/stat[@name="java_exec_time"]',
                                    PHYSICAL_READ_BYTES NUMBER path 'stats/stat[@name="read_bytes"]',
                                    PHYSICAL_WRITE_BYTES NUMBER path 'stats/stat[@name="write_bytes"]',
                                    IO_CELL_OFFLOAD_ELIGIBLE_BYTES NUMBER path 'stats/stat[@name="elig_bytes"]', 
                                    IO_CELL_OFFLOAD_RETURNED_BYTES NUMBER path 'stats/stat[@name="ret_bytes"]', 
                                    offlrtn NUMBER path 'stats/stat[@name="ret_bytes"]',
                                    status VARCHAR2(30) PATH 'status',
                                    sql_text VARCHAR2(4000) PATH 'sql_text')
                            WHERE (&filter)
                            $END
                            ) a
                    WHERE  (&SNAP=1 OR (keyw IS NOT NULL AND plan_hash IS NULL OR NOT regexp_like(upper(TRIM(SQL_TEXT)), '^(BEGIN|DECLARE|CALL)')))
                    AND    (&SNAP=1 OR (keyw IS NULL OR a.sql_id ||'_'|| sql_plan_hash_value||'_'|| sql_exec_id || lower(sql_text) LIKE '%' || keyw || '%'))
                    GROUP  BY sql_id &OPTION
                    ORDER  BY 4 DESC)
            WHERE  ROWNUM <= 100*nvl2(:option1,1,10)
            ORDER  BY 4, ela;
        IF sq_id IS NOT NULL AND '&option' IS NOT NULL THEN
            IF plan_hash IS NOT NULL THEN
                $IF DBMS_DB_VERSION.VERSION>11 AND &check_access_hub =1 $THEN
                    SELECT MIN(sql_exec_start), MAX(last_refresh_time), &uniq
                    INTO   start_time, end_time, execs
                    FROM   gv$sql_monitor
                    WHERE  sql_id = sq_id
                    AND    PX_SERVER# IS NULL
                    AND    sql_plan_hash_value = plan_hash;
                    filename := 'sqlhub_' || sq_id || '.html';
                    content  := sys.dbms_perf.report_sql(sql_id => sq_id,
                                                         is_realtime => 1,
                                                         outer_start_time => start_time,
                                                         outer_end_time => end_time,
                                                         selected_start_time => start_time,
                                                         selected_end_time => end_time,
                                                         inst_id => inst,
                                                         dbid => did,
                                                         monitor_list_detail => 20);
                $END
                
                IF counter = 0 THEN
                    counter := execs;
                END IF;
                $IF &check_access_report=1 $THEN
                    OPEN c0 FOR 
                        SELECT /*+no_expand opt_param('optimizer_dynamic_sampling' 5)*/  
                               KEY1 SQL_ID,
                               KEY2 SQL_EXEC_ID,
                               REPORT_ID,
                               SNAP_ID,
                               PERIOD_START_TIME,
                               PERIOD_END_TIME,
                               b.*,
                               substr(TRIM(regexp_replace(REPLACE(sql_text, chr(0)), '[' || chr(10) || chr(13) || chr(9) || ' ]+', ' ')), 1, 200) SQL_TEXT
                        FROM   (SELECT a.*, xmltype(a.report_summary) summary 
                                FROM   dba_hist_reports a
                                WHERE  (did IS NULL OR did in(dbid,con_dbid))
                                AND    KEY1=sq_id
                                AND    COMPONENT_NAME='sqlmonitor'
                                AND    instance_number=nvl(inst,instance_number)) a,
                                xmltable('/report_repository_summary/*' PASSING a.summary columns --
                                        plan_hash NUMBER PATH 'plan_hash',
                                        username  VARCHAR2(100) PATH 'user',
                                        dur NUMBER path 'stats/stat[@name="duration"]', 
                                        ela NUMBER path 'stats/stat[@name="elapsed_time"]*1e-6', 
                                        CPU NUMBER path 'stats/stat[@name="cpu_time"]*1e-6',
                                        io NUMBER path 'stats/stat[@name="user_io_wait_time"]*1e-6', 
                                        app NUMBER path 'stats/stat[@name="application_wait_time"]*1e-6',
                                        cl NUMBER path 'stats/stat[@name="cluster_wait_time"]*1e-6', 
                                        cc NUMBER path 'stats/stat[@name="concurrency_wait_time"]*1e-6',
                                        ot NUMBER path 'stats/stat[@name="other_wait_time"]*1e-6', 
                                        plsql NUMBER path 'stats/stat[@name="plsql_exec_time"]*1e-6',
                                        ioreq NUMBER path 'sum(stats/stat[@name=("read_reqs","write_reqs")])',
                                        iosize NUMBER path 'sum(stats/stat[@name=("read_bytes","write_bytes")])', 
                                        buffget NUMBER path 'stats/stat[@name="buffer_gets"]*8192',
                                        offload NUMBER path 'stats/stat[@name="elig_bytes"]', 
                                        ofleff NUMBER path 'stats/stat[@name="cell_offload_efficiency"]',
                                        ofleff2 NUMBER path 'stats/stat[@name="cell_offload_efficiency2"]', 
                                        offlrtn NUMBER path 'stats/stat[@name="ret_bytes"]',
                                        --,service VARCHAR2(100) PATH 'service', program VARCHAR2(300) PATH 'program'
                                        sql_text VARCHAR2(4000) PATH 'sql_text'
                                        --unc_bytes NUMBER path 'stats/stat[@name="unc_bytes"]',
                                        --fetches NUMBER path 'stats/stat[@name="user_fetch_count"]'
                                        --
                                        ) b
                        ORDER  BY 2;
                $END

                :c0 := c0;
            
                OPEN :c1 FOR
                    SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                            DECODE(phv, plan_hash, '*', ' ') || phv plan_hash,
                            &uniq execs,
                            SUM(nvl2(ERROR_MESSAGE, 1, 0)) errs,
                            round(SUM(FETCHES), 2) FETCHES,
                            to_char(MIN(sql_exec_start), 'YYMMDD HH24:MI:SS') first_seen,
                            to_char(MAX(last_refresh_time), 'YYMMDD HH24:MI:SS') last_seen,
                            round(SUM(dur*nvl2(px_qcsid,0,1))/&avg, 2) dur,
                            round(SUM(GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME))  /&avg, 2) ela,
                            round(SUM(QUEUING_TIME)  /&avg, 2) QUEUE,
                            round(SUM(CPU_TIME)  /&avg, 2) CPU,
                            round(SUM(APPLICATION_WAIT_TIME)  /&avg, 2) app,
                            round(SUM(CONCURRENCY_WAIT_TIME)  /&avg, 2) cc,
                            round(SUM(CLUSTER_WAIT_TIME)  /&avg, 2) cl,
                            round(SUM(PLSQL_EXEC_TIME)  /&avg, 2) plsql,
                            round(SUM(JAVA_EXEC_TIME)  /&avg, 2) JAVA,
                            round(SUM(USER_IO_WAIT_TIME)  /&avg, 2) io,
                            round(SUM(io_interconnect_bytes) /&avg, 2) cellio,
                            round(SUM(PHYSICAL_READ_BYTES) /&avg, 2) READ,
                            round(SUM(PHYSICAL_WRITE_BYTES) /&avg, 2) WRITE,
                            round(SUM(DIRECT_WRITES) /&avg, 2) dxwrite,
                            round(SUM(BUFFER_GETS)*8192 /&avg, 2) buffget,
                            &ver round(SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES) /&avg, 2) offload,
                            &ver round(SUM(IO_CELL_OFFLOAD_RETURNED_BYTES) /&avg, 2) offlrtn,
                            MAX(PX_MAXDOP) DOP,
                            MAX(DOPS) SIDS,
                            regexp_replace(MAX(ERROR_MESSAGE) keep(dense_rank LAST ORDER BY nvl2(ERROR_MESSAGE, last_refresh_time, NULL) NULLS FIRST),'\s+', ' ') last_error
                    FROM   (SELECT a.*,sql_plan_hash_value phv,
                                     max(nvl((last_refresh_time-sql_exec_start)*86400+1,greatest(ELAPSED_TIME,(CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME))))  over(partition by sql_exec_id,sql_exec_start) dur,
                                     count(distinct inst_id||','||sid) over(partition by sql_exec_id,sql_exec_start) dops 
                            FROM gv$sql_monitor a WHERE sql_id = sq_id) b
                    GROUP  BY phv
                    ORDER  BY decode(phv, plan_hash, SYSDATE + 1, MAX(last_refresh_time));
                
            END IF;
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
