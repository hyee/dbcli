/*[[Show locked objects in gv$locked_object whose lock_type.id1_tag LIKE 'object%'. Usage: @@NAME [-f"<filter>"]
   --[[
    @CHECK_ACCESS: dba_objects={dba_objects},all_objects={all_objects}
    &FILTER: default={1=1} f={}
   --]]
]]*/

set feed off
WITH b AS
 (SELECT /*+use_hash(l t) opt_param('optimizer_dynamic_sampling' 5) 
           no_expand materialize 
           table_stats(SYS.X$KSQRS set rows=1000000) 
           table_stats(SYS.X$KSUSE set rows=100000)
        */
         l.*,nvl2(s.sid,s.sid||'@'||s.inst_id,'') blocking,s.event e2
  FROM   v$lock_type t 
  JOIN   gv$lock l 
  ON     l.type=t.type AND l.id1>0
  LEFT  JOIN gv$session_wait s
  ON     l.id1=s.p2 AND l.id2=s.p3 AND t.id1_tag=s.p2text AND t.id2_tag=s.p3text
  AND    l.request=0
  WHERE (t.id1_tag LIKE 'obj%' or s.sid is not null)),
objs AS (
  SELECT id1,b.*
  FROM   (select /*+no_merge*/ distinct id1 from b) d,
         XMLTABLE('/ROWSET/ROW' 
                passing(dbms_xmlgen.getxmltype('select owner,object_name,subobject_name from &CHECK_ACCESS where object_id=' || d.id1)) 
                columns owner VARCHAR2(128),
                        object_name VARCHAR2(128), 
                        subobject_name VARCHAR2(128)) b
)
SELECT /*+leading(b d) outline_leaf*/
         distinct 
         c.sid||','||c.serial#||',@'||c.inst_id session#,
         d.type,
         d.lmode || ' [' ||
         decode(d.lmode, 0, 'None', 1, 'Null', 2, 'Row-S(SS)', 3, 'Row-X(SX)', 4, 'Share', 5, 'S/Row-X(SSX)',
                6, 'Exclusive', 'Invalid') || ']' lock_mode,
         decode(d.REQUEST, 0, 'Hold', 'Request') ltype,
         NULLIF(BLOCKING_SESSION || ',@' || BLOCKING_INSTANCE, ',@') BLOCKER,
         blocking,
         --d.id1 id,
         b.owner,
         b.object_name table_name,
         nvl(nullif(greatest(2,count(distinct b.subobject_name) over(partition by b.owner,b.object_name,c.sid,c.inst_id))|| ' Segments','2 Segments'),b.subobject_name) sub_name,
         round(max(d.ctime) over(partition by b.owner,b.object_name,c.sid,c.inst_id)/ 60, 1) Mins,
         c.SQL_ID,
         nvl(e2,c.event) event,
         c.PROGRAM,
         c.MODULE,
         c.osuser,
         c.machine
FROM   b d,
       objs b,
       gv$session c
WHERE  d.inst_id = c.inst_id
AND    d.id1=b.id1
AND    d.sid = c.sid AND (&filter)
ORDER  BY owner, table_name,sub_name,type,nvl2(blocking,2,0)+nvl2(blocker,0,1),1;


