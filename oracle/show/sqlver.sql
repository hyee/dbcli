/*[[
    Show SQL Share cursors (gv$sql_shared_cursor). Usage: @@NAME [-i"<inst_id>"] [-s"<sql_id>" [-c"<child_number>"]] 

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
FROM   (SELECT sql_id, mod(SUM(DISTINCT childs),1e6) childs,mod(SUM(DISTINCT vers),1e6) vers,
               SUM(distinct ela) ela,
               SUM(distinct avg_ela) avg_ela,
               SUM(distinct mem) mem,
               '$HEADCOLOR$|$NOR$' "|",
               ' '||listagg(rpad(c,l)||'='||lpad(val,4) ||&sep,'') WITHIN GROUP(ORDER BY val desc,c) " MISMATCH_REASONS",
               substr(trim(regexp_replace(MAX(sql_text),'\s+ ',' ')),1,200) sql_text
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
                                  MAX(substr(b.sql_text,1,300)) sql_text,
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
                HAVING SUM(val) > 0)
        GROUP  BY sql_id
        ORDER  BY 2 DESC)
WHERE  ROWNUM <= 50;

VAR c REFCURSOR "MISMATCH DETAILS &sql_id";

DECLARE
    XML    XMLTYPE := XMLTYPE('<ROWSET/>');
    R      XMLTYPE;
    TYPE   t IS TABLE OF VARCHAR2(32767) INDEX BY VARCHAR2(32767);
    lst    t;
    cnt    t;
    ps     t;
    fl     t;
    ll     t;
    pares  PLS_INTEGER;
    fld    VARCHAR2(30);
    lld    VARCHAR2(30);
    key    VARCHAR2(32767);
    val    VARCHAR2(32767);
    v      VARCHAR2(32767);
    phv    int;
    calls  int;
    chd    VARCHAR2(4000);
    reason VARCHAR2(2000);
    memo   VARCHAR2(32767);
    n      PLS_INTEGER := 0;
    PROCEDURE flush IS
        key    VARCHAR2(32767);
    BEGIN
        IF reason IS NULL THEN 
            return;
        END IF;
        select xmlelement(R,xmlelement(P,phv)
                           ,xmlelement(R,reason)
                           ,xmlelement(M,trim(chr(10) from substr(memo,1,3600)))).getstringval()
        into   key from dual;

        IF lst.exists(key) THEN
            lst(key) := substr(lst(key),1,32750)||','||chd;
            cnt(key) := cnt(key)+n;
            ps(key)  := ps(key)+calls;
            fl(key)  := least(fl(key),fld);
            ll(key)  := greatest(ll(key),lld);
        ELSE
            lst(key) := chd;
            cnt(key) := n;
            ps(key)  := calls;
            fl(key)  := fld;
            ll(key)  := lld;
        END IF;
        reason:=null;
        memo:=null;
        val:=null;
    END;
BEGIN
    IF :sql_id IS NULL THEN
        RETURN;
    END IF;
    dbms_output.enable(NULL);
    FOR r IN (SELECT * 
              FROM (
                  SELECT a.*,
                         decode(seq,1,listagg(child_number||decode(insts,1,'','@'||inst_id),',')
                            within group(order by child_number)
                            over(partition by grp))
                         AS c
                  FROM   (SELECT /*+use_hash(a b) outline_leaf*/
                                  child_number,
                                  count(distinct inst_id) over() insts,
                                  inst_id,
                                  plan_hash_value phv,
                                  optimizer_env_hash_value env_hash,
                                  schema,
                                  reason,
                                  grp,
                                  min(first_load_time) over(partition by plan_hash_value,grp) first_load,
                                  max(last_load_time)  over(partition by plan_hash_value,grp) last_load,
                                  sum(parse_calls)     over(partition by plan_hash_value,grp) parses,
                                  count(1)             over(partition by plan_hash_value,grp) cnt,
                                  row_number()         over(partition by plan_hash_value,grp order by child_number) seq
                          FROM   (SELECT inst_id, 
                                         sql_id, 
                                         child_number,
                                         rel reason,
                                         SYS_OP_COMBINED_HASH(regexp_replace(rel, '<(ChildNumber|size|ID)>.*?</\1>')) grp
                                  FROM (SELECT a.*,
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
                                        FROM gv$sql_shared_cursor a &sql_id)) a
                          JOIN (SELECT  inst_id, 
                                        sql_id, 
                                        child_number,
                                        plan_hash_value,
                                        loads,
                                        optimizer_env_hash_value,
                                        parsing_schema_name schema,
                                        first_load_time,
                                        last_load_time,
                                        parse_calls
                                FROM    gv$sql &sql_id) b
                          USING  (inst_id, sql_id, child_number)
                          WHERE  inst_id=nvl(&inst1,inst_id)) a
                  WHERE  seq <=100)
             WHERE seq=1
             ORDER  BY c) LOOP
        phv   := r.phv;
        chd   := r.c;
        n     := r.cnt;
        fld   := r.first_load;
        lld   := r.last_load;
        calls := r.parses;
        XML := xmltype('<R>' || regexp_substr(
                                    regexp_replace(
                                        regexp_replace(r.reason, '<(ChildNumber|size)>.*?</\1>'),
                                        '(</?[a-zA-Z0-9_]+)[^<>/]*?(/?>)','\1\2'), 
                                    '<ChildNode>.+</ChildNode>')
                       || '</R>');

        FOR r1 IN (SELECT i,id,trim(reason) reason,trim(t) t,trim(v) v
                   FROM   XMLTABLE('/R/ChildNode' PASSING XML COLUMNS
                                i for ordinality,
                                id INT PATH 'ID',
                                reason VARCHAR2(300) PATH 'reason',
                                n XMLTYPE PATH 'node()') a,
                          XMLTABLE('/*[not(name()="ID" or name()="reason")]' PASSING a.n COLUMNS 
                                t VARCHAR2(128) PATH 'name()', 
                                v VARCHAR2(4000) PATH 'text()') b
                    ORDER BY i,id,reason,lower(t)) LOOP
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
        lst(key) := regexp_replace(lst(key),'(\d+)(,\1)+','\1');
        xml := xml.appendChildXML('/ROWSET',xmltype(key)
            .appendChildXML('/R',XMLTYPE('<C>'||substr(regexp_replace(lst(key),'(.{80})','\1'||chr(10)),1,3900)||'</C>'))
            .appendChildXML('/R',XMLTYPE('<PS>'||ps(key)||'</PS>'))
            .appendChildXML('/R',XMLTYPE('<L>'||fl(key)||chr(10)||ll(key)||'</L>'))
            .appendChildXML('/R',XMLTYPE('<CNT>'||cnt(key)||'</CNT>')));
        key := lst.next(key);
    END LOOP;
    OPEN :c FOR
        SELECT *
        FROM  XMLTABLE('/ROWSET/R' PASSING xml 
              COLUMNS "Count" INT PATH 'CNT',
                      PLAN_HASH INT PATH 'P',
                      PARSES INT PATH 'PS',
                      Reason  VARCHAR2(2000) PATH 'R',
                      MEMO VARCHAR2(4000) PATH 'M',
                      LOAD_TIME VARCHAR2(80) PATH 'L',
                      EXAMPLE_CURSORS VARCHAR(2000) PATH 'C')
        ORDER BY 1 DESC,REASON;
END;
/

set rowsep - colsep |
print c