/*[[Show data in gv$open_cursor, usage: cursor [[-s] <sid> [inst]|-o <object_name>
    --[[
        
        &V9: {s={SID=REGEXP_SUBSTR(:V1,'^\d+$') AND (:V2 IS NULL OR INST_ID=:V2)},
              o={EXISTS(
                  SELECT 1 from  gv$object_dependency b
                  WHERE  a.inst_id=b.inst_id AND a.address = b.from_address
                  AND    a.hash_value = b.from_hash
                  AND    nvl(to_owner, '0') NOT IN ('0', 'SYS')
                  AND    to_type NOT IN (0, 5, 55)
                  AND    to_name=upper(:V1)) }
             }
        &V10: s={}, o={(select event from gv$session where inst_id=a.inst_id and sid=a.sid) event,}
        @aggs: 11.2={regexp_replace(listagg(to_name,'','') within group(order by to_name),''([^,]+)(,\1)+'',''\1'')},default={to_char(wmsys.wm_concat(DISTINCT to_name))}
    ]]--
]]*/
SELECT distinct a.INST_ID,
       SID,&V10
       SQL_ID,
       trim(SQL_TEXT) SQL_TEXT,
       extractvalue(c.column_value,'/ROW/LAST_ACTIVE')  last_active,
       extractvalue(b.column_value,'/ROW/OBJS')  OBJECTS
FROM   gv$open_cursor a, 
       TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype('
           select &aggs objs
            from  gv$object_dependency b
            WHERE  '||a.inst_id||'=b.inst_id AND hextoraw('''||a.address||''') = b.from_address
            AND    '||a.hash_value||' = b.from_hash
            AND    to_type NOT IN (0, 5, 55)
            AND    rownum<130'),'/ROWSET/ROW')))(+) b, 
       TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype('
           SELECT TO_CHAR(last_active_time,''yyyy-mm-dd hh24:mi:ss'') last_active
            FROM   gv$sqlstats
            WHERE  sql_id = '''||a.sql_id||'''
            AND    inst_id = '||a.inst_id),'/ROWSET/ROW')))(+) c
WHERE  a.user_name NOT IN ('SYS') and &V9
ORDER  BY 1,2,last_active nulls last
