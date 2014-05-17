/*[[To find the open cursors that refer to target object. Usage: ora objcursor <object_name>]]*/
SELECT *
FROM   (SELECT /*+ordered use_hash(a b)*/
         a.inst_id,
         a.sid,
         a.user_name,
         a.sql_id,
         a.hash_value,
         a.sql_text,
         to_char(wmsys.wm_concat(DISTINCT to_name)) objs
        FROM   gv$open_cursor a, gv$object_dependency b
        WHERE  a.inst_id = b.inst_id
        AND    a.address = b.from_address
        AND    a.hash_value = b.from_hash
        AND    nvl(to_owner, '0') NOT IN ('0', 'SYS')
        AND    a.user_name NOT IN ('SYS')
        AND    to_type NOT IN (0, 5, 55) --exclude cursor/synonom/xdb
        GROUP  BY a.inst_id, a.sid, a.sql_id, a.hash_value, a.user_name, a.sql_text)
WHERE  :V1 IS NULL
OR     instr(upper(objs || CHR(1) || sql_text || CHR(1) || sid || CHR(1) || user_name),
             upper(:V1)) > 0
