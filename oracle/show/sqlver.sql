/*[[
    Show child cursors that share the same sql_id, with the aggregate count of each
    gv$sql_shared_cursor mismatch reason. Usage: @@NAME [-i"<inst_id>"] [-s"<sql_id>" [-c"<child_number>"]]

    -i : Limit the result to the given instance id
    -s : Report the mismatch details of the specified sql_id
    -c : Used together with "-s", limit the details to the given child_number

    Sample Outputs:
    ===============
    SQL> @@NAME
    SQL_ID         CHILDS VERS      ELA  AVG_ELA       MEM |  MISMATCH_REASONS
    ------------- ------ ---- -------- -------- --------- -  ------------------------------------------------------------------------------------------------------------------------
    acmvv4fhdc9zh      50   47    1.17s  40.30us  14.36 MB |  OPTIMIZER_MISMATCH     =  50 | LANGUAGE_MISMATCH      =  29 | BIND_LENGTH_UPGRADEABLE=  16 | ROLL_INVALID_MISMATCH  =   7 | HASH_MATCH_FAILED      =   1
    b9nbhsbx8tqz5      49   49    4.49s  10.05us   7.38 MB |  ROLL_INVALID_MISMATCH  =  47 | OPTIMIZER_MISMATCH     =  32 | HASH_MATCH_FAILED      =  15 | LANGUAGE_MISMATCH      =  11 | BIND_LENGTH_UPGRADEABLE=   8
    121ffmrc95v7g      38   37    1.66s 204.23us  10.94 MB |  OPTIMIZER_MISMATCH     =  37 | LANGUAGE_MISMATCH      =  17 | ROLL_INVALID_MISMATCH  =  14 | HASH_MATCH_FAILED      =   4
    3un99a0zwp4vd      35   31    1.56s 154.83us   7.35 MB |  OPTIMIZER_MISMATCH     =  34 | OPTIMIZER_MODE_MISMATCH=  19 | ROLL_INVALID_MISMATCH  =   6
    8swypbbr0m372      35   31 682.90ms  53.06us   6.75 MB |  OPTIMIZER_MISMATCH     =  33 | OPTIMIZER_MODE_MISMATCH=  16

    SQL> @@NAME -s"acmvv4fhdc9zh"
    SQL_ID         CHILDS VERS      ELA  AVG_ELA       MEM |  MISMATCH_REASONS
    ------------- ------ ---- -------- -------- --------- -  -------------------------
    acmvv4fhdc9zh      50   47    1.17s  40.30us  14.36 MB |  OPTIMIZER_MISMATCH     =  50
                                                              LANGUAGE_MISMATCH      =  29
                                                              BIND_LENGTH_UPGRADEABLE=  16
                                                              ROLL_INVALID_MISMATCH  =   7
                                                              HASH_MATCH_FAILED      =   1

--[[
        @ALIAS  : nonshare
        &sql_id : default={} s={WHERE SQL_ID='&0' &child}
        &child  : default={} c={AND child_number='&0'}
        &cnt    : default={AND CNT_>1} s={AND 1=1}
        &sep    : default={' | '} s={chr(10)||' '}
        &inst1  : default={:instance} i={0+'&0'}
    --]]

]]*/

col ela,avg_ela for usmhd2
col mem for kmg2
set feed off verify off
SELECT *
FROM   (SELECT sql_id, mod(sum(DISTINCT childs),1e6) childs,mod(sum(DISTINCT vers),1e6) vers,
               sum(DISTINCT ela) ela,
               sum(DISTINCT avg_ela) avg_ela,
               sum(DISTINCT mem) mem,
               '$HEADCOLOR$|$NOR$' "|",
               ' '||listagg(rpad(c,l)||'='||lpad(val,4) ||&sep,'') WITHIN GROUP(ORDER BY val DESC,c) " MISMATCH_REASONS",
               substr(trim(regexp_replace(max(sql_text),'\s+ ',' ')),1,200) sql_text
        FROM   (SELECT sql_id,
                       max(sql_text) sql_text, c,
                       sum(DISTINCT childs) childs,
                       sum(DISTINCT vers) vers,
                       sum(DISTINCT ela) ela,
                       sum(DISTINCT avg_ela) avg_ela,
                       sum(DISTINCT mem) mem,
                       sum(val) val,
                       max(length(c)) OVER() l
                FROM   TABLE(gv$(CURSOR(
                           SELECT /*+ordered DYNAMIC_SAMPLING(5)*/
                                  sql_id,
                                  userenv('instance')*1e6+COUNT(1) childs,
                                  userenv('instance')*1e6+sum(loaded_versions) vers,
                                  max(substr(b.sql_text,1,300)) sql_text,
                                  sum(elapsed_time) ela,
                                  sum(SHARABLE_MEM+TYPECHECK_MEM) mem,
                                  round(sum(elapsed_time)/greatest(sum(executions),1),3) avg_ela,
                                  sum(decode(UNBOUND_CURSOR, 'Y', 1, 0)) UNBOUND_CURSOR,
                                  sum(decode(SQL_TYPE_MISMATCH, 'Y', 1, 0)) SQL_TYPE_MISMATCH,
                                  sum(decode(OPTIMIZER_MISMATCH, 'Y', 1, 0)) OPTIMIZER_MISMATCH,
                                  sum(decode(OUTLINE_MISMATCH, 'Y', 1, 0)) OUTLINE_MISMATCH,
                                  sum(decode(STATS_ROW_MISMATCH, 'Y', 1, 0)) STATS_ROW_MISMATCH,
                                  sum(decode(LITERAL_MISMATCH, 'Y', 1, 0)) LITERAL_MISMATCH,
                                  sum(decode(FORCE_HARD_PARSE, 'Y', 1, 0)) FORCE_HARD_PARSE,
                                  sum(decode(EXPLAIN_PLAN_CURSOR, 'Y', 1, 0)) EXPLAIN_PLAN_CURSOR,
                                  sum(decode(BUFFERED_DML_MISMATCH, 'Y', 1, 0)) BUFFERED_DML_MISMATCH,
                                  sum(decode(PDML_ENV_MISMATCH, 'Y', 1, 0)) PDML_ENV_MISMATCH,
                                  sum(decode(INST_DRTLD_MISMATCH, 'Y', 1, 0)) INST_DRTLD_MISMATCH,
                                  sum(decode(SLAVE_QC_MISMATCH, 'Y', 1, 0)) SLAVE_QC_MISMATCH,
                                  sum(decode(TYPECHECK_MISMATCH, 'Y', 1, 0)) TYPECHECK_MISMATCH,
                                  sum(decode(AUTH_CHECK_MISMATCH, 'Y', 1, 0)) AUTH_CHECK_MISMATCH,
                                  sum(decode(BIND_MISMATCH, 'Y', 1, 0)) BIND_MISMATCH,
                                  sum(decode(DESCRIBE_MISMATCH, 'Y', 1, 0)) DESCRIBE_MISMATCH,
                                  sum(decode(LANGUAGE_MISMATCH, 'Y', 1, 0)) LANGUAGE_MISMATCH,
                                  sum(decode(TRANSLATION_MISMATCH, 'Y', 1, 0)) TRANSLATION_MISMATCH,
                                  sum(decode(BIND_EQUIV_FAILURE, 'Y', 1, 0)) BIND_EQUIV_FAILURE,
                                  sum(decode(INSUFF_PRIVS, 'Y', 1, 0)) INSUFF_PRIVS,
                                  sum(decode(INSUFF_PRIVS_REM, 'Y', 1, 0)) INSUFF_PRIVS_REM,
                                  sum(decode(REMOTE_TRANS_MISMATCH, 'Y', 1, 0)) REMOTE_TRANS_MISMATCH,
                                  sum(decode(LOGMINER_SESSION_MISMATCH, 'Y', 1, 0)) LOGMINER_SESSION_MISMATCH,
                                  sum(decode(INCOMP_LTRL_MISMATCH, 'Y', 1, 0)) INCOMP_LTRL_MISMATCH,
                                  sum(decode(OVERLAP_TIME_MISMATCH, 'Y', 1, 0)) OVERLAP_TIME_MISMATCH,
                                  sum(decode(EDITION_MISMATCH, 'Y', 1, 0)) EDITION_MISMATCH,
                                  sum(decode(MV_QUERY_GEN_MISMATCH, 'Y', 1, 0)) MV_QUERY_GEN_MISMATCH,
                                  sum(decode(USER_BIND_PEEK_MISMATCH, 'Y', 1, 0)) USER_BIND_PEEK_MISMATCH,
                                  sum(decode(TYPCHK_DEP_MISMATCH, 'Y', 1, 0)) TYPCHK_DEP_MISMATCH,
                                  sum(decode(NO_TRIGGER_MISMATCH, 'Y', 1, 0)) NO_TRIGGER_MISMATCH,
                                  sum(decode(FLASHBACK_CURSOR, 'Y', 1, 0)) FLASHBACK_CURSOR,
                                  sum(decode(ANYDATA_TRANSFORMATION, 'Y', 1, 0)) ANYDATA_TRANSFORMATION,
                                  sum(decode(PDDL_ENV_MISMATCH, 'Y', 1, 0)) PDDL_ENV_MISMATCH,
                                  sum(decode(TOP_LEVEL_RPI_CURSOR, 'Y', 1, 0)) TOP_LEVEL_RPI_CURSOR,
                                  sum(decode(DIFFERENT_LONG_LENGTH, 'Y', 1, 0)) DIFFERENT_LONG_LENGTH,
                                  sum(decode(LOGICAL_STANDBY_APPLY, 'Y', 1, 0)) LOGICAL_STANDBY_APPLY,
                                  sum(decode(DIFF_CALL_DURN, 'Y', 1, 0)) DIFF_CALL_DURN,
                                  sum(decode(BIND_UACS_DIFF, 'Y', 1, 0)) BIND_UACS_DIFF,
                                  sum(decode(PLSQL_CMP_SWITCHS_DIFF, 'Y', 1, 0)) PLSQL_CMP_SWITCHS_DIFF,
                                  sum(decode(CURSOR_PARTS_MISMATCH, 'Y', 1, 0)) CURSOR_PARTS_MISMATCH,
                                  sum(decode(STB_OBJECT_MISMATCH, 'Y', 1, 0)) STB_OBJECT_MISMATCH,
                                  sum(decode(CROSSEDITION_TRIGGER_MISMATCH, 'Y', 1, 0)) CROSSEDITION_TRIGGER_MISMATCH,
                                  sum(decode(PQ_SLAVE_MISMATCH, 'Y', 1, 0)) PQ_SLAVE_MISMATCH,
                                  sum(decode(TOP_LEVEL_DDL_MISMATCH, 'Y', 1, 0)) TOP_LEVEL_DDL_MISMATCH,
                                  sum(decode(MULTI_PX_MISMATCH, 'Y', 1, 0)) MULTI_PX_MISMATCH,
                                  sum(decode(BIND_PEEKED_PQ_MISMATCH, 'Y', 1, 0)) BIND_PEEKED_PQ_MISMATCH,
                                  sum(decode(MV_REWRITE_MISMATCH, 'Y', 1, 0)) MV_REWRITE_MISMATCH,
                                  sum(decode(ROLL_INVALID_MISMATCH, 'Y', 1, 0)) ROLL_INVALID_MISMATCH,
                                  sum(decode(OPTIMIZER_MODE_MISMATCH, 'Y', 1, 0)) OPTIMIZER_MODE_MISMATCH,
                                  sum(decode(PX_MISMATCH, 'Y', 1, 0)) PX_MISMATCH,
                                  sum(decode(MV_STALEOBJ_MISMATCH, 'Y', 1, 0)) MV_STALEOBJ_MISMATCH,
                                  sum(decode(FLASHBACK_TABLE_MISMATCH, 'Y', 1, 0)) FLASHBACK_TABLE_MISMATCH,
                                  sum(decode(LITREP_COMP_MISMATCH, 'Y', 1, 0)) LITREP_COMP_MISMATCH,
                                  sum(decode(PLSQL_DEBUG, 'Y', 1, 0)) PLSQL_DEBUG,
                                  sum(decode(LOAD_OPTIMIZER_STATS, 'Y', 1, 0)) LOAD_OPTIMIZER_STATS,
                                  sum(decode(ACL_MISMATCH, 'Y', 1, 0)) ACL_MISMATCH,
                                  sum(decode(FLASHBACK_ARCHIVE_MISMATCH, 'Y', 1, 0)) FLASHBACK_ARCHIVE_MISMATCH,
                                  sum(decode(LOCK_USER_SCHEMA_FAILED, 'Y', 1, 0)) LOCK_USER_SCHEMA_FAILED,
                                  sum(decode(REMOTE_MAPPING_MISMATCH, 'Y', 1, 0)) REMOTE_MAPPING_MISMATCH,
                                  sum(decode(LOAD_RUNTIME_HEAP_FAILED, 'Y', 1, 0)) LOAD_RUNTIME_HEAP_FAILED,
                                  sum(decode(HASH_MATCH_FAILED, 'Y', 1, 0)) HASH_MATCH_FAILED,
                                  sum(decode(PURGED_CURSOR, 'Y', 1, 0)) PURGED_CURSOR,
                                  sum(decode(BIND_LENGTH_UPGRADEABLE, 'Y', 1, 0)) BIND_LENGTH_UPGRADEABLE,
                                  sum(decode(USE_FEEDBACK_STATS, 'Y', 1, 0)) USE_FEEDBACK_STATS
                           FROM   (SELECT A.*,COUNT(1) OVER(PARTITION BY SQL_ID) CNT_ FROM v$sql_shared_cursor a &sql_id) a
                           JOIN   (SELECT /*+merge*/ * FROM v$sql &sql_id) b USING(sql_id,child_number)
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
                HAVING sum(val) > 0)
        GROUP  BY sql_id
        ORDER  BY 2 DESC)
WHERE  ROWNUM <= 50;

VAR c REFCURSOR "MISMATCH DETAILS &sql_id";

DECLARE
    XML    xmltype := xmltype('<ROWSET/>');
    R      xmltype;
    TYPE   t IS TABLE OF VARCHAR2(32767) INDEX BY VARCHAR2(32767);
    lst    t;
    cnt    t;
    ps     t;
    fl     t;
    ll     t;
    bks    t;
    pares  PLS_INTEGER;

    fld    VARCHAR2(30);
    lld    VARCHAR2(30);
    key    VARCHAR2(32767);
    val    VARCHAR2(32767);
    v      VARCHAR2(32767);
    phv    INT;
    calls  INT;
    bcks   INT;
    chd    VARCHAR2(4000);
    reason VARCHAR2(2000);
    memo   VARCHAR2(32767);
    n      PLS_INTEGER := 0;
    PROCEDURE flush IS
        key    VARCHAR2(32767);
    BEGIN
        IF reason IS NULL THEN
            RETURN;
        END IF;
        SELECT xmlelement(R,xmlelement(P,phv)
                           ,xmlelement(R,reason)
                           ,xmlelement(M,trim(chr(10) FROM substr(memo,1,3600)))).getstringval()
        INTO   key FROM dual;

        IF lst.exists(key) THEN
            lst(key) := substr(lst(key),1,32750)||','||chd;
            cnt(key) := cnt(key)+n;
            ps(key)  := ps(key)+calls;
            bks(key) := bks(key)+bcks;
            fl(key)  := least(fl(key),fld);
            ll(key)  := greatest(ll(key),lld);
        ELSE
            lst(key) := chd;
            cnt(key) := n;
            ps(key)  := calls;
            fl(key)  := fld;
            ll(key)  := lld;
            bks(key) := bcks;
        END IF;
        reason:=NULL;
        memo:=NULL;
        val:=NULL;
    END;
BEGIN
    IF :sql_id IS NULL THEN
        RETURN;
    END IF;
    dbms_output.enable(NULL);
    FOR r IN (SELECT *
              FROM   (
                  SELECT a.*,
                         decode(seq,1,listagg(child_number||decode(insts,1,'','@'||inst_id),',')
                            WITHIN GROUP(ORDER BY child_number)
                            OVER(PARTITION BY grp))
                         AS c
                  FROM   (SELECT /*+use_hash(a b) outline_leaf*/
                                  child_number,
                                  buckets,
                                  count(DISTINCT inst_id) OVER() insts,
                                  inst_id,
                                  plan_hash_value phv,
                                  optimizer_env_hash_value env_hash,
                                  schema,
                                  reason,
                                  grp,
                                  min(first_load_time) OVER(PARTITION BY plan_hash_value,grp) first_load,
                                  to_char(max(last_active_time)  OVER(PARTITION BY plan_hash_value,grp),'YYYY-MM-DD/HH24:MI:SS') last_load,
                                  sum(parse_calls)     OVER(PARTITION BY plan_hash_value,grp) parses,
                                  count(1)             OVER(PARTITION BY plan_hash_value,grp) cnt,
                                  row_number()         OVER(PARTITION BY plan_hash_value,grp ORDER BY child_number) seq
                          FROM   (SELECT inst_id,
                                         sql_id,
                                         child_number,
                                         buckets,
                                         rel reason,
                                         SYS_OP_COMBINED_HASH(regexp_replace(rel, '<(ChildNumber|size|ID)>.*?</\1>')) grp
                                  FROM   (SELECT a.*,
                                                 (SELECT COUNT(1)
                                                FROM   (SELECT /*+merge*/ * FROM GV$SQL_CS_HISTOGRAM &sql_id) B
                                                WHERE  B.child_number=a.child_number) buckets,
                                                 CASE WHEN instr(reason, 'ChildNode')>0 THEN reason ELSE to_clob('<ChildNode><ID>0</ID><reason>Common</reason>'
                                                || decode(UNBOUND_CURSOR, 'Y', '<UNBOUND_CURSOR>Yes</UNBOUND_CURSOR>')
                                                || decode(SQL_TYPE_MISMATCH, 'Y', '<SQL_TYPE_MISMATCH>Yes</SQL_TYPE_MISMATCH>')
                                                || decode(OPTIMIZER_MISMATCH, 'Y', '<OPTIMIZER_MISMATCH>Yes</OPTIMIZER_MISMATCH>')
                                                || decode(OUTLINE_MISMATCH, 'Y', '<OUTLINE_MISMATCH>Yes</OUTLINE_MISMATCH>')
                                                || decode(STATS_ROW_MISMATCH, 'Y', '<STATS_ROW_MISMATCH>Yes</STATS_ROW_MISMATCH>')
                                                || decode(LITERAL_MISMATCH, 'Y', '<LITERAL_MISMATCH>Yes</LITERAL_MISMATCH>')
                                                || decode(FORCE_HARD_PARSE, 'Y', '<FORCE_HARD_PARSE>Yes</FORCE_HARD_PARSE>')
                                                || decode(EXPLAIN_PLAN_CURSOR, 'Y', '<EXPLAIN_PLAN_CURSOR>Yes</EXPLAIN_PLAN_CURSOR>')
                                                || decode(BUFFERED_DML_MISMATCH, 'Y', '<BUFFERED_DML_MISMATCH>Yes</BUFFERED_DML_MISMATCH>')
                                                || decode(PDML_ENV_MISMATCH, 'Y', '<PDML_ENV_MISMATCH>Yes</PDML_ENV_MISMATCH>')
                                                || decode(INST_DRTLD_MISMATCH, 'Y', '<INST_DRTLD_MISMATCH>Yes</INST_DRTLD_MISMATCH>')
                                                || decode(SLAVE_QC_MISMATCH, 'Y', '<SLAVE_QC_MISMATCH>Yes</SLAVE_QC_MISMATCH>')
                                                || decode(TYPECHECK_MISMATCH, 'Y', '<TYPECHECK_MISMATCH>Yes</TYPECHECK_MISMATCH>')
                                                || decode(AUTH_CHECK_MISMATCH, 'Y', '<AUTH_CHECK_MISMATCH>Yes</AUTH_CHECK_MISMATCH>')
                                                || decode(BIND_MISMATCH, 'Y', '<BIND_MISMATCH>Yes</BIND_MISMATCH>')
                                                || decode(DESCRIBE_MISMATCH, 'Y', '<DESCRIBE_MISMATCH>Yes</DESCRIBE_MISMATCH>')
                                                || decode(LANGUAGE_MISMATCH, 'Y', '<LANGUAGE_MISMATCH>Yes</LANGUAGE_MISMATCH>')
                                                || decode(TRANSLATION_MISMATCH, 'Y', '<TRANSLATION_MISMATCH>Yes</TRANSLATION_MISMATCH>')
                                                || decode(BIND_EQUIV_FAILURE, 'Y', '<BIND_EQUIV_FAILURE>Yes</BIND_EQUIV_FAILURE>')
                                                || decode(INSUFF_PRIVS, 'Y', '<INSUFF_PRIVS>Yes</INSUFF_PRIVS>')
                                                || decode(INSUFF_PRIVS_REM, 'Y', '<INSUFF_PRIVS_REM>Yes</INSUFF_PRIVS_REM>')
                                                || decode(REMOTE_TRANS_MISMATCH, 'Y', '<REMOTE_TRANS_MISMATCH>Yes</REMOTE_TRANS_MISMATCH>')
                                                || decode(LOGMINER_SESSION_MISMATCH, 'Y', '<LOGMINER_SESSION_MISMATCH>Yes</LOGMINER_SESSION_MISMATCH>')
                                                || decode(INCOMP_LTRL_MISMATCH, 'Y', '<INCOMP_LTRL_MISMATCH>Yes</INCOMP_LTRL_MISMATCH>')
                                                || decode(OVERLAP_TIME_MISMATCH, 'Y', '<OVERLAP_TIME_MISMATCH>Yes</OVERLAP_TIME_MISMATCH>')
                                                || decode(EDITION_MISMATCH, 'Y', '<EDITION_MISMATCH>Yes</EDITION_MISMATCH>')
                                                || decode(MV_QUERY_GEN_MISMATCH, 'Y', '<MV_QUERY_GEN_MISMATCH>Yes</MV_QUERY_GEN_MISMATCH>')
                                                || decode(USER_BIND_PEEK_MISMATCH, 'Y', '<USER_BIND_PEEK_MISMATCH>Yes</USER_BIND_PEEK_MISMATCH>')
                                                || decode(TYPCHK_DEP_MISMATCH, 'Y', '<TYPCHK_DEP_MISMATCH>Yes</TYPCHK_DEP_MISMATCH>')
                                                || decode(NO_TRIGGER_MISMATCH, 'Y', '<NO_TRIGGER_MISMATCH>Yes</NO_TRIGGER_MISMATCH>')
                                                || decode(FLASHBACK_CURSOR, 'Y', '<FLASHBACK_CURSOR>Yes</FLASHBACK_CURSOR>')
                                                || decode(ANYDATA_TRANSFORMATION, 'Y', '<ANYDATA_TRANSFORMATION>Yes</ANYDATA_TRANSFORMATION>')
                                                || decode(PDDL_ENV_MISMATCH, 'Y', '<PDDL_ENV_MISMATCH>Yes</PDDL_ENV_MISMATCH>')
                                                || decode(TOP_LEVEL_RPI_CURSOR, 'Y', '<TOP_LEVEL_RPI_CURSOR>Yes</TOP_LEVEL_RPI_CURSOR>')
                                                || decode(DIFFERENT_LONG_LENGTH, 'Y', '<DIFFERENT_LONG_LENGTH>Yes</DIFFERENT_LONG_LENGTH>')
                                                || decode(LOGICAL_STANDBY_APPLY, 'Y', '<LOGICAL_STANDBY_APPLY>Yes</LOGICAL_STANDBY_APPLY>')
                                                || decode(DIFF_CALL_DURN, 'Y', '<DIFF_CALL_DURN>Yes</DIFF_CALL_DURN>')
                                                || decode(BIND_UACS_DIFF, 'Y', '<BIND_UACS_DIFF>Yes</BIND_UACS_DIFF>')
                                                || decode(PLSQL_CMP_SWITCHS_DIFF, 'Y', '<PLSQL_CMP_SWITCHS_DIFF>Yes</PLSQL_CMP_SWITCHS_DIFF>')
                                                || decode(CURSOR_PARTS_MISMATCH, 'Y', '<CURSOR_PARTS_MISMATCH>Yes</CURSOR_PARTS_MISMATCH>')
                                                || decode(STB_OBJECT_MISMATCH, 'Y', '<STB_OBJECT_MISMATCH>Yes</STB_OBJECT_MISMATCH>')
                                                || decode(CROSSEDITION_TRIGGER_MISMATCH, 'Y', '<CROSSEDITION_TRIGGER_MISMATCH>Yes</CROSSEDITION_TRIGGER_MISMATCH>')
                                                || decode(PQ_SLAVE_MISMATCH, 'Y', '<PQ_SLAVE_MISMATCH>Yes</PQ_SLAVE_MISMATCH>')
                                                || decode(TOP_LEVEL_DDL_MISMATCH, 'Y', '<TOP_LEVEL_DDL_MISMATCH>Yes</TOP_LEVEL_DDL_MISMATCH>')
                                                || decode(MULTI_PX_MISMATCH, 'Y', '<MULTI_PX_MISMATCH>Yes</MULTI_PX_MISMATCH>')
                                                || decode(BIND_PEEKED_PQ_MISMATCH, 'Y', '<BIND_PEEKED_PQ_MISMATCH>Yes</BIND_PEEKED_PQ_MISMATCH>')
                                                || decode(MV_REWRITE_MISMATCH, 'Y', '<MV_REWRITE_MISMATCH>Yes</MV_REWRITE_MISMATCH>')
                                                || decode(ROLL_INVALID_MISMATCH, 'Y', '<ROLL_INVALID_MISMATCH>Yes</ROLL_INVALID_MISMATCH>')
                                                || decode(OPTIMIZER_MODE_MISMATCH, 'Y', '<OPTIMIZER_MODE_MISMATCH>Yes</OPTIMIZER_MODE_MISMATCH>')
                                                || decode(PX_MISMATCH, 'Y', '<PX_MISMATCH>Yes</PX_MISMATCH>')
                                                || decode(MV_STALEOBJ_MISMATCH, 'Y', '<MV_STALEOBJ_MISMATCH>Yes</MV_STALEOBJ_MISMATCH>')
                                                || decode(FLASHBACK_TABLE_MISMATCH, 'Y', '<FLASHBACK_TABLE_MISMATCH>Yes</FLASHBACK_TABLE_MISMATCH>')
                                                || decode(LITREP_COMP_MISMATCH, 'Y', '<LITREP_COMP_MISMATCH>Yes</LITREP_COMP_MISMATCH>')
                                                || decode(PLSQL_DEBUG, 'Y', '<PLSQL_DEBUG>Yes</PLSQL_DEBUG>')
                                                || decode(LOAD_OPTIMIZER_STATS, 'Y', '<LOAD_OPTIMIZER_STATS>Yes</LOAD_OPTIMIZER_STATS>')
                                                || decode(ACL_MISMATCH, 'Y', '<ACL_MISMATCH>Yes</ACL_MISMATCH>')
                                                || decode(FLASHBACK_ARCHIVE_MISMATCH, 'Y', '<FLASHBACK_ARCHIVE_MISMATCH>Yes</FLASHBACK_ARCHIVE_MISMATCH>')
                                                || decode(LOCK_USER_SCHEMA_FAILED, 'Y', '<LOCK_USER_SCHEMA_FAILED>Yes</LOCK_USER_SCHEMA_FAILED>')
                                                || decode(REMOTE_MAPPING_MISMATCH, 'Y', '<REMOTE_MAPPING_MISMATCH>Yes</REMOTE_MAPPING_MISMATCH>')
                                                || decode(LOAD_RUNTIME_HEAP_FAILED, 'Y', '<LOAD_RUNTIME_HEAP_FAILED>Yes</LOAD_RUNTIME_HEAP_FAILED>')
                                                || decode(HASH_MATCH_FAILED, 'Y', '<HASH_MATCH_FAILED>Yes</HASH_MATCH_FAILED>')
                                                || decode(PURGED_CURSOR, 'Y', '<PURGED_CURSOR>Yes</PURGED_CURSOR>')
                                                || decode(BIND_LENGTH_UPGRADEABLE, 'Y', '<BIND_LENGTH_UPGRADEABLE>Yes</BIND_LENGTH_UPGRADEABLE>')
                                                || decode(USE_FEEDBACK_STATS, 'Y', '<USE_FEEDBACK_STATS>Yes</USE_FEEDBACK_STATS>')
                                                ||'</ChildNode>') END rel
                                        FROM   gv$sql_shared_cursor a &sql_id)) a
                          JOIN   (SELECT  inst_id,
                                         sql_id,
                                         child_number,
                                         plan_hash_value,
                                         loads,
                                         optimizer_env_hash_value,
                                         parsing_schema_name schema,
                                         first_load_time,
                                         last_active_time,
                                         parse_calls
                                FROM   gv$sql &sql_id) b
                          USING  (inst_id, sql_id, child_number)
                          WHERE  inst_id=nvl(&inst1,inst_id)) a
                  WHERE  seq <=100)
            WHERE  seq=1
            ORDER  BY c) LOOP
        phv    := r.phv;
        chd    := r.c;
        n      := r.cnt;
        fld    := r.first_load;
        lld    := r.last_load;
        calls  := r.parses;
        bcks   := r.buckets;
        XML    := xmltype('<R>' || regexp_substr(
                                    regexp_replace(
                                        regexp_replace(r.reason, '<(ChildNumber|size)>.*?</\1>'),
                                        '(</?[a-zA-Z0-9_]+)[^<>/]*?(/?>)','\1\2'),
                                    '<ChildNode>.+</ChildNode>')
                       || '</R>');

        FOR r1 IN (SELECT i,id,trim(reason) reason,trim(t) t,trim(v) v
                   FROM   xmltable('/R/ChildNode' PASSING XML COLUMNS
                                i FOR ordinality,
                                id INT PATH 'ID',
                                reason VARCHAR2(300) PATH 'reason',
                                n xmltype PATH 'node()') a,
                          xmltable('/*[not(name()="ID" or name()="reason")]' PASSING a.n COLUMNS
                                t VARCHAR2(128) PATH 'name()',
                                v VARCHAR2(4000) PATH 'text()') b
                    ORDER  BY i,id,reason,lower(t)) LOOP
            key := r1.i||','||r1.reason;
            IF val IS NULL THEN
                val := key;
            ELSIF key != val THEN
                flush;
                val := key;
            END IF;
            reason:= r1.reason;

            memo  := memo||chr(10)||r1.t||': '||regexp_replace(r1.v,'(\s*'||chr(9)||'\s*|\s{3,})',' <= ');
        END LOOP;
        flush;
    END LOOP;

    key:=lst.first;
    XML := xmltype('<ROWSET/>');
    WHILE key IS NOT NULL LOOP
        lst(key) := regexp_replace(lst(key),'([^,]+)(,\1)+','\1');
        xml := xml.appendChildXML('/ROWSET',xmltype(key)
            .appendChildXML('/R',xmltype('<C>'||substr(regexp_replace(lst(key),'(.{80})','\1'||chr(10)),1,3900)||'</C>'))
            .appendChildXML('/R',xmltype('<PS>'||ps(key)||'</PS>'))
            .appendChildXML('/R',xmltype('<L>'||fl(key)||chr(10)||ll(key)||'</L>'))
            .appendChildXML('/R',xmltype('<BS>'||bks(key)||'</BS>'))
            .appendChildXML('/R',xmltype('<CNT>'||cnt(key)||'</CNT>')));
        key := lst.next(key);
    END LOOP;
    OPEN :c FOR
        SELECT *
        FROM   xmltable('/ROWSET/R' PASSING xml
              COLUMNS CURSORS INT PATH 'CNT',
                      BUCKETS INT PATH 'BS',
                      PLAN_HASH INT PATH 'P',
                      PARSES INT PATH 'PS',
                      Reason  VARCHAR2(2000) PATH 'R',
                      MEMO VARCHAR2(4000) PATH 'M',
                      ACTIVE_TIME VARCHAR2(80) PATH 'L',
                      EXAMPLE_CURSORS VARCHAR(2000) PATH 'C')
        ORDER  BY 1 DESC,REASON;
END;
/

set rowsep - colsep |
print c