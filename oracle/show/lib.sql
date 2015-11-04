/*[[Show library cache information.]]*/
set feed off
PRO Library Cache Ratio:
PRO ====================
select * from gv$LIBRARYCACHE order by 1,2;
PRO Library Cache Memory:
PRO ====================
select * from GV$LIBRARY_CACHE_MEMORY  order by 1,2;