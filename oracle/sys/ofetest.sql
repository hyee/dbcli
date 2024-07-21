/*[[Test the execution plan changes by adjusting the new fix controls and session environments. Usage: @@NAME <sql_id> <low_OFE> [high_OFE] [-batch"<number>"] [-ofe|-env] [-f"<plan_filter>"|-k"<keyword>]
    -batch: number of options to be tested for each batch
    -env  : only test the parameters
    -ofe  : only test the fix controls
    -accu : test the options in accumulation mode, instead turning on/off one by one
    -desc : test from high OFE to low OFE, instead of from low to high

    Example: @@NAME g6px76dmjv1jy 10.2.0.4 12.1.0
             @@NAME g6px76dmjv1jy 11.2.0.4 -k"PARTITION RANGE SINGLE"
    --[[
        @ARGS  : 2
        &typ   : default={all} ofe={ofe} env={env}
        &filter: default={1=2} f={} k={operation||' '||options||' '||object_name like upper('%&0%')}
        &batch : default={1} batch={}
        &sep   : default={rowsep default} batch={rowsep - colsep |}
        &accu  : default={0} accu={1}
        &dir   : default={asc} desc={desc}
    --]]
]]*/
set SQLTIMEOUT 7200 verify off feed off &sep
var cur refcursor;
var msg varchar2
var plans clob;

DECLARE
    low_ofe   VARCHAR2(30) := :V2;
    high_ofe  VARCHAR2(30) := :V3;
    buff      CLOB;
    bulks     PLS_INTEGER := :batch;
    sql_text  CLOB;
    low_env   sys.XMLTYPE;
    high_env  sys.XMLTYPE;
    ofe_cnt   PLS_INTEGER := 0;
    env_cnt   PLS_INTEGER := 0;
    old_ofe   VARCHAR2(32767);
    new_ofe   VARCHAR2(32767);
    tmp_ofe   VARCHAR2(32767);
    errcount  PLS_INTEGER := 0;
    ofelist   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    ofeold    SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    ofedesc   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    counter   PLS_INTEGER := 0;
    to_schema VARCHAR2(128);
    fmt       VARCHAR2(300);
    curr      VARCHAR2(128) := sys_context('userenv', 'current_schema');
    qry       VARCHAR2(4000) := q'{
        SELECT 'ofe' typ,''||bugno name,''||value value,3 vtype,DESCRIPTION,nvl2(optimizer_feature_enable,1,0) flag,0+regexp_substr(optimizer_feature_enable,'^\d+\.\d+') ofe
        FROM   v$session_fix_control
        WHERE  SESSION_ID=userenv('sid')
        AND    '&typ' IN('all','ofe')
        AND    bugno NOT IN(16923858,25167306)
        AND    (optimizer_feature_enable IS NOT NULL OR value>0)
        UNION  ALL
        SELECT 'env',pi.ksppinm, NVL(kc.PVALUE_QKSCESEROW,cv.KSPPSTVL), ksppity,ksppdesc,1,0
        FROM   sys.x$ksppi pi ,sys.x$ksppcv cv,sys.X$QKSCESES kc
        WHERE  pi.indx=cv.indx
        AND    pi.ksppinm=kc.PNAME_QKSCESEROW(+)
        AND    kc.SID_QKSCESEROW(+) = userenv('sid')
        AND    ksppity IN (1, 2, 3)
        AND    LENGTH(NVL(kc.PVALUE_QKSCESEROW,cv.KSPPSTVL))<=20
        AND    bitand(ksppiflg / 256, 1)=1
        AND    substr(pi.ksppinm,1,2)!='__'
        AND    pi.ksppinm!='optimizer_features_enable'
        AND    '&typ' IN('all','env')
        ORDER  BY 1,ofe &dir,2 &dir}';
    CURSOR c IS
        SELECT /*+ordered use_hash(b)*/ 
               typ,name,vtype,
               CASE WHEN flag=0 AND '&dir'='asc'  THEN '1' ELSE value_high END value_high,
               CASE WHEN flag=0 AND '&dir'='desc' THEN '1' ELSE value_low  END value_low,
               a.description
        FROM   (SELECT extractvalue(column_value, '/ROW/TYP') typ,
                       extractvalue(column_value, '/ROW/NAME') NAME,
                       extractvalue(column_value, '/ROW/VTYPE') + 0 VTYPE,
                       extractvalue(column_value, '/ROW/VALUE') value_high,
                       extractvalue(column_value, '/ROW/FLAG')+0 flag,
                       extractvalue(column_value, '/ROW/OFE')+0 ofe,
                       regexp_replace(extractvalue(column_value, '/ROW/DESCRIPTION'), '\s+', ' ') description
                FROM   TABLE(XMLSEQUENCE(extract(high_env, '/ROWSET/ROW')))) a
        JOIN   (SELECT extractvalue(column_value, '/ROW/TYP') typ,
                       extractvalue(column_value, '/ROW/NAME') NAME,
                       extractvalue(column_value, '/ROW/VALUE') value_low
                FROM   TABLE(XMLSEQUENCE(extract(low_env, '/ROWSET/ROW')))) b
        USING  (typ, NAME)
        WHERE  nvl(value_high, '_') != nvl(value_low, '_') OR flag=0
        ORDER  BY typ,ofe &dir,nvl(regexp_substr(name,'^\d+$')+0,0) &dir,decode(substr(name,1,1),'_',1,0);
    TYPE t_changes IS TABLE OF c%ROWTYPE;
    changes t_changes;
    PROCEDURE wr(msg VARCHAR2) IS
    BEGIN
        dbms_lob.writeappend(sql_text, nvl(length(msg), 0) + 1, msg || chr(10));
    END;
BEGIN
    BEGIN
        SELECT *
        INTO   to_schema, buff
        FROM   (SELECT parsing_schema_name, sql_fulltext
                FROM   gv$sqlarea
                WHERE  sql_id = :V1
                AND    rownum < 2
                UNION ALL
                SELECT parsing_schema_name, sql_text
                FROM   all_sqlset_statements
                WHERE  sql_id = :v1
                AND    rownum < 2
                UNION ALL
                SELECT parsing_schema_name, sql_text
                FROM   dba_hist_sqlstat
                JOIN   dba_hist_sqltext
                USING  (sql_id)
                WHERE  sql_id = :v1
                AND    rownum < 2
                UNION ALL
                SELECT username, TO_CLOB(sql_text)
                FROM   gv$sql_monitor
                WHERE  sql_id = :v1
                AND    IS_FULL_SQLTEXT = 'Y'
                AND    rownum < 2)
        WHERE  rownum < 2;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            raise_application_error(-20001, 'Cannot find the SQL text for sql_id: ' || :v1);
    END;
    sql_text := 'explain plan set statement_id=''OFE_@dbcli_stmt_id@'' INTO SYS.PLAN_TABLE$ for ';
    buff := regexp_replace(buff,'^\s*explain.*?for\s*','',1,1,'i');
    dbms_lob.append(sql_text, buff);

    IF low_ofe IS NULL THEN
        raise_application_error(-20001, 'Please input the lower value of optimizer_features_enable!');
    END IF;

    IF high_ofe IS NULL THEN
        SELECT optimizer_feature_enable
        INTO   high_ofe
        FROM   (SELECT *
                FROM   v$session_fix_control
                ORDER  BY regexp_substr(optimizer_feature_enable, '\d+') + 0 DESC NULLS LAST,
                          optimizer_feature_enable DESC)
        WHERE  rownum < 2;
    END IF;

    DELETE SYS.PLAN_TABLE$ WHERE STATEMENT_ID IS NOT NULL;
    COMMIT;
    EXECUTE IMMEDIATE 'alter session set current_schema=SYS';
    EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || high_ofe || '''';
    high_env := dbms_xmlgen.getxmltype(qry);
    EXECUTE IMMEDIATE 'alter session set current_schema=' || to_schema;
    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', 'BASELINE_HIGH');
    COMMIT;

    EXECUTE IMMEDIATE 'alter session set STATISTICS_LEVEL=ALL current_schema=SYS';
    EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || low_ofe || '''';
    low_env := dbms_xmlgen.getxmltype(qry);
    EXECUTE IMMEDIATE 'alter session set current_schema=' || to_schema;
    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', 'BASELINE_LOW');
    COMMIT;

    IF '&dir'='desc' THEN
        EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || high_ofe || '''';
    END IF;

    OPEN c;
    LOOP
        FETCH c BULK COLLECT
            INTO changes LIMIT bulks;
        EXIT WHEN changes.count = 0;
        ofelist.extend;
        ofeold .extend;
        ofedesc.extend;
        counter := counter + 1;
        new_ofe := NULL;
        old_ofe := NULL;
        FOR i IN 1 .. changes.count LOOP
            IF changes(i).typ = 'ofe' THEN
                old_ofe := '"_fix_control"=''' || changes(i).name || ':' || changes(i).value_low || '''';
                new_ofe := '"_fix_control"=''' || changes(i).name || ':' || changes(i).value_high || '''';
                ofe_cnt := ofe_cnt + 1;
            ELSE
                IF changes(i).vtype = 2 THEN
                    changes(i).value_low := '''' || changes(i).value_low || '''';
                    changes(i).value_high := '''' || changes(i).value_high || '''';
                END IF;
                IF substr(changes(i).name,1,1)='_' THEN
                    changes(i).name := '"'||changes(i).name||'"';
                END IF;
                old_ofe := changes(i).name||'='||changes(i).value_low;
                new_ofe := changes(i).name||'='||changes(i).value_high;
                env_cnt := env_cnt + 1;
            END IF;

            ofelist(counter) := ofelist(counter) || new_ofe || chr(10);
            ofeold(counter)  := ofeold(counter)  || old_ofe || chr(10);
            IF length(ofedesc(counter) || changes(i).description) < 3800 THEN
                ofedesc(counter) := ofedesc(counter) || changes(i).description || chr(10);
            END IF;
        END LOOP;
        ofedesc(counter) := NVL(REPLACE(TRIM(ofedesc(counter)),CHR(9)),' ');

        IF '&dir'='desc' THEN
            tmp_ofe          := ofelist(counter);
            ofelist(counter) := ofeold(counter);
            ofeold(counter)  := tmp_ofe;
        END IF;

        IF new_ofe IS NOT NULL THEN
            old_ofe := ofeold(counter);
            BEGIN
                EXECUTE IMMEDIATE 'alter session set '|| ofelist(counter);
                EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', ''||counter);
                COMMIT;
            EXCEPTION WHEN OTHERS THEN
                errcount := errcount + 1;
                IF errcount <= 100 THEN
                    dbms_output.put_line('Unable to set '||replace(ofelist(ofelist.count),chr(10),' ')||' due to '||sqlerrm);
                END IF;
            END;
            IF :accu = 0 THEN
                BEGIN
                    EXECUTE IMMEDIATE 'alter session set '|| old_ofe;
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;
        END IF;
    END LOOP;
    CLOSE c;

    dbms_output.put_line(counter||' OFE differences are tested.');

    IF :accu = 1 THEN
        DELETE SYS.PLAN_TABLE$ WHERE STATEMENT_ID IN(
            SELECT /*+unnest*/ STATEMENT_ID 
            FROM (
                SELECT STATEMENT_ID,ID, DECODE(STATS, LAG(STATS) OVER(ORDER BY ID), 'Y', 'N') is_Delete
                FROM   (SELECT STATEMENT_ID,
                               NVL(regexp_substr(STATEMENT_ID, '\d+') + 0, 0) ID,
                               MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml, 1, 2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1),'')) ||
                               CHR(1) ||
                               MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml, 1, 2000)), '"plan_hash_2">(\d+)', 1, 1, 'i', 1),'')) ||
                               CHR(1) || MAX(q.cost) || CHR(1) || MAX(bytes) || CHR(1) || MAX(cardinality) keep(dense_rank FIRST ORDER BY id) || CHR(1) || SUM(nvl2(object_owner, cardinality, 0)) STATS
                        FROM   SYS.PLAN_TABLE$ q
                        WHERE  STATEMENT_ID NOT LIKE '%BASELINE_%'
                        GROUP  BY STATEMENT_ID
                        ORDER  BY ID))
            WHERE is_Delete='Y');
        COMMIT;
        FOR i in 1..counter LOOP
            BEGIN
                EXECUTE IMMEDIATE 'alter session set '|| ofeold(i);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
    END IF;

    MERGE INTO SYS.PLAN_TABLE$ A
    USING ( SELECT r,v1||chr(9)||v2 MEMO
            FROM  (SELECT rownum r,trim(chr(10) from column_value) v1 from table(ofelist)) A
            JOIN  (SELECT rownum r,trim(chr(10) from column_value) v2 from table(ofedesc)) B
            USING (r)) B
    ON   (B.r=regexp_substr(STATEMENT_ID, '\d+$') AND A.OTHER_XML IS NOT NULL)
    WHEN MATCHED THEN UPDATE SET A.REMARKS=B.MEMO;
    COMMIT;

    EXECUTE IMMEDIATE 'alter session set current_schema=' || curr;

    dbms_lob.createtemporary(sql_text, TRUE);
    fmt :='ALL ALLSTATS OUTLINE';
    IF dbms_db_version.version>10 THEN
        fmt := fmt||' ADVANCED';
    END IF;
    
    IF dbms_db_version.version>11 THEN
        fmt := fmt||' +REPORT +ADAPTIVE +METRICS';
    END IF;
    
    wr(chr(10));
    wr('SQL Text:');
    wr('=========');
    dbms_lob.append(sql_text, buff);
    wr(chr(10)||chr(10));
    FOR r IN (WITH plans AS
                  (SELECT STATEMENT_ID,
                          NVL(regexp_substr(STATEMENT_ID, '\d+') + 0, 0) ID,
                          MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash,
                          MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash_2">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash2
                   FROM   SYS.PLAN_TABLE$ q
                   WHERE  STATEMENT_ID IS NOT NULL
                   GROUP  BY STATEMENT_ID)
              SELECT MIN(STATEMENT_ID) id, 
                     MIN(ID) seq, 
                     plan_hash, 
                     plan_hash2
              FROM   PLANS
              GROUP  BY plan_hash, plan_hash2
              ORDER  BY seq) LOOP
        qry := 'PLAN_HASH_VALUE: ' || r.plan_hash || '    PLAN_HASH_VALUE_2: ' || r.plan_hash2;
        wr(qry);
        wr(lpad('=', length(qry), '='));
        FOR i IN (SELECT * FROM TABLE(dbms_xplan.display('SYS.PLAN_TABLE$', r.id, fmt))) LOOP
            IF trim(i.PLAN_TABLE_OUTPUT) IS NOT NULL AND i.PLAN_TABLE_OUTPUT NOT LIKE '%Plan hash value%' THEN
                wr(i.PLAN_TABLE_OUTPUT);
            END IF;
        END LOOP;
        wr(chr(10)||chr(10));
    END LOOP;

    :plans := sql_text;

    OPEN :cur FOR
        WITH plans AS
         (SELECT A.*,
                 dense_rank() over(order by grp, plan_hash,plan_hash2,cost, bytes, total_card, card) p,
                 regexp_substr(remarks,'[^'||CHR(9)||']+',1,1) d1,
                 regexp_substr(remarks,'[^'||CHR(9)||']+',1,2) d2
          FROM  (SELECT  STATEMENT_ID,
                         CASE WHEN STATEMENT_ID LIKE '%BASELINE_%' THEN 0 ELSE 1 END grp,
                         NVL(regexp_substr(STATEMENT_ID, '\d+') + 0, 0) ID,
                         MAX(ID) plan_lines,
                         MAX(remarks) remarks,
                         MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash,
                         MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash_2">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash2,
                         MAX(q.cost) cost,
                         MAX(bytes) bytes,
                         MAX(cardinality) keep(dense_rank FIRST ORDER BY id) card,
                         SUM(nvl2(object_owner, cardinality, 0)) total_card,
                         MAX(CASE WHEN &filter THEN 'Y' ELSE 'N' END) is_matched
                  FROM   SYS.PLAN_TABLE$ q
                  WHERE  STATEMENT_ID IS NOT NULL
                  GROUP  BY STATEMENT_ID) A),
        finals AS
         (SELECT a.*, 
                 decode(seq,1,listagg(d1,decode(bulks,1,chr(10),chr(10)||chr(10))) within group(ORDER BY seq) over(partition by p)) settings,
                 decode(seq,1,listagg(d2,decode(bulks,1,chr(10),chr(10)||chr(10))) within group(ORDER BY seq) over(partition by p)) description
          FROM   (SELECT a.*,
                         COUNT(DISTINCT STATEMENT_ID) over(PARTITION BY P) cnt,
                         row_number() over(PARTITION BY P ORDER BY id) seq
                  FROM   plans a) a
          WHERE  seq<=10)
        SELECT /*+ordered use_hash(b)*/
                 STATEMENT_ID,
                 is_matched matched,
                 plan_hash,
                 plan_hash2 phv2,
                 plan_lines     lines,
                 cnt            plans,
                 cost,
                 bytes,
                 card           "ROWS",
                 total_card,
                 settings "Top 10 Settings",
                 description "Top 10 Descriptions"
        FROM   finals a
        WHERE  seq=1
        ORDER  BY grp,decode(:accu,1,id,0),regexp_substr(statement_id,'\d+')+0,plan_hash,plan_hash2,cost,bytes,total_card,id;
    :msg := utl_lms.format_message('* Note: Run "ora plan <statement_id> -all" to query the detailed plan. ' || chr(10) ||
                                   '* Note: Totally %d options are tested, including %d fix controls and %d parameters. Please reconnect to reset all options to the defaults.',
                                   ofe_cnt + env_cnt,
                                   ofe_cnt,
                                   env_cnt);
EXCEPTION
    WHEN OTHERS THEN
        EXECUTE IMMEDIATE 'alter session set current_schema=' || curr;
        RAISE;
END;
/
SPOOL ofe_test_&v1..txt
PRO SQL Plan Summary:
PRO =================
print cur
SET TERMOUT OFF
print plans
SET TERMOUT ON FEED ON
SPOOL OFF
print msg