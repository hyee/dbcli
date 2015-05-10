DEF title = 'Standalone SQL';
DEF main_table = 'V$SQL';

@@sqld360_0s_pre_nondef

SET SERVEROUT ON
SET TERM OFF HEA OFF

VAR binds_from_mem NUMBER
BEGIN
  SELECT COUNT(*) 
    INTO :binds_from_mem 
	FROM gv$sql_bind_capture 
   WHERE sql_id = '&&sqld360_sqlid.';
END;
/

-- thanks to Kerry's post http://kerryosborne.oracle-guy.com/2009/07/creating-test-scripts-with-bind-variables/

SPO &&one_spool_filename..sql

PRO -- Standalone script to run the SQL, just copy and paste in SQL*Plus
PRO -- or copy file &&one_spool_filename..sql from &&sqld360_main_filename._&&sqld360_file_time..zip
PRO
-- right now it only picks up the info from memory, can be extended to AWR if needed
SELECT 'VAR '||
       CASE WHEN REGEXP_INSTR(SUBSTR(name,1,2),'[[:digit:]]') > 0 THEN 'b'||SUBSTR(name,2) ELSE SUBSTR(name,2) END||' '||
	   CASE WHEN datatype_string = 'DATE' OR datatype_string LIKE 'TIMESTAMP%' THEN 'VARCHAR2(50)' ELSE datatype_string END 
  FROM gv$sql_bind_capture
 WHERE sql_id = '&&sqld360_sqlid.'
   AND child_number||' '||inst_id = (SELECT MAX(child_number||' '||inst_id)
                                       FROM gv$sql
                                      WHERE sql_id = '&&sqld360_sqlid.')
 ORDER BY position; 

-- if there is no info available in memory then try AWR
SELECT 'VAR '||
       CASE WHEN REGEXP_INSTR(SUBSTR(name,1,2),'[[:digit:]]') > 0 THEN 'b'||SUBSTR(name,2) ELSE SUBSTR(name,2) END||' '||
	   CASE WHEN datatype_string = 'DATE' OR datatype_string LIKE 'TIMESTAMP%' THEN 'VARCHAR2(50)' ELSE datatype_string END
  FROM dba_hist_sql_bind_metadata
 WHERE :binds_from_mem = 0
   AND sql_id = '&&sqld360_sqlid.'
   AND '&&diagnostics_pack.' = 'Y';
   
PRO
-- values come from V$SQL_PLAN for the peeked binds
SELECT  
   'EXEC '||
   CASE WHEN REGEXP_INSTR(SUBSTR(bind_name,1,2),'[[:digit:]]') > 0 THEN ':b'||SUBSTR(bind_name,2) ELSE bind_name END||
   ' := ' ||
   CASE WHEN bind_type = 2 THEN NULL ELSE '''' END ||
               CASE WHEN bind_type =  1 THEN UTL_RAW.CAST_TO_VARCHAR2(bind_data)
			        WHEN bind_type =  2 THEN TO_CHAR(UTL_RAW.CAST_TO_NUMBER(bind_data))
			        WHEN bind_type = 12 THEN TO_CHAR(TO_DATE(TO_CHAR(TO_NUMBER(SUBSTR(CAST(bind_data AS VARCHAR2(30)),  1, 2), 'xx') - 100, 'FM00')  ||
                                                             TO_CHAR(MOD(TO_NUMBER(SUBSTR(CAST(bind_data AS VARCHAR2(30)), 3, 2), 'xx'), 100), 'FM00') ||
                                                             TO_CHAR(TO_NUMBER(SUBSTR(CAST(bind_data AS VARCHAR2(30)),  5, 2), 'xx'), 'FM00') ||
                                                             TO_CHAR(TO_NUMBER(SUBSTR(CAST(bind_data AS VARCHAR2(30)),  7, 2), 'xx'), 'FM00'),
                                                             'YYYYMMDD'),
                                                     'DD-MON-YYYY')
			  ELSE bind_data END ||
   CASE WHEN bind_type = 2 THEN NULL ELSE '''' END ||
   ';' 
  FROM (SELECT EXTRACTVALUE(VALUE(d), '/bind/@nam') as bind_name,
               EXTRACTVALUE(VALUE(d), '/bind/@dty') as bind_type,
               EXTRACTVALUE(VALUE(d), '/bind') as bind_data
          FROM XMLTABLE('/*/*/bind' PASSING (SELECT XMLTYPE(other_xml) AS xmlval 
				                               FROM gv$sql_plan 
											  WHERE sql_id = '&&sqld360_sqlid.' 
											    AND child_number||' '||inst_id = (SELECT MAX(child_number||' '||inst_id)
                                                                                    FROM gv$sql
                                                                                   WHERE sql_id = '&&sqld360_sqlid.')
												AND other_xml IS NOT NULL)) d
        )
 ORDER BY 1;

-- if there is no plan in memory then extract info from AWR
SELECT  
   'EXEC '||
   CASE WHEN REGEXP_INSTR(SUBSTR(b.name,1,2),'[[:digit:]]') > 0 THEN ':b'||SUBSTR(b.name,2) ELSE b.name END||
   ' := ' ||
   CASE WHEN b.datatype = 2 THEN NULL ELSE '''' END||
   a.value_string||
   CASE WHEN b.datatype = 2 THEN NULL ELSE '''' END||
   ';' 
  FROM TABLE(SELECT DBMS_SQLTUNE.EXTRACT_BINDS(bind_data) 
               FROM dba_hist_sqlstat
              WHERE sql_id = '&&sqld360_sqlid.'  
                AND rownum < 2
                AND bind_data IS NOT NULL) a,
       dba_hist_sql_bind_metadata b
 WHERE a.position = b.position
   AND :binds_from_mem = 0
   AND b.sql_id = '&&sqld360_sqlid.'
   AND '&&diagnostics_pack.' = 'Y'
 ORDER BY b.position;


PRO

PRINT :sqld360_fullsql
PRO /
SPO OFF;

SET TERM ON
-- get current time
SPO &&sqld360_log..txt APP;
COL current_time NEW_V current_time FOR A15;
SPO OFF;
SELECT 'Completed: ' x, TO_CHAR(SYSDATE, 'HH24:MI:SS') current_time FROM DUAL;
SET TERM OFF HEAD ON PAGES 50000

HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title.
PRO <a href="&&one_spool_filename..sql">sql</a>
PRO </li>
SPO OFF;
--HOS zip -jmq 99999_sqld360_&&sqld360_sqlid._drivers sqld360_xpand_&&sqld360_sqlid._driver.sql
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename..sql
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html
