/*[[Show tablspace usage]]*/
SELECT /*+no_merge(d) no_merge(f)*/ D.TABLESPACE_NAME,
       siz "MAX_SIZE(G)",
       SPACE "FILE_SIZE(G)",
       SPACE - NVL(FREE_SPACE, 0) "USED_SPACE(G)",
       ROUND(((SPACE - NVL(FREE_SPACE, 0)) / nullif(siz, 0)) * 100, 2) "USED_RATE(%)",
       FREE_SPACE "FREE_SPACE(G)",
       siz+FREE_SPACE-space "TOTAL_FREE(G)",
       g Disk_Groups
FROM   (SELECT TABLESPACE_NAME,
               round(SUM(greatest(maxbytes, bytes)) / power(1024, 3), 2) siz,
               ROUND(SUM(BYTES) / (1024 * 1024 * 1024), 2) SPACE,
               MAX(autoextensible) ext,
               wm_concat(DISTINCT regexp_substr(file_name, '\w+')) g
        FROM   DBA_DATA_FILES
        GROUP  BY TABLESPACE_NAME) D,
       (SELECT TABLESPACE_NAME, ROUND(SUM(BYTES) / (1024 * 1024 * 1024), 2) FREE_SPACE
        FROM   DBA_FREE_SPACE
        GROUP  BY TABLESPACE_NAME) F
WHERE  D.TABLESPACE_NAME = F.TABLESPACE_NAME(+)
UNION ALL
SELECT h.tablespace_name,
       round(SUM(decode(f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) / power(1024, 3), 2) file_size,
       round(SUM(h.bytes_free + h.bytes_used) / power(1024, 3), 2) space_all,
       round(SUM(nvl(p.bytes_used, 0)) / power(1024, 3), 2) space_used,
       round(SUM(nvl(p.bytes_used, 0)) / SUM(h.bytes_free + h.bytes_used), 2) space_pct,
       round(SUM((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) / power(1024, 3),
             2) space_free,
       NULL,
       wmsys.wm_concat(DISTINCT regexp_substr(f.file_name, '\w+'))
FROM   sys.v_$TEMP_SPACE_HEADER h, sys.v_$Temp_extent_pool p, dba_temp_files f
WHERE  p.file_id(+) = h.file_id
AND    p.tablespace_name(+) = h.tablespace_name
AND    f.file_id = h.file_id
AND    f.tablespace_name = h.tablespace_name
GROUP  BY h.tablespace_name
ORDER  BY 5 DESC