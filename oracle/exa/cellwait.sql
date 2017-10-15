/*[[Show session waits associated to cell nodes]]*/
SELECT w.sid||',@'||w.inst_id session#, w.event, 
       extractvalue(xmltype(c.CONFVAL),'/cli-output/context/@cell') cell, 
       d.name asm_disk,P2, w.p3||' '||e.PARAMETER3 P3, w.sql_id
FROM   GV$SESSION w, V$ASM_DISK d, V$CELL_CONFIG c,v$event_name e
WHERE  e.PARAMETER1 ='cellhash#'
AND    w.p1 = c.cellhash
and    c.CONFTYPE='CELL'
and    w.event=e.name
AND    w.p2 = d.hash_value(+)
AND    d.hash_value(+)>0;
