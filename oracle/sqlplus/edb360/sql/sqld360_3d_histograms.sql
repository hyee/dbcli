SPO &&one_spool_filename..html APP;
PRO </head>
@sql/sqld360_0d_html_header.sql
PRO <body>
PRO <h1><a href="http://www.enkitec.com" target="_blank">Enkitec</a>: SQL 360-degree view <em>(<a href="http://www.enkitec.com/products/sqld360" target="_blank">SQLd360</a>)</em> &&sqld360_vYYNN. - Histograms Page</h1>
PRO
PRO <pre>
PRO sqlid:&&sqld360_sqlid. dbname:&&database_name_short. version:&&db_version. host:&&host_name_short. license:&&license_pack. days:&&history_days. today:&&sqld360_time_stamp.
PRO </pre>
PRO

PRO <table><tr class="main">

SET SERVEROUT ON ECHO OFF FEEDBACK OFF TIMING OFF 

BEGIN
  FOR i IN (SELECT DISTINCT owner, table_name 
              FROM dba_tab_cols
             WHERE (owner, table_name) in &&tables_list_s. 
			   AND histogram <> 'NONE'
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

SPO sqld360_histograms_&&sqld360_sqlid._driver.sql
SET SERVEROUT ON

DECLARE
  PROCEDURE put (p_line IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put;
BEGIN

-- this is intentional, showing all the tables including the ones with no histograms
-- so it's easier to spot the ones with no histograms too
  FOR i IN (SELECT DISTINCT a.owner, a.table_name, b.num_rows 
              FROM dba_tab_cols a,
			       dba_tables b
             WHERE (a.owner, a.table_name) in &&tables_list_s. 
			   AND a.histogram <> 'NONE'
			   AND a.owner = b.owner
			   AND a.table_name = b.table_name
             ORDER BY 1,2) 
  LOOP	
    put('SET PAGES 50000');
    put('SPO &&sqld360_main_report..html APP;');	
    put('PRO <td>');
    put('SPO OFF');
    FOR j IN (SELECT owner, table_name, column_name, data_type, 
		             histogram, sample_size, num_nulls, num_buckets 
                FROM dba_tab_cols
               WHERE owner = i.owner
                 AND table_name = i.table_name
				 AND histogram <> 'NONE'
               ORDER BY owner, table_name, column_id) 
    LOOP
      -- frequency and top-freq can be handled the same since sample_size is the whole set including "non popular" values
      IF j.histogram IN ('FREQUENCY','TOP-FREQUENCY') THEN
        put('DEF title= ''Histogram on Column '||j.column_name||'''');
        put('DEF main_table = ''DBA_TAB_HISTOGRAMS''');
        put('BEGIN');
        put(' :sql_text := ''');
        put('SELECT /*+ &&top_level_hints. */');
		put('       CASE WHEN endpoint_actual_value IS NOT NULL THEN REPLACE(endpoint_actual_value, '''''''''''''''', '''''''') ');
        put('            WHEN endpoint_actual_value IS NULL THEN ');
        put('               CASE WHEN '''''||j.data_type||''''' = ''''DATE'''' or '''''||j.data_type||''''' LIKE ''''TIMESTAMP%'''' THEN ');
        put('                      TO_CHAR(TO_DATE(TO_CHAR(TRUNC(endpoint_value)), ''''J'''') + (endpoint_value - TRUNC(endpoint_value)),''''SYYYY/MM/DD HH24:MI:SS'''') ');
        put('                    WHEN '''''||j.data_type||''''' IN (''''NUMBER'''', ''''FLOAT'''', ''''BINARY_FLOAT'''') THEN ');
        put('                      TO_CHAR(endpoint_value) ');
        put('                    ELSE ');
        put('                      UTL_RAW.CAST_TO_VARCHAR2(SUBSTR(LPAD(TO_CHAR(endpoint_value,''''fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx''''),30,''''0''''),1,12)) ');  
        put('               END ');
        put('       END approximate_value, '); 
		put('       round((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.sample_size||' * '||(i.num_rows-j.num_nulls)||') rows_per_bucket,  ');
		put('       trunc((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.sample_size||',5) selectivity, ');
        put('       ''''ApproxValue: ''''||CASE WHEN endpoint_actual_value IS NOT NULL THEN REPLACE(endpoint_actual_value, '''''''''''''''', '''''''') ');
        put('            WHEN endpoint_actual_value IS NULL THEN ');
        put('               CASE WHEN '''''||j.data_type||''''' = ''''DATE'''' or '''''||j.data_type||''''' LIKE ''''TIMESTAMP%'''' THEN ');
        put('                      TO_CHAR(TO_DATE(TO_CHAR(TRUNC(endpoint_value)), ''''J'''') + (endpoint_value - TRUNC(endpoint_value)),''''SYYYY/MM/DD HH24:MI:SS'''') ');
        put('                    WHEN '''''||j.data_type||''''' IN (''''NUMBER'''', ''''FLOAT'''', ''''BINARY_FLOAT'''') THEN ');
        put('                      TO_CHAR(endpoint_value) ');
        put('                    ELSE ');
        put('                      UTL_RAW.CAST_TO_VARCHAR2(SUBSTR(LPAD(TO_CHAR(endpoint_value,''''fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx''''),30,''''0''''),1,12)) ');  
        put('               END ');
        put('       END||'''' NumRows: ''''||round((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.sample_size||' * '||(i.num_rows-j.num_nulls)||')||'''' Sel: ''''||trunc((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.sample_size||' , 5) chart_text ');      
        put('  FROM dba_tab_histograms a');
        put(' WHERE a.owner = '''''||j.owner||''''''); 
        put('   AND a.table_name = '''''||j.table_name||'''''');
   	    put('   AND a.column_name = '''''||j.column_name||'''''');
        put(' ORDER BY a.endpoint_number');
        put(''';');
        put('END;');
        put('/ ');
		put('DEF skip_bch=''''');
        put('@sql/sqld360_9a_pre_one.sql');
      ELSIF j.histogram = 'HEIGHT BALANCED' THEN
        put('DEF title= ''Histogram on Column '||j.column_name||'''');
        put('DEF main_table = ''DBA_TAB_HISTOGRAMS''');
        put('BEGIN');
        put(' :sql_text := ''');
        put('SELECT /*+ &&top_level_hints. */');
		put('       CASE WHEN endpoint_actual_value IS NOT NULL THEN REPLACE(endpoint_actual_value, '''''''''''''''', '''''''') ');
        put('            WHEN endpoint_actual_value IS NULL THEN ');
        put('               CASE WHEN '''''||j.data_type||''''' = ''''DATE'''' or '''''||j.data_type||''''' LIKE ''''TIMESTAMP%'''' THEN ');
        put('                      TO_CHAR(TO_DATE(TO_CHAR(TRUNC(endpoint_value)), ''''J'''') + (endpoint_value - TRUNC(endpoint_value)),''''SYYYY/MM/DD HH24:MI:SS'''') ');
        put('                    WHEN '''''||j.data_type||''''' IN (''''NUMBER'''', ''''FLOAT'''', ''''BINARY_FLOAT'''') THEN ');
        put('                      TO_CHAR(endpoint_value) ');
        put('                    ELSE ');
        put('                      UTL_RAW.CAST_TO_VARCHAR2(SUBSTR(LPAD(TO_CHAR(endpoint_value,''''fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx''''),30,''''0''''),1,12)) ');  
        put('               END ');
        put('       END approximate_value, '); 
		put('       round((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.num_buckets||' * '||(i.num_rows-j.num_nulls)||') rows_per_bucket,  ');
		put('       trunc((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.num_buckets||',5) selectivity, ');
        put('       ''''ApproxValue: ''''||CASE WHEN endpoint_actual_value IS NOT NULL THEN REPLACE(endpoint_actual_value, '''''''''''''''', '''''''') ');
        put('            WHEN endpoint_actual_value IS NULL THEN ');
        put('               CASE WHEN '''''||j.data_type||''''' = ''''DATE'''' or '''''||j.data_type||''''' LIKE ''''TIMESTAMP%'''' THEN ');
        put('                      TO_CHAR(TO_DATE(TO_CHAR(TRUNC(endpoint_value)), ''''J'''') + (endpoint_value - TRUNC(endpoint_value)),''''SYYYY/MM/DD HH24:MI:SS'''') ');
        put('                    WHEN '''''||j.data_type||''''' IN (''''NUMBER'''', ''''FLOAT'''', ''''BINARY_FLOAT'''') THEN ');
        put('                      TO_CHAR(endpoint_value) ');
        put('                    ELSE ');
        put('                      UTL_RAW.CAST_TO_VARCHAR2(SUBSTR(LPAD(TO_CHAR(endpoint_value,''''fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx''''),30,''''0''''),1,12)) ');  
        put('               END ');
        put('       END||'''' NumRows: ''''||round((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.num_buckets||' * '||(i.num_rows-j.num_nulls)||')||'''' Sel: ''''||trunc((a.endpoint_number - lag(a.endpoint_number,1,0) over (order by a.endpoint_number)) / '||j.num_buckets||' , 5) chart_text ');      
        put('  FROM dba_tab_histograms a');
        put(' WHERE a.owner = '''''||j.owner||''''''); 
        put('   AND a.table_name = '''''||j.table_name||'''''');
   	    put('   AND a.column_name = '''''||j.column_name||'''''');
        put(' ORDER BY a.endpoint_number');
        put(''';');
        put('END;');
        put('/ ');
		put('DEF skip_bch=''''');
        put('@sql/sqld360_9a_pre_one.sql');
	  ELSIF j.histogram = 'HYBRID' THEN
        put('DEF title= ''Histogram on Column '||j.column_name||'''');
        put('DEF main_table = ''DBA_TAB_HISTOGRAMS''');
        put('BEGIN');
        put(' :sql_text := ''');
        put('SELECT /*+ &&top_level_hints. */');
		put('       CASE WHEN endpoint_actual_value IS NOT NULL THEN REPLACE(endpoint_actual_value, '''''''''''''''', '''''''') ');
        put('            WHEN endpoint_actual_value IS NULL THEN ');
        put('               CASE WHEN '''''||j.data_type||''''' = ''''DATE'''' or '''''||j.data_type||''''' LIKE ''''TIMESTAMP%'''' THEN ');
        put('                      TO_CHAR(TO_DATE(TO_CHAR(TRUNC(endpoint_value)), ''''J'''') + (endpoint_value - TRUNC(endpoint_value)),''''SYYYY/MM/DD HH24:MI:SS'''') ');
        put('                    WHEN '''''||j.data_type||''''' IN (''''NUMBER'''', ''''FLOAT'''', ''''BINARY_FLOAT'''') THEN ');
        put('                      TO_CHAR(endpoint_value) ');
        put('                    ELSE ');
        put('                      UTL_RAW.CAST_TO_VARCHAR2(SUBSTR(LPAD(TO_CHAR(endpoint_value,''''fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx''''),30,''''0''''),1,12)) ');  
        put('               END ');
        put('       END approximate_value, ');                                                                                                                
		put('       round(endpoint_repeat_count / '||j.sample_size||' * '||(i.num_rows-j.num_nulls)||') rows_per_bucket,  ');
		put('       trunc(endpoint_repeat_count / '||j.sample_size||',5) selectivity, ');
        put('       ''''ApproxValue: ''''||CASE WHEN endpoint_actual_value IS NOT NULL THEN REPLACE(endpoint_actual_value, '''''''''''''''', '''''''') ');
        put('            WHEN endpoint_actual_value IS NULL THEN ');
        put('               CASE WHEN '''''||j.data_type||''''' = ''''DATE'''' or '''''||j.data_type||''''' LIKE ''''TIMESTAMP%'''' THEN ');
        put('                      TO_CHAR(TO_DATE(TO_CHAR(TRUNC(endpoint_value)), ''''J'''') + (endpoint_value - TRUNC(endpoint_value)),''''SYYYY/MM/DD HH24:MI:SS'''') ');
        put('                    WHEN '''''||j.data_type||''''' IN (''''NUMBER'''', ''''FLOAT'''', ''''BINARY_FLOAT'''') THEN ');
        put('                      TO_CHAR(endpoint_value) ');
        put('                    ELSE ');
        put('                      UTL_RAW.CAST_TO_VARCHAR2(SUBSTR(LPAD(TO_CHAR(endpoint_value,''''fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx''''),30,''''0''''),1,12)) ');  
        put('               END ');
        put('       END||'''' NumRows: ''''||round(endpoint_repeat_count / '||j.sample_size||' * '||(i.num_rows-j.num_nulls)||')||'''' Sel: ''''||trunc(endpoint_repeat_count / '||j.sample_size||',5) chart_text ');      
        put('  FROM dba_tab_histograms a');
        put(' WHERE a.owner = '''''||j.owner||''''''); 
        put('   AND a.table_name = '''''||j.table_name||'''''');
   	    put('   AND a.column_name = '''''||j.column_name||'''''');
        put(' ORDER BY a.endpoint_number');
        put(''';');
        put('END;');
        put('/ ');
		put('DEF skip_bch=''''');
        put('@sql/sqld360_9a_pre_one.sql');
      END IF;
    END LOOP;
    put('SPO &&sqld360_main_report..html APP;');
    put('PRO </td>');
  END LOOP;
END;
/
SPO &&sqld360_main_report..html APP;
@sqld360_histograms_&&sqld360_sqlid._driver.sql

SPO &&sqld360_main_report..html APP;
PRO </tr></table>
@@sqld360_0e_html_footer.sql
SPO OFF
SET PAGES 50000

HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html
HOS zip -jmq 99999_sqld360_&&sqld360_sqlid._drivers sqld360_histograms_&&sqld360_sqlid._driver.sql

DEF sqld360_main_report = &&sqld360_main_report_bck.
