/*[[Find locked objects in gv$locked_object
   --[[
    @CHECK_ACCESS: dba_objects={dba_objects},all_objects={all_objects}
   --]]
]]*/

set feed off
WITH a as(SELECT /*+materialize*/ * from gv$locked_object),
     b as(SELECT /*+materialize*/ * FROM gv$lock where (inst_id,sid,id1) in(select inst_id,session_id,object_id from a))
SELECT /*+ordered*/ c.inst_id,
       c.sid,
       d.type,
       a.locked_mode||' ['||decode(a.locked_mode,
                0, 'None',           /* Mon Lock equivalent */
                1, 'Null',           /* N */
                2, 'Row-S(SS)',     /* L */
                3, 'Row-X(SX)',     /* R */
                4, 'Share',          /* S */
                5, 'S/Row-X(SSX)',  /* C */
                6, 'Exclusive',      /* X */
                'Invalid')||']' lmode,
       decode(d.REQUEST,0,'Request','Hold') ltype,  
       NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCK_BY,
       a.object_id,
       b.owner,
       b.object_name table_name,
       b.subobject_name sub_name,
       round(d.ctime/60,1) Mins,
       c.SQL_ID,
       c.event,
       c.PROGRAM,
       c.MODULE,
       c.osuser,
       c.machine       
FROM   a, b d, gv$session c,
       XMLTABLE('/ROWSET/ROW'
            passing(dbms_xmlgen.getxmltype('select owner,object_name,subobject_name from &CHECK_ACCESS where object_id='||a.object_id))
            columns 
                owner             varchar2(30)
               ,object_name       varchar2(30)
               ,subobject_name    varchar2(30)
             ) b
WHERE  a.inst_id = c.inst_id
AND    a.session_id = c.sid
AND    a.inst_id = d.inst_id
AND    a.session_id = d.sid
AND    a.object_id=d.id1
order by 1,2;

