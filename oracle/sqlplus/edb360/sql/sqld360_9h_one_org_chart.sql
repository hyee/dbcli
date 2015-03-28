-- add seq to one_spool_filename
EXEC :file_seq := :file_seq + 1;
SELECT LPAD(:file_seq, 5, '0')||'_&&spool_filename.' one_spool_filename FROM DUAL;

-- display
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET TERM ON;
SPO &&sqld360_log..txt APP;
PRO &&hh_mm_ss. col:&&column_number.of&&max_col_number. "&&one_spool_filename._org_chart.html"
SPO OFF;
SET TERM OFF;

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <a href="&&one_spool_filename._org_chart.html">chart</a>
SPO OFF;

-- get time t0
EXEC :get_time_t0 := DBMS_UTILITY.get_time;

-- header
SPO &&one_spool_filename._org_chart.html;
@@sqld360_0o_html_header_org.sql
PRO <!-- &&one_spool_filename._org_chart.html $ -->

-- chart header
PRO    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
PRO    <script type="text/javascript">
PRO      google.load("visualization", "1", {packages:["orgchart"]});
PRO      google.setOnLoadCallback(drawChart);
PRO      function drawChart() {
PRO        var data = google.visualization.arrayToDataTable([

-- body
SET SERVEROUT ON;
DECLARE
  cur SYS_REFCURSOR;
  l_step_id VARCHAR2(1000);
  l_parent_id NUMBER;
  l_text VARCHAR2(1000);
  l_sql_text VARCHAR2(32767);
  l_sort NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('[''Step'', ''Parent Step'',''Tooltip'' ]');
  --OPEN cur FOR :sql_text;
  l_sql_text := DBMS_LOB.SUBSTR(:sql_text); -- needed for 10g
  OPEN cur FOR l_sql_text; -- needed for 10g
  LOOP
    FETCH cur INTO l_step_id, l_parent_id, l_text, l_sort;
    EXIT WHEN cur%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(',['||l_step_id||', '''||NVL(l_parent_id,'')||''', '''||l_text||''']');
  END LOOP;
  CLOSE cur;
END;
/
SET SERVEROUT OFF;

-- chart footer
PRO        ]);;
PRO        
PRO        var options = {
PRO          backgroundColor: {fill: '#fcfcf0', stroke: '#336699', strokeWidth: 1},
PRO          title: '&&title.&&title_suffix.',
PRO          titleTextStyle: {fontSize: 16, bold: false},
PRO          legend: {position: 'none'},
PRO          allowHtml:true,
PRO          tooltip: {textStyle: {fontSize: 14}}
PRO        };
PRO
PRO        var chart = new google.visualization.OrgChart(document.getElementById('orgchart'));
PRO        chart.draw(data, options);
PRO      }
PRO    </script>
PRO  </head>
PRO  <body>
PRO<h1>&&title. <em>(&&main_table.)</em></h1>
PRO
PRO <br>
PRO &&abstract.
PRO &&abstract2.
PRO
PRO    <div id="orgchart"></div>
PRO

-- footer
PRO <pre>
SET LIN 80;
DESC &&main_table.
SET HEA OFF;
SET LIN 32767;
PRINT sql_text_display;
SET HEA ON;
PRO &&row_count. rows selected.
PRO </pre>

@@sqld360_0e_html_footer.sql
SPO OFF;

-- get time t1
EXEC :get_time_t1 := DBMS_UTILITY.get_time;

-- update log2
SET HEA OFF;
SPO &&sqld360_log2..txt APP;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')||' , '||
       TO_CHAR((:get_time_t1 - :get_time_t0)/100, '999999990.00')||' , '||
       :row_count||' , &&main_table. , &&title_no_spaces., org_chart , &&one_spool_filename._org_chart.html'
  FROM DUAL
/
SPO OFF;
SET HEA OFF;

-- zip
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename._org_chart.html
