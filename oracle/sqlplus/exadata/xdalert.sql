col cell_name for a33
col SEVERITY for a20
select * from V$CELL_OPEN_ALERTS order by begin_time desc;