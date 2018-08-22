SET VERIFY OFF
SET TERMOUT OFF
column max_width new_value max_width
column row_limit new_value row_limit
SELECT 0 max_width,0 row_limit from dual WHERE ROWNUM = 0;
SET TERMOUT ON
define select_stmt=&1
undefine 1
select * from print_table.print(dual,q'{&select_stmt}',nvl('&&row_limit','50'),nvl('&&max_width','128'));