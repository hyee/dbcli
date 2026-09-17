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
    l_list   sys.odcivarchar2list:=sys.odcivarchar2list();
    l_err    VARCHAR2(4000);
BEGIN
    dbms_output.disable;
    dbms_output.enable;
    BEGIN
        EXECUTE IMMEDIATE 'begin sys.dbms_result_cache.memory_report(true);end;';
    EXCEPTION WHEN OTHERS THEN
        l_err := sqlerrm;
    END;

    l_list.extend;
    l_list(l_list.count) := '$PROMPTCOLOR$[DBMS_RESULT_CACHE.STATUS]$NOR$';
    l_list.extend;
    l_list(l_list.count) := '  '||dbms_result_cache.status;
    l_list.extend;

    dbms_output.get_lines(l_arr, l_done);
    FOR i IN 2 .. l_done LOOP
        l_arr(i) := trim(l_arr(i));
        IF l_arr(i) IS NOT NULL THEN
            IF i>2 AND l_arr(i) LIKE '[%' THEN
                l_arr(i) := '$PROMPTCOLOR$'||l_arr(i)||'$NOR$';
                FOR r IN(SELECT rownum r,name,value,max(length(name)) OVER() l FROM v$parameter WHERE name LIKE '%result%cache%' AND name NOT IN('result_cache_max_result','result_cache_max_size')) LOOP
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
        SELECT min(id) id,
               name,
               decode(name,'Block Size (Bytes)',round(avg(value)),'LRU Chain Scan Depth',round(avg(value)),sum(value)) value
        FROM   gv$result_cache_statistics
        WHERE  regexp_like(value,'^\d+$')
        GROUP  BY name
        ORDER  BY 1,2;

    OPEN :c2 FOR
        SELECT column_value report FROM TABLE(l_list);

    OPEN :c3 FOR q'{
        SELECT *
        FROM   (SELECT sum(scans) scans,
                       sum(decode(flag, 1, 1)) keys,
                       sum(cnt) rows#,
                       sum(decode(flag, 1, bytes)) bytes,
                       sum(build_time * 10) build,
                       --SUM(DECODE(flag, 2, bytes)) dep_bytes,
                       sum(invalids) invalids,
                       root_name name,
                       regexp_replace(listagg(&dst object_no,',') WITHIN GROUP(ORDER BY object_no),'([^,]+)(,\1)+','\1') dep_objs
                FROM   TABLE(gv$(CURSOR(
                                  SELECT /*+leading(c) use_hash(a c) no_merge(a) no_expand OPT_PARAM('_fix_control' '26552730:0')*/
                                  DISTINCT userenv('instance') inst_id,
                                           c.type,
                                           decode(a.id, c.id, 1, NULL, 1, 2) flag,
                                           max(regexp_replace(decode(a.id, c.id, c.name, NULL, c.name),'(\W)#.*','\1')) OVER(PARTITION BY nvl(a.id, c.id)) root_name,
                                           row_count cnt,
                                           block_count*(SELECT value FROM v$result_cache_statistics WHERE name='Block Size (Bytes)' AND rownum<2) bytes,
                                           c.scan_count + c.pin_count scans,
                                           build_time,
                                           invalidations invalids,
                                           nvl(nullif(a.object_no,0),nullif(c.object_no,0)) object_no
                                  FROM   (SELECT result_id id, depend_id,object_no
                                          FROM   v$result_cache_dependency
                                          UNION
                                          SELECT result_id, result_id,NULL
                                          FROM   v$result_cache_dependency) a,
                                         v$result_cache_objects c
                                  WHERE  a.depend_id(+) = c.id
                                  AND    userenv('instance')=nvl(:1,userenv('instance')))))
                WHERE  root_name IS NOT NULL
                GROUP  BY root_name
                HAVING max(type)='Result'
                ORDER  BY scans DESC, invalids DESC)
        WHERE  rownum <= 30}' USING :instance;

    OPEN :c4 FOR q'{
        SELECT *
        FROM   (SELECT object_no obj#,
                       max(decode(flag,1,root_name)) object_name,
                       count(DISTINCT decode(flag,2,root_name)) names,
                       count(depend_id) keys,
                       sum(cnt) rows#,
                       sum(decode(flag, 2, bytes)) bytes,
                       sum(scans) scans,
                       sum(build_time * 10) build,
                       sum(invalids) invalids
                FROM   TABLE(gv$(CURSOR(
                                  SELECT /*+leading(c) use_hash(a c) no_merge(a) no_expand OPT_PARAM('_fix_control' '26552730:0')*/
                                  DISTINCT userenv('instance') inst_id,
                                           c.type,
                                           decode(a.id, c.id, 1, NULL, 1, 2) flag,
                                           regexp_replace(c.name,'(\W)#.*','\1') root_name,
                                           row_count cnt,
                                           block_count*(SELECT value FROM v$result_cache_statistics WHERE name='Block Size (Bytes)' AND rownum<2) bytes,
                                           c.scan_count + c.pin_count scans,
                                           build_time,
                                           nullif(a.depend_id,a.id) depend_id,
                                           invalidations invalids,
                                           nvl(nullif(a.object_no,0),nullif(c.object_no,0)) object_no
                                  FROM   (SELECT depend_id id, result_id depend_id,object_no
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
        WHERE  rownum <= 30}' USING :instance;
END;
/

grid {
    '/*grid={topic="Statistics"}*/ c1',
    '-',[[/*grid={topic='Object Summary'}*/
        SELECT --+NO_EXPAND_GSET_TO_UNION OPT_PARAM('_fix_control' '26552730:0')
               coalesce(t,s,n,u) type,
               count(DISTINCT regexp_replace(name,'\W#.*')) names,
               count(1) keys,
               sum(block_count) blks,
               sum(pin_count) pins,
               sum(scan_count) scans
        FROM   (SELECT a.*,
                       'T-' || type t,
                       'S-' || status s,
                       'N-' || nvl(namespace, 'OBJECT') n,
                       'C-' || decode(creator_uid, 0, 'SYS', 'USER') u
                FROM   gv$result_cache_objects a)
        GROUP  BY GROUPING SETS(t, s, n, u)
        ORDER  BY 1 DESC]],
    '+','/*grid={topic="Local Memory Report"}*/ c2',
    '+','/*grid={topic="Top 30 Based Objects"}*/ c4',
    '-','/*grid={topic="Top 30 Scanned Results ( Keys=Count(ID[Result]) Invalids=Invalidations Scans=Scan+Pin Bytes=Blocks*BlockSize )"}*/ c3'
}