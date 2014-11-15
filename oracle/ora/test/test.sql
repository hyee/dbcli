--test.sql
/*[[
            Hello, here is an example ora command. Usage: ora test
            OK, this is the second line.
   --[[
       this part belongs to the template definition
   --]]
]]*/


var cur cursor Printing matched items from all_objects
def rn=3

exec open :cur for select * from all_objects where object_name like upper(:V1);

PRO Printing matched items from all_views:
PRO ======================================
select * from all_views where view_name like upper(:V1) and rownum <= &rn;