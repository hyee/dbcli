/*  Generate SQL Monitor report in both detailed TEXT and ACTIVE format.
    Usages:   
        1) Generate Last SQL Monitor report for the specific SQL ID: @sqlm <sql_id> [<sql_exec_id>]
        2) Generate Last SQL Monitor report in database: @sqlm l or @sqlm last
        3) Generate SQL Monitor report via the content from a query: @sqlm "<Select statement that returns one fields whose content is SQL Monitor report>"
        4) Generate SQL Monitor from dba_hist_reports with specific report_id

    Examples:
        1.1) @sqlm 85f3z6f04jvyd
        1.2) @sqlm 85f3z6f04jvyd 16777216
        2.1) @sqlm l
        2.2) @sqlm last
        3.1) @sqlm "select sqlmon_clob from sqlmon_report_table"
        3.2) @sqlm "select sqlmon_clob from sqlmon_report_table where sql_id='85f3z6f04jvyd'"
        4)   @sqlm 6423  (from dba_hist_reports.report_id)
*/

COLUMN 2 NEW_VALUE 2

SET TERMOUT OFF VERIFY OFF FEED OFF ARRAYSIZE 1000 PAGES 0
SELECT  '' "2" FROM dual WHERE ROWNUM = 0;
SET TERMOUT ON LINES 2000 LONG 80000000 longchunksize 30000

VAR c refcursor;
VAR filename VARCHAR2(50);
var sqlmon CLOB;
col PLAN_OUTPUT format a400

DECLARE /*+no_monitor*/
    sq_id      VARCHAR2(500):='&1';
    sql_exec   INT:=REGEXP_SUBSTR('&2','\d+');
    sql_start  DATE;
    filename   VARCHAR2(100);
    sqlmon     CLOB;
    content    CLOB;
    txt        CLOB;
    lst        SYS.ODCIVARCHAR2LIST;
    serial     INT;
    xml        xmltype;
    mon        xmltype;
    descs      SYS.ODCIARGDESCLIST;
    PROCEDURE wr(msg VARCHAR2) IS
        m VARCHAR2(32767) := nvl(msg,' ');
    BEGIN
        m := replace(msg,chr(10),chr(10)||'    ');
        dbms_lob.writeappend(txt,length(m)+5,chr(10)||'    '||m);
    END;
    PROCEDURE flush(section VARCHAR2) IS
    BEGIN
        IF lst.count > 0 then
            wr(' ');
            wr(lpad('=',66,'='));
            wr('|  '||rpad(section,60)||'  |');
            wr(lpad('-',66,'-'));
            for i in 1..lst.count loop
                wr(lst(i));
            end loop;
        end if;
    END;

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
    IF sq_id IS NULL THEN
        raise_application_error(-20001,'Please input the target sql_id/file/query!');
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
        xml  := xmltype(sqlmon).EXTRACT('//report[1]');
        IF xml IS NULL THEN
            raise_application_error(-20001,'Target file is not a valid SQL Monitor Report file!');
        END IF;
        mon := xml.extract('//report_parameters[1]');
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
        sql_exec:= mon.extract('//report_parameters/sql_exec_id[1]/text()').getNumberVal();
        xml  := xmltype(xml.getClobVal());
    END IF;
    
    IF xml IS NULL THEN
        IF sql_exec IS NULL THEN
            select max(sql_id) keep(dense_rank last order by sql_exec_start,sql_exec_id),
                   max(sql_exec_id) keep(dense_rank last order by sql_exec_start),
                   max(sql_exec_start)
            into  sq_id,sql_exec,sql_start
            from  gv$sql_monitor
            where (sql_id=sq_id or lower(sq_id) in('l','last'))
            AND   sql_plan_hash_value > 0
            AND   sql_exec_id >0 
            AND   PX_SERVER# IS NULL;
        END IF;
        
        --If run into error on fetching the ALL report, then get TYPICAL instead
        BEGIN
            xml := DBMS_SQLTUNE.REPORT_SQL_MONITOR_XML(report_level => 'ALL',  sql_id => sq_id,  SQL_EXEC_START=>sql_start,SQL_EXEC_ID => sql_exec);
        EXCEPTION WHEN OTHERS THEN
            xml := DBMS_SQLTUNE.REPORT_SQL_MONITOR_XML(report_level => 'TYPICAL', sql_id => sq_id,  SQL_EXEC_START=>sql_start,SQL_EXEC_ID => sql_exec);
        END;
    END IF;
    
    --When building ACTIVE report, don't compressing the metadata
    BEGIN
        execute immediate 'alter session set events ''emx_control compress_xml=none''';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    --reduce line widths and add extra white spaces before each line
    --txt := regexp_replace(DBMS_REPORT.FORMAT_REPORT(xml, 'text'),'([^'||chr(10)||']{300}[^ '||chr(10)||']*) ','\1'||chr(10),1,1,'m');
    txt := replace(DBMS_REPORT.FORMAT_REPORT(xml, 'text'),chr(10),chr(10)||'    ');
    
    --==================== Start building addtional information for the TEXT report ===============
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
    
    WITH line_info AS(
        SELECT ArgType AS ID,TableName as Typ, ColName as val,Cardinality as seq
        FROM TABLE(descs)),
    line_len AS(
       SELECT MAX(LENGTH(ID)) l1,MAX(LENGTH(typ)) l2,MAX(LENGTH(val)+2) l3
       FROM line_info)
    SELECT decode(seq,1,LPAD(ID,l1)||' - ',LPAD(' ',l1+3))||RPAD(typ,l2)||' : '||regexp_replace(replace(val,chr(10),' '),'(.{150}[^ ]* +)','\1'||chr(10)||lpad(' ',l2+l1+6))
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
      FROM   XMLTABLE('//stattype//stat' PASSING xml COLUMNS --
                      ID INT PATH '@id',
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
    
    --Bypass 11g XML bugs
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
        SELECT '+' || LPAD('-', l1 + l2 + l3 + 8 + 8, '-') || '+'
        FROM   w_len
        WHERE  c > 0
        UNION ALL
        SELECT '| ' || RPAD('Wait Class', l1) || ' | ' || LPAD('AAS', l2) || ' | ' || LPAD('Pct', 5) ||  ' | ' || RPAD('Top Lines of AAS', l3) || ' |'
        FROM   w_len
        WHERE  c > 0
        UNION ALL
        SELECT '+' || LPAD('-', l1 + l2 + l3 + 8 + 8, '-') || '+'
        FROM   w_len
        WHERE  c > 0
        UNION ALL
        SELECT *
        FROM   (
            SELECT '| ' || RPAD(clz, l1) || ' | ' || LPAD(cnt, l2)  || ' | ' || LPAD(pct, l2) || ' | ' || RPAD(ids, l3) || ' |' 
            FROM waits, w_len 
            WHERE c > 0 
            ORDER BY 0 + cnt DESC,clz)
        UNION ALL
        SELECT '+' || LPAD('-', l1 + l2 + l3 + 8 + 8 , '-') || '+' FROM w_len WHERE c > 0);
    flush('Wait Event Summary');
    
    WITH line_info AS
     (SELECT b.*
      FROM   XMLTABLE('//other_xml/info[@note="y" or @type=("sql_patch","sql_profile","outline","baseline")]' PASSING xml COLUMNS --
                      typ VARCHAR2(50) PATH '@type',
                      val VARCHAR2(500) PATH '.') b),
    line_len AS
     (SELECT MAX(LENGTH(typ)) l1, MAX(LENGTH(val)) l2 FROM line_info)
    SELECT RPAD(typ, l1) || NVL2(val, ' : ' || RPAD(val, l2), ',') 
    BULK COLLECT INTO lst 
    FROM line_info, line_len ORDER BY typ;
    flush('Notes');
    
    OPEN :c FOR SELECT txt PLAN_OUTPUT from dual;
    content   := DBMS_REPORT.FORMAT_REPORT(xml, 'active') ;
    filename  := 'sqlm_' || sq_id;
    :sqlmon  := content;
    :filename := filename;
END;
/
UNDEF 1
UNDEF 2
set termout off
col fname new_value fname
select :filename fname from dual;
set termout on
spool &fname..txt
print c;
spool off
pro SQL Monitor Report saved to &fname..txt
set termout off
spool &fname..html
SELECT :sqlmon sqlmon_html from dual;
spool off
set termout on pages 9999
pro SQL Monitor Report saved to &fname..html