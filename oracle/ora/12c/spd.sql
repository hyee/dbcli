/*[[Show column usage and SQL plan directives on target table. Usage: @@NAME [<owner>.]<object_name>
    --[[
        @CHECK_ACCESSS_OBJ: dba_sql_plan_dir_objects={1}, default={0}
    --]]
]]*/
SET FEED OFF VERIFY OFF
ora _find_object &V1
VAR Text clob
VAR cur REFCURSOR;
DECLARE
    c sys_refcursor;
BEGIN
    :Text:=DBMS_STATS.REPORT_COL_USAGE(:object_owner,:object_name);
    $IF &CHECK_ACCESSS_OBJ=1 $THEN
    OPEN c for
        SELECT /*+leading(o d) use_nl(d) merge(d)*/
                 TO_CHAR(d.directive_id) dir_id,
                 d.ENABLED,
                 d.state,
                 extract(d.notes, '/spd_note/internal_state/text()') i_state,
                 d.AUTO_DROP,
                 d.reason,
                 extract(d.notes, '/spd_note/spd_text/text()') AS spd_text,
                 nvl(LAST_MODIFIED, CREATED) LAST_MDF,
                 LAST_USED
        FROM   (SELECT DISTINCT directive_id
                FROM   dba_sql_plan_dir_objects o
                WHERE  o.owner = '&object_owner'
                AND    o.object_name = '&object_name'
                AND    object_type in('COLUMN','TABLE')) o,
               dba_sql_plan_directives d
        WHERE  d.directive_id = o.directive_id
        ORDER  BY reason;
    $END
    :cur := c;
END;
/
PRINT Text
PRINT CUR
