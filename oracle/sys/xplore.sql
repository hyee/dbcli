/*[[
    Test the execution plan changes by adjusting the fix controls and session environments. Usage: @@NAME <sql_id>|<sql_text> [-ofe|-env] [-f"<plan_filter>"]
    -env  : only test the parameters
    -ofe  : only test the fix controls

    Refer to: https://github.com/mauropagano/pathfinder
    --[[
        @ARGS  : 1
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
var file varchar2
DECLARE
    sq_id VARCHAR2(32767) := '&v1';
    params  SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    descs   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    TYPE t_record IS RECORD(
        NAME        VARCHAR2(128),
        TYPE        NUMBER(1),
        VALUE       VARCHAR2(128),
        avails      SYS.ODCIVARCHAR2LIST,
        description VARCHAR2(4000));
    TYPE t_list IS TABLE OF t_record;
    lst       t_list;
    prefix    VARCHAR2(10);
    NAME      VARCHAR2(128);
    VALUE     VARCHAR2(128);
    to_schema VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
    curr      VARCHAR2(128) := to_schema;
    buff      CLOB;
    sql_text  CLOB;
    avails    SYS.ODCIVARCHAR2LIST;
    counter   PLS_INTEGER := 0;
    changed   BOOLEAN;
    fix       VARCHAR2(128);
    stmt VARCHAR2(300);
    fmt       VARCHAR2(300);
    qry       VARCHAR2(4000);
    PROCEDURE alter_session(n VARCHAR2, v VARCHAR2, fix VARCHAR2 := NULL) IS
        val  VARCHAR2(128) := v;
    BEGIN
        IF fix IS NOT NULL THEN
            val := '''' || fix || ':' || val || '''';
        ELSIF NOT regexp_like(val, '^[[:alnum:]]+$') THEN
            val := '''' || val || '''';
        ELSIF val IS NULL THEN
            val := '''''';
        END IF;
        stmt := utl_lms.format_message('alter session set %s=%s', n, val);
        EXECUTE IMMEDIATE stmt;
    END;

    PROCEDURE wr(msg VARCHAR2) IS
    BEGIN
        dbms_lob.writeappend(sql_text, nvl(length(msg), 0) + 1, msg || chr(10));
    END;
BEGIN
    EXECUTE IMMEDIATE 'alter session set STATISTICS_LEVEL=ALL current_schema=SYS';

    IF instr(sq_id, ' ') = 0 THEN
        BEGIN
            SELECT *
            INTO   to_schema, buff
            FROM   (SELECT parsing_schema_name, sql_fulltext
                    FROM   gv$sqlarea
                    WHERE  sql_id = sq_id
                    AND    rownum < 2
                    UNION ALL
                    SELECT parsing_schema_name, sql_text
                    FROM   dba_hist_sqlstat
                    JOIN   dba_hist_sqltext
                    USING  (sql_id)
                    WHERE  sql_id = sq_id
                    AND    rownum < 2
                    UNION ALL
                    SELECT username, TO_CLOB(sql_text)
                    FROM   gv$sql_monitor
                    WHERE  sql_id = sq_id
                    AND    IS_FULL_SQLTEXT = 'Y'
                    AND    rownum < 2)
            WHERE  rownum < 2;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'Cannot find the SQL text for sql_id: ' || :v1);
        END;
    ELSE
        buff := sq_id;
        EXECUTE IMMEDIATE 'BEGIN :1 := SYS.DBMS_SQLTUNE_UTIL0.SQLTEXT_TO_SQLID(:2);END;' USING OUT sq_id,buff;
    END IF;
    buff := regexp_replace(buff,'^\s*explain.*?for\s*','',1,1,'i');
    :file := sq_id;
    sql_text := 'explain plan set statement_id=''XPLORE_@dbcli_stmt_id@'' for ';
    dbms_lob.append(sql_text, buff);

    EXECUTE IMMEDIATE q'{
        WITH cbo_param AS
         (SELECT /*+ materialize */
                 pname_qksceserow NAME,
                 CAST(COLLECT(VALUE_KSPVLD_VALUES ORDER BY 0+regexp_substr(VALUE_KSPVLD_VALUES,'\d+'),VALUE_KSPVLD_VALUES) AS  SYS.ODCIVARCHAR2LIST) AS  avails
          FROM   x$qksceses a, x$kspvld_values b
          WHERE  sid_qksceserow = SYS_CONTEXT('USERENV', 'SID')
          AND    pname_qksceserow = NAME_KSPVLD_VALUES(+)
          GROUP  BY pname_qksceserow)
        SELECT *
        FROM   (SELECT x.ksppinm name,
                       x.ksppity TYPE,
                       y.ksppstvl VALUE,
                       avails,
                       x.ksppdesc description
                FROM   x$ksppi x, x$ksppcv y, cbo_param
                WHERE  x.indx = y.indx
                AND    BITAND(x.ksppiflg, 268435456) = 0
                AND    TRANSLATE(x.ksppinm, '_', '#') NOT LIKE '##%'
                AND    x.ksppinm = cbo_param.name
                AND    x.inst_id = USERENV('Instance')
                AND    BITAND(x.ksppiflg / 256, 1) = 1
                AND    x.ksppity IN (1, 2, 3)
                AND    '&typ' IN('all','env')
                UNION ALL
                SELECT '' || bugno, 2, '' || VALUE, SYS.ODCIVARCHAR2LIST(0, 1),description
                FROM   v$session_fix_control
                WHERE  session_id = userenv('sid')
                AND    '&typ' IN('all','ofe'))
        ORDER  BY nvl2(regexp_substr(name,'^\d+$'),1,0), DECODE(name, 'optimizer_features_enable', ' ', name)}' --
        BULK COLLECT
        INTO lst;
    EXECUTE IMMEDIATE 'alter session set current_schema=' || to_schema;
    EXECUTE IMMEDIATE 'delete plan_table';

    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', 'BASELINE');

    COMMIT;
    FOR i IN 1 .. lst.count LOOP
        NAME := lst(i).name;
        fix  := NULL;
        prefix := NULL;
        IF SUBSTR(NAME, 1, 1) = '_' THEN
            NAME := '"' || NAME || '"';
        ELSIF name = 'optimizer_features_enable' THEN
            prefix := 'OFE_';
        ELSIF regexp_like(NAME, '^\d+$') THEN
            fix  := NAME;
            NAME := '"_fix_control"';
        END IF;
        avails := lst(i).avails;
        VALUE  := lst(i).value;
        IF avails IS NULL OR avails.count = 0 THEN
            CASE lst(i).type
                WHEN 1 THEN
                    avails := SYS.ODCIVARCHAR2LIST('TRUE', 'FALSE');
                WHEN 3 THEN
                    CASE
                        WHEN lst(i).name = 'optimizer_index_cost_adj' THEN
                            avails := SYS.ODCIVARCHAR2LIST(1, 10, 25, 50, 100, 200, 400, 1000, 10000);
                        WHEN lst(i).name = 'optimizer_index_cost_adj' THEN
                            avails := SYS.ODCIVARCHAR2LIST(0, 12, 25, 50, 100);
                        WHEN lst(i).name = 'optimizer_dynamic_sampling' THEN
                            avails := SYS.ODCIVARCHAR2LIST(0, 2, 3, 4, 6, 8, 10, 11);
                        WHEN lst(i).name IN ('hash_area_size', 'sort_area_size') THEN
                            avails := SYS.ODCIVARCHAR2LIST(VALUE * 2, VALUE * 8, VALUE * 32);
                        WHEN lst(i).name IN ('db_file_multiblock_read_count', '_db_file_optimizer_read_count') THEN
                            avails := SYS.ODCIVARCHAR2LIST(4, 8, 16, 32, 64, 128);
                        WHEN lst(i).name = '_optimizer_max_permutations' THEN
                            avails := SYS.ODCIVARCHAR2LIST(100, 2000, 40000, 79999, 80000);
                        WHEN lst(i).name = '_sort_elimination_cost_ratio' THEN
                            avails := SYS.ODCIVARCHAR2LIST(0, 3, 6, 12, 25, 50, 100, 1000);
                        WHEN lst(i).name = '_optimizer_extended_stats_usage_control' THEN
                            avails := SYS.ODCIVARCHAR2LIST(255, 240, 224, 192);
                        WHEN lst(i).name = '_optimizer_fkr_index_cost_bias' THEN
                            avails := SYS.ODCIVARCHAR2LIST(2, 5, 10, 20);
                        ELSE
                            avails := SYS.ODCIVARCHAR2LIST();
                    END CASE;
                ELSE
                    avails := SYS.ODCIVARCHAR2LIST();
            END CASE;
        END IF;
        changed := FALSE;
        FOR j IN 1 .. avails.count LOOP
            IF avails(j) IS NOT NULL AND UPPER(avails(j)) != NVL(UPPER(VALUE), 'x') THEN
                BEGIN
                    alter_session(NAME, avails(j), fix);
                    changed := TRUE;
                    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', prefix||(counter + 1));
                    counter := counter + 1;
                    params.extend;
                    descs.extend;
                    params(counter) := substr(stmt,19);
                    descs(counter)  := lst(i).description;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL; --dbms_output.put_line(SQLERRM||':'||stmt);
                END;
            END IF;
        END LOOP;
        IF changed THEN
            alter_session(NAME, VALUE, fix);
        END IF;
    END LOOP;

    fmt :='ALL ALLSTATS OUTLINE';
    IF dbms_db_version.version>10 THEN
        fmt := fmt||' ADVANCED';
    END IF;
    
    IF dbms_db_version.version>11 THEN
        fmt := fmt||' +REPORT +ADAPTIVE +METRICS';
    END IF;

    dbms_lob.createtemporary(sql_text, TRUE);
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
                 CASE WHEN STATEMENT_ID LIKE '%BASELINE' THEN 0 WHEN STATEMENT_ID LIKE '%OFE%' THEN 1 ELSE 2 END grp,
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
        LEFT   JOIN (SELECT rownum id, trim(chr(10) from column_value) settings FROM TABLE(params)) b
        USING  (id)
        LEFT   JOIN (SELECT rownum id, trim(chr(10) from column_value) description FROM TABLE(descs)) c
        USING  (id)
        ORDER  BY grp, id;
    :msg := utl_lms.format_message('* Note: Run "ora plan <statement_id> -all" to query the detailed plan. ' || chr(10) ||
                                   '* Note: Totally %d options are tested. Please reconnect to reset all options to the defaults.',
                                   counter);
    EXECUTE IMMEDIATE 'alter session set current_schema=' || curr;
EXCEPTION
    WHEN OTHERS THEN
        EXECUTE IMMEDIATE 'alter session set current_schema=' || curr;
        RAISE;    
END;
/
SPOOL xplore_&file..txt
PRO SQL Plan Summary:
PRO =================
print cur
SET TERMOUT OFF
print plans
SET TERMOUT ON FEED ON
SPOOL OFF
print msg