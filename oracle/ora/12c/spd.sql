/*[[Show column usage and SQL plan directives on target table. Usage: @@NAME [<owner>.]<object_name>[.<partition>]
    --[[
        @CHECK_ACCESSS_OBJ: dba_sql_plan_dir_objects={1}, default={0}
        @CHECK_ACCESSS_COL: sys.col_usage$={1},default={0}
    --]]
]]*/
SET FEED OFF
ora _find_object &V1
VAR Text clob
VAR cur1 REFCURSOR;
VAR cur2 REFCURSOR;
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
            SELECT /*+leading(o d) use_nl(d) merge(d)*/
                     TO_CHAR(d.directive_id) dir_id,
                     owner,object_name,
                     d.ENABLED,
                     d.state,
                     extract(d.notes, '/spd_note/internal_state/text()') i_state,
                     d.AUTO_DROP,
                     d.reason,
                     extract(d.notes, '/spd_note/spd_text/text()') AS spd_text,
                     nvl(LAST_MODIFIED, CREATED) LAST_MDF,
                     LAST_USED
            FROM   (SELECT /*+no_expand*/ DISTINCT directive_id,owner,object_name
                    FROM   dba_sql_plan_dir_objects o
                    WHERE  o.owner = '&object_owner'
                    AND    o.object_name = '&object_name'
                    AND    object_type in('COLUMN','TABLE')) o,
                   dba_sql_plan_directives d
            WHERE  d.directive_id = o.directive_id
            ORDER  BY reason;
    $END
    :cur1 := c1;
    :cur2 := c2;
END;
/
