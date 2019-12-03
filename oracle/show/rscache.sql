/*[[Show result cache report]]*/
set feed off verify off
col value,keys,blocks,rows#,invalids,dep_blocks,dep_rows,dep_scans,invalids for tmb
col build_time,dep_build_time for msmhd2
col bytes,dep_bytes for kmg
var c1 refcursor
var c2 refcursor
var c3 refcursor
DECLARE
    l_arr    dbms_output.chararr;
    l_done   PLS_INTEGER := 32767;
    l_list   SYS.ODCIVARCHAR2LIST:=SYS.ODCIVARCHAR2LIST();
BEGIN
    BEGIN
        dbms_result_cache.memory_report(true);
        dbms_output.get_lines(l_arr, l_done);
        FOR i IN 2 .. l_done LOOP
            IF trim(l_arr(i)) LIKE '[%' THEN
                l_list.extend;
                l_list(l_list.count) := ' ';
            END IF;
            IF trim(l_arr(i)) IS NOT NULL THEN
                l_list.extend;
                l_list(l_list.count) := l_arr(i);
            END IF;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        l_list.extend;
        l_list(l_list.count) := sqlerrm;
    END;

    OPEN :c1 FOR 
        select listagg(inst_id,',') within group(order by inst_id) inst,
               id,name,
               decode(name,'Block Size (Bytes)',max(value)+0,sum(value)) value
        from  gv$result_cache_statistics 
        where inst_id=nvl(:instance,inst_id)
        and   name!='Hash Chain Length'
        group by id,name
        order by 1,2;

    OPEN :c2 FOR 
        SELECT column_value report FROM TABLE(l_list);

    OPEN :c3 FOR
        SELECT *
        FROM   (SELECT SUM(scans) scans,
                       SUM(DECODE(flag, 1, 1)) keys,
                       SUM(DECODE(flag, 1, bytes)) bytes,
                       SUM(cnt) rows#,
                       SUM(build_time * 10) build_time,
                       SUM(DECODE(flag, 2, bytes)) dep_bytes,
                       SUM(invalids) invalids,
                       root_name NAME,
                       regexp_replace(listagg(object_no,',') within group(order by object_no),'(\d+)(,\1)+','\1') dep_objs
                FROM   TABLE(GV$(CURSOR (
                                  SELECT /*+leading(c) use_hash(b c)*/
                                  DISTINCT userenv('instance') inst_id,
                                           DECODE(a.id, c.id, 1, NULL, 1, 2) flag,
                                           MAX(regexp_substr(DECODE(a.id, c.id, c.name, NULL, c.name), '[^#]+')) OVER(PARTITION BY nvl(a.id, c.id)) root_name,
                                           ROW_COUNT cnt,
                                           block_count*(select value from v$result_cache_statistics where name='Block Size (Bytes)' and rownum<2) bytes,
                                           c.scan_count + c.pin_count scans,
                                           build_time,
                                           invalidations invalids,
                                           NULLIF(c.object_no,0) object_no
                                  FROM   (SELECT result_id ID, depend_id
                                          FROM   v$result_cache_dependency
                                          UNION
                                          SELECT result_id, result_id
                                          FROM   v$result_cache_dependency) a,
                                         v$result_cache_objects c
                                  WHERE  a.depend_id(+) = c.id
                                  AND    userenv('instance')=nvl(:instance,userenv('instance')))))
                WHERE  root_name IS NOT NULL
                GROUP  BY root_name
                ORDER  BY scans DESC, invalids DESC)
        WHERE  ROWNUM <= 50;
END;
/

grid {'c1','|','c2','-','c3'}