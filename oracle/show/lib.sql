/*[[Show library cache information.]]*/
set feed off digits 4
PRO Library Cache Ratio:
PRO ====================
SELECT * FROM gv$librarycache ORDER BY 1, 2;
PRO Library Cache Memory:
PRO =====================
SELECT * FROM gv$library_cache_memory ORDER BY 1, 2;