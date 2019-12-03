/*[[Show result cache report]]*/
set feed off verify off
col value for k0
col keys,deps,rows#,blocks,scans,invalids for tmb
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
               decode(name,'Block Size (Bytes)',max(value)+0,sum(value)) value
        from  gv$result_cache_statistics 
        where inst_id=nvl(:instance,inst_id)
        and   name!='Hash Chain Length'
        group by name
        order by 1,2;

    OPEN :c2 FOR 
        SELECT column_value report FROM TABLE(l_list);

    OPEN :c3 FOR q'{
        SELECT *
        FROM   (SELECT SUM(scans) scans,
                       SUM(DECODE(flag, 1, 1)) keys,
                       SUM(DECODE(flag, 1, bytes)) bytes,
                       SUM(cnt) rows#,
                       SUM(build_time * 10) build,
                       SUM(DECODE(flag, 2, bytes)) dep_bytes,
                       SUM(invalids) invalids,
                       root_name NAME,
                       regexp_replace(listagg(object_no,',') within group(order by object_no),'(\d+)(,\1)+','\1') dep_objs
                FROM   TABLE(GV$(CURSOR (
                                  SELECT /*+leading(c) use_hash(b c)*/
                                  DISTINCT userenv('instance') inst_id,
                                           c.type,
                                           DECODE(a.id, c.id, 1, NULL, 1, 2) flag,
                                           MAX(regexp_substr(DECODE(a.id, c.id, c.name, NULL, c.name), '[^#]+')) OVER(PARTITION BY nvl(a.id, c.id)) root_name,
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
                       MAX(root_name) NAME,
                       COUNT(depend_id) keys,
                       SUM(DECODE(flag, 2, bytes)) bytes,
                       SUM(scans) scans,
                       SUM(cnt) rows#,
                       SUM(build_time * 10) build,
                       SUM(invalids) invalids
                FROM   TABLE(GV$(CURSOR (
                                  SELECT /*+leading(c) use_hash(b c)*/
                                  DISTINCT userenv('instance') inst_id,
                                           c.type,
                                           DECODE(a.id, c.id, 1, NULL, 1, 2) flag,
                                           MAX(regexp_substr(DECODE(a.id, c.id, c.name, NULL, c.name), '[^#]+')) OVER(PARTITION BY nvl(a.id, c.id)) root_name,
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
        SELECT DECODE(r, 1, 'T-' || TYPE, 2, 'S-' || status,3, 'N-' || NVL(namespace, 'OBJECT'),'O-'||u) TYPE,
               COUNT(1) keys,
               SUM(blocks) blocks,
               SUM(pins) pins,
               SUM(scans) scans,
               SUM(items) items
        FROM   (SELECT TYPE,
                       status,
                       namespace,
                       DECODE(creator_uid,0,'SYS','USER') u,
                       COUNT(1) keys,
                       SUM(block_count) blocks,
                       SUM(pin_count) pins,
                       SUM(scan_count) scans,
                       COUNT(DISTINCT regexp_substr(NAME, '[^#]+')) items
                FROM   gv$result_cache_objects
                GROUP  BY TYPE, status, namespace,DECODE(creator_uid,0,'SYS','USER')) a,
               (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM <= 4) b
        GROUP  BY DECODE(r, 1, 'T-' || TYPE, 2, 'S-' || status,3, 'N-' || NVL(namespace, 'OBJECT'),'O-'||u)
        ORDER  BY 1 DESC]],
    '+','/*grid={topic="Top 30 Based Objects"}*/ c4',
    '+','/*grid={topic="Local Memory Report"}*/ c2',
    '-','/*grid={topic="Top 30 Scanned Results ( Keys=Count(ID[Result]) Invalids=Invalidations Scans=Scan+Pin Bytes=Blocks*BlockSize )"}*/ c3'
}