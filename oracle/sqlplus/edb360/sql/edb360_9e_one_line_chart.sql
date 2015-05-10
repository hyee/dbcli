-- add seq to one_spool_filename
EXEC :file_seq := :file_seq + 1;
SELECT LPAD(:file_seq, 5, '0')||'_&&spool_filename.' one_spool_filename FROM DUAL;

-- display
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET TERM ON;
SPO &&edb360_log..txt APP;
PRO &&hh_mm_ss. &&section_id. "&&one_spool_filename._line_chart.html"
SPO OFF;
SET TERM OFF;

-- update main report
SPO &&edb360_main_report..html APP;
PRO <a href="&&one_spool_filename._line_chart.html">line</a>
SPO OFF;

-- get time t0
EXEC :get_time_t0 := DBMS_UTILITY.get_time;

-- header
SPO &&one_spool_filename._line_chart.html;
@@edb360_0d_html_header.sql
PRO <!-- &&one_spool_filename._line_chart.html $ -->

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
  l_snap_id NUMBER;
  l_begin_time VARCHAR2(32);
  l_end_time VARCHAR2(32);
  l_col_01 NUMBER;
  l_col_02 NUMBER;
  l_col_03 NUMBER;
  l_col_04 NUMBER;
  l_col_05 NUMBER;
  l_col_06 NUMBER;
  l_col_07 NUMBER;
  l_col_08 NUMBER;
  l_col_09 NUMBER;
  l_col_10 NUMBER;
  l_col_11 NUMBER;
  l_col_12 NUMBER;
  l_col_13 NUMBER;
  l_col_14 NUMBER;
  l_col_15 NUMBER;
  l_line VARCHAR2(1000);
  l_sql_text VARCHAR2(32767);
BEGIN
  l_line := '[''Date''';
  IF '&&tit_01.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_01.'''; 
  END IF;
  IF '&&tit_02.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_02.'''; 
  END IF;
  IF '&&tit_03.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_03.'''; 
  END IF;
  IF '&&tit_04.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_04.'''; 
  END IF;
  IF '&&tit_05.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_05.'''; 
  END IF;
  IF '&&tit_06.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_06.'''; 
  END IF;
  IF '&&tit_07.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_07.'''; 
  END IF;
  IF '&&tit_08.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_08.'''; 
  END IF;
  IF '&&tit_09.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_09.'''; 
  END IF;
  IF '&&tit_10.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_10.'''; 
  END IF;
  IF '&&tit_11.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_11.'''; 
  END IF;
  IF '&&tit_12.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_12.'''; 
  END IF;
  IF '&&tit_13.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_13.'''; 
  END IF;
  IF '&&tit_14.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_14.'''; 
  END IF;
  IF '&&tit_15.' IS NOT NULL THEN
    l_line := l_line||', ''&&tit_15.'''; 
  END IF;
  l_line := l_line||']';
  DBMS_OUTPUT.PUT_LINE(l_line);
  --OPEN cur FOR :sql_text;
  l_sql_text := DBMS_LOB.SUBSTR(:sql_text); -- needed for 10g
  OPEN cur FOR l_sql_text; -- needed for 10g
  LOOP
    FETCH cur INTO l_snap_id, l_begin_time, l_end_time,
    l_col_01, l_col_02, l_col_03, l_col_04, l_col_05,
    l_col_06, l_col_07, l_col_08, l_col_09, l_col_10,
    l_col_11, l_col_12, l_col_13, l_col_14, l_col_15;
    EXIT WHEN cur%NOTFOUND;
    l_line := ', [new Date('||SUBSTR(l_end_time,1,4)||','||(TO_NUMBER(SUBSTR(l_end_time,6,2)) - 1)||','||SUBSTR(l_end_time,9,2)||','||SUBSTR(l_end_time,12,2)||','||SUBSTR(l_end_time,15,2)||',0)';
    IF '&&tit_01.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_01; 
    END IF;
    IF '&&tit_02.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_02; 
    END IF;
    IF '&&tit_03.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_03; 
    END IF;
    IF '&&tit_04.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_04; 
    END IF;
    IF '&&tit_05.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_05; 
    END IF;
    IF '&&tit_06.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_06; 
    END IF;
    IF '&&tit_07.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_07; 
    END IF;
    IF '&&tit_08.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_08; 
    END IF;
    IF '&&tit_09.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_09; 
    END IF;
    IF '&&tit_10.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_10; 
    END IF;
    IF '&&tit_11.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_11; 
    END IF;
    IF '&&tit_12.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_12; 
    END IF;
    IF '&&tit_13.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_13; 
    END IF;
    IF '&&tit_14.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_14; 
    END IF;
    IF '&&tit_15.' IS NOT NULL THEN
      l_line := l_line||', '||l_col_15; 
    END IF;
    l_line := l_line||']';
    DBMS_OUTPUT.PUT_LINE(l_line);
  END LOOP;
  CLOSE cur;
END;
/
SET SERVEROUT OFF;

-- chart footer
PRO        ]);;
PRO        
PRO        var options = {&&stacked.
PRO          backgroundColor: {fill: '#fcfcf0', stroke: '#336699', strokeWidth: 1},
PRO          explorer: {actions: ['dragToZoom', 'rightClickToReset'], maxZoomIn: 0.1},
PRO          title: '&&title.&&title_suffix.',
PRO          titleTextStyle: {fontSize: 16, bold: false},
PRO          focusTarget: 'category',
PRO          legend: {position: 'right', textStyle: {fontSize: 12}},
PRO          tooltip: {textStyle: {fontSize: 10}},
PRO          hAxis: {title: '&&haxis.', gridlines: {count: -1}},
PRO          vAxis: {title: '&&vaxis.', &&vbaseline. gridlines: {count: -1}}
PRO        };
PRO
PRO        var chart = new google.visualization.&&chartype.(document.getElementById('chart_div'));
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
PRO    <div id="chart_div" style="width: 900px; height: 500px;"></div>
PRO

-- footer
PRO<font class="n">Notes:<br>1) drag to zoom, and right click to reset<br>2) up to &&history_days. days of awr history were considered</font>
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
       :row_count||' , &&section_id., &&main_table., &&edb360_prev_sql_id., -1, &&title_no_spaces., html , &&one_spool_filename._line_chart.html'
  FROM DUAL
/
SPO OFF;
SET HEA ON;

-- zip
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&one_spool_filename._line_chart.html >> &&edb360_log3..txt
