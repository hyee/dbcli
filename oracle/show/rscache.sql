/*[[Show result cache report
    --[[ @dst: 19={DISTINCT} default={}
    --]]
]]*/
set feed off verify off
col value for k0
col keys,deps,rows#,blks,scans,invalids for tmb
col build,dep_build_time for msmhd2
col bytes,dep_bytes for kmg
var c1 refcursor
var c2 refcursor
var c3 refcursor
var c4 refcursor
DECLARE
    l_arr    dbms_output.chararr;
    l_done   PLS_INTEGER := 32767;
    l_list   SYS.ODCIVARCHAR2LIST:=SYS.ODCIVARCHAR2LIST();
    l_err    VARCHAR2(4000);
BEGIN
    dbms_output.disable;
    dbms_output.enable;
    BEGIN
        dbms_result_cache.memory_report(true);
    EXCEPTION WHEN OTHERS THEN
        l_err := sqlerrm;
    END;

    dbms_output.get_lines(l_arr, l_done);
    FOR i IN 2 .. l_done LOOP
        l_arr(i) := trim(l_arr(i));
        IF l_arr(i) IS NOT NULL THEN
            IF i>2 AND l_arr(i) LIKE '[%' THEN
                l_arr(i) := '$PROMPTCOLOR$'||l_arr(i)||'$NOR$';
                FOR r IN(select rownum r,name,value,max(length(name)) over() l from v$parameter where name like '%result%cache%' and name not in('result_cache_max_result','result_cache_max_size')) LOOP
                    l_list.extend;
                    l_list(l_list.count) := '  ... '||rpad(r.name,r.l)||' = '||r.value;
                END LOOP;
                l_list.extend;
                l_list(l_list.count) := ' ';
            ELSIF l_arr(i) NOT LIKE '[%' THEN
                l_arr(i) := '  '||l_arr(i);
            ELSE
                l_arr(i) := '$PROMPTCOLOR$'||l_arr(i)||'$NOR$';
            END IF;
            l_list.extend;
            l_list(l_list.count) := l_arr(i);
        END IF;
    END LOOP;

    IF l_err IS NOT NULL THEN
        l_list.extend;
        l_list.extend;
        l_list(l_list.count) := l_err;
    END IF;
    
    OPEN :c1 FOR 
        select min(id) id,
               name,
               decode(name,'Block Size (Bytes)',round(avg(value)),'LRU Chain Scan Depth',round(avg(value)),sum(value)) value
        from  gv$result_cache_statistics 
        where regexp_like(value,'^\d+$')
        group by name
        order by 1,2;

    OPEN :c2 FOR 
        SELECT column_value report FROM TABLE(l_list);

    OPEN :c3 FOR q'{
        SELECT *
        FROM   (SELECT SUM(scans) scans,
                       SUM(DECODE(flag, 1, 1)) keys,
                       SUM(cnt) rows#,
                       SUM(DECODE(flag, 1, bytes)) bytes,
                       SUM(build_time * 10) build,
                       --SUM(DECODE(flag, 2, bytes)) dep_bytes,
                       SUM(invalids) invalids,
                       root_name NAME,
                       regexp_replace(listagg(&dst object_no,',') within group(order by object_no),'([^,]+)(,\1)+','\1') dep_objs
                FROM   TABLE(GV$(CURSOR(
                                  SELECT /*+leading(c) use_hash(a c) no_merge(a) no_expand*/
                                  DISTINCT userenv('instance') inst_id,
                                           c.type,
                                           DECODE(a.id, c.id, 1, NULL, 1, 2) flag,
                                           MAX(regexp_replace(DECODE(a.id, c.id, c.name, NULL, c.name),'(\W)#.*','\1')) OVER(PARTITION BY nvl(a.id, c.id)) root_name,
                                           ROW_COUNT cnt,
                                           block_count*(select value from v$result_cache_statistics where name='Block Size (Bytes)' and rownum<2) bytes,
                                           c.scan_count + c.pin_count scans,
                                           build_time,
                                           invalidations invalids,
                                           NVL(NULLIF(a.object_no,0),NULLIF(c.object_no,0)) object_no
                                  FROM   (SELECT result_id ID, depend_id,object_no
                                          FROM   v$result_cache_dependency
                                          UNION
                                          SELECT result_id, result_id,null
                                          FROM   v$result_cache_dependency) a,
                                         v$result_cache_objects c
                                  WHERE  a.depend_id(+) = c.id
                                  AND    userenv('instance')=nvl(:1,userenv('instance')))))
                WHERE  root_name IS NOT NULL
                GROUP  BY root_name
                HAVING max(type)='Result'
                ORDER  BY scans DESC, invalids DESC)
        WHERE  ROWNUM <= 30}' USING :instance;

    OPEN :c4 FOR q'{
        SELECT *
        FROM   (SELECT object_no obj#,
                       MAX(decode(flag,1,root_name)) OBJECT_NAME,
                       COUNT(DISTINCT decode(flag,2,root_name)) names,
                       COUNT(depend_id) keys,
                       SUM(cnt) rows#,
                       SUM(DECODE(flag, 2, bytes)) bytes,
                       SUM(scans) scans,
                       SUM(build_time * 10) build,
                       SUM(invalids) invalids
                FROM   TABLE(GV$(CURSOR(
                                  SELECT /*+leading(c) use_hash(a c) no_merge(a) no_expand*/
                                  DISTINCT userenv('instance') inst_id,
                                           c.type,
                                           DECODE(a.id, c.id, 1, NULL, 1, 2) flag,
                                           regexp_replace(c.name,'(\W)#.*','\1') root_name,
                                           ROW_COUNT cnt,
                                           block_count*(select value from v$result_cache_statistics where name='Block Size (Bytes)' and rownum<2) bytes,
                                           c.scan_count + c.pin_count scans,
                                           build_time,
                                           nullif(a.depend_id,a.id) depend_id,
                                           invalidations invalids,
                                           NVL(NULLIF(a.object_no,0),NULLIF(c.object_no,0)) object_no
                                  FROM   (SELECT depend_id ID, result_id depend_id,object_no
                                          FROM   v$result_cache_dependency
                                          UNION
                                          SELECT depend_id, depend_id,object_no
                                          FROM   v$result_cache_dependency) a,
                                         v$result_cache_objects c
                                  WHERE  a.depend_id(+) = c.id
                                  AND    userenv('instance')=nvl(:1,userenv('instance')))))
                GROUP  BY object_no
                HAVING min(type)!='Result'
                ORDER  BY scans DESC, invalids DESC,keys DESC)
        WHERE  ROWNUM <= 30}' USING :instance;
END;
/

grid {
    '/*grid={topic="Statistics"}*/ c1',
    '-',[[/*grid={topic='Object Summary'}*/ 
        SELECT --+NO_EXPAND_GSET_TO_UNION
               coalesce(t,s,n,u) type,
               COUNT(DISTINCT regexp_replace(name,'\W#.*')) names,
               COUNT(1) keys,
               SUM(block_count) blks,
               SUM(pin_count) pins,
               SUM(scan_count) scans
        FROM   (SELECT a.*,
                       'T-' || type t,
                       'S-' || status s,
                       'N-' || NVL(namespace, 'OBJECT') n,
                       'C-' || DECODE(creator_uid, 0, 'SYS', 'USER') u
                FROM   gv$result_cache_objects a)
        GROUP  BY GROUPING SETS(t, s, n, u)
        ORDER  BY 1 DESC]],
    '+','/*grid={topic="Top 30 Based Objects"}*/ c4',
    '+','/*grid={topic="Local Memory Report"}*/ c2',
    '-','/*grid={topic="Top 30 Scanned Results ( Keys=Count(ID[Result]) Invalids=Invalidations Scans=Scan+Pin Bytes=Blocks*BlockSize )"}*/ c3'
}