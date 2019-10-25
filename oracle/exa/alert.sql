/*[[Show cell alerts]]*/
select BEGIN_TIME,SEQ_NO SEQ,SEVERITY,
       (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
	   replace(trim('"' from MESSAGE),'<exadata:br/>',chr(10)) message,STATEFUL
from   V$CELL_OPEN_ALERTS a
order by begin_time desc;