/*[[
    Show FlashLogging stats. Usage: @@NAME [<cell>] [-cli]
    -cli: Show the info of EXA$FLASHLOG instead of fetching info from V$CELL_STATE
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_state={1} EXA$FLASHLOG={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/

set sep4k on verify off feed off
col size,effectiveSize format kmg
col num_bytes_written format kmg
var c1 refcursor
var c2 refcursor "Flash Log Stats"
DECLARE
    c1 SYS_REFCURSOR;
    c2 SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
    lst VARCHAR2(32767);
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        SELECT listagg('''' || c || '''', ',') within GROUP(ORDER BY c)
        INTO   lst
        FROM   (SELECT extractvalue(XMLTYPE(a.statistics_value), '/flashlogstore_stats/stat[@name="celldisk"]') c
                FROM   v$cell_state a
                WHERE  statistics_type = 'FLASHLOG'
                AND    instr(a.statistics_value, '<flashlogstore_stats') > 0)
        WHERE lower(c) LIKE lower('%'||V1||'%');
        lst := regexp_replace(lst,'''(.+?)''','''\1'' as "\1"');
        OPEN c1 FOR replace(replace(q'~
            SELECT *
            FROM   (SELECT extractvalue(XMLTYPE(a.statistics_value), '/flashlogstore_stats/stat[@name="celldisk"]') c, b.*
                    FROM   v$cell_state a,
                           XMLTABLE('/flashlogstore_stats/stat[@name!="celldisk"]' PASSING XMLTYPE(a.statistics_value) COLUMNS --
                                    stats VARCHAR2(100) path '@name',
                                    VALUE VARCHAR2(@siz) path '.') b
                    WHERE  statistics_type = 'FLASHLOG')
            PIVOT(max(value) for c in(@lst))
            ORDER BY 1~','@lst',lst),'@siz',CASE WHEN V1 IS NOT NULL THEN 100 ELSE 18 END);

        SELECT listagg('''' || c || '''', ',') within GROUP(ORDER BY c)
        INTO   lst
        FROM (select DISTINCT extractvalue(xmltype(confval),'/cli-output/context/@cell') c from v$cell_config)
        WHERE lower(c) LIKE lower('%'||V1||'%');
        lst := regexp_replace(lst,'''(.+?)''','''\1'' as "\1"');
        
        OPEN c2 FOR replace(q'~
            SELECT * FROM(
                SELECT (select extractvalue(xmltype(c.confval),'/cli-output/context/@cell') from v$cell_config c where c.CELLNAME=a.CELL_NAME and rownum<2) c,b.*
                FROM v$cell_state  a,
                     XMLTABLE('/flashlog_stats/stat' PASSING XMLTYPE(a.statistics_value) COLUMNS --
                       stats  VARCHAR2(100) path '@name',
                       VALUE VARCHAR2(30) path '.') b
                WHERE statistics_type='FLASHLOG')
            PIVOT(max(value) for c in(@lst))
            ORDER BY 1~','@lst',lst);
    $ELSE
        OPEN C1 for 
            SELECT CELLNODE,NAME,"status","size","effectiveSize","efficiency","degradedCelldisks","creationTime","id","cellDisk" 
            FROM  EXA$FLASHLOG
            WHERE lower(cellnode) like lower('%'||V1||'%')
            ORDER BY 1,2;
    $END
    :c1 := c1;
    :c2 := c2;
END;
/
print c1
print c2