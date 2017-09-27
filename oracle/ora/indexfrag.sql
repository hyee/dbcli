/*[[
   Show index fragmentation(with sys_op_lbid). Usage: @@NAME {<index_name> [table_partition] [sample_rows]} [-f"<filter>"]
   Refer to https://jonathanlewis.wordpress.com/index-sizing/
    --[[
        &V3: default={1000000}
        &FILTER: default={1=1} f={}
    --]]
]]*/
VAR O REFCURSOR Many blocks for small values of 'rows/block' means fragmentation, and rebuild/coalesce is recommended;
ora _find_object "&V1" 1

DECLARE
    v_obj INT;
    v_owner VARCHAR2(30);
    v_tab   VARCHAR2(30);
    v_ind   VARCHAR2(30);
    v_part  VARCHAR2(30):=UPPER(:V2);
    v_typ   VARCHAR2(30);
    v_sql VARCHAR2(32767):=q'[
        SELECT MAX(DECODE(MOD(r, 7), 1, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 1, b)) blocks,'|' "*",
               MAX(DECODE(MOD(r, 7), 2, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 2, b)) blocks,'|' "*",
               MAX(DECODE(MOD(r, 7), 3, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 3, b)) blocks,'|' "*",
               MAX(DECODE(MOD(r, 7), 4, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 4, b)) blocks,'|' "*",
               MAX(DECODE(MOD(r, 7), 5, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 5, b)) blocks,'|' "*",
               MAX(DECODE(MOD(r, 7), 6, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 6, b)) blocks,'|' "*",
               MAX(DECODE(MOD(r, 7), 0, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 0, b)) blocks
        FROM   (SELECT row_number() OVER(ORDER BY p) r, p, COUNT(*) b
                FROM   (SELECT /*+
                                 cursor_sharing_exact
                                 dynamic_sampling(0)
                                 no_monitoring
                                 no_expand
                                 index_ffs(t1,@indx)
                                 noparallel_index(t1,@indx)
                                */ COUNT(*) AS p
                          FROM   @tab t1
                          WHERE  (:1=0 or ROWNUM <= :1) AND &filter
                          GROUP  BY sys_op_lbid(@ind_id, 'L', t1.rowid))
                 GROUP  BY p)
        GROUP  BY CEIL(r / 7)
        ORDER  BY CEIL(r / 7)]';
BEGIN
    v_owner := :object_owner;
    v_obj   := :object_id;
    v_ind   := :object_name;

    SELECT MAX(OWNER),MAX(OBJECT_NAME),MAX(REGEXP_SUBSTR(OBJECT_TYPE,'[^ ]+$'))
    INTO v_owner,v_tab,v_typ
    FROM  ALL_OBJECTS
    WHERE (OWNER,OBJECT_NAME) IN(SELECT TABLE_OWNER,TABLE_NAME FROM ALL_INDEXES WHERE OWNER=v_owner AND INDEX_NAME=v_ind)
    AND   NVL(SUBOBJECT_NAME,' ')=NVL(v_part,' ');

    IF v_tab IS NULL THEN
        OPEN :O FOR SELECT 'Cannot find target index in current schema!' message from dual;
    ELSE
        v_sql := replace(v_sql,'@tab',v_owner||'.'||v_tab||CASE WHEN v_part IS NOT NULL THEN ' '||v_typ||'('||v_part||')' END);
        v_sql := replace(v_sql,'@indx',v_ind);
        v_sql := replace(v_sql,'@ind_id',v_obj);
        OPEN :O FOR v_sql using :V3,:V3;
    END IF;
END;
/