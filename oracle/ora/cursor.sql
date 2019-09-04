/*[[Show data in gv$open_cursor, usage: @@NAME {<sid> [inst] | -o <object_name>}
    --[[
        &V1: default={userenv('sid')}
        &V2: default={nvl(:instance,userenv('instance'))}
        &V9: {s={a.sid=REGEXP_SUBSTR(&V1,'^\d+$')},
              o={b.to_name=upper(:V1)}
             }
        &V10: s={}, o={(select event from v$session where sid=a.sid) event,}
        @aggs: 11.2={regexp_replace(listagg(to_name,',') within group(order by to_name),'([^,]+)(,\1)+','\1')},default={to_char(wmsys.wm_concat(DISTINCT to_name))}
    ]]--
]]*/

SELECT DISTINCT * 
FROM TABLE(GV$(CURSOR(
    SELECT /*+use_nl(c)*/
           USERENV('instance') inst_id,
           a.sid,
           &V10
           a.sql_id,
           TRIM(a.sql_text) || CASE
               WHEN a.sql_text LIKE 'table_%' AND regexp_like(regexp_substr(a.sql_text, '[^\_]+', 1, 4), '^[0-9A-Fa-f]+$') THEN
                ' (obj# ' || to_number(regexp_substr(a.sql_text, '[^\_]+', 1, 4), 'xxxxxxxxxx') || ')'
           END SQL_TEXT,
           MAX(c.last_active_time) last_active,
           &aggs objs
    FROM   v$open_cursor a, v$object_dependency b, v$sqlstats c
    WHERE  userenv('instance')=&V2
    AND    &V9
    AND    a.address = b.from_address(+)
    AND    a.hash_value = b.from_hash(+)
    AND    b.to_type(+) NOT IN (0, 5, 55)
    AND    a.sql_id = c.sql_id(+)
    GROUP  BY a.sid, a.sql_id, a.sql_text)))
ORDER  BY 1,2,last_active nulls last;