-- add seq to one_spool_filename
EXEC :file_seq := :file_seq + 1;
SELECT LPAD(:file_seq, 5, '0')||'_&&spool_filename.' one_spool_filename FROM DUAL;

-- display
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET TERM ON;
SPO &&edb360_log..txt APP;
PRO &&hh_mm_ss. col:&&column_number.of&&max_col_number. "&&one_spool_filename._pie_chart.html"
SPO OFF;
SET TERM OFF;

-- update main report
SPO &&edb360_main_report..html APP;
PRO <a href="&&one_spool_filename._pie_chart.html">chart</a>
SPO OFF;

-- get time t0
EXEC :get_time_t0 := DBMS_UTILITY.get_time;

-- header
SPO &&one_spool_filename._pie_chart.html;
@@edb360_0d_html_header.sql
PRO <!-- &&one_spool_filename._pie_chart.html $ -->

-- chart header
PRO    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
PRO    <script type="text/javascript">
PRO      google.load("visualization", "1", {packages:["corechart"]});
PRO      google.setOnLoadCallback(drawChart);
PRO      function drawChart() {
PRO        var data = google.visualization.arrayToDataTable([

-- body
SET SERVEROUT ON;
DECLARE
  cur SYS_REFCURSOR;
  l_slice VARCHAR2(32767);
  l_value NUMBER;
  l_percent NUMBER;
  l_text VARCHAR2(32767);
  l_sql_text VARCHAR2(32767);
BEGIN
  DBMS_OUTPUT.PUT_LINE('[''Slice'', ''Value'']');
  --OPEN cur FOR :sql_text;
  l_sql_text := DBMS_LOB.SUBSTR(:sql_text); -- needed for 10g
  OPEN cur FOR l_sql_text; -- needed for 10g
  LOOP
    FETCH cur INTO l_slice, l_value, l_percent, l_text;
    EXIT WHEN cur%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(',['''||l_slice||''', '||l_value||']');
  END LOOP;
  CLOSE cur;
END;
/
SET SERVEROUT OFF;

-- chart footer
PRO        ]);;
PRO        
PRO        var options = {
PRO          is3D: true,
PRO          backgroundColor: {fill: '#fcfcf0', stroke: '#336699', strokeWidth: 1},
PRO          title: '&&title.&&title_suffix.',
PRO          titleTextStyle: {fontSize: 16, bold: false},
PRO          legend: {position: 'right', textStyle: {fontSize: 12}},
PRO          tooltip: {textStyle: {fontSize: 14}},
PRO          sliceVisibilityThreshold: 1/1440
PRO        };
PRO
PRO        var chart = new google.visualization.PieChart(document.getElementById('piechart_3d'));
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
PRO    <div id="piechart_3d" style="width: 900px; height: 500px;"></div>
PRO

-- footer
PRO<font class="n">Notes:<br>1) up to &&history_days. days of awr history were considered<br>2) ASH reports are based on number of samples</font>
PRO<font class="n"><br>3) &&foot.</font>
PRO <pre>
SET LIN 80;
DESC &&main_table.
SET HEA OFF;
SET LIN 32767;
PRINT sql_text_display;
SET HEA ON;
PRO &&row_count. rows selected.
PRO </pre>

@@edb360_0e_html_footer.sql
SPO OFF;

-- get time t1
EXEC :get_time_t1 := DBMS_UTILITY.get_time;

-- update log2
SET HEA OFF;
SPO &&edb360_log2..txt APP;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')||' , '||
       TO_CHAR((:get_time_t1 - :get_time_t0)/100, '999999990.00')||' , rows:'||
       :row_count||' , &&section_id., &&main_table., &&edb360_prev_sql_id., -1, &&title_no_spaces., html , &&one_spool_filename._pie_chart.html'
  FROM DUAL
/
SPO OFF;
SET HEA ON;

-- zip
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. &&one_spool_filename._pie_chart.html
