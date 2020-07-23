/*[[
        Get resource usage from SQL monitor. Usage: @@NAME {[<sql_id> {[-l|-d|-a] [<sql_exec_id>|plan_hash_value]}}|<sqlmon file>|"<query>"]} | {. <keyword>} [-u|-f"<filter>"] [-avg]
        Related parameters for SQL monitor: 
                _sqlmon_recycle_time,_sqlmon_max_planlines,_sqlmon_max_plan,_sqlmon_threshold,control_management_pack_access,statistics_level
        A SQL can be forced to record the sql monitor report by the alter system statement:
                ALTER SYSTEM SET EVENTS 'sql_monitor [sql: <sql_id1>|sql: <sql_id2>] force=true';

        Usages:
             1. @@NAME <sql_id> [<sql_exec_id>]                   : Extract sql monitor report with specific sql_id, options: -s,-a,-f"<format>"
             2. @@NAME [. <keyword>]                              : List recent sql monitor reports,options: -avg,-u,-f"<filter>" 
             3. @@NAME -snap <sec> <sid>                          : Monitor the specific <sid> for <sec> seconds, and then list the SQL monitor result, options: -avg
             4. @@NAME <sqlmon_file>                              : Read SQL Monitor report from target location and print
             5. @@NAME "<Query>"                                  : Read SQL Monitor report from target query(return CLOB) and print
             6. @@NAME <report_id>                                : Read SQL Monitor report from dba_hist_reports with specific report_id
             7. @@NAME <sql_id> -l [-a] [plan_hash|sql_exec_id]   : List the reports and generate perf hub report for specific sql_id, options: -avg,-u,-a,-f"<filter>"
             8. @@NAME <sql_id> -d [<plan_hash> [YYYYMMDDHH24MI]] : Report SQL detail

        Options:
            -u     : Only show the SQL list within current schema
            -f     : List the records that match the predicates, i.e.: -f"MODULE='DBMS_SCHEDULER'"
            -s     : Plan format is "ALL-SESSIONS-SQL_FULLTEXT-SQL_TEXT", this is the default
            -a     : Plan format is "ALL-SQL_FULLTEXT-SQL_TEXT", when together with "-l" option, generate SQL Hub report
            -avg   : Show avg time in case of listing the SQL monitor reports
            -detail: Extract more detailed information when generating the SQL Monitor report

     --[[
            @ver: 12.2={} 11.2={--}
            &uniq:    default={count(DISTINCT sql_exec_id||','||to_char(sql_exec_start,'YYYYMMDDHH24MISS'))}
            &option : default={}, l={,sql_exec_id,plan_hash,sql_exec_start}
            &option1: default={&uniq execs,round(sum(GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME))/&uniq,2) avg_ela,}, l={}
            &filter: default={1=1},f={},l={sql_id=sq_id},snap={DBOP_EXEC_ID=dopeid and dbop_name=dopename},u={username=nvl('&0',sys_context('userenv','current_schema'))}
            &tot : default={1} avg={0}
            &avg : defult={1} avg={&uniq}
            &out: default={active} html={html} em={em}
            &snap: default={0} snap={1}
            &showhub: default={0} a={1}
            &detail: default={0} detail={1}
            &rpt   : default={0} d={1}
            @check_access_hub : SYS.DBMS_PERF={&showhub} default={0}
            @check_access_sqlm: SYS.DBMS_SQL_MONITOR/SYS.DBMS_LOCK={1} default={0}
     --]]
]]*/

set feed off VERIFY off printsize 3000
var c refcursor;
var c0 refcursor;
var c1 refcursor;
var c2 refcursor;
var rs CLOB;
var filename varchar2;
var plan_hash number;
col dur,avg_ela,ela,parse,queue,cpu,app,cc,cl,plsql,java,io,time format usmhd2
col read,write,iosize,mem,temp,cellio,buffget,offload,offlrtn,calc_kmg,ofl format kmg
col est_cost,est_rows,act_rows,ioreq,execs,outputs,FETCHES,dxwrite,calc_tmb format TMB
accept sqlmon_file noprompt "@&V1"

ALTER SESSION SET PLSQL_CCFLAGS = 'hub:&check_access_hub,sqlm:&check_access_sqlm';

DECLARE /*+no_monitor*/
    detail     INT := &detail; 
    plan_hash  INT := regexp_substr(:V2, '^\d+$');
    start_time DATE;
    end_time   DATE;
    sq_id      VARCHAR2(500):=:V1;
    inst       INT := :INSTANCE;
    did        INT := :dbid;
    execs      INT;
    counter    INT := &tot;
    filename   VARCHAR2(100);
    sqlmon     CLOB := :sqlmon_file;
    content    CLOB;
    txt        CLOB;
    lst        SYS.ODCIVARCHAR2LIST;
    dopename   VARCHAR(30);
    dopeid     INT;
    keyw       VARCHAR2(300):=:V2;
    c2         SYS_REFCURSOR;
    sql_exec   INT;
    sql_start  DATE;
    serial     INT;
    xml        xmltype;
    mon        xmltype;
    elem       xmltype;
    descs      SYS.ODCIARGDESCLIST;
    type t_fmt IS TABLE OF VARCHAR2(50);
    fmt        t_fmt;
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
        $IF $$sqlm=0 OR DBMS_DB_VERSION.release=1 $THEN
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
                SELECT *
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
        $IF dbms_db_version.version>11 $THEN
            sqlmon := DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL(RID => 0+sq_id, TYPE => 'XML');
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
        detail := 1;

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
            
            sql_exec := :V2;

            IF &rpt=0 THEN
                IF sql_exec IS NULL THEN
                    select max(sql_id) keep(dense_rank last order by sql_exec_start,sql_exec_id),
                           max(sql_exec_id) keep(dense_rank last order by sql_exec_start),
                           max(sql_exec_start)
                    into  sq_id,sql_exec,sql_start
                    from  gv$sql_monitor
                    where (sql_id=sq_id or lower(sq_id) in('l','last'))
                    AND   sql_plan_hash_value > 0
                    AND   sql_exec_id >0 
                    AND   PX_SERVER# IS NULL
                    AND   sql_text IS NOT NULL
                    and   inst_id=nvl(inst,inst_id);
                    
                    if sq_id is null then
                        raise_application_error(-20001,'cannot find relative records for the specific SQL ID!');
                    end if;
                END IF;
                fmt := t_fmt('ALL','ALL-BINDS','ALL-SQL_TEXT','ALL-SQL_TEXT-BINDS','TYPICAL');
                FOR i in 1..fmt.count LOOP
                    BEGIN
                        xml := DBMS_SQLTUNE.REPORT_SQL_MONITOR_XML(report_level => fmt(i),  sql_id => sq_id,  SQL_EXEC_START=>sql_start,SQL_EXEC_ID => sql_exec, inst_id => inst);
                        dbms_output.put_line('Extracted report level is: '||fmt(i));
                        exit;
                    EXCEPTION WHEN OTHERS THEN
                        IF i=fmt.count THEN
                            RAISE;
                        END IF;
                    END;
                END LOOP;
                filename := 'sqlm_' || sq_id ||nullif('_'||:v2,'_')|| '.html';
            ELSE
                sql_start := nvl(to_char(nvl(:V3,:starttime),'yymmddhh24mi'),sysdate-7);
                xml := xmltype(DBMS_SQLTUNE.REPORT_SQL_DETAIL(report_level => 'ALL',
                                                      sql_id => sq_id,
                                                      sql_plan_hash_value=>sql_exec,
                                                      start_time=>sql_start,
                                                      duration=> 86400*(sysdate-sql_start), 
                                                      inst_id => inst, 
                                                      dbid=>did,
                                                      top_n=>50,
                                                      type=>'XML'));
                filename := 'sqld_' || sq_id ||nullif('_'||:v2,'_') || '.html';
            END IF;
        END IF;

        content  := DBMS_REPORT.FORMAT_REPORT(xml, '&out') ;

        IF &rpt=0 THEN
            txt := DBMS_REPORT.FORMAT_REPORT(xml.deleteXML('//sql_fulltext'), 'text');
        ELSE
            dbms_lob.createtemporary(txt,true);
        END IF;

        IF &rpt=2 OR detail =1 THEN
            SELECT SYS.ODCIARGDESC(id,typ,null,val,null,null,null)
            BULK   COLLECT INTO descs
            FROM   XMLTABLE('//operation[qblock]' PASSING xml COLUMNS --
                            id VARCHAR2(6) PATH '@id',
                            typ VARCHAR2(30) PATH 'qblock',
                            val VARCHAR2(50) PATH 'object_alias') b;

            WITH line_info AS
             (SELECT ArgType as id,TableName as typ,ColName as val
              FROM   table(descs)),
            line_len AS
             (SELECT MAX(LENGTH(ID)) l1, MAX(LENGTH(typ)) l2, MAX(nvl(LENGTH(val),0) + 2) l3 FROM line_info)
            SELECT LPAD(ID, l1) || ' - ' || RPAD(typ, l2) || NVL2(val,' / ' || RPAD(val, l3),'') 
            BULK COLLECT INTO lst
            FROM line_info, line_len ORDER BY 0 + ID;

            flush('Query Block Name / Object Alias');

            WITH q AS(
                SELECT ArgType as id,replace('"'||TableName||'"','$','\$') as q,'"'||replace(ColName,'@','"@"')||'"' as c,
                       row_number() over(partition by TableName order by ArgType) seq
                FROM   table(descs)),
            hints AS(
                SELECT TRIM(',' FROM (
                            SELECT listagg('Q'||ID,',') WITHIN GROUP(ORDER BY  regexp_instr(val,'[ @"\(]+'||q))
                            FROM q
                            WHERE regexp_substr(val,'[ @"\(]+'||q) NOT LIKE '%"@%'
                            AND seq=1
                        )||(
                            SELECT nvl(listagg(',O'||ID,'') WITHIN GROUP(ORDER BY INSTR(val,c)),' ')
                            FROM q
                            WHERE INSTR(val,c)>0
                            AND ROWNUM<=5
                        )) Q,val,rownum r
                FROM   XMLTABLE('//outline_data/hint' PASSING xml COLUMNS val VARCHAR2(500) PATH '.') b),
            widths as(SELECT MAX(LENGTH(Q)) l from hints)
            SELECT rpad(q,l)||'  '||val 
            BULK COLLECT INTO LST
            FROM hints,widths
            ORDER BY r;
            flush('Outline Data (Hints)');
            
            WITH line_info AS
             (SELECT b.*
              FROM   XMLTABLE('//optimizer_env/param' PASSING xml COLUMNS --
                             typ VARCHAR2(50) PATH '@name',
                             val VARCHAR2(500) PATH '.') b),
            line_len AS
             (SELECT MAX(LENGTH(typ)) l1,MAX(LENGTH(val)) l2 FROM line_info)
            SELECT RPAD(typ, l1) || NVL2(val,' : ' || RPAD(val, l2),',') 
            BULK COLLECT INTO lst
            FROM line_info, line_len 
            ORDER BY typ;
            flush('Optimizer Environments');

            WITH line_info AS (
               SELECT a.*,row_number() OVER(PARTITION BY ID ORDER BY flag,typ) seq
               FROM(
                SELECT 1 flag,id,'[PRED] '||typ typ,val
                FROM   XMLTABLE('//operation/predicates' PASSING xml COLUMNS--
                                id VARCHAR2(5) PATH './../@id',
                                typ VARCHAR2(10) PATH '@type',
                                val VARCHAR2(2000) PATH '.') b
                UNION ALL
                SELECT 2 flag,id,'[PROJ] Projection' typ,val
                FROM   XMLTABLE('//operation/project' PASSING xml COLUMNS--
                                id VARCHAR2(5) PATH './../@id',
                                val VARCHAR2(2000) PATH '.') b
                UNION ALL
                SELECT DISTINCT 3,id, '[STATS] '||NAME, 
                       trim(CASE WHEN lower(descr) LIKE '%bytes%' THEN dbms_xplan.format_size(VALUE) ELSE dbms_xplan.format_number(VALUE) END)||' '||descr VALUE
                FROM   XMLTABLE('//rwsstats/metadata/stat' PASSING xml COLUMNS--
                                stat_grp INT PATH './../../@group_id',
                                stat_id INT PATH '@id',
                                NAME VARCHAR2(50) PATH '@name',
                                descr VARCHAR2(300) PATH '@desc') b,
                       XMLTABLE('//operation/rwsstats/stat' PASSING xml COLUMNS--
                                stat_grp INT PATH './../@group_id',
                                id  VARCHAR2(5) PATH './../../@id',
                                stat_id INT PATH '@id',
                                VALUE INT PATH '.') c --
                WHERE  b.stat_grp = c.stat_grp
                AND    b.stat_id = c.stat_id
                UNION ALL
                SELECT 4,id,'[WAIT] '||nvl(event,'ON CPU'),trim(dbms_xplan.format_number(cnt))||' AAS'
                FROM XMLTABLE('//operation/activity_sampled/activity' PASSING xml COLUMNS--
                    id VARCHAR2(5) PATH './../../@id',
                    w_class VARCHAR2(10) PATH '@class',
                    event VARCHAR2(2000) PATH '@event',
                    cnt INT PATH '.') b) a)
            SELECT SYS.ODCIARGDESC(ID,TYP,NULL,VAL,NULL,NULL,seq)
            BULK COLLECT INTO descs
            FROM   line_info;
            --Bypass XML Bug in 11g
            WITH line_info AS(
                SELECT ArgType AS ID,TableName as Typ, ColName as val,Cardinality as seq
                FROM TABLE(descs)
            ),
            line_len AS(
               SELECT MAX(LENGTH(ID)) l1,MAX(LENGTH(typ)) l2,MAX(LENGTH(val)+2) l3
               FROM line_info
            )
            SELECT decode(seq,1,LPAD(ID,l1)||' - ',LPAD(' ',l1+3))||RPAD(typ,l2)||' : '||regexp_replace(replace(val,chr(10),' '),'(.{150}[^ ]+ +)','\1'||chr(10)||lpad(' ',l2+l1+6))
            BULK COLLECT INTO lst
            FROM line_info,line_len
            ORDER BY 0+ID,seq;
            flush('Additional Plan Line Information');
            

            WITH binds AS
             (SELECT NAME,
                     MAX(dty) dty,
                     MAX(maxlen) maxlen,
                     MAX(pre) pre,
                     MAX(scl) scl,
                     MAX(frm) frm,
                     MAX(dtystr) dtystr,
                     MAX(DECODE(typ, 'binds', val)) bind,
                     MAX(DECODE(typ, 'peeked_binds', HEXTORAW(val))) peek
              FROM   (SELECT b.*
                      FROM   XMLTABLE('//bind' PASSING xml COLUMNS --
                                      typ VARCHAR2(15) PATH 'name(..)',
                                      NAME VARCHAR2(30) PATH '@name | @nam',
                                      val VARCHAR2(300) PATH '.',
                                      dty INT PATH '@dty',
                                      pre INT PATH '@pre',
                                      scl INT PATH '@scl',
                                      frm INT PATH '@frm',
                                      dtystr VARCHAR2(30) PATH '@dtystr',
                                      maxlen INT PATH '@maxlen | @mxl') b)
              GROUP  BY NAME),
            line_info AS
             (SELECT NAME,
                     NVL(dtystr,
                         decode(dty, /* DATA_TYPE */
                                0,NULL,
                                1,decode(frm, 2, 'NVARCHAR2', 'VARCHAR2'),
                                2,decode(scl,
                                       -127,'FLOAT',
                                       CASE
                                           WHEN pre = 38 AND nvl(scl, 0) = 0 THEN
                                            'INTEGER'
                                           ELSE
                                            'NUMBER'
                                       END),
                                3,'NATIVE INTEGER',
                                8,'LONG',
                                9,decode(frm, 2, 'NCHAR VARYING', 'VARCHAR'),
                                11,'ROWID',
                                12,'DATE',
                                23,'RAW',
                                24,'LONG RAW',
                                29,'BINARY_INTEGER',
                                69,'ROWID',
                                96,decode(frm, 2, 'NCHAR', 'CHAR'),
                                100,'BINARY_FLOAT',
                                101,'BINARY_DOUBLE',
                                102,'REF CURSOR',
                                104,'UROWID',
                                105,'MLSLABEL',
                                106,'MLSLABEL',
                                110,'REF',
                                111,'REF',
                                112,decode(frm, 2, 'NCLOB', 'CLOB'),
                                113,'BLOB',
                                114,'BFILE',
                                115,'CFILE',
                                121,'OBJECT',
                                122,'TABLE',
                                123,'VARRAY',
                                178,'TIME',
                                179,'TIME WITH TIME ZONE',
                                180,'TIMESTAMP',
                                181,'TIMESTAMP WITH TIME ZONE',
                                231,'TIMESTAMP WITH LOCAL TIME ZONE',
                                182,'INTERVAL YEAR TO MONTH',
                                183,'INTERVAL DAY TO SECOND',
                                250,'PL/SQL RECORD',
                                251,'PL/SQL TABLE',
                                252,'PL/SQL BOOLEAN',
                                'UNDEFINED') || CASE
                             WHEN dty = 2 AND scl > 0 AND nvl(nullif(scl, 0), pre) NOT IN (38, -127) THEN
                              '(' || pre || NULLIF(',' || scl, ',') || ')'
                             WHEN dty != 2 AND maxlen > 0 THEN
                              '(' || maxlen || ')'
                         END) datatype,
                     bind,
                     rtrim(decode(dty,
                                  2,to_char(utl_raw.cast_to_number(peek)),
                                  1,to_char(decode(frm, 2, utl_raw.cast_to_nvarchar2(peek),utl_raw.cast_to_varchar2(peek))),
                                  9,to_char(decode(frm, 2, utl_raw.cast_to_nvarchar2(peek),utl_raw.cast_to_varchar2(peek))),
                                  96,to_char(decode(frm, 2, utl_raw.cast_to_nvarchar2(peek),utl_raw.cast_to_varchar2(peek))),
                                  112,to_char(decode(frm, 2, utl_raw.cast_to_nvarchar2(peek),utl_raw.cast_to_varchar2(peek))),
                                  100,to_char(utl_raw.cast_to_binary_double(peek)),
                                  101,to_char(utl_raw.cast_to_binary_float(peek)),
                                  180,lpad(TO_NUMBER(SUBSTR(peek, 1, 2), 'XX') - 100, 2, 0) || lpad(TO_NUMBER(SUBSTR(peek, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 5, 2), 'XX'), 2, 0) || '-' || lpad(TO_NUMBER(SUBSTR(peek, 7, 2), 'XX'), 2, 0) || ' ' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 9, 2), 'XX') - 1, 2, 0) || ':' || lpad(TO_NUMBER(SUBSTR(peek, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 13, 2), 'XX') - 1, 2, 0) || '.' || nvl(substr(TO_NUMBER(SUBSTR(peek, 15, 8), 'XXXXXXXX'), 1, 6), '0'),
                                  181,lpad(TO_NUMBER(SUBSTR(peek, 1, 2), 'XX') - 100, 2, 0) || lpad(TO_NUMBER(SUBSTR(peek, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 5, 2), 'XX'), 2, 0) || '-' || lpad(TO_NUMBER(SUBSTR(peek, 7, 2), 'XX'), 2, 0) || ' ' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 9, 2), 'XX') - 1, 2, 0) || ':' || lpad(TO_NUMBER(SUBSTR(peek, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 13, 2), 'XX') - 1, 2, 0) || '.' || nvl(substr(TO_NUMBER(SUBSTR(peek, 15, 8), 'XXXXXXXX'), 1, 6), '0') || ' ' ||
                                      nvl(TO_NUMBER(SUBSTR(peek, 23, 2), 'XX') - 20, 0) || ':' || nvl(TO_NUMBER(SUBSTR(peek, 25, 2), 'XX') - 60, 0),
                                  231,lpad(TO_NUMBER(SUBSTR(peek, 1, 2), 'XX') - 100, 2, 0) || lpad(TO_NUMBER(SUBSTR(peek, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 5, 2), 'XX'), 2, 0) || '-' || lpad(TO_NUMBER(SUBSTR(peek, 7, 2), 'XX'), 2, 0) || ' ' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 9, 2), 'XX') - 1, 2, 0) || ':' || lpad(TO_NUMBER(SUBSTR(peek, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 13, 2), 'XX') - 1, 2, 0) || '.' || nvl(substr(TO_NUMBER(SUBSTR(peek, 15, 8), 'XXXXXXXX'), 1, 6), '0') || ' ' ||
                                      nvl(TO_NUMBER(SUBSTR(peek, 23, 2), 'XX') - 20, 0) || ':' || nvl(TO_NUMBER(SUBSTR(peek, 25, 2), 'XX') - 60, 0),
                                  12,lpad(TO_NUMBER(SUBSTR(peek, 1, 2), 'XX') - 100, 2, 0) || lpad(TO_NUMBER(SUBSTR(peek, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 5, 2), 'XX'), 2, 0) || '-' || lpad(TO_NUMBER(SUBSTR(peek, 7, 2), 'XX'), 2, 0) || ' ' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 9, 2), 'XX') - 1, 2, 0) || ':' || lpad(TO_NUMBER(SUBSTR(peek, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                      lpad(TO_NUMBER(SUBSTR(peek, 13, 2), 'XX') - 1, 2, 0),
                                  '' || peek)) peek
              FROM   binds),
            w_len AS
             (SELECT /**/ greatest(MAX(length(NAME)), 3) l1, greatest(MAX(LENGTH(datatype)), 9) l2, MAX(nvl(LENGTH(bind),6)) l3, MAX(nvl(LENGTH(peek),6)) l4, COUNT(1) c FROM line_info)
            SELECT RPAD(NAME, l1) || ' : DataType=' || RPAD(datatype, l2) || ' / Bind=' || RPAD(nvl(bind,'<NULL>'), l3) || ' / PeekedBind='||nvl(peek,'<NULL>') 
            BULK COLLECT INTO lst
            FROM line_info, w_len WHERE c > 0 ORDER BY NAME;

            flush('Binds and Peeked Binds');

            WITH line_info AS
             (SELECT ID,
                     MAX(NAME || NVL2(unit, ' (' || unit || ')', '')) NAME,
                     trim(dbms_xplan.format_size(MAX(VALUE)*nvl(MAX(factor),1))) || DECODE(ID, 1, ' / ' || MAX(cpu_count), '') maxv,
                     trim(dbms_xplan.format_size(MIN(VALUE)*nvl(MAX(factor),1))) || DECODE(ID, 1, ' / ' || MAX(cpu_count), '') minv,
                     trim(dbms_xplan.format_size(AVG(VALUE)*nvl(MAX(factor),1))) || DECODE(ID, 1, ' / ' || MAX(cpu_count), '') avgv,
                     trim(dbms_xplan.format_size(MEDIAN(VALUE)*nvl(MAX(factor),1))) || DECODE(ID, 1, ' / ' || MAX(cpu_count), '') mdv,
                     CASE WHEN max(unit) like '%per_sec%' THEN trim(dbms_xplan.format_size(SUM(VALUE*duration)*nvl(MAX(factor),1))) ELSE ' ' END sums,
                     trim(dbms_xplan.format_time_s(SUM(duration))) dur
              FROM   XMLTABLE('//stattype//stat' PASSING xml COLUMNS ID INT PATH '@id',
                              cpu_count INT PATH './../../@cpu_cores',
                              unit VARCHAR2(30) PATH '@unit',
                              NAME VARCHAR2(30) PATH '@name',
                              duration INT PATH './../../@duration',
                              factor INT PATH '@factor',
                              VALUE INT PATH '@value') b
              
              GROUP  BY ID
              HAVING MAX(VALUE) IS NOT NULL
              ORDER  BY ID),
            w_len AS
             (SELECT 3 l1, greatest(MAX(LENGTH(NAME)), 3) l2,greatest(MAX(NVL(LENGTH(sums),0)), 8) l3, COUNT(1) c FROM line_info)
            SELECT * BULK COLLECT INTO lst
            FROM   (SELECT '+' || LPAD('-', l1 + l2 + l3*6 + 6*3, '-') || '+'
                    FROM   w_len
                    WHERE  c > 0
                    UNION ALL
                    SELECT '| ' || RPAD('ID', l1) || ' | ' || LPAD('Name', l2) || ' | ' || LPAD('Avg', l3) || ' |'|| LPAD('Min', l3) || ' |'|| LPAD('Max', l3) || ' |'|| LPAD('Median', l3) || ' |'|| LPAD('Sum', l3) || ' |'|| LPAD('Duration', l3) || ' |'
                    FROM   w_len
                    WHERE  c > 0
                    UNION ALL
                    SELECT  '+' || LPAD('-', l1 + l2 + l3*6 + 6*3, '-') || '+'
                    FROM   w_len
                    WHERE  c > 0
                    UNION ALL
                    SELECT *
                    FROM   (SELECT '| ' || RPAD(ID, l1) || ' | ' || RPAD(NAME, l2) || ' | ' || LPAD(avgv, l3) || ' |'|| LPAD(minv, l3) || ' |'|| LPAD(maxv, l3) || ' |'
                                    || LPAD(mdv, l3) || ' |'|| LPAD(sums, l3) || ' |'|| LPAD(dur, l3) || ' |'
                            FROM   line_info, w_len
                            WHERE  c > 0
                            ORDER  BY ID)
                    UNION ALL
                    SELECT  '+' || LPAD('-', l1 + l2 + l3*6 + 6*3, '-') || '+'
                    FROM   w_len
                    WHERE  c > 0);
            flush('Metrics');

            SELECT SYS.ODCIARGDESC(c.cnt,REPLACE(NVL(substr(c.event,1,30), c.w_class), 'Cpu', 'ON CPU'),
                                   b.id ||nvl2(b.id,'(' || round(b.cnt / c.cnt * 100, 1) || '%)',' '),
                                   NULL,NULL,NULL,
                                   row_number() OVER(PARTITION BY NVL(c.event, c.w_class) ORDER BY b.cnt DESC, b.id)) 
            BULK COLLECT INTO descs
            FROM   XMLTABLE('//sql_monitor_report/activity_sampled/activity' PASSING xml COLUMNS --
                            w_class VARCHAR2(10) PATH '@class',
                            event VARCHAR2(2000) PATH '@event',
                            cnt INT PATH '.') C
            LEFT   JOIN XMLTABLE('//operation/activity_sampled/activity' PASSING xml COLUMNS --
                            id INT PATH './../../@id', 
                            w_class VARCHAR2(10) PATH '@class', 
                            event VARCHAR2(2000) PATH '@event', 
                            cnt INT PATH '.') b
            ON     NVL(c.event, c.w_class) = NVL(b.event, b.w_class)
            WHERE c.cnt>0;

            WITH waits AS
             (SELECT clz, to_char(cnt) cnt,round(100*ratio_to_report(cnt) over(),2)||'%' pct, listagg(pct, ',') WITHIN GROUP(ORDER BY seq) ids
              FROM   (
                    SELECT ArgType as cnt,TableName as clz,TableSchema as pct,Cardinality as seq
                    FROM   TABLE(descs))
              WHERE  seq <= 5
              GROUP  BY clz, cnt),
            w_len AS
             (SELECT greatest(MAX(length(clz)), 10) l1, greatest(MAX(LENGTH(''||cnt)), 3) l2, greatest(MAX(LENGTH(ids)), 16) l3, COUNT(1) c FROM waits)
            SELECT * BULK COLLECT INTO lst
            FROM (
                SELECT '+' || LPAD('-', l1 + l2 + l3 + 8 + 9, '-') || '+'
                FROM   w_len
                WHERE  c > 0
                UNION ALL
                SELECT '| ' || RPAD('Wait Class', l1) || ' | ' || LPAD('AAS', l2) || ' | ' || LPAD('Pct', 6) ||  ' | ' || RPAD('Top Lines of AAS', l3) || ' |'
                FROM   w_len
                WHERE  c > 0
                UNION ALL
                SELECT '+' || LPAD('-', l1 + l2 + l3 + 8 + 9, '-') || '+'
                FROM   w_len
                WHERE  c > 0
                UNION ALL
                SELECT *
                FROM   (
                    SELECT '| ' || RPAD(clz, l1) || ' | ' || LPAD(cnt, l2)  || ' | ' || LPAD(pct, 6) || ' | ' || RPAD(ids, l3) || ' |' 
                    FROM waits, w_len 
                    WHERE c > 0 
                    ORDER BY 0 + cnt DESC,clz)
                UNION ALL
                SELECT '+' || LPAD('-', l1 + l2 + l3 + 8 + 9 , '-') || '+' FROM w_len WHERE c > 0);
            flush('Wait Event Summary');

            WITH line_info AS
             (SELECT b.*
              FROM   XMLTABLE('//other_xml/info[@note="y" or @type=("sql_patch","sql_profile","outline","baseline")]' PASSING xml COLUMNS --
                             typ VARCHAR2(50) PATH '@type',
                             val VARCHAR2(500) PATH '.') b),
            line_len AS
             (SELECT MAX(LENGTH(typ)) l1,MAX(LENGTH(val)) l2 FROM line_info)
            SELECT RPAD(typ, l1) || NVL2(val,' : ' || RPAD(val, l2),',')
            BULK COLLECT INTO lst
            FROM line_info, line_len ORDER BY typ;
            flush('Notes');
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
            FROM   (SELECT   a.sql_id &OPTION,
                             &option1 to_char(MIN(sql_exec_start), 'YYMMDD HH24:MI:SS') first_seen,
                             to_char(MAX(last_refresh_time), 'YYMMDD HH24:MI:SS') last_seen,
                             MAX(sid || ',@' || inst_id) keep(dense_rank LAST ORDER BY last_refresh_time) last_sid,
                             MAX(status) keep(dense_rank LAST ORDER BY last_refresh_time, sid) last_status,
                             round(sum(last_refresh_time - sql_exec_start)/&avg * 86400*1e6, 2) dur,
                             round(sum(ela)/&avg , 2) ela,
                             round(sum(QUEUING_TIME)/&avg , 2) QUEUE,
                             round(sum(CPU_TIME)/&avg , 2) CPU,
                             round(sum(APPLICATION_WAIT_TIME)/&avg , 2) app,
                             round(sum(CONCURRENCY_WAIT_TIME)/&avg , 2) cc,
                             round(sum(CLUSTER_WAIT_TIME)/&avg , 2) cl,
                             round(sum(PLSQL_EXEC_TIME)/&avg , 2) plsql,
                             round(sum(JAVA_EXEC_TIME)/&avg , 2) JAVA,
                             round(sum(USER_IO_WAIT_TIME)/&avg , 2) io,
                             round(sum(PHYSICAL_READ_BYTES)/&avg, 2) READ,
                             round(sum(PHYSICAL_WRITE_BYTES)/&avg, 2) WRITE,
                             &ver round(sum(IO_CELL_OFFLOAD_ELIGIBLE_BYTES)/&avg,2) OFL,
                             substr(regexp_replace(regexp_replace(MAX(sql_text), '^\s+'), '\s+', ' '), 1, 200) sql_text
                    FROM   (select sql_id,sql_exec_start,sql_exec_id,
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
                                     &ver ,SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES) IO_CELL_OFFLOAD_ELIGIBLE_BYTES
                                FROM  gv$sql_monitor a
                                WHERE (&filter)
                                GROUP BY sql_id,sql_exec_start,sql_exec_id) a
                    WHERE  (&SNAP=1 OR (plan_hash IS NULL AND :V2 IS NOT NULL OR NOT regexp_like(upper(TRIM(SQL_TEXT)), '^(BEGIN|DECLARE|CALL)')))
                    AND    (&SNAP=1 OR (keyw IS NULL OR a.sql_id ||'_'|| sql_plan_hash_value||'_'|| sql_exec_id || lower(sql_text) LIKE '%' || lower(keyw) || '%'))
                    GROUP  BY sql_id &OPTION
                    ORDER  BY last_seen DESC)
            WHERE  ROWNUM <= 100
            ORDER  BY last_seen, ela;
        IF sq_id IS NOT NULL AND '&option' IS NOT NULL THEN
            SELECT /*+no_expand*/ MAX(sql_plan_hash_value) KEEP(DENSE_RANK LAST ORDER BY SQL_EXEC_START) INTO plan_hash 
            FROM  gv$sql_monitor 
            WHERE sql_id = sq_id AND (plan_hash IS NULL OR plan_hash in(sql_exec_id,sql_plan_hash_value));
        
            IF plan_hash IS NOT NULL THEN
                SELECT MIN(sql_exec_start), MAX(last_refresh_time), &uniq
                INTO   start_time, end_time, execs
                FROM   gv$sql_monitor
                WHERE  sql_id = sq_id
                AND    PX_SERVER# IS NULL
                AND    sql_plan_hash_value = plan_hash;
                
                $IF DBMS_DB_VERSION.VERSION>11 AND $$hub =1 $THEN
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
            
                OPEN :c0 FOR
                    SELECT DECODE(phv, plan_hash, '*', ' ') || phv plan_hash,
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
                                     max(greatest((last_refresh_time-sql_exec_start)*86400,ELAPSED_TIME,(CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME)))  over(partition by sql_exec_id,sql_exec_start) dur,
                                     count(distinct inst_id||','||sid) over(partition by sql_exec_id,sql_exec_start) dops 
                            FROM gv$sql_monitor a WHERE sql_id = sq_id) b
                    GROUP  BY phv
                    ORDER  BY decode(phv, plan_hash, SYSDATE + 1, MAX(last_refresh_time));
            
                OPEN :c1 FOR
                    WITH ASH AS
                     (SELECT /*+materialize*/id, SUM(cnt) aas, MAX(SUBSTR(event, 1, 30) || '(' || cnt || ')') keep(dense_rank LAST ORDER BY cnt) top_event
                        FROM   (SELECT id, nvl(event, 'ON CPU') event, round(SUM(flag) / counter, 3) cnt
                                FROM   (SELECT a.*, rank() over(PARTITION BY sql_exec_id,sql_exec_start ORDER BY flag) r
                                        FROM   (SELECT SQL_PLAN_LINE_ID id, event, current_obj#, sql_exec_id,sql_exec_start, 1 flag
                                                FROM   gv$active_session_history
                                                WHERE  sql_id = sq_id
                                                AND    sql_plan_hash_value = plan_hash
                                                AND    sample_time BETWEEN start_time AND end_time
                                                UNION ALL
                                                SELECT SQL_PLAN_LINE_ID id, event, current_obj#, sql_exec_id,sql_exec_start, 10 flag
                                                FROM   dba_hist_active_sess_history
                                                WHERE  sql_id = sq_id
                                                AND    sql_plan_hash_value = plan_hash
                                                AND    sample_time BETWEEN start_time AND end_time) a)
                                WHERE  r = 1
                                GROUP  BY id, event)
                        GROUP  BY id),
                    SQLM as (SELECT /*+materialize*/ plan_line_id ID,
                                     MAX(plan_parent_id) pid,
                                     MIN(lpad(' ', plan_depth, ' ') || plan_operation || NULLIF(' ' || plan_options, ' ')) operation,
                                     MAX(plan_object_name) name,
                                     round(SUM(TIME*flag), 3) TIME,
                                     round(SUM(TIME*flag) / NULLIF(SUM(tick*flag),0), 2) "%",
                                     --MAX(plan_cost) est_cost,
                                     MAX(plan_cardinality) est_rows,
                                     round(SUM(output_rows) / execs, 2) act_rows,
                                     round(SUM(starts) / execs, 2) avg_exec,
                                     round(SUM(output_rows) / counter, 3) outputs,
                                     round(SUM(io_interconnect_bytes) / counter, 3) cellio,
                                     round(SUM(physical_read_bytes + physical_write_bytes) / counter, 3) iosize,
                                     round(SUM(physical_read_requests + physical_write_requests) / counter, 3) ioreq,
                                     MAX(workarea_max_mem) mem,
                                     MAX(workarea_max_tempseg) temp
                            FROM   (SELECT a.*,
                                             decode(a.sql_exec_start,max(a.sql_exec_start) over(),1,0) flag,                
                                             ((b.last_refresh_time - b.sql_exec_start)*86400+1)*NVL2(b.px_qcsid,0,1) tick,
                                             max((a.last_change_time-a.first_change_time)*86400+1) over(partition by a.sql_exec_id,a.sql_exec_start,a.plan_line_id) TIME
                                    FROM   gv$sql_plan_monitor a, gv$sql_monitor b
                                    WHERE  b.sql_id = sq_id
                                    AND    b.sql_plan_hash_value = plan_hash
                                    AND    b.sql_id = a.sql_id
                                    AND    b.sql_exec_id = a.sql_exec_id
                                    AND    b.sql_exec_start=a.sql_exec_start
                                    AND    b.key=a.key
                                    AND    b.inst_id = a.inst_id
                                    AND    b.sid = a.sid
                                    AND    b.sql_plan_hash_value = a.sql_plan_hash_value)
                            GROUP  BY plan_line_id)
                    SELECT row_number() over(ORDER BY rownum DESC) OID, m.*
                    FROM   (select * FROM (SELECT * FROM SQLM LEFT JOIN ash USING (id)) START WITH ID = (SELECT MIN(id) FROM SQLM) CONNECT BY PRIOR id = pid ORDER SIBLINGS BY id DESC) m
                    ORDER  BY id;
                
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
