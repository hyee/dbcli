/*[[Show locked objects in gv$locked_object
   --[[
    @CHECK_ACCESS: dba_objects={dba_objects},all_objects={all_objects}
   --]]
]]*/

set feed off
WITH b AS
 (SELECT /*+use_hash(l) no_expand materialize*/l.*
  FROM   v$lock_type t, gv$lock l
  WHERE  t.type = l.type
  AND    (t.id1_tag LIKE 'object%' and id1>0))
SELECT /*+ordered*/
         c.inst_id,
         c.sid,
         d.type,
         d.lmode || ' [' ||
         decode(d.lmode, 0, 'None', 1, 'Null', 2, 'Row-S(SS)', 3, 'Row-X(SX)', 4, 'Share', 5, 'S/Row-X(SSX)',
                6, 'Exclusive', 'Invalid') || ']' lock_mode,
         decode(d.REQUEST, 0, 'Hold', 'Request') ltype,
         NULLIF(BLOCKING_SESSION || ',@' || BLOCKING_INSTANCE, ',@') BLOCKER,
         d.id1 object_id,
         b.owner,
         b.object_name table_name,
         b.subobject_name sub_name,
         round(d.ctime / 60, 1) Mins,
         c.SQL_ID,
         c.event,
         c.PROGRAM,
         c.MODULE,
         c.osuser,
         c.machine
FROM   b d,
       gv$session c,
       XMLTABLE('/ROWSET/ROW' passing(dbms_xmlgen.getxmltype('select owner,object_name,subobject_name from &CHECK_ACCESS where object_id=' || d.id1)) columns 
                owner VARCHAR2(128),
                object_name VARCHAR2(128), 
                subobject_name VARCHAR2(128)) b
WHERE  d.inst_id = c.inst_id
AND    d.sid = c.sid
ORDER  BY owner, table_name,sub_name,1,2;


