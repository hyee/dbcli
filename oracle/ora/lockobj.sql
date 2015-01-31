/*[[Find locked objects in gv$locked_object]]*/

set feed off

SELECT /*+ordered*/ c.inst_id,
       c.sid,
       a.locked_mode||' ['||decode(a.locked_mode,
                0, 'None',           /* Mon Lock equivalent */
                1, 'Null',           /* N */
                2, 'Row-S(SS)',     /* L */
                3, 'Row-X(SX)',     /* R */
                4, 'Share',          /* S */
                5, 'S/Row-X(SSX)',  /* C */
                6, 'Exclusive',      /* X */
                'Invalid')||']' lmode,
       decode(XIDSQN,0,'Request','Hold') ltype,         
       a.object_id,
       b.owner,
       b.object_name table_name,
       b.subobject_name sub_name,
       c.SQL_ID,
       c.event,
       c.PROGRAM,
       c.MODULE,
       c.osuser,
       c.machine       
FROM   gv$locked_object a,  gv$session c,
       XMLTABLE('/ROWSET/ROW'
            passing(dbms_xmlgen.getxmltype('select owner,object_name,subobject_name from all_objects where object_id='||a.object_id))
            columns 
                owner             varchar2(30)
               ,object_name       varchar2(30)
               ,subobject_name    varchar2(30)
             ) b
WHERE  a.inst_id = c.inst_id
AND    a.session_id = c.sid
order by 1,2;

