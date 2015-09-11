/*[[Show data in gv$open_cursor, usage: cursor [[-s] <sid>|-o <object_name>
    --[[
        &V9: {s={SID=REGEXP_SUBSTR(:V1,'^\d+$')},
              o={EXISTS(
                  SELECT 1 from  gv$object_dependency b
                  WHERE  a.inst_id=b.inst_id AND a.address = b.from_address
                  AND    a.hash_value = b.from_hash
                  AND    nvl(to_owner, '0') NOT IN ('0', 'SYS')
                  AND    to_type NOT IN (0, 5, 55)
                  AND    to_name=upper(:V1)) }
             }
        &V10: s={}, o={(select event from gv$session where inst_id=a.inst_id and sid=a.sid) event,}
    ]]--
]]*/
SELECT distinct a.INST_ID,
       SID,&V10
       SQL_ID,
       trim(SQL_TEXT) SQL_TEXT,
       (SELECT (last_active_time)
        FROM   gv$sqlarea
        WHERE  sql_id = a.sql_id
        AND    inst_id = a.inst_id) last_active,
       (select to_char(wmsys.wm_concat(DISTINCT to_name))
        from  gv$object_dependency b
        WHERE a.inst_id=b.inst_id
        AND    a.address = b.from_address
        AND    a.hash_value = b.from_hash
        --AND    nvl(to_owner, '0') NOT IN ('0', 'SYS')
        AND    to_type NOT IN (0, 5, 55)) OBJECTS
FROM   gv$open_cursor a
WHERE  a.user_name NOT IN ('SYS') and &V9
ORDER  BY 1,2,last_active
