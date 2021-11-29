/*[[
    Show SQL Share cursors (gv$sql_shared_cursor). Usage: @@NAME [-s"<sql_id>"] [-i"<inst_id>"]

    Sample Outputs:
    ===============
    SQL> @@NAME
       SQL_ID     CHILDS VERS   ELA     AVG_ELA |  MISMATCH_REASONS
    ------------- ------ ---- -------- -------- - ---------------------------------------------------------------------------------------------------------------------------
    6dhs74d4au081    190  189   25.84s    9.88s |  PQ_SLAVE_MISMATCH      = 173 | OPTIMIZER_MISMATCH     = 107 | USE_FEEDBACK_STATS     =   8 | TOP_LEVEL_RPI_CURSOR   =   5
    1q1spprb9m55h    134  134   56.56m   19.71s |  OPTIMIZER_MISMATCH     = 113 | PQ_SLAVE_MISMATCH      =  63 | DIFF_CALL_DURN         =  12 | MULTI_PX_MISMATCH      =   6
    acmvv4fhdc9zh    104  102   58.89s   2.50ms |  OPTIMIZER_MISMATCH     = 101 | OPTIMIZER_MODE_MISMATCH=  69 | LANGUAGE_MISMATCH      =  20 | PURGED_CURSOR          =   4
    grwydz59pu6mc     99   96   50.44s 295.64us |  OPTIMIZER_MISMATCH     =  93 | PURGED_CURSOR          =   4 | STATS_ROW_MISMATCH     =   1
    cb21bacyh3c7d     94   94    3.42m   6.37ms |  OPTIMIZER_MISMATCH     =  90 | OPTIMIZER_MODE_MISMATCH=  65 | LANGUAGE_MISMATCH      =  15
    0ctk7jpux5chm     84   84   22.27s  23.74ms |  OPTIMIZER_MISMATCH     =  67 | USE_FEEDBACK_STATS     =  67 | BIND_EQUIV_FAILURE     =  17 | LOAD_OPTIMIZER_STATS   =   4
    6yxprcw0ax14g     83   83   18.92s    1.76s |  OPTIMIZER_MISMATCH     =  68 | PQ_SLAVE_MISMATCH      =  40 | TOP_LEVEL_RPI_CURSOR   =  20 | USE_FEEDBACK_STATS     =  13
    87gaftwrm2h68     81   78    1.21m   1.17ms |  OPTIMIZER_MISMATCH     =  78 | PURGED_CURSOR          =   3
    
    SQL> @@NAME -s"6dhs74d4au081"
       SQL_ID     CHILDS VERS  ELA   AVG_ELA |      MISMATCH_REASONS
    ------------- ------ ---- ------ ------- - --------------------------
    6dhs74d4au081    190  189 25.84s   9.88s |  PQ_SLAVE_MISMATCH   = 173
                                                OPTIMIZER_MISMATCH  = 107
                                                USE_FEEDBACK_STATS  =   8
                                                TOP_LEVEL_RPI_CURSOR=   5

    --[[
        @ALIAS  : nonshare
        &sql_id : default={} s={WHERE sql_id='&0'}
        &cnt    : default={AND CNT_>1} s={AND 1=1}
        &sep    : default={' | '} s={chr(10)||' '}
        &inst1  : default={:instance} i={0+'&0'}
    --]]

]]*/

col ela,avg_ela for usmhd2
col mem for kmg2
set feed off
SELECT *
FROM   (SELECT sql_id, mod(SUM(DISTINCT childs),1e6) childs,mod(SUM(DISTINCT vers),1e6) vers,
               SUM(distinct ela) ela,
               SUM(distinct avg_ela) avg_ela,
               SUM(distinct mem) mem,
               '$HEADCOLOR$|$NOR$' "|",
               ' '||listagg(rpad(c,l)||'='||lpad(val,4),&sep) WITHIN GROUP(ORDER BY val desc,c) " MISMATCH_REASONS",
               MAX(sql_text) sql_text
        FROM   (SELECT sql_id,
                       MAX(sql_text) sql_text, c, 
                       SUM(DISTINCT childs) childs,
                       SUM(distinct vers) vers,
                       SUM(distinct ela) ela,
                       SUM(distinct avg_ela) avg_ela,
                       SUM(distinct mem) mem,
                       SUM(val) val,
                       MAX(length(c)) over() l
                FROM   TABLE(gv$(CURSOR(
                           SELECT /*+ordered DYNAMIC_SAMPLING(5)*/ 
                                  sql_id,
                                  USERENV('instance')*1e6+COUNT(1) childs,
                                  USERENV('instance')*1e6+SUM(loaded_versions) vers,
                                  substr(TRIM(regexp_replace(replace(MAX(b.sql_text),chr(0)), '[' || chr(1) || chr(10) || chr(13) || chr(9) || ' ]+', ' ')), 1, 200) sql_text,
                                  SUM(elapsed_time) ela,
                                  SUM(SHARABLE_MEM+TYPECHECK_MEM) mem,
                                  round(SUM(elapsed_time)/greatest(SUM(executions),1),3) avg_ela,
                                  SUM(decode(UNBOUND_CURSOR, 'Y', 1, 0)) UNBOUND_CURSOR,
                                  SUM(decode(SQL_TYPE_MISMATCH, 'Y', 1, 0)) SQL_TYPE_MISMATCH,
                                  SUM(decode(OPTIMIZER_MISMATCH, 'Y', 1, 0)) OPTIMIZER_MISMATCH,
                                  SUM(decode(OUTLINE_MISMATCH, 'Y', 1, 0)) OUTLINE_MISMATCH,
                                  SUM(decode(STATS_ROW_MISMATCH, 'Y', 1, 0)) STATS_ROW_MISMATCH,
                                  SUM(decode(LITERAL_MISMATCH, 'Y', 1, 0)) LITERAL_MISMATCH,
                                  SUM(decode(FORCE_HARD_PARSE, 'Y', 1, 0)) FORCE_HARD_PARSE,
                                  SUM(decode(EXPLAIN_PLAN_CURSOR, 'Y', 1, 0)) EXPLAIN_PLAN_CURSOR,
                                  SUM(decode(BUFFERED_DML_MISMATCH, 'Y', 1, 0)) BUFFERED_DML_MISMATCH,
                                  SUM(decode(PDML_ENV_MISMATCH, 'Y', 1, 0)) PDML_ENV_MISMATCH,
                                  SUM(decode(INST_DRTLD_MISMATCH, 'Y', 1, 0)) INST_DRTLD_MISMATCH,
                                  SUM(decode(SLAVE_QC_MISMATCH, 'Y', 1, 0)) SLAVE_QC_MISMATCH,
                                  SUM(decode(TYPECHECK_MISMATCH, 'Y', 1, 0)) TYPECHECK_MISMATCH,
                                  SUM(decode(AUTH_CHECK_MISMATCH, 'Y', 1, 0)) AUTH_CHECK_MISMATCH,
                                  SUM(decode(BIND_MISMATCH, 'Y', 1, 0)) BIND_MISMATCH,
                                  SUM(decode(DESCRIBE_MISMATCH, 'Y', 1, 0)) DESCRIBE_MISMATCH,
                                  SUM(decode(LANGUAGE_MISMATCH, 'Y', 1, 0)) LANGUAGE_MISMATCH,
                                  SUM(decode(TRANSLATION_MISMATCH, 'Y', 1, 0)) TRANSLATION_MISMATCH,
                                  SUM(decode(BIND_EQUIV_FAILURE, 'Y', 1, 0)) BIND_EQUIV_FAILURE,
                                  SUM(decode(INSUFF_PRIVS, 'Y', 1, 0)) INSUFF_PRIVS,
                                  SUM(decode(INSUFF_PRIVS_REM, 'Y', 1, 0)) INSUFF_PRIVS_REM,
                                  SUM(decode(REMOTE_TRANS_MISMATCH, 'Y', 1, 0)) REMOTE_TRANS_MISMATCH,
                                  SUM(decode(LOGMINER_SESSION_MISMATCH, 'Y', 1, 0)) LOGMINER_SESSION_MISMATCH,
                                  SUM(decode(INCOMP_LTRL_MISMATCH, 'Y', 1, 0)) INCOMP_LTRL_MISMATCH,
                                  SUM(decode(OVERLAP_TIME_MISMATCH, 'Y', 1, 0)) OVERLAP_TIME_MISMATCH,
                                  SUM(decode(EDITION_MISMATCH, 'Y', 1, 0)) EDITION_MISMATCH,
                                  SUM(decode(MV_QUERY_GEN_MISMATCH, 'Y', 1, 0)) MV_QUERY_GEN_MISMATCH,
                                  SUM(decode(USER_BIND_PEEK_MISMATCH, 'Y', 1, 0)) USER_BIND_PEEK_MISMATCH,
                                  SUM(decode(TYPCHK_DEP_MISMATCH, 'Y', 1, 0)) TYPCHK_DEP_MISMATCH,
                                  SUM(decode(NO_TRIGGER_MISMATCH, 'Y', 1, 0)) NO_TRIGGER_MISMATCH,
                                  SUM(decode(FLASHBACK_CURSOR, 'Y', 1, 0)) FLASHBACK_CURSOR,
                                  SUM(decode(ANYDATA_TRANSFORMATION, 'Y', 1, 0)) ANYDATA_TRANSFORMATION,
                                  SUM(decode(PDDL_ENV_MISMATCH, 'Y', 1, 0)) PDDL_ENV_MISMATCH,
                                  SUM(decode(TOP_LEVEL_RPI_CURSOR, 'Y', 1, 0)) TOP_LEVEL_RPI_CURSOR,
                                  SUM(decode(DIFFERENT_LONG_LENGTH, 'Y', 1, 0)) DIFFERENT_LONG_LENGTH,
                                  SUM(decode(LOGICAL_STANDBY_APPLY, 'Y', 1, 0)) LOGICAL_STANDBY_APPLY,
                                  SUM(decode(DIFF_CALL_DURN, 'Y', 1, 0)) DIFF_CALL_DURN,
                                  SUM(decode(BIND_UACS_DIFF, 'Y', 1, 0)) BIND_UACS_DIFF,
                                  SUM(decode(PLSQL_CMP_SWITCHS_DIFF, 'Y', 1, 0)) PLSQL_CMP_SWITCHS_DIFF,
                                  SUM(decode(CURSOR_PARTS_MISMATCH, 'Y', 1, 0)) CURSOR_PARTS_MISMATCH,
                                  SUM(decode(STB_OBJECT_MISMATCH, 'Y', 1, 0)) STB_OBJECT_MISMATCH,
                                  SUM(decode(CROSSEDITION_TRIGGER_MISMATCH, 'Y', 1, 0)) CROSSEDITION_TRIGGER_MISMATCH,
                                  SUM(decode(PQ_SLAVE_MISMATCH, 'Y', 1, 0)) PQ_SLAVE_MISMATCH,
                                  SUM(decode(TOP_LEVEL_DDL_MISMATCH, 'Y', 1, 0)) TOP_LEVEL_DDL_MISMATCH,
                                  SUM(decode(MULTI_PX_MISMATCH, 'Y', 1, 0)) MULTI_PX_MISMATCH,
                                  SUM(decode(BIND_PEEKED_PQ_MISMATCH, 'Y', 1, 0)) BIND_PEEKED_PQ_MISMATCH,
                                  SUM(decode(MV_REWRITE_MISMATCH, 'Y', 1, 0)) MV_REWRITE_MISMATCH,
                                  SUM(decode(ROLL_INVALID_MISMATCH, 'Y', 1, 0)) ROLL_INVALID_MISMATCH,
                                  SUM(decode(OPTIMIZER_MODE_MISMATCH, 'Y', 1, 0)) OPTIMIZER_MODE_MISMATCH,
                                  SUM(decode(PX_MISMATCH, 'Y', 1, 0)) PX_MISMATCH,
                                  SUM(decode(MV_STALEOBJ_MISMATCH, 'Y', 1, 0)) MV_STALEOBJ_MISMATCH,
                                  SUM(decode(FLASHBACK_TABLE_MISMATCH, 'Y', 1, 0)) FLASHBACK_TABLE_MISMATCH,
                                  SUM(decode(LITREP_COMP_MISMATCH, 'Y', 1, 0)) LITREP_COMP_MISMATCH,
                                  SUM(decode(PLSQL_DEBUG, 'Y', 1, 0)) PLSQL_DEBUG,
                                  SUM(decode(LOAD_OPTIMIZER_STATS, 'Y', 1, 0)) LOAD_OPTIMIZER_STATS,
                                  SUM(decode(ACL_MISMATCH, 'Y', 1, 0)) ACL_MISMATCH,
                                  SUM(decode(FLASHBACK_ARCHIVE_MISMATCH, 'Y', 1, 0)) FLASHBACK_ARCHIVE_MISMATCH,
                                  SUM(decode(LOCK_USER_SCHEMA_FAILED, 'Y', 1, 0)) LOCK_USER_SCHEMA_FAILED,
                                  SUM(decode(REMOTE_MAPPING_MISMATCH, 'Y', 1, 0)) REMOTE_MAPPING_MISMATCH,
                                  SUM(decode(LOAD_RUNTIME_HEAP_FAILED, 'Y', 1, 0)) LOAD_RUNTIME_HEAP_FAILED,
                                  SUM(decode(HASH_MATCH_FAILED, 'Y', 1, 0)) HASH_MATCH_FAILED,
                                  SUM(decode(PURGED_CURSOR, 'Y', 1, 0)) PURGED_CURSOR,
                                  SUM(decode(BIND_LENGTH_UPGRADEABLE, 'Y', 1, 0)) BIND_LENGTH_UPGRADEABLE,
                                  SUM(decode(USE_FEEDBACK_STATS, 'Y', 1, 0)) USE_FEEDBACK_STATS
                           FROM   (SELECT A.*,COUNT(1) OVER(PARTITION BY SQL_ID) CNT_ FROM v$sql_shared_cursor a &sql_id) a
                           LEFT   JOIN (SELECT /*+merge*/ * FROM v$sql &sql_id) b USING(sql_id,child_number)
                           WHERE  userenv('instance')=nvl(&inst1,userenv('instance')) &cnt
                           GROUP  BY sql_id))) --
                        UNPIVOT(val FOR c IN(UNBOUND_CURSOR,
                                             SQL_TYPE_MISMATCH,
                                             OPTIMIZER_MISMATCH,
                                             OUTLINE_MISMATCH,
                                             STATS_ROW_MISMATCH,
                                             LITERAL_MISMATCH,
                                             FORCE_HARD_PARSE,
                                             EXPLAIN_PLAN_CURSOR,
                                             BUFFERED_DML_MISMATCH,
                                             PDML_ENV_MISMATCH,
                                             INST_DRTLD_MISMATCH,
                                             SLAVE_QC_MISMATCH,
                                             TYPECHECK_MISMATCH,
                                             AUTH_CHECK_MISMATCH,
                                             BIND_MISMATCH,
                                             DESCRIBE_MISMATCH,
                                             LANGUAGE_MISMATCH,
                                             TRANSLATION_MISMATCH,
                                             BIND_EQUIV_FAILURE,
                                             INSUFF_PRIVS,
                                             INSUFF_PRIVS_REM,
                                             REMOTE_TRANS_MISMATCH,
                                             LOGMINER_SESSION_MISMATCH,
                                             INCOMP_LTRL_MISMATCH,
                                             OVERLAP_TIME_MISMATCH,
                                             EDITION_MISMATCH,
                                             MV_QUERY_GEN_MISMATCH,
                                             USER_BIND_PEEK_MISMATCH,
                                             TYPCHK_DEP_MISMATCH,
                                             NO_TRIGGER_MISMATCH,
                                             FLASHBACK_CURSOR,
                                             ANYDATA_TRANSFORMATION,
                                             PDDL_ENV_MISMATCH,
                                             TOP_LEVEL_RPI_CURSOR,
                                             DIFFERENT_LONG_LENGTH,
                                             LOGICAL_STANDBY_APPLY,
                                             DIFF_CALL_DURN,
                                             BIND_UACS_DIFF,
                                             PLSQL_CMP_SWITCHS_DIFF,
                                             CURSOR_PARTS_MISMATCH,
                                             STB_OBJECT_MISMATCH,
                                             CROSSEDITION_TRIGGER_MISMATCH,
                                             PQ_SLAVE_MISMATCH,
                                             TOP_LEVEL_DDL_MISMATCH,
                                             MULTI_PX_MISMATCH,
                                             BIND_PEEKED_PQ_MISMATCH,
                                             MV_REWRITE_MISMATCH,
                                             ROLL_INVALID_MISMATCH,
                                             OPTIMIZER_MODE_MISMATCH,
                                             PX_MISMATCH,
                                             MV_STALEOBJ_MISMATCH,
                                             FLASHBACK_TABLE_MISMATCH,
                                             LITREP_COMP_MISMATCH,
                                             PLSQL_DEBUG,
                                             LOAD_OPTIMIZER_STATS,
                                             ACL_MISMATCH,
                                             FLASHBACK_ARCHIVE_MISMATCH,
                                             LOCK_USER_SCHEMA_FAILED,
                                             REMOTE_MAPPING_MISMATCH,
                                             LOAD_RUNTIME_HEAP_FAILED,
                                             HASH_MATCH_FAILED,
                                             PURGED_CURSOR,
                                             BIND_LENGTH_UPGRADEABLE,
                                             USE_FEEDBACK_STATS))
                GROUP  BY sql_id, c
                HAVING SUM(val) > 0)
        GROUP  BY sql_id
        ORDER  BY 2 DESC)
WHERE  ROWNUM <= 50;

DECLARE
    reason VARCHAR2(32767);
    TYPE t IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;
    t1   t;
    t2   t;
    prev PLS_INTEGER := -1;
    XML  XMLTYPE;
BEGIN
    IF :sql_id IS NULL THEN
        RETURN;
    END IF;
    dbms_output.enable(NULL);
    FOR r IN (SELECT *
              FROM   (SELECT /*+use_hash(a b)*/
                       child_number c,
                       plan_hash_value phv,
                       REGEXP_REPLACE(reason, '<(ChildNumber|size)>.*?</\1>') reason,
                       row_number() over(PARTITION BY ora_hash(reason, 2147483646, 1) ORDER BY child_number) seq
                      FROM   (SELECT * FROM gv$sql_shared_cursor &sql_id)
                      JOIN   (SELECT * FROM gv$sql &sql_id)
                      USING  (inst_id, sql_id, child_number)
                      WHERE  INSTR(reason, 'ChildNode') > 0)
              WHERE  seq = 1) LOOP
        XML := xmltype('<R>' || SUBSTR(r.reason, 1, INSTR(r.reason, '</ChildNode>', -1) + LENGTH('</ChildNode>') - 1) || '</R>');
        dbms_output.put_line('--------------------------------------------------------------------');
        dbms_output.put_line('Plan_Hash_Value: '||r.phv||'    Child# :'||r.c);
        FOR r1 IN (SELECT *
                   FROM   XMLTABLE('/R/ChildNode' PASSING XML COLUMNS n XMLTYPE PATH 'node()') a,
                          XMLTABLE('/*' PASSING a.n COLUMNS t VARCHAR2(128) PATH 'name()', v VARCHAR2(128) PATH 'text()') b) LOOP
            dbms_output.put_line(r1.t || ': ' || r1.v);
        END LOOP;
    END LOOP;
END;
/
