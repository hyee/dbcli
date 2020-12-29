/*+[[show rowcache. Usag: @@NAME <keyword>

]]*/

SELECT *
FROM   TABLE(GV$(CURSOR(
	  SELECT INDX,
           HASH,
           ADDRESS,
           CACHE#,
           CACHE_NAME,
           EXISTENT,
           LOCK_MODE,
           LOCK_REQUEST,
           TXN,
           SADDR,
           CASE
               WHEN CACHE_NAME IN ('dc_objects', 'dc_users') THEN
                regexp_substr(utl_raw.cast_to_varchar2(key), '[[:print:]]+')
               WHEN CACHE_NAME IN ('dc_tablespaces') THEN
                (SELECT NAME FROM v$tablespace WHERE ts# = num)
               WHEN CACHE_NAME IN ('dc_realtime_colst', 'dc_realtime_tabst', 'dc_sequences') THEN
                 'OBJ#'||NUM
               WHEN CACHE_NAME IN ('dc_realtime_colst', 'dc_histogram_defs') THEN
                  'OBJ#'||NUM||' COL#'||to_number(substr(key, 9, 2), 'XX')
               WHEN CACHE_NAME IN ('dc_files') THEN
                (SELECT NAME FROM v$datafile WHERE file# = num)
               WHEN CACHE_NAME IN ('dc_profiles') THEN
                'SYS.PROFNAME$: profile#' || num
               WHEN CACHE_NAME IN ('dc_segments') THEN
                'file#' || to_number(substr(key, 11, 4), 'XXXX') || ' block#' || to_number(utl_raw.reverse(substr(key, 17, 6)), 'XXXXXX')
           END object_name,
           num,
           SUBSTR(KEY, 1, 80) KEY
    FROM  (SELECT a.*, to_number(UTL_RAW.REVERSE(SUBSTR(KEY, 1, 8)), 'XXXXXXXX') num FROM v$rowcache_parent a))))
WHERE  :V1 IS NOT NULL AND (upper(object_name) LIKE upper('%&V1%') OR cache_name = :V1) 
OR     :V1 IS NULL AND LOCK_MODE+LOCK_REQUEST>0
ORDER  BY object_name,CACHE_NAME,INDX