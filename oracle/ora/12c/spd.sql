/*[[Show column usage and SQL plan directives on target table. Usage: @@NAME [<owner>.]<object_name>[.<partition>]
    --[[
        @CHECK_ACCESSS_OBJ: dba_sql_plan_dir_objects={1}, default={0}
        @CHECK_ACCESSS_COL: sys.col_usage$={1},default={0}
    --]]
]]*/
SET FEED OFF VERIFY ON
ora _find_object &V1
VAR Text clob
VAR cur1 REFCURSOR;
VAR cur2 REFCURSOR "E=equality_predicates_only | C=simple_column_predicates_only | J=index_access_by_join_predicates | F=filter_on_joining_object";
DECLARE
    c1 sys_refcursor;
    c2 sys_refcursor;
BEGIN
    $IF 1=1 $THEN 
        OPEN c1 FOR SELECT DBMS_STATS.REPORT_COL_USAGE('&object_owner','&object_name') report from dual;
    $ELSE
        OPEN c1 FOR 
        SELECT /*+ ordered use_nl(o c cu h) index(u i_user1) index(o i_obj1)
               index(ci_obj#) index(cu i_col_usage$)
               index(h i_hh_obj#_intcol#) */
               C.NAME COL_NAME,
               CU.EQUALITY_PREDS EQ_PREDS,
               CU.EQUIJOIN_PREDS EQJ_PREDS,
               CU.NONEQUIJOIN_PREDS NO_EQ_PREDS,
               CU.RANGE_PREDS,
               CU.LIKE_PREDS,
               CU.NULL_PREDS,
               C.DEFAULT$ default#,
               h.ROW_CNT rows#,
               h.NULL_CNT nulls,
               H.BUCKET_CNT BUCKETS,
               round((T.ROWCNT - H.NULL_CNT) / GREATEST(H.DISTCNT, 1),2) CARD
          FROM SYS.USER$      U,
               SYS.OBJ$       O,
               SYS.TAB$       T,
               SYS.COL$       C,
               SYS.COL_USAGE$ CU,
               SYS.HIST_HEAD$ H
         WHERE U.NAME =  '&object_owner'
           AND O.OWNER# = U.USER#
           AND O.TYPE# = 2
           AND O.obj# = &object_id
           AND O.OBJ# = T.OBJ#
           AND O.OBJ# = C.OBJ#
           AND C.OBJ# = CU.OBJ#
           AND C.INTCOL# = CU.INTCOL#
           AND C.OBJ# = H.OBJ#(+)
           AND C.INTCOL# = H.INTCOL#(+);
    $END
    $IF &CHECK_ACCESSS_OBJ=1 $THEN
        OPEN c2 for
            WITH o AS
             (SELECT /*+no_expand materialize ORDERED_PREDICATES*/
              DISTINCT directive_id dir_id, owner, object_name
              FROM   dba_sql_plan_dir_objects o
              WHERE  object_name = '&object_name'
              AND    object_type IN ('COLUMN', 'TABLE')),
            o1 AS
             (SELECT /*+parallel(4)*/*
              FROM   o,
                     lateral((SELECT OWNER || '.' || OBJECT_NAME obj,
                                    SUBOBJECT_NAME,
                                    DECODE(EXTRACTVALUE(NOTES, '/obj_note/equality_predicates_only'), 'YES', 'E') ALLEQ,
                                    DECODE(EXTRACTVALUE(NOTES, '/obj_note/simple_column_predicates_only'), 'YES', 'C') ALLCOLS,
                                    DECODE(EXTRACTVALUE(NOTES, '/obj_note/index_access_by_join_predicates'), 'YES', 'J') NLJNIX,
                                    DECODE(EXTRACTVALUE(NOTES, '/obj_note/filter_on_joining_object'), 'YES', 'F') FILTER
                             FROM   SYS.DBA_SQL_PLAN_DIR_OBJECTS
                             WHERE  DIRECTIVE_ID = o.dir_id)) o1
              WHERE  o.owner = '&object_owner'),
            o2 AS
             (SELECT dir_id,
                     OWNER,
                     OBJECT_NAME,
                     listagg(op || '(' || obj  || nvl2(cols, '[' || cols || ']', '')|| ')', ' / ') WITHIN GROUP(ORDER BY obj) notes
              FROM   (SELECT dir_id,
                             OWNER,
                             OBJECT_NAME,
                             obj,
                             listagg(ALLEQ||ALLCOLS||NLJNIX||FILTER,'') within group(order by 1) op,
                             listagg(SUBOBJECT_NAME, ',') within GROUP(ORDER BY SUBOBJECT_NAME) COLS
                      FROM   o1
                      GROUP  BY dir_id, OWNER, OBJECT_NAME, obj)
              GROUP  BY dir_id, OWNER, OBJECT_NAME)
            SELECT /*+leading(o2 d) use_nl(d) merge(d)*/
                     TO_CHAR(d.directive_id) directive_id,
                     o2.owner,
                     o2.object_name,
                     d.ENABLED,
                     d.state,
                     d.AUTO_DROP,
                     d.reason,
                     o2.notes,
                     nvl(d.LAST_MODIFIED, d.CREATED) LAST_MDF,
                     d.LAST_USED
            FROM   o2, dba_sql_plan_directives d
            WHERE  d.directive_id = o2.dir_id
            ORDER  BY d.reason;
    $END
    :cur1 := c1;
    :cur2 := c2;
END;
/
