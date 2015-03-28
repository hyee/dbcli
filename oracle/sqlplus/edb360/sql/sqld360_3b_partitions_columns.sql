SPO &&one_spool_filename..html APP;
PRO </head>
@sql/sqld360_0d_html_header.sql
PRO <body>
PRO <h1><a href="http://www.enkitec.com" target="_blank">Enkitec</a>: SQL 360-degree view <em>(<a href="http://www.enkitec.com/products/sqld360" target="_blank">SQLd360</a>)</em> &&sqld360_vYYNN. - Partitions Page</h1>
PRO
PRO <pre>
PRO sqlid:&&sqld360_sqlid. dbname:&&database_name_short. version:&&db_version. host:&&host_name_short. license:&&license_pack. days:&&history_days. today:&&sqld360_time_stamp.
PRO </pre>
PRO

PRO <table><tr class="main">

SET SERVEROUT ON ECHO OFF FEEDBACK OFF TIMING OFF 

BEGIN
  FOR i IN (SELECT DISTINCT table_name, owner 
              FROM dba_tables 
             WHERE (owner, table_name) in &&tables_list_s. 
			   AND partitioned = 'YES'
             ORDER BY 1,2) 
  LOOP
    DBMS_OUTPUT.PUT_LINE('<td class="c">'||i.owner||'.'||i.table_name||'</td>');
  END LOOP;
END;
/

PRO </tr><tr class="main">
SPO OFF

-- this is to trick sqld360_9a_pre
DEF sqld360_main_report_bck = &&sqld360_main_report.
DEF sqld360_main_report = &&one_spool_filename.

SPO sqld360_partitions_columns_&&sqld360_sqlid._driver.sql
SET SERVEROUT ON

DECLARE
  PROCEDURE put (p_line IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put;
BEGIN

  put('DELETE plan_table WHERE statement_id = ''SQLD360_LOW_HIGH'';'); 
  put('DECLARE');
  put('  l_low VARCHAR2(256);');
  put('  l_high VARCHAR2(256);');
  put('  FUNCTION compute_low_high (p_data_type IN VARCHAR2, p_raw_value IN RAW)');
  put('  RETURN VARCHAR2 AS');
  put('    l_number NUMBER;');
  put('    l_varchar2 VARCHAR2(256);');
  put('    l_date DATE;');
  put('  BEGIN');
  put('    IF p_data_type = ''NUMBER'' THEN');
  put('      DBMS_STATS.convert_raw_value(p_raw_value, l_number);');
  put('      RETURN TO_CHAR(l_number);');
  put('    ELSIF p_data_type IN (''VARCHAR2'', ''CHAR'', ''NVARCHAR2'', ''CHAR2'') THEN');
  put('      DBMS_STATS.convert_raw_value(p_raw_value, l_varchar2);');
  put('      RETURN l_varchar2;');
  put('    ELSIF SUBSTR(p_data_type, 1, 4) IN (''DATE'', ''TIME'') THEN');
  put('      DBMS_STATS.convert_raw_value(p_raw_value, l_date);');
  put('      RETURN TO_CHAR(l_date, ''YYYY-MM-DD HH24:MI:SS'');');
  put('    ELSE');
  put('      RETURN RAWTOHEX(p_raw_value);');
  put('    END IF;');
  put('  END compute_low_high;');
  put('BEGIN');
  put('  FOR i IN (SELECT a.owner, a.table_name, a.partition_name, a.column_name, b.data_type, a.low_value, a.high_value');
  put('              FROM dba_part_col_statistics a,');
  put('                   dba_tab_cols b');
  put('             WHERE (a.owner, a.table_name) IN &&tables_list.');
  put('		          AND ''&&translate_lowhigh.'' = ''Y''');
  put('               AND a.owner = b.owner');
  put('               AND a.table_name = b.table_name');
  put('               AND a.column_name = b.column_name)');
  put('  LOOP');
  put('    l_low := compute_low_high(i.data_type, i.low_value);');
  put('    l_high := compute_low_high(i.data_type, i.high_value);');
  put('    INSERT INTO plan_table (statement_id, object_owner, object_name, object_node, object_type, partition_start, partition_stop)');
  put('    VALUES (''SQLD360_LOW_HIGH'', i.owner, i.table_name, i.partition_name, i.column_name, l_low, l_high);');
  put('  END LOOP;');
  put('END;');
  put('/');	

  FOR i IN (SELECT DISTINCT table_name, owner 
              FROM dba_tables 
             WHERE (owner, table_name) in &&tables_list_s. 
			   AND partitioned = 'YES'
             ORDER BY 1,2) 
  LOOP	
    put('SET PAGES 50000');
    put('SPO &&sqld360_main_report..html APP;');	
    put('PRO <td>');
    put('SPO OFF');
    FOR j IN (SELECT DISTINCT a.owner, a.table_name, a.partition_name, b.partition_position 
                FROM dba_part_col_statistics a,
      		         dba_tab_partitions b
               WHERE a.owner = i.owner
                 AND a.table_name = i.table_name			
			     AND a.owner = b.table_owner
      	         AND a.table_name = b.table_name
      	         AND a.partition_name = b.partition_name	
               ORDER BY a.owner, a.table_name, b.partition_position DESC) 
    LOOP

      put('DEF title= ''Partition '||j.partition_name||'''');
      put('DEF DEF main_table = ''DBA_PART_COL_STATISTICS''');
      put('BEGIN');
      put(' :sql_text := ''');
      put('SELECT /*+ &&top_level_hints. */');
      put('       a.*,b.partition_start low_value_translated, b.partition_stop high_value_translated');
      put('  FROM dba_part_col_statistics a,');
      put('       plan_table b');
      put(' WHERE a.owner = '''''||j.owner||''''''); 
	  put('   AND a.table_name = '''''||j.table_name||'''''');
	  put('   AND a.partition_name = '''''||j.partition_name||'''''');
      put('   AND a.owner = b.object_owner(+)');
      put('   AND a.table_name = b.object_name(+)');
      put('   AND a.partition_name = b.object_node(+)');
      put('   AND a.column_name = b.object_type(+)');
      put('   AND b.statement_id(+) = ''''SQLD360_LOW_HIGH''''');
      put(' ORDER BY a.owner, a.table_name, a.partition_name');
      put(''';');
      put('END;');
      put('/ ');
      put('@sql/sqld360_9a_pre_one.sql');
    END LOOP;
    put('SPO &&sqld360_main_report..html APP;');
    put('PRO </td>');
  END LOOP;
END;
/
SPO &&sqld360_main_report..html APP;
@sqld360_partitions_columns_&&sqld360_sqlid._driver.sql

SPO &&sqld360_main_report..html APP;
PRO </tr></table>
@@sqld360_0e_html_footer.sql
SPO OFF
SET PAGES 50000

HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html
HOS zip -jmq 99999_sqld360_&&sqld360_sqlid._drivers sqld360_partitions_columns_&&sqld360_sqlid._driver.sql

DEF sqld360_main_report = &&sqld360_main_report_bck.
