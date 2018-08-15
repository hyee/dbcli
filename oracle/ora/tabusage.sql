/*[[Report table usages. Usage: @@NAME [owner.]<table_name> 
    Parameters that impacts column tracking and SPD tracking: _column_tracking_level,_dml_monitoring_enabled
    Parameters that impacts index usage tracking: _iut_enable,_iut_max_entries,_iut_stat_collection_type,
	--[[
		@check_access_usage: SYS.COL_USAGE$/SYS.COL_GROUP_USAGE$={2} SYS.COL_USAGE$={1} default={0}
		@check_access_index: dba_index_usage={1} default={0}
		@check_access_mdf: sys.dba_tab_modifications={sys.dba_tab_modifications} sys.all_tab_modifications={sys.all_tab_modifications}
	--]]
]]*/
SET FEED OFF VERIFY ON BYPASSEMPTYRS ON
ora _find_object &V1
BEGIN
	IF nvl('&object_type','x') not like 'TABLE%' THEN
		raise_application_error(-20001,'Invalid table name: '||nvl(:V1,'no input parameter'));
	END IF;
END;
/
COL EXECS,ACCESSES,CARD,AVG_R_1K+,AVG_RTN,SAMPLE_SIZE,NUM_DISTINCT,STATS_VALUE,INSERTS,UPDATES,DELETES,EQ_PREDS,EQJ_PREDS,NO_EQ_PREDS,RANGE_PREDS,LIKE_PREDS,NULL_PREDS FORMAT TMB
VAR cur00 REFCURSOR "Table Modifications Since Last Analyzed"
VAR cur01 REFCURSOR "Segment Statistics"
VAR cur1 REFCURSOR "Column Usages"
VAR cur2 REFCURSOR "Column Group Usage [used for dbms_stats.create_extended_stats('&object_owner','&object_name')]"
VAR cur3 REFCURSOR "Index Usage(R%=access percentage of returned rows from x to y)"
PRO &OBJECT_TYPE &OBJECT_OWNER..&OBJECT_NAME
PRO ***********************************************
pro 
DECLARE
    ca SYS_REFCURSOR;
    cb SYS_REFCURSOR;
    c1 SYS_REFCURSOR;
    c2 SYS_REFCURSOR;
    c3 SYS_REFCURSOR;
BEGIN
	OPEN ca FOR
		select count(1) segments,
		       sum(INSERTS) INSERTS,
		       sum(UPDATES) UPDATES,
		       sum(DELETES) DELETES,
		       count(decode(TRUNCATED,'YES',1)) TRUNCATES,
		       max(TIMESTAMP) LAST_TIMESTAMP
		FROM  &check_access_mdf
		WHERE TABLE_OWNER=:OBJECT_OWNER
		AND   TABLE_NAME=:OBJECT_NAME;
	OPEN cb FOR
		SELECT OWNER,OBJECT_NAME,SEGMENT_TYPE,COUNT(DISTINCT DATAOBJ#) SEGMENTS,STATISTIC_NAME,SUM(VALUE) STATS_VALUE 
		FROM (
			SELECT DISTINCT SEGMENT_OWNER OWNER,SEGMENT_NAME OBJECT_NAME,
			       REGEXP_SUBSTR(SEGMENT_TYPE,'^[^ ]+') SEGMENT_TYPE
			FROM  TABLE(DBMS_SPACE.OBJECT_DEPENDENT_SEGMENTS(:OBJECT_OWNER,:OBJECT_NAME,NULL,1))
		) A NATURAL JOIN GV$SEGMENT_STATISTICS B
		GROUP BY OWNER,OBJECT_NAME,SEGMENT_TYPE,STATISTIC_NAME
		ORDER BY 1,2,3,UPPER(STATISTIC_NAME); 
    $IF &check_access_usage=0 $THEN
    OPEN c1 FOR
        SELECT DBMS_STATS.REPORT_COL_USAGE('&object_owner', '&object_name') report FROM dual;
    $ELSE
    OPEN c1 FOR
        SELECT /*+ ordered use_nl(o c cu) no_expand*/
                 c.INTERNAL_COLUMN_ID intcol#,
                 C.column_name COL_NAME,
                 CU.EQUALITY_PREDS EQ_PREDS,
                 CU.EQUIJOIN_PREDS EQJ_PREDS,
                 CU.NONEQUIJOIN_PREDS NO_EQ_PREDS,
                 CU.RANGE_PREDS,
                 CU.LIKE_PREDS,
                 CU.NULL_PREDS,
                 c.histogram,
                 c.NUM_BUCKETS buckets,
                 c.sample_size,
                 c.NUM_DISTINCT,
                 c.NUM_NULLS,
                 ROUND(((SELECT rowcnt FROM sys.tab$ WHERE obj# = o.object_id) - c.num_nulls) / GREATEST(c.NUM_DISTINCT, 1), 2) card,
                 C.DATA_DEFAULT "DEFAULT",
                 c.last_analyzed
                FROM   dba_objects o, dba_tab_cols c, SYS.COL_USAGE$ CU
                WHERE  o.owner = c.owner
                AND    o.object_name = c.table_name
                AND    cu.obj#(+) = &object_id
                AND    c.INTERNAL_COLUMN_ID =cu.intcol# (+)
                AND    o.object_id = &object_id
                AND    o.object_name = '&object_name'
                AND    o.owner       = '&object_owner'
                AND    (cu.obj# is not null or c.column_name like 'SYS\_%' escape '\')
                ORDER  BY 1;
    $END
    $IF &check_access_usage=2 $THEN
    OPEN c2 FOR
    	SELECT COLS,
    		   REGEXP_SUBSTR(cols_and_cards,'[^//]+',1,1) col_names,
    		   REGEXP_SUBSTR(cols_and_cards,'[^//]+',1,2) cards,
    		   USAGES，
    		   (SELECT distinct sys.stragg(e.extension_name||' ') over() 
		        FROM   dba_tab_cols c, dba_stat_extensions e
		        WHERE  c.owner = '&object_owner'
		        AND    c.table_name = '&object_name'
		        AND    INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ',') > 0
		        AND    e.owner = c.owner
		        AND    e.table_name = c.table_name
		        AND    instr(e.extension, '"' || c.column_name || '"') > 0
		        AND    LENGTH(extension)-LENGTH(REPLACE(extension,','))=cu.col_count-1
		        GROUP BY e.extension_name
		        HAVING COUNT(1)=cu.col_count) extension_name
    	FROM (
			SELECT CU.COLS,
			       LENGTH(cu.cols)-LENGTH(REPLACE(cu.cols,','))+1 col_count,
					(SELECT '('||listagg(C.COLUMN_NAME,',') 
								WITHIN GROUP(ORDER BY INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ','))||')/('||--
		                    listagg(ROUND((SELECT rowcnt- c.num_nulls FROM sys.tab$ WHERE obj# = cu.obj#) / GREATEST(c.NUM_DISTINCT, 1), 2) ,', ') 
		                    	WITHIN GROUP(ORDER BY INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ',')) ||')'
			        FROM   dba_tab_cols c
			        WHERE  c.owner = '&object_owner'
			        AND    c.table_name = '&object_name'
			        AND    INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ',') > 0) cols_and_cards,
			       CASE
			           WHEN BITAND(CU.FLAGS, 1) = 1 THEN 'FILTER '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 2) = 2 THEN 'JOIN '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 4) = 4 THEN 'GROUP_BY '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 8) = 8 THEN 'EXT_STATS_CREATED '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 16) = 16 THEN 'SPD '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 16) = 16 THEN 'COL_SEED '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 64) = 64 THEN 'DROPPED '
			       END USAGES,
			       CU.FLAGS USAGEFLG
			FROM   SYS.COL_GROUP_USAGE$ CU
			WHERE  OBJ#=&object_id) cu;
    $END

    $IF &check_access_index=1 $THEN
   	OPEN c3 for 
		SELECT a.owner,
		       a.index_name,
		       (SELECT listagg(column_name || NULLIF(' ' || DESCEND, ' ASC'), ',') WITHIN GROUP(ORDER BY COLUMN_POSITION)
		        FROM   dba_ind_columns c
		        WHERE  c.index_owner = a.owner
		        AND    c.index_name = a.index_name) cols,
		       TOTAL_EXEC_COUNT EXECS,
		       TOTAL_ACCESS_COUNT accesses,
		       round(a.NUM_ROWS / GREATEST(a.DISTINCT_KEYS, 1), 2) card,
		       round(TOTAL_ROWS_RETURNED / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) avg_rtn,
		       ROUND(BUCKET_0_ACCESS_COUNT * 100 / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) "R_0 %",
		       ROUND(BUCKET_1_ACCESS_COUNT * 100 / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) "R_1 %",
		       ROUND(BUCKET_2_10_ACCESS_COUNT * 100 / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) "R_2_10 %",
		       ROUND(BUCKET_11_100_ACCESS_COUNT * 100 / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) "R_11_100 %",
		       ROUND(BUCKET_101_1000_ACCESS_COUNT * 100 / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) "R_101_1K %",
		       ROUND(BUCKET_1000_PLUS_ACCESS_COUNT * 100 / NULLIF(TOTAL_ACCESS_COUNT, 0), 2) "R_1K+ %",
		       ROUND(BUCKET_1000_PLUS_ROWS_RETURNED / nullif(BUCKET_1000_PLUS_ACCESS_COUNT, 0), 2) "AVG_R_1K+"
		FROM   dba_indexes a, dba_index_usage b
		WHERE  a.owner = b.owner(+)
		AND    a.index_name = b.name(+)
		AND    a.table_owner = '&object_owner'
		AND    a.table_name = '&object_name';
    $END
    :cur00 := ca;
    :cur01 := cb;
    :cur1  := c1;
    :cur2  := c2;
    :cur3  := c3;
END;
/