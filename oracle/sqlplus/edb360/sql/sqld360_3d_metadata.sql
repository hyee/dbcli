DEF section_name = 'Metadata';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF

DEF title = 'Metadata script';
DEF main_table = 'DBMS_METADATA';

@@sqld360_0s_pre_nondef

VAR mymetadata CLOB;

SET SERVEROUT ON
SET TERM OFF
SPO sqld360_metadata_&&sqld360_sqlid._driver.sql
DECLARE
  PROCEDURE put (p_line IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put;
BEGIN

 FOR i IN (SELECT * 
             FROM (SELECT owner object_owner, table_name object_name, 'TABLE' object_type
                     FROM dba_tables
                    WHERE (owner, table_name) IN &&tables_list_s.
                   UNION 
                   SELECT owner object_owner, index_name object_name, 'INDEX' object_type
                     FROM dba_indexes
                    WHERE (table_owner, table_name) IN &&tables_list_s.
&&skip_10g.&&skip_11r1.   UNION 
&&skip_10g.&&skip_11r1.   SELECT SUBSTR(owner,1,30) object_owner, SUBSTR(name,1,30) object_name, SUBSTR(type,1,30) object_type
&&skip_10g.&&skip_11r1.     FROM v$db_object_cache -- it's intentional here to use V$ instead of GV$ to keep the plan easy 
&&skip_10g.&&skip_11r1.    WHERE type IN ('INDEX', 'TABLE', 'CLUSTER', 'VIEW', 'SYNONYM', 'SEQUENCE', 'PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY' ) 
&&skip_10g.&&skip_11r1.      AND hash_value IN (SELECT to_hash
&&skip_10g.&&skip_11r1.                           FROM v$object_dependency
&&skip_10g.&&skip_11r1.                          WHERE from_hash IN (SELECT hash_value
&&skip_10g.&&skip_11r1.                                                FROM v$sql
&&skip_10g.&&skip_11r1.                                               WHERE sql_id = '&&sqld360_sqlid.'))
                  )
            WHERE object_owner NOT IN ('ANONYMOUS','APEX_030200','APEX_040000','APEX_SSO','APPQOSSYS','CTXSYS','DBSNMP','DIP','EXFSYS','FLOWS_FILES',
                                       'MDSYS','OLAPSYS','ORACLE_OCM','ORDDATA','ORDPLUGINS','ORDSYS','OUTLN','OWBSYS', 'PUBLIC',
                                       'SI_INFORMTN_SCHEMA','SQLTXADMIN','SQLTXPLAIN','SYS','SYSMAN','SYSTEM','TRCANLZR','WMSYS','XDB','XS$NULL')
            ORDER BY 1,2,3 DESC) 
   LOOP
    put('BEGIN');
    put(':mymetadata :=');
    put('DBMS_METADATA.GET_DDL');
    put('( object_type => '''||i.object_type||'''');
    put(', name => '''||i.object_name||'''');
    put(', schema => '''||i.object_owner||''');');
    put('END;');
    put('/');
    put('PRINT :mymetadata;');
  END LOOP;
END;
/
SPO OFF;
SET SERVEROUT OFF;  

SPO &&one_spool_filename..txt
@sqld360_metadata_&&sqld360_sqlid._driver.sql
SPO OFF;

SET TERM ON
-- get current time
SPO &&sqld360_log..txt APP;
COL current_time NEW_V current_time FOR A15;
SELECT 'Completed: ' x, TO_CHAR(SYSDATE, 'HH24:MI:SS') current_time FROM DUAL;
SPO OFF;
SET TERM OFF PAGES 50000

HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title.
PRO <a href="&&one_spool_filename..txt">txt</a>
PRO </li>
SPO OFF;
HOS zip -jmq 99999_sqld360_&&sqld360_sqlid._drivers sqld360_metadata_&&sqld360_sqlid._driver.sql
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename..txt
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html
