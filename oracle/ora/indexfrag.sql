/*[[
    Show index fragmentation(with sys_op_lbid). Usage: @@NAME {<index_name> [table_partition] [0|<sample_rows>]} [-f"<filter>"]
    Refer to https://jonathanlewis.wordpress.com/index-sizing/
    
    Sample Output:
    ==============
    ORCL> ORA INDEXFRAG i_obj1                                                                                                                    
    Many blocks for small values of 'rows/block' means fragmentation, and rebuild/coalesce is recommended:
    ======================================================================================================
    ROWS/BLOCK BLOCKS|ROWS/BLOCK BLOCKS|ROWS/BLOCK BLOCKS|ROWS/BLOCK BLOCKS|ROWS/BLOCK BLOCKS|ROWS/BLOCK BLOCKS|ROWS/BLOCK BLOCKS
    ---------- ------+---------- ------+---------- ------+---------- ------+---------- ------+---------- ------+---------- ------
            13      1|        28      1|        49      1|        58      1|        84      1|       108      1|       144      1
           154      1|       164      1|       180      1|       181      1|       182      1|       183      1|       185     77
           186   1956|       187      7|       188      9|       189     11|       190      3|       191      5|       192     28
           193     24|       194     55|       195     11|       196      3|       198      5|       199      3|       200    345
           201      6|       203      4|       204      1|       205      1|       206      1|       208      1|       209      3
           211      3|       212      1|       214      1|       215      2|       216      1|       217      1|       218      1
           219      1|       220      1|       221      1|       222      1|       225      2|       228      2|       231      3
           233      2|       234      2|       236      2|       239      1|       241      2|       243      2|       244      1
           248      1|       250      2|       251      1|       252      2|       258      1|       259      1|       260      1
           261      1|       265      3|       266      1|       267      2|       269      1|       270      1|       272      1
           277      1|       281      1|       282      1|       283      1|       284      1|       285      1|       288      1
           289      1|       290      4|       292      1|       293      1|       294      1|       296      1|       297      1
           298      2|       299      1|       300      4|       302      1|       303      1|       312      1|       314      1
           318      2|       327      2|       329      2|       330      1|       331      1|       332      2|       333      2
           334      1|       336      2|       337      2|       338      1|       339      1|       340      2|       341      1
           342      1|       343      1|       344      1|       345      1|       346      1|       347      1|       348      2
           352      1|       353      1|       355      1|       356      1|       359      1|       361      1|       363      1
           364      1|       366      1|       369      1|       371      1|       373      1|       376      1|       377      1
           378      1|       379     21|       380      8|       381      1|       392      1|       393      1|       402      1
           408      1|       409      1|       410      5|       411      3|       413      1|       420      1|       426      1

    --[[
        &V3: default={1000000}
        &FILTER: default={1=1} f={}
        @ARGS: 1
    --]]
]]*/
VAR O REFCURSOR Many blocks for small values of 'rows/block' means fragmentation, and rebuild/coalesce is recommended;
ora _find_object "&V1" 1
set feed off

DECLARE
    v_obj INT;
    v_owner VARCHAR2(128);
    v_tab   VARCHAR2(128);
    v_ind   VARCHAR2(128);
    v_part  VARCHAR2(128):=UPPER(:V2);
    v_typ   VARCHAR2(128);
    v_sql VARCHAR2(32767):=q'[
        SELECT MAX(DECODE(MOD(r, 7), 1, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 1, b)) blocks,'|' "|",
               MAX(DECODE(MOD(r, 7), 2, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 2, b)) blocks,'|' "|",
               MAX(DECODE(MOD(r, 7), 3, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 3, b)) blocks,'|' "|",
               MAX(DECODE(MOD(r, 7), 4, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 4, b)) blocks,'|' "|",
               MAX(DECODE(MOD(r, 7), 5, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 5, b)) blocks,'|' "|",
               MAX(DECODE(MOD(r, 7), 6, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 6, b)) blocks,'|' "|",
               MAX(DECODE(MOD(r, 7), 0, p)) "ROWS/BLOCK", MAX(DECODE(MOD(r, 7), 0, b)) blocks
        FROM   (SELECT row_number() OVER(ORDER BY p) r, p, COUNT(*) b
                FROM   (SELECT /*+
                                 cursor_sharing_exact
                                 dynamic_sampling(0)
                                 no_monitoring
                                 no_expand
                                 index_ffs(t1,@indx)
                                 no_parallel_index(t1,@indx)
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