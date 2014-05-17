/*[[Show excution plan of previous execution. Usage: cursor mode
  Mode:
     &V1:1={}, 2={ -PROJECTION +ALLSTATS}
]]*/

SELECT * FROM table(dbms_xplan.display_cursor(null,null,'ALL&V1'))