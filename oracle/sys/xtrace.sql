/*[[Show info in x$trace of a specific sid. Usage: @@NAME {<sid> [inst_id]}
  --[[
    @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
    &V2: default={&instance}
  --]]
]]*/
SELECT *
FROM   (SELECT *
        FROM   &gv
                  SELECT /*+no_expand*/
                   CASE
                       WHEN (SELECT 0 + regexp_substr(version, '^\d+') FROM v$instance) < 11 THEN
                        to_char(time/1000000)
                       ELSE
                        to_char(systimestamp+numtodsinterval(TIME / 1000000,'second'),'yyyy-mm-dd hh24:mi:ssxff6')
                   END time,
                   inst_id,
                   sid,
                   component,function,
                   event,
                   file_loc,
                   CASE event
                       WHEN 10812 THEN
                        'rfile=' ||
                        RPAD(DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(TO_NUMBER(SUBSTR(REPLACE(data, '0x', ''), 7, 2) ||
                                                                            SUBSTR(REPLACE(data, '0x', ''), 5, 2) ||
                                                                            SUBSTR(REPLACE(data, '0x', ''), 3, 2) ||
                                                                            SUBSTR(REPLACE(data, '0x', ''), 1, 2),
                                                                            'XXXXXXXX')),
                             4) || ' block=' ||
                        RPAD(DBMS_UTILITY.DATA_BLOCK_ADDRESS_BLOCK(TO_NUMBER(SUBSTR(REPLACE(data, '0x', ''), 7, 2) ||
                                                                             SUBSTR(REPLACE(data, '0x', ''), 5, 2) ||
                                                                             SUBSTR(REPLACE(data, '0x', ''), 3, 2) ||
                                                                             SUBSTR(REPLACE(data, '0x', ''), 1, 2),
                                                                             'XXXXXXXX')),
                             8) || ' cr_scn=' || TO_CHAR(TO_NUMBER(SUBSTR(REPLACE(data, '0x', ''), 41, 2) ||
                                                                   SUBSTR(REPLACE(data, '0x', ''), 39, 2) ||
                                                                   SUBSTR(REPLACE(data, '0x', ''), 37, 2) ||
                                                                   SUBSTR(REPLACE(data, '0x', ''), 35, 2),
                                                                   'XXXXXXXX'))
                       ELSE
                        replace(data,chr(10))
                   END AS xtrace_data
                  FROM   x$trace a
                  WHERE  sid = nvl(0 + :V1, userenv('sid'))
                  AND    inst_id = nvl(:V2, inst_id)
        ))) a
ORDER  BY a.time DESC)
WHERE  ROWNUM <= 300
ORDER  BY TIME;
