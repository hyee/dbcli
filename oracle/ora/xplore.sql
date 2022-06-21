/*[[
    Test the execution plan changes by adjusting the fix controls and session environments. Usage: @@NAME <sql_id>|"<sql_text>" [-ofe|-env|-s"<query>"] [-f"<plan_filter>"|-k"<keyword>]
    -env  : only test the parameters
    -ofe  : only test the fix controls
    -s    : customize the source. e.g.: -s"select bugno name,2 type,value,SYS.ODCIVARCHAR2LIST() avails,description from v$system_fix_control"
    -p    : specify plan table name. e.g.: -p"SYSTEM.PLAN_TABLE"

    Refer to: https://github.com/mauropagano/pathfinder

    Example:
    ========
    SQL> @@NAME 25jq1h90jjj13 -k"SINGLE" -ofe
    SQL Plan Summary:
    =================
     STATEMENT_ID   MATCHED  PLAN_HASH  PHV_FULL  LINES PLANS  COST   BYTES    ROWS  TOTAL_CARD          SETTINGS            DESCRIPTION
    --------------- ------- ---------- ---------- ----- ----- ------ -------- ------ ---------- --------------------------- ----------------------------------------------------------
    XPLORE_BASELINE N       2881531378 2779240993     2     1 700859 11097499 124691     124691
    XPLORE_1        N       2881531378 2779240993     2  1478 700859 11097499 124691     124691 "_fix_control"='10004943:0' enable removal of group by in subquery for create table
    XPLORE_807      Y       1009876827 1285040990     2     1   8763 11097499 124691     124691 "_fix_control"='27175987:0' disable partition pruning with non-deterministic functions


    Output is written to "D:\dbcli\cache\imtst\xplore_25jq1h90jjj13.txt".
    * Note: Run "ora plan <statement_id> -all" to query the detailed plan.
    * Note: Totally 1479 options are tested. Please reconnect to reset all options to the defaults.    
    --[[
        @ARGS  : 1
        &typ   : default={all} ofe={ofe} env={env}
        &filter: default={1=2} f={} k={operation||' '||options||' '||object_name like upper('%&0%')}
        &batch : default={1} batch={}
        &sep   : default={rowsep default} batch={rowsep - colsep |}
        &ptable: default={plan_table} p={}
        @CHECK_USER_FLAG: SYSDBA={1} DEFAULT={0}
        @CHECK_USER_X : {
            SYSDBA = {
                SELECT /*+no_expand use_hash(x y cbo_param)*/
                       x.ksppinm name,
                       x.ksppity TYPE,
                       y.ksppstvl VALUE,
                       avails,
                       x.ksppdesc description
                FROM   sys.x$ksppi x, sys.x$ksppcv y, (
                          SELECT /*+ no_merge */
                                 PNAME_QKSCESYROW NAME,
                                 CAST(COLLECT(VALUE_KSPVLD_VALUES ORDER BY 0+regexp_substr(VALUE_KSPVLD_VALUES,'^\d+') desc,VALUE_KSPVLD_VALUES DESC) AS  SYS.ODCIVARCHAR2LIST) AS  avails
                          FROM   sys.X$QKSCESYS a, sys.x$kspvld_values b
                          WHERE  PNAME_QKSCESYROW = NAME_KSPVLD_VALUES(+)
                          GROUP  BY PNAME_QKSCESYROW) cbo_param
                WHERE  x.indx = y.indx
                AND    BITAND(x.ksppiflg, 268435456) = 0
                AND    TRANSLATE(x.ksppinm, '_', '#') NOT LIKE '##%'
                AND    x.ksppinm = cbo_param.name(+)
                AND    x.inst_id = USERENV('Instance')
                AND    BITAND(x.ksppiflg / 256, 1) = 1
                AND    x.ksppity IN (1, 2, 3)
                AND   (cbo_param.name is not null or x.ksppinm IN (
                       '_bloom_filter_enabled',
                       '_bloom_folding_enabled',
                       '_bloom_minmax_enabled',
                       '_bloom_predicate_enabled',
                       '_bloom_predicate_pushdown_to_storage',
                       '_bloom_pruning_enabled',
                       '_bloom_pushing_max',
                       '_bloom_vector_elements',
                       '_cell_storidx_mode',
                       '_kcfis_cell_passthru_enabled',
                       '_kcfis_control1',
                       '_kcfis_control2',
                       '_kcfis_dump_corrupt_block',
                       '_kcfis_kept_in_cellfc_enabled',
                       '_kcfis_rdbms_blockio_enabled',
                       '_kcfis_storageidx_disabled',
                       '_projection_pushdown',
                       '_slave_mapping_enabled',
                       '_windowfunc_optimization_settings',
                       'cell_offload_processing',
                       'parallel_force_local'))
            }

            DEFAULT={
                SELECT /*+use_hash(a b)*/ a.NAME,a.TYPE,a.VALUE,SYS.ODCIVARCHAR2LIST() AVAILS,a.DESCRIPTION
                FROM  v$parameter a,v$sys_optimizer_env b
                WHERE ISSES_MODIFIABLE='TRUE'
                AND   a.name=b.name
            }
        }

        &SOURCE: {
            default={
                &CHECK_USER_X
                AND    '&typ' IN('all','env')
                UNION ALL
                SELECT '' || bugno, 2, '' || VALUE, SYS.ODCIVARCHAR2LIST(0, 1),description
                FROM   v$session_fix_control
                WHERE  session_id = userenv('sid')
                AND    '&typ' IN('all','ofe')
            }

            s={}
        }
    --]]
]]*/
set SQLTIMEOUT 7200 verify off feed off &sep
var cur refcursor;
var msg varchar2
var plans clob;
var file varchar2
PRO Processing, you can run 'show longops' in another session to monitor the progress.
DECLARE
    sq_id     VARCHAR2(32767) := '&v1';
    params    SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    descs     SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    avails    SYS.ODCIVARCHAR2LIST;
    prefix    VARCHAR2(10);
    NAME      VARCHAR2(128);
    VALUE     VARCHAR2(128);
    to_schema VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
    curr      VARCHAR2(128) := to_schema;
    fix       VARCHAR2(128);
    stmt      VARCHAR2(300);
    fmt       VARCHAR2(300);
    qry       VARCHAR2(4000);
    buff      CLOB;
    sql_text  CLOB;
    counter   PLS_INTEGER := 0;
    phase     PLS_INTEGER := 0;
    rindex    PLS_INTEGER;
    slno      PLS_INTEGER;
    plines    PLS_INTEGER := 0;
    changed   BOOLEAN;
    TYPE t_record IS RECORD(
        NAME        VARCHAR2(128),
        TYPE        NUMBER(1),
        VALUE       VARCHAR2(128),
        avails      SYS.ODCIVARCHAR2LIST,
        description VARCHAR2(4000));
    TYPE t_list IS TABLE OF t_record;
    lst       t_list;
    PROCEDURE alter_session(n VARCHAR2, v VARCHAR2, fix VARCHAR2 := NULL) IS
        val VARCHAR2(128) := v;
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
                    FROM   all_sqlset_statements
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
                raise_application_error(-20001, 'Cannot find the SQL text for sql_id: ' || sq_id);
        END;
    ELSE
        buff := sq_id;
        BEGIN
            EXECUTE IMMEDIATE 'BEGIN :1 := SYS.DBMS_SQLTUNE_UTIL0.SQLTEXT_TO_SQLID(:2);END;'
                USING OUT sq_id, buff;
        EXCEPTION WHEN OTHERS THEN
            sq_id := substr(buff,1,1000);
            select ora_hash(sq_id,1e8,1000) into sq_id from dual;
        END;
    END IF;
    buff     := regexp_replace(buff, '^\s*explain.*?for\s*', '', 1, 1, 'i');
    :file    := sq_id;
    sql_text := 'explain plan set statement_id=''XPLORE_@dbcli_stmt_id@'' INTO &ptable for ';
    dbms_lob.append(sql_text, buff);
    phase := 1;
    IF &CHECK_USER_FLAG=1 THEN
        EXECUTE IMMEDIATE 'alter session set current_schema=SYS';
    END IF;
    EXECUTE IMMEDIATE q'{
            SELECT *
            FROM   ( &SOURCE )
            ORDER  BY nvl2(regexp_substr(name,'^\d+$'),1,0),decode(substr(name,1,1),'_',1,0), DECODE(name, 'optimizer_features_enable', ' ', name)}' --
        BULK COLLECT
        INTO lst;
    EXECUTE IMMEDIATE 'alter session set STATISTICS_LEVEL=ALL current_schema=' || to_schema;
    DELETE &ptable;
    phase := 2;
    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', 'BASELINE');
    SELECT COUNT(1) INTO plines FROM &ptable;
    phase := 3;
    COMMIT;
    FOR i IN 1 .. lst.count LOOP
        NAME   := lst(i).name;
        fix    := NULL;
        prefix := NULL;
        IF SUBSTR(NAME, 1, 1) = '_' THEN
            NAME := '"' || NAME || '"';
        ELSIF NAME = 'optimizer_features_enable' THEN
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
                        WHEN lst(i).name = 'optimizer_index_caching' THEN
                            avails := SYS.ODCIVARCHAR2LIST(0, 12, 25, 50, 100);
                        WHEN lst(i).name = 'optimizer_dynamic_sampling' THEN
                            avails := SYS.ODCIVARCHAR2LIST(0, 2, 3, 4, 6, 8, 10, 11);
                        WHEN lst(i).name IN ('hash_area_size', 'sort_area_size') THEN
                            avails := SYS.ODCIVARCHAR2LIST(VALUE * 2, VALUE * 8, VALUE * 32);
                        WHEN lst(i).name IN ('db_file_multiblock_read_count', '_db_file_optimizer_read_count') THEN
                            avails := SYS.ODCIVARCHAR2LIST(4, 8, 16, 32, 64, 128);
                        WHEN lst(i).name = '_optimizer_max_permutations' THEN
                            avails := SYS.ODCIVARCHAR2LIST(100, 2000, 40000, 79999, 80000);
                        WHEN lst(i).name = '_optimizer_degree' THEN
                            avails := SYS.ODCIVARCHAR2LIST(1,4,16,32,64,128,256,512,1024);    
                        WHEN lst(i).name = '_sort_elimination_cost_ratio' THEN
                            avails := SYS.ODCIVARCHAR2LIST(0, 3, 6, 12, 25, 50, 100, 1000);
                        WHEN lst(i).name = '_optimizer_extended_stats_usage_control' THEN
                            avails := SYS.ODCIVARCHAR2LIST(255, 240, 224, 192);
                        WHEN lst(i).name = '_optimizer_fkr_index_cost_bias' THEN
                            avails := SYS.ODCIVARCHAR2LIST(2, 5, 10, 20);
                        WHEN lst(i).name = '_recursive_with_branch_iterations' THEN
                            avails := SYS.ODCIVARCHAR2LIST(1,7);
                        WHEN lst(i).name = '_windowfunc_optimization_settings' THEN
                            avails := SYS.ODCIVARCHAR2LIST(2,8,16,32,128,256,1024,8192);
                        ELSE
                            avails := SYS.ODCIVARCHAR2LIST();
                    END CASE;
                ELSE
                    IF fix = '16792882' THEN
                        avails := SYS.ODCIVARCHAR2LIST(1,2,3);
                    ELSIF fix = '20355502' THEN
                        avails := SYS.ODCIVARCHAR2LIST(1,2,3,4,5,6,7,8,9,10);
                    ELSIF fix IS NOT NULL THEN
                        avails := SYS.ODCIVARCHAR2LIST(0,1);
                    ELSIF upper(VALUE) IN ('ON', 'OFF') THEN
                        avails := SYS.ODCIVARCHAR2LIST('ON', 'OFF');
                    ELSIF upper(VALUE) IN ('TRUE', 'FALSE') THEN
                        avails := SYS.ODCIVARCHAR2LIST('TRUE', 'FALSE');
                    ELSIF upper(VALUE) IN ('ENABLE', 'DISABLE') THEN
                        avails := SYS.ODCIVARCHAR2LIST('ENABLE', 'DISABLE');
                    ELSE
                        avails := SYS.ODCIVARCHAR2LIST();
                    END IF;
            END CASE;
        END IF;
        changed := FALSE;
        FOR j IN 1 .. avails.count LOOP
            IF avails(j) IS NOT NULL AND UPPER(avails(j)) != NVL(UPPER(VALUE), 'x') THEN
                BEGIN
                    alter_session(NAME, avails(j), fix);
                    changed := TRUE;
                    EXECUTE IMMEDIATE REPLACE(sql_text, '@dbcli_stmt_id@', prefix || (counter + 1));
                    /*
                    UPDATE &ptable
                    SET    REMARKS=substr(stmt, 19)
                    WHERE  STATEMENT_ID LIKE '%\_'||prefix || (counter + 1) escape '\';
                    */
                    COMMIT;
                    params.extend;
                    descs.extend;
                    counter         := counter + 1;
                    params(counter) := substr(stmt, 19);
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
        SYS.DBMS_APPLICATION_INFO.set_session_longops(rindex      => rindex, 
                                                      slno        => slno,
                                                      op_name     => 'XPLORE '||sq_id,
                                                      sofar       => i, 
                                                      totalwork   => lst.count,
                                                      target_desc => ' ',
                                                      units       => 'options');
    END LOOP;

    UPDATE &ptable
    SET    REMARKS=(select trim(chr(10) from v) from (SELECT rownum r,column_value v from table(params)) where r=regexp_substr(STATEMENT_ID, '\d+$'))||chr(9)||
                   (select trim(chr(10) from v) from (SELECT rownum r,column_value v from table(descs)) where r=regexp_substr(STATEMENT_ID, '\d+$'))
    WHERE  regexp_like(STATEMENT_ID, '\d+$')
    AND    nvl(id,0)=0;
    COMMIT; 

    fmt := 'ALL ALLSTATS OUTLINE';
    IF dbms_db_version.version > 10 THEN
        fmt := fmt || ' ADVANCED';
    END IF;

    IF dbms_db_version.version > 11 THEN
        fmt := fmt || ' +REPORT +ADAPTIVE +METRICS';
    END IF;

    dbms_lob.createtemporary(sql_text, TRUE);
    wr(chr(10));
    wr('SQL Text:');
    wr('=========');
    dbms_lob.append(sql_text, buff);
    wr(chr(10) || chr(10));
    FOR r IN (WITH plans AS
                   (SELECT STATEMENT_ID,
                          NVL(regexp_substr(STATEMENT_ID, '\d+$') + 0, 0) ID,
                          MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml, 1, 2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash,
                          MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml, 1, 2000)),'"plan_hash_2">(\d+)',1,1,'i',1),'')) + 0 plan_hash2
                   FROM   &ptable q
                   GROUP  BY STATEMENT_ID)
                  SELECT MIN(STATEMENT_ID) id, MIN(ID) seq, plan_hash, plan_hash2
                  FROM   PLANS
                  GROUP  BY plan_hash, plan_hash2
                  ORDER  BY seq) LOOP
        qry := 'PLAN_HASH_VALUE: ' || r.plan_hash || '    PLAN_HASH_VALUE_FULL: ' || r.plan_hash2;
        wr(qry);
        wr(lpad('=', length(qry), '='));
        FOR i IN (SELECT * FROM TABLE(dbms_xplan.display('&ptable', r.id, fmt))) LOOP
            IF trim(i.PLAN_TABLE_OUTPUT) IS NOT NULL AND i.PLAN_TABLE_OUTPUT NOT LIKE '%Plan hash value%' THEN
                wr(i.PLAN_TABLE_OUTPUT);
            END IF;
        END LOOP;
        wr(chr(10) || chr(10));
    END LOOP;

    :plans := sql_text;

    OPEN :cur FOR
        WITH plans AS 
         (SELECT A.*,
                 dense_rank() over(order by grp, plan_hash, cost, bytes, total_card, card) p,
                 regexp_substr(remarks,'[^'||CHR(9)||']+',1,1) d1,
                 regexp_substr(remarks,'[^'||CHR(9)||']+',1,2) d2
           FROM  (SELECT STATEMENT_ID,
                         CASE
                             WHEN STATEMENT_ID LIKE '%BASELINE' THEN
                              0
                             WHEN STATEMENT_ID LIKE '%OFE%' THEN
                              1
                             ELSE
                              2
                         END grp,
                         MAX(remarks) remarks,
                         NVL(regexp_substr(STATEMENT_ID, '\d+$') + 0, 0) ID,
                         MAX(ID) plan_lines,
                         MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml, 1, 2000)), '"plan_hash">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash,
                         MAX(nvl2(other_xml,regexp_substr(to_char(substr(other_xml, 1, 2000)), '"plan_hash_2">(\d+)', 1, 1, 'i', 1),'')) + 0 plan_hash2,
                         MAX(q.cost) cost,
                         MAX(bytes) bytes,
                         MAX(cardinality) keep(dense_rank FIRST ORDER BY id) card,
                         SUM(nvl2(object_owner, cardinality, 0)) total_card,
                         MAX(CASE WHEN &filter THEN 'Y' ELSE 'N' END) is_matched
                  FROM   &ptable q
                  GROUP  BY STATEMENT_ID) a),
        finals AS
         (SELECT a.*, 
                 decode(seq,1,listagg(d1,chr(10)) within group(ORDER BY seq) over(partition by p)) settings,
                 decode(seq,1,listagg(d2,chr(10)) within group(ORDER BY seq) over(partition by p)) description
          FROM   (SELECT a.*,
                         COUNT(DISTINCT STATEMENT_ID) over(PARTITION BY P) cnt,
                         row_number() over(PARTITION BY P ORDER BY id) seq
                  FROM   plans a) a
          WHERE  seq<=10)
        SELECT /*+ordered use_hash(b)*/
                 STATEMENT_ID,
                 is_matched matched,
                 plan_hash,
                 plan_hash2,
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
        ORDER  BY grp, matched DESC,plan_hash,plan_hash2,cost,bytes,total_card,id;
    :msg := utl_lms.format_message('* Note: Run "ora plan <statement_id> -all" to query the detailed plan. ' || chr(10) ||
                                   '* Note: Totally %d options are tested. Please reconnect to reset all options to the defaults.',
                                   counter);
    EXECUTE IMMEDIATE 'alter session set current_schema=' || curr;
EXCEPTION
    WHEN OTHERS THEN
        EXECUTE IMMEDIATE 'alter session set current_schema=' || curr;
        IF phase = 2 THEN
            raise_application_error(-20001, 'Unable to explain ' || sq_id || ': ' || SQLERRM);
        ELSE
            RAISE;
        END IF;
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