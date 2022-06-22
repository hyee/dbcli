/*[[Show data in gv$open_cursor, usage: @@NAME {<sid> [inst]} | {-o <object_name>}
    --[[
        &V2: default={nvl(:instance,userenv('instance'))}
        &V9: {s={a.sid=nvl(REGEXP_SUBSTR(:V1,'^\d+$'),userenv('sid'))},
              o={b.to_name=upper(:V1)}
             }
        &V10: s={}, o={(select event from v$session where sid=a.sid) event,}
        @type: 11.2={cursor_type} default={' '}
        @overflow: 19.1={distinct to_name,',' on overflow truncate} default={to_name,','}
        @aggs: 12.2={regexp_replace(listagg(&overflow) within group(order by to_name),'([^,]+)(,\1)+','\1')},default={to_char(wmsys.wm_concat(DISTINCT to_name))}
    ]]--
]]*/

SELECT DISTINCT * 
FROM TABLE(GV$(CURSOR(
    SELECT /*+use_nl(c) use_nl(a b)*/
           USERENV('instance') inst_id,
           a.sid,
           &V10
           a.sql_id,
           TRIM(a.sql_text) || CASE
               WHEN a.sql_text LIKE 'table_%' AND regexp_like(regexp_substr(a.sql_text, '[^\_]+', 1, 4), '^[0-9A-Fa-f]+$') THEN
                ' (obj# ' || to_number(regexp_substr(a.sql_text, '[^\_]+', 1, 4), 'xxxxxxxxxx') || ')'
           END SQL_TEXT,
           &type cursor_type,
           &aggs objs
    FROM   v$open_cursor a, v$object_dependency b
    WHERE  userenv('instance')=&V2
    AND    &V9
    AND    a.address = b.from_address(+)
    AND    a.hash_value = b.from_hash(+)
    AND    b.to_type(+) NOT IN (0, 5, 55)
    GROUP  BY a.sid, a.sql_id, a.sql_text,&type)))
ORDER  BY 1,2,instr(cursor_type,'OPEN') ;