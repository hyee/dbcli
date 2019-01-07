/*[[Test the execution plan changes by adjusting the new fix controls and session environments. Usage: @@NAME <sql_id> <lower_OFT> [high_OFE] [-f"<plan_filter>"] [-batch"<number>"] [-ofe|-env]
    -batch: number of options to be tested for each batch
    -env  : only test the parameters
    -ofe  : only test the fix controls
    --[[
        &typ   : default={all} ofe={ofe} env={env}
        &filter: default={1=2} f={}
        &batch : default={1} batch={}
        &sep   : default={rowsep default} batch={rowsep - colsep |}
    --]]
]]*/
set verify off feed off &sep
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
    org_ofes  VARCHAR2(4000);
    new_ofe   VARCHAR2(32767);
    ofelist   ODCIVARCHAR2LIST := ODCIVARCHAR2LIST();
    ofedesc   ODCIVARCHAR2LIST := ODCIVARCHAR2LIST();
    to_schema VARCHAR2(128);
    fmt       VARCHAR2(300);
    curr      VARCHAR2(128) := sys_context('userenv', 'current_schema');
    qry       VARCHAR2(4000) := q'{
        SELECT 'ofe' typ,''||bugno name,''||value value,3 vtype,DESCRIPTION
        FROM   v$session_fix_control
        WHERE  SESSION_ID=userenv('sid')
        AND    '&typ' IN('all','ofe')    
        union all
        SELECT 'env',pi.ksppinm, kc.PVALUE_QKSCESEROW, ksppity,ksppdesc
        FROM   x$ksppi pi ,x$ksppcv cv,X$QKSCESES kc
        WHERE  pi.indx=cv.indx
        AND    pi.ksppinm=kc.PNAME_QKSCESEROW
        AND    kc.SID_QKSCESEROW = userenv('sid')
        AND    ksppity IN (1, 2, 3)
        AND    LENGTH(kc.PVALUE_QKSCESEROW)<=20
        AND    bitand(ksppiflg / 256, 1)=1
        AND    pi.ksppinm!='optimizer_features_enable'
        AND    '&typ' IN('all','env')
        ORDER  BY 1,2}';
    CURSOR c IS
        SELECT /*+ordered use_hash(b)*/ *
        FROM   (SELECT extractvalue(column_value, '/ROW/TYP') typ,
                       extractvalue(column_value, '/ROW/NAME') NAME,
                       extractvalue(column_value, '/ROW/VTYPE') + 0 VTYPE,
                       extractvalue(column_value, '/ROW/VALUE') value_high,
                       regexp_replace(extractvalue(column_value, '/ROW/DESCRIPTION'), '\s+', ' ') description
                FROM   TABLE(XMLSEQUENCE(extract(high_env, '/ROWSET/ROW')))) a
        JOIN   (SELECT extractvalue(column_value, '/ROW/TYP') typ,
                       extractvalue(column_value, '/ROW/NAME') NAME,
                       extractvalue(column_value, '/ROW/VTYPE') + 0 VTYPE,
                       extractvalue(column_value, '/ROW/VALUE') value_low
                FROM   TABLE(XMLSEQUENCE(extract(low_env, '/ROWSET/ROW')))) b
        USING  (typ, NAME, vtype)
        WHERE  nvl(value_high, '_') != nvl(value_low, '_');
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
    sql_text := 'explain plan set statement_id=''OFE_@dbcli_stmt_id@'' for ';
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
    EXECUTE IMMEDIATE 'alter session set current_schema=' || to_schema;
    DELETE plan_table;
    --DBMS_OUTPUT.PUT_LINE(replace(sql_text,'@dbcli_stmt_id@','BASELINE'));

    SELECT REPLACE(regexp_replace(nvl(MAX(VALUE), '3834770:1'), '([^,]+)', '''\1'''), ' ')
    INTO   org_ofes
    FROM   v$parameter
    WHERE  NAME = '_fix_control';

    EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || low_ofe || '''';
    low_env := dbms_xmlgen.getxmltype(qry);
    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', 'BASELINE_LOW');
    COMMIT;

    EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || high_ofe || '''';
    high_env := dbms_xmlgen.getxmltype(qry);
    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', 'BASELINE_HIGH');
    COMMIT;

    OPEN c;
    LOOP
        FETCH c BULK COLLECT
            INTO changes LIMIT bulks;
        EXIT WHEN changes.count = 0;
        ofelist.extend;
        ofedesc.extend;
        new_ofe := NULL;
        FOR i IN 1 .. changes.count LOOP
            IF changes(i).typ = 'ofe' THEN
                IF nvl(instr(org_ofes, changes(i).name || ':'), 0) = 0 THEN
                    new_ofe := new_ofe || ',''' || changes(i).name || ':' || changes(i).value_low || '''';
                    ofe_cnt := ofe_cnt + 1;
                    ofelist(ofelist.count) := ofelist(ofelist.count) || changes(i).name || ':' || changes(i).value_low ||
                                              chr(10);
                END IF;
            ELSE
                IF changes(i).vtype = 2 THEN
                    changes(i).value_low := '''' || changes(i).value_low || '''';
                    changes(i).value_high := '''' || changes(i).value_high || '''';
                END IF;
                EXECUTE IMMEDIATE 'alter session set "' || changes(i).name || '"=' || changes(i).value_low;
                env_cnt := env_cnt + 1;
                ofelist(ofelist.count) := ofelist(ofelist.count) || changes(i).name || ' = ' || changes(i).value_low ||
                                          chr(10);
            END IF;
        
            IF length(ofedesc(ofedesc.count) || changes(i).description) < 3999 THEN
                ofedesc(ofedesc.count) := ofedesc(ofedesc.count) || changes(i).description || chr(10);
            END IF;
        END LOOP;
    
        ofelist(ofelist.count) := TRIM(TRIM(',' FROM ofelist(ofelist.count)));
        ofedesc(ofedesc.count) := TRIM(ofedesc(ofedesc.count));
    
        IF new_ofe IS NOT NULL THEN
            EXECUTE IMMEDIATE 'alter session set "_fix_control"=' || org_ofes || new_ofe;
        END IF;
    
        EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', ofelist.count);
        COMMIT;
    
        IF new_ofe IS NOT NULL THEN
            EXECUTE IMMEDIATE 'alter session set "_fix_control"=' || org_ofes;
        END IF;
        FOR i IN 1 .. changes.count LOOP
            IF changes(i).typ != 'ofe' THEN
                EXECUTE IMMEDIATE 'alter session set "' || changes(i).name || '"=' || changes(i).value_high;
            END IF;
        END LOOP;
    END LOOP;
    CLOSE c;
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
                          MAX(decode(id, 1, regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1))) + 0 plan_hash,
                          MAX(decode(id, 1, regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash_full">(\d+)', 1, 1, 'i', 1))) + 0 plan_hash_full
                   FROM   PLAN_TABLE q
                   GROUP  BY STATEMENT_ID)
                  SELECT MIN(STATEMENT_ID) id, MIN(ID) seq, plan_hash, plan_hash_full
                  FROM   PLANS
                  GROUP  BY plan_hash, plan_hash_full
                  ORDER  BY seq) LOOP
        qry := 'PLAN_HASH_VALUE: ' || r.plan_hash || '    PLAN_HASH_VALUE_FULL: ' || r.plan_hash_full;
        wr(qry);
        wr(lpad('=', length(qry), '='));
        FOR i IN (SELECT * FROM TABLE(dbms_xplan.display('plan_table', NULL, fmt, 'statement_id=''' || r.id || ''''))) LOOP
            IF nvl(i.PLAN_TABLE_OUTPUT,'X') not like '%Plan hash value%' THEN
                wr(i.PLAN_TABLE_OUTPUT);
            END IF;
        END LOOP;
        wr(chr(10)||chr(10));
    END LOOP;

    :plans := sql_text;

    OPEN :cur FOR
        WITH plans AS
         (SELECT STATEMENT_ID,
                 CASE WHEN STATEMENT_ID LIKE '%BASELINE_LOW' THEN 0 ELSE 1 END grp,
                 NVL(regexp_substr(STATEMENT_ID, '\d+') + 0, 0) ID,
                 MAX(ID) plan_lines,
                 MAX(decode(id, 1, regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1))) + 0 plan_hash,
                 MAX(decode(id, 1, regexp_substr(to_char(substr(other_xml,1,2000)), '"plan_hash_full">(\d+)', 1, 1, 'i', 1))) + 0 plan_hash_full,
                 MAX(q.cost) cost,
                 MAX(bytes) bytes,
                 MAX(cardinality) keep(dense_rank FIRST ORDER BY id) card,
                 SUM(nvl2(object_owner, cardinality, 0)) total_card,
                 MAX(CASE WHEN &filter THEN 'Y' ELSE 'N' END) is_matched
          FROM   PLAN_TABLE q
          GROUP  BY STATEMENT_ID),
        finals AS
         (SELECT *
          FROM   (SELECT a.*,
                         COUNT(DISTINCT STATEMENT_ID) over(PARTITION BY grp, plan_hash, plan_hash_full, cost, bytes, total_card, card) cnt,
                         MIN(id) over(PARTITION BY grp, plan_hash, cost, bytes, total_card, card) m_id
                  FROM   plans a)
          WHERE  id = m_id)
        SELECT /*+ordered use_hash(b)*/
                 STATEMENT_ID,
                 plan_hash,
                 plan_hash_full phv_full,
                 plan_lines     lines,
                 cnt            plans,
                 is_matched,
                 cost,
                 bytes,
                 card           "ROWS",
                 total_card,
                 b.settings,
                 description
        FROM   finals a
        LEFT   JOIN (SELECT rownum id, column_value settings FROM TABLE(ofelist)) b
        USING  (id)
        LEFT   JOIN (SELECT rownum id, column_value description FROM TABLE(ofedesc)) c
        USING  (id)
        ORDER  BY grp, id;
    :msg := utl_lms.format_message('* Note: Run "ora plan <statement_id>" to query the detailed plan. ' || chr(10) ||
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