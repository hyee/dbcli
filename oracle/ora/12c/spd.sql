/*[[
    Show column usage and SQL plan directives of a target object. Usage: @@NAME {[<owner>.]<object_name>[.<partition>]} | <SQL Id> | <directive id>

    The argument is resolved by "ora _find_object", so a bare table name is
    looked up in the current schema and "owner.table.partition" is accepted.

        <object_name> : CUR1 gets the dbms_stats.report_col_usage text report,
                        CUR2 gets the plan directives collected for the object
                        (only when dba_sql_plan_dir_objects is readable).
        <SQL Id>      : a sql_id is not an object, so CUR1 stays empty and
                        CUR2 lists the directives of that statement.
        <numeric>     : taken as a directive id; CUR1 dumps that single
                        dba_sql_plan_directives row and CUR2 stays empty.

    Run "exec dbms_spd.flush_sql_plan_directive" to flush the SPD statistics
    that are kept in memory into the dictionary views.

    Sample Output:
    ==============
    REPORT
    -------------------------------------------------------------------------------
    LEGEND:
    .......
    EQ         : Used in single table EQuality predicate
    RANGE      : Used in single table RANGE predicate
    LIKE       : Used in single table LIKE predicate
    NULL       : Used in single table is (not) NULL predicate
    EQ_JOIN    : Used in EQuality JOIN predicate
    NONEQ_JOIN : Used in NON EQuality JOIN predicate
    FILTER     : Used in single table FILTER predicate
    JOIN       : Used in JOIN predicate
    GROUP_BY   : Used in GROUP BY expression
    ...............................................................................

    ###############################################################################

    COLUMN USAGE REPORT FOR SSB_EXA.LINEORDER
    .........................................
    1. LO_CUSTKEY                          : EQ EQ_JOIN
    8. LO_SUPPKEY                          : EQ RANGE EQ_JOIN
    9. LO_TAX                              : EQ
    10. SYS_STUJ36XMDV785HVKOD$O7AT13N     : EQ
    11. (LO_ORDERDATE)                     : GROUP_BY
    12. (LO_PARTKEY, LO_ORDERDATE)         : GROUP_BY
         LO_SUPPKEY, LO_ORDERDATE)         : GROUP_BY
    ###############################################################################

    E=equality_predicates_only | C=simple_column_predicates_only | J=index_access_by_join_predicates | F=filter_on_joining_object:
    ==============================================================================================================================
    DIRECTIVE_ID         OWNER   OBJECT_NAME ENABLED STATE      AUTO_DROP TYPE                     REASON                           NOTES
    -------------------- ------- ----------- ------- ---------- --------- ----------------------- -------------------------------- ----------------------------------------------------------
    147738779520430212   SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.CUSTOMER) / (SSB_EXA.DATE_DIM[D_MONTH,D_YEAR]) /
    657765050449506494   SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.DATE_DIM[D_MONTH,D_YEAR]) / (SSB_EXA.LINEORDER) /
    12494119925691582800 SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.CUSTOMER[C_NATION]) / (SSB_EXA.DATE_DIM[D_MONTH,D
    1206655006907814904  SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.CUSTOMER) / (SSB_EXA.DATE_DIM[D_MONTH,D_YEAR]) /
    1213500342159162928  SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.DATE_DIM[D_MONTH,D_YEAR]) / (SSB_EXA.LINEORDER) /
    2138964446153603234  SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.CUSTOMER[C_NATION,C_REGION]) / (SSB_EXA.DATE_DIM[
    2649271532294943916  SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.CUSTOMER) / (SSB_EXA.DATE_DIM[D_MONTH,D_YEAR]) /
    3596048118434922344  SSB_EXA LINEORDER   YES     USABLE     YES       DYNAMIC_SAMPLING        GROUP BY CARDINALITY MISESTIMATE (SSB_EXA.CUSTOMER[C_CITY,C_NATION]) / (SSB_EXA.DATE_DIM[D_

    --[[
        @CHECK_ACCESSS_OBJ: dba_sql_plan_dir_objects={1}, default={0}
        @CHECK_ACCESSS_COL: sys.col_usage$={1}, default={0}
        @ARGS : 1
    --]]
]]*/
set feed off verify on
ora _find_object &V1 1
VAR Text clob
VAR cur1 REFCURSOR;
VAR cur2 REFCURSOR "E=equality_predicates_only | C=simple_column_predicates_only | J=index_access_by_join_predicates | F=filter_on_joining_object";
DECLARE
    did INT := regexp_substr(:V1, '^\d+$');
    c1  sys_refcursor;
    c2  sys_refcursor;
BEGIN
    IF did IS NOT NULL THEN
        OPEN c1 FOR
            WITH o1 AS
             (SELECT directive_id dir_id,
                     owner,
                     object_name,
                     nvl(owner, 'SQL') || '.' || object_name obj,
                     subobject_name,
                     decode(extractvalue(notes, '/obj_note/equality_predicates_only'), 'YES', 'E') alleq,
                     decode(extractvalue(notes, '/obj_note/simple_column_predicates_only'), 'YES', 'C') allcols,
                     decode(extractvalue(notes, '/obj_note/index_access_by_join_predicates'), 'YES', 'J') nljnix,
                     decode(extractvalue(notes, '/obj_note/filter_on_joining_object'), 'YES', 'F') filter
              FROM   sys.dba_sql_plan_dir_objects
              WHERE  directive_id = did),
            o2 AS
             (SELECT dir_id,
                     owner,
                     object_name,
                     listagg(op || '(' || obj || nvl2(cols, '[' || cols || ']', '') || ')', ' / ') WITHIN GROUP(ORDER BY obj) notes
              FROM   (SELECT dir_id,
                             owner,
                             object_name,
                             obj,
                             listagg(alleq || allcols || nljnix || filter, '') WITHIN GROUP(ORDER BY 1) op,
                             listagg(subobject_name, ',') WITHIN GROUP(ORDER BY subobject_name) cols
                      FROM   o1
                      GROUP  BY dir_id, owner, object_name, obj)
              GROUP  BY dir_id, owner, object_name)
            SELECT to_char(d.directive_id) directive_id,
                   o2.owner,
                   o2.object_name,
                   d.enabled,
                   d.state,
                   extract(d.notes, '/spd_note/internal_state/text()') internal_state,
                   d.auto_drop,
                   d.type,
                   d.reason,
                   o2.notes,
                   nvl(d.last_modified, d.created) last_mdf,
                   d.last_used
            FROM   o2, dba_sql_plan_directives d
            WHERE  d.directive_id = o2.dir_id
            AND    d.directive_id = did
            ORDER  BY d.reason;
    ELSE
    $IF 1=1 $THEN
        IF '&object_name' IS NOT NULL THEN
            OPEN c1 FOR SELECT dbms_stats.report_col_usage('&object_owner', '&object_name') report FROM dual;
        END IF;
    $ELSE
        OPEN c1 FOR
        SELECT /*+ ordered use_nl(o c cu h) index(u i_user1) index(o i_obj1)
               index(ci_obj#) index(cu i_col_usage$)
               index(h i_hh_obj#_intcol#) */
               c.name col_name,
               cu.equality_preds eq_preds,
               cu.equijoin_preds eqj_preds,
               cu.nonequijoin_preds no_eq_preds,
               cu.range_preds,
               cu.like_preds,
               cu.null_preds,
               c.default$ default#,
               h.row_cnt rows#,
               h.null_cnt nulls,
               h.bucket_cnt buckets,
               round((t.rowcnt - h.null_cnt) / greatest(h.distcnt, 1), 2) card
        FROM   sys.user$ u,
               sys.obj$ o,
               sys.tab$ t,
               sys.col$ c,
               sys.col_usage$ cu,
               sys.hist_head$ h
        WHERE  u.name = '&object_owner'
        AND    o.owner# = u.user#
        AND    o.type# = 2
        AND    o.obj# = &object_id
        AND    o.obj# = t.obj#
        AND    o.obj# = c.obj#
        AND    c.obj# = cu.obj#
        AND    c.intcol# = cu.intcol#
        AND    c.obj# = h.obj#(+)
        AND    c.intcol# = h.intcol#(+);
    $END
    $IF &CHECK_ACCESSS_OBJ=1 $THEN
        OPEN c2 FOR
            WITH o AS
             (SELECT /*+no_expand materialize ORDERED_PREDICATES opt_estimate(query_block rows=2)*/ DISTINCT directive_id dir_id, owner, object_name
              FROM   dba_sql_plan_dir_objects o
              WHERE  object_name IN ('&object_name', '&V1')
              AND    nvl(owner, ' ') = nvl('&object_owner', ' ')
              AND    object_type IN ('COLUMN', 'TABLE', 'SQL STATEMENT')),
            o1 AS
             (SELECT /*+use_nl(o1) no_expand push_pred(o1) no_merge(o1)*/ *
              FROM   o,
                     LATERAL(SELECT nvl(owner, 'SQL') || '.' || object_name obj,
                                    subobject_name,
                                    decode(extractvalue(notes, '/obj_note/equality_predicates_only'), 'YES', 'E') alleq,
                                    decode(extractvalue(notes, '/obj_note/simple_column_predicates_only'), 'YES', 'C') allcols,
                                    decode(extractvalue(notes, '/obj_note/index_access_by_join_predicates'), 'YES', 'J') nljnix,
                                    decode(extractvalue(notes, '/obj_note/filter_on_joining_object'), 'YES', 'F') filter
                             FROM   sys.dba_sql_plan_dir_objects o1
                             WHERE  directive_id = o.dir_id) o1),
            o2 AS
             (SELECT dir_id,
                     owner,
                     object_name,
                     listagg(op || '(' || obj || nvl2(cols, '[' || cols || ']', '') || ')', ' / ') WITHIN GROUP(ORDER BY obj) notes
              FROM   (SELECT dir_id,
                             owner,
                             object_name,
                             obj,
                             listagg(alleq || allcols || nljnix || filter, '') WITHIN GROUP(ORDER BY 1) op,
                             listagg(subobject_name, ',') WITHIN GROUP(ORDER BY subobject_name) cols
                      FROM   o1
                      GROUP  BY dir_id, owner, object_name, obj)
              GROUP  BY dir_id, owner, object_name)
            SELECT /*+leading(o2 d) use_nl(d) merge(d)*/
                   to_char(d.directive_id) directive_id,
                   o2.owner,
                   o2.object_name,
                   d.enabled,
                   d.state,
                   extract(d.notes, '/spd_note/internal_state/text()') "Internal|State",
                   d.auto_drop "Auto|Drop",
                   d.type,
                   d.reason,
                   o2.notes,
                   nvl(d.last_modified, d.created) last_mdf,
                   d.last_used
            FROM   o2, dba_sql_plan_directives d
            WHERE  d.directive_id = o2.dir_id
            ORDER  BY d.reason;
    $END
    END IF;
    :cur1 := c1;
    :cur2 := c2;
END;
/
