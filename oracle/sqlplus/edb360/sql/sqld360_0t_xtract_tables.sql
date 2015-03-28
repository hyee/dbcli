-- setup
SET VER OFF; 
SET FEED OFF; 
SET ECHO OFF;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') sqld360_time_stamp FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET HEA OFF;
SET TERM ON;

-- log
SPO &&sqld360_log..txt APP;
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
PRO &&hh_mm_ss.
PRO Extracting table list

-- double single quoted, used as SQL string
VAR tables_list CLOB;    
-- single quoted, used in straight SQL
VAR tables_list_s CLOB; 
-- number of tables, needed for second level reporting
VAR num_tables NUMBER;

EXEC :tables_list := NULL;
EXEC :tables_list_s := NULL;
EXEC :num_tables := 0;
-- get list of tables from execution plan
-- format (('owner', 'table_name'), (), ()...)
DECLARE
  l_pair VARCHAR2(32767);
BEGIN
  DBMS_LOB.CREATETEMPORARY(:tables_list, TRUE, DBMS_LOB.SESSION);
  DBMS_LOB.CREATETEMPORARY(:tables_list_s, TRUE, DBMS_LOB.SESSION);
  FOR i IN (WITH object AS (
  	    SELECT /*+ MATERIALIZE */
  	           object_owner owner, object_name name
  	      FROM gv$sql_plan
  	     WHERE inst_id IN (SELECT inst_id FROM gv$instance)
  	       AND sql_id = '&&sqld360_sqlid.'
  	       AND object_owner IS NOT NULL
  	       AND object_name IS NOT NULL
  	     UNION
  	    SELECT object_owner owner, object_name name
  	      FROM dba_hist_sql_plan
  	     WHERE '&&diagnostics_pack.' = 'Y'
  	       AND &&sqld360_dbid. = dbid
  	       AND sql_id = '&&sqld360_sqlid.'
  	       AND object_owner IS NOT NULL
  	       AND object_name IS NOT NULL
  	     UNION
  	    SELECT o.owner, o.object_name name
  	      FROM plan_table pt,
  	           dba_objects o
  	     WHERE '&&diagnostics_pack.' = 'Y'
  	       AND pt.statement_id = 'SQLD360_ASH_DATA'
  	       AND pt.remarks = '&&sqld360_sqlid.'
  	       AND pt.object_instance > 0
  	       AND o.object_id = pt.object_instance
  	    )
  	    SELECT 'TABLE', t.owner, t.table_name
  	      FROM dba_tab_statistics t, -- include fixed objects
  	           object o
  	     WHERE t.owner = o.owner
  	       AND t.table_name = o.name
  	     UNION
  	    SELECT 'TABLE', i.table_owner, i.table_name
  	      FROM dba_indexes i,
  	           object o
  	     WHERE i.owner = o.owner
  	       AND i.index_name = o.name)
  LOOP
    IF l_pair IS NULL THEN
      DBMS_LOB.WRITEAPPEND(:tables_list, 1, '(');
      DBMS_LOB.WRITEAPPEND(:tables_list_s, 1, '(');
    ELSE
      DBMS_LOB.WRITEAPPEND(:tables_list, 1, ',');
      DBMS_LOB.WRITEAPPEND(:tables_list_s, 1, ',');
    END IF;
    l_pair := '('''''||i.owner||''''','''''||i.table_name||''''')';
    DBMS_LOB.WRITEAPPEND(:tables_list, LENGTH(l_pair), l_pair);
    l_pair := '('''||i.owner||''','''||i.table_name||''')';
    DBMS_LOB.WRITEAPPEND(:tables_list_s, LENGTH(l_pair), l_pair);
    :num_tables := :num_tables + 1;
  END LOOP;
  IF l_pair IS NULL THEN
    l_pair := '((''''DUMMY'''',''''DUMMY''''))';
    DBMS_LOB.WRITEAPPEND(:tables_list, LENGTH(l_pair), l_pair);
    l_pair := '((''DUMMY'',''DUMMY''))';
	DBMS_LOB.WRITEAPPEND(:tables_list_s, LENGTH(l_pair), l_pair);
  ELSE
    DBMS_LOB.WRITEAPPEND(:tables_list, 1, ')');
    DBMS_LOB.WRITEAPPEND(:tables_list_s, 1, ')');
  END IF;
END;
/

COL tables_list NEW_V tables_list FOR A32767 NOPRI;
SELECT :tables_list tables_list FROM DUAL;
COL tables_list_s NEW_V tables_list_s FOR A32767 NOPRI;
SELECT :tables_list_s tables_list_s FROM DUAL;
  
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') sqld360_time_stamp FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;  

PRO Done extracting table list
PRO &&hh_mm_ss.
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
SPO OFF
