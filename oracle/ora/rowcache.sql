/*[[show rowcache. Usag: @@NAME [<keyword>|-f"<filter>"] [-detail]
  -detail: do not count dis,indx and hash
  --[[
    @con: 12.1={and a.con_id=b.con_id} default={}
    &filter: {
        default={:V1 IS NOT NULL AND (upper(object_name||','||address||','||substr(key,1,256)) LIKE upper('%&V1%') OR cache_name = :V1) OR :V1 IS NULL AND LOCK_MODE+LOCK_REQUEST>0}
        f={}
    }
    &inner: default={:V1 IS NOT NULL} f={1=1}
    &grp: default={} detail={,sid,indx,hash}
  --]]
]]*/

SELECT INST,
       Count(1) "Count",
       decode(count(distinct sid),1,max(sid),count(distinct sid)) "SID(s)",
       decode(count(distinct INDX),1,max(INDX),count(distinct INDX)) "INDX(s)",
       decode(count(distinct HASH),1,max(HASH),count(distinct HASH)) "HASH(s)",
       ADDRESS,
       CACHE#,CACHE_NAME,EXISTENT,LOCK_MODE,LOCK_REQUEST,INST_REQ,INST_RELEASE,INST_TYPE,TXN, OBJECT_NAME,NUM,KEY
FROM   TABLE(GV$(CURSOR(
      SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
           userenv('instance') INST,
           sid,
           INDX,
           HASH,
           ADDRESS,
           CACHE#,
           CACHE_NAME,
           EXISTENT,
           LOCK_MODE,
           LOCK_REQUEST,
           INST_LOCK_REQUEST INST_REQ,INST_LOCK_RELEASE INST_RELEASE,INST_LOCK_TYPE INST_TYPE,
           TXN,
           CASE
               WHEN CACHE_NAME IN ('dc_objects') THEN
                regexp_substr(utl_raw.cast_to_varchar2(substr(key,13)), '[[:print:]]+')
               WHEN CACHE_NAME IN ('dc_users') THEN
                regexp_substr(utl_raw.cast_to_varchar2(substr(key,5)), '[[:print:]]+')
               WHEN CACHE_NAME IN ('dc_tablespaces') THEN
                (SELECT NAME FROM v$tablespace b WHERE ts# = num &con)
               WHEN CACHE_NAME IN ('dc_realtime_tabst', 'dc_sequences') THEN
                 'OBJ#'||NUM
               WHEN CACHE_NAME IN ('dc_realtime_colst', 'dc_histogram_defs') THEN
                  'OBJ#'||NUM||' COL#'||to_number(substr(key, 9, 2), 'XX')
               WHEN CACHE_NAME IN ('dc_files') THEN
                (SELECT NAME FROM v$datafile b WHERE file# = num &con)
               WHEN CACHE_NAME IN ('dc_profiles') THEN
                'SYS.PROFNAME$: profile#' || num
               WHEN CACHE_NAME IN ('dc_segments') THEN
                'file#' || to_number(substr(key, 11, 4), 'XXXX') || ' block#' || to_number(utl_raw.reverse(substr(key, 17, 6)), 'XXXXXX')
           END object_name,
           num,
           INST_LOCK_ID1 ID1,
           INST_LOCK_ID1 ID2,
           SUBSTR(KEY, 1, 80) KEY
    FROM  (SELECT a.*, to_number(UTL_RAW.REVERSE(SUBSTR(KEY, 1, 8)), 'XXXXXXXX') num FROM v$rowcache_parent a) a
    LEFT  JOIN (select sid,saddr from v$session)  b USING(saddr)
    WHERE &inner OR LOCK_MODE+LOCK_REQUEST+INST_LOCK_REQUEST+INST_LOCK_RELEASE>0)))
WHERE  &filter
GROUP BY ADDRESS,INST,CACHE#,CACHE_NAME,EXISTENT,LOCK_MODE,LOCK_REQUEST,INST_REQ,INST_RELEASE,INST_TYPE,TXN, OBJECT_NAME,NUM,KEY &grp
ORDER BY LOCK_MODE+LOCK_REQUEST desc,CACHE_NAME,address,LOCK_MODE desc,OBJECT_NAME